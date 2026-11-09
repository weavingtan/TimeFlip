import Foundation

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: String, alpha: Double = 1) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.red = Double((value >> 16) & 0xFF) / 255
        self.green = Double((value >> 8) & 0xFF) / 255
        self.blue = Double(value & 0xFF) / 255
        self.alpha = alpha
    }

    public var hexString: String {
        String(
            format: "#%02lX%02lX%02lX",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    public static let ink = RGBAColor(hex: "#1A1A1A") ?? RGBAColor(red: 0.1, green: 0.1, blue: 0.1)
    public static let paper = RGBAColor(hex: "#FFFFFF", alpha: 0.9) ?? RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.9)
}

public enum ClockStyle: String, Codable, Sendable {
    case flip
    case digital
}

public enum ClockFontWeight: String, Codable, Sendable {
    case bold
    case heavy
    case black
}

public enum ShowMode: String, Codable, Sendable {
    case auto
    case countdownOnly
    case clockOnly
}

public enum WindowForm: String, Codable, Sendable {
    case floating
    case fullScreen
}

public enum WindowLayer: String, Codable, Sendable {
    case desktop
    case floating
}

public struct ClockAppearance: Codable, Equatable, Sendable {
    public var style: ClockStyle = .flip
    public var fontFamily: String = "Helvetica Neue"
    public var fontWeight: ClockFontWeight = .heavy
    public var fontSize: Double = 96
    public var textColor: RGBAColor = .ink
    public var backgroundColor: RGBAColor = .paper
    public var backgroundOpacity: Double = 0.9
    public var shadowEnabled: Bool = true
    public var shadowRadius: Double = 12
    public var shadowOpacity: Double = 0.25
    public var showSeconds: Bool = true
    public var showDate: Bool = true
    public var showBottomLine: Bool = true
    public var use24Hour: Bool = true
    public var colonBlink: Bool = true
    public var showLeadingZero: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, fontFamily, fontWeight, fontSize, textColor, backgroundColor
        case backgroundOpacity, shadowEnabled, shadowRadius, shadowOpacity
        case showSeconds, showDate, showBottomLine, use24Hour, colonBlink, showLeadingZero
    }

    public init(from decoder: Decoder) throws {
        let fallback = ClockAppearance()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? container.decode(ClockStyle.self, forKey: .style)) ?? fallback.style
        fontFamily = (try? container.decode(String.self, forKey: .fontFamily)) ?? fallback.fontFamily
        fontWeight = (try? container.decode(ClockFontWeight.self, forKey: .fontWeight)) ?? fallback.fontWeight
        fontSize = (try? container.decode(Double.self, forKey: .fontSize)) ?? fallback.fontSize
        textColor = (try? container.decode(RGBAColor.self, forKey: .textColor)) ?? fallback.textColor
        backgroundColor = (try? container.decode(RGBAColor.self, forKey: .backgroundColor)) ?? fallback.backgroundColor
        backgroundOpacity = (try? container.decode(Double.self, forKey: .backgroundOpacity)) ?? fallback.backgroundOpacity
        shadowEnabled = (try? container.decode(Bool.self, forKey: .shadowEnabled)) ?? fallback.shadowEnabled
        shadowRadius = (try? container.decode(Double.self, forKey: .shadowRadius)) ?? fallback.shadowRadius
        shadowOpacity = (try? container.decode(Double.self, forKey: .shadowOpacity)) ?? fallback.shadowOpacity
        showSeconds = (try? container.decode(Bool.self, forKey: .showSeconds)) ?? fallback.showSeconds
        showDate = (try? container.decode(Bool.self, forKey: .showDate)) ?? fallback.showDate
        showBottomLine = (try? container.decode(Bool.self, forKey: .showBottomLine)) ?? fallback.showBottomLine
        use24Hour = (try? container.decode(Bool.self, forKey: .use24Hour)) ?? fallback.use24Hour
        colonBlink = (try? container.decode(Bool.self, forKey: .colonBlink)) ?? fallback.colonBlink
        showLeadingZero = (try? container.decode(Bool.self, forKey: .showLeadingZero)) ?? fallback.showLeadingZero
    }
}

public struct ClockBehavior: Codable, Equatable, Sendable {
    public var showMode: ShowMode = .auto
    public var form: WindowForm = .floating
    public var layer: WindowLayer = .desktop
    public var visible: Bool = true

    public init() {}
}

public struct MenuBarSettings: Codable, Equatable, Sendable {
    public enum Style: String, Codable, Sendable {
        case iconAndTime
        case timeOnly
        case iconOnly
    }

    public var style: Style = .iconAndTime
    public var showProgressRing: Bool = true

    public init() {}
}

public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘T：cmdKey 256 | optionKey 2048 | controlKey 4096 = 6400，kVK_ANSI_T = 17
    public static let `default` = HotKeySpec(keyCode: 17, modifiers: 256 | 2048 | 4096)
}

public struct WindowOrigin: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TimerSettings: Codable, Equatable, Sendable {
    public var durations: Durations = .standard
    public var autoStartNext: Bool = false
    public var soundName: String? = "Glass"
    public var hotKey: HotKeySpec = .default

    public init() {}
}

public struct TimeFlipSettings: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var timer: TimerSettings = TimerSettings()
    public var appearance: ClockAppearance = ClockAppearance()
    public var behavior: ClockBehavior = ClockBehavior()
    public var menuBar: MenuBarSettings = MenuBarSettings()
    public var windowPlacements: [String: WindowOrigin] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, timer, appearance, behavior, menuBar, windowPlacements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        timer = (try? container.decode(TimerSettings.self, forKey: .timer)) ?? TimerSettings()
        appearance = (try? container.decode(ClockAppearance.self, forKey: .appearance)) ?? ClockAppearance()
        behavior = (try? container.decode(ClockBehavior.self, forKey: .behavior)) ?? ClockBehavior()
        menuBar = (try? container.decode(MenuBarSettings.self, forKey: .menuBar)) ?? MenuBarSettings()
        windowPlacements = (try? container.decode([String: WindowOrigin].self, forKey: .windowPlacements)) ?? [:]
    }
}
