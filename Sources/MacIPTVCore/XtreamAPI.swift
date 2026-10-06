import Foundation

public enum XtreamEndpoints {
    /// Valida la direccion base. Anade esquema https por defecto SOLO si el
    /// texto no trae ninguno; un esquema explicito debe ser http o https.
    public static func validatedBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw IPTVError.invalidURL(reason: "campo vacio") }
        let lower = trimmed.lowercased()
        guard !lower.hasPrefix("http//"), !lower.hasPrefix("https//"),
              !(lower.hasPrefix("http:/") && !lower.hasPrefix("http://")),
              !(lower.hasPrefix("https:/") && !lower.hasPrefix("https://")) else {
            throw IPTVError.invalidURL(reason: "usa http:// o https://, incluyendo los dos puntos")
        }
        let hasExplicitScheme = trimmed.lowercased().contains("://")
        let candidate = hasExplicitScheme ? trimmed : "https://" + trimmed
        guard var comps = URLComponents(string: candidate) else {
            throw IPTVError.invalidURL(reason: "no se puede analizar")
        }
        guard let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw IPTVError.unsupportedScheme(scheme: comps.scheme ?? "?")
        }
        guard comps.host != nil, !(comps.host!.isEmpty) else {
            throw IPTVError.invalidURL(reason: "falta el nombre del servidor")
        }
        guard comps.user == nil && comps.password == nil else {
            throw IPTVError.invalidURL(reason: "no incluyas usuario en la direccion")
        }
        // Se conserva el prefijo de ruta (p. ej. /panel/sub): muchos servidores
        // montan el backend Xtream bajo un subdirectorio. Sin ruta queda raiz.
        let path = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = path.isEmpty ? "/" : path
        comps.query = nil
        comps.fragment = nil
        guard let url = comps.url else { throw IPTVError.invalidURL(reason: "no se puede construir") }
        return url
    }

    private static func query(_ items: [(String, String)]) -> [URLQueryItem] {
        items.map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    /// Rutas normalizadas validas para la RFC 3986; se percent-codean solas.
    private static func endpointURL(base: URL, endpoint: String, items: [(String, String)]) throws -> URL {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: true)!
        let prefix = base.path == "/" ? "" : base.path
        comps.path = prefix + endpoint
        comps.queryItems = query(items)
        guard let url = comps.url else { throw IPTVError.invalidURL(reason: "no se puede construir la URL") }
        return url
    }

    /// get.php con m3u_plus: conserva grupo, logo y tvg-id, y HLS para AVKit.
    public static func m3uURL(base: URL, username: String, password: String) throws -> URL {
        try endpointURL(base: base, endpoint: "/get.php", items: [
            ("username", username),
            ("password", password),
            ("type", "m3u_plus"),
            ("output", "m3u8"),
        ])
    }

    public static func xmltvURL(base: URL, username: String, password: String) throws -> URL {
        try endpointURL(base: base, endpoint: "/xmltv.php", items: [("username", username), ("password", password)])
    }

    public static func playerAPIURL(base: URL, username: String, password: String) throws -> URL {
        try endpointURL(base: base, endpoint: "/player_api.php", items: [("username", username), ("password", password)])
    }
}
