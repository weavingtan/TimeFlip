import SwiftUI

struct FlipDigitView: View {
    let text: String
    let metrics: ClockMetrics
    let appearance: ClockAppearance

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: String
    @State private var previous: String
    @State private var phase: Phase = .idle
    @State private var angle: Double = 0

    private enum Phase: Equatable {
        case idle
        case falling
        case rising
    }

    init(text: String, metrics: ClockMetrics, appearance: ClockAppearance) {
        self.text = text
        self.metrics = metrics
        self.appearance = appearance
        _current = State(initialValue: text)
        _previous = State(initialValue: text)
    }

    private var cornerRadius: CGFloat { metrics.digitWidth * 0.12 }
    private var seam: CGFloat { max(1, metrics.digitHeight * 0.012) }

    var body: some View {
        ZStack {
            card
            VStack(spacing: seam) {
                half(current, top: true)
                half(phase == .idle ? current : previous, top: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if phase == .falling {
                half(previous, top: true)
                    .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
                    .opacity(1 + angle / 90 * 0.4)
            }

            if phase == .rising {
                half(current, top: false)
                    .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
            }

            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: metrics.digitWidth, height: seam)
        }
        .frame(width: metrics.digitWidth, height: metrics.digitHeight)
        .onChange(of: text) { _, newValue in
            animate(to: newValue)
        }
    }

    private var card: some View {
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

    private func half(_ value: String, top: Bool) -> some View {
        Text(value)
            .font(.custom(appearance.fontFamily, size: metrics.fontSize * 0.82).weight(appearance.fontWeight.swiftUI))
            .foregroundStyle(appearance.textColor.color)
            .frame(width: metrics.digitWidth, height: metrics.digitHeight)
            .frame(width: metrics.digitWidth, height: metrics.digitHeight / 2, alignment: top ? .top : .bottom)
            .clipped()
    }

    private func animate(to newValue: String) {
        guard newValue != current else { return }

        if reduceMotion {
            previous = current
            current = newValue
            phase = .idle
            return
        }

        previous = current
        current = newValue
        angle = 0
        phase = .falling

        withAnimation(.linear(duration: 0.09)) {
            angle = -90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            guard phase == .falling else { return }
            phase = .rising
            angle = 90
            withAnimation(.linear(duration: 0.09)) {
                angle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                guard phase == .rising else { return }
                phase = .idle
                angle = 0
                previous = current
            }
        }
    }
}
