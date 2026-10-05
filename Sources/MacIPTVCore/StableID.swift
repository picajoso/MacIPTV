import Foundation

/// Hash FNV-1a de 64 bits, determinista entre ejecuciones.
/// Se usa para generar identificadores estables de canal que sobreviven a
/// refrescos de la lista aunque cambien los tokens de la URL.
public func fnv1a64Hex(_ input: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }
    return String(format: "%016llx", hash)
}

public enum ChannelIdentity {
    /// ID estable basado en host+ruta (sin consulta ni credenciales),
    /// identificador tvg, nombre normalizado y grupo normalizado. El grupo
    /// entra en la identidad porque el mismo canal en dos grupos debe ser dos
    /// filas distintas para SwiftUI (IDs de lista unicos).
    public static func stableID(url: String, tvgID: String?, name: String, group: String? = nil) -> String {
        var key = normalizedURLKey(url)
        key += "|" + (tvgID ?? "").lowercased()
        key += "|" + name.trimmingCharacters(in: .whitespaces).lowercased()
        key += "|" + (group ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return fnv1a64Hex(key)
    }

    static func normalizedURLKey(_ url: String) -> String {
        guard var comps = URLComponents(string: url) else { return url.lowercased() }
        comps.query = nil
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        return (comps.url?.absoluteString ?? url).lowercased()
    }
}
