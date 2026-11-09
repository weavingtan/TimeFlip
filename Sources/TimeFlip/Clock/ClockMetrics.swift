import CoreGraphics

/// 挂件的几何参数：卡片尺寸由字体大小或屏幕宽度推导，窗口与视图共用同一份数值。
struct ClockMetrics: Equatable {
    var digitWidth: CGFloat
    var digitHeight: CGFloat
    var spacing: CGFloat
    var colonWidth: CGFloat
    var padding: CGFloat
    var fontSize: CGFloat

    static func floating(appearance: ClockAppearance) -> ClockMetrics {
        metrics(fitting: CGFloat(appearance.fontSize) * 0.74, fontSize: CGFloat(appearance.fontSize))
    }

    static func fullScreen(screenWidth: CGFloat, appearance: ClockAppearance, slots: Int, colons: Int) -> ClockMetrics {
        let usable = screenWidth * 0.86
        let digitWidth = ClockLayout.digitWidth(containerWidth: usable, slots: max(1, slots), colons: colons)
        return metrics(fitting: digitWidth, fontSize: digitWidth / 0.74)
    }

    private static func metrics(fitting digitWidth: CGFloat, fontSize: CGFloat) -> ClockMetrics {
        ClockMetrics(
            digitWidth: digitWidth,
            digitHeight: fontSize * 1.24,
            spacing: digitWidth * 0.12,
            colonWidth: digitWidth * 0.40,
            padding: max(16, digitWidth * 0.18),
            fontSize: fontSize
        )
    }

    func rowWidth(slots: Int, colons: Int) -> CGFloat {
        let gaps = max(0, slots + colons - 1)
        return CGFloat(slots) * digitWidth + CGFloat(colons) * colonWidth + CGFloat(gaps) * spacing
    }

    func contentSize(slots: Int, colons: Int, showDate: Bool, showBottom: Bool) -> CGSize {
        var height = digitHeight
        if showDate { height += fontSize * 0.30 + spacing * 0.6 }
        if showBottom { height += fontSize * 0.30 + spacing * 0.6 }
        return CGSize(width: rowWidth(slots: slots, colons: colons) + padding * 2, height: height + padding * 2)
    }
}
