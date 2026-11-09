import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @State private var customMinutes = ""

    private var snapshot: TimerSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            Divider()
            presets
            customInput
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeStrings.countdown(seconds: snapshot.displaySeconds))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(snapshot.isFinished ? Color.red : Color.primary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(primaryTitle) {
                model.toggle()
            }
            .keyboardShortcut(.defaultAction)

            Button("跳过") { model.skip() }
                .disabled(snapshot.phase == .idle)

            Button("重置") { model.reset() }
                .disabled(snapshot.phase == .idle && !snapshot.isFinished)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快捷倒计时")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes)") {
                        model.startPreset(minutes)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var customInput: some View {
        HStack(spacing: 8) {
            TextField("自定义分钟", text: $customMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
            Button("开始") {
                if let value = Int(customMinutes), (1...180).contains(value) {
                    model.startCustom(value)
                    customMinutes = ""
                }
            }
            .disabled(Int(customMinutes).map { (1...180).contains($0) } != true)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Button("设置…") { model.openSettings() }
            Spacer()
            Text("完成 \(snapshot.completedFocusSessions) 轮")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(model.clockVisible ? "隐藏时钟" : "显示时钟") {
                model.setClockVisible(!model.clockVisible)
            }
            .controlSize(.small)
        }
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
            return "下一阶段 · \(nextTitle(next))"
        }
        if snapshot.isPaused { return "点击继续" }
        if snapshot.phase == .idle { return "\(model.settings.timer.durations.focusMinutes) 分钟专注" }
        return snapshot.isCustom ? "自定义" : "第 \(snapshot.completedFocusSessions + 1) 轮"
    }

    private var primaryTitle: String {
        if snapshot.isPaused { return "继续" }
        if snapshot.isRunning { return "暂停" }
        return snapshot.isFinished ? "开始下一阶段" : "开始"
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
