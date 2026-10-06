import Foundation
import XCTest
@testable import MacIPTVCore

final class ParserSecurityTests: XCTestCase {
    private let limitDetail = "XMLTV excede los límites de entrada"
    private let dtdDetail = "XMLTV no admite DTD ni entidades declaradas"

    private func rejectedM3U(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = M3UParser.parse(text, baseURL: nil)
        XCTAssertTrue(result.channels.isEmpty, file: file, line: line)
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1, file: file, line: line)
    }

    private func rejectedXML(_ data: Data, detail: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try XMLTVParser.parse(data), file: file, line: line) { error in
            guard case IPTVError.xmltvInvalid(let actual) = error else {
                return XCTFail("Se esperaba xmltvInvalid", file: file, line: line)
            }
            XCTAssertEqual(actual, detail, file: file, line: line)
        }
    }

    private func xml(title: String = "Noticias", desc: String = "") -> Data {
        Data("<tv><programme channel=\"c1\" start=\"20260101090000 +0000\"><title>\(title)</title><desc>\(desc)</desc></programme></tv>".utf8)
    }

    func testM3URejectsSourceOverEightMiB() {
        let line = "#" + String(repeating: "a", count: 1022) + "\n"
        rejectedM3U(String(repeating: line, count: 8192) + "https://example.invalid/live\n")
    }

    func testM3UAcceptsSourceExactlyEightMiB() {
        let line = "#" + String(repeating: "a", count: 1022) + "\n"
        let result = M3UParser.parse(String(repeating: line, count: 8192), baseURL: nil)
        XCTAssertTrue(result.channels.isEmpty)
        XCTAssertEqual(result.skippedCount, 0)
    }

    func testM3ULineLimitCountsUTF8BeforeTrimmingAndRejectsWholeSource() {
        rejectedM3U("https://example.invalid/valid\n#" + String(repeating: "é", count: 8192))
        rejectedM3U(String(repeating: " ", count: 16385) + "\nhttps://example.invalid/live")
    }

    func testM3UAcceptsLineExactlySixteenKiBAndAllLineEndings() {
        for separator in ["\n", "\r", "\r\n"] {
            let text = "#" + String(repeating: "a", count: 16383) + separator + "https://example.invalid/live"
            XCTAssertEqual(M3UParser.parse(text, baseURL: nil).channels.count, 1)
        }
    }

    func testM3UChannelLimitRejectsWholeSource() {
        let text = (0..<50000).map { "https://example.invalid/\($0)\n" }.joined()
        XCTAssertEqual(M3UParser.parse(text, baseURL: nil).channels.count, 50000)
        rejectedM3U(text + "https://example.invalid/50000\n")
    }

    func testXMLRejectsDataOverSixtyFourMiB() {
        var data = Data("<tv><!--".utf8)
        data.append(Data(repeating: 0x61, count: 64 * 1024 * 1024))
        data.append(Data("--></tv>".utf8))
        rejectedXML(data, detail: limitDetail)
    }

    func testXMLAcceptsDataExactlySixtyFourMiB() throws {
        // Small comments avoid libxml's independent limit on a single node.
        let block = "<!--" + String(repeating: "a", count: 1017) + "-->"
        let remaining = 64 * 1024 * 1024 - 9
        var data = Data("<tv>".utf8)
        data.append(Data(String(repeating: block, count: remaining / 1024).utf8))
        data.append(Data(("<!--" + String(repeating: "a", count: remaining % 1024 - 7) + "--></tv>").utf8))
        XCTAssertEqual(data.count, 64 * 1024 * 1024)
        XCTAssertTrue(try XMLTVParser.parse(data).programmes.isEmpty)
    }

    func testXMLProgrammeLimitIncludesInvalidProgrammes() throws {
        let entries = String(repeating: "<programme/>", count: 500000)
        XCTAssertTrue(try XMLTVParser.parse(Data("<tv>\(entries)</tv>".utf8)).programmes.isEmpty)
        rejectedXML(Data("<tv>\(entries)<programme/></tv>".utf8), detail: limitDetail)
    }

    func testXMLFieldLimitsCountUTF8AndCDATAChunks() throws {
        let boundary = String(repeating: "é", count: 32768)
        let guide = try XMLTVParser.parse(xml(title: boundary, desc: boundary))
        XCTAssertEqual(guide.programmes(for: "c1").first?.title, boundary)
        XCTAssertEqual(guide.programmes(for: "c1").first?.details, boundary)
        rejectedXML(xml(title: boundary + "x"), detail: limitDetail)
        rejectedXML(xml(desc: boundary + "<![CDATA[x]]>"), detail: limitDetail)
        rejectedXML(xml(title: "<![CDATA[\(boundary)x]]>"), detail: limitDetail)
    }

    func testXMLRejectsDTDAndInternalExpansion() {
        rejectedXML(Data("<!DOCTYPE tv><tv/>".utf8), detail: dtdDetail)
        let document = "<!DOCTYPE tv [<!ENTITY a 'abc'><!ENTITY b '&a;&a;&a;'>]><tv><programme channel='c1' start='20260101090000'><title>&b;</title></programme></tv>"
        rejectedXML(Data(document.utf8), detail: dtdDetail)
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            rejectedXML(document.data(using: encoding)!, detail: dtdDetail)
        }
    }

    func testXMLRejectsExternalDTDBeforeResolution() {
        // Synthetic, nonexistent paths: never read user files or contact a server.
        rejectedXML(Data("<!DOCTYPE tv SYSTEM 'file:///nonexistent-maciptv-security.dtd'><tv/>".utf8), detail: dtdDetail)
        rejectedXML(Data("<!DOCTYPE tv [<!ENTITY x SYSTEM 'https://example.invalid/security'>]><tv/>".utf8), detail: dtdDetail)
    }

    func testOrdinaryXMLWithoutDTDStillParsesDatesEntitiesAndCDATA() throws {
        let guide = try XMLTVParser.parse(xml(title: "Noticias &amp; tiempo", desc: "<![CDATA[Información]]>"))
        let programme = try XCTUnwrap(guide.programmes(for: "c1").first)
        XCTAssertEqual(programme.title, "Noticias & tiempo")
        XCTAssertEqual(programme.details, "Información")
        XCTAssertEqual(programme.start, XMLTVDateFormatterCache.date(from: "20260101090000 +0000"))
    }
}
