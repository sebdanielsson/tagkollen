// Renders the app icon variants (light / dark / tinted) as opaque 1024×1024 PNGs.
// Usage: swift Scripts/make-app-icon.swift
import AppKit

let side = 1024
let outDir = URL(fileURLWithPath: "Tagkollen/Resources/Assets.xcassets/AppIcon.appiconset")

func render(background: [NSColor], glyph: NSColor, file: String) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("no context") }
    let size = CGSize(width: side, height: side)

    let colors = background.map(\.cgColor) as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

    // Subtle diagonal rail lines across the lower part.
    ctx.setStrokeColor(glyph.withAlphaComponent(0.16).cgColor)
    ctx.setLineWidth(14)
    for y in stride(from: 140.0, through: 320.0, by: 60) {
        ctx.move(to: CGPoint(x: -20, y: y))
        ctx.addLine(to: CGPoint(x: size.width + 20, y: y - 70))
        ctx.strokePath()
    }

    let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [glyph]))
    if let symbol = NSImage(systemSymbolName: "train.side.front.car", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let scale = min(700 / symbolSize.width, 700 / symbolSize.height)
        let drawSize = CGSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2 + 30)
        symbol.draw(in: CGRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! png.write(to: outDir.appendingPathComponent(file))
    print("wrote \(file) \(cgImage.width)x\(cgImage.height)")
}

render(background: [NSColor(red: 0.00, green: 0.38, blue: 0.86, alpha: 1), NSColor(red: 0.10, green: 0.68, blue: 0.95, alpha: 1)],
       glyph: .white, file: "AppIcon.png")
render(background: [NSColor(red: 0.03, green: 0.07, blue: 0.16, alpha: 1), NSColor(red: 0.04, green: 0.20, blue: 0.42, alpha: 1)],
       glyph: NSColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1), file: "AppIcon-Dark.png")
render(background: [NSColor.black, NSColor(white: 0.12, alpha: 1)], glyph: .white, file: "AppIcon-Tinted.png")
