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
    public let fetcher: any ContentFetching

    public init(fetcher: any ContentFetching = ContentFetcher()) {
        self.fetcher = fetcher
    }

    public func importSource(_ source: SourceConfiguration, loadGuide: Bool = true) async throws -> ImportOutcome {
        var playlistText: String
        var base: URL?
        var xmltvURL: URL?

        switch source {
        case .m3uURL(let url, let xml):
            guard let parsed = URL(string: url),
                  parsed.scheme?.lowercased() == "http" || parsed.scheme?.lowercased() == "https" else {
                throw IPTVError.invalidURL(reason: "la URL debe empezar por http:// o https://")
            }
            playlistText = try await fetcher.fetchString(parsed)
            base = parsed
            xmltvURL = xml.flatMap { URL(string: $0) }
        case .m3uFile(let path, let xml):
            playlistText = try await fetcher.readFile(path: path)
            base = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            xmltvURL = xml.flatMap { URL(string: $0) }
        case .xtream(let baseRaw, let username, let password):
            let baseURL = try XtreamEndpoints.validatedBaseURL(baseRaw)
            let m3u = try XtreamEndpoints.m3uURL(base: baseURL, username: username, password: password)
            playlistText = try await fetcher.fetchString(m3u)
            base = m3u
            if loadGuide {
                xmltvURL = try XtreamEndpoints.xmltvURL(base: baseURL, username: username, password: password)
            }
        }

        let parsed = M3UParser.parse(playlistText, baseURL: base)
        guard !parsed.channels.isEmpty else { throw IPTVError.emptyPlaylist }

        var guide: XMLTVGuide?
        var guideWarning: String?
        if loadGuide, let xmltvURL {
            do {
                let data = try await fetcher.fetchData(xmltvURL)
                guide = try XMLTVParser.parse(data)
            } catch is CancellationError {
                // La cancelacion del usuario nunca se traga el aviso opcional.
                throw CancellationError()
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
