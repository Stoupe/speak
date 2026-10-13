// Generates Speak's app icon, menu bar glyphs and website favicon.
//
//   swift Tools/make-icons.swift [repo-root] [preview-dir]
//
// The mark: a waveform whose tallest line is a text cursor. Grey voice bars on a white page, the cursor in
// macOS's text-cursor blue.
//
// Writes the Icon Composer bundle Speak/AppIcon.icon (the real app icon: layered Liquid Glass),
// renders it with Xcode's `ictool` into Speak/Assets.xcassets/AppIcon.appiconset (fallback PNGs),
// draws MenuBarIcon / MenuBarIconRecording, writes site/icon.svg, and puts previews in /tmp/speak-icon.

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
let previewDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "/tmp/speak-icon")
let catalog = root.appendingPathComponent("Speak/Assets.xcassets")
let iconBundle = root.appendingPathComponent("Speak/AppIcon.icon")
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let fm = FileManager.default

// MARK: - Design (1024 canvas, y down, as in SVG)

let canvas: CGFloat = 1024
/// The whole mark is drawn at this scale about the centre, leaving room for the glass edge.
let markScale: CGFloat = 0.92

struct Bar { var height: CGFloat; var top: String; var bottom: String }
/// Waveform slots, left to right; `nil` is the cursor. Bars darken towards it and the right side tails off sooner.
let slots: [Bar?] = [
    Bar(height: 170, top: "#C9CCD6", bottom: "#B4B8C6"),
    Bar(height: 300, top: "#A9AEBE", bottom: "#9298AC"),
    Bar(height: 430, top: "#8A90A6", bottom: "#747B94"),
    nil,
    Bar(height: 400, top: "#8A90A6", bottom: "#747B94"),
    Bar(height: 260, top: "#A9AEBE", bottom: "#9298AC"),
    Bar(height: 150, top: "#C9CCD6", bottom: "#B4B8C6"),
]
/// Bars and the cursor stem share a width, so the cursor reads as one line of the waveform.
let barWidth: CGFloat = 56, barGap: CGFloat = 50

func slotX(_ i: Int) -> CGFloat {
    let n = CGFloat(slots.count)
    return canvas / 2 - (n * barWidth + (n - 1) * barGap) / 2 + CGFloat(i) * (barWidth + barGap)
}

/// Text cursor (I-beam), the tallest line.
struct Caret { var stemX: CGFloat, stemWidth: CGFloat, top: CGFloat, bottom: CGFloat, serifWidth: CGFloat, serifHeight: CGFloat, fillet: CGFloat }
let caretSlot = slots.firstIndex { $0 == nil }!
let caret = Caret(stemX: slotX(caretSlot), stemWidth: barWidth, top: 212, bottom: 812, serifWidth: 176, serifHeight: 50, fillet: 22)
let caretTop = "#3C8BFF", caretBottom = "#0A66F0"

func barRect(_ i: Int) -> CGRect {
    let h = slots[i]!.height
    return CGRect(x: slotX(i), y: canvas / 2 - h / 2, width: barWidth, height: h)
}

/// One closed outline: round-ended serifs joined to the stem with small fillets.
/// The shape is symmetric top to bottom, so it works in y-up and y-down space alike.
func caretPath(_ c: Caret) -> CGPath {
    let p = CGMutablePath()
    let cx = c.stemX + c.stemWidth / 2
    let l = cx - c.serifWidth / 2, r = cx + c.serifWidth / 2
    let sl = c.stemX, sr = c.stemX + c.stemWidth
    let t = c.top, b = c.bottom, h = c.serifHeight, rad = h / 2
    p.move(to: CGPoint(x: l + rad, y: t))
    p.addArc(center: CGPoint(x: r - rad, y: t + rad), radius: rad, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    if c.fillet > 0 {
        p.addArc(tangent1End: CGPoint(x: sr, y: t + h), tangent2End: CGPoint(x: sr, y: b), radius: c.fillet)
        p.addArc(tangent1End: CGPoint(x: sr, y: b - h), tangent2End: CGPoint(x: r, y: b - h), radius: c.fillet)
    } else {
        p.addLine(to: CGPoint(x: sr, y: t + h)); p.addLine(to: CGPoint(x: sr, y: b - h))
    }
    p.addArc(center: CGPoint(x: r - rad, y: b - rad), radius: rad, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addArc(center: CGPoint(x: l + rad, y: b - rad), radius: rad, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
    if c.fillet > 0 {
        p.addArc(tangent1End: CGPoint(x: sl, y: b - h), tangent2End: CGPoint(x: sl, y: t), radius: c.fillet)
        p.addArc(tangent1End: CGPoint(x: sl, y: t + h), tangent2End: CGPoint(x: l, y: t + h), radius: c.fillet)
    } else {
        p.addLine(to: CGPoint(x: sl, y: b - h)); p.addLine(to: CGPoint(x: sl, y: t + h))
    }
    p.addArc(center: CGPoint(x: l + rad, y: t + rad), radius: rad, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
    p.closeSubpath()
    return p
}

/// Background: a white page with a faint cool shade at the bottom.
let bgTop = "display-p3:1.00000,1.00000,1.00000,1.00000"
let bgBottom = "display-p3:0.89000,0.90000,0.93000,1.00000"
let bgTopHex = "#FFFFFF", bgBottomHex = "#E2E4EB"

// MARK: - SVG helpers

func svgPathData(_ path: CGPath) -> String {
    var d = ""
    func f(_ p: CGPoint) -> String { String(format: "%.2f %.2f", p.x, p.y) }
    path.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M\(f(pts[0]))"
        case .addLineToPoint: d += "L\(f(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0])) \(f(pts[1]))"
        case .addCurveToPoint: d += "C\(f(pts[0])) \(f(pts[1])) \(f(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func vGradient(_ id: String, _ top: String, _ bottom: String) -> String {
    "<linearGradient id=\"\(id)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(top)\"/><stop offset=\"1\" stop-color=\"\(bottom)\"/></linearGradient>"
}

func scaled(_ body: String) -> String {
    "<g transform=\"translate(512 512) scale(\(markScale)) translate(-512 -512)\">\(body)</g>"
}

func svgDocument(defs: String, body: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs>\(defs)</defs>
      \(body)
    </svg>

    """
}

func barSVG(_ i: Int, fill: String) -> String {
    let r = barRect(i)
    return String(format: "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"%.1f\" fill=\"%@\"/>",
                  r.minX, r.minY, r.width, r.height, r.width / 2, fill)
}

let caretD = svgPathData(caretPath(caret))
let caretGradient = vGradient("caret", caretTop, caretBottom)

// MARK: - Icon Composer bundle
//
// Groups, front to back: the cursor, then the voice bars, one glass layer each so each catches its own highlight.
// Dark mode keeps the system's dark page; only the cursor needs a brighter blue there.

try? fm.removeItem(at: iconBundle)
let assets = iconBundle.appendingPathComponent("Assets")
try! fm.createDirectory(at: assets, withIntermediateDirectories: true)
func writeAsset(_ name: String, _ svg: String) {
    try! svg.write(to: assets.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

writeAsset("Caret.svg", svgDocument(defs: caretGradient, body: scaled("<path d=\"\(caretD)\" fill=\"url(#caret)\"/>")))
let barSlots = slots.indices.filter { slots[$0] != nil }
for (n, i) in barSlots.enumerated() {
    writeAsset("Bar\(n + 1).svg", svgDocument(defs: vGradient("bar", slots[i]!.top, slots[i]!.bottom), body: scaled(barSVG(i, fill: "url(#bar)"))))
}

/// Dark mode recolours layers on its own unless they say otherwise.
func darkFill(_ p3: String) -> [String: Any] {
    ["fill-specializations": [["appearance": "dark", "value": ["solid": p3]]]]
}
func layer(_ name: String, glass: Bool = true, extra: [String: Any] = [:]) -> [String: Any] {
    ["image-name": "\(name).svg", "name": name, "glass": glass].merging(extra) { $1 }
}

let iconJSON: [String: Any] = [
    "fill": ["linear-gradient": [bgTop, bgBottom]],
    "groups": [
        [
            "name": "Cursor",
            "layers": [layer("Caret", extra: darkFill("display-p3:0.30000,0.60000,1.00000,1.00000"))],
            "lighting": "individual", "specular": true,
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.1],
        ],
        [
            "name": "Voice",
            "layers": barSlots.indices.map { layer("Bar\($0 + 1)") },
            "lighting": "individual", "specular": true,
            "shadow": ["kind": "neutral", "opacity": 0.35],
            "translucency": ["enabled": true, "value": 0.25],
        ],
    ],
    "supported-platforms": ["squares": ["macOS"]],
]

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}
writeJSON(iconJSON, to: iconBundle.appendingPathComponent("icon.json"))

// MARK: - Rendering helpers

let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func bitmap(_ w: Int, _ h: Int, space: CGColorSpace = srgb) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

func loadPNG(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

/// Renders the Icon Composer bundle with Xcode's own renderer.
func renderIcon(px: Int, rendition: String = "Default", to url: URL) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: ictool)
    task.arguments = [iconBundle.path, "--export-image", "--output-file", url.path, "--platform", "macOS",
                      "--rendition", rendition, "--width", "\(px)", "--height", "\(px)", "--scale", "1"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try! task.run()
    task.waitUntilExit()
    precondition(task.terminationStatus == 0, "ictool failed for \(rendition) \(px)px")
}

try! fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
let scratch = fm.temporaryDirectory.appendingPathComponent("speak-icon-\(getpid())")
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }

// MARK: - Asset catalog: fallback PNGs on Apple's macOS grid (824 pt body inset 100 pt, soft shadow)

let info = ["author": "xcode", "version": 1] as [String: Any]
let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try? fm.removeItem(at: appIconSet)
try! fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let bodyPx = Int((CGFloat(px) * 824 / canvas).rounded())
        let raw = scratch.appendingPathComponent("raw-\(px).png")
        renderIcon(px: bodyPx, to: raw)
        let ctx = bitmap(px, px, space: p3)
        let inset = (CGFloat(px) - CGFloat(bodyPx)) / 2
        ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(px) * 10 / canvas), blur: CGFloat(px) * 24 / canvas,
                      color: CGColor(gray: 0, alpha: 0.28))
        ctx.draw(loadPNG(raw), in: CGRect(x: inset, y: inset, width: CGFloat(bodyPx), height: CGFloat(bodyPx)))
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        writePNG(ctx.makeImage()!, to: appIconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
    }
}
writeJSON(["images": images, "info": info], to: appIconSet.appendingPathComponent("Contents.json"))

// MARK: - Menu bar glyphs (18 x 18 pt template, pixel-aligned at 1x, y up)

let glyphSize = CGSize(width: 18, height: 18)

func capsule(_ rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func drawGlyph(_ ctx: CGContext, recording: Bool) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    if !recording {
        // 1.5 pt lines (3 px on Retina) on a 4 pt pitch; the cursor in the middle spans the full height.
        for (i, h) in [(0, 6), (1, 10), (3, 8), (4, 4)] as [(Int, CGFloat)] {
            ctx.addPath(capsule(CGRect(x: CGFloat(i) * 4 + 0.25, y: 9 - h / 2, width: 1.5, height: h)))
        }
        ctx.addPath(caretPath(Caret(stemX: 8.25, stemWidth: 1.5, top: 1, bottom: 17, serifWidth: 5, serifHeight: 1.5, fillet: 0)))
        ctx.fillPath()
    } else {
        // Filled squircle with the mark knocked out (shapes must not overlap for even-odd).
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: glyphSize), cornerWidth: 5, cornerHeight: 5, transform: nil))
        for (i, h) in [(0, 4), (1, 6), (3, 6), (4, 4)] as [(Int, CGFloat)] {
            ctx.addPath(capsule(CGRect(x: 2.25 + CGFloat(i) * 3, y: 9 - h / 2, width: 1.5, height: h)))
        }
        ctx.addPath(caretPath(Caret(stemX: 8.25, stemWidth: 1.5, top: 3, bottom: 15, serifWidth: 5, serifHeight: 1.5, fillet: 0)))
        ctx.fillPath(using: .evenOdd)
    }
}

func writeGlyphPDF(recording: Bool, to url: URL) {
    var box = CGRect(origin: .zero, size: glyphSize)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawGlyph(ctx, recording: recording)
    ctx.endPDFPage()
    ctx.closePDF()
}

for (name, recording) in [("MenuBarIcon", false), ("MenuBarIconRecording", true)] {
    let set = catalog.appendingPathComponent("\(name).imageset")
    try? fm.removeItem(at: set)
    try! fm.createDirectory(at: set, withIntermediateDirectories: true)
    writeGlyphPDF(recording: recording, to: set.appendingPathComponent("\(name).pdf"))
    writeJSON([
        "images": [["filename": "\(name).pdf", "idiom": "universal"]],
        "info": info,
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ], to: set.appendingPathComponent("Contents.json"))
}

// MARK: - Website favicon: the same art, flattened

do {
    let defs = vGradient("bg", bgTopHex, bgBottomHex) + caretGradient
        + barSlots.map { vGradient("bar\($0)", slots[$0]!.top, slots[$0]!.bottom) }.joined()
    // Hairline edge so the white page doesn't vanish on white browser tabs.
    let body = """
    <rect x="4" y="4" width="1016" height="1016" rx="228" fill="url(#bg)" stroke="#C9CCD6" stroke-width="8"/>
      \(scaled(barSlots.map { barSVG($0, fill: "url(#bar\($0))") }.joined() + "<path d=\"\(caretD)\" fill=\"url(#caret)\"/>"))
    """
    try! svgDocument(defs: defs, body: body).write(to: root.appendingPathComponent("site/icon.svg"), atomically: true, encoding: .utf8)
}

// MARK: - Previews

for rendition in ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"] {
    renderIcon(px: 512, rendition: rendition, to: previewDir.appendingPathComponent("appicon-\(rendition).png"))
}
for (px, file) in [(16, "icon_16x16"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128")] {
    let dest = previewDir.appendingPathComponent("appicon-\(px).png")
    try? fm.removeItem(at: dest)
    try! fm.copyItem(at: appIconSet.appendingPathComponent("\(file).png"), to: dest)
}
do {
    // Menu bar: both glyphs at 1x and 2x on light and dark bars, magnified 8x (nearest neighbour).
    let mag = 8, barH = 24, colW = 34
    let w = 4 * colW * mag, h = 2 * barH * mag
    let ctx = bitmap(w, h)
    ctx.interpolationQuality = .none
    for (row, (bg, fg)) in [(CGColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1), CGColor(gray: 0.1, alpha: 1)),
                            (CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1), CGColor(gray: 1, alpha: 0.92))].enumerated() {
        let y = (1 - row) * barH * mag
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y, width: w, height: barH * mag))
        for (col, (recording, scale)) in [(false, 1), (true, 1), (false, 2), (true, 2)].enumerated() {
            let g = bitmap(18 * scale, 18 * scale)
            g.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            drawGlyph(g, recording: recording)
            let tinted = bitmap(18 * scale, 18 * scale)
            tinted.clip(to: CGRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale), mask: g.makeImage()!)
            tinted.setFillColor(fg); tinted.fill(CGRect(x: 0, y: 0, width: 18 * scale, height: 18 * scale))
            ctx.draw(tinted.makeImage()!, in: CGRect(x: (col * colW + 8) * mag, y: y + 3 * mag, width: 18 * mag, height: 18 * mag))
        }
    }
    writePNG(ctx.makeImage()!, to: previewDir.appendingPathComponent("menubar.png"))
}

print("Wrote \(iconBundle.path), \(catalog.path), site/icon.svg; previews in \(previewDir.path)")
