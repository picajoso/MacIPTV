import Foundation
import Network

struct HTTPResult: Sendable { let data: Data; let response: HTTPURLResponse }

/// Ephemeral, bounded HTTP with an authenticated, fail-closed pinned-IP gateway.
actor SecureHTTPClient {
    private let policy: NetworkPolicy
    private let timeout: Double
    private let gateway: NetworkGateway
    private let delegate: BoundedSessionDelegate
    private var setup: Task<URLSession, Error>?
    private var active = 0
    init(policy: NetworkPolicy, timeout: Double = 30) {
        self.policy = policy; self.timeout = timeout
        gateway = NetworkGateway(policy: policy)
        delegate = BoundedSessionDelegate(policy: policy)
    }
    func fetch(_ request: URLRequest, maximumBytes: Int) async throws -> HTTPResult {
        guard let url = request.url else { throw URLError(.badURL) }
        try policy.validate(url)
        try Task.checkCancellation()
        guard maximumBytes > 0, active < 4 else { throw IPTVError.security(reason: "Demasiadas descargas simultáneas.") }
        active += 1
        defer { active -= 1 }
        if setup == nil {
            let gateway = gateway, delegate = delegate, timeout = timeout
            setup = Task {
                let proxy = try await gateway.start()
                let config = URLSessionConfiguration.ephemeral
                config.urlCache = nil; config.urlCredentialStorage = nil
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.timeoutIntervalForRequest = timeout
                config.timeoutIntervalForResource = max(timeout, 60)
                config.httpMaximumConnectionsPerHost = 4
                config.proxyConfigurations = [proxy]
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                return URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
            }
        }
        let session = try await setup!.value
        try Task.checkCancellation()
        return try await delegate.fetch(request, session: session, maximumBytes: maximumBytes)
    }
    func stop() async {
        setup?.cancel()
        if let session = try? await setup?.value { session.invalidateAndCancel() }
        setup = nil
        await gateway.stop()
    }
    deinit {
        let setup = setup, gateway = gateway
        Task {
            setup?.cancel()
            if let session = try? await setup?.value { session.invalidateAndCancel() }
            await gateway.stop()
        }
    }
}

private final class DownloadTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func set(_ value: URLSessionTask) { lock.lock(); task = value; let cancel = cancelled; lock.unlock(); if cancel { value.cancel() } }
    func cancel() { lock.lock(); cancelled = true; let current = task; lock.unlock(); current?.cancel() }
}

private final class BoundedSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class State {
        let maximum: Int
        let continuation: CheckedContinuation<HTTPResult, Error>
        var data = Data()
        var response: HTTPURLResponse?
        var failure: Error?
        var redirects = 0
        init(maximum: Int, continuation: CheckedContinuation<HTTPResult, Error>) {
            self.maximum = maximum; self.continuation = continuation
        }
    }
    private let policy: NetworkPolicy
    private let lock = NSLock()
    private var states: [Int: State] = [:]
    init(policy: NetworkPolicy) { self.policy = policy }
    func fetch(_ request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> HTTPResult {
        let box = DownloadTaskBox()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.lock(); states[task.taskIdentifier] = State(maximum: maximumBytes, continuation: continuation); lock.unlock()
                box.set(task); task.resume()
            }
        } onCancel: { box.cancel() }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard let state = states[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else {
            lock.unlock(); completionHandler(.cancel); return
        }
        state.response = http
        var allowed = true
        if (200..<300).contains(http.statusCode) {
            if response.expectedContentLength > Int64(state.maximum) { state.failure = IPTVError.downloadTooLarge; allowed = false }
        } else { allowed = false } // Don't download error bodies.
        states[dataTask.taskIdentifier] = state; lock.unlock()
        completionHandler(allowed ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let state = states[dataTask.taskIdentifier] else { lock.unlock(); return }
        if data.count > state.maximum - state.data.count {
            state.failure = IPTVError.downloadTooLarge
            states[dataTask.taskIdentifier] = state; lock.unlock(); dataTask.cancel(); return
        }
        state.data.append(data)
        states[dataTask.taskIdentifier] = state; lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        guard let state = states[task.taskIdentifier] else { lock.unlock(); completionHandler(nil); return }
        do {
            guard let destination = request.url else { throw URLError(.badURL) }
            try policy.validate(destination, redirectedFrom: response.url)
            state.redirects += 1
            guard state.redirects <= 8 else { throw URLError(.httpTooManyRedirects) }
            states[task.taskIdentifier] = state; lock.unlock(); completionHandler(request)
        } catch {
            state.failure = error; states[task.taskIdentifier] = state
            lock.unlock(); completionHandler(nil); task.cancel()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let state = states.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let state else { return }
        if let failure = state.failure { state.continuation.resume(throwing: failure) }
        else if let response = state.response, !(200..<300).contains(response.statusCode) {
            state.continuation.resume(returning: HTTPResult(data: Data(), response: response))
        } else if let error {
            if (error as? URLError)?.code == .cancelled { state.continuation.resume(throwing: CancellationError()) }
            else { state.continuation.resume(throwing: error) }
        } else if let response = state.response {
            state.continuation.resume(returning: HTTPResult(data: state.data, response: response))
        } else { state.continuation.resume(throwing: URLError(.badServerResponse)) }
    }
}
