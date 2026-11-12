import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @State private var customMinutes = ""

    private var snapshot: TimerSnapshot { model.snapshot }
    private var durations: Durations { model.settings.timer.durations }
    private var accent: Color { TFTheme.accent(for: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            timeBlock
            controls
            presets
            customInput
            footer
        }
        .padding(18)
        .frame(width: TFTheme.panelWidth)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: TFTheme.icon(for: snapshot.phase))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            cycleDots
        }
    }

    /// 本轮循环内的进度圆点（4 轮一长休时画 4 个）。
    private var cycleDots: some View {
        let total = max(2, durations.sessionsPerLongBreak)
        let done = snapshot.completedFocusSessions % total
        let filled = done == 0 && snapshot.completedFocusSessions > 0 ? total : done

        return HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? accent : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(snapshot.isCustom ? 0 : 1)
        .accessibilityLabel("本轮已完成 \(filled) / \(total) 次专注")
    }

    // MARK: - 倒计时

    private var timeBlock: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 结束后显示 00:00（与菜单栏一致），下一阶段时长放在副标题里。
                Text(snapshot.isFinished ? "00:00" : TimeStrings.countdown(seconds: snapshot.displaySeconds))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isFinished ? accent : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                Text(progressLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            progressBar
        }
    }

    private var progressBar: some View {
        let value = snapshot.isFinished ? 1 : min(1, max(0, snapshot.progress))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 5)
            GeometryReader { proxy in
                Capsule()
                    .fill(accent)
                    .frame(width: max(5, proxy.size.width * value), height: 5)
            }
            .frame(height: 5)
        }
        .frame(height: 5)
        .accessibilityLabel("进度 \(Int((value * 100).rounded()))%")
    }

    private var progressLabel: String {
        if snapshot.isFinished { return "已完成" }
        if snapshot.phase == .idle { return "\(durations.focusMinutes) 分钟" }
        return "\(Int((snapshot.progress * 100).rounded()))%"
    }

    // MARK: - 控制

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                model.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 12, weight: .bold))
                    Text(primaryTitle)
                }
            }
            .buttonStyle(TFPrimaryButtonStyle(tint: accent))
            .keyboardShortcut(.defaultAction)

            Button {
                model.skip()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(TFIconButtonStyle())
            .disabled(snapshot.phase == .idle)
            .opacity(snapshot.phase == .idle ? 0.4 : 1)
            .help("跳过当前阶段")
            .accessibilityLabel("跳过当前阶段")

            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(TFIconButtonStyle())
            .disabled(snapshot.phase == .idle && !snapshot.isFinished)
            .opacity(snapshot.phase == .idle && !snapshot.isFinished ? 0.4 : 1)
            .help("重置")
            .accessibilityLabel("重置计时")
        }
    }

    private var primaryIcon: String {
        if snapshot.isPaused { return "play.fill" }
        if snapshot.isRunning { return "pause.fill" }
        return snapshot.isFinished ? "arrow.right" : "play.fill"
    }

    // MARK: - 快捷倒计时

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷开始")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach([5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) 分钟") {
                        model.startPreset(minutes)
                    }
                    .buttonStyle(TFChipButtonStyle())
                    .help("开始 \(minutes) 分钟倒计时")
                }
            }
        }
    }

    private var customInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("自定义分钟", text: $customMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(startCustom)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )

            Button("开始") { startCustom() }
                .buttonStyle(TFChipButtonStyle(tint: accent, prominent: true))
                .frame(width: 68)
                .disabled(!isCustomValid)
                .opacity(isCustomValid ? 1 : 0.45)
        }
    }

    private var isCustomValid: Bool {
        Int(customMinutes).map { (1...180).contains($0) } ?? false
    }

    private func startCustom() {
        guard let value = Int(customMinutes), (1...180).contains(value) else { return }
        model.startCustom(value)
        customMinutes = ""
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.6)

            HStack(spacing: 2) {
                Button {
                    model.openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(TFFooterButtonStyle())
                .keyboardShortcut(",")

                Button {
                    model.setClockVisible(!model.clockVisible)
                } label: {
                    Label(
                        model.clockVisible ? "隐藏时钟" : "显示时钟",
                        systemImage: model.clockVisible ? "eye.slash" : "eye"
                    )
                }
                .buttonStyle(TFFooterButtonStyle())
                .help("在桌面显示或隐藏翻转时钟")

                Spacer(minLength: 8)

                Text(footerStats)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 文案

    /// 弹窗底部：优先显示今日目标进度，没设目标就退回轮次。
    private var footerStats: String {
        let stats = model.stats
        if stats.dailyGoalSessions > 0 {
            return "今日 \(stats.todaySessions)/\(stats.dailyGoalSessions) · 连续 \(stats.streakDays) 天"
        }
        return "完成 \(snapshot.completedFocusSessions) 轮"
    }

    private var phaseTitle: String {
        if snapshot.isPaused { return "已暂停" }
        if snapshot.isFinished {
            switch snapshot.nextPhase {
            case .shortBreak: return "专注完成"
            case .longBreak: return "该长休了"
            case .focus: return "休息结束"
            default: return "已完成"
            }
        }
        switch snapshot.phase {
        case .focus: return snapshot.isCustom ? "自定义倒计时" : "专注中"
        case .shortBreak: return "短休"
        case .longBreak: return "长休"
        case .idle: return "准备开始"
        }
    }

    private var subtitle: String {
        if snapshot.isFinished, let next = snapshot.nextPhase {
            return "下一阶段 · \(nextTitle(next)) \(durations.minutes(for: next)) 分钟"
        }
        if snapshot.isPaused { return "点击继续 · 剩余 \(snapshot.displaySeconds / 60) 分钟" }
        if snapshot.phase == .idle {
            return "\(durations.focusMinutes) 分钟专注 · \(durations.sessionsPerLongBreak) 轮后长休"
        }
        if snapshot.isCustom { return "自定义 · 结束后回到空闲" }
        if snapshot.phase.isBreak {
            return "休息一下 · 接下来第 \(snapshot.completedFocusSessions + 1) 轮"
        }
        return "第 \(snapshot.completedFocusSessions + 1) 轮 · 共 \(durations.focusMinutes) 分钟"
    }

    private var primaryTitle: String {
        if snapshot.isPaused { return "继续" }
        if snapshot.isRunning { return "暂停" }
        return snapshot.isFinished ? "开始下一阶段" : "开始专注"
    }

    private func nextTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "专注"
        case .shortBreak: return "短休"
        case .longBreak: return "长休"
        case .idle: return "空闲"
        }
    }
}
