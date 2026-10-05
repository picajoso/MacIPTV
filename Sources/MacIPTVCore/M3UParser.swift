import Foundation

public struct M3UParseResult: Sendable {
    public var channels: [Channel]
    public var skippedCount: Int
    public init(channels: [Channel], skippedCount: Int) {
        self.channels = channels
        self.skippedCount = skippedCount
    }
}

public enum M3UParser {
    /// Analiza una lista M3U/M3U8 extendida.
    /// - base: URL de la lista, para resolver URLs relativas de stream.
    public static func parse(_ text: String, baseURL: URL?) -> M3UParseResult {
        var normalized = text
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var channels: [Channel] = []
        var emittedIDs = Set<String>()
        var skipped = 0
        var order = 0
        var pending: PendingEntry?

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                pending = parseExtINF(line)
                continue
            }
            if line.hasPrefix("#EXTGRP:") {
                let grp = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
                if !grp.isEmpty { pending?.group = grp }
                continue
            }
            if line.hasPrefix("#") { continue }

            // Linea de URL de stream: solo http/https tras resolver relativas.
            guard let url = resolveStreamURL(line, base: baseURL) else {
                skipped += 1
                pending = nil
                continue
            }
            let name = pending?.name ?? fallbackName(from: url)
            if name.isEmpty {
                skipped += 1
                pending = nil
                continue
            }
            let group = pending?.group.flatMap { $0.isEmpty ? nil : $0 } ?? "Sin grupo"
            let id = ChannelIdentity.stableID(url: url.absoluteString,
                                              tvgID: pending?.tvgID, name: name, group: group)
            // Duplicado exacto dentro del mismo grupo: una sola fila.
            guard !emittedIDs.contains(id) else {
                pending = nil
                continue
            }
            emittedIDs.insert(id)
            channels.append(Channel(
                id: id,
                name: name,
                url: url.absoluteString,
                group: group,
                logoURL: pending?.logo,
                tvgID: pending?.tvgID,
                order: order
            ))
            order += 1
            pending = nil
        }
        return M3UParseResult(channels: channels, skippedCount: skipped)
    }

    struct PendingEntry {
        var name: String
        var logo: String?
        var group: String?
        var tvgID: String?
    }

    /// Separa cabecera de nombre en la PRIMERA coma fuera de comillas del
    /// EXTINF original. El nombre es todo el sufijo tras esa coma, incluidos
    /// los demas caracteres (las comas del propio nombre se conservan).
    private static func parseExtINF(_ line: String) -> PendingEntry? {
        var inQuotes = false
        var separator: String.Index?
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes { separator = idx; break }
            line.formIndex(after: &idx)
        }
        guard let sep = separator else { return nil }
        let header = String(line[line.startIndex..<sep])
        let name = String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }

        var entry = PendingEntry(name: name, logo: nil, group: nil, tvgID: nil)
        let attrs = attributes(in: header)
        if let v = attrs["tvg-logo"], !v.isEmpty { entry.logo = v }
        if let v = attrs["group-title"], !v.isEmpty { entry.group = v }
        if let v = attrs["tvg-id"], !v.isEmpty { entry.tvgID = v }
        return entry
    }

    /// Extrae atributos clave="valor" y clave=valor del encabezado EXTINF.
    static func attributes(in header: String) -> [String: String] {
        var result: [String: String] = [:]
        let scalars = Array(header)
        var i = 0
        while i < scalars.count {
            var key = ""
            while i < scalars.count, scalars[i] != "=", scalars[i] != " ", scalars[i] != "," { key.append(scalars[i]); i += 1 }
            guard i < scalars.count, scalars[i] == "=" else { i += 1; continue }
            i += 1
            var value = ""
            if i < scalars.count, scalars[i] == "\"" {
                i += 1
                while i < scalars.count, scalars[i] != "\"" { value.append(scalars[i]); i += 1 }
                if i < scalars.count { i += 1 }
            } else {
                while i < scalars.count, scalars[i] != " ", scalars[i] != "," { value.append(scalars[i]); i += 1 }
            }
            if !key.isEmpty { result[key.lowercased()] = value }
        }
        return result
    }

    /// Solo admite flujos http/https, absolutos o relativos a la lista.
    static func resolveStreamURL(_ raw: String, base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var candidate: URL?
        if let url = URL(string: trimmed), url.scheme != nil {
            candidate = url
        } else if let base, let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL {
            candidate = resolved
        }
        guard let url = candidate,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private static func fallbackName(from url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        return last.isEmpty ? url.host ?? "" : last
    }
}
