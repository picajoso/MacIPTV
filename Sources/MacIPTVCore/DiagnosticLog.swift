import Foundation

/// Registro local acotado. Solo acepta etapas fijas y errores redactados;
/// nunca guarda URLs, nombres de canales ni configuraciones de proveedor.
public enum DiagnosticLog {
    public enum Stage: String { case playlist, playback }
    /// Eventos fijos de reproduccion. Solo se aceptan estos casos; nunca cadenas arbitrarias.
    public enum PlaybackEvent: String { case started, stalled, ended, reconnecting, recovered, exhausted }
    private static let lock = NSLock()
    public static var fileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MacIPTV/diagnostics.log")
    }
    public static func record(_ stage: Stage, error: Error) {
        append(ISO8601DateFormatter().string(from: Date()) + " " + stage.rawValue + " " + ErrorDiagnostics.summary(error))
    }
    public static func record(_ event: PlaybackEvent) {
        append(ISO8601DateFormatter().string(from: Date()) + " playback " + event.rawValue)
    }
    private static func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n").suffix(199).map(String.init)
        lines.append(line)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch { /* El diagnostico no puede impedir reproducir o importar. */ }
    }
}
