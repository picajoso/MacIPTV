import XCTest

final class TransportPolicyTests: XCTestCase {
    func testBundleAllowsHTTPPlaylistDownloadsWithoutGranularATSOverrides() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ats = try XCTUnwrap(plist["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsArbitraryLoads"] as? Bool, true)
        // En macOS estas claves hacen que la anterior se ignore, incluso
        // si su valor es false. AVKit y URLSession necesitan permitir HTTP.
        for key in ["NSAllowsArbitraryLoadsForMedia", "NSAllowsArbitraryLoadsInWebContent", "NSAllowsLocalNetworking"] {
            XCTAssertNil(ats[key], "La presencia de \(key) desactiva el permiso HTTP de las listas")
        }
    }
}
