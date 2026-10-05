import XCTest
@testable import MacIPTVCore

final class PlaybackRecoveryTests: XCTestCase {
    func testFrozenReadyItemTriggersRecoveryAfterGrace() {
        var state = PlaybackRecovery()
        XCTAssertFalse(state.sample(now: 0, position: 5, paused: false))
        XCTAssertFalse(state.sample(now: 14, position: 5, paused: false))
        XCTAssertTrue(state.sample(now: 15, position: 5, paused: false))
    }
    func testPauseDoesNotReconnectAndResumeGetsFreshGrace() {
        var state = PlaybackRecovery()
        _ = state.sample(now: 0, position: 5, paused: false)
        XCTAssertFalse(state.sample(now: 100, position: 5, paused: true))
        XCTAssertFalse(state.sample(now: 101, position: 5, paused: false))
        XCTAssertFalse(state.sample(now: 115, position: 5, paused: false))
        XCTAssertTrue(state.sample(now: 116, position: 5, paused: false))
    }
    func testRepeatedShortLivedConnectionsHaveFiniteBudget() {
        var state = PlaybackRecovery()
        for delay in [2.0, 4.0, 8.0] {
            XCTAssertEqual(state.nextRetryDelay(), delay)
            state.resetProgress()
            for second in 0...10 { _ = state.sample(now: Double(second), position: Double(second), paused: false) }
        }
        XCTAssertNil(state.nextRetryDelay())
    }
    func testSustainedPlaybackRestoresBudget() {
        var state = PlaybackRecovery()
        _ = state.nextRetryDelay()
        for second in 0...61 { _ = state.sample(now: Double(second), position: Double(second), paused: false) }
        XCTAssertEqual(state.nextRetryDelay(), 2)
    }
    func testBufferingBreaksHealthyWindow() {
        var state = PlaybackRecovery()
        _ = state.nextRetryDelay()
        for second in 0...40 { _ = state.sample(now: Double(second), position: Double(second), paused: false) }
        _ = state.sample(now: 50, position: 40, paused: false)
        for second in 51...90 { _ = state.sample(now: Double(second), position: Double(second - 10), paused: false) }
        XCTAssertEqual(state.nextRetryDelay(), 4)
    }
}
