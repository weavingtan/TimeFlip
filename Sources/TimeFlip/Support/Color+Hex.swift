import AppKit
import SwiftUI

extension RGBAColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: max(0, min(1, opacity)))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func nsColor(opacity: Double) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: max(0, min(1, opacity)))
    }
}

extension ClockFontWeight {
    var swiftUI: Font.Weight {
        switch self {
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var nsWeight: NSFont.Weight {
        switch self {
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}
