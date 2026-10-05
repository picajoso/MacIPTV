import AppKit

let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let background = NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.19, yRadius: p * 0.19)
        NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.13, alpha: 1).setFill()
        background.fill()
        let screen = NSBezierPath(roundedRect: NSRect(x: p * 0.19, y: p * 0.28, width: p * 0.62, height: p * 0.47), xRadius: p * 0.07, yRadius: p * 0.07)
        NSColor(calibratedRed: 0.29, green: 0.83, blue: 0.75, alpha: 1).setStroke()
        screen.lineWidth = p * 0.037
        screen.stroke()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: p * 0.43, y: p * 0.39))
        play.line(to: NSPoint(x: p * 0.43, y: p * 0.64))
        play.line(to: NSPoint(x: p * 0.64, y: p * 0.515))
        play.close()
        NSColor(calibratedRed: 0.29, green: 0.83, blue: 0.75, alpha: 1).setFill()
        play.fill()
        let stand = NSBezierPath(roundedRect: NSRect(x: p * 0.37, y: p * 0.18, width: p * 0.26, height: p * 0.035), xRadius: p * 0.017, yRadius: p * 0.017)
        stand.fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
