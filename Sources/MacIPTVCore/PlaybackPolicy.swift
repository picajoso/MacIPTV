import Foundation

public enum PlaybackPolicy {
    /// Perfil HTTP de compatibilidad comprobado con servidores IPTV que
    /// rechazan agentes genericos. Se aplica a listas y a peticiones de AVKit.
    public static let userAgent = "VLC/3.0.21 LibVLC/3.0.21"
    /// El proveedor puede filtrar las descargas de listas de forma distinta
    /// al video. Perfil de lista comprobado por separado del de reproduccion.
    public static let playlistUserAgent = "MacIPTV/1.0"

    /// Xtream publica TS y HLS bajo la misma ruta de canal. AVKit utiliza HLS;
    /// la URL original se conserva en Channel para otros reproductores.
    public static func nativeURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? "") else { return url }
        let path = components.percentEncodedPath
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 5, parts[parts.count - 4] == "live",
              !parts[parts.count - 3].isEmpty, !parts[parts.count - 2].isEmpty,
              let file = parts.last, file.lowercased().hasSuffix(".ts") else { return url }
        let id = file.dropLast(3)
        guard !id.isEmpty, id.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return url }
        components.percentEncodedPath = String(path.dropLast(3)) + ".m3u8"
        return components.url ?? url
    }
}
