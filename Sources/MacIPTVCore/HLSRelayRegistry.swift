import Foundation

/// In-memory mapping. The same logical media sequence always has one local URL,
/// while its authorized upstream URL is refreshed with each playlist reload.
public struct HLSRelayRegistry {
    public enum Kind: String { case playlist, segment, key, other }
    private struct Resource { var url: URL; let kind: Kind; var revision: Int }
    private var resources: [String: Resource] = [:]
    private var identities: [String: String] = [:]
    private var revision = 0
    public init() {}
    public func destination(for id: String) -> URL? { resources[id]?.url }
    public func kind(for id: String) -> Kind { resources[id]?.kind ?? .other }
    public mutating func setRoot(_ url: URL) { resources["root"] = Resource(url: url, kind: .playlist, revision: revision) }

    public mutating func rewrite(_ text: String, upstream: URL, localBase: URL, playlistID: String) throws -> String {
        revision += 1
        let summary = HLSManifestSummary(text)
        var index = 0
        let uriPattern = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if !line.isEmpty && !line.hasPrefix("#") {
                let identity: String?
                if !summary.isMaster, let sequence = summary.mediaSequence,
                   sequence >= 0, sequence <= Int.max - index {
                    identity = "segment:\(playlistID):\(sequence + index)"
                } else { identity = nil }
                line = register(line, upstream: upstream, localBase: localBase,
                                identity: identity, kind: summary.isMaster ? .playlist : .segment)
                index += 1
            } else {
                let matches = uriPattern.matches(in: line, range: NSRange(line.startIndex..., in: line))
                for match in matches.reversed() {
                    guard let range = Range(match.range(at: 1), in: line) else { continue }
                    let kind: Kind = line.hasPrefix("#EXT-X-KEY") ? .key : (line.hasPrefix("#EXT-X-MAP") ? .segment : .playlist)
                    let replacement = register(String(line[range]), upstream: upstream, localBase: localBase, identity: nil, kind: kind)
                    line.replaceSubrange(range, with: replacement)
                }
            }
            lines.append(line)
        }
        // Keep recent windows (at least 100 refreshes), not an unbounded history.
        let expired = Set(resources.filter { $0.key != "root" && $0.value.revision < revision - 100 }.map(\.key))
        expired.forEach { resources.removeValue(forKey: $0) }
        identities = identities.filter { !expired.contains($0.value) }
        return lines.joined(separator: "\n")
    }

    private mutating func register(_ raw: String, upstream: URL, localBase: URL, identity: String?, kind: Kind) -> String {
        guard let url = URL(string: raw, relativeTo: upstream)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return raw }
        let key = identity ?? "resource:\(url.absoluteString)"
        let id = identities[key] ?? UUID().uuidString
        identities[key] = id
        resources[id] = Resource(url: url, kind: kind, revision: revision)
        return localBase.appendingPathComponent(id).absoluteString
    }
}
