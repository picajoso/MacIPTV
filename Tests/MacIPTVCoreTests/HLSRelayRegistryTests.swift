import XCTest
@testable import MacIPTVCore
final class HLSRelayRegistryTests: XCTestCase {
    let upstream = URL(string: "https://example.test/session/live.m3u8")!
    let local = URL(string: "http://127.0.0.1:1234/private/")!
    func manifest(sequence: Int, token: String, names: [Int]) -> String {
        "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:\(sequence)\n" + names.map {
            "#EXTINF:10,\nhttps://example.test/\(token)/\($0).ts?token=\(token)\n"
        }.joined()
    }
    func paths(_ text: String) -> [String] { text.components(separatedBy: .newlines).filter {!$0.isEmpty && !$0.hasPrefix("#")} }
    func testRotatingAuthorizationKeepsSegmentIdentityAndUpdatesDestination() throws {
        var registry = HLSRelayRegistry()
        let first = paths(try registry.rewrite(manifest(sequence: 100, token: "secretA", names: [1,2,3]), upstream: upstream, localBase: local, playlistID: "root"))
        let next = paths(try registry.rewrite(manifest(sequence: 101, token: "secretB", names: [2,3,4]), upstream: upstream, localBase: local, playlistID: "root"))
        XCTAssertEqual(first[1], next[0])
        XCTAssertEqual(first[2], next[1])
        let id = URL(string: next[0])!.lastPathComponent
        XCTAssertTrue(try XCTUnwrap(registry.destination(for: id)).absoluteString.contains("secretB"))
        XCTAssertFalse(next.joined().contains("secret"))
        XCTAssertFalse(next.joined().contains("example.test"))
    }
    func testRepeatedSequenceUsesFreshTokensWithoutChangingLocalURLs() throws {
        var registry = HLSRelayRegistry()
        let a = try registry.rewrite(manifest(sequence: 10, token: "A", names: [1,2]), upstream: upstream, localBase: local, playlistID: "root")
        let b = try registry.rewrite(manifest(sequence: 10, token: "B", names: [1,2]), upstream: upstream, localBase: local, playlistID: "root")
        XCTAssertEqual(paths(a), paths(b))
    }
    func testRelativeAndQuotedResourcesAreResolvedAndSecretsHidden() throws {
        var registry = HLSRelayRegistry()
        let input = "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-KEY:METHOD=AES-128,URI=\"keys/k?token=secret\"\n#EXTINF:10,\n1.ts?token=secret\n"
        let result = try registry.rewrite(input, upstream: upstream, localBase: local, playlistID: "root")
        XCTAssertFalse(result.contains("secret"))
        XCTAssertFalse(result.contains("keys/k"))
        XCTAssertTrue(result.contains("METHOD=AES-128"))
    }
    func testPlaylistsDoNotShareSameSequenceIdentities() throws {
        var registry = HLSRelayRegistry()
        let input = manifest(sequence: 10, token: "A", names: [1])
        XCTAssertNotEqual(paths(try registry.rewrite(input, upstream: upstream, localBase: local, playlistID: "a")), paths(try registry.rewrite(input, upstream: upstream, localBase: local, playlistID: "b")))
    }

    func testActiveVariantSurvivesWhileOldSegmentsExpire() throws {
        var registry = HLSRelayRegistry()
        registry.setRoot(upstream)
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000\nvariant.m3u8\n"
        let rewritten = try registry.rewrite(master, upstream: upstream, localBase: local, playlistID: "root")
        let variantID = try XCTUnwrap(URL(string: XCTUnwrap(paths(rewritten).first))).lastPathComponent
        let variantURL = try XCTUnwrap(registry.destination(for: variantID))
        let first = try registry.rewrite(manifest(sequence: 1, token: "A", names: [1]), upstream: variantURL, localBase: local, playlistID: variantID)
        let oldSegmentID = try XCTUnwrap(URL(string: XCTUnwrap(paths(first).first))).lastPathComponent
        for sequence in 2...205 {
            _ = try registry.rewrite(manifest(sequence: sequence, token: "B", names: [sequence]), upstream: variantURL, localBase: local, playlistID: variantID)
        }
        XCTAssertEqual(registry.destination(for: variantID), variantURL)
        XCTAssertNil(registry.destination(for: oldSegmentID))
    }

    func testImplicitByteRangesBecomeExplicitBeforeURIsChange() throws {
        var registry = HLSRelayRegistry()
        let input = "#EXTM3U\n#EXT-X-VERSION:4\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:1\n"
            + "#EXTINF:10,\n#EXT-X-BYTERANGE:100@20\nmedia.ts\n"
            + "#EXTINF:10,\n#EXT-X-BYTERANGE:50\n#comment\n./media.ts\n"
            + "#EXTINF:10,\n#EXT-X-BYTERANGE:30\nmedia.ts\n"
        let result = try registry.rewrite(input, upstream: upstream, localBase: local, playlistID: "root")
        let ranges = result.components(separatedBy: .newlines).filter { $0.hasPrefix("#EXT-X-BYTERANGE:") }
        XCTAssertEqual(ranges, ["#EXT-X-BYTERANGE:100@20", "#EXT-X-BYTERANGE:50@120", "#EXT-X-BYTERANGE:30@170"])
        XCTAssertEqual(Set(paths(result)).count, 3)
        for path in paths(result) {
            let id = try XCTUnwrap(URL(string: path)).lastPathComponent
            XCTAssertEqual(registry.destination(for: id), URL(string: "https://example.test/session/media.ts"))
        }
    }

    func testUndefinedOrOverflowingByteRangesAreRejected() throws {
        let header = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:1\n"
        let bodies = [
            "#EXTINF:10,\n#EXT-X-BYTERANGE:100\nmedia.ts\n",
            "#EXTINF:10,\n#EXT-X-BYTERANGE:100@0\na.ts\n#EXTINF:10,\n#EXT-X-BYTERANGE:100\nb.ts\n",
            "#EXTINF:10,\n#EXT-X-BYTERANGE:100@0\nmedia.ts\n#EXTINF:10,\nmedia.ts\n#EXTINF:10,\n#EXT-X-BYTERANGE:100\nmedia.ts\n",
            "#EXTINF:10,\n#EXT-X-BYTERANGE:100@\(Int.max)\nmedia.ts\n"
        ]
        for body in bodies {
            var registry = HLSRelayRegistry()
            XCTAssertThrowsError(try registry.rewrite(header + body, upstream: upstream, localBase: local, playlistID: "root"))
        }
    }

    func testRejectedManifestDoesNotChangeExistingDestinations() throws {
        var registry = HLSRelayRegistry()
        registry.setRoot(upstream)
        let original = try registry.rewrite(manifest(sequence: 1, token: "A", names: [1]), upstream: upstream, localBase: local, playlistID: "root")
        let id = try XCTUnwrap(URL(string: XCTUnwrap(paths(original).first))).lastPathComponent
        let originalDestination = registry.destination(for: id)
        let invalid = manifest(sequence: 1, token: "B", names: [1])
            + "#EXTINF:10,\n#EXT-X-BYTERANGE:100\nother.ts\n"
        XCTAssertThrowsError(try registry.rewrite(invalid, upstream: URL(string: "https://example.test/redirected.m3u8")!, localBase: local, playlistID: "root"))
        XCTAssertEqual(registry.destination(for: id), originalDestination)
        XCTAssertEqual(registry.destination(for: "root"), upstream)
    }
}
