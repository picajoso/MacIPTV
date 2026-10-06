import Foundation

public enum IPTVError: Error, Equatable, LocalizedError {
    case security(reason: String)
    case httpConsentRequired
    case downloadTooLarge
    case invalidURL(reason: String)
    case unsupportedScheme(scheme: String)
    /// Solo se guarda el codigo y el origen ya reducido; nunca la URL completa.
    case httpStatus(code: Int, host: String)
    case network(detail: String)
    case emptyPlaylist
    case fileMissing(path: String)
    case xmltvInvalid(detail: String)
    case keychain(detail: String)

    public var errorDescription: String? {
        switch self {
        case .security(let reason):
            return reason
        case .httpConsentRequired:
            return "Esta fuente solicita HTTP sin cifrar. Autorízalo solo si aceptas que tu suscripción pueda ser interceptada en la red."
        case .downloadTooLarge:
            return "La respuesta supera el límite de tamaño permitido."
        case .invalidURL(let reason):
            return "La direccion introducida no es valida: " + reason + "."
        case .unsupportedScheme(let scheme):
            return "El protocolo " + scheme + " no esta admitido. Usa http o https."
        case .httpStatus(let code, let host):
            return "El servidor " + host + " devolvio error " + String(code) + "."
        case .network(let detail):
            return "Fallo de conexion: " + detail + " Revisa tu red y los datos del proveedor."
        case .emptyPlaylist:
            return "La lista de canales llego vacia. Se mantiene la lista anterior."
        case .fileMissing(let path):
            return "No se encontro el archivo: " + (path as NSString).lastPathComponent + "."
        case .xmltvInvalid(let detail):
            return "La programacion XMLTV no se pudo leer: " + detail + "."
        case .keychain(let detail):
            return "Problema con el Llavero: " + detail + "."
        }
    }
}
