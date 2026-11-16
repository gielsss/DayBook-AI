// Renders the DayBook AI app icon PNGs from the same drawing code the app uses
// (Sources/PersonalPlanner/Views/Components/DayBookMarkDrawing.swift).
// Usage: icon_renderer <output-iconset-dir> [<output-1024-png>]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    // Flip to a top-left origin, as the drawing code expects.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let simplified = size < DayBookMarkDrawing.simplifiedBelowPixels
    let tileRect: CGRect
    if simplified {
        // Small sizes: fill more of the canvas and skip the shadow so the shapes stay crisp.
        let inset = (size * 0.06).rounded()
        tileRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    } else {
        // macOS icon grid: 824/1024 tile with a soft drop shadow.
        let tile = size * 824 / 1024
        tileRect = CGRect(x: (size - tile) / 2, y: (size - tile) / 2, width: tile, height: tile)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
        let path = CGPath(roundedRect: tileRect, cornerWidth: tileRect.width * DayBookMarkDrawing.cornerFraction,
                          cornerHeight: tileRect.width * DayBookMarkDrawing.cornerFraction, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(DayBookMarkDrawing.navy)
        ctx.fillPath()
        ctx.restoreGState()
    }
    DayBookMarkDrawing.draw(in: ctx, rect: tileRect, style: .standard, simplified: simplified)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(url.path)") }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: icon_renderer <iconset-dir> [<1024-png>]")
    exit(1)
}
let iconset = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in entries {
    writePNG(renderIcon(pixels: px), to: iconset.appendingPathComponent(name))
}
if args.count >= 3 {
    writePNG(renderIcon(pixels: 1024), to: URL(fileURLWithPath: args[2]))
}
print("Rendered \(entries.count) icon sizes")
