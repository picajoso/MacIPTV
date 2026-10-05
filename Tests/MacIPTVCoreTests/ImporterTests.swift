import XCTest
@testable import MacIPTVCore

/// Fixture en memoria: sin red real en los tests.
struct StubFetcher: ContentFetching {
    var texts: [String: String] = [:]
    var datas: [String: Data] = [:]
    var files: [String: String] = [:]
    var networkError: Error?

    func fetchString(_ url: URL) async throws -> String {
        if let networkError { throw networkError }
        guard let t = texts[url.absoluteString] else {
            throw IPTVError.httpStatus(code: 404, host: URLRedactor.origin(of: url))
        }
        return t
    }
    func fetchData(_ url: URL) async throws -> Data {
        if let networkError { throw networkError }
        guard let d = datas[url.absoluteString] else {
            throw IPTVError.httpStatus(code: 404, host: URLRedactor.origin(of: url))
        }
        return d
    }
    func readFile(path: String) async throws -> String {
        guard let t = files[path] else { throw IPTVError.fileMissing(path: path) }
        return t
    }
}

final class ImporterTests: XCTestCase {

    // Decodificacion real de rawData compartida entre red y archivo.
    func testDecodeTextPrefersUTF8ThenCP1252ThenLatin1() {
        let utf8 = Data("Café ☕".utf8)
        XCTAssertEqual(ContentFetcher.decodeText(utf8), "Café ☕")
        // CP1252: 0xE9 es 'é'; no es UTF-8 valido.
        let cp = Data([0x43, 0x61, 0x66, 0xE9])
        XCTAssertEqual(ContentFetcher.decodeText(cp), "Café")
        // 0x80 esta indefinido en CP1252 (nil alli), pero euro en CP1252...
        // 0x80 = EUR en CP1252; 0x81 es indefinido -> cae a Latin-1 sin trap.
        XCTAssertEqual(ContentFetcher.decodeText(Data([0x80])), "\u{20AC}")
        XCTAssertNotNil(ContentFetcher.decodeText(Data([0x81, 0x41])))
        // Secuencia UTF-8 invalida con byte latin1: nunca nil por Latin-1.
        XCTAssertNotNil(ContentFetcher.decodeText(Data([0xC3, 0x41])))
    }

    func testReadFileDecodesCP1252Bytes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("maciptv-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("lista.m3u")
        // "Cine Práctico" en CP1252: acento agudo = 0xE1.
        let bytes = Data([0x43, 0x69, 0x6E, 0x65, 0x20, 0x50, 0x72, 0xE1, 0x63, 0x74, 0x69, 0x63, 0x6F])
        try bytes.write(to: file)
        let text = try await ContentFetcher().readFile(path: file.path)
        XCTAssertEqual(text, "Cine Práctico")
    }

    private let playlist = """
    #EXTM3U
    #EXTINF:-1 tvg-id="a" group-title="G",Canal A
    http://h/a.m3u8
    """

    func testM3UURLWithGuide() async throws {
        let guideXML = Data("""
        <?xml version="1.0"?><tv>
        <programme start="20260101100000 +0000" stop="20260101110000 +0000" channel="a"><title>T</title></programme>
        </tv>
        """.utf8)
        let fetcher = StubFetcher(texts: ["http://list.tv/p.m3u": playlist],
                                  datas: ["http://list.tv/xmltv.php": guideXML])
        let importer = SourceImporter(fetcher: fetcher)
        let out = try await importer.importSource(.m3uURL(url: "http://list.tv/p.m3u",
                                                          xmltvURL: "http://list.tv/xmltv.php"))
        XCTAssertEqual(out.channels.count, 1)
        XCTAssertEqual(out.guide?.programmes(for: "a").count, 1)
        XCTAssertNil(out.guideWarning)
    }

    func testEmptyPlaylistThrowsAndPreservesNothingChanged() async {
        let fetcher = StubFetcher(texts: ["http://list.tv/p.m3u": "#EXTM3U\n"])
        let importer = SourceImporter(fetcher: fetcher)
        do {
            _ = try await importer.importSource(.m3uURL(url: "http://list.tv/p.m3u", xmltvURL: nil))
            XCTFail("deberia fallar")
        } catch IPTVError.emptyPlaylist {
            // El estado superior conserva la fuente anterior.
        } catch {
            XCTFail("error inesperado \(error)")
        }
    }

    func testMalformedGuideIsWarningOnly() async throws {
        let fetcher = StubFetcher(texts: ["http://list.tv/p.m3u": playlist],
                                  datas: ["http://list.tv/xmltv": Data("<tv><x".utf8)])
        let importer = SourceImporter(fetcher: fetcher)
        let out = try await importer.importSource(.m3uURL(url: "http://list.tv/p.m3u",
                                                          xmltvURL: "http://list.tv/xmltv"))
        XCTAssertEqual(out.channels.count, 1)
        XCTAssertNil(out.guide)
        XCTAssertNotNil(out.guideWarning)
    }

    func testGuideDownloadFailureIsWarningOnly() async throws {
        let fetcher = StubFetcher(texts: ["http://list.tv/p.m3u": playlist])
        let importer = SourceImporter(fetcher: fetcher)
        let out = try await importer.importSource(.m3uURL(url: "http://list.tv/p.m3u",
                                                          xmltvURL: "http://list.tv/missing.xml"))
        XCTAssertEqual(out.channels.count, 1)
        XCTAssertNotNil(out.guideWarning)
        // El aviso nunca contiene la URL con credenciales.
        XCTAssertFalse(out.guideWarning!.contains("xmltv?user"))
    }

    func testNetworkErrorHostOnly() async throws {
        let fetcher = StubFetcher(networkError: IPTVError.httpStatus(code: 503, host: "http://srv.tv"))
        let importer = SourceImporter(fetcher: fetcher)
        do {
            _ = try await importer.importSource(.m3uURL(url: "http://srv.tv/p.m3u?u=x&p=y", xmltvURL: nil))
            XCTFail("deberia fallar")
        } catch let IPTVError.httpStatus(code, host) {
            XCTAssertEqual(code, 503)
            XCTAssertEqual(host, "http://srv.tv")
        }
    }

    func testLocalFileImport() async throws {
        let fetcher = StubFetcher(files: ["/tmp/lista.m3u": playlist])
        let importer = SourceImporter(fetcher: fetcher)
        let out = try await importer.importSource(.m3uFile(path: "/tmp/lista.m3u", xmltvURL: nil))
        XCTAssertEqual(out.channels.count, 1)
    }

    func testFileMissing() async {
        let importer = SourceImporter(fetcher: StubFetcher())
        await XCTAssertThrowsErrorAsync(try await importer.importSource(.m3uFile(path: "/nada.m3u", xmltvURL: nil)))
    }

    func testXtreamImportUsesEndpoints() async throws {
        let m3uKey = "http://srv.tv/get.php?username=u&password=p&type=m3u_plus&output=m3u8"
        let xmlKey = "http://srv.tv/xmltv.php?username=u&password=p"
        let fetcher = StubFetcher(texts: [m3uKey: playlist],
                                  datas: [xmlKey: Data("<?xml version=\"1.0\"?><tv></tv>".utf8)])
        let importer = SourceImporter(fetcher: fetcher)
        let out = try await importer.importSource(.xtream(baseURL: "srv.tv", username: "u", password: "p"))
        XCTAssertEqual(out.channels.count, 1)
        XCTAssertNotNil(out.guide)
    }

    func testFTPSourceRejected() async {
        let importer = SourceImporter(fetcher: StubFetcher())
        await XCTAssertThrowsErrorAsync(try await importer.importSource(.m3uURL(url: "ftp://h/l.m3u", xmltvURL: nil)))
    }
}

extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> some Sendable,
                                   file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("se esperaba error", file: file, line: line)
        } catch {
            // correcto
        }
    }
}
