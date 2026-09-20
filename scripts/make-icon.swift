// Draws the app icon into an .iconset directory: swift scripts/make-icon.swift <iconset-dir>
import AppKit

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Everything is laid out on a 1024pt canvas and scaled to the requested pixel size.
func draw(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGradient(starting: NSColor(red: 0.35, green: 0.56, blue: 0.98, alpha: 1),
               ending: NSColor(red: 0.30, green: 0.22, blue: 0.72, alpha: 1))!.draw(in: tile, angle: -90)

    let capsule = NSRect(x: 196, y: 422, width: 632, height: 180)
    NSColor(white: 1, alpha: 0.92).setFill()
    NSBezierPath(roundedRect: capsule, xRadius: 90, yRadius: 90).fill()

    let ink = NSColor(red: 0.24, green: 0.22, blue: 0.55, alpha: 1)
    ink.setStroke()
    ink.setFill()
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 330, y: 562))
    chevron.line(to: NSPoint(x: 280, y: 512))
    chevron.line(to: NSPoint(x: 330, y: 462))
    chevron.lineWidth = 30
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.stroke()
    for x in [470, 590, 710] {
        NSBezierPath(ovalIn: NSRect(x: x - 34, y: 478, width: 68, height: 68)).fill()
    }

    NSGraphicsContext.current = nil
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try draw(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
