import XCTest
@testable import MacIPTVCore

final class XMLTVParserTests: XCTestCase {

    func testTimezoneOffsetsAreAbsolute() throws {
        XCTAssertEqual(XMLTVDateFormatterCache.date(from: "20260101120000 +0100"),
                       XMLTVDateFormatterCache.date(from: "20260101110000 +0000"))
        XCTAssertEqual(XMLTVDateFormatterCache.date(from: "20260101120000Z"),
                       XMLTVDateFormatterCache.date(from: "20260101120000"))
    }

    func testInvalidDatesAndTimezonesSkipped() {
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260231120000 +0000"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20261301120000"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260101250000"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260101120000 +2500"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260101120000 X"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "nofecha"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: ""))
    }

    /// Digitos Unicode (arabo-indicos, de ancho completo, superindices) pasan
    /// Character.isNumber pero Int(...) devuelve nil: deben rechazarse sin trap.
    func testUnicodeNumericDigitsRejectedWithoutTrap() {
        // Ano parcial y completo en arabigo-indico: isNumber=true, Int=nil.
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "\u{0660}\u{0662}\u{0666}\u{0664}0101120000"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "\u{0662}\u{0660}\u{0662}\u{0666}0101120000"))
        // Ancho completo (fullwidth).
        let fullwidth = "\u{FF12}\u{FF10}\u{FF12}\u{FF16}0101120000"
        XCTAssertNil(XMLTVDateFormatterCache.date(from: fullwidth))
        // Superindices.
        let superscript = "\u{00B2}\u{00B2}\u{2070}\u{2076}0101120000"
        XCTAssertNil(XMLTVDateFormatterCache.date(from: superscript))
        // Digitos Unicode en el desplazamiento de zona tambien.
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260101120000 +\u{0661}\u{0662}00"))
        XCTAssertNil(XMLTVDateFormatterCache.date(from: "20260101120000 +\u{FF11}\u{FF12}00"))
        // Sanidad: ASCII valido sigue funcionando.
        XCTAssertNotNil(XMLTVDateFormatterCache.date(from: "20260101120000 +0100"))
    }
    private func guideXML() -> Data {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20260101100000 +0000" stop="20260101110000 +0000" channel="c1">
            <title>Uno</title><desc>D1</desc></programme>
          <programme start="20260101120000 +0000" channel="c1">
            <title>Sin stop</title></programme>
          <programme start="20260102100000 +0000" stop="20260102103000 +0000" channel="c1">
            <title>Tres</title></programme>
          <programme channel="c1"><title>Sin inicio</title></programme>
          <programme start="notafecha" channel="c1"><title>Inicio ilegible</title></programme>
        </tv>
        """
        return Data(xml.utf8)
    }

    func testParseIndexesByChannelAndSorts() throws {
        let guide = try XMLTVParser.parse(guideXML())
        let list = guide.programmes(for: "c1")
        XCTAssertEqual(list.map({ p in p.title }), ["Uno", "Sin stop", "Tres"])
        XCTAssertEqual(list[0].details, "D1")
        XCTAssertNil(list[1].end)
    }

    func testMissingStopInferredFromNextStart() throws {
        let guide = try XMLTVParser.parse(guideXML())
        let sinStop = guide.programmes(for: "c1")[1]
        let mid = XMLTVDateFormatterCache.date(from: "20260101130000 +0000")!
        XCTAssertEqual(guide.nowPlaying(channelID: "c1", at: mid)?.title, "Sin stop")
        // A las 10:00 empieza "Tres", ya no se extiende "Sin stop".
        let after = XMLTVDateFormatterCache.date(from: "20260102100000 +0000")!
        XCTAssertEqual(guide.nowPlaying(channelID: "c1", at: after)?.title, "Tres")
        XCTAssertEqual(guide.effectiveEnd(of: sinStop),
                       XMLTVDateFormatterCache.date(from: "20260102100000 +0000"))
    }

    func testTwoConsecutiveMissingStopsDoNotBothExtend() throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20260101100000 +0100" channel="c1"><title>A</title></programme>
          <programme start="20260101110000 +0100" channel="c1"><title>B</title></programme>
        </tv>
        """
        let guide = try XMLTVParser.parse(Data(xml.utf8))
        let t = XMLTVDateFormatterCache.date(from: "20260101103000 +0100")!
        XCTAssertEqual(guide.nowPlaying(channelID: "c1", at: t)?.title, "A")
        let t2 = XMLTVDateFormatterCache.date(from: "20260101113000 +0100")!
        XCTAssertEqual(guide.nowPlaying(channelID: "c1", at: t2)?.title, "B")
    }

    func testLastMissingStopEndsAtLatestMatchingStart() throws {
        // Caso del enunciado: sin stop y sin siguiente -> sin fin conocido;
        // la busqueda "now" debe usar el ultimo start anterior.
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20260101090000 +0000" channel="c9"><title>Antes</title></programme>
          <programme start="20260101110000 +0000" channel="c9"><title>Actual</title></programme>
        </tv>
        """
        let guide = try XMLTVParser.parse(Data(xml.utf8))
        let t = XMLTVDateFormatterCache.date(from: "20260101120000 +0000")!
        XCTAssertEqual(guide.nowPlaying(channelID: "c9", at: t)?.title, "Actual")
        XCTAssertNil(guide.effectiveEnd(of: guide.programmes(for: "c9")[1]))
    }

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try XMLTVParser.parse(Data("<tv><programme".utf8)))
    }

    func testUpcoming() throws {
        let guide = try XMLTVParser.parse(guideXML())
        let from = XMLTVDateFormatterCache.date(from: "20260101103000 +0000")!
        let next = guide.upcoming(channelID: "c1", after: from)
        XCTAssertEqual(next.map({ p in p.title }), ["Sin stop", "Tres"])
    }
}
