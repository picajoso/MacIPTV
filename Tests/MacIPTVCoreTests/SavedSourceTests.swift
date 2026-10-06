import XCTest
@testable import MacIPTVCore

final class SavedSourceTests: XCTestCase {
    func testLegacySourceNeverGrantsHTTPConsent() throws {
        let source = SourceConfiguration.xtream(baseURL: "example.test:8080", username: "fixture", password: "fixture")
        let saved = try SavedSource.decode(JSONEncoder().encode(source))
        XCTAssertFalse(saved.policy.allowHTTP)
        XCTAssertEqual(saved.policy.localEndpoints, [])
        guard case .xtream(let base, _, _) = saved.source else { return XCTFail("source changed") }
        XCTAssertEqual(base, "http://example.test:8080")
    }
    func testPermissionsSurviveEnvelopeRoundTrip() throws {
        let saved = SavedSource(source: .m3uURL(url: "http://example.test/list", xmltvURL: nil), policy: NetworkPolicy(allowHTTP: true, localEndpoints: ["127.0.0.1:8000"]))
        XCTAssertEqual(try SavedSource.decode(JSONEncoder().encode(saved)), saved)
    }
}
