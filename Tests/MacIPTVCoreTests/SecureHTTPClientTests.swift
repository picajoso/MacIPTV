import XCTest
@testable import MacIPTVCore

final class SecureHTTPClientTests: XCTestCase {
    func testStreamingDeliversBeforeResponseCompletes() async throws {
        let fixture = SecurityHTTPFixture(); let url = try await fixture.start()
        let prefix = Data(repeating: 65, count: 32768), suffix = Data(repeating: 66, count: 32768)
        await fixture.configure(.split(prefix, suffix))
        let client = SecureHTTPClient(policy: NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: url.host!, port: UInt16(url.port!))]))
        let first = expectation(description: "First chunk arrives while upstream tail is withheld")
        let download = Task {
            try await client.stream(URLRequest(url: url), maximumBytes: 65536, onResponse: { _ in }, onChunk: { chunk in
                if chunk == prefix { first.fulfill() }
            })
        }
        await fulfillment(of: [first], timeout: 3)
        await fixture.releaseTail()
        let result = try await download.value
        XCTAssertEqual(result.byteCount, 65536)
        await client.stop(); await fixture.stop()
    }

    func testStreamingEnforcesBodyLimitsAndRedirectPolicy() async throws {
        let source = SecurityHTTPFixture(), target = SecurityHTTPFixture()
        let url = try await source.start(), targetURL = try await target.start()
        let client = SecureHTTPClient(policy: NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: url.host!, port: UInt16(url.port!))]))
        for reply in [SecurityHTTPFixture.Reply.body(Data(repeating: 65, count: 8192)), .chunked(Data(repeating: 65, count: 8192))] {
            await source.configure(reply)
            do {
                _ = try await client.stream(URLRequest(url: url), maximumBytes: 2048, onResponse: { _ in }, onChunk: { _ in })
                XCTFail("Oversized stream accepted")
            } catch IPTVError.downloadTooLarge { }
        }
        await source.configure(.redirect(targetURL))
        do {
            _ = try await client.stream(URLRequest(url: url), maximumBytes: 1024, onResponse: { _ in }, onChunk: { _ in })
            XCTFail("Redirect accepted")
        } catch IPTVError.security { }
        let requests = await target.requests
        XCTAssertEqual(requests, 0)
        await client.stop(); await source.stop(); await target.stop()
    }

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
