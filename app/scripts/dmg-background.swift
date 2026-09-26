import AppKit

// Renders the DMG window background (660×400 pt, 1x + 2x). Icons sit at (180, 190) and (480, 190) from top-left.
// Usage: swift scripts/dmg-background.swift Resources/dmg-background.tiff
let W: CGFloat = 660, H: CGFloat = 400

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(colors: [NSColor(srgbRed: 0.97, green: 0.975, blue: 0.985, alpha: 1),
                        NSColor(srgbRed: 0.91, green: 0.93, blue: 0.96, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Soft blue glow behind the app icon slot.
    NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 0.22), .clear])!
        .draw(fromCenter: NSPoint(x: 180, y: H - 190), radius: 0, toCenter: NSPoint(x: 180, y: H - 190), radius: 130, options: [])

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        (s as NSString).draw(in: NSRect(x: 0, y: H - y - size * 1.3, width: W, height: size * 1.5), withAttributes: attr)
    }
    text("Drag Gust into Applications", size: 22, weight: .semibold, color: NSColor(white: 0.08, alpha: 1), y: 44)

    // Arrow between the two icon slots.
    let blue = NSColor(srgbRed: 0.16, green: 0.42, blue: 0.98, alpha: 1)
    let y = H - 180
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 268, y: y))
    shaft.curve(to: NSPoint(x: 376, y: y + 4), controlPoint1: NSPoint(x: 300, y: y + 28), controlPoint2: NSPoint(x: 348, y: y + 26))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    let dash: [CGFloat] = [0.1, 12]
    shaft.setLineDash(dash, count: 2, phase: 0)
    blue.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: y + 16))
    head.line(to: NSPoint(x: 396, y: y))
    head.line(to: NSPoint(x: 376, y: y - 6))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("First launch: System Settings → Privacy & Security → Open Anyway", size: 12, weight: .regular,
         color: NSColor(white: 0.45, alpha: 1), y: 340)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
let tmp = FileManager.default.temporaryDirectory
let one = tmp.appendingPathComponent("bg.png"), two = tmp.appendingPathComponent("bg@2x.png")
try! render(scale: 1).representation(using: .png, properties: [:])!.write(to: one)
try! render(scale: 2).representation(using: .png, properties: [:])!.write(to: two)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", one.path, two.path, "-out", out]
try! p.run(); p.waitUntilExit()
try? FileManager.default.copyItem(at: two, to: URL(fileURLWithPath: "/tmp/dmg-bg-preview.png"))
