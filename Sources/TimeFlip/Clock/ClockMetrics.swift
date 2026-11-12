import AppKit
import CoreGraphics

/// 挂件的几何参数：卡片尺寸由字体大小或屏幕宽度推导，窗口与视图共用同一份数值。
///
/// 比例是"像不像真翻牌机"的核心：
/// - 卡片 3:4（宽:高）
/// - 数字按**真实字体度量**反算字号，保证 Georgia / Menlo / Avenir 都不会顶出卡片
/// - 卡间距只有卡宽的 6.5%，四张卡是同一台机器的四个窗口，而不是四个独立标签
struct ClockMetrics: Equatable {
    var digitWidth: CGFloat
    var digitHeight: CGFloat
    var spacing: CGFloat
    var colonWidth: CGFloat
    var padding: CGFloat
    var fontSize: CGFloat
    var cardRadius: CGFloat
    /// 机身托盘的内边距；0 表示不画机身。
    var chassisPadding: CGFloat
    var chassisRadius: CGFloat

    static let cardAspect: CGFloat = 4.0 / 3.0
    /// 数字留白：字面最多占卡宽 72%、卡高 62%（真机就是这个呼吸感，撑太满会显得廉价）。
    static let digitWidthFill: CGFloat = 0.72
    static let digitHeightFill: CGFloat = 0.62
    /// 日期行 / 底行的行高占字号的比例。
    static let captionHeightRatio: CGFloat = 0.27

    /// 日期行、底行的固定行高：视图与窗口尺寸都用它，避免"文字压到机身上"。
    var captionHeight: CGFloat { fontSize * Self.captionHeightRatio }
    var captionGap: CGFloat { spacing * 0.85 }
    var chassisBoxHeight: CGFloat { digitHeight + chassisPadding * 2 }

    static func floating(appearance: ClockAppearance) -> ClockMetrics {
        let digitWidth = max(2, CGFloat(appearance.fontSize) * 0.74)
        return metrics(
            digitWidth: digitWidth,
            fontSize: fittedFontSize(
                family: appearance.fontFamily,
                weight: appearance.fontWeight,
                digitWidth: digitWidth
            ),
            appearance: appearance
        )
    }

    static func fullScreen(screenWidth: CGFloat, appearance: ClockAppearance, slots: Int, colons: Int) -> ClockMetrics {
        let usable = screenWidth * 0.88
        let digitWidth = max(2, ClockLayout.digitWidth(containerWidth: usable, slots: max(1, slots), colons: colons))
        return metrics(
            digitWidth: digitWidth,
            fontSize: fittedFontSize(
                family: appearance.fontFamily,
                weight: appearance.fontWeight,
                digitWidth: digitWidth
            ),
            appearance: appearance
        )
    }

    private static func metrics(digitWidth: CGFloat, fontSize: CGFloat, appearance: ClockAppearance) -> ClockMetrics {
        let width = max(2, digitWidth)
        let radius = appearance.material == .pixel ? width * 0.045 : width * 0.10
        return ClockMetrics(
            digitWidth: width,
            digitHeight: width * cardAspect,
            spacing: width * 0.065,
            colonWidth: width * 0.34,
            padding: max(14, width * 0.15),
            fontSize: max(4, fontSize),
            cardRadius: radius,
            chassisPadding: appearance.showChassis ? width * 0.10 : 0,
            chassisRadius: radius * 1.55
        )
    }

    /// 用真实字体度量反算字号：Georgia 的数字比 Helvetica Neue 窄，等宽字体又更宽，
    /// 只按倍数猜一定会有人顶出卡片。这里量 "0" 的步进宽度和大写高度，取两者较小值。
    static func fittedFontSize(family: String, weight: ClockFontWeight, digitWidth: CGFloat) -> CGFloat {
        let probe: CGFloat = 100
        let font = NSFont(name: family, size: probe) ?? NSFont.systemFont(ofSize: probe)
        let advance = max(1, ("0" as NSString).size(withAttributes: [.font: font]).width)
        // 大写高度对字重不敏感，宽度步进同理（数字都是等宽表格式），probe 一次足够。
        let cap = max(1, font.capHeight)
        let maxWidth = digitWidth * digitWidthFill
        let maxHeight = digitWidth * cardAspect * digitHeightFill
        let byWidth = probe * maxWidth / advance
        let byHeight = probe * maxHeight / cap
        return max(4, min(byWidth, byHeight))
    }

    func rowWidth(slots: Int, colons: Int) -> CGFloat {
        let gaps = max(0, slots + colons - 1)
        return CGFloat(slots) * digitWidth + CGFloat(colons) * colonWidth + CGFloat(gaps) * spacing
    }

    func contentSize(slots: Int, colons: Int, showDate: Bool, showBottom: Bool) -> CGSize {
        var height = chassisBoxHeight
        if showDate { height += captionGap + captionHeight }
        if showBottom { height += captionGap + captionHeight }
        return CGSize(
            width: rowWidth(slots: slots, colons: colons) + (padding + chassisPadding) * 2,
            height: height + padding * 2
        )
    }
}
