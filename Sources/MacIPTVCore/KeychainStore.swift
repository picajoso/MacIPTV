import Foundation
import Security
import LocalAuthentication

/// Guarda la configuracion de fuente (que puede llevar usuario y contrasena)
/// en el Llavero de macOS. Nunca en UserDefaults ni en disco plano.
public struct KeychainSourceStore: Sendable {
    public static let service = "es.maciptv.source"
    private static let account = "source"

    public init() {}

    private func baseQuery(allowAuthentication: Bool = false) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !allowAuthentication
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: KeychainSourceStore.service,
         kSecAttrAccount as String: KeychainSourceStore.account,
         kSecUseAuthenticationContext as String: context]
    }

    /// Actualizacion atomica: primero SecItemUpdate; solo se anade si no
    /// existia. Nunca se borra lo anterior antes de guardar, asi una falla
    /// no destruye la fuente guardada previa.
    public func save(_ source: SourceConfiguration) throws { try save(SavedSource(source: source)) }
    public func save(_ saved: SavedSource) throws {
        let data = try JSONEncoder().encode(saved)
        let attributes = baseQuery(allowAuthentication: true)
        let update = SecItemUpdate(attributes as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = attributes
            add[kSecValueData as String] = data
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw IPTVError.keychain(detail: "no se pudo guardar (codigo " + String(status) + ").")
            }
            return
        }
        guard update == errSecSuccess else {
            throw IPTVError.keychain(detail: "no se pudo actualizar (codigo " + String(update) + ").")
        }
    }

    public func load(allowAuthentication: Bool = false) throws -> SourceConfiguration? {
        try loadSaved(allowAuthentication: allowAuthentication)?.source
    }
    public func loadSaved(allowAuthentication: Bool = false) throws -> SavedSource? {
        var query = baseQuery(allowAuthentication: allowAuthentication)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw IPTVError.keychain(detail: "no se pudo acceder a la fuente guardada (codigo \(status)). Revisa su permiso en Acceso a Llaveros")
        }
        guard let data = item as? Data,
              let source = try? SavedSource.decode(data) else {
            throw IPTVError.keychain(detail: "la configuracion guardada no se pudo leer")
        }
        return source
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery(allowAuthentication: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IPTVError.keychain(detail: "no se pudo quitar la fuente (codigo \(status))")
        }
    }
}

/// Las llamadas de Security son sincronas. Este actor las serializa en un
/// ejecutor distinto del hilo principal, incluso cuando macOS demora la IPC.
public actor KeychainSourceRepository {
    private let store = KeychainSourceStore()
    public init() {}
    public func load(allowAuthentication: Bool = false) throws -> SourceConfiguration? {
        try Task.checkCancellation()
        return try store.load(allowAuthentication: allowAuthentication)
    }
    public func save(_ source: SourceConfiguration) throws {
        try Task.checkCancellation()
        try store.save(source)
    }
    public func loadSaved(allowAuthentication: Bool = false) throws -> SavedSource? {
        try Task.checkCancellation()
        return try store.loadSaved(allowAuthentication: allowAuthentication)
    }
    public func save(_ saved: SavedSource) throws {
        try Task.checkCancellation()
        try store.save(saved)
    }
    public func clear() throws { try store.clear() }
}
