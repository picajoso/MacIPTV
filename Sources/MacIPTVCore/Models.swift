import Foundation

public struct Channel: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var group: String
    public var logoURL: String?
    public var tvgID: String?
    public var order: Int

    public init(id: String, name: String, url: String, group: String,
                logoURL: String? = nil, tvgID: String? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.group = group
        self.logoURL = logoURL
        self.tvgID = tvgID
        self.order = order
    }
}

public struct Programme: Hashable, Sendable {
    public var channelID: String
    public var title: String
    public var details: String?
    public var start: Date
    public var end: Date?

    public init(channelID: String, title: String, details: String? = nil, start: Date, end: Date?) {
        self.channelID = channelID
        self.title = title
        self.details = details
        self.start = start
        self.end = end
    }
}

/// Configuración de la fuente del proveedor. Las variantes que llevan
/// credenciales solo deben persistir en el Llavero.
public enum SourceConfiguration: Codable, Hashable, Sendable {
    case m3uURL(url: String, xmltvURL: String?)
    case m3uFile(path: String, xmltvURL: String?)
    case xtream(baseURL: String, username: String, password: String)

    /// Descripción sin secretos, apta para registros e interfaz: solo el origen.
    public var summary: String {
        switch self {
        case .m3uURL(let url, _):
            return "M3U: " + URLRedactor.origin(of: url)
        case .m3uFile(let path, _):
            return "Archivo: " + (path as NSString).lastPathComponent
        case .xtream(let base, _, _):
            return "Xtream: " + URLRedactor.origin(of: base)
        }
    }
}

public enum URLRedactor {
    /// Devuelve solo scheme://host:port. Elimina usuario, contrasena, ruta,
    /// consulta y fragmento, porque las rutas de IPTV suelen llevar secretos
    /// (p. ej. /live/usuario/clave/canal.ts o tokens de sesion).
    public static func origin(of raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host, !host.isEmpty else {
            return "servidor no identificable"
        }
        let scheme = (comps.scheme ?? "http").lowercased()
        if let port = comps.port {
            return scheme + "://" + host + ":" + String(port)
        }
        return scheme + "://" + host
    }

    public static func origin(of url: URL) -> String {
        origin(of: url.absoluteString)
    }
}
