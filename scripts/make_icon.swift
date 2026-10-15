// Draws the 1024×1024 PowerDeck app icon. Usage: make_icon <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let canvas = 1024

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("Could not create bitmap")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The standard macOS icon body: an 824-point rounded square centred in the canvas.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
NSGradient(starting: color(0x1C2330), ending: color(0x07090D))!.draw(in: body, angle: -90)

NSGraphicsContext.current?.saveGraphicsState()
body.addClip()
NSGradient(starting: color(0x34D399, 0.4), ending: color(0x34D399, 0))!
    .draw(in: body, relativeCenterPosition: NSPoint(x: 0, y: -0.05))
NSGraphicsContext.current?.restoreGraphicsState()

color(0xFFFFFF, 0.08).setStroke()
body.lineWidth = 6
body.stroke()

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .black)
    .applying(NSImage.SymbolConfiguration(paletteColors: [color(0x34D399)]))
if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let size = bolt.size
    bolt.draw(in: NSRect(x: (CGFloat(canvas) - size.width) / 2, y: (CGFloat(canvas) - size.height) / 2,
                         width: size.width, height: size.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
