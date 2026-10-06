import XCTest
import Network
@testable import MacIPTVCore

final class HLSRelaySecurityTests: XCTestCase {
    private let upstream = URL(string: "https://example.test/live.m3u8")!
    private let local = URL(string: "http://127.0.0.1:1234/private/")!

    func testManifestCannotExposeFileOrPrivateNetworkReferences() {
        for resource in ["file:///tmp/private", "http://127.0.0.1:9000/private", "https://192.168.1.1/admin"] {
            var registry = HLSRelayRegistry()
            XCTAssertThrowsError(try registry.rewrite("#EXTM3U\n#EXTINF:10,\n\(resource)\n", upstream: upstream, localBase: local, playlistID: "root"))
        }
    }

    func testAmbiguousURIAttributesAreRejectedBeforeAVPlayerReceivesThem() {
        for attribute in ["URI = \"file:///tmp/private\"", "uri=\"https://127.0.0.1/private\"", "URI=file:///tmp/private"] {
            var registry = HLSRelayRegistry()
            XCTAssertThrowsError(try registry.rewrite("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,\(attribute)\n", upstream: upstream, localBase: local, playlistID: "root"))
        }
    }

    func testOversizedManifestIsRejected() {
        var registry = HLSRelayRegistry()
        XCTAssertThrowsError(try registry.rewrite(String(repeating: "x", count: DownloadLimits.manifest + 1), upstream: upstream, localBase: local, playlistID: "root"))
    }

    func testSessionKeysAndInitializationSegmentsKeepTheirResourceKinds() throws {
        var registry = HLSRelayRegistry()
        let result = try registry.rewrite("#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXT-X-MAP:URI=\"init.mp4\"\n", upstream: upstream, localBase: local, playlistID: "root")
        let lines = result.components(separatedBy: .newlines)
        let pattern = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        for (index, kind) in [(1, HLSRelayRegistry.Kind.key), (2, .segment)] {
            let line = lines[index]
            let match = try XCTUnwrap(pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)))
            let range = try XCTUnwrap(Range(match.range(at: 1), in: line))
            let id = try XCTUnwrap(URL(string: String(line[range]))).lastPathComponent
            XCTAssertEqual(registry.kind(for: id), kind)
        }
    }

    func testRelayRejectsPrivateSubresourcesWithoutContactingThem() async throws {
        let source = SecurityHTTPFixture(), target = SecurityHTTPFixture()
        let sourceURL = try await source.start(), targetURL = try await target.start()
        await source.configure(.body(Data("#EXTM3U\n#EXTINF:10,\n\(targetURL.absoluteString)\n".utf8)))
        let policy = NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: "127.0.0.1", port: UInt16(sourceURL.port!))])
        let relay = HLSRelay(policy: policy)
        let relayURL = try await relay.start(upstream: sourceURL)
        let session = URLSession(configuration: .ephemeral)
        let (_, response) = try await session.data(from: relayURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 502)
        let requests = await target.requests
        XCTAssertEqual(requests, 0)
        session.invalidateAndCancel()
        await relay.stop(); await source.stop(); await target.stop()
    }

    func testIncompleteLocalHeaderIsClosedAtDeadline() async throws {
        let relay = HLSRelay()
        let relayURL = try await relay.start(upstream: upstream)
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(relayURL.port!))!, using: .tcp)
        try await SocketIO.ready(connection, queue: DispatchQueue(label: "header-test"))
        try await SocketIO.send(Data("GET /".utf8), to: connection)
        let started = Date()
        do {
            let data = try await SocketIO.receive(connection, timeout: 8)
            XCTAssertTrue(data.isEmpty)
        } catch { /* Peer closure can surface as NWError rather than EOF. */ }
        XCTAssertLessThan(Date().timeIntervalSince(started), 7)
        connection.cancel()
        await relay.stop()
    }

    func testAbandonedRequestsReleaseDownloadSlots() async throws {
        let fixture = SecurityHTTPFixture(), data = Data("#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nmedia.ts\n".utf8)
        let upstream = try await fixture.start()
        await fixture.configure(.delayed(data))
        let relay = HLSRelay(policy: NetworkPolicy(allowHTTP: true, localEndpoints: [NetworkPolicy.endpointKey(host: "127.0.0.1", port: UInt16(upstream.port!))]))
        let local = try await relay.start(upstream: upstream)
        var connections: [NWConnection] = []
        for _ in 0..<4 {
            let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(local.port!))!, using: .tcp)
            try await SocketIO.ready(connection, queue: DispatchQueue(label: "abandon-test"))
            try await SocketIO.send(Data("GET \(local.path) HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8), to: connection)
            connections.append(connection)
        }
        let arrivalDeadline = Date().addingTimeInterval(2)
        while await fixture.requests < 4 && Date() < arrivalDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let arrivals = await fixture.requests
        XCTAssertEqual(arrivals, 4)
        connections.forEach { $0.cancel() }
        await fixture.configure(.body(data))
        let session = URLSession(configuration: .ephemeral)
        let releaseDeadline = Date().addingTimeInterval(1)
        var status = 0
        repeat {
            try await Task.sleep(nanoseconds: 20_000_000)
            let (_, response) = try await session.data(from: local)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } while status != 200 && Date() < releaseDeadline
        XCTAssertEqual(status, 200, "Abandoned downloads must not occupy all four slots for five seconds")
        session.invalidateAndCancel()
        await relay.stop(); await fixture.stop()
    }
}
