// Offscreen UI regression: programme labels must advance without interaction.
// Uses synthetic data only; no keychain access or provider connections.
// After swift test, compile with the architecture-specific debug objects:
// swiftc -swift-version 5 -module-cache-path "$PWD/.build/clang-cache" \
//   -I .build/arm64-apple-macosx/debug/Modules \
//   Sources/MacIPTV/{AppStore,DemoContent,PlayerView,ContentView,GuideView,SourceSettingsView}.swift \
//   scripts/programme-refresh-smoke.swift \
//   .build/arm64-apple-macosx/debug/MacIPTVCore.build/*.swift.o \
//   -o /tmp/maciptv-programme-refresh-smoke
// /tmp/maciptv-programme-refresh-smoke
import AppKit
import SwiftUI
import Vision
import MacIPTVCore

@main struct ProgrammeRefreshSmoke {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let suite = "MacIPTV.ProgrammeRefreshSmoke.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: preferences)
        store.demoMode = true
        let channel = Channel(id: "clock-fixture", name: "Clock fixture", url: "", group: "Fixture", tvgID: "clock")
        store.channels = [channel]
        store.selectedChannelID = channel.id
        let start = Date()
        let boundary = start.addingTimeInterval(5)
        store.guide = XMLTVGuide(programmes: ["clock": [
            Programme(channelID: "clock", title: "BEFORECLOCK", start: start.addingTimeInterval(-60), end: boundary),
            Programme(channelID: "clock", title: "AFTERCLOCK", start: boundary, end: start.addingTimeInterval(120))
        ]])
        let root = NSHostingView(rootView: ContentView().environment(store))
        root.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        func waitUntil(_ date: Date) {
            while Date() < date {
                RunLoop.current.run(until: min(date, Date().addingTimeInterval(0.2)))
            }
        }
        func titles() throws -> String {
            root.layoutSubtreeIfNeeded()
            guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw NSError(domain: "SmokeBitmap", code: 1) }
            root.cacheDisplay(in: root.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { throw NSError(domain: "SmokeBitmap", code: 2) }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").uppercased()
        }
        func count(_ title: String, in text: String) -> Int { text.components(separatedBy: title).count - 1 }
        waitUntil(start.addingTimeInterval(2))
        let before = try titles()
        guard count("BEFORECLOCK", in: before) >= 2 else {
            print("FAIL: initial programme must appear in both list and player panel; recognized: \(before)")
            exit(1)
        }
        print("Initial programme visible in list and player panel")
        waitUntil(start.addingTimeInterval(36))
        let after = try titles()
        guard count("AFTERCLOCK", in: after) >= 2, !after.contains("BEFORECLOCK") else {
            print("FAIL: programme labels did not advance without interaction; recognized: \(after)")
            exit(1)
        }
        window.contentView = nil
        print("PASS: list and player panel advance to the next programme without interaction")
    }
}
