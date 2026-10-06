import XCTest
@testable import MacIPTVCore

final class XtreamTests: XCTestCase {

    func testValidatedBaseAddsSchemeOnlyWhenMissing() throws {
        XCTAssertEqual(try XtreamEndpoints.validatedBaseURL("miptv.tv:8080").absoluteString,
                       "https://miptv.tv:8080/")
        XCTAssertEqual(try XtreamEndpoints.validatedBaseURL("https://miptv.tv").absoluteString,
                       "https://miptv.tv/")
    }

    func testRejectsOtherSchemesInsteadOfPrefixing() {
        XCTAssertThrowsError(try XtreamEndpoints.validatedBaseURL("ftp://miptv.tv")) { err in
            guard case IPTVError.unsupportedScheme(let scheme) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(scheme, "ftp")
        }
        XCTAssertThrowsError(try XtreamEndpoints.validatedBaseURL("rtmp://x")) { err in
            guard case IPTVError.unsupportedScheme = err else { return XCTFail("\(err)") }
        }
        XCTAssertThrowsError(try XtreamEndpoints.validatedBaseURL("")) { err in
            guard case IPTVError.invalidURL = err else { return XCTFail("\(err)") }
        }
    }

    func testRejectsMisspelledHTTPSchemeInsteadOfConnectingToHostHTTP() {
        for raw in ["http//srv.tv", "https//srv.tv", "http:/srv.tv", "https:/srv.tv"] {
            XCTAssertThrowsError(try XtreamEndpoints.validatedBaseURL(raw), raw)
        }
    }

    func testCredentialsEncodeInQuery() throws {
        let base = try XtreamEndpoints.validatedBaseURL("http://srv.tv")
        let url = try XtreamEndpoints.m3uURL(base: base, username: "us er@x", password: "p&ss=1 /z")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.path, "/get.php")
        let items = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(items["username"], "us er@x")
        XCTAssertEqual(items["password"], "p&ss=1 /z")
        XCTAssertEqual(items["type"], "m3u_plus")
        XCTAssertEqual(items["output"], "m3u8")
        XCTAssertTrue(url.absoluteString.contains("password=p%26ss%3D1%20/z"))
    }

    func testXMLTVKEndpoint() throws {
        let base = try XtreamEndpoints.validatedBaseURL("http://srv.tv")
        let url = try XtreamEndpoints.xmltvURL(base: base, username: "u", password: "p")
        XCTAssertTrue(url.absoluteString.hasPrefix("http://srv.tv/xmltv.php?"))
    }

    func testBaseRejectsEmbeddedCredentials() {
        XCTAssertThrowsError(try XtreamEndpoints.validatedBaseURL("http://user:pass@srv.tv"))
    }

    func testBasePathPrefixPreservedInEndpoints() throws {
        let base = try XtreamEndpoints.validatedBaseURL("https://srv.tv/panel/sub/")
        XCTAssertEqual(base.path, "/panel/sub")
        XCTAssertEqual(try XtreamEndpoints.m3uURL(base: base, username: "u", password: "p").path,
                       "/panel/sub/get.php")
        XCTAssertEqual(try XtreamEndpoints.xmltvURL(base: base, username: "u", password: "p").path,
                       "/panel/sub/xmltv.php")
        XCTAssertEqual(try XtreamEndpoints.playerAPIURL(base: base, username: "u", password: "p").path,
                       "/panel/sub/player_api.php")
    }

    func testPathPrefixWithSpecialCharactersIsPercentEncoded() throws {
        let base = try XtreamEndpoints.validatedBaseURL("https://srv.tv/panel%20a/b%26c")
        let url = try XtreamEndpoints.xmltvURL(base: base, username: "u", password: "p")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.path, "/panel a/b&c/xmltv.php")
        XCTAssertTrue(url.absoluteString.contains("/panel%20a/b&c/xmltv.php")
                      || url.absoluteString.contains("/panel%20a/b%26c/xmltv.php"))
    }
}

final class RedactorTests: XCTestCase {
    func testOriginStripsCredentialsAndPath() {
        let raw = "http://usuario:clave@srv.tv:8080/live/usuario/clave/123.ts?token=xyz"
        XCTAssertEqual(URLRedactor.origin(of: raw), "http://srv.tv:8080")
    }
    func testSourceSummaryHasNoSecrets() {
        let src = SourceConfiguration.xtream(baseURL: "http://srv.tv/p", username: "secretuser", password: "hunter2")
        let s = src.summary
        XCTAssertFalse(s.contains("secretuser"))
        XCTAssertFalse(s.contains("hunter2"))
        XCTAssertTrue(s.contains("http://srv.tv"))
    }
    func testUnparsableOrigin() {
        XCTAssertEqual(URLRedactor.origin(of: "no es una url"), "servidor no identificable")
    }
}
