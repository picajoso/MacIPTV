import XCTest
@testable import MacIPTVCore

final class SecureHTTPClientTests: XCTestCase {
    func testAuthorisedEndpointWorksThroughPinnedGateway() async throws {
        let fixture = SecurityHTTPFixture(); let url = try await fixture.start()
        let policy = NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: url.host!, port: UInt16(url.port!))])
        let client = SecureHTTPClient(policy: policy)
        let response = try await client.fetch(URLRequest(url: url), maximumBytes: 1024)
        XCTAssertEqual(response.data, Data("fixture".utf8))
        await client.stop(); await fixture.stop()
    }
    func testBothDeclaredAndChunkedOversizedBodiesAreCancelled() async throws {
        let fixture = SecurityHTTPFixture(); let url = try await fixture.start()
        let client = SecureHTTPClient(policy: NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: url.host!, port: UInt16(url.port!))]))
        for reply in [SecurityHTTPFixture.Reply.body(Data(repeating: 65, count: 8192)), .chunked(Data(repeating: 65, count: 8192))] {
            await fixture.configure(reply)
            do { _ = try await client.fetch(URLRequest(url: url), maximumBytes: 2048); XCTFail("oversized response accepted") }
            catch IPTVError.downloadTooLarge { }
        }
        await client.stop(); await fixture.stop()
    }
    func testRedirectCannotReachAnotherLocalService() async throws {
        let source = SecurityHTTPFixture(), target = SecurityHTTPFixture()
        let url = try await source.start(), targetURL = try await target.start()
        await source.configure(.redirect(targetURL))
        let client = SecureHTTPClient(policy: NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: url.host!, port: UInt16(url.port!))]))
        do { _ = try await client.fetch(URLRequest(url: url), maximumBytes: 1024); XCTFail("redirect accepted") }
        catch IPTVError.security { }
        let requests = await target.requests
        XCTAssertEqual(requests, 0)
        await client.stop(); await source.stop(); await target.stop()
    }
}
