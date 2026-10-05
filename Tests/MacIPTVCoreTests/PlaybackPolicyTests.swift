import XCTest
@testable import MacIPTVCore

final class PlaybackPolicyTests: XCTestCase {
    func testXtreamTSUsesEquivalentHLSWithoutChangingCredentialsOrQuery() throws {
        let url = try XCTUnwrap(URL(string: "http://example.test/live/User/P%26%2Fword/123.ts?token=a%2Bb"))
        XCTAssertEqual(PlaybackPolicy.nativeURL(for: url).absoluteString,
                       "http://example.test/live/User/P%26%2Fword/123.m3u8?token=a%2Bb")
    }
    func testPrefixedXtreamPathIsPreserved() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/panel/live/u/p/42.ts"))
        XCTAssertEqual(PlaybackPolicy.nativeURL(for: url).path, "/panel/live/u/p/42.m3u8")
    }
    func testOrdinaryTSAndHLSAreNotRewritten() throws {
        for raw in ["http://example.test/video/42.ts", "http://example.test/live/u/p/42.m3u8",
                    "http://example.test/live/u/p/movie.ts", "http://example.test/live/u//42.ts"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(PlaybackPolicy.nativeURL(for: url), url)
        }
    }
}
