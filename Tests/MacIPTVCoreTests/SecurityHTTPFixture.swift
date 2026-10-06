@testable import MacIPTVCore

import Foundation
import Network

actor SecurityHTTPFixture {
    enum Reply { case body(Data), chunked(Data), redirect(URL), delayed(Data) }
    private let queue = DispatchQueue(label: "MacIPTV.SecurityHTTPFixture")
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var reply: Reply = .body(Data("fixture".utf8))
    private(set) var requests = 0
    func configure(_ reply: Reply) { self.reply = reply }
    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters); self.listener = listener
        listener.newConnectionHandler = { connection in Task { await self.serve(connection) } }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://127.0.0.1:\(port)/fixture")!
    }
    func stop() { listener?.cancel(); listener = nil; clients.values.forEach { $0.cancel() }; clients.removeAll() }
    private func serve(_ connection: NWConnection) async {
        let id = UUID(); clients[id] = connection
        connection.start(queue: queue)
        defer { connection.cancel(); clients.removeValue(forKey: id) }
        do {
            var header = Data()
            while header.range(of: Data("\r\n\r\n".utf8)) == nil {
                let data = try await SocketIO.receive(connection, timeout: 3)
                guard !data.isEmpty, header.count + data.count <= 8192 else { return }
                header.append(data)
            }
            requests += 1
            switch reply {
            case .delayed(let data):
                try await Task.sleep(nanoseconds: 5_000_000_000)
                var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(data); try await SocketIO.send(response, to: connection)
            case .body(let data):
                var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(data); try await SocketIO.send(response, to: connection)
            case .chunked(let data):
                try await SocketIO.send(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".utf8), to: connection)
                for start in stride(from: 0, to: data.count, by: 1024) {
                    let chunk = data.subdata(in: start..<min(start + 1024, data.count))
                    var packet = Data("\(String(chunk.count, radix: 16))\r\n".utf8); packet.append(chunk); packet.append(Data("\r\n".utf8))
                    try await SocketIO.send(packet, to: connection)
                }
                try await SocketIO.send(Data("0\r\n\r\n".utf8), to: connection)
            case .redirect(let url):
                try await SocketIO.send(Data("HTTP/1.1 302 Found\r\nLocation: \(url.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
            }
        } catch { }
    }
}
