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

    func testSourceCatalogPreservesIndependentCredentialsAndConsent() throws {
        let first = UUID(), second = UUID()
        let catalog = KeychainSourceStore.Catalog(sources: [
            first: SavedSource(source: .xtream(baseURL: "https://first.example", username: "alice", password: "first-secret")),
            second: SavedSource(source: .m3uURL(url: "http://second.example/list", xmltvURL: nil),
                                policy: NetworkPolicy(allowHTTP: true))
        ])
        let restored = try JSONDecoder().decode(KeychainSourceStore.Catalog.self,
                                                from: JSONEncoder().encode(catalog))
        XCTAssertEqual(restored.sources.count, 2)
        XCTAssertEqual(restored.sources[first], catalog.sources[first])
        XCTAssertEqual(restored.sources[second], catalog.sources[second])
        XCTAssertFalse(restored.sources[first]!.policy.allowHTTP)
        XCTAssertTrue(restored.sources[second]!.policy.allowHTTP)
    }
}
