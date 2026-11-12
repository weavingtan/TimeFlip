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
        .system(size: metrics.fontSize * 0.17, weight: .semibold, design: .rounded)
    }

    private var content: some View {
        VStack(spacing: metrics.spacing * 0.9) {
            if let date = model.dateLine {
                HStack(spacing: 8) {
                    Text(date.left)
                        .tracking(metrics.fontSize * 0.014)
                    Spacer(minLength: 0)
                    Text(date.right)
                        .tracking(metrics.fontSize * 0.026)
                }
                .textCase(.uppercase)
                .font(captionFont)
                .foregroundStyle(appearance.textColor.color.opacity(0.58))
                .frame(width: containerWidth)
            }

            if appearance.style == .flip {
                cardRow
            } else {
                digitalRow
            }

            if let bottom = model.bottomLine {
                Text(bottom)
                    .textCase(.uppercase)
                    .font(.system(size: metrics.fontSize * 0.15, weight: .medium, design: .rounded))
                    .tracking(metrics.fontSize * 0.02)
                    .foregroundStyle(appearance.textColor.color.opacity(0.5))
                    .frame(width: containerWidth)
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
        .padding(.vertical, metrics.chassisPadding * 1.15)
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
        let factor = isDarkCard ? 1.55 : 0.34
        let warm = isDarkCard ? 1.0 : 0.92
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
        let dot = metrics.digitWidth * 0.15
        return VStack(spacing: metrics.digitHeight * 0.22) {
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
        .padding(.horizontal, metrics.spacing)
    }
}
