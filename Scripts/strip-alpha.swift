// Rewrites each PNG given on the command line as an opaque RGB image, in place.
//
//   swift Scripts/strip-alpha.swift fastlane/screenshots/en-US/*.png
//
// The simulator always writes RGBA, and App Store Connect rejects screenshots that carry an alpha
// channel — even a fully opaque one. `sips` cannot drop the channel (it re-adds it on every
// conversion), so the flattening happens through CoreGraphics.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("strip-alpha: \(message)\n".utf8))
    exit(1)
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else { fail("no files given") }

for path in paths {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read \(path)") }

    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: image.width, height: image.height,
              bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { fail("cannot make a context for \(path)") }

    // White underneath, so any translucent pixel lands on the same ground the store shows.
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(rect)
    context.draw(image, in: rect)

    guard let opaque = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(path)") }
    CGImageDestinationAddImage(destination, opaque, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot finalise \(path)") }
}
