// Renders the app icon into an .iconset folder. Usage: swift make-icon.swift <out.iconset> [preview.png]
// Envelopes lifting out of an inbox tray and fading away, on a navy-to-electric-blue gradient.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let indigo = CGColor(srgbRed: 0.22, green: 0.30, blue: 0.88, alpha: 1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
}

/// Inbox tray: a box whose top edge dips in the middle where mail goes in.
func tray(_ ctx: CGContext, _ s: CGFloat) {
    let cx: CGFloat = 0.5, w: CGFloat = 0.60
    let x0 = s * (cx - w / 2), x1 = s * (cx + w / 2), yT = s * 0.43, yB = s * 0.22
    let a = s * (cx - w * 0.24), b = s * (cx + w * 0.24), dip = s * 0.065, d = s * 0.035, r = s * 0.06
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0, y: yT))
    p.addLine(to: CGPoint(x: a, y: yT))
    p.addLine(to: CGPoint(x: a + d, y: yT - dip))
    p.addLine(to: CGPoint(x: b - d, y: yT - dip))
    p.addLine(to: CGPoint(x: b, y: yT))
    p.addLine(to: CGPoint(x: x1, y: yT))
    p.addArc(tangent1End: CGPoint(x: x1, y: yB), tangent2End: CGPoint(x: x0, y: yB), radius: r)
    p.addArc(tangent1End: CGPoint(x: x0, y: yB), tangent2End: CGPoint(x: x0, y: yT), radius: r)
    p.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: rgb(0.02, 0.04, 0.2, 0.45))
    ctx.addPath(p)
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(p)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(1, 1, 1), rgb(0.90, 0.91, 0.97)], [0, 1]),
                           start: CGPoint(x: 0, y: yT), end: CGPoint(x: 0, y: yB), options: [])
    ctx.restoreGState()
}

/// Small envelope centered at (x, y) as a fraction of the icon, rotated and faded.
func envelope(_ ctx: CGContext, _ s: CGFloat, x: CGFloat, y: CGFloat, w: CGFloat, angle: CGFloat, alpha: CGFloat) {
    let ew = s * w, eh = ew * 0.7
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: s * x, y: s * y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -ew / 2, y: -eh / 2, width: ew, height: eh)
    ctx.setShadow(offset: CGSize(width: 0, height: -ew * 0.06), blur: ew * 0.15, color: rgb(0.02, 0.04, 0.2, 0.35))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: ew * 0.1, cornerHeight: ew * 0.1, transform: nil))
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.move(to: CGPoint(x: r.minX + ew * 0.12, y: r.maxY - ew * 0.12))
    ctx.addLine(to: CGPoint(x: 0, y: -eh * 0.05))
    ctx.addLine(to: CGPoint(x: r.maxX - ew * 0.12, y: r.maxY - ew * 0.12))
    ctx.setStrokeColor(indigo)
    ctx.setLineWidth(ew * 0.07)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = ns.cgContext
    let s = CGFloat(px)

    // Background squircle on the macOS icon grid.
    let inset = s * 0.098
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0.12, 0.17, 0.5))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0.06, 0.09, 0.25), rgb(0.20, 0.26, 0.82), rgb(0.27, 0.56, 1.0)], [0, 0.55, 1]),
                           start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)], [0, 1]),
                           startCenter: CGPoint(x: s * 0.5, y: s * 0.95), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.5, y: s * 0.95), endRadius: s * 0.6, options: [])
    ctx.restoreGState()

    // Hairline edge for definition on dark backgrounds.
    ctx.addPath(squircle)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()

    // Mail lifting out of the inbox and fading as it leaves.
    envelope(ctx, s, x: 0.76, y: 0.79, w: 0.11, angle: -24, alpha: 0.35)
    envelope(ctx, s, x: 0.65, y: 0.67, w: 0.17, angle: -16, alpha: 0.65)
    envelope(ctx, s, x: 0.52, y: 0.53, w: 0.25, angle: -8, alpha: 1)
    tray(ctx, s)

    ns.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try render(512).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
