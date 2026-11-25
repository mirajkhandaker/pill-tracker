// Generates PillTrack's launcher-icon and splash source images.
//
//   swift tool/generate_brand_assets.swift
//
// Then regenerate platform assets:
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// Artwork: a white capsule (with a teal seam) on teal #00897B.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let teal = CGColor(srgbRed: 0x00 / 255, green: 0x89 / 255, blue: 0x7B / 255, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(path)")
    print("wrote \(path)")
}

/// White capsule of [length] x [thickness], rotated 45°, centred at (cx, cy),
/// with a seam in [seam] colour (or a cut-out when seam is nil).
func drawPill(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, length: CGFloat,
              thickness: CGFloat, seam: CGColor?) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: .pi / 4)
    let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: thickness / 2,
                       cornerHeight: thickness / 2, transform: nil))
    ctx.setFillColor(white)
    ctx.fillPath()
    let seamWidth = thickness * 0.09
    let seamRect = CGRect(x: -seamWidth / 2, y: -thickness / 2, width: seamWidth, height: thickness)
    if let seam = seam {
        ctx.setFillColor(seam)
        ctx.fill(seamRect)
    } else {
        ctx.setBlendMode(.clear)
        ctx.fill(seamRect)
    }
    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, _ text: String, size: CGFloat, centerX: CGFloat, baselineY: CGFloat) {
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: centerX - CGFloat(width) / 2, y: baselineY)
    CTLineDraw(line, ctx)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 1. Full icon (iOS + legacy Android): teal square, pill fills the canvas.
do {
    let ctx = makeContext(1024, 1024)
    ctx.setFillColor(teal)
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawPill(ctx, cx: 512, cy: 512, length: 640, thickness: 256, seam: teal)
    save(ctx, "\(outDir)/icon.png")
}

// 2. Adaptive-icon foreground: transparent, pill kept inside the 66% safe zone
//    (launchers mask the outer third). Seam is cut out so the same file works
//    as the Android 13 monochrome (themed) icon, which uses alpha only.
do {
    let ctx = makeContext(1024, 1024)
    drawPill(ctx, cx: 512, cy: 512, length: 560, thickness: 224, seam: nil)
    save(ctx, "\(outDir)/icon_foreground.png")
}

// 3. Android 12+ splash icon: 1152x1152, content within the 768px circle.
do {
    let ctx = makeContext(1152, 1152)
    drawPill(ctx, cx: 576, cy: 576, length: 600, thickness: 240, seam: nil)
    save(ctx, "\(outDir)/splash_icon.png")
}

// 4. Pre-Android-12 / iOS splash: pill with "PillTrack" beneath (4x density).
do {
    let ctx = makeContext(800, 800)
    drawPill(ctx, cx: 400, cy: 480, length: 420, thickness: 168, seam: nil)
    drawText(ctx, "PillTrack", size: 120, centerX: 400, baselineY: 90)
    save(ctx, "\(outDir)/splash.png")
}

// 5. Android 12+ branding strip (bottom of the system splash): "PillTrack".
do {
    let ctx = makeContext(800, 320)
    drawText(ctx, "PillTrack", size: 150, centerX: 400, baselineY: 110)
    save(ctx, "\(outDir)/splash_branding.png")
}
