// Compile alongside the production PlayerView and MacIPTVCore objects.
// Offscreen SwiftUI integration: induce a frozen player, require a new item
// and resumed playback. Does not use credentials or modify the saved source.
import AppKit
import AVFoundation
import SwiftUI
import MacIPTVCore

@main struct RecoverySmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let channel = Channel(id: "recovery-smoke", name: "Public recovery fixture",
            url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8", group: "Fixture")
        let root = NSHostingView(rootView: PlayerView(channel: channel))
        root.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        func findPlayer(_ view: NSView) -> AVPlayer? {
            if let layer = view.layer as? AVPlayerLayer { return layer.player }
            for child in view.subviews { if let found = findPlayer(child) { return found } }
            return nil
        }
        let deadline = Date().addingTimeInterval(70)
        var oldItem: AVPlayerItem?
        var player: AVPlayer?
        var passed = false
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            root.layoutSubtreeIfNeeded()
            if player == nil { player = findPlayer(root); player?.isMuted = true }
            guard let player else { continue }
            if oldItem == nil && player.currentTime().seconds > 3 {
                oldItem = player.currentItem
                player.pause() // Simulate freeze without a voluntary UI pause.
                print("Injected non-advancing ready item")
            } else if let oldItem, let item = player.currentItem, item !== oldItem,
                      player.timeControlStatus == .playing, player.currentTime().seconds > 3 {
                print("PASS: production PlayerView replaced frozen item and resumed video")
                passed = true
                break
            }
        }
        player?.pause()
        window.contentView = nil
        if !passed { print("FAIL: production recovery did not resume within 70s") }
        exit(passed ? 0 : 1)
    }
}
