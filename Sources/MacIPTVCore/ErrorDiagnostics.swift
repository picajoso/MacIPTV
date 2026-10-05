import Foundation

/// Diagnostico de errores seguro para mostrar en UI o logs.
///
/// Unicas fuentes de salida: dominio (solo si esta en la lista blanca),
/// codigo numerico y una categoria en espanol derivada del numero.
/// Nunca se usa localizedDescription, ni userInfo (salvo la cadena de
/// NSUnderlyingErrorKey), ni URLs, rutas, queries o credenciales.
/// Los dominios desconocidos se colapsan a "error" para no filtrar cadenas
/// arbitrarias que podrian contener datos sensibles.
public enum ErrorDiagnostics {

    /// Profundidad maxima de la cadena de errores subyacentes.
    static let maxDepth = 4

    /// Dominios cuyos nombres se consideran seguros de imprimir.
    static let whitelistedDomains: Set<String> = [
        NSURLErrorDomain,
        "AVFoundationErrorDomain",   // AVFoundationErrorDomain
        "NSCMErrorDomain",          // CoreMediaErrorDomain
        "CoreMediaErrorDomain",     // CoreMediaErrorDomain (nombre publico)
        NSOSStatusErrorDomain,      // codigos numericos genericos
        "kCFErrorDomainCFNetwork",  // kCFErrorDomainCFNetwork
        NSPOSIXErrorDomain,
    ]

    /// Resumen encadenado "dominio=codigo (categoria) <- ..." con maximo
    /// 4 eslabones via NSUnderlyingErrorKey. Ciclos se detectan y cortan.
    public static func summary(_ error: Error) -> String {
        var segments: [String] = []
        var seen: Set<ObjectIdentifier> = []
        var current: NSError? = (error as NSError)
        var depth = 0
        while let ns = current, depth < maxDepth {
            if !seen.insert(ObjectIdentifier(ns)).inserted { break }
            segments.append(describe(ns))
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return segments.isEmpty ? "error" : segments.joined(separator: " <- ")
    }

    static func describe(_ ns: NSError) -> String {
        if whitelistedDomains.contains(ns.domain) {
            return ns.domain + "=" + String(ns.code) + " (" + category(domain: ns.domain, code: ns.code) + ")"
        }
        return "error(" + String(ns.code) + ")"
    }

    /// Categoria en espanol derivada solo de (dominio, codigo numerico).
    static func category(domain: String, code: Int) -> String {
        switch domain {
        case NSURLErrorDomain:
            switch code {
            case -1009: return "sin conexion"
            case -1004: return "no se pudo conectar"
            case -1003, -1006: return "DNS no resoluble"
            case -1001: return "tiempo de espera agotado"
            case -1011: return "respuesta invalida del servidor"
            case -1200, -1201, -1202, -1203, -1205, -1206:
                return "error TLS/SSL"
            case -1022: return "conexion bloqueada por ATS"
            case -1002: return "URL no admitida"
            case -1005: return "datos incompletos"
            case -1010: return "redirecciones excesivas"
            case -1012: return "acceso denegado"
            case -1017: return "respuesta ilegible del servidor"
            case -1023: return "compresion no soportada"
            case -999: return "conexion cancelada"
            default: return "fallo de red"
            }
        case "AVFoundationErrorDomain":
            switch code {
            case -11800: return "error desconocido de reproduccion"
            case -11828: return "formato no admitido"
            case -11850: return "respuesta del servidor incorrecta"
            case -11863: return "no hay elementos reproducibles"
            case -11862: return "elemento no utilizable"
            case -11805: return "operacion no permitida"
            case -11829: return "medio no soportado"
            case -16212: return "sesion interrumpida por otra app"
            default: return "error de reproduccion"
            }
        case "NSCMErrorDomain", "CoreMediaErrorDomain":
            switch code {
            case -12752: return "flujo de medios invalido"
            case -12753: return "formato de muestra no soportado"
            case -12743: return "dato no soportado"
            case -12744: return "buffer insuficiente"
            default: return "error de medios"
            }
        case NSOSStatusErrorDomain:
            return "error de sistema"
        case "kCFErrorDomainCFNetwork":
            switch code {
            case -1003, -1006: return "DNS no resoluble"
            case -1004: return "no se pudo conectar"
            case -1001: return "tiempo de espera agotado"
            case -1022: return "conexion bloqueada por ATS"
            default: return "fallo de red"
            }
        case NSPOSIXErrorDomain:
            switch code {
            case Int(ETIMEDOUT): return "tiempo de espera agotado"
            case Int(ECONNREFUSED): return "conexion rechazada"
            case Int(ECONNRESET): return "conexion reiniciada por el servidor"
            case Int(ECONNABORTED): return "conexion abortada"
            case Int(EHOSTUNREACH): return "host inaccesible"
            case Int(ENETUNREACH), Int(ENETDOWN): return "red no disponible"
            case Int(EPIPE): return "conexion cerrada por el servidor"
            case Int(EACCES): return "permiso denegado"
            case Int(ENOMEM): return "memoria insuficiente"
            default: return "error de sistema"
            }
        default:
            return "error"
        }
    }
}
