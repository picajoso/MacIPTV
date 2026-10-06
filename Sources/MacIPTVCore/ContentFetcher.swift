import Foundation

/// Descarga listas y guias sin cachear en disco: algunas URLs llevan
/// credenciales o tokens y no deben quedar en la cache compartida del sistema.
public protocol ContentFetching: Sendable {
    func fetchString(_ url: URL) async throws -> String
    func fetchData(_ url: URL) async throws -> Data
    /// Lee un archivo local de solo lectura (lista M3U local).
    func readFile(path: String) async throws -> String
}

public struct ContentFetcher: ContentFetching {
    private let client: SecureHTTPClient

    /// Sesion efimera sin cache: nada de credenciales en disco.
    public init(timeout: TimeInterval = 30, policy: NetworkPolicy = NetworkPolicy()) {
        self.client = SecureHTTPClient(policy: policy, timeout: timeout)
    }

    public func fetchData(_ url: URL) async throws -> Data {
        try await fetch(url, maximumBytes: DownloadLimits.guide)
    }

    private func fetch(_ url: URL, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(PlaybackPolicy.playlistUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let result = try await client.fetch(request, maximumBytes: maximumBytes)
            guard (200...299).contains(result.response.statusCode) else {
                throw IPTVError.httpStatus(code: result.response.statusCode, host: URLRedactor.origin(of: url))
            }
            return result.data
        } catch let error as IPTVError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch {
            DiagnosticLog.record(.playlist, error: error)
            throw IPTVError.network(detail: ErrorDiagnostics.summary(error))
        }
    }

    public func fetchString(_ url: URL) async throws -> String {
        let data = try await fetch(url, maximumBytes: DownloadLimits.playlist)
        guard let text = Self.decodeText(data) else {
            throw IPTVError.network(detail: "respuesta no decodificable como texto.")
        }
        return text
    }

    /// Decodificacion compartida archivo/red: UTF-8 primero; muchas listas
    /// reales vienen en Windows-1252 y, si algun byte no existe ahi, se
    /// intenta ISO-Latin-1, que nunca falla byte a byte.
    public static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    public func readFile(path: String) async throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw IPTVError.fileMissing(path: expanded)
        }
        let url = URL(fileURLWithPath: expanded)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw IPTVError.security(reason: "Selecciona un archivo normal de lista.") }
        guard (values.fileSize ?? 0) <= DownloadLimits.playlist else { throw IPTVError.downloadTooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: DownloadLimits.playlist + 1) ?? Data()
        guard data.count <= DownloadLimits.playlist else { throw IPTVError.downloadTooLarge }
        guard let text = Self.decodeText(data) else {
            throw IPTVError.network(detail: "archivo de lista no legible.")
        }
        return text
    }
}
