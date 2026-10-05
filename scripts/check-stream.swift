// Public-fixture playback smoke test: require a decoded frame, not merely a fetched playlist.
import Foundation
import AVFoundation
import CoreVideo

let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!
let item = AVPlayerItem(url: url)
let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
item.add(output)
let player = AVPlayer(playerItem: item)
player.isMuted = true
player.play()
let deadline = Date().addingTimeInterval(35)
var decoded = false
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let time = output.itemTime(forHostTime: ProcessInfo.processInfo.systemUptime)
    if let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
        print("PASS: decoded HLS video frame \(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame)); playback time \(player.currentTime().seconds)s")
        decoded = true
        break
    }
    if item.status == .failed {
        print("FAIL: AVPlayer item failed (code \((item.error as NSError?)?.code ?? 0))")
        break
    }
}
player.pause()
if !decoded { print("FAIL: no decoded video frame within 35 seconds") }
exit(decoded ? 0 : 1)
