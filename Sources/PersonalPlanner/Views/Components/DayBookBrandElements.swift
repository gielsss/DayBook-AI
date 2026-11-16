import SwiftUI

/// Small tracked uppercase line with an amber sparkle, in the voice of the logo's tagline
/// ("YOUR DAY, WRITTEN DOWN").
public struct DayBookEyebrow: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.dbAccent)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.dbInk.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A glyph in a rounded-square tile, like the app icon. Used for stat cards and section icons.
public struct DayBookIconTile: View {
    let systemImage: String
    let color: Color
    let size: CGFloat

    public init(systemImage: String, color: Color, size: CGFloat = 26) {
        self.systemImage = systemImage
        self.color = color
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Settings-style grouped box drawn as a DayBook card: navy title with an amber icon above a
/// warm card, instead of the system's flat gray box.
public struct DayBookGroupBoxStyle: GroupBoxStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
                .foregroundStyle(Color.dbInk)
                .labelStyle(DayBookAccentIconLabelStyle())
                .padding(.leading, 2)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
                .dayBookCard(padding: 12)
        }
    }
}

/// Label with the icon in brand amber and the title in the current foreground style.
public struct DayBookAccentIconLabelStyle: LabelStyle {
    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.foregroundStyle(Color.dbAccent)
            configuration.title
        }
    }
}

/// Friendly empty state built around the logo mark.
public struct DayBookEmptyState: View {
    let title: String
    let message: String?

    public init(_ title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            DayBookMark(size: 56)
                .opacity(0.9)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.dbInk)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

/// Time-of-day greeting for the Today page.
public enum DayBookGreeting {
    public static func current(at date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
