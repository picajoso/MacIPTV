import XCTest
@testable import MacIPTVCore

final class NetworkSecurityTests: XCTestCase {
    func testXtreamDefaultsToHTTPS() throws {
        XCTAssertEqual(try XtreamEndpoints.validatedBaseURL("example.test:443").scheme, "https")
    }
    func testHTTPRequiresConsentAndDowngradeIsAlwaysRejected() throws {
        let secure = NetworkPolicy()
        XCTAssertThrowsError(try secure.validate(URL(string: "http://example.test/secret")!))
        let consent = NetworkPolicy(allowHTTP: true)
        XCTAssertNoThrow(try consent.validate(URL(string: "http://example.test/a")!))
        XCTAssertThrowsError(try consent.validate(URL(string: "http://example.test/b")!, redirectedFrom: URL(string: "https://example.test/a")!))
    }
    func testNonPublicAddressesAreBlockedIncludingMappedIPv6() {
        for address in ["0.0.0.0", "127.0.0.1", "127.9.8.7", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "198.18.0.1", "224.0.0.1", "255.255.255.255", "::", "::1", "fc00::1", "fe80::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:192.168.1.1", "64:ff9b::7f00:1", "2002:7f00:1::"] {
            XCTAssertFalse(NetworkPolicy.isPublicAddress(address), address)
        }
        for address in ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"] {
            XCTAssertTrue(NetworkPolicy.isPublicAddress(address), address)
        }
    }
    func testLocalExceptionIsLimitedToExactHostAndPort() throws {
        let policy = NetworkPolicy(allowHTTP: true, localEndpoints: ["127.0.0.1:8000"])
        XCTAssertNoThrow(try policy.validate(URL(string: "http://127.0.0.1:8000/a")!))
        XCTAssertThrowsError(try policy.validate(URL(string: "http://127.0.0.1:8001/a")!))
        XCTAssertThrowsError(try policy.validate(URL(string: "http://localhost:8000/a")!))
        XCTAssertThrowsError(try policy.validate(URL(string: "file:///tmp/a")!))
    }
    func testMixedDNSAnswerFailsClosedWithoutConsent() throws {
        let policy = NetworkPolicy()
        XCTAssertThrowsError(try policy.checkedAddresses(["8.8.8.8", "127.0.0.1"], host: "example.test", port: 443))
        XCTAssertEqual(try policy.checkedAddresses(["8.8.8.8"], host: "example.test", port: 443), ["8.8.8.8"])
    }

    func testHostnameExceptionsAreRejectedEvenForPublicDNSAnswers() {
        for endpoint in ["iptv.example:8080", "localhost:8080", "iptv.local:8080"] {
            let policy = NetworkPolicy(allowHTTP: true, localEndpoints: [endpoint])
            XCTAssertThrowsError(try policy.validate(URL(string: "http://8.8.8.8/")!))
            XCTAssertThrowsError(try policy.checkedAddresses(["8.8.8.8"], host: "iptv.example", port: 8080))
            XCTAssertThrowsError(try policy.checkedAddresses(["127.0.0.1"], host: "iptv.example", port: 8080))
        }
    }

    func testLiteralExceptionCannotAuthorizeOtherAddressesOrDNSAliases() throws {
        let policy = NetworkPolicy(allowHTTP: true, localEndpoints: ["127.0.0.1:8080"])
        XCTAssertEqual(try policy.checkedAddresses(["127.0.0.1"], host: "127.0.0.1", port: 8080), ["127.0.0.1"])
        for addresses in [["127.0.0.2"], ["127.0.0.1", "169.254.169.254"], ["8.8.8.8"]] {
            XCTAssertThrowsError(try policy.checkedAddresses(addresses, host: "127.0.0.1", port: 8080))
        }
        XCTAssertThrowsError(try policy.checkedAddresses(["127.0.0.1"], host: "iptv.example", port: 8080))
        XCTAssertThrowsError(try policy.checkedAddresses(["127.0.0.1"], host: "127.0.0.1", port: 8081))
    }

    func testIPv6LiteralExceptionMatchesAddressBytesAndExactPort() throws {
        let policy = NetworkPolicy(allowHTTP: true, localEndpoints: ["[::1]:8080"])
        XCTAssertNoThrow(try policy.validate(URL(string: "http://[::1]:8080/live")!))
        XCTAssertEqual(try policy.checkedAddresses(["0:0:0:0:0:0:0:1"], host: "::1", port: 8080), ["0:0:0:0:0:0:0:1"])
        XCTAssertThrowsError(try policy.checkedAddresses(["fc00::1"], host: "::1", port: 8080))
        XCTAssertThrowsError(try policy.checkedAddresses(["::1"], host: "::1", port: 8081))
        XCTAssertThrowsError(try policy.validate(URL(string: "http://[::1]:8081/live")!))
    }

    func testMalformedLocalExceptionsFailClosed() {
        for endpoint in ["127.0.0.1", "127.0.0.1:0", "127.0.0.1:65536", "user@127.0.0.1:8080", "127.0.0.1:8080/path", "127.0.0.1:8080?x=1"] {
            let policy = NetworkPolicy(allowHTTP: true, localEndpoints: [endpoint])
            XCTAssertThrowsError(try policy.validate(URL(string: "https://example.test/")!))
            XCTAssertThrowsError(try policy.checkedAddresses(["8.8.8.8"], host: "example.test", port: 443))
        }
    }
}
