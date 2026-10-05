import XCTest
@testable import MacIPTVCore

final class HLSRelayAccessTests: XCTestCase {
    func testLoopbackRelayRejectsUnknownRoutesWithoutContactingProvider() async throws {
        let relay = HLSRelay()
        // A provider that cannot respond; invalid local paths must still return
        // 404 immediately rather than being forwarded to this destination.
        let local = try await relay.start(upstream: URL(string: "http://127.0.0.1:1/unused.m3u8")!)
        XCTAssertEqual(local.host, "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        let unknown = local.deletingLastPathComponent().appendingPathComponent("unknown")
        let (_, first) = try await session.data(from: unknown)
        XCTAssertEqual((first as? HTTPURLResponse)?.statusCode, 404)
        var components = URLComponents(url: local, resolvingAgainstBaseURL: false)!
        components.path = "/wrong-prefix/root"
        let (_, second) = try await session.data(from: components.url!)
        XCTAssertEqual((second as? HTTPURLResponse)?.statusCode, 404)
        await relay.stop()
        session.invalidateAndCancel()
    }
}
