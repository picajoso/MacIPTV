import Foundation
import Network

/// Loopback-only HLS adapter. No Python, external service, credential files or
/// additional live session: one provider session is opened and reused.
public actor HLSRelay {
    private var listener: NWListener?
    private var client: SecureHTTPClient?
    private let policy: NetworkPolicy
    private let onHTTPConsentRequired: (@Sendable () async -> Void)?
    private var registry = HLSRelayRegistry()
    private var localBase: URL?
    private var connections: [UUID: NWConnection] = [:]
    private var downloads: [UUID: Task<HTTPResult, Error>] = [:]
    private let nonce = UUID().uuidString
    private let queue = DispatchQueue(label: "MacIPTV.HLSRelay")
    public init(policy: NetworkPolicy = NetworkPolicy(), onHTTPConsentRequired: (@Sendable () async -> Void)? = nil) {
        self.policy = policy; self.onHTTPConsentRequired = onHTTPConsentRequired
    }

    public func start(upstream: URL) async throws -> URL {
        try policy.validate(upstream)
        client = SecureHTTPClient(policy: policy, timeout: 15)
        registry.setRoot(upstream)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.serve(connection) }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port?.rawValue { continuation.resume(returning: port) }
                    else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard self.listener === listener, !Task.isCancelled else { throw CancellationError() }
        let base = URL(string: "http://127.0.0.1:\(port)/\(nonce)/")!
        localBase = base
        return base.appendingPathComponent("root")
    }

    public func stop() async {
        listener?.cancel(); listener = nil
        let previous = client
        client = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        downloads.values.forEach { $0.cancel() }; downloads.removeAll()
        registry = HLSRelayRegistry(); localBase = nil
        await previous?.stop()
    }

    private func serve(_ connection: NWConnection) async {
        guard listener != nil, connections.count < 12 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: queue)
        let headerDeadline = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if !Task.isCancelled { connection.cancel() } }
        let requestDeadline = Task { try? await Task.sleep(nanoseconds: 75_000_000_000); if !Task.isCancelled { connection.cancel() } }
        defer { headerDeadline.cancel(); requestDeadline.cancel(); downloads.removeValue(forKey: id)?.cancel(); connections.removeValue(forKey: id); connection.cancel() }
        do {
            var header = Data()
            while header.range(of: Data("\r\n\r\n".utf8)) == nil {
                guard header.count < 16_384 else { try await respond(connection, status: 431); return }
                let part = try await receive(connection)
                guard !part.isEmpty else { return }
                guard header.count + part.count <= 16_384 else { try await respond(connection, status: 431); return }
                header.append(part)
            }
            headerDeadline.cancel()
            let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
            let first = lines.first?.split(separator: " ") ?? []
            guard first.count == 3, ["GET", "HEAD"].contains(String(first[0])) else {
                try await respond(connection, status: 405); return
            }
            let path = String(first[1]).components(separatedBy: "/")
            guard path.count == 3, path[1] == nonce, let upstream = registry.destination(for: path[2]),
                  let client, let base = localBase else {
                try await respond(connection, status: 404); return
            }
            let kind = registry.kind(for: path[2])
            var request = URLRequest(url: upstream, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue(PlaybackPolicy.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if kind != .playlist, let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }) {
                let value = rangeLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if value.range(of: "^bytes=[0-9]+-[0-9]*$", options: .regularExpression) != nil {
                    request.setValue(value, forHTTPHeaderField: "Range")
                }
            }
            let started = ProcessInfo.processInfo.systemUptime
            let maximum = kind == .segment ? DownloadLimits.segment : (kind == .key ? DownloadLimits.key : DownloadLimits.manifest)
            let download = Task { try await client.fetch(request, maximumBytes: maximum) }
            downloads[id] = download
            // One request per socket, Connection: close. EOF, failure or further
            // pipelined input abandons this download and releases its slot.
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in download.cancel() }
            let result = try await download.value
            let data = result.data, response = result.response
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            guard (200..<300).contains(response.statusCode) else {
                DiagnosticLog.recordHLS(kind: kind, status: response.statusCode, bytes: data.count, elapsed: elapsed)
                try await respond(connection, status: response.statusCode); return
            }
            guard data.count <= 32 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            var body = data
            var mime = "application/octet-stream"
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") || text.hasPrefix("\u{FEFF}#EXTM3U") {
                let resolved = response.url ?? upstream
                if path[2] == "root" { registry.setRoot(resolved) }
                guard data.count <= DownloadLimits.manifest else { throw IPTVError.downloadTooLarge }
                let rewritten = try registry.rewrite(text, upstream: resolved, localBase: base, playlistID: path[2], policy: policy)
                body = Data(rewritten.utf8); mime = "application/vnd.apple.mpegurl"
                DiagnosticLog.recordHLS(kind: .playlist, status: response.statusCode, bytes: data.count, elapsed: elapsed, manifest: HLSManifestSummary(text))
            } else {
                guard kind != .playlist else { throw IPTVError.security(reason: "El reproductor integrado requiere una lista HLS válida.") }
                if kind == .segment { mime = "video/mp2t" }
                DiagnosticLog.recordHLS(kind: kind, status: response.statusCode, bytes: data.count, elapsed: elapsed)
            }
            var contentRange: String?
            if let value = response.value(forHTTPHeaderField: "Content-Range"),
               value.range(of: "^bytes [0-9]+-[0-9]+/[0-9*]+$", options: .regularExpression) != nil { contentRange = value }
            try await respond(connection, status: response.statusCode, body: body, mime: mime,
                              head: first[0] == "HEAD", contentRange: contentRange)
        } catch {
            if let failure = error as? IPTVError, failure == .httpConsentRequired {
                await onHTTPConsentRequired?()
            }
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                DiagnosticLog.record(.playback, error: error)
            }
            try? await respond(connection, status: 502)
        }
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await SocketIO.receive(connection, maximum: 4096, timeout: 5)
    }
    private func respond(_ connection: NWConnection, status: Int, body: Data = Data(), mime: String = "application/octet-stream", head: Bool = false, contentRange: String? = nil) async throws {
        var header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if let contentRange { header += "Content-Range: \(contentRange)\r\n" }
        try await SocketIO.send(Data((header + "\r\n").utf8), to: connection)
        if !head && !body.isEmpty { try await SocketIO.send(body, to: connection) }
    }
}
