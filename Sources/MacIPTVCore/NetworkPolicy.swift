import Foundation
import Darwin

/// Permission is attached to a source, never inferred from provider content.
public struct NetworkPolicy: Codable, Hashable, Sendable {
    public var allowHTTP: Bool
    public var localEndpoints: Set<String>
    public init(allowHTTP: Bool = false, localEndpoints: Set<String> = []) {
        self.allowHTTP = allowHTTP
        self.localEndpoints = localEndpoints
    }
    public static func endpointKey(host: String, port: UInt16) -> String {
        let host = canonicalHost(host)
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
    static func canonicalHost(_ host: String) -> String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    /// Persisted policies are also checked: a legacy hostname permission must
    /// never turn a later DNS answer into permission for arbitrary private IPs.
    private func validateLocalExceptions() throws {
        for endpoint in localEndpoints {
            guard let components = URLComponents(string: "http://" + endpoint),
                  let rawHost = components.host,
                  Self.isNumericAddress(Self.canonicalHost(rawHost)),
                  let rawPort = components.port, let port = UInt16(exactly: rawPort), port > 0,
                  components.user == nil, components.password == nil,
                  components.path.isEmpty, components.query == nil, components.fragment == nil,
                  endpoint == Self.endpointKey(host: rawHost, port: port) else {
                throw IPTVError.security(reason: "Las excepciones locales requieren una dirección IP literal y un puerto válido.")
            }
        }
    }

    private static func sameAddress(_ lhs: String, _ rhs: String) -> Bool {
        var left4 = in_addr(), right4 = in_addr()
        if inet_pton(AF_INET, lhs, &left4) == 1, inet_pton(AF_INET, rhs, &right4) == 1 {
            return left4.s_addr == right4.s_addr
        }
        var left6 = in6_addr(), right6 = in6_addr()
        guard inet_pton(AF_INET6, lhs, &left6) == 1, inet_pton(AF_INET6, rhs, &right6) == 1 else { return false }
        return withUnsafeBytes(of: &left6) { left in
            withUnsafeBytes(of: &right6) { right in left.elementsEqual(right) }
        }
    }
    public func validate(_ url: URL, redirectedFrom previous: URL? = nil) throws {
        try validateLocalExceptions()
        guard url.absoluteString.utf8.count <= 8192,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let rawHost = components.host, !rawHost.isEmpty,
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.fragment == nil else { throw IPTVError.security(reason: "Dirección de red no admitida.") }
        if scheme == "http" && !allowHTTP { throw IPTVError.httpConsentRequired }
        if previous?.scheme?.lowercased() == "https" && scheme != "https" {
            throw IPTVError.security(reason: "Se ha bloqueado una redirección de HTTPS a HTTP.")
        }
        let host = Self.canonicalHost(rawHost)
        guard !host.contains("%"), let port = UInt16(exactly: components.port ?? (scheme == "https" ? 443 : 80)), port > 0 else {
            throw IPTVError.security(reason: "Servidor o puerto no admitido.")
        }
        let localAllowed = localEndpoints.contains(Self.endpointKey(host: host, port: port))
        if Self.isNumericAddress(host) && !Self.isPublicAddress(host) && !localAllowed {
            throw IPTVError.security(reason: "Se ha bloqueado un destino de red local no autorizado.")
        }
        if (host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")) && !localAllowed {
            throw IPTVError.security(reason: "Este servidor local requiere autorización explícita.")
        }
    }
    public func checkedAddresses(_ addresses: [String], host: String, port: UInt16) throws -> [String] {
        try validateLocalExceptions()
        guard !addresses.isEmpty else { throw URLError(.cannotFindHost) }
        let host = Self.canonicalHost(host)
        if Self.isNumericAddress(host), !addresses.allSatisfy({ Self.sameAddress(host, $0) }) {
            throw IPTVError.security(reason: "La dirección de conexión no coincide con la IP solicitada.")
        }
        let localAllowed = localEndpoints.contains(Self.endpointKey(host: host, port: port))
        guard addresses.allSatisfy({ Self.isNumericAddress($0) && (Self.isPublicAddress($0) || localAllowed) }) else {
            throw IPTVError.security(reason: "La resolución DNS incluye un destino interno no autorizado.")
        }
        return addresses
    }
    static func isNumericAddress(_ address: String) -> Bool {
        var v4 = in_addr(); var v6 = in6_addr()
        return inet_pton(AF_INET, address, &v4) == 1 || inet_pton(AF_INET6, address, &v6) == 1
    }
    public static func isPublicAddress(_ address: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            let value = UInt32(bigEndian: v4.s_addr)
            let a = value >> 24, b = (value >> 16) & 255, c = (value >> 8) & 255
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a == 169 && b == 254 || a == 172 && (16...31).contains(b) || a == 192 && b == 168 { return false }
            if a == 192 && b == 0 && (c == 0 || c == 2) || a == 192 && b == 88 && c == 99 { return false }
            if a == 198 && (b == 18 || b == 19) || a == 198 && b == 51 && c == 100 || a == 203 && b == 0 && c == 113 { return false }
            return true
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, address, &v6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &v6) { Array($0) }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 {
            return isPublicAddress(bytes[12...15].map(String.init).joined(separator: "."))
        }
        // Only global unicast, excluding transition/special/documentation ranges.
        guard bytes[0] & 0xe0 == 0x20 else { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x02 { return false } // 6to4 can embed private IPv4
        if bytes[0] == 0x20 && bytes[1] == 0x01 {
            if bytes[2] < 2 || bytes[2] == 0x0d && bytes[3] == 0xb8 { return false }
        }
        if bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0 { return false }
        return true
    }
}

public enum DownloadLimits {
    public static let playlist = 8 * 1024 * 1024
    public static let guide = 64 * 1024 * 1024
    public static let manifest = 512 * 1024
    public static let segment = 32 * 1024 * 1024
    public static let key = 4096
}
