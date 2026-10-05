import XCTest
@testable import MacIPTVCore

private let secretPhrase = "SUPERSecretToken-NOAPARECER"

/// NSError con userInfo controlado y localizedDescription con secretos,
/// para comprobar que summary() nunca los copia.
private final class CustomError: NSError, @unchecked Sendable {
    private let info: [String: Any]
    init(domain: String, code: Int, userInfo info: [String: Any]) {
        self.info = info
        super.init(domain: domain, code: code, userInfo: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var localizedDescription: String { return secretPhrase }
    override var userInfo: [String: Any] { return info }
}

/// Error cuyo underlying es el mismo objeto: obliga a cortar el ciclo.
private final class SelfReferencingError: NSError, @unchecked Sendable {
    init() { super.init(domain: NSURLErrorDomain, code: -1009, userInfo: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var userInfo: [String: Any] { return [NSUnderlyingErrorKey: self] }
}

final class ErrorDiagnosticsTests: XCTestCase {

    private func ns(_ domain: String, _ code: Int, _ underlying: NSError? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let underlying { info[NSUnderlyingErrorKey] = underlying }
        return NSError(domain: domain, code: code, userInfo: info)
    }

    func testURLOfflineDNSAndTimeoutCategories() {
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1009)),
                       "NSURLErrorDomain=-1009 (sin conexion)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1003)),
                       "NSURLErrorDomain=-1003 (DNS no resoluble)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1001)),
                       "NSURLErrorDomain=-1001 (tiempo de espera agotado)")
    }

    func testTLSThirdPartyATSAndUnsupportedURL() {
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1200)),
                       "NSURLErrorDomain=-1200 (error TLS/SSL)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1022)),
                       "NSURLErrorDomain=-1022 (conexion bloqueada por ATS)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1002)),
                       "NSURLErrorDomain=-1002 (URL no admitida)")
        // -1011 es respuesta invalida del servidor, no tiempo de espera.
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1011)),
                       "NSURLErrorDomain=-1011 (respuesta invalida del servidor)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -1001)),
                       "NSURLErrorDomain=-1001 (tiempo de espera agotado)")
        // Codigo NSURLError desconocido -> categoria generica, nunca la cadena cruda.
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSURLErrorDomain, -7777)),
                       "NSURLErrorDomain=-7777 (fallo de red)")
    }

    func testCoreMediaAndOSStatusAreWhitelistedNumeric() {
        XCTAssertEqual(ErrorDiagnostics.summary(ns("CoreMediaErrorDomain", -12752)),
                       "CoreMediaErrorDomain=-12752 (flujo de medios invalido)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns("CoreMediaErrorDomain", -9999)),
                       "CoreMediaErrorDomain=-9999 (error de medios)")
        let osStatus = ErrorDiagnostics.summary(ns(NSOSStatusErrorDomain, -9999))
        XCTAssertTrue(osStatus.hasPrefix("NSOSStatusErrorDomain=-9999 ("), osStatus)
    }

    func testAVFoundationCategoriesAndFallback() {
        XCTAssertEqual(ErrorDiagnostics.summary(ns("AVFoundationErrorDomain", -11828)),
                       "AVFoundationErrorDomain=-11828 (formato no admitido)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns("AVFoundationErrorDomain", -11850)),
                       "AVFoundationErrorDomain=-11850 (respuesta del servidor incorrecta)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns("AVFoundationErrorDomain", -4242)),
                       "AVFoundationErrorDomain=-4242 (error de reproduccion)")
    }

    func testWhitelistedPOSIXCoreMediaAndCFNetworkDomains() {
        XCTAssertEqual(ErrorDiagnostics.summary(ns(NSPOSIXErrorDomain, 61)),
                       "NSPOSIXErrorDomain=61 (conexion rechazada)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns("NSCMErrorDomain", -12752)),
                       "NSCMErrorDomain=-12752 (flujo de medios invalido)")
        XCTAssertEqual(ErrorDiagnostics.summary(ns("kCFErrorDomainCFNetwork", -1004)),
                       "kCFErrorDomainCFNetwork=-1004 (no se pudo conectar)")
    }

    func testUnknownDomainCollapsesToErrorWithoutRawString() {
        let evil = ns("ProveedorMaloErrorDomain-" + secretPhrase, 42)
        let out = ErrorDiagnostics.summary(evil)
        XCTAssertEqual(out, "error(42)")
        XCTAssertFalse(out.contains(secretPhrase))
    }

    func testSecretsInLocalizedDescriptionAndUserInfoNeverLeak() {
        let nested = CustomError(domain: "com.secretsauce.Weird",
                                 code: 7,
                                 userInfo: ["NSLocalizedDescription": secretPhrase])
        let top = CustomError(domain: NSURLErrorDomain,
                              code: -1009,
                              userInfo: ["NSLocalizedDescription": secretPhrase,
                                         "url": "https://user:" + secretPhrase + "@miptv.tv/x",
                                         NSUnderlyingErrorKey: nested])
        let out = ErrorDiagnostics.summary(top)
        XCTAssertFalse(out.contains(secretPhrase))
        XCTAssertFalse(out.contains("miptv.tv"))
        XCTAssertTrue(out.hasPrefix("NSURLErrorDomain=-1009 (sin conexion) <- "))
        XCTAssertTrue(out.contains("error(7)"))
    }

    func testNestedChainJoinsCodesAndStopsAtMaxDepth() {
        let l4 = ns("NSCMErrorDomain", -12752)
        let l3 = ns("kCFErrorDomainCFNetwork", -1004, l4)
        let l2 = ns(NSPOSIXErrorDomain, Int(ECONNREFUSED), l3)
        let l1 = ns(NSURLErrorDomain, -1004, l2)
        let l0 = ns("AVFoundationErrorDomain", -11850, l1)
        let out = ErrorDiagnostics.summary(l0)
        XCTAssertEqual(out,
                       "AVFoundationErrorDomain=-11850 (respuesta del servidor incorrecta)"
                       + " <- NSURLErrorDomain=-1004 (no se pudo conectar)"
                       + " <- NSPOSIXErrorDomain=61 (conexion rechazada)"
                       + " <- kCFErrorDomainCFNetwork=-1004 (no se pudo conectar)")
        XCTAssertFalse(out.contains("-12752"), "quinto eslabon debe quedar fuera")
    }

    func testSelfReferencingChainTerminates() {
        XCTAssertEqual(ErrorDiagnostics.summary(SelfReferencingError()),
                       "NSURLErrorDomain=-1009 (sin conexion)")
    }

    func testNonNSErrorBridgesToSafeShapeOnly() {
        struct CustomErrorType: Error {}
        let out = ErrorDiagnostics.summary(CustomErrorType())
        // La bridging da un dominio desconocido: salida colapsada "error(codigo)".
        XCTAssertTrue(out.hasPrefix("error("), out)
        XCTAssertTrue(out.hasSuffix(")"), out)
        let inner = out.dropFirst("error(".count).dropLast()
        XCTAssertNotNil(Int(inner), out)
        XCTAssertFalse(out.contains("CustomErrorType"))
    }
}
