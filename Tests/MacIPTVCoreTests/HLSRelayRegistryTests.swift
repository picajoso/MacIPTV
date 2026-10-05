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
}
