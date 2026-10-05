import Foundation

/// Deterministic numeric summary of an HLS playlist, used as a debug sidecar for
/// fixed-length live cuts. Parses text only: it never touches the network, never
/// logs, and stores no URLs, keys, tokens, or any other arbitrary strings, so the
/// whole struct is safe to persist in diagnostics alongside credential-bearing URIs.
public struct HLSManifestSummary: Equatable, Sendable {
    /// EXT-X-MEDIA-SEQUENCE value; nil when the tag is absent.
    public let mediaSequence: Int?
    /// EXT-X-TARGETDURATION value in seconds; nil when the tag is absent.
    public let targetDuration: Double?
    /// Number of media segment URI lines; always 0 for master playlists.
    public let segmentCount: Int
    /// Sum of EXTINF durations paired with counted segments.
    public let totalDuration: Double
    /// True when the playlist declares EXT-X-ENDLIST (finite/VOD).
    public let endList: Bool
    /// True when EXT-X-STREAM-INF marks a master playlist.
    public let isMaster: Bool
    /// EXT-X-VERSION value; nil when the tag is absent.
    public let version: Int?

    public init(_ text: String) {
        var mediaSequence: Int?
        var targetDuration: Double?
        var version: Int?
        var segmentCount = 0
        var totalDuration = 0.0
        var endList = false
        var sawStreamInf = false
        // Only lines inside a tagged playlist (#EXT...) are URI candidates; stray
        // text in a non-HLS file must not be mistaken for segments.
        var sawExtTag = false
        var sawMediaSequence = false
        var sawTargetDuration = false
        var sawEndList = false
        // EXTINF applies to the next URI line; pairing is best-effort per spec.
        var pendingDuration: Double?
        // Counts URI lines seen without a preceding EXTINF so the sum is honest.
        var uriWithoutExtinf = false

        // Strip a leading UTF-8 BOM if present.
        var text = text
        if text.hasPrefix("\u{FEFF}") { text = String(text.dropFirst()) }
        let lines = text.components(separatedBy: .newlines)
        for raw in lines {
            var line = String(raw)
            if line.hasSuffix("\r") { line = String(line.dropLast()) }
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                pendingDuration = Self.extinfDuration(String(line.dropFirst("#EXTINF:".count)))
                sawExtTag = true
                continue
            }
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Self.integer(String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)))
                sawMediaSequence = true
                sawExtTag = true
                continue
            }
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = Self.double(String(line.dropFirst("#EXT-X-TARGETDURATION:".count)))
                sawTargetDuration = true
                sawExtTag = true
                continue
            }
            if line.hasPrefix("#EXT-X-VERSION:") {
                version = Self.integer(String(line.dropFirst("#EXT-X-VERSION:".count)))
                sawExtTag = true
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                sawStreamInf = true
                sawExtTag = true
                continue
            }
            if line.hasPrefix("#EXT-X-ENDLIST") {
                endList = true
                sawEndList = true
                sawExtTag = true
                continue
            }
            // Matches #EXTM3U and #EXT-* directives without over-matching #EXTINF-style
            // handling above; any tagged playlist enables URI counting.
            if line.hasPrefix("#EXTM3U") || line.hasPrefix("#EXT-") { sawExtTag = true }
            // Any other directive or comment is acknowledged but never stored.
            if line.hasPrefix("#") { continue }

            // Non-directive line: a media segment URI candidate. Never retained.
            if !sawStreamInf && sawExtTag {
                segmentCount += 1
                if let pendingDuration {
                    totalDuration += pendingDuration
                } else {
                    uriWithoutExtinf = true
                }
            }
            pendingDuration = nil
        }

        // EXT-X-STREAM-INF is definitive. Without it, treat the playlist as media
        // when any media-playlist tag or segment is present (RFC 8216 requires
        // TARGETDURATION on media playlists); otherwise fall back to master.
        let isMaster = sawStreamInf
            || !(sawMediaSequence || sawTargetDuration || sawEndList || segmentCount > 0)

        self.mediaSequence = mediaSequence
        self.targetDuration = targetDuration
        self.segmentCount = isMaster ? 0 : segmentCount
        // Report the sum only when every counted segment carried a duration.
        self.totalDuration = (!isMaster && !uriWithoutExtinf) ? (totalDuration * 1000).rounded() / 1000 : 0
        self.endList = endList
        self.isMaster = isMaster
        self.version = version
    }

    /// Fixed key order, digits and booleans only. Safe to log anywhere.
    public var summary: String {
        "version=\(Self.field(version)) mediaSequence=\(Self.field(mediaSequence)) "
            + "targetDuration=\(Self.field(targetDuration)) segmentCount=\(segmentCount) "
            + "totalDuration=\(Self.decimal(totalDuration)) endList=\(endList) isMaster=\(isMaster)"
    }

    private static func field(_ value: Double?) -> String {
        value.map(decimal) ?? "nil"
    }

    private static func field(_ value: Int?) -> String {
        value.map(String.init) ?? "nil"
    }

    private static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "nil" }
        var text = String(value)
        if !text.contains(".") { text += ".0" }
        return text
    }

    /// EXTINF value is a float optionally followed by a comma and a title.
    private static func extinfDuration(_ raw: String) -> Double? {
        let token = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return double(String(token))
    }

    private static func double(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespaces))
    }

    private static func integer(_ raw: String) -> Int? {
        Int(raw.trimmingCharacters(in: .whitespaces))
    }
}
