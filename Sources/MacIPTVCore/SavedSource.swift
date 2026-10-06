import Foundation

/// Stored only in Keychain, including source-specific consent and file bookmark.
public struct SavedSource: Codable, Hashable, Sendable {
    public var source: SourceConfiguration
    public var policy: NetworkPolicy
    public var fileBookmark: Data?
    public init(source: SourceConfiguration, policy: NetworkPolicy = NetworkPolicy(), fileBookmark: Data? = nil) {
        self.source = source; self.policy = policy; self.fileBookmark = fileBookmark
    }
    public static func decode(_ data: Data) throws -> SavedSource {
        if let saved = try? JSONDecoder().decode(SavedSource.self, from: data) { return saved }
        var source = try JSONDecoder().decode(SourceConfiguration.self, from: data)
        // Legacy bare Xtream hosts meant HTTP. Preserve that meaning, but not consent.
        if case .xtream(let base, let user, let password) = source, !base.contains("://") {
            source = .xtream(baseURL: "http://" + base, username: user, password: password)
        }
        return SavedSource(source: source)
    }
    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public func fileURL() throws -> URL? {
        guard case .m3uFile(let path, _) = source else { return nil }
        guard let fileBookmark else { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        var stale = false
        return try URL(resolvingBookmarkData: fileBookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
