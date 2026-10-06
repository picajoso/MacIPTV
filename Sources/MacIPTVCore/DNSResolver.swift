import Foundation

/// getaddrinfo itself cannot be interrupted. Bound its global concurrency and
/// detach the caller on cancellation/deadline; late results never connect.
final class DNSResolver: @unchecked Sendable {
    static let shared = DNSResolver(lookup: { try NetworkGateway.lookup($0) })
    private let lock = NSLock()
    private var active = 0
    private let maximum: Int
    private let lookup: @Sendable (String) throws -> [String]
    init(maximum: Int = 4, lookup: @escaping @Sendable (String) throws -> [String]) {
        self.maximum = maximum; self.lookup = lookup
    }
    func resolve(_ host: String, timeout: Double = 8) async throws -> [String] {
        try Task.checkCancellation()
        guard reserve() else { throw IPTVError.security(reason: "Demasiadas resoluciones DNS simultáneas.") }
        let completion = DNSCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    completion.finish(.failure(URLError(.timedOut)))
                }
                DispatchQueue.global(qos: .utility).async { [self] in
                    let result: Result<[String], Error>
                    if completion.isFinished { result = .failure(CancellationError()) }
                    else { result = Result { try lookup(host) } }
                    lock.lock(); active -= 1; lock.unlock()
                    completion.finish(result)
                }
            }
        } onCancel: { completion.finish(.failure(CancellationError())) }
    }
    private func reserve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active < maximum else { return false }
        active += 1; return true
    }
}

private final class DNSCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[String], Error>?
    private var continuation: CheckedContinuation<[String], Error>?
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
    func install(_ continuation: CheckedContinuation<[String], Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<[String], Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result)
    }
}
