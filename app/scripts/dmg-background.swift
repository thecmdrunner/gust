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

    // First-launch callout: the app is unsigned, so Gatekeeper blocks the first open.
    let card = NSRect(x: 70, y: H - 378, width: W - 140, height: 84)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 14
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.shadowColor = NSColor(white: 0, alpha: 0.10)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
    NSGraphicsContext.restoreGraphicsState()
    let amber = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.07, alpha: 1)
    amber.withAlphaComponent(0.9).setStroke()
    let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.75, dy: 0.75), xRadius: 13.5, yRadius: 13.5)
    border.lineWidth = 1.5
    border.stroke()

    func draw(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) -> CGFloat {
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (s as NSString).draw(at: p, withAttributes: a)
        return (s as NSString).size(withAttributes: a).width
    }

    // Header: amber "!" badge + title.
    let badge = NSRect(x: card.minX + 18, y: card.maxY - 36, width: 20, height: 20)
    amber.setFill()
    NSBezierPath(ovalIn: badge).fill()
    let bang = NSFont.systemFont(ofSize: 13, weight: .heavy)
    let bw = ("!" as NSString).size(withAttributes: [.font: bang]).width
    _ = draw("!", bang, .white, at: NSPoint(x: badge.midX - bw / 2, y: badge.minY + 2))
    _ = draw("First launch? macOS will block Gust. Allow it here:", .systemFont(ofSize: 14, weight: .semibold),
             NSColor(white: 0.1, alpha: 1), at: NSPoint(x: badge.maxX + 10, y: badge.minY + 1))

    // Steps as chips.
    let chipFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    var x = badge.minX
    let cy = card.minY + 14
    for (i, step) in ["System Settings", "Privacy & Security", "Open Anyway"].enumerated() {
        let w = (step as NSString).size(withAttributes: [.font: chipFont]).width + 20
        let chip = NSRect(x: x, y: cy, width: w, height: 24)
        let last = i == 2
        (last ? blue : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 7, yRadius: 7).fill()
        _ = draw(step, chipFont, last ? .white : NSColor(white: 0.15, alpha: 1), at: NSPoint(x: x + 10, y: cy + 4))
        x += w
        if !last { x += 6 + draw("›", .systemFont(ofSize: 15, weight: .semibold), NSColor(white: 0.55, alpha: 1), at: NSPoint(x: x + 6, y: cy + 2)) + 6 }
    }

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
try? FileManager.default.removeItem(atPath: "/tmp/dmg-bg-preview.png")
try? FileManager.default.copyItem(at: two, to: URL(fileURLWithPath: "/tmp/dmg-bg-preview.png"))
