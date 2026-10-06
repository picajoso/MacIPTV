import Foundation

public struct ImportOutcome: Sendable {
    public var channels: [Channel]
    public var guide: XMLTVGuide?
    public var guideWarning: String?
    public var skippedCount: Int

    public init(channels: [Channel], guide: XMLTVGuide?, guideWarning: String?, skippedCount: Int) {
        self.channels = channels
        self.guide = guide
        self.guideWarning = guideWarning
        self.skippedCount = skippedCount
    }
}

/// Descarga y analiza la fuente. Si la lista llega vacia o falla la red,
/// lanza error para que la capa de estado conserve la fuente anterior.
public struct SourceImporter: Sendable {
    public let fetcher: (any ContentFetching)?

    public init(fetcher: (any ContentFetching)? = nil) {
        self.fetcher = fetcher
    }

    public func importSource(_ source: SourceConfiguration, loadGuide: Bool = true,
                             policy: NetworkPolicy = NetworkPolicy(), fileBookmark: Data? = nil) async throws -> ImportOutcome {
        let fetcher: any ContentFetching = self.fetcher ?? ContentFetcher(policy: policy)
        var playlistText: String
        var base: URL?
        var xmltvURL: URL?

        switch source {
        case .m3uURL(let url, let xml):
            guard let parsed = URL(string: url),
                  parsed.scheme?.lowercased() == "http" || parsed.scheme?.lowercased() == "https" else {
                throw IPTVError.invalidURL(reason: "la URL debe empezar por http:// o https://")
            }
            try policy.validate(parsed)
            playlistText = try await fetcher.fetchString(parsed)
            base = parsed
            xmltvURL = xml.flatMap { URL(string: $0) }
        case .m3uFile(let path, let xml):
            let saved = SavedSource(source: source, policy: policy, fileBookmark: fileBookmark)
            let url = try saved.fileURL() ?? URL(fileURLWithPath: path)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do { playlistText = try await fetcher.readFile(path: url.path) }
            catch is CancellationError { throw CancellationError() }
            catch where fileBookmark == nil && self.fetcher == nil {
                throw IPTVError.security(reason: "Vuelve a seleccionar tu lista local con «Fuente → Archivo M3U → Elegir» para autorizar su lectura.")
            }
            catch let error as CocoaError where error.code == .fileReadNoPermission {
                throw IPTVError.security(reason: "Vuelve a seleccionar tu lista local con «Fuente → Archivo M3U → Elegir» para autorizar su lectura.")
            }
            base = url
            xmltvURL = xml.flatMap { URL(string: $0) }
        case .xtream(let baseRaw, let username, let password):
            let baseURL = try XtreamEndpoints.validatedBaseURL(baseRaw)
            let m3u = try XtreamEndpoints.m3uURL(base: baseURL, username: username, password: password)
            try policy.validate(m3u)
            playlistText = try await fetcher.fetchString(m3u)
            base = m3u
            if loadGuide {
                xmltvURL = try XtreamEndpoints.xmltvURL(base: baseURL, username: username, password: password)
            }
        }

        let parsed = M3UParser.parse(playlistText, baseURL: base)
        guard !parsed.channels.isEmpty else { throw IPTVError.emptyPlaylist }
        // Consent covers media as well as the initial list. Do not infer it from
        // an HTTPS source that embeds plaintext channel or guide URLs.
        if !policy.allowHTTP && (parsed.channels.contains { URL(string: $0.url)?.scheme?.lowercased() == "http" }
            || loadGuide && xmltvURL?.scheme?.lowercased() == "http") {
            throw IPTVError.httpConsentRequired
        }

        var guide: XMLTVGuide?
        var guideWarning: String?
        if loadGuide, let xmltvURL {
            do {
                try policy.validate(xmltvURL)
                let data = try await fetcher.fetchData(xmltvURL)
                guide = try XMLTVParser.parse(data)
            } catch is CancellationError {
                // La cancelacion del usuario nunca se traga el aviso opcional.
                throw CancellationError()
            } catch IPTVError.httpConsentRequired {
                throw IPTVError.httpConsentRequired
            } catch {
                // La guia es opcional: se ignora con aviso, la lista sigue valid.
                guideWarning = (error as? LocalizedError)?.errorDescription
                    ?? "La programacion no se pudo descargar."
            }
        }
        return ImportOutcome(channels: parsed.channels, guide: guide,
                             guideWarning: guideWarning, skippedCount: parsed.skippedCount)
    }
}
