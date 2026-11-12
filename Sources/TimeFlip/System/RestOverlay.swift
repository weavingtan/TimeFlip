import AppKit
import SwiftUI

// MARK: - 休息遮罩

@MainActor
final class BreakOverlayModel: ObservableObject {
    @Published var remaining: Int
    @Published var total: Int
    @Published var phase: TimerPhase
    var onGiveUp: () -> Void

    init(phase: TimerPhase, remaining: Int, total: Int, onGiveUp: @escaping () -> Void) {
        self.phase = phase
        self.remaining = remaining
        self.total = total
        self.onGiveUp = onGiveUp
    }
}

/// 专注结束后盖住所有屏幕的休息层：不用锁屏也能把人从屏幕前拉走，
/// 而且它比锁屏温和——休息结束时自己消失，回来就能继续。
@MainActor
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var model: BreakOverlayModel?

    var isVisible: Bool { !windows.isEmpty }

    func show(phase: TimerPhase, remaining: Int, total: Int, onGiveUp: @escaping () -> Void) {
        hide()
        let model = BreakOverlayModel(phase: phase, remaining: remaining, total: total, onGiveUp: onGiveUp)
        self.model = model

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: true)
            window.contentView = NSHostingView(rootView: BreakOverlayView(model: model))
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func update(remaining: Int, total: Int) {
        guard let model else { return }
        model.remaining = max(0, remaining)
        model.total = max(1, total)
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        model = nil
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct BreakOverlayView: View {
    @ObservedObject var model: BreakOverlayModel
    @State private var breathe = false

    private var accent: Color { TFTheme.accent(for: model.phase) }

    private var progress: Double {
        guard model.total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(model.remaining) / Double(model.total)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
            RadialGradient(
                colors: [accent.opacity(0.22), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 560
            )

            VStack(spacing: 30) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.55))

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 2)
                        .frame(width: 236, height: 236)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 236, height: 236)

                    // 呼吸引导圈：4 秒一次收放，跟着它慢慢呼吸。
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 168, height: 168)
                        .scaleEffect(breathe ? 1.10 : 0.88)

                    VStack(spacing: 6) {
                        Text(TimeStrings.countdown(seconds: model.remaining))
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("深呼吸")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                VStack(spacing: 8) {
                    Text("起来走走，看看远处")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("盯着屏幕 25 分钟，眼睛和腰都需要这三分钟。")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Button {
                    model.onGiveUp()
                } label: {
                    Text("提前结束休息")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("TIMEFLIP")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.top, 8)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .longBreak: return "长 休"
        case .shortBreak: return "短 休"
        case .focus: return "专 注"
        case .idle: return "休 息"
        }
    }
}

// MARK: - 锁屏宽限

@MainActor
final class GraceModel: ObservableObject {
    @Published var remaining: Int
    let style: LockStyle

    init(remaining: Int, style: LockStyle) {
        self.remaining = remaining
        self.style = style
    }

    var styleText: String {
        style == .lock ? "锁定屏幕" : "关闭屏幕"
    }
}

/// 锁屏前的最后一根救命稻草：默认 10 秒，够点「再等 5 分钟」，又短到不会让人真去忙别的。
@MainActor
final class GraceOverlayController {
    private var window: NSWindow?
    private var timer: Timer?
    private var model: GraceModel?

    var isVisible: Bool { window != nil }

    func show(
        seconds: Int,
        style: LockStyle,
        onLock: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        hide()
        let model = GraceModel(remaining: max(0, seconds), style: style)
        self.model = model

        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 208),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: GraceView(
                model: model,
                onSnooze: { [weak self] in
                    self?.hide()
                    onSnooze()
                },
                onLockNow: { [weak self] in
                    self?.hide()
                    onLock()
                },
                onSkip: { [weak self] in
                    self?.hide()
                    onSkip()
                }
            )
        )

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.visibleFrame.midX - 200,
                y: screen.visibleFrame.midY + 40
            )
            window.setFrameOrigin(origin)
        }
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        self.window = window

        guard seconds > 0 else {
            hide()
            onLock()
            return
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let model = self.model else { return }
                if model.remaining > 1 {
                    model.remaining -= 1
                } else {
                    self.hide()
                    onLock()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }
}

private struct GraceView: View {
    @ObservedObject var model: GraceModel
    var onSnooze: () -> Void
    var onLockNow: () -> Void
    var onSkip: () -> Void

    private var accent: Color { TFTheme.accent(for: .focus) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text("专注完成")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(model.remaining)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            Text("\(model.remaining) 秒后\(model.styleText)")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)

            Text("起来走走，顺手倒杯水。想把这轮做完就再等 5 分钟。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("再等 5 分钟") { onSnooze() }
                    .buttonStyle(TFChipButtonStyle())
                Button("现在就\(model.styleText)") { onLockNow() }
                    .buttonStyle(TFChipButtonStyle(tint: accent, prominent: true))
            }

            Button("跳过这次") { onSkip() }
                .buttonStyle(TFFooterButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        )
        .padding(12)
    }
}
