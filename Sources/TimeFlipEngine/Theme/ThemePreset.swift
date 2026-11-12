import Foundation

/// 精调预设：把 12 个外观参数压缩成「一键就好看」的一组取值。
/// 套用时只保留用户的字号，其余外观整体替换——换主题不该把字号打回 96pt。
public struct ThemePreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let appearance: ClockAppearance

    public init(id: String, name: String, subtitle: String, appearance: ClockAppearance) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.appearance = appearance
    }

    /// 把预设搬到目标外观上（保留字号），返回新值。
    public func applied(to current: ClockAppearance) -> ClockAppearance {
        var next = appearance
        next.fontSize = current.fontSize
        next.themeID = id
        return next.clamped()
    }

    public static func preset(id: String?) -> ThemePreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    // MARK: - 八套预设

    public static let all: [ThemePreset] = [
        ThemePreset(
            id: "cream",
            name: "奶油白",
            subtitle: "象牙卡面 · 炭黑数字",
            appearance: make(
                style: .flip,
                font: "Helvetica Neue",
                weight: .heavy,
                text: "#16130F",
                background: "#F2EDE4",
                opacity: 0.97,
                shadow: true,
                shadowRadius: 18,
                shadowOpacity: 0.22,
                material: .paper,
                chassis: true,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "neon",
            name: "霓虹暗夜",
            subtitle: "深空卡面 · 薄荷荧光",
            appearance: make(
                style: .flip,
                font: "Helvetica Neue",
                weight: .black,
                text: "#7CF7D8",
                background: "#0B1013",
                opacity: 1,
                shadow: true,
                shadowRadius: 30,
                shadowOpacity: 0.55,
                material: .metal,
                chassis: true,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "film",
            name: "胶片颗粒",
            subtitle: "暖褐纸面 · 衬线数字",
            appearance: make(
                style: .flip,
                font: "Georgia",
                weight: .regular,
                text: "#221A12",
                background: "#E8D9BD",
                opacity: 0.97,
                shadow: true,
                shadowRadius: 12,
                shadowOpacity: 0.16,
                material: .paper,
                chassis: true,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "newsprint",
            name: "报纸黑白",
            subtitle: "无机身 · 墨色纸面",
            appearance: make(
                style: .flip,
                font: "Georgia",
                weight: .regular,
                text: "#0E0E0E",
                background: "#FAF6EC",
                opacity: 1,
                shadow: false,
                shadowRadius: 0,
                shadowOpacity: 0,
                material: .paper,
                chassis: false,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "frosted",
            name: "磨砂玻璃",
            subtitle: "半透卡面 · 冷色高光",
            appearance: make(
                style: .flip,
                font: "Avenir Next",
                weight: .heavy,
                text: "#FFFFFF",
                background: "#FFFFFF",
                opacity: 0.20,
                shadow: true,
                shadowRadius: 24,
                shadowOpacity: 0.30,
                material: .glass,
                chassis: true,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "wood",
            name: "木质翻牌",
            subtitle: "深胡桃底 · 米色数字",
            appearance: make(
                style: .flip,
                font: "Georgia",
                weight: .bold,
                text: "#F4E3C8",
                background: "#2A1C12",
                opacity: 0.98,
                shadow: true,
                shadowRadius: 16,
                shadowOpacity: 0.28,
                material: .wood,
                chassis: true,
                showDate: true,
                showBottom: true
            )
        ),
        ThemePreset(
            id: "pixel",
            name: "像素",
            subtitle: "纯数字 · 荧光绿",
            appearance: make(
                style: .digital,
                font: "Menlo",
                weight: .bold,
                text: "#8CFF5A",
                background: "#0F130F",
                opacity: 1,
                shadow: false,
                shadowRadius: 0,
                shadowOpacity: 0,
                material: .pixel,
                chassis: false,
                showDate: false,
                showBottom: false
            )
        ),
        ThemePreset(
            id: "minimal",
            name: "纯数字极简",
            subtitle: "无卡片 · 只剩时间",
            appearance: make(
                style: .digital,
                font: "Helvetica Neue",
                weight: .bold,
                text: "#101010",
                background: "#FFFFFF",
                opacity: 0,
                shadow: false,
                shadowRadius: 0,
                shadowOpacity: 0,
                material: .pixel,
                chassis: false,
                showDate: true,
                showBottom: false
            )
        )
    ]

    private static func make(
        style: ClockStyle,
        font: String,
        weight: ClockFontWeight,
        text: String,
        background: String,
        opacity: Double,
        shadow: Bool,
        shadowRadius: Double,
        shadowOpacity: Double,
        material: ClockMaterial,
        chassis: Bool,
        showDate: Bool,
        showBottom: Bool
    ) -> ClockAppearance {
        var appearance = ClockAppearance()
        appearance.style = style
        appearance.fontFamily = font
        appearance.fontWeight = weight
        appearance.textColor = RGBAColor(hex: text) ?? .charcoal
        appearance.backgroundColor = RGBAColor(hex: background) ?? .ivory
        appearance.backgroundOpacity = opacity
        appearance.shadowEnabled = shadow
        appearance.shadowRadius = shadowRadius
        appearance.shadowOpacity = shadowOpacity
        appearance.material = material
        appearance.showChassis = chassis
        appearance.showDate = showDate
        appearance.showBottomLine = showBottom
        return appearance
    }
}
