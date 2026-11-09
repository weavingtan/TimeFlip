import SwiftUI

/// 单张翻页卡片：KeyframeAnimator 用一条 0 → -90 → -180 的角度曲线驱动，
/// 前半段落下的旧上半、后半段翻起的新下半，避免两段独立动画拼接造成的卡顿感。
struct FlipDigitView: View {
    let text: String
    let metrics: ClockMetrics
    let appearance: ClockAppearance
    /// 仅用于离屏渲染核对：把动画定格在指定角度。
    var previewAngle: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: String
    @State private var previous: String
    @State private var trigger = 0

    init(
        text: String,
        metrics: ClockMetrics,
        appearance: ClockAppearance,
        previewAngle: Double? = nil,
        previewPrevious: String? = nil
    ) {
        self.text = text
        self.metrics = metrics
        self.appearance = appearance
        self.previewAngle = previewAngle
        _current = State(initialValue: text)
        _previous = State(initialValue: previewPrevious ?? text)
    }

    private var cornerRadius: CGFloat { metrics.digitWidth * 0.12 }
    private var seam: CGFloat { max(1, metrics.digitHeight * 0.012) }

    var body: some View {
        Group {
            if let previewAngle {
                animatedCard(angle: previewAngle)
            } else if reduceMotion {
                staticCard
            } else {
                KeyframeAnimator(initialValue: 0.0, trigger: trigger) { angle in
                    animatedCard(angle: angle)
                } keyframes: { _ in
                    KeyframeTrack(\.self) {
                        CubicKeyframe(-90, duration: 0.13)
                        CubicKeyframe(-180, duration: 0.15)
                    }
                }
            }
        }
        .frame(width: metrics.digitWidth, height: metrics.digitHeight)
        .onChange(of: text) { _, newValue in
            guard newValue != current else { return }
            previous = current
            current = newValue
            trigger += 1
        }
    }

    private var staticCard: some View {
        ZStack {
            cardBackground
            VStack(spacing: seam) {
                half(current, top: true)
                half(current, top: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            seamLine
        }
    }

    private func animatedCard(angle: Double) -> some View {
        ZStack {
            cardBackground

            // 上半槽 / 下半槽各自承载自己的翻页层，避免 ZStack 把翻页层放到中缝上。
            VStack(spacing: seam) {
                ZStack {
                    half(current, top: true)
                    if angle > -90 {
                        half(previous, top: true)
                            .overlay(
                                flapShade(top: true, intensity: 0.20 * min(1, abs(angle) / 90))
                            )
                            .rotation3DEffect(
                                .degrees(angle),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .bottom,
                                perspective: 0.45
                            )
                    }
                }
                .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2)

                ZStack {
                    half(previous, top: false)
                    if angle <= -90 {
                        half(current, top: false)
                            .overlay(
                                flapShade(top: false, intensity: 0.20 * min(1, (angle + 180) / 90))
                            )
                            .rotation3DEffect(
                                .degrees(angle + 180),
                                axis: (x: 1, y: 0, z: 0),
                                anchor: .top,
                                perspective: 0.45
                            )
                    }
                }
                .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            seamLine
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                appearance.backgroundColor.color(
                    opacity: appearance.backgroundOpacity * appearance.backgroundColor.alpha
                )
            )
            .shadow(
                color: appearance.shadowEnabled ? Color.black.opacity(appearance.shadowOpacity) : .clear,
                radius: appearance.shadowEnabled ? appearance.shadowRadius : 0,
                y: appearance.shadowEnabled ? appearance.shadowRadius * 0.35 : 0
            )
    }

    /// 翻页面越"背光"越暗：自由边（远离转轴的那条边）颜色最深。
    private func flapShade(top: Bool, intensity: Double) -> LinearGradient {
        let dark = Color.black.opacity(intensity)
        let clear = Color.black.opacity(0)
        return LinearGradient(
            colors: top ? [dark, clear] : [clear, dark],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var seamLine: some View {
        Rectangle()
            .fill(Color.black.opacity(0.18))
            .frame(width: metrics.digitWidth, height: seam)
    }

    private func half(_ value: String, top: Bool) -> some View {
        Text(value)
            .font(.custom(appearance.fontFamily, size: metrics.fontSize * 0.82).weight(appearance.fontWeight.swiftUI))
            .foregroundStyle(appearance.textColor.color)
            .frame(width: metrics.digitWidth, height: metrics.digitHeight)
            .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2, alignment: top ? .top : .bottom)
            .clipped()
    }
}
