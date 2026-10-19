// Renders the app icon: a processor chip on a dark blue rounded square, with a load trace.
//   usage: swift scripts/make-icon.swift <output.iconset>
// scripts/make-icon.sh turns the iconset into packaging/AppIcon.icns.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024

    // Background: macOS icon grid inset (100 px of 1024) with a continuous-corner rectangle.
    let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let background = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.32, alpha: 1),
        ending: NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.14, alpha: 1)
    )!.draw(in: background, angle: -90)

    // Pins on all four sides of the chip.
    let pin = NSColor(calibratedRed: 0.55, green: 0.80, blue: 1.0, alpha: 1)
    pin.setFill()
    for index in 0..<5 {
        let offset = (332 + CGFloat(index) * 90) * scale
        for rect in [
            NSRect(x: offset, y: 222 * scale, width: 36 * scale, height: 90 * scale),
            NSRect(x: offset, y: 712 * scale, width: 36 * scale, height: 90 * scale),
            NSRect(x: 222 * scale, y: offset, width: 90 * scale, height: 36 * scale),
            NSRect(x: 712 * scale, y: offset, width: 90 * scale, height: 36 * scale),
        ] {
            NSBezierPath(roundedRect: rect, xRadius: 10 * scale, yRadius: 10 * scale).fill()
        }
    }

    // Chip body.
    let chip = NSRect(x: 292 * scale, y: 292 * scale, width: 440 * scale, height: 440 * scale)
    NSGradient(
        starting: NSColor(calibratedRed: 0.36, green: 0.72, blue: 1.0, alpha: 1),
        ending: NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 1)
    )!.draw(in: NSBezierPath(roundedRect: chip, xRadius: 60 * scale, yRadius: 60 * scale), angle: -90)

    // Load trace across the chip.
    let trace = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [(340, 470), (420, 470), (465, 600), (530, 400), (585, 540), (620, 470), (684, 470)]
    trace.move(to: NSPoint(x: points[0].0 * scale, y: points[0].1 * scale))
    for point in points.dropFirst() {
        trace.line(to: NSPoint(x: point.0 * scale, y: point.1 * scale))
    }
    trace.lineWidth = 34 * scale
    trace.lineCapStyle = .round
    trace.lineJoinStyle = .round
    NSColor.white.setStroke()
    trace.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
