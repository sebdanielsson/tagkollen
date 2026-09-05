// Renders the app icon layers for the Icon Composer package at Tagkollen/AppIcon.icon and a
// flattened 1024×1024 preview for the App Store / README.
//
//   swift Scripts/make-app-icon.swift
//
// The glyph is an original front view of a train drawn with CoreGraphics paths. Apple's SF Symbols
// licence forbids using SF Symbols (or confusingly similar glyphs) in app icons, so nothing here is
// derived from the symbol set. Layers are white on transparent; Icon Composer supplies the
// Trafikverket-red background and derives the dark, clear and tinted appearances.
import AppKit

let side = 1024
let iconDir = URL(fileURLWithPath: "Tagkollen/AppIcon.icon/Assets")
let marketingDir = URL(fileURLWithPath: "Marketing")

/// Trafikverket's main red, RGB 215 0 0 (#D70000), and the darker shade used for the dark appearance (#AF0000).
let trafikverketRed = NSColor(srgbRed: 215 / 255, green: 0, blue: 0, alpha: 1)
let trafikverketDarkRed = NSColor(srgbRed: 175 / 255, green: 0, blue: 0, alpha: 1)

func context() -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }
    return ctx
}

func write(_ ctx: CGContext, to url: URL, opaque: Bool) {
    guard let image = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! png.write(to: url)
    print("wrote \(url.path) \(image.width)x\(image.height)\(opaque ? "" : " (alpha)")")
}

// MARK: Glyph geometry (origin bottom-left, 1024 canvas)

/// Train body seen from the front: a tall rounded nose with a windshield and two headlights cut out.
func trainPath() -> CGPath {
    let path = CGMutablePath()
    // Body: wide rounded top, gently flared skirt.
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 262, y: 300))
    body.addLine(to: CGPoint(x: 262, y: 560))
    body.addCurve(to: CGPoint(x: 512, y: 812), control1: CGPoint(x: 262, y: 720), control2: CGPoint(x: 372, y: 812))
    body.addCurve(to: CGPoint(x: 762, y: 560), control1: CGPoint(x: 652, y: 812), control2: CGPoint(x: 762, y: 720))
    body.addLine(to: CGPoint(x: 762, y: 300))
    body.addCurve(to: CGPoint(x: 722, y: 262), control1: CGPoint(x: 762, y: 278), control2: CGPoint(x: 744, y: 262))
    body.addLine(to: CGPoint(x: 302, y: 262))
    body.addCurve(to: CGPoint(x: 262, y: 300), control1: CGPoint(x: 280, y: 262), control2: CGPoint(x: 262, y: 278))
    body.closeSubpath()
    path.addPath(body)

    // Windshield (cut out with even-odd fill).
    let windshield = CGRect(x: 322, y: 560, width: 380, height: 150)
    path.addPath(CGPath(roundedRect: windshield, cornerWidth: 54, cornerHeight: 54, transform: nil))
    // Headlights.
    path.addEllipse(in: CGRect(x: 322, y: 352, width: 96, height: 96))
    path.addEllipse(in: CGRect(x: 606, y: 352, width: 96, height: 96))
    // Coupler slot at the bottom.
    path.addPath(CGPath(roundedRect: CGRect(x: 468, y: 296, width: 88, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
    return path
}

/// Two rails running towards the viewer and a few sleepers, below the train.
func railsPath() -> CGPath {
    let path = CGMutablePath()
    let rail = CGMutablePath()
    rail.move(to: CGPoint(x: 340, y: 246))
    rail.addLine(to: CGPoint(x: 214, y: 112))
    rail.move(to: CGPoint(x: 684, y: 246))
    rail.addLine(to: CGPoint(x: 810, y: 112))
    path.addPath(rail.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10))
    for (y, inset) in [(212.0, 308.0), (160.0, 259.0), (112.0, 214.0)] {
        let sleeper = CGMutablePath()
        sleeper.move(to: CGPoint(x: inset, y: y))
        sleeper.addLine(to: CGPoint(x: 1024 - inset, y: y))
        path.addPath(sleeper.copy(strokingWithWidth: 22, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }
    return path
}

func renderLayer(_ shape: CGPath, evenOdd: Bool, file: String) {
    let ctx = context()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(shape)
    if evenOdd {
        ctx.fillPath(using: .evenOdd)
    } else {
        ctx.fillPath()
    }
    write(ctx, to: iconDir.appendingPathComponent(file), opaque: false)
}

/// Flattened preview: background colour plus the two layers, the way iOS 18-style flat icons looked.
func renderFlat(background: NSColor, file: String) {
    let ctx = context()
    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    ctx.addPath(railsPath())
    ctx.fillPath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(trainPath())
    ctx.fillPath(using: .evenOdd)
    write(ctx, to: marketingDir.appendingPathComponent(file), opaque: true)
}

renderLayer(trainPath(), evenOdd: true, file: "train.png")
renderLayer(railsPath(), evenOdd: false, file: "rails.png")
renderFlat(background: trafikverketRed, file: "AppIcon-1024.png")
renderFlat(background: trafikverketDarkRed, file: "AppIcon-1024-dark.png")
