import Foundation

/// Inclusive limits. Text budgets are UTF-8 bytes, not grapheme counts.
/// Rejection is atomic: neither parser returns a partial source on excess.
enum ParserLimits {
    static let m3uBytes = 8 * 1024 * 1024
    static let m3uLineBytes = 16 * 1024
    static let m3uChannels = 50_000
    static let xmltvBytes = 64 * 1024 * 1024
    static let xmltvProgrammes = 500_000
    static let xmltvFieldBytes = 64 * 1024
    static let xmltvLimitDetail = "XMLTV excede los límites de entrada"
    static let xmltvDTDDetail = "XMLTV no admite DTD ni entidades declaradas"

    /// Check before normalization, trimming or allocation of line arrays.
    /// CR and LF terminate a physical line; CRLF therefore counts once.
    static func acceptsM3U(_ text: String) -> Bool {
        var total = 0
        var line = 0
        for byte in text.utf8 {
            total += 1
            if total > m3uBytes { return false }
            if byte == 10 || byte == 13 { line = 0 }
            else {
                line += 1
                if line > m3uLineBytes { return false }
            }
        }
        return true
    }

    /// Conservative, allocation-free preflight: reject the literal DOCTYPE
    /// marker even in comments/CDATA. Ignoring NUL bytes covers UTF-16/32 in
    /// either byte order, alongside ASCII-compatible XML encodings. DTDs are
    /// unsupported so entity expansion cannot begin before delegate callbacks.
    static func containsDTD(_ data: Data) -> Bool {
        let marker: [UInt8] = Array("<!DOCTYPE".utf8)
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var matched = 0
            for byte in bytes {
                if byte == 0 { continue }
                if byte == marker[matched] {
                    matched += 1
                    if matched == marker.count { return true }
                } else {
                    matched = byte == marker[0] ? 1 : 0
                }
            }
            return false
        }
    }
}
