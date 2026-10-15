import CryptoKit
import XCTest
@testable import MacIPTVCore

private actor OrderedStartupFetcher: ContentFetching {
    var published = false
    func markPublished() { published = true }
    func fetchString(_ url: URL) async throws -> String {
        "#EXTM3U\n#EXTINF:-1,Canal\nhttps://example.test/live/secret-token\n"
    }
    func fetchData(_ url: URL) async throws -> Data {
        // La guía no puede empezar a descargarse antes de mostrar canales.
        XCTAssertTrue(published)
        return Data("<tv></tv>".utf8)
    }
    func readFile(path: String) async throws -> String { "" }
}

final class StartupCacheTests: XCTestCase {
    func testChannelsArePublishedBeforeGuideDownload() async throws {
        let fetcher = OrderedStartupFetcher()
        let outcome = try await SourceImporter(fetcher: fetcher).importSource(
            .m3uURL(url: "https://example.test/list", xmltvURL: "https://example.test/guide"),
            onChannelsLoaded: { partial in
                XCTAssertEqual(partial.channels.count, 1)
                XCTAssertNil(partial.guide)
                await fetcher.markPublished()
            })
        XCTAssertEqual(outcome.channels.count, 1)
        XCTAssertNotNil(outcome.guide)
    }

    func testEncryptedSnapshotSurvivesRestartRejectsDifferentSourceAndCanBeRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let id = UUID()
        let source = SavedSource(source: .xtream(baseURL: "https://example.test", username: "user", password: "secret"))
        let channels = [Channel(id: "1", name: "Canal", url: "https://example.test/live/secret-token", group: "Grupo")]
        let cache = ChannelCache(directory: directory, encryptionKey: key)
        try await cache.save(channels: channels, sourceID: id, source: source)
        let raw = try Data(contentsOf: directory.appendingPathComponent(id.uuidString + ".cache"))
        XCTAssertNil(raw.range(of: Data("secret-token".utf8)))
        let restarted = ChannelCache(directory: directory, encryptionKey: key)
        let snapshot = try await restarted.load(sourceID: id, source: source)
        XCTAssertEqual(snapshot?.channels, channels)
        let other = SavedSource(source: .xtream(baseURL: "https://example.test", username: "user", password: "changed"))
        let mismatched = try await restarted.load(sourceID: id, source: other)
        XCTAssertNil(mismatched)
        try await restarted.remove(sourceID: id)
        let removed = try await restarted.load(sourceID: id, source: source)
        XCTAssertNil(removed)
    }
}
