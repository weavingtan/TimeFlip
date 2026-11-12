import SwiftUI

struct FlipClockView: View {
    let model: ClockRenderModel

    private var metrics: ClockMetrics { model.metrics }
    private var appearance: ClockAppearance { model.appearance }

    var body: some View {
        content
            .padding(metrics.padding)
            .frame(width: size.width, height: size.height)
    }

    private var size: CGSize {
        metrics.contentSize(
            slots: model.slotCount,
            colons: model.colonCount,
            showDate: model.dateLine != nil,
            showBottom: model.bottomLine != nil
        )
    }

    private var rowWidth: CGFloat {
        metrics.rowWidth(slots: model.slotCount, colons: model.colonCount)
    }

    /// 顶行 / 底行与机身左右边缘对齐，而不是与卡片对齐。
    private var containerWidth: CGFloat { rowWidth + metrics.chassisPadding * 2 }

    private var captionFont: Font {
        .system(size: metrics.fontSize * 0.20, weight: .semibold, design: .rounded)
    }

    private var hasChassis: Bool { metrics.chassisPadding > 0 }

    /// 机身是深色（浅色卡），日期与底行要印成浅色才看得见；
    /// 无机身时退回字体色，并用卡片底色垫一条窄纸带，避免深色字贴在深色壁纸上看不见。
    private var chassisIsDark: Bool { appearance.backgroundColor.luminance >= 0.42 }

    private var captionColor: Color {
        if hasChassis {
            return chassisIsDark ? Color.white.opacity(0.60) : Color.black.opacity(0.42)
        }
        return appearance.textColor.color.opacity(0.72)
    }

    private var captionBackdrop: Color {
        guard hasChassis == false, appearance.backgroundOpacity > 0.05 else { return .clear }
        return appearance.backgroundColor.color(opacity: appearance.backgroundOpacity * 0.92)
    }

    /// 反向描边：深色字配浅描边、浅色字配深描边。
    /// 无机身的主题（纯数字极简）没有纸带垫底，靠这一层保证在任何壁纸上都读得出来。
    private var captionHalo: Color {
        appearance.textColor.luminance > 0.55
            ? Color.black.opacity(0.45)
            : Color.white.opacity(0.45)
    }

    private var captionHaloRadius: CGFloat { max(1.5, metrics.fontSize * 0.014) }

    private var content: some View {
        VStack(spacing: metrics.captionGap) {
            if let date = model.dateLine {
                HStack(spacing: 8) {
                    Text(date.left)
                        .tracking(metrics.fontSize * 0.012)
                    Spacer(minLength: 0)
                    Text(date.right)
                        .tracking(metrics.fontSize * 0.022)
                }
                .textCase(.uppercase)
                .font(captionFont)
                .foregroundStyle(captionColor)
                .shadow(color: captionHalo, radius: captionHaloRadius)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: containerWidth, height: metrics.captionHeight)
                .background(captionBackdrop.clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)))
            }

            if appearance.style == .flip {
                cardRow
            } else {
                digitalRow
            }

            if let bottom = model.bottomLine {
                Text(bottom)
                    .textCase(.uppercase)
                    .font(.system(size: metrics.fontSize * 0.18, weight: .medium, design: .rounded))
                    .tracking(metrics.fontSize * 0.018)
                    .foregroundStyle(captionColor)
                    .shadow(color: captionHalo, radius: captionHaloRadius)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: containerWidth, height: metrics.captionHeight)
                    .background(captionBackdrop.clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)))
            }
        }
    }

    // MARK: - 卡片

    private var cardRow: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(Array(model.characters.enumerated()), id: \.offset) { _, character in
                if character == ":" {
                    colon
                } else {
                    FlipDigitView(
                        text: String(character),
                        metrics: metrics,
                        appearance: appearance
                    )
                }
            }
        }
        .padding(.horizontal, metrics.chassisPadding)
        .padding(.vertical, metrics.chassisPadding)
        .background { chassis }
    }

    /// 机身：卡片像嵌在一个下沉的盒子里，而不是四张纸片浮在壁纸上。
    @ViewBuilder private var chassis: some View {
        if metrics.chassisPadding > 0 {
            RoundedRectangle(cornerRadius: metrics.chassisRadius, style: .continuous)
                .fill(chassisColor)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.chassisRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.18),
                                    Color.clear,
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.chassisRadius, style: .continuous)
                        .strokeBorder(chassisBorder, lineWidth: 1)
                )
                .shadow(
                    color: appearance.shadowEnabled
                        ? Color.black.opacity(appearance.shadowOpacity * 0.55)
                        : .clear,
                    radius: appearance.shadowEnabled ? appearance.shadowRadius * 0.8 : 0,
                    y: appearance.shadowEnabled ? appearance.shadowRadius * 0.25 : 0
                )
        }
    }

    /// 机身是"深一号的机身色"：浅色卡配深色机身（真机就是深灰塑料框），
    /// 深色卡配略亮的机身，保证卡片永远比机身亮或暗一档，不会被糊成一块。
    private var chassisColor: Color {
        let base = appearance.backgroundColor
        let isDarkCard = base.luminance < 0.42
        // 浅卡压到 0.26 才是"黑机身"，0.34 会发灰发脏；暖色再收一点，避免偏黄。
        let factor = isDarkCard ? 1.55 : 0.26
        let warm = isDarkCard ? 1.0 : 0.96
        return Color(
            .sRGB,
            red: min(1, base.red * factor),
            green: min(1, base.green * factor * warm),
            blue: min(1, base.blue * factor * warm),
            opacity: max(0.45, appearance.backgroundOpacity)
        )
    }

    private var chassisBorder: Color {
        Color.white.opacity(appearance.backgroundColor.luminance < 0.42 ? 0.14 : 0.10)
    }

    private var colon: some View {
        let dot = metrics.digitWidth * 0.12
        return VStack(spacing: metrics.digitHeight * 0.20) {
            Circle()
                .fill(appearance.textColor.color)
                .frame(width: dot, height: dot)
            Circle()
                .fill(appearance.textColor.color)
                .frame(width: dot, height: dot)
        }
        .frame(width: metrics.colonWidth, height: metrics.digitHeight)
        .opacity(colonOpacity)
    }

    private var colonOpacity: Double {
        guard appearance.colonBlink else { return 1 }
        return model.colonVisible ? 1 : 0.2
    }

    private var digitalRow: some View {
        HStack(spacing: metrics.spacing * 0.5) {
            ForEach(Array(model.characters.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .foregroundStyle(appearance.textColor.color)
                    .opacity(character == ":" ? colonOpacity : 1)
            }
        }
        .font(.custom(appearance.fontFamily, size: metrics.fontSize).weight(appearance.fontWeight.swiftUI))
        .kerning(metrics.fontSize * 0.01)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: rowWidth)
    }
}
