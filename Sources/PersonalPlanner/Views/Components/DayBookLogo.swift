import SwiftUI
import AppKit

/// Brand colors for the logo itself. These stay fixed across Light / Colorful (the logo is not
/// re-tinted); Dark Mode uses the reversed lockup from the brand sheet (cream text, bright amber).
private extension Color {
    static func dbLogoAdaptive(light: UInt32, dark: UInt32) -> Color {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? rgb(dark) : rgb(light)
        })
    }
    /// "daybook": navy on light backgrounds, paper cream on dark.
    static let dbLogoWord = dbLogoAdaptive(light: 0x1C2A4E, dark: 0xFAF5EE)
    /// "AI": the logo's deep amber, brightened on dark backgrounds.
    static let dbLogoAI = dbLogoAdaptive(light: 0xD97706, dark: 0xF5A623)
}

/// The DayBook AI mark at any size. Below 64 pixels it switches to the simplified drawing
/// (no sparkle, thicker book and sun). In Dark Mode it uses the reversed (cream) tile so it
/// stays visible on dark backgrounds.
public struct DayBookMark: View {
    let size: CGFloat
    let style: DayBookMarkStyle?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// - Parameter style: nil picks standard in light looks and reversed in Dark Mode.
    public init(size: CGFloat, style: DayBookMarkStyle? = nil) {
        self.size = size
        self.style = style
    }

    public var body: some View {
        let resolved = style ?? (colorScheme == .dark ? .reversed : .standard)
        let simplified = size * displayScale < DayBookMarkDrawing.simplifiedBelowPixels
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                DayBookMarkDrawing.draw(in: cg, rect: CGRect(origin: .zero, size: canvasSize),
                                        style: resolved, simplified: simplified)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "daybook" + "AI" wordmark.
public struct DayBookWordmark: View {
    let fontSize: CGFloat

    public init(fontSize: CGFloat) {
        self.fontSize = fontSize
    }

    public var body: some View {
        (Text("daybook").foregroundColor(.dbLogoWord) + Text(" AI").foregroundColor(.dbLogoAI))
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(-fontSize * 0.02)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("DayBook AI")
    }
}

/// Mark + wordmark, with the optional tagline "Your day, written down".
public struct DayBookLockup: View {
    let markSize: CGFloat
    let showsTagline: Bool

    public init(markSize: CGFloat = 24, showsTagline: Bool = false) {
        self.markSize = markSize
        self.showsTagline = showsTagline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: markSize * 0.3) {
            HStack(spacing: markSize * 0.4) {
                DayBookMark(size: markSize)
                DayBookWordmark(fontSize: markSize * 0.72)
            }
            if showsTagline {
                // One tracked line under the lockup, as on the brand sheet.
                Text(DayBookBrand.tagline.uppercased())
                    .font(.system(size: max(8, markSize * 0.29), weight: .semibold))
                    .tracking(markSize * 0.05)
                    .foregroundStyle(Color.dbLogoWord.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public enum DayBookBrand {
    public static let name = "DayBook AI"
    public static let tagline = "Your day, written down"

    /// Standard About panel with the tagline under the app name and icon.
    @MainActor public static func showAboutPanel() {
        let credits = NSAttributedString(string: tagline, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: name])
        NSApp.activate(ignoringOtherApps: true)
    }
}
