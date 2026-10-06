import Foundation
import Network
import Darwin

/// Authenticated loopback SOCKS5 gateway. TLS remains end-to-end in URLSession.
/// Resolves once and connects to that numeric IP: no DNS check/connect race.
actor NetworkGateway {
    private let policy: NetworkPolicy
    private let username = UUID().uuidString
    private let password = UUID().uuidString
    private let queue = DispatchQueue(label: "MacIPTV.NetworkGateway")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var remoteConnections: [UUID: NWConnection] = [:]
    init(policy: NetworkPolicy) { self.policy = policy }

    func start() async throws -> ProxyConfiguration {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { if let self { await self.serve(connection) } else { connection.cancel() } }
        }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port { continuation.resume(returning: port) }
                    else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                case .cancelled: listener.stateUpdateHandler = nil; continuation.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard self.listener === listener, !Task.isCancelled else { throw CancellationError() }
        var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
        proxy.allowFailover = false
        proxy.applyCredential(username: username, password: password)
        return proxy
    }
    func stop() {
        listener?.cancel(); listener = nil
        // Include sockets still connecting. Do this synchronously on the actor,
        // before returning, rather than waiting for a local pump to observe EOF.
        remoteConnections.values.forEach { $0.cancel() }; remoteConnections.removeAll()
        connections.values.forEach { $0.cancel() }; connections.removeAll()
    }
    private func serve(_ client: NWConnection) async {
        guard listener != nil, connections.count < 16 else { client.cancel(); return }
        let id = UUID(); connections[id] = client
        client.start(queue: queue)
        var upstream: NWConnection?
        let handshakeDeadline = Task { try? await Task.sleep(nanoseconds: 10_000_000_000); if !Task.isCancelled { client.cancel() } }
        defer {
            handshakeDeadline.cancel(); client.cancel(); upstream?.cancel()
            remoteConnections.removeValue(forKey: id)?.cancel()
            connections.removeValue(forKey: id)
        }
        do {
            let greeting = try await SocketIO.exactly(2, from: client)
            guard greeting[0] == 5, greeting[1] > 0 else { return }
            let methods = try await SocketIO.exactly(Int(greeting[1]), from: client)
            guard methods.contains(2) else { try await SocketIO.send(Data([5, 255]), to: client); return }
            try await SocketIO.send(Data([5, 2]), to: client)
            let auth = try await SocketIO.exactly(2, from: client)
            guard auth[0] == 1 else { return }
            let user = try await SocketIO.exactly(Int(auth[1]), from: client)
            let passwordLength = try await SocketIO.exactly(1, from: client)[0]
            let pass = try await SocketIO.exactly(Int(passwordLength), from: client)
            guard user == Array(username.utf8), pass == Array(password.utf8) else {
                try await SocketIO.send(Data([1, 1]), to: client); return
            }
            try await SocketIO.send(Data([1, 0]), to: client)
            let request = try await SocketIO.exactly(4, from: client)
            guard request[0] == 5, request[1] == 1, request[2] == 0 else { return }
            let host: String
            switch request[3] {
            case 1: host = try await SocketIO.exactly(4, from: client).map(String.init).joined(separator: ".")
            case 3:
                let length = try await SocketIO.exactly(1, from: client)[0]
                guard length > 0 else { return }
                let bytes = try await SocketIO.exactly(Int(length), from: client)
                guard let value = String(bytes: bytes, encoding: .utf8), !value.contains("\0") else { return }
                host = NetworkPolicy.canonicalHost(value)
            case 4:
                let bytes = try await SocketIO.exactly(16, from: client)
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard bytes.withUnsafeBytes({ inet_ntop(AF_INET6, $0.baseAddress, &buffer, socklen_t(buffer.count)) }) != nil else { return }
                host = String(cString: buffer)
            default: return
            }
            let portBytes = try await SocketIO.exactly(2, from: client)
            let port = UInt16(portBytes[0]) * 256 + UInt16(portBytes[1])
            guard port > 0 else { return }
            // One monotonic budget for DNS plus all validated-IP attempts.
            // A late DNS result cannot restart the connection budget.
            let connectDeadline = ProcessInfo.processInfo.systemUptime + 8
            let addresses = try await Self.resolve(host)
            let checked = try policy.checkedAddresses(addresses, host: host, port: port)
            guard listener != nil, connections[id] === client, !Task.isCancelled else { return }
            let remote = try await connect(checked, port: port, client: client, id: id, deadline: connectDeadline)
            upstream = remote
            try await SocketIO.send(Data([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]), to: client)
            handshakeDeadline.cancel()
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await Self.pump(client, remote) }
                group.addTask { try await Self.pump(remote, client) }
                _ = try await group.next()
                group.cancelAll(); client.cancel(); remote.cancel()
            }
        } catch { /* No provider URLs or proxy credentials are logged. */ }
    }
    private func connect(_ addresses: [String], port: UInt16, client: NWConnection,
                         id: UUID, deadline: Double) async throws -> NWConnection {
        var lastError: Error = URLError(.cannotConnectToHost)
        for (index, address) in addresses.enumerated() {
            try Task.checkCancellation()
            guard listener != nil, connections[id] === client else { throw CancellationError() }
            switch client.state {
            case .cancelled, .failed: throw CancellationError()
            default: break
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw URLError(.timedOut) }
            // Reserve time for later addresses, e.g. reachable IPv4 after an
            // unreachable IPv6 route. No attempt re-resolves the hostname.
            let attemptTimeout = min(3, remaining / Double(addresses.count - index))
            let remote = NWConnection(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            remoteConnections[id] = remote
            do {
                try await SocketIO.ready(remote, queue: queue, timeout: attemptTimeout)
                try Task.checkCancellation()
                guard listener != nil, connections[id] === client,
                      remoteConnections[id] === remote else { throw CancellationError() }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
                return remote
            } catch {
                remote.cancel()
                if remoteConnections[id] === remote { remoteConnections.removeValue(forKey: id) }
                lastError = error
                // Cancellation of an individual timed-out attempt allows a
                // fallback; cancellation of this request or stop never does.
                try Task.checkCancellation()
                guard listener != nil, connections[id] === client else { throw CancellationError() }
            }
        }
        if ProcessInfo.processInfo.systemUptime >= deadline { throw URLError(.timedOut) }
        throw lastError
    }
    private static func pump(_ from: NWConnection, _ to: NWConnection) async throws {
        while !Task.isCancelled {
            let data = try await SocketIO.receive(from, timeout: 30)
            if data.isEmpty { return }
            // Response budgets are enforced by SecureHTTPClient. A persistent
            // HTTP/TLS tunnel may carry arbitrarily many individually bounded responses.
            try await SocketIO.send(data, to: to)
        }
    }
    static func resolve(_ host: String) async throws -> [String] {
        if NetworkPolicy.isNumericAddress(host) { return [host] }
        return try await DNSResolver.shared.resolve(host)
    }
    static func lookup(_ host: String) throws -> [String] {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { throw URLError(.cannotFindHost) }
            defer { freeaddrinfo(first) }
            var addresses: [String] = []; var node: UnsafeMutablePointer<addrinfo>? = first
            while let current = node {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: buffer)
                    if !addresses.contains(address) { addresses.append(address) }
                }
                node = current.pointee.ai_next
            }
            return addresses
    }
}
