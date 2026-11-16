import SwiftUI
import AppKit

public extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }
        
        var rgb: UInt64 = 0
        if Scanner(string: hexSanitized).scanHexInt64(&rgb) {
            let length = hexSanitized.count
            if length == 6 {
                let r = Double((rgb & 0xFF0000) >> 16) / 255.0
                let g = Double((rgb & 0x00FF00) >> 8) / 255.0
                let b = Double(rgb & 0x0000FF) / 255.0
                self.init(red: r, green: g, blue: b)
                return
            } else if length == 8 {
                let r = Double((rgb & 0xFF000000) >> 24) / 255.0
                let g = Double((rgb & 0x00FF0000) >> 16) / 255.0
                let b = Double((rgb & 0x0000FF00) >> 8) / 255.0
                let a = Double(rgb & 0x000000FF) / 255.0
                self.init(red: r, green: g, blue: b, opacity: a)
                return
            }
        }
        self.init(.sRGB, red: 0.04, green: 0.52, blue: 1.0, opacity: 1.0)
    }
}
