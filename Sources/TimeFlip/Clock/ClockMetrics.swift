import CoreGraphics

/// 挂件的几何参数：卡片尺寸由字体大小或屏幕宽度推导，窗口与视图共用同一份数值。
///
/// 比例是"像不像真翻牌机"的核心：
/// - 卡片 3:4（宽:高），比之前的瘦长卡片更接近实物
/// - 字号与卡宽固定比例，数字上下撑满约七成卡高、左右撑满约八成卡宽
/// - 卡间距只有卡宽的 7%，四张卡是同一台机器的四个窗口，而不是四个独立标签
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

    static func floating(appearance: ClockAppearance) -> ClockMetrics {
        metrics(digitWidth: CGFloat(appearance.fontSize) * 0.74, fontSize: CGFloat(appearance.fontSize), appearance: appearance)
    }

    static func fullScreen(screenWidth: CGFloat, appearance: ClockAppearance, slots: Int, colons: Int) -> ClockMetrics {
        let usable = screenWidth * 0.88
        let digitWidth = ClockLayout.digitWidth(containerWidth: usable, slots: max(1, slots), colons: colons)
        return metrics(digitWidth: max(2, digitWidth), fontSize: digitWidth / 0.74, appearance: appearance)
    }

    private static func metrics(digitWidth: CGFloat, fontSize: CGFloat, appearance: ClockAppearance) -> ClockMetrics {
        let width = max(2, digitWidth)
        let radius = appearance.material == .pixel ? width * 0.045 : width * 0.10
        return ClockMetrics(
            digitWidth: width,
            digitHeight: width * cardAspect,
            spacing: width * 0.07,
            colonWidth: width * 0.36,
            padding: max(16, width * 0.16),
            fontSize: fontSize,
            cardRadius: radius,
            chassisPadding: appearance.showChassis ? width * 0.11 : 0,
            chassisRadius: radius * 1.6
        )
    }

    func rowWidth(slots: Int, colons: Int) -> CGFloat {
        let gaps = max(0, slots + colons - 1)
        return CGFloat(slots) * digitWidth + CGFloat(colons) * colonWidth + CGFloat(gaps) * spacing
    }

    func contentSize(slots: Int, colons: Int, showDate: Bool, showBottom: Bool) -> CGSize {
        var height = digitHeight + chassisPadding * 2
        if showDate { height += fontSize * 0.34 + spacing * 0.7 }
        if showBottom { height += fontSize * 0.34 + spacing * 0.7 }
        return CGSize(
            width: rowWidth(slots: slots, colons: colons) + (padding + chassisPadding) * 2,
            height: height + padding * 2
        )
    }
}
