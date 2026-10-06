import XCTest
@testable import MacIPTVCore

final class DNSResolverTests: XCTestCase {
    func testCancellationReleasesCallerAndKeepsBlockedWorkersBounded() async throws {
        let started = expectation(description: "lookup started")
        let finished = expectation(description: "lookup finished")
        let gate = DispatchSemaphore(value: 0)
        let resolver = DNSResolver(maximum: 1) { _ in
            started.fulfill()
            gate.wait()
            finished.fulfill()
            return ["8.8.8.8"]
        }
        let request = Task { try await resolver.resolve("fixture.test") }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        do { _ = try await request.value; XCTFail("cancelled resolution returned data") }
        catch is CancellationError { }
        do { _ = try await resolver.resolve("other.test"); XCTFail("unbounded workers") }
        catch IPTVError.security { }
        gate.signal()
        await fulfillment(of: [finished], timeout: 1)
    }

    func testDeadlineDiscardsLateResults() async throws {
        let gate = DispatchSemaphore(value: 0)
        let resolver = DNSResolver(maximum: 1) { _ in gate.wait(); return ["127.0.0.1"] }
        defer { gate.signal() }
        do { _ = try await resolver.resolve("fixture.test", timeout: 0.05); XCTFail("deadline ignored") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
    }
}
