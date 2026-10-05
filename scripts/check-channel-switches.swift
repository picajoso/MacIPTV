// Lifecycle smoke: a stable AVPlayerLayer survives rapid item replacement.
// Uses only public demo media; never reads the user's provider or Keychain.
import AppKit
import AVFoundation
import CoreVideo

let surface = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
let layer = AVPlayerLayer()
let player = AVPlayer()
player.isMuted = true
layer.player = player
layer.videoGravity = .resizeAspect
surface.wantsLayer = true
surface.layer = layer
var output: AVPlayerItemVideoOutput?
let raw = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
for index in 1...20 {
    let item = AVPlayerItem(url: URL(string: raw)!)
    let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    item.add(videoOutput)
    player.replaceCurrentItem(with: item)
    player.play()
    output = videoOutput
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard layer.player === player else { print("FAIL: video surface lost its player"); exit(1) }
    if index % 5 == 0 { print("Completed channel changes:", index) }
}
let deadline = Date().addingTimeInterval(35)
var decoded = false
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    if let output {
        let time = output.itemTime(forHostTime: ProcessInfo.processInfo.systemUptime)
        if let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            print("PASS: decoded frame after 20 channel changes", CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
            decoded = true
            break
        }
    }
    if player.currentItem?.status == .failed {
        print("FAIL: final item error code", (player.currentItem?.error as NSError?)?.code ?? 0)
        break
    }
}
player.pause()
player.replaceCurrentItem(with: nil)
layer.player = nil
if !decoded { print("FAIL: no final frame within deadline") }
exit(decoded ? 0 : 1)
