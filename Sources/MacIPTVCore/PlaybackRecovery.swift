import Foundation

/// Bounded reconnects for live streams. A ready item can still stop advancing.
/// Uses monotonic seconds supplied by the caller; never reconnects a user pause.
public struct PlaybackRecovery {
    private var attempts = 0
    private var lastPosition: Double?
    private var lastProgress: Double?
    private var healthySince: Double?
    public init() {}

    public mutating func resetProgress() {
        lastPosition = nil
        lastProgress = nil
        healthySince = nil
    }

    public mutating func sample(now: Double, position: Double, paused: Bool) -> Bool {
        guard !paused else { resetProgress(); return false }
        guard let previous = lastPosition, let progress = lastProgress else {
            lastPosition = position.isFinite ? position : 0
            lastProgress = now
            healthySince = now
            return false
        }
        if position.isFinite && abs(position - previous) > 0.05 {
            if now - progress > 3 { healthySince = now }
            lastPosition = position
            lastProgress = now
            if let healthySince, now - healthySince >= 60 { attempts = 0 }
            return false
        }
        if now - progress > 3 { healthySince = nil }
        return now - progress >= 15
    }

    public mutating func nextRetryDelay() -> Double? {
        guard attempts < 3 else { return nil }
        let delay = pow(2.0, Double(attempts + 1))
        attempts += 1
        return delay
    }
}
