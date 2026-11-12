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
    /// 翻牌机的象牙白卡面：比纯白暖一点，避免"网页白"的廉价感。
    public static let ivory = RGBAColor(hex: "#F2EDE4") ?? RGBAColor(red: 0.95, green: 0.93, blue: 0.89)
    /// 卡面上的近黑字色：比纯黑柔和。
    public static let charcoal = RGBAColor(hex: "#16130F") ?? RGBAColor(red: 0.09, green: 0.07, blue: 0.06)
}

public enum ClockStyle: String, Codable, Sendable {
    case flip
    case digital
}

/// 卡面材质：决定渐变、圆角、描边与投影的算法，而不只是换颜色。
public enum ClockMaterial: String, Codable, Sendable, CaseIterable {
    /// 哑光纸面（默认）：微受光渐变 + 细颗粒感。
    case paper
    /// 玻璃：极低不透明度 + 冷色高光边。
    case glass
    /// 金属：强对角的拉丝高光。
    case metal
    /// 木质：暖色底 + 深一档的框边。
    case wood
    /// 像素：直角、无渐变、无投影。
    case pixel
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
    public var textColor: RGBAColor = .charcoal
    public var backgroundColor: RGBAColor = .ivory
    public var backgroundOpacity: Double = 0.96
    public var shadowEnabled: Bool = true
    public var shadowRadius: Double = 18
    public var shadowOpacity: Double = 0.22
    public var showSeconds: Bool = true
    public var showDate: Bool = true
    public var showBottomLine: Bool = true
    public var use24Hour: Bool = true
    public var colonBlink: Bool = true
    public var showLeadingZero: Bool = true
    public var material: ClockMaterial = .paper
    public var showChassis: Bool = true
    /// 当前套用的预设 id，仅用于设置面板高亮，不参与渲染。
    public var themeID: String?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, fontFamily, fontWeight, fontSize, textColor, backgroundColor
        case backgroundOpacity, shadowEnabled, shadowRadius, shadowOpacity
        case showSeconds, showDate, showBottomLine, use24Hour, colonBlink, showLeadingZero
        case material, showChassis, themeID
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
        material = (try? container.decode(ClockMaterial.self, forKey: .material)) ?? fallback.material
        showChassis = (try? container.decode(Bool.self, forKey: .showChassis)) ?? fallback.showChassis
        themeID = try? container.decode(String.self, forKey: .themeID)
    }

    /// 把外观夹回合法区间：导入别人分享的主题时不能信任任何数值。
    public func clamped() -> ClockAppearance {
        var copy = self
        copy.fontSize = min(400, max(12, fontSize.isFinite ? fontSize : 96))
        copy.backgroundOpacity = min(1, max(0, backgroundOpacity.isFinite ? backgroundOpacity : 0.96))
        copy.shadowRadius = min(40, max(0, shadowRadius.isFinite ? shadowRadius : 18))
        copy.shadowOpacity = min(1, max(0, shadowOpacity.isFinite ? shadowOpacity : 0.22))
        return copy
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

/// 统计相关的用户设置（目前只有每日目标）。
public struct StatsSettings: Codable, Equatable, Sendable {
    /// 每日目标专注轮数，0 表示不设目标。
    public var dailyGoalSessions: Int = 4

    public init() {}

    public init(from decoder: Decoder) throws {
        let fallback = StatsSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let goal = (try? container.decode(Int.self, forKey: .dailyGoalSessions)) ?? fallback.dailyGoalSessions
        dailyGoalSessions = min(24, max(0, goal))
    }

    private enum CodingKeys: String, CodingKey {
        case dailyGoalSessions
    }
}

public enum LockStyle: String, Codable, Sendable, CaseIterable {
    /// 只提醒，不动系统。
    case off
    /// 关闭显示器（无需任何权限）。
    case displaySleep
    /// 真正锁定屏幕（需要一次「辅助功能」授权）。
    case lock
}

public struct LockSettings: Codable, Equatable, Sendable {
    public var style: LockStyle = .off
    /// 锁屏前的宽限秒数，期间可点「再等 5 分钟」取消。
    public var graceSeconds: Int = 10
    /// 专注结束后是否铺全屏休息遮罩。
    public var overlayEnabled: Bool = true
    /// 前台是全屏应用（演示 / 录屏 / 视频）时不打扰。
    public var skipWhenFullScreenApp: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let fallback = LockSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? container.decode(LockStyle.self, forKey: .style)) ?? fallback.style
        let grace = (try? container.decode(Int.self, forKey: .graceSeconds)) ?? fallback.graceSeconds
        graceSeconds = min(60, max(0, grace))
        overlayEnabled = (try? container.decode(Bool.self, forKey: .overlayEnabled)) ?? fallback.overlayEnabled
        skipWhenFullScreenApp = (try? container.decode(Bool.self, forKey: .skipWhenFullScreenApp))
            ?? fallback.skipWhenFullScreenApp
    }

    private enum CodingKeys: String, CodingKey {
        case style, graceSeconds, overlayEnabled, skipWhenFullScreenApp
    }

    public var isEnabled: Bool { style != .off }
}

public struct TimeFlipSettings: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var timer: TimerSettings = TimerSettings()
    public var appearance: ClockAppearance = ClockAppearance()
    public var behavior: ClockBehavior = ClockBehavior()
    public var menuBar: MenuBarSettings = MenuBarSettings()
    public var stats: StatsSettings = StatsSettings()
    public var lock: LockSettings = LockSettings()
    public var windowPlacements: [String: WindowOrigin] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, timer, appearance, behavior, menuBar, stats, lock, windowPlacements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        timer = (try? container.decode(TimerSettings.self, forKey: .timer)) ?? TimerSettings()
        appearance = (try? container.decode(ClockAppearance.self, forKey: .appearance)) ?? ClockAppearance()
        behavior = (try? container.decode(ClockBehavior.self, forKey: .behavior)) ?? ClockBehavior()
        menuBar = (try? container.decode(MenuBarSettings.self, forKey: .menuBar)) ?? MenuBarSettings()
        stats = (try? container.decode(StatsSettings.self, forKey: .stats)) ?? StatsSettings()
        lock = (try? container.decode(LockSettings.self, forKey: .lock)) ?? LockSettings()
        windowPlacements = (try? container.decode([String: WindowOrigin].self, forKey: .windowPlacements)) ?? [:]
    }
}
