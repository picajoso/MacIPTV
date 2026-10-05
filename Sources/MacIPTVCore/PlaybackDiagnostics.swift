import Foundation

/// Explicitly typed telemetry. Never accepts a URL, channel name or provider text.
public struct PlaybackSnapshot {
    public enum Trigger: String { case periodic, ready, stalled, failed, ended, access, mediaError }
    public enum Transport: String { case playing, waiting, paused }
    public enum Wait: String { case none, buffer, evaluate, noItem, other }
    public let trigger: Trigger
    public let session: UUID
    public let elapsed: Double
    public let position: Double
    public let duration: Double
    public let rate: Float
    public let itemStatus: Int
    public let transport: Transport
    public let wait: Wait
    public let bufferedAhead: Double
    public let seekableStart: Double
    public let seekableEnd: Double
    public let bufferEmpty: Bool
    public let likelyToKeepUp: Bool
    public let mediaRequests: Int
    public let stalls: Int
    public let bytes: Int64
    public let observedBitrate: Double
    public let indicatedBitrate: Double
    public let droppedFrames: Int

    public init(trigger: Trigger, session: UUID, elapsed: Double, position: Double, duration: Double,
                rate: Float, itemStatus: Int, transport: Transport, wait: Wait, bufferedAhead: Double,
                seekableStart: Double, seekableEnd: Double, bufferEmpty: Bool, likelyToKeepUp: Bool,
                mediaRequests: Int, stalls: Int, bytes: Int64, observedBitrate: Double, indicatedBitrate: Double,
                droppedFrames: Int) {
        self.trigger = trigger; self.session = session; self.elapsed = elapsed; self.position = position
        self.duration = duration; self.rate = rate; self.itemStatus = itemStatus; self.transport = transport
        self.wait = wait; self.bufferedAhead = bufferedAhead; self.seekableStart = seekableStart
        self.seekableEnd = seekableEnd; self.bufferEmpty = bufferEmpty; self.likelyToKeepUp = likelyToKeepUp
        self.mediaRequests = mediaRequests; self.stalls = stalls; self.bytes = bytes
        self.observedBitrate = observedBitrate; self.indicatedBitrate = indicatedBitrate
        self.droppedFrames = droppedFrames
    }
    public var summary: String {
        func number(_ value: Double) -> String { value.isFinite ? String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) : "unknown" }
        return "session=\(session.uuidString) event=\(trigger.rawValue) elapsed=\(number(elapsed)) position=\(number(position)) duration=\(number(duration)) rate=\(number(Double(rate))) item=\(itemStatus) transport=\(transport.rawValue) wait=\(wait.rawValue) ahead=\(number(bufferedAhead)) seekable=\(number(seekableStart))...\(number(seekableEnd)) empty=\(bufferEmpty) keepUp=\(likelyToKeepUp) requests=\(mediaRequests) stalls=\(stalls) bytes=\(bytes) observedBitrate=\(number(observedBitrate)) indicatedBitrate=\(number(indicatedBitrate)) dropped=\(droppedFrames)"
    }
}

public enum MediaFailureReason: String {
    case forbidden, unauthorized, notFound, timeout, playlistUnchanged, other
    /// Classify in memory, emitting only a fixed value. Never redact-and-print free text.
    public static func classify(_ comment: String?) -> Self {
        let text = comment?.lowercased() ?? ""
        if text.contains("forbidden") || text.contains("http 403") { return .forbidden }
        if text.contains("unauthorized") || text.contains("http 401") { return .unauthorized }
        if text.contains("not found") || text.contains("http 404") { return .notFound }
        if text.contains("timed out") || text.contains("timeout") { return .timeout }
        if text.contains("playlist") && text.contains("unchanged") { return .playlistUnchanged }
        return .other
    }
}
