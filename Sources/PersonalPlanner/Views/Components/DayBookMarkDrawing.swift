import CoreGraphics

/// The DayBook AI mark (navy tile, open book, rising sun, sparkle) drawn with CoreGraphics.
/// This file has no SwiftUI/AppKit dependency so the same drawing renders both the in-app logo
/// (`DayBookMark`) and the app icon PNGs (`scripts/icon_renderer`). Geometry is measured from the
/// logo artwork and expressed in a unit square (0...1, origin top-left, y pointing down).
public enum DayBookMarkStyle: Sendable {
    /// Navy tile, cream book, amber sun and sparkle (the primary icon).
    case standard
    /// Cream tile, navy book, amber sun and sparkle (for navy or dark backgrounds).
    case reversed
}

public enum DayBookMarkDrawing {
    /// Below this many pixels the sparkle drops out and the book and sun thicken (logo guideline).
    public static let simplifiedBelowPixels: CGFloat = 64

    public static let navy = CGColor(srgbRed: 0x1C / 255, green: 0x2A / 255, blue: 0x4E / 255, alpha: 1)
    public static let cream = CGColor(srgbRed: 0xFA / 255, green: 0xF5 / 255, blue: 0xEE / 255, alpha: 1)
    public static let amber = CGColor(srgbRed: 0xF0 / 255, green: 0xA5 / 255, blue: 0x3A / 255, alpha: 1)

    /// Tile corner radius as a fraction of the tile size (matches the macOS icon shape).
    public static let cornerFraction: CGFloat = 0.225

    private struct Geometry {
        var pageOuterX: CGFloat      // distance of the outer page edge from the tile's left edge
        var pageInnerX: CGFloat      // inner (spine-side) edge of the left page
        var topOuterY: CGFloat
        var topCenterY: CGFloat
        var spineTopY: CGFloat
        var bottomOuterY: CGFloat
        var bottomCenterY: CGFloat
        var topControl: CGPoint
        var bottomControl: CGPoint
        var sunCenter: CGPoint
        var sunRadius: CGFloat
        var sparkle: (center: CGPoint, radius: CGFloat, waist: CGFloat)?
    }

    private static let full = Geometry(
        pageOuterX: 0.182, pageInnerX: 0.489,
        topOuterY: 0.376, topCenterY: 0.447, spineTopY: 0.47,
        bottomOuterY: 0.631, bottomCenterY: 0.692,
        topControl: CGPoint(x: 0.30, y: 0.365), bottomControl: CGPoint(x: 0.34, y: 0.615),
        sunCenter: CGPoint(x: 0.5, y: 0.35), sunRadius: 0.108,
        sparkle: (CGPoint(x: 0.75, y: 0.216), 0.067, 0.02)
    )

    /// Small-size variant: no sparkle, larger book and sun, wider spine so it stays readable.
    private static let simplified = Geometry(
        pageOuterX: 0.13, pageInnerX: 0.47,
        topOuterY: 0.40, topCenterY: 0.49, spineTopY: 0.53,
        bottomOuterY: 0.71, bottomCenterY: 0.79,
        topControl: CGPoint(x: 0.27, y: 0.385), bottomControl: CGPoint(x: 0.31, y: 0.69),
        sunCenter: CGPoint(x: 0.5, y: 0.355), sunRadius: 0.155,
        sparkle: nil
    )

    /// Draws the mark filling `rect` in a context whose origin is top-left (y down), as in
    /// SwiftUI `Canvas`. For a bottom-left bitmap context, flip the CTM first.
    public static func draw(in ctx: CGContext, rect: CGRect, style: DayBookMarkStyle, simplified useSimplified: Bool) {
        let g = useSimplified ? simplified : full
        let s = min(rect.width, rect.height)
        let o = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }

        let tileColor = style == .standard ? navy : cream
        let pageColor = style == .standard ? cream : navy

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Tile
        let tile = CGPath(roundedRect: CGRect(x: o.x, y: o.y, width: s, height: s),
                          cornerWidth: s * cornerFraction, cornerHeight: s * cornerFraction, transform: nil)
        ctx.addPath(tile)
        ctx.setFillColor(tileColor)
        ctx.fillPath()

        // Sun (behind the book)
        ctx.setFillColor(amber)
        let r = g.sunRadius * s
        let c = p(g.sunCenter.x, g.sunCenter.y)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

        // Sparkle: four-point star with straight sides and a narrow waist
        if let sp = g.sparkle {
            let sc = p(sp.center.x, sp.center.y)
            let R = sp.radius * s, w = sp.waist * s
            let star = CGMutablePath()
            star.addLines(between: [
                CGPoint(x: sc.x, y: sc.y - R), CGPoint(x: sc.x + w, y: sc.y - w),
                CGPoint(x: sc.x + R, y: sc.y), CGPoint(x: sc.x + w, y: sc.y + w),
                CGPoint(x: sc.x, y: sc.y + R), CGPoint(x: sc.x - w, y: sc.y + w),
                CGPoint(x: sc.x - R, y: sc.y), CGPoint(x: sc.x - w, y: sc.y - w),
            ])
            star.closeSubpath()
            ctx.addPath(star)
            ctx.fillPath()
        }

        // Open book: two pages meeting at the center, then a tile-colored spine with a rounded top
        ctx.setFillColor(pageColor)
        for mirrored in [false, true] {
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(mirrored ? 1 - x : x, y) }
            let page = CGMutablePath()
            page.move(to: q(g.pageOuterX, g.topOuterY))
            page.addQuadCurve(to: q(0.5, g.topCenterY), control: q(g.topControl.x, g.topControl.y))
            page.addLine(to: q(0.5, g.bottomCenterY + 0.01))
            page.addQuadCurve(to: q(g.pageOuterX, g.bottomOuterY), control: q(g.bottomControl.x, g.bottomControl.y))
            page.closeSubpath()
            ctx.addPath(page)
            ctx.fillPath()
        }
        let spineWidth = (0.5 - g.pageInnerX) * 2 * s
        let spineTop = p(0.5, g.spineTopY)
        let spine = CGPath(roundedRect: CGRect(x: spineTop.x - spineWidth / 2, y: spineTop.y,
                                               width: spineWidth, height: (g.bottomCenterY + 0.02 - g.spineTopY) * s),
                           cornerWidth: spineWidth / 2, cornerHeight: spineWidth / 2, transform: nil)
        ctx.addPath(spine)
        ctx.setFillColor(tileColor)
        ctx.fillPath()
    }
}
