import SwiftUI

/// 单张翻页卡片：KeyframeAnimator 用一条 0 → -90 → -180 的角度曲线驱动，
/// 前半段落下的旧上半、后半段翻起的新下半，避免两段独立动画拼接造成的卡顿感。
///
/// 画法按真机三层叠出来：
/// 1. 卡面（受光渐变 + 材质高光 + 1px 描边 + 接触阴影 + 环境阴影）
/// 2. 上下两半拼成的数字
/// 3. 中缝：缝体 + 上半卡底部的暗边 + 下半卡上沿的高光
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

    private var cornerRadius: CGFloat { metrics.cardRadius }
    private var seam: CGFloat { max(1.2, metrics.digitHeight * 0.014) }
    private var halfHeight: CGFloat { metrics.digitHeight / 2 }

    private var fillColor: Color {
        appearance.backgroundColor.color(
            opacity: appearance.backgroundOpacity * appearance.backgroundColor.alpha
        )
    }

    private var isPixel: Bool { appearance.material == .pixel }

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

    // MARK: - 静态卡

    private var staticCard: some View {
        ZStack {
            cardFace
            numberLayer(current)
            seamDecoration
        }
    }

    private func numberLayer(_ value: String) -> some View {
        VStack(spacing: 0) {
            half(value, top: true)
            half(value, top: false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - 翻页

    private func animatedCard(angle: Double) -> some View {
        ZStack {
            cardFace

            // 上半槽 / 下半槽各自承载自己的翻页层，避免 ZStack 把翻页层放到中缝上。
            VStack(spacing: 0) {
                ZStack {
                    clippedHalf(current, top: true, visibleFraction: topReveal(angle))
                    if angle > -90 {
                        flap(previous, top: true, angle: angle)
                    }
                }
                .frame(width: metrics.digitWidth, height: halfHeight)

                ZStack {
                    clippedHalf(previous, top: false, visibleFraction: bottomReveal(angle))
                    if angle <= -90 {
                        flap(current, top: false, angle: angle + 180)
                    }
                }
                .frame(width: metrics.digitWidth, height: halfHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            seamDecoration
        }
    }

    /// 一片翻页卡：卡面本色 + 数字 + 随角度加深的压暗
    /// （真机的翻页面是背光的，只会变暗，不会变白）。
    private func flap(_ value: String, top: Bool, angle: Double) -> some View {
        let progress = min(1, abs(angle) / 90)
        return ZStack {
            Rectangle().fill(fillColor)
            Rectangle().fill(flapSheen)
            half(value, top: top)
            Rectangle().fill(flapShade(top: top, intensity: 0.30 * progress))
        }
        .frame(width: metrics.digitWidth, height: halfHeight)
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 1, y: 0, z: 0),
            anchor: top ? .bottom : .top,
            perspective: Self.perspective
        )
    }

    private var flapSheen: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.06), Color.clear],
            startPoint: .top,
            endPoint: .bottom
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
        let visible = halfHeight * min(1, max(0, visibleFraction))
        return ZStack(alignment: top ? .top : .bottom) {
            if visible > 0.5 {
                half(value, top: top)
            }
        }
        .frame(width: metrics.digitWidth, height: visible, alignment: top ? .top : .bottom)
        .clipped()
        .frame(width: metrics.digitWidth, height: halfHeight, alignment: top ? .top : .bottom)
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

    // MARK: - 卡面

    private var cardFace: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay(sheen.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: contactShadowColor,
                radius: contactShadowRadius,
                y: contactShadowOffset
            )
            .shadow(
                color: ambientShadowColor,
                radius: ambientShadowRadius,
                y: ambientShadowOffset
            )
    }

    /// 材质高光：不换颜色，换的是"光怎么打在卡面上"。
    @ViewBuilder private var sheen: some View {
        switch appearance.material {
        case .paper:
            LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0.03), Color.black.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .glass:
            // 玻璃卡本身几乎透明，压一层淡暗底，白字才有对比。
            ZStack {
                Color.black.opacity(0.14)
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.white.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .metal:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.18),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .wood:
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.black.opacity(0.04), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .pixel:
            Color.clear
        }
    }

    private var borderColor: Color {
        switch appearance.material {
        case .glass: return Color.white.opacity(0.42)
        case .metal: return Color.white.opacity(0.20)
        case .wood: return Color.black.opacity(0.35)
        case .pixel: return Color.clear
        case .paper: return Color.white.opacity(0.14)
        }
    }

    private var borderWidth: CGFloat {
        appearance.material == .glass ? 0.8 : 0.5
    }

    private var contactShadowColor: Color {
        guard appearance.shadowEnabled, !isPixel else { return .clear }
        return Color.black.opacity(appearance.shadowOpacity * 0.55)
    }

    private var contactShadowRadius: CGFloat {
        guard appearance.shadowEnabled, !isPixel else { return 0 }
        return max(1, appearance.shadowRadius * 0.10)
    }

    private var contactShadowOffset: CGFloat {
        appearance.shadowEnabled && !isPixel ? 1.5 : 0
    }

    private var ambientShadowColor: Color {
        guard appearance.shadowEnabled, !isPixel else { return .clear }
        return Color.black.opacity(appearance.shadowOpacity)
    }

    private var ambientShadowRadius: CGFloat {
        guard appearance.shadowEnabled, !isPixel else { return 0 }
        return appearance.shadowRadius
    }

    private var ambientShadowOffset: CGFloat {
        appearance.shadowEnabled && !isPixel ? appearance.shadowRadius * 0.35 : 0
    }

    // MARK: - 中缝

    /// 三件套：缝体（深）+ 上半卡底部的暗边 + 下半卡上沿的 0.5px 高光。
    private var seamDecoration: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: seam * 3)
                .offset(y: -seam * 1.5)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.50),
                                Color.black.opacity(0.62),
                                Color.black.opacity(0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: seam)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.5)

                LinearGradient(
                    colors: [Color.black.opacity(0.22), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: seam * 3)
                .offset(y: seam * 1.5)
            }
        }
        .frame(width: metrics.digitWidth, height: metrics.digitHeight)
        .allowsHitTesting(false)
    }

    // MARK: - 数字

    private func half(_ value: String, top: Bool) -> some View {
        Text(value)
            .font(.custom(appearance.fontFamily, size: metrics.fontSize).weight(appearance.fontWeight.swiftUI))
            .foregroundStyle(appearance.textColor.color)
            // 文字行框含 ascender/descender，直接居中会让字面整体偏下 3% 左右。
            .offset(y: -metrics.fontSize * 0.03)
            .frame(width: metrics.digitWidth, height: metrics.digitHeight)
            .frame(width: metrics.digitWidth, height: halfHeight, alignment: top ? .top : .bottom)
            .clipped()
    }
}
