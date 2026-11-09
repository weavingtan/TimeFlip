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

    private var content: some View {
        VStack(spacing: metrics.spacing * 0.8) {
            if let date = model.dateLine {
                HStack(spacing: 8) {
                    Text(date.left)
                    Spacer(minLength: 0)
                    Text(date.right)
                }
                .font(.system(size: metrics.fontSize * 0.17, weight: .semibold, design: .rounded))
                .foregroundStyle(appearance.textColor.color.opacity(0.72))
                .frame(width: rowWidth)
            }

            if appearance.style == .flip {
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
            } else {
                digitalRow
            }

            if let bottom = model.bottomLine {
                Text(bottom)
                    .font(.system(size: metrics.fontSize * 0.17, weight: .semibold, design: .rounded))
                    .foregroundStyle(appearance.textColor.color.opacity(0.72))
                    .frame(width: rowWidth)
            }
        }
    }

    private var colon: some View {
        VStack(spacing: metrics.digitHeight * 0.22) {
            Circle()
                .fill(appearance.textColor.color)
                .frame(width: metrics.digitWidth * 0.13, height: metrics.digitWidth * 0.13)
            Circle()
                .fill(appearance.textColor.color)
                .frame(width: metrics.digitWidth * 0.13, height: metrics.digitWidth * 0.13)
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
        .monospacedDigit()
        .padding(.horizontal, metrics.spacing)
    }
}
