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
    private let session: URLSession

    /// Sesion efimera sin cache: nada de credenciales en disco.
    public init(timeout: TimeInterval = 30) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(timeout, 120)
        config.httpAdditionalHeaders = ["User-Agent": PlaybackPolicy.playlistUserAgent]
        self.session = URLSession(configuration: config)
    }

    public func fetchData(_ url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw IPTVError.unsupportedScheme(scheme: url.scheme ?? "?")
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                DiagnosticLog.record(.playlist, error: NSError(domain: "HTTP", code: http.statusCode))
                // Solo codigo y origen reducido: nunca la URL completa.
                throw IPTVError.httpStatus(code: http.statusCode,
                                           host: URLRedactor.origin(of: url))
            }
            return data
        } catch let error as IPTVError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            DiagnosticLog.record(.playlist, error: error)
            throw IPTVError.network(detail: ErrorDiagnostics.summary(error))
        }
    }

    public func fetchString(_ url: URL) async throws -> String {
        let data = try await fetchData(url)
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
        let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
        guard let text = Self.decodeText(data) else {
            throw IPTVError.network(detail: "archivo de lista no legible.")
        }
        return text
    }
}
