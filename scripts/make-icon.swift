// Renders the app icon into an .iconset folder. Usage: swift make-icon.swift <out.iconset> [preview.png]
// A smiling envelope with sparkles and confetti on a sunset gradient.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Four-point sparkle centered at (x, y).
func sparkle(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor) {
    let r = size / 2, w = size * 0.13
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: y + r))
    p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + w, y: y + w))
    p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + w, y: y - w))
    p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - w, y: y - w))
    p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - w, y: y + w))
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func confetti(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = ns.cgContext
    let s = CGFloat(px)

    // Background squircle following the macOS icon grid.
    let inset = s * 0.098
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.3))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0.95, 0.35, 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [rgb(1.0, 0.62, 0.35), rgb(0.98, 0.33, 0.55), rgb(0.55, 0.36, 0.98)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // Soft glossy highlight in the upper left.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.3, y: s * 0.82), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.3, y: s * 0.82), endRadius: s * 0.55, options: [])

    // Confetti.
    confetti(ctx, x: s * 0.24, y: s * 0.27, w: s * 0.07, h: s * 0.028, angle: 30, color: rgb(0.45, 0.95, 0.80))
    confetti(ctx, x: s * 0.73, y: s * 0.21, w: s * 0.06, h: s * 0.026, angle: -25, color: rgb(1.0, 0.86, 0.35))
    confetti(ctx, x: s * 0.17, y: s * 0.55, w: s * 0.05, h: s * 0.024, angle: 70, color: rgb(0.55, 0.85, 1.0))
    confetti(ctx, x: s * 0.84, y: s * 0.47, w: s * 0.055, h: s * 0.024, angle: 15, color: rgb(1.0, 1.0, 1.0, 0.85))
    ctx.setFillColor(rgb(1, 1, 1, 0.8))
    ctx.fillEllipse(in: CGRect(x: s * 0.62, y: s * 0.80, width: s * 0.03, height: s * 0.03))
    ctx.setFillColor(rgb(1.0, 0.86, 0.35))
    ctx.fillEllipse(in: CGRect(x: s * 0.33, y: s * 0.16, width: s * 0.025, height: s * 0.025))

    // The envelope, tilted a little for some personality.
    let cx = s * 0.48, cy = s * 0.47
    let ew = s * 0.54, eh = s * 0.38
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -9 * .pi / 180)
    let env = CGRect(x: -ew / 2, y: -eh / 2, width: ew, height: eh)
    let envPath = CGPath(roundedRect: env, cornerWidth: s * 0.055, cornerHeight: s * 0.055, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.045, color: rgb(0.35, 0.05, 0.3, 0.35))
    ctx.addPath(envPath)
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Flap.
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(s * 0.02)
    ctx.setStrokeColor(rgb(0.98, 0.55, 0.68))
    ctx.move(to: CGPoint(x: env.minX + s * 0.05, y: env.maxY - s * 0.035))
    ctx.addLine(to: CGPoint(x: 0, y: s * 0.015))
    ctx.addLine(to: CGPoint(x: env.maxX - s * 0.05, y: env.maxY - s * 0.035))
    ctx.strokePath()

    // Happy face.
    let ink = rgb(0.24, 0.13, 0.36)
    ctx.setFillColor(ink)
    for dx in [-s * 0.075, s * 0.075] {
        ctx.fillEllipse(in: CGRect(x: dx - s * 0.018, y: -s * 0.08, width: s * 0.036, height: s * 0.05))
    }
    ctx.setFillColor(rgb(1, 1, 1))
    for dx in [-s * 0.075, s * 0.075] {
        ctx.fillEllipse(in: CGRect(x: dx - s * 0.006, y: -s * 0.048, width: s * 0.012, height: s * 0.012))
    }
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(s * 0.018)
    ctx.addArc(center: CGPoint(x: 0, y: -s * 0.095), radius: s * 0.045, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(rgb(1.0, 0.45, 0.6, 0.45))
    for dx in [-s * 0.14, s * 0.14] {
        ctx.fillEllipse(in: CGRect(x: dx - s * 0.03, y: -s * 0.125, width: s * 0.06, height: s * 0.036))
    }
    ctx.restoreGState()

    // Sparkles.
    sparkle(ctx, x: s * 0.77, y: s * 0.74, size: s * 0.17, color: rgb(1.0, 0.88, 0.38))
    sparkle(ctx, x: s * 0.86, y: s * 0.61, size: s * 0.07, color: rgb(1, 1, 1, 0.95))
    sparkle(ctx, x: s * 0.22, y: s * 0.76, size: s * 0.09, color: rgb(1, 1, 1, 0.9))
    ctx.restoreGState()

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
