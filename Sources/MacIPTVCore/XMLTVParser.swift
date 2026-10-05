import Foundation

public struct XMLTVGuide: Sendable {
    public var programmes: [String: [Programme]]
    public init(programmes: [String: [Programme]]) {
        self.programmes = programmes
    }
    public func programmes(for channelID: String) -> [Programme] {
        programmes[channelID] ?? []
    }
}

public enum XMLTVDateFormatterCache {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss"
        f.isLenient = false
        return f
    }()

    /// Solo digitos ASCII 0-9. Character.isNumber aceptaria cifras arabo-
    /// indicas, de ancho completo o superindices, que Int(...) devuelve nil y
    /// provocaria un trap al forzar el unwrap.
    private static func isASCIIDigit(_ c: Character) -> Bool {
        c.isASCII && c >= "0" && c <= "9"
    }

    /// Entero de N digitos ASCII ya validados; nil ante cualquier desvio.
    private static func asciiInt(_ slice: some StringProtocol) -> Int? {
        guard slice.allSatisfy(isASCIIDigit) else { return nil }
        return Int(slice)
    }

    /// Formato XMLTV: aaaammddHHMMSS [+HHMM | -HHMM | Z]. Rechaza fechas
    /// imposibles y zonas horarias malformadas. Devuelve UTC absoluto.
    public static func date(from raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.hasSuffix("Z") { s = String(s.dropLast()) + " +0000" }
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let stamp = parts.first, stamp.count == 14,
              stamp.allSatisfy(isASCIIDigit) else { return nil }

        let digits = String(stamp)
        guard let year = asciiInt(digits.prefix(4)),
              let month = asciiInt(digits.dropFirst(4).prefix(2)),
              let day = asciiInt(digits.dropFirst(6).prefix(2)),
              let hour = asciiInt(digits.dropFirst(8).prefix(2)),
              let minute = asciiInt(digits.dropFirst(10).prefix(2)),
              let second = asciiInt(digits.dropFirst(12).prefix(2)) else { return nil }
        guard (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
              year >= 1900 else { return nil }

        var offsetSeconds = 0
        if parts.count == 2 {
            let tz = String(parts[1])
            let sign: Int
            let body: Substring
            if tz.hasPrefix("+") { sign = 1; body = tz.dropFirst() }
            else if tz.hasPrefix("-") { sign = -1; body = tz.dropFirst() }
            else { return nil }
            guard body.count == 4 || body.count == 2, body.allSatisfy(isASCIIDigit) else { return nil }
            guard let hh = asciiInt(body.prefix(2)) else { return nil }
            var mm = 0
            if body.count >= 4 {
                guard let v = asciiInt(body.dropFirst(2).prefix(2)) else { return nil }
                mm = v
            }
            guard hh <= 23 || (hh == 24 && mm == 0), mm <= 59 else { return nil }
            offsetSeconds = sign * (hh * 3600 + mm * 60)
        } else {
            // Sin zona declarada se asume UTC explicitamente.
            offsetSeconds = 0
        }

        lock.lock()
        let base = formatter.date(from: digits)
        lock.unlock()
        guard let base else { return nil }
        // Comprobacion de rango real (p. ej. 31 de febrero se descarta).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day], from: base)
        guard comps.year == year, comps.month == month, comps.day == day else { return nil }
        return base.addingTimeInterval(TimeInterval(-offsetSeconds))
    }
}

final class GuideBuilder: NSObject, XMLParserDelegate {
    var programmes: [String: [Programme]] = [:]
    private var currentChannelID: String?
    private var currentStart: Date?
    private var currentEnd: Date?
    private var currentTitle = ""
    private var currentDetails = ""
    private var capturingTitle = false
    private var capturingDetails = false
    var errorText: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "programme":
            currentChannelID = attributeDict["channel"]
            currentStart = attributeDict["start"].flatMap(XMLTVDateFormatterCache.date)
            currentEnd = attributeDict["stop"].flatMap(XMLTVDateFormatterCache.date)
            currentTitle = ""
            currentDetails = ""
        case "title":
            capturingTitle = true
            currentTitle = ""
        case "desc":
            capturingDetails = true
            currentDetails = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingTitle { currentTitle += string }
        if capturingDetails { currentDetails += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if capturingTitle, let s = String(data: CDATABlock, encoding: .utf8) { currentTitle += s }
        if capturingDetails, let s = String(data: CDATABlock, encoding: .utf8) { currentDetails += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "title":
            capturingTitle = false
        case "desc":
            capturingDetails = false
        case "programme":
            if let channelID = currentChannelID, let start = currentStart {
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = currentDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    programmes[channelID, default: []].append(Programme(
                        channelID: channelID,
                        title: title,
                        details: details.isEmpty ? nil : details,
                        start: start,
                        end: currentEnd
                    ))
                }
            }
            currentChannelID = nil
            currentStart = nil
            currentEnd = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if errorText == nil { errorText = parseError.localizedDescription }
    }
}

public enum XMLTVParser {
    public static func parse(_ data: Data) throws -> XMLTVGuide {
        var cleaned = data
        if cleaned.count >= 3, cleaned[0] == 0xEF, cleaned[1] == 0xBB, cleaned[2] == 0xBF {
            cleaned = cleaned.subdata(in: 3..<cleaned.count)
        }
        let builder = GuideBuilder()
        let parser = XMLParser(data: cleaned)
        parser.delegate = builder
        guard parser.parse() else {
            throw IPTVError.xmltvInvalid(detail: builder.errorText
                ?? parser.parserError?.localizedDescription ?? "XML malformado")
        }
        let sorted = builder.programmes.mapValues { list in
            list.sorted { $0.start < $1.start }
        }
        return XMLTVGuide(programmes: sorted)
    }
}

extension XMLTVGuide {
    /// Programa en emision para un canal en un instante dado. Si el ultimo
    /// programa no tiene stop, su fin se infiere del siguiente; asi dos
    /// entradas sin stop no quedan activas para siempre.
    public func nowPlaying(channelID: String, at date: Date) -> Programme? {
        let list = programmes(for: channelID)
        guard let idx = list.lastIndex(where: { $0.start <= date }) else { return nil }
        let p = list[idx]
        if let end = p.end {
            return date < end ? p : nil
        }
        if idx + 1 < list.count {
            return date < list[idx + 1].start ? p : nil
        }
        return p
    }

    /// Fin efectivo de un programa (stop real o inicio del siguiente).
    public func effectiveEnd(of program: Programme) -> Date? {
        if let end = program.end { return end }
        let list = programmes(for: program.channelID)
        if let idx = list.firstIndex(where: { $0.channelID == program.channelID && $0.start == program.start }),
           idx + 1 < list.count {
            return list[idx + 1].start
        }
        return nil
    }

    public func upcoming(channelID: String, after date: Date, limit: Int = 5) -> [Programme] {
        Array(programmes(for: channelID).filter { $0.start > date }.prefix(limit))
    }
}
