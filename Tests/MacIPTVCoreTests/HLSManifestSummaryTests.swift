import XCTest
@testable import MacIPTVCore

final class HLSManifestSummaryTests: XCTestCase {
    // Fake values only; nothing here is a real credential or reachable host.
    private let fakeToken = "SECRETTOKEN9z"
    private let fakeKey = "AKIAFAKEACCESSKEY"
    private let fakeSecret = "fakeSecretDoNotLog"
    private let fakeHost = "cdn.example-invalid.test"

    private var liveManifest: String {
        [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:10",
            "#EXT-X-MEDIA-SEQUENCE:2684395713",
            "#EXT-X-KEY:METHOD=AES-128,URI=\"https://\(fakeHost)/key?token=\(fakeToken)\"",
            "#EXTINF:9.009,",
            "https://\(fakeHost)/live/key=\(fakeKey)/seg1.ts?sig=\(fakeSecret)",
            "#EXTINF:9.009,",
            "https://\(fakeHost)/live/seg2.ts?sig=\(fakeSecret)",
            "#EXTINF:9.009,",
            "https://\(fakeHost)/live/seg3.ts?sig=\(fakeSecret)",
            "#EXTINF:9.009,",
            "https://\(fakeHost)/live/seg4.ts?sig=\(fakeSecret)",
        ].joined(separator: "\n")
    }

    private var masterManifest: String {
        [
            "#EXTM3U",
            "#EXT-X-VERSION:4",
            "#EXT-X-STREAM-INF:BANDWIDTH=5000000,AVERAGE-BANDWIDTH=4500000,RESOLUTION=1920x1080",
            "https://\(fakeHost)/master/band720.m3u8?token=\(fakeToken)",
            "#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720",
            "https://\(fakeHost)/master/band480.m3u8?token=\(fakeToken)",
        ].joined(separator: "\n")
    }

    private var finiteManifest: String {
        [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:10",
            "#EXTINF:10.5,VOD Title With \(fakeSecret)",
            "https://\(fakeHost)/vod/seg1.ts?KeyId=\(fakeKey)",
            "#EXTINF:9.4,",
            "https://\(fakeHost)/vod/seg2.ts",
            "#EXTINF:5.25,",
            "https://\(fakeHost)/vod/seg3.ts",
            "#EXT-X-ENDLIST",
        ].joined(separator: "\n")
    }

    private func assertLeakFree(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for needle in [fakeToken, fakeKey, fakeSecret, fakeHost, "EXTM3U", "EXTINF", "STREAM", "http", "m3u8", ".ts"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(needle), "summary leaked \(needle)", file: file, line: line)
        }
    }

    func testLiveManifestParsesTagsAndPairsExtinf() {
        let summary = HLSManifestSummary(liveManifest)
        XCTAssertEqual(summary.version, 3)
        XCTAssertEqual(summary.mediaSequence, 2684395713)
        XCTAssertEqual(summary.targetDuration, 10)
        XCTAssertEqual(summary.segmentCount, 4)
        XCTAssertEqual(summary.totalDuration, 36.036, accuracy: 0.0005)
        XCTAssertFalse(summary.endList)
        XCTAssertFalse(summary.isMaster)
    }

    func testMasterManifestCountsNoSegments() {
        let summary = HLSManifestSummary(masterManifest)
        XCTAssertTrue(summary.isMaster)
        XCTAssertEqual(summary.segmentCount, 0)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertEqual(summary.version, 4)
        XCTAssertNil(summary.mediaSequence)
        XCTAssertFalse(summary.endList)
    }

    func testFiniteManifestEndListAndCommaSuffixTitle() {
        let summary = HLSManifestSummary(finiteManifest)
        XCTAssertTrue(summary.endList)
        XCTAssertFalse(summary.isMaster)
        XCTAssertEqual(summary.segmentCount, 3)
        XCTAssertEqual(summary.totalDuration, 25.15, accuracy: 0.0005)
        XCTAssertNil(summary.mediaSequence)
    }

    func testSummaryStringIsDeterministicNumericOnly() {
        let summary = HLSManifestSummary(liveManifest)
        XCTAssertEqual(summary.summary, "version=3 mediaSequence=2684395713 targetDuration=10.0 segmentCount=4 totalDuration=36.036 endList=false isMaster=false")
        XCTAssertEqual(HLSManifestSummary(liveManifest).summary, summary.summary)
    }

    func testSummaryNeverLeaksCredentialsOrURLs() {
        assertLeakFree(HLSManifestSummary(liveManifest).summary)
        assertLeakFree(HLSManifestSummary(masterManifest).summary)
        assertLeakFree(HLSManifestSummary(finiteManifest).summary)
        // The synthesized description only shows numeric/boolean properties.
        assertLeakFree(String(describing: HLSManifestSummary(liveManifest)))
    }

    func testCRLFAndBOMAreHandled() {
        let crlf = liveManifest.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(HLSManifestSummary(crlf), HLSManifestSummary(liveManifest))
        let bom = "\u{FEFF}" + crlf
        XCTAssertEqual(HLSManifestSummary(bom), HLSManifestSummary(liveManifest))
    }

    func testSegmentWithoutExtinfSuppressesTotalButStillCounts() {
        let text = [
            "#EXTM3U",
            "#EXT-X-TARGETDURATION:4",
            "#EXT-X-MEDIA-SEQUENCE:10",
            "#EXTINF:4.0,",
            "seg1.ts",
            "seg2.ts",
        ].joined(separator: "\n")
        let summary = HLSManifestSummary(text)
        XCTAssertEqual(summary.segmentCount, 2)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertEqual(summary.targetDuration, 4)
    }

    func testEmptyAndGarbageManifestsAreSafe() {
        for text in ["", "\n\r\n", "# not hls at all", "random \(fakeSecret) text"] {
            let summary = HLSManifestSummary(text)
            XCTAssertEqual(summary.segmentCount, 0)
            XCTAssertTrue(summary.isMaster)
            XCTAssertEqual(summary.totalDuration, 0)
            XCTAssertFalse(summary.endList)
            assertLeakFree(summary.summary)
        }
    }

    func testEquatableAndSendable() {
        func takeSendable(_ value: some Sendable & Equatable) -> Bool { value == value }
        let a = HLSManifestSummary(liveManifest)
        let b = HLSManifestSummary(finiteManifest)
        XCTAssertTrue(takeSendable(a))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, HLSManifestSummary(liveManifest))
    }
}
