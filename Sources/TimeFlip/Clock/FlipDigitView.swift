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

    private static let perspective = 0.45

    private var cornerRadius: CGFloat { metrics.digitWidth * 0.12 }
    private var seam: CGFloat { max(1, metrics.digitHeight * 0.016) }

    var body: some View {
        Group {
            if let previewAngle {
                if previewAngle <= -179.5 {
                    staticCard
                } else {
                    animatedCard(angle: previewAngle)
                }
            } else if reduceMotion {
                staticCard
            } else {
                KeyframeAnimator(initialValue: 0.0, trigger: trigger) { angle in
                    if angle <= -179.5 {
                        // 落定后回到单层渲染：不再叠加翻页面，杜绝重影。
                        staticCard
                    } else {
                        animatedCard(angle: angle)
                    }
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
                    clippedHalf(current, top: true, visibleFraction: topReveal(angle))
                    if angle > -90 {
                        flap(previous, top: true, angle: angle)
                    }
                }
                .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2)

                ZStack {
                    clippedHalf(previous, top: false, visibleFraction: bottomReveal(angle))
                    if angle <= -90 {
                        flap(current, top: false, angle: angle + 180)
                    }
                }
                .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            seamLine
        }
    }

    /// 卡面：上下两半各带一层极淡的渐变（上亮下暗），加一条发丝高光边，
    /// 让"翻页卡"有厚度感，而不是一块纯色方块。
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                appearance.backgroundColor.color(
                    opacity: appearance.backgroundOpacity * appearance.backgroundColor.alpha
                )
            )
            .overlay(
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.12), Color.black.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(
                color: appearance.shadowEnabled ? Color.black.opacity(appearance.shadowOpacity) : .clear,
                radius: appearance.shadowEnabled ? appearance.shadowRadius : 0,
                y: appearance.shadowEnabled ? appearance.shadowRadius * 0.35 : 0
            )
    }

    /// 一片翻页卡：轻微卡面 + 数字 + 随角度加深的阴影。
    /// 底下那半张卡的数字已被裁剪掉，所以卡面不需要做到不透明，卡片透明度保持不变。
    private func flap(_ value: String, top: Bool, angle: Double) -> some View {
        let progress = min(1, abs(angle) / 90)
        return ZStack {
            Rectangle()
                .fill(appearance.backgroundColor.color(opacity: 0.18))
            half(value, top: top)
            flapShade(top: top, intensity: 0.20 * progress)
        }
        .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2)
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 1, y: 0, z: 0),
            anchor: top ? .bottom : .top,
            perspective: Self.perspective
        )
    }

    /// 上半张卡里"没被下落翻页面遮住"的比例：翻页面绕中缝转 θ，投影高度按 cos θ 收缩，
    /// 于是从顶边被揭开的正是 1 - cos θ（0° 遮满，90° 露满）。
    private func topReveal(_ angle: Double) -> CGFloat {
        guard angle > -90 else { return 1 }
        return CGFloat(1 - cos(min(90, abs(angle)) * .pi / 180))
    }

    /// 下半张卡同理：新翻页面从 90° 落回 0°，旧数字从底边露出（90° 露满 → 0° 遮满）。
    private func bottomReveal(_ angle: Double) -> CGFloat {
        guard angle <= -90 else { return 1 }
        let falling = min(90, max(0, angle + 180))
        return CGFloat(1 - cos(falling * .pi / 180))
    }

    /// 只显示某半张卡的一段（用于让数字被翻页面"揭开"或"盖住"）。
    /// `visibleFraction` 与翻页面的投影互补，两者相加正好一整半，既不留缝也不重叠。
    private func clippedHalf(_ value: String, top: Bool, visibleFraction: CGFloat) -> some View {
        let full = metrics.digitHeight / 2
        let visible = full * min(1, max(0, visibleFraction))
        return ZStack(alignment: top ? .top : .bottom) {
            if visible > 0.5 {
                half(value, top: top)
            }
        }
        .frame(width: metrics.digitWidth, height: visible, alignment: top ? .top : .bottom)
        .clipped()
        .frame(width: metrics.digitWidth, height: full, alignment: top ? .top : .bottom)
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

    /// 中缝：中间最暗、上下收边，模拟两张卡叠在一起的缝。
    private var seamLine: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.32),
                        Color.black.opacity(0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
