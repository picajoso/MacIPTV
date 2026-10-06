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

    public mutating func rewrite(_ text: String, upstream: URL, localBase: URL, playlistID: String, policy: NetworkPolicy = NetworkPolicy()) throws -> String {
        // Invalid manifests must not leave partial destinations or revisions.
        var updated = self
        guard text.utf8.count <= DownloadLimits.manifest else { throw IPTVError.downloadTooLarge }
        let output = try updated.rewriteManifest(text, upstream: upstream, localBase: localBase, playlistID: playlistID, policy: policy)
        guard updated.resources.count <= 10000 else { throw IPTVError.security(reason: "Demasiados recursos en la lista HLS.") }
        self = updated
        return output
    }

    private mutating func rewriteManifest(_ text: String, upstream: URL, localBase: URL, playlistID: String, policy: NetworkPolicy) throws -> String {
        revision += 1
        // A variant can be reloaded indefinitely without reloading its master.
        // Its own refresh must keep the route alive, not just its segments.
        if var playlist = resources[playlistID] {
            playlist.url = upstream
            playlist.revision = revision
            resources[playlistID] = playlist
        }
        let summary = HLSManifestSummary(text)
        var index = 0
        var pendingRange: (length: Int, offset: Int?, lineIndex: Int)?
        var previousRange: (url: URL, end: Int)?
        let uriPattern = try NSRegularExpression(pattern: "URI=\"([^\"]+)\"")
        let uriAssignment = try NSRegularExpression(pattern: "URI\\s*=", options: .caseInsensitive)
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.hasPrefix("#EXT-X-BYTERANGE:") {
                let value = line.dropFirst("#EXT-X-BYTERANGE:".count)
                let parts = value.split(separator: "@", omittingEmptySubsequences: false)
                guard pendingRange == nil, parts.count == 1 || parts.count == 2,
                      let length = Int(parts[0]), length > 0 else { throw URLError(.badServerResponse) }
                var offset: Int?
                if parts.count == 2 {
                    guard let parsed = Int(parts[1]), parsed >= 0 else { throw URLError(.badServerResponse) }
                    offset = parsed
                }
                pendingRange = (length, offset, lines.count)
            }
            if !line.isEmpty && !line.hasPrefix("#") {
                if let range = pendingRange {
                    guard let resource = URL(string: line, relativeTo: upstream)?.absoluteURL else {
                        throw URLError(.badServerResponse)
                    }
                    let offset: Int
                    if let explicit = range.offset { offset = explicit }
                    else {
                        guard let previousRange, previousRange.url == resource else { throw URLError(.badServerResponse) }
                        offset = previousRange.end
                    }
                    guard offset <= Int.max - range.length else { throw URLError(.badServerResponse) }
                    // Sequence-based local URLs differ even when upstream ranges
                    // share a file. Preserve the offset before changing the URI.
                    lines[range.lineIndex] = "#EXT-X-BYTERANGE:\(range.length)@\(offset)"
                    previousRange = (resource, offset + range.length)
                    pendingRange = nil
                } else {
                    previousRange = nil
                }
                let identity: String?
                if !summary.isMaster, let sequence = summary.mediaSequence,
                   sequence >= 0, sequence <= Int.max - index {
                    identity = "segment:\(playlistID):\(sequence + index)"
                } else { identity = nil }
                line = try register(line, upstream: upstream, localBase: localBase,
                                    identity: identity, kind: summary.isMaster ? .playlist : .segment, policy: policy)
                index += 1
            } else {
                let matches = uriPattern.matches(in: line, range: NSRange(line.startIndex..., in: line))
                // AVPlayer must never receive an alternate spelling that bypassed
                // rewriting. Accept the HLS quoted, uppercase URI syntax only.
                let assignments = uriAssignment.matches(in: line, range: NSRange(line.startIndex..., in: line))
                guard assignments.count == matches.count else {
                    throw IPTVError.security(reason: "Atributo URI HLS no admitido.")
                }
                for match in matches.reversed() {
                    guard let range = Range(match.range(at: 1), in: line) else { continue }
                    let tag = line.components(separatedBy: ":").first ?? ""
                    let kind: Kind
                    switch tag {
                    case "#EXT-X-KEY", "#EXT-X-SESSION-KEY": kind = .key
                    case "#EXT-X-MAP", "#EXT-X-PART", "#EXT-X-PRELOAD-HINT": kind = .segment
                    case "#EXT-X-SESSION-DATA": kind = .other
                    case "#EXT-X-CONTENT-STEERING":
                        throw IPTVError.security(reason: "La selección dinámica de servidores HLS no está admitida.")
                    default: kind = .playlist
                    }
                    let replacement = try register(String(line[range]), upstream: upstream, localBase: localBase, identity: nil, kind: kind, policy: policy)
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

    private mutating func register(_ raw: String, upstream: URL, localBase: URL, identity: String?, kind: Kind, policy: NetworkPolicy) throws -> String {
        guard let url = URL(string: raw, relativeTo: upstream)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw IPTVError.security(reason: "Recurso HLS con protocolo no admitido.") }
        try policy.validate(url)
        guard resources.count < 10000 || identity.flatMap({ identities[$0] }) != nil || identities["resource:\(url.absoluteString)"] != nil else {
            throw IPTVError.security(reason: "Demasiados recursos en la lista HLS.")
        }
        let key = identity ?? "resource:\(url.absoluteString)"
        let id = identities[key] ?? UUID().uuidString
        identities[key] = id
        resources[id] = Resource(url: url, kind: kind, revision: revision)
        return localBase.appendingPathComponent(id).absoluteString
    }
}
