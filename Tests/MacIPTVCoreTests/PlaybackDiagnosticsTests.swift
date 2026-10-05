import XCTest
@testable import MacIPTVCore

final class PlaybackDiagnosticsTests: XCTestCase {
    func testMediaCommentOutputsOnlyFixedReason() {
        XCTAssertEqual(MediaFailureReason.classify("HTTP 403 Forbidden http://example.test/live/private-user/private-password/42.ts"), .forbidden)
        XCTAssertEqual(MediaFailureReason.classify("arbitrary secret http://example.test/?token=private"), .other)
        XCTAssertEqual(MediaFailureReason.classify("Playlist unchanged for too long"), .playlistUnchanged)
    }
    func testSnapshotDescribesWaitingWithoutInfiniteNumericValues() {
        let snapshot = PlaybackSnapshot(trigger: .failed, session: UUID(), elapsed: 31.5, position: 30,
            duration: .infinity, rate: 0, itemStatus: 1, transport: .waiting, wait: .buffer,
            bufferedAhead: 0, seekableStart: .nan, seekableEnd: 50, bufferEmpty: true,
            likelyToKeepUp: false, mediaRequests: 4, stalls: 1, bytes: 4096,
            observedBitrate: 1500, indicatedBitrate: .nan, droppedFrames: 0)
        XCTAssertTrue(snapshot.summary.contains("elapsed=31.50"))
        XCTAssertTrue(snapshot.summary.contains("transport=waiting wait=buffer"))
        XCTAssertTrue(snapshot.summary.contains("duration=unknown"))
        XCTAssertFalse(snapshot.summary.contains("nan"))
        XCTAssertFalse(snapshot.summary.contains("inf"))
    }
}
