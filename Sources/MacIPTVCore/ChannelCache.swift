import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Las URLs de reproducción pueden contener secretos. Solo se escriben
/// cifradas; la clave permanece en el Llavero, fuera del archivo de caché.
public actor ChannelCache {
    public struct Snapshot: Codable, Sendable {
        public let channels: [Channel]
        public let savedAt: Date
        let sourceDigest: Data
    }

    private let directory: URL
    private var encryptionKey: SymmetricKey?

    public init(directory: URL? = nil, encryptionKey: SymmetricKey? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("es.maciptv/channel-snapshots", isDirectory: true)
        self.encryptionKey = encryptionKey
    }

    private func digest(_ source: SavedSource) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Data(SHA256.hash(data: try encoder.encode(source)))
    }

    private func key() throws -> SymmetricKey {
        if let encryptionKey { return encryptionKey }
        let context = LAContext()
        context.interactionNotAllowed = true
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "es.maciptv.channel-cache",
            kSecAttrAccount as String: "encryption-key"
        ]
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            encryptionKey = key
            return key
        }
        guard status == errSecItemNotFound else { throw CocoaError(.fileReadNoPermission) }
        let key = SymmetricKey(size: .bits256)
        var add = identity
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw CocoaError(.fileWriteNoPermission)
        }
        encryptionKey = key
        return key
    }

    public func load(sourceID: UUID, source: SavedSource) throws -> Snapshot? {
        let url = directory.appendingPathComponent(sourceID.uuidString + ".cache")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: AES.GCM.open(sealed, using: key()))
        guard snapshot.sourceDigest == (try digest(source)), !snapshot.channels.isEmpty else { return nil }
        return snapshot
    }

    public func save(channels: [Channel], sourceID: UUID, source: SavedSource) throws {
        let snapshot = Snapshot(channels: channels, savedAt: Date(), sourceDigest: try digest(source))
        let sealed = try AES.GCM.seal(JSONEncoder().encode(snapshot), using: key())
        guard let data = sealed.combined else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(sourceID.uuidString + ".cache")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(sourceID: UUID) throws {
        let url = directory.appendingPathComponent(sourceID.uuidString + ".cache")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
