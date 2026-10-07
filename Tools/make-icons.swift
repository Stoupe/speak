// Generates Speak's app icon and menu bar glyphs.
//
//   swift Tools/make-icons.swift [repo-root] [preview-dir]
//
// Writes into Speak/Assets.xcassets (AppIcon, MenuBarIcon, MenuBarIconRecording),
// the Icon Composer bundle Tools/AppIcon.icon, and preview PNGs (default /tmp/speak-icon).

import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
let previewDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "/tmp/speak-icon")
let catalog = root.appendingPathComponent("Speak/Assets.xcassets")
let fm = FileManager.default

// MARK: - Design

/// Waveform shared by the app icon and the menu bar glyph: relative bar heights, left to right.
let waveform: [CGFloat] = [0.40, 0.70, 1.00, 0.58, 0.32]
/// Fewer, chunkier bars for the 16 and 32 px renditions so they don't turn to mush.
let smallWaveform: [CGFloat] = [0.56, 1.00, 0.50]

let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: p3, components: [r, g, b, a])!
}

// Background: luminous violet-blue at the top settling into deep indigo.
let bgTop = color(0.47, 0.42, 1.00)
let bgBottom = color(0.20, 0.13, 0.66)

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

func capsule(_ rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Bars centred in `rect`. `width` and `gap` are fractions of rect width; heights are fractions of rect height.
func barRects(in rect: CGRect, heights: [CGFloat], width: CGFloat, gap: CGFloat) -> [CGRect] {
    let n = CGFloat(heights.count)
    let bw = rect.width * width, g = rect.width * gap
    let total = n * bw + (n - 1) * g
    var x = rect.midX - total / 2
    return heights.map { h in
        let bh = max(bw, rect.height * h)
        defer { x += bw + g }
        return CGRect(x: x, y: rect.midY - bh / 2, width: bw, height: bh)
    }
}

// macOS 26 icon grid on a 1024 canvas: 824 pt body inset 100 pt, continuous corner radius ~185.4.
let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

/// Bar layout inside the icon body (in 1024 canvas units).
func iconBars(small: Bool) -> [CGRect] {
    let area = CGRect(x: body.minX + 150, y: body.minY + 190, width: body.width - 300, height: body.height - 380)
    return small
        ? barRects(in: area.insetBy(dx: -40, dy: -30), heights: smallWaveform, width: 0.22, gap: 0.17)
        : barRects(in: area, heights: waveform, width: 0.118, gap: 0.098)
}

func drawAppIcon(_ ctx: CGContext, size: CGFloat, small: Bool, shadow: Bool = true) {
    ctx.saveGState()
    ctx.scaleBy(x: size / canvas, y: size / canvas)
    let shape = squircle(body, radius: bodyRadius)

    // Drop shadow, as in Apple's macOS template.
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0, 0, 0.28))
        ctx.addPath(shape); ctx.setFillColor(bgBottom); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: p3, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Soft glow behind the bars.
    let glow = CGGradient(colorsSpace: p3, colors: [color(0.70, 0.66, 1.0, 0.45), color(0.70, 0.66, 1.0, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
    // Gentle sheen across the top edge.
    let sheen = CGGradient(colorsSpace: p3, colors: [color(1, 1, 1, 0.16), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 80), options: [])
    ctx.restoreGState()

    // Bars: white with a whisper of lavender at the bottom and a soft indigo shadow.
    let bars = iconBars(small: small)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0.10, 0.04, 0.40, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    for r in bars { ctx.addPath(capsule(r)) }
    ctx.clip()
    let barGrad = CGGradient(colorsSpace: p3, colors: [color(1, 1, 1), color(0.88, 0.86, 1.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(barGrad, start: CGPoint(x: 0, y: 780), end: CGPoint(x: 0, y: 240), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Hairline inner edge for definition on light backgrounds.
    if size >= 128 {
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.addPath(shape); ctx.setStrokeColor(color(1, 1, 1, 0.18)); ctx.setLineWidth(4); ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

// MARK: - Menu bar glyphs (18 x 18 pt, pixel-aligned at 1x)

let glyphSize = CGSize(width: 18, height: 18)
/// Idle: five 2 pt capsules, 2 pt apart, filling the 18 pt width.
let idleHeights: [CGFloat] = [6, 12, 16, 10, 6]
/// Recording: filled squircle with the waveform knocked out.
let recHeights: [CGFloat] = [4, 8, 12, 8, 4]

func drawGlyph(_ ctx: CGContext, recording: Bool) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    if !recording {
        for (i, h) in idleHeights.enumerated() {
            ctx.addPath(capsule(CGRect(x: CGFloat(i) * 4, y: 9 - h / 2, width: 2, height: h)))
        }
        ctx.fillPath()
    } else {
        ctx.addPath(squircle(CGRect(origin: .zero, size: glyphSize), radius: 5))
        for (i, h) in recHeights.enumerated() {
            ctx.addPath(capsule(CGRect(x: 2 + CGFloat(i) * 3, y: 9 - h / 2, width: 2, height: h)))
        }
        ctx.fillPath(using: .evenOdd)
    }
}

// MARK: - Output helpers

func bitmap(_ w: Int, _ h: Int, space: CGColorSpace = srgb) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

func mkdir(_ url: URL) { try! fm.createDirectory(at: url, withIntermediateDirectories: true) }

func renderAppIcon(px: Int) -> CGImage {
    let ctx = bitmap(px, px, space: p3)
    drawAppIcon(ctx, size: CGFloat(px), small: px <= 32)
    return ctx.makeImage()!
}

func renderGlyph(recording: Bool, scale: Int) -> CGImage {
    let ctx = bitmap(18 * scale, 18 * scale)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawGlyph(ctx, recording: recording)
    return ctx.makeImage()!
}

func writeGlyphPDF(recording: Bool, to url: URL) {
    var box = CGRect(origin: .zero, size: glyphSize)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawGlyph(ctx, recording: recording)
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - Asset catalog

let info = ["author": "xcode", "version": 1] as [String: Any]
mkdir(catalog)
writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))

let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try? fm.removeItem(at: appIconSet)
mkdir(appIconSet)
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(renderAppIcon(px: pt * scale), to: appIconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
}
writeJSON(["images": images, "info": info], to: appIconSet.appendingPathComponent("Contents.json"))

for (name, recording) in [("MenuBarIcon", false), ("MenuBarIconRecording", true)] {
    let set = catalog.appendingPathComponent("\(name).imageset")
    try? fm.removeItem(at: set)
    mkdir(set)
    writeGlyphPDF(recording: recording, to: set.appendingPathComponent("\(name).pdf"))
    writeJSON([
        "images": [["filename": "\(name).pdf", "idiom": "universal"]],
        "info": info,
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ], to: set.appendingPathComponent("Contents.json"))
}

// MARK: - Icon Composer bundle (Liquid Glass): background fill + glass waveform layer

let iconBundle = root.appendingPathComponent("Tools/AppIcon.icon")
try? fm.removeItem(at: iconBundle)
mkdir(iconBundle.appendingPathComponent("Assets"))
do {
    // Layer artwork is authored on the 1024 canvas; SVG is y-down.
    let rects = iconBars(small: false).map { r in
        String(format: "  <rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"%.1f\" fill=\"#FFFFFF\"/>",
               r.minX, canvas - r.maxY, r.width, r.height, r.width / 2)
    }
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    \(rects.joined(separator: "\n"))
    </svg>

    """
    try! svg.write(to: iconBundle.appendingPathComponent("Assets/Waveform.svg"), atomically: true, encoding: .utf8)
    func p3String(_ c: CGColor) -> String {
        let comps = c.components!
        return "display-p3:" + comps.map { String(format: "%.5f", $0) }.joined(separator: ",")
    }
    writeJSON([
        "fill": ["linear-gradient": [p3String(bgTop), p3String(bgBottom)]],
        "groups": [[
            "layers": [["glass": true, "image-name": "Waveform.svg", "name": "Waveform"]],
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.4],
        ]],
        "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
    ], to: iconBundle.appendingPathComponent("icon.json"))
}

// MARK: - Previews

mkdir(previewDir)
do {
    // App icon: 1024 on the left, then 16/32/64/128 at 1x on light and dark strips.
    let w = 1024 + 40 + 420, h = 1024
    let ctx = bitmap(w, h, space: p3)
    ctx.setFillColor(color(0.93, 0.93, 0.95)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(renderAppIcon(px: 1024), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let sizes = [16, 32, 64, 128]
    for (row, bg) in [color(0.96, 0.96, 0.97), color(0.12, 0.12, 0.14)].enumerated() {
        let strip = CGRect(x: 1064, y: CGFloat(h / 2 + 40 - row * 440), width: 400, height: 380)
        ctx.setFillColor(bg); ctx.fill(strip)
        var x = strip.minX + 20
        for s in sizes {
            // Each size rendered natively and placed 1:1.
            ctx.draw(renderAppIcon(px: s), in: CGRect(x: x, y: strip.midY - CGFloat(s) / 2, width: CGFloat(s), height: CGFloat(s)))
            x += CGFloat(s) + 24
        }
    }
    writePNG(ctx.makeImage()!, to: previewDir.appendingPathComponent("preview-appicon.png"))

    // Separate magnified sheet: each small size rendered natively, then enlarged 6x without smoothing.
    let mag = 6
    let mw = (16 + 32 + 64 + 128 + 5 * 8) * mag, mh = 2 * (128 + 16) * mag
    let m = bitmap(mw, mh, space: p3)
    m.interpolationQuality = .none
    for (row, bg) in [color(0.96, 0.96, 0.97), color(0.12, 0.12, 0.14)].enumerated() {
        let y = CGFloat((1 - row) * (128 + 16) * mag)
        m.setFillColor(bg); m.fill(CGRect(x: 0, y: y, width: CGFloat(mw), height: CGFloat((128 + 16) * mag)))
        var x = CGFloat(8 * mag)
        for s in sizes {
            m.draw(renderAppIcon(px: s), in: CGRect(x: x, y: y + CGFloat(8 * mag), width: CGFloat(s * mag), height: CGFloat(s * mag)))
            x += CGFloat((s + 8) * mag)
        }
    }
    writePNG(m.makeImage()!, to: previewDir.appendingPathComponent("preview-appicon-small-magnified.png"))
}
do {
    // Menu bar: both glyphs at 1x and 2x on light and dark bars, magnified 8x (nearest neighbour).
    let mag = 8
    let barH = 24
    let cols = 4, colW = 34
    let w = cols * colW * mag, h = 2 * barH * mag
    let ctx = bitmap(w, h)
    ctx.interpolationQuality = .none
    for (row, (bg, fg)) in [(CGColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1), CGColor(gray: 0.1, alpha: 1)),
                            (CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1), CGColor(gray: 1, alpha: 0.92))].enumerated() {
        let y = (1 - row) * barH * mag
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y, width: w, height: barH * mag))
        for (col, (recording, scale)) in [(false, 1), (true, 1), (false, 2), (true, 2)].enumerated() {
            // Tint the template: render glyph mask, then fill through it.
            let glyph = renderGlyph(recording: recording, scale: scale)
            let tinted = bitmap(18 * scale, 18 * scale)
            tinted.clip(to: CGRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale), mask: glyph)
            tinted.setFillColor(fg); tinted.fill(CGRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale))
            let x = (col * colW + 8) * mag, gy = y + 3 * mag
            ctx.draw(tinted.makeImage()!, in: CGRect(x: x, y: gy, width: 18 * mag, height: 18 * mag))
        }
    }
    writePNG(ctx.makeImage()!, to: previewDir.appendingPathComponent("preview-menubar.png"))
}

print("Wrote \(catalog.path), \(iconBundle.path), previews in \(previewDir.path)")
