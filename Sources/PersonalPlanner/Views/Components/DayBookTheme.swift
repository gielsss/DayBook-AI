import SwiftUI
import AppKit

/// Window look chosen in the toolbar or Settings. Stored in UserDefaults (UI-only, not planner data).
public enum DayBookAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, colorful

    public static let storageKey = "dayBookAppearance"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .colorful: return "Colorful"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .colorful: return "paintpalette"
        }
    }

    /// The macOS appearance to force; nil follows System Settings. Colorful is a light look.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light, .colorful: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The look currently in effect. Read by the adaptive colors below.
    nonisolated(unsafe) public static var current: DayBookAppearance =
        DayBookAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system

    /// Applies a look to every window (main window, sheets, Quick Capture panel).
    @MainActor public static func apply(_ appearance: DayBookAppearance) {
        current = appearance
        NSApp?.appearance = appearance.nsAppearance
    }
}

/// DayBook AI design language, taken from the logo: deep navy, warm amber, paper cream.
/// Apple-style restraint: one accent (amber), one secondary hue (navy) for calendar/info,
/// and system red/green/orange only for status (overdue, done, warnings).
public extension Color {
    private static func adaptive(light: NSColor, dark: NSColor, colorful: NSColor? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil { return dark }
            if DayBookAppearance.current == .colorful, let colorful { return colorful }
            return light
        })
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// The logo's amber: the app's accent (your planned work, primary actions, selection).
    static let dbAccent = adaptive(light: rgb(0xD98A1E), dark: rgb(0xF0A83E), colorful: rgb(0xE07B12))
    /// The logo's navy: calendar commitments and informational text. Lightened in Dark Mode.
    static let dbNavy = adaptive(light: rgb(0x1D2A4C), dark: rgb(0xA9B8D8), colorful: rgb(0x2A4A9E))
    /// Card surface: warm white on the paper page; a lifted navy panel at night.
    static let dbSurface = adaptive(light: rgb(0xFFFDF9), dark: rgb(0x1E2B4A), colorful: rgb(0xFFFCF5))
    /// Hairline used for card borders and separators (navy-tinted, cream at night).
    static let dbHairline = adaptive(light: rgb(0x1C2A4E, 0.10), dark: rgb(0xFAF5EE, 0.10), colorful: rgb(0xD98A1E, 0.28))
    /// Page background: the marketing sheet's paper cream by day, the reversed logo's navy by night.
    static let dbBackground = adaptive(light: rgb(0xFBF6EE), dark: rgb(0x141D33), colorful: rgb(0xF6EEDC))
    /// Sidebar: a deeper sand than the page by day, deep navy by night.
    static let dbSidebar = adaptive(light: rgb(0xF3EADC), dark: rgb(0x0F172B), colorful: rgb(0xEEDFC2))
    /// Headline ink: logo navy by day, paper cream by night (the reversed lockup).
    static let dbInk = adaptive(light: rgb(0x1C2A4E), dark: rgb(0xFAF5EE), colorful: rgb(0x1C2A4E))
}

public extension ShapeStyle where Self == Color {
    static var dbAccent: Color { Color.dbAccent }
    static var dbNavy: Color { Color.dbNavy }
    static var dbSurface: Color { Color.dbSurface }
    static var dbHairline: Color { Color.dbHairline }
    static var dbBackground: Color { Color.dbBackground }
    static var dbInk: Color { Color.dbInk }
}

/// A rounded card with a hairline border, used for every grouped block in the app.
/// In Colorful mode a card with a `tint` is washed in that color.
public struct DayBookCard: ViewModifier {
    var padding: CGFloat = 14
    var tint: Color? = nil
    @AppStorage(DayBookAppearance.storageKey) private var appearance: DayBookAppearance = .system

    public func body(content: Content) -> some View {
        // Rounder corners echo the app icon's tile.
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let wash = appearance == .colorful ? tint : nil
        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(Color.dbSurface)
                    if let wash { shape.fill(wash.opacity(0.16)) }
                }
            }
            .overlay(shape.stroke(wash.map { $0.opacity(0.4) } ?? Color.dbHairline, lineWidth: 1))
    }
}

public extension View {
    func dayBookCard(padding: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(DayBookCard(padding: padding, tint: tint))
    }
}

/// Toolbar control for switching between Match System, Light, Dark and Colorful.
public struct DayBookAppearanceMenu: View {
    @AppStorage(DayBookAppearance.storageKey) private var appearance: DayBookAppearance = .system
    public init() {}

    public var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(DayBookAppearance.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Appearance", systemImage: appearance.systemImage)
        }
        .help("Appearance: \(appearance.title)")
    }
}

/// Page header used at the top of each tab: large bold title, quiet subtitle.
public struct DayBookPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    static var eyebrowDate: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: Date())
    }

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                // Journal-page eyebrow in the logo tagline's voice: "✦ SUNDAY, NOVEMBER 8"
                DayBookEyebrow(Self.eyebrowDate)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.dbInk)
                if let subtitle {
                    Text(subtitle).font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

/// Small quiet label ("Busy", "Demo", calendar names): a colored dot plus secondary text,
/// instead of a filled colored capsule.
public struct DayBookTag: View {
    let text: String
    let color: Color?

    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Small amber "Updated" reminder next to a task that a sync updated instead of duplicating.
/// Hover shows what changed.
public struct TaskUpdatedBadge: View {
    let update: TaskSyncUpdate

    public init(_ update: TaskSyncUpdate) {
        self.update = update
    }

    public var body: some View {
        Label("Updated", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.dbAccent)
            .help("\(update.summary) (from \(update.source))")
    }
}

/// "Start now" / "Start soon" / "On track" / "Won't fit" from the planner's slack judgement.
/// Hover explains how much free time is left before the deadline.
public struct UrgencyTag: View {
    let urgency: TaskUrgency

    public init(_ urgency: TaskUrgency) {
        self.urgency = urgency
    }

    private var color: Color {
        switch urgency.level {
        case .overbooked: return .red
        case .startNow: return .orange
        case .startSoon: return .dbAccent
        case .onTrack: return .secondary
        }
    }

    public var body: some View {
        Text(urgency.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .help(urgency.explanation)
    }
}
