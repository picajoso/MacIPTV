// Compile with MacIPTVCore objects, bundle and sign using production entitlements.
// Only synthetic local data and Apple's public HLS sample; no saved subscription.
import AppKit
import Foundation
import MacIPTVCore

@main struct SecuritySandboxSmoke {
    static func main() async {
        var failed = false
        let forbidden = "/Users/javipas/maciptv/.build/security-forbidden.txt"
        do {
            _ = try String(contentsOfFile: forbidden, encoding: .utf8)
            print("FAIL: sandbox read unselected fixture")
            failed = true
        } catch { print("PASS: sandbox denied unselected file") }
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fixture = home.appendingPathComponent("security-smoke.txt")
            try "synthetic".write(to: fixture, atomically: true, encoding: .utf8)
            guard try String(contentsOf: fixture, encoding: .utf8) == "synthetic" else { throw URLError(.unknown) }
            try FileManager.default.removeItem(at: fixture)
            print("PASS: container storage works")
        } catch { print("FAIL: container storage \(error)"); failed = true }
        let publicURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!
        do {
            let text = try await ContentFetcher(timeout: 15).fetchString(publicURL)
            guard text.hasPrefix("#EXTM3U") else { throw URLError(.badServerResponse) }
            print("PASS: validated HTTPS via pinned-IP gateway")
        } catch { print("FAIL: HTTPS \(error)"); failed = true }
        let relay = HLSRelay()
        do {
            let local = try await relay.start(upstream: publicURL)
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(from: local)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  String(decoding: data, as: UTF8.self).contains("http://127.0.0.1:") else { throw URLError(.badServerResponse) }
            print("PASS: sandbox loopback HLS relay")
        } catch { print("FAIL: relay \(error)"); failed = true }
        await relay.stop()
        exit(failed ? 1 : 0)
    }
}
