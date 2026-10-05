import XCTest
@testable import MacIPTVCore

final class M3UParserTests: XCTestCase {

    func testCommaOutsideQuotesSeparatesHeaderAndName() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-logo="http://x/logo,a.png" group-title="General" tvg-id="uno",La Cadena, Uno
        http://srv/stream/1
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 1)
        let c = r.channels[0]
        XCTAssertEqual(c.name, "La Cadena, Uno")
        XCTAssertEqual(c.logoURL, "http://x/logo,a.png")
        XCTAssertEqual(c.group, "General")
        XCTAssertEqual(c.tvgID, "uno")
    }

    func testHeaderAttributesParsedFromFullPrefix() {
        let text = """
        #EXTINF:-1 tvg-id="a.b" group-title="G, R",Nombre
        http://h/u
        """
        let c = M3UParser.parse(text, baseURL: nil).channels[0]
        XCTAssertEqual(c.name, "Nombre")
        XCTAssertEqual(c.tvgID, "a.b")
        XCTAssertEqual(c.group, "G, R")
    }

    func testEmptyNameAfterCommaFallsBackToFileStem() {
        let text = """
        #EXTINF:-1 ,
        http://h/s
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 1)
        XCTAssertEqual(r.channels[0].name, "s")
    }

    func testNoCommaLineUsesFallbackName() {
        let text = """
        #EXTINF:-1 tvg-id="x"
        http://h/canal.m3u8
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 1)
        XCTAssertEqual(r.channels[0].name, "canal")
    }

    func testBOMAndCRLF() {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,N A\r\nhttp://h/a\r\n"
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 1)
        XCTAssertEqual(r.channels[0].name, "N A")
    }

    func testRelativeURLResolvedAgainstBase() {
        let base = URL(string: "http://prov:8080/lists/main.m3u")!
        let text = "#EXTINF:-1,X\n/live/u/p/1.ts"
        let r = M3UParser.parse(text, baseURL: base)
        XCTAssertEqual(r.channels[0].url, "http://prov:8080/live/u/p/1.ts")
    }

    func testNonHTTPSchemeSkipped() {
        let text = """
        #EXTINF:-1,A
        ftp://h/a.ts
        #EXTINF:-1,B
        rtsp://h/b
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 0)
        XCTAssertEqual(r.skippedCount, 2)
    }

    func testExtGRPOverridesGroup() {
        let text = """
        #EXTINF:-1 group-title="Viejo",N
        #EXTGRP:Nuevo
        http://h/n
        """
        let c = M3UParser.parse(text, baseURL: nil).channels[0]
        XCTAssertEqual(c.group, "Nuevo")
    }

    func testEmptyPlaylistYieldsNoChannels() {
        let r = M3UParser.parse("#EXTM3U\n", baseURL: nil)
        XCTAssertEqual(r.channels.count, 0)
    }

    func testStableIDsSurviveQueryTokenChange() {
        let text1 = "#EXTINF:-1,N\nhttp://h/s?token=aaa"
        let text2 = "#EXTINF:-1,N\nhttp://h/s?token=bbb"
        let a = M3UParser.parse(text1, baseURL: nil).channels[0]
        let b = M3UParser.parse(text2, baseURL: nil).channels[0]
        XCTAssertEqual(a.id, b.id)
    }

    func testSameChannelInTwoGroupsGetsTwoUniqueIDs() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="x" group-title="Cine",Mismo Canal
        http://h/s.ts
        #EXTINF:-1 tvg-id="x" group-title="Deportes",Mismo Canal
        http://h/s.ts
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 2)
        XCTAssertNotEqual(r.channels[0].id, r.channels[1].id)
        XCTAssertEqual(Set(r.channels.map(\.group)), ["Cine", "Deportes"])
    }

    func testIdenticalSameGroupEntryDeduplicatesAndStaysStable() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="x" group-title="Cine",Mismo Canal
        http://h/s.ts?token=1
        #EXTINF:-1 tvg-id="x" group-title="Cine",Mismo Canal
        http://h/s.ts?token=2
        """
        let r = M3UParser.parse(text, baseURL: nil)
        XCTAssertEqual(r.channels.count, 1)
        // El refresco de token no cambia la identidad.
        let r2 = M3UParser.parse(text.replacingOccurrences(of: "token=1", with: "token=9"),
                                 baseURL: nil)
        XCTAssertEqual(r.channels[0].id, r2.channels[0].id)
    }
}
