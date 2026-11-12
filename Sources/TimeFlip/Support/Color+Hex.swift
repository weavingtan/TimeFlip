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

    /// 感知亮度（0…1）：用来判断主题是深色还是浅色，机身/描边据此反向着色。
    var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
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
