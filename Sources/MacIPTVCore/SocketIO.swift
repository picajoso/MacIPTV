import Foundation
import Network

/// Bounded socket operations. Cancellation closes the socket and resumes I/O.
enum SocketIO {
    static func ready(_ connection: NWConnection, queue: DispatchQueue, timeout: Double = 8) async throws {
        let deadline = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); if !Task.isCancelled { connection.cancel() } }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: connection.stateUpdateHandler = nil; continuation.resume()
                    case .failed(let error): connection.stateUpdateHandler = nil; continuation.resume(throwing: error)
                    case .cancelled: connection.stateUpdateHandler = nil; continuation.resume(throwing: CancellationError())
                    default: break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: { connection.cancel() }
    }
    static func receive(_ connection: NWConnection, maximum: Int = 16384, timeout: Double = 15) async throws -> Data {
        let deadline = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); if !Task.isCancelled { connection.cancel() } }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data ?? Data()) }
                }
            }
        } onCancel: { connection.cancel() }
    }
    static func exactly(_ count: Int, from connection: NWConnection) async throws -> [UInt8] {
        var data = Data()
        while data.count < count {
            let next = try await receive(connection, maximum: count - data.count, timeout: 5)
            guard !next.isEmpty else { throw URLError(.networkConnectionLost) }
            data.append(next)
        }
        return Array(data)
    }
    static func send(_ data: Data, to connection: NWConnection, timeout: Double = 15) async throws {
        let deadline = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); if !Task.isCancelled { connection.cancel() } }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        } onCancel: { connection.cancel() }
    }
}
