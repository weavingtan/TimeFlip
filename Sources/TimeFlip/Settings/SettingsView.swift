import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var page: Page
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    enum Page: String, CaseIterable, Identifiable {
        case timer = "计时器"
        case clock = "桌面时钟"
        case general = "通用"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .timer: return "timer"
            case .clock: return "clock"
            case .general: return "gearshape"
            }
        }
    }

    private let rendering: Bool

    init(model: AppModel, initialPage: Page = .timer, rendering: Bool = false) {
        self.model = model
        self.rendering = rendering
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            if rendering {
                pageBody
            } else {
                ScrollView {
                    pageBody
                }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch page {
            case .timer: timerPage
            case .clock: clockPage
            case .general: generalPage
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 侧栏

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                Text("TimeFlip")
                    .font(.headline)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)

            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .frame(width: 16)
                        Text(item.rawValue)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(page == item ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(page == item ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Text("v1.0")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
        .padding(16)
        .frame(width: 190)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - 计时器

    private var timerPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("时长") {
                stepperRow("专注", value: model.binding(\.timer.durations.focusMinutes), range: 1...180)
                stepperRow("短休", value: model.binding(\.timer.durations.shortBreakMinutes), range: 1...180)
                stepperRow("长休", value: model.binding(\.timer.durations.longBreakMinutes), range: 1...180)
                HStack {
                    Text("几轮后长休")
                        .frame(width: 110, alignment: .leading)
                    Stepper(
                        value: model.binding(\.timer.durations.sessionsPerLongBreak),
                        in: 2...8
                    ) {
                        Text("\(model.settings.timer.durations.sessionsPerLongBreak) 轮")
                    }
                    Spacer()
                }
            }

            section("流程") {
                Toggle("自动开始下一阶段", isOn: model.binding(\.timer.autoStartNext))
                    .toggleStyle(.checkbox)
                Text("关闭时，阶段结束会停在菜单栏等待手动开始。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            section("提醒") {
                HStack {
                    Text("提示音")
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: soundBinding) {
                        Text("无").tag("")
                        ForEach(ChimePlayer.availableSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Button("试听") {
                        model.previewChime(model.settings.timer.soundName)
                    }
                    Spacer()
                }
                Text("通知被系统拦下时，会改为菜单栏图标变红 + 提示音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            section("快捷键") {
                Text("⌃⌥⌘T 开始 / 暂停（全局生效）")
                    .font(.system(size: 13, weight: .medium))
                Text("若与其他应用冲突，会自动回退到默认组合。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 桌面时钟

    private var clockPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            previewCard

            section("显示") {
                Picker("内容", selection: model.binding(\.behavior.showMode)) {
                    Text("自动").tag(ShowMode.auto)
                    Text("仅倒计时").tag(ShowMode.countdownOnly)
                    Text("仅时钟").tag(ShowMode.clockOnly)
                }
                .pickerStyle(.segmented)
                .frame(width: 340)

                HStack(spacing: 20) {
                    Picker("形态", selection: model.binding(\.behavior.form)) {
                        Text("浮动窗口").tag(WindowForm.floating)
                        Text("铺满屏幕").tag(WindowForm.fullScreen)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Picker("层级", selection: model.binding(\.behavior.layer)) {
                        Text("贴桌面").tag(WindowLayer.desktop)
                        Text("始终置顶").tag(WindowLayer.floating)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                HStack(spacing: 14) {
                    Toggle(
                        "在桌面显示",
                        isOn: Binding(
                            get: { model.settings.behavior.visible },
                            set: { model.setClockVisible($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    Button("调整桌面时钟位置") {
                        model.adjustPosition()
                    }
                    Text("进入后 8 秒内可拖动，带虚线边框")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            section("外观") {
                Picker("样式", selection: model.binding(\.appearance.style)) {
                    Text("翻转卡片").tag(ClockStyle.flip)
                    Text("纯数字").tag(ClockStyle.digital)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                HStack(spacing: 10) {
                    Text("字号")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: model.binding(\.appearance.fontSize), in: 12...400)
                    Text("\(Int(model.settings.appearance.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }

                HStack(spacing: 14) {
                    Text("背景色")
                        .frame(width: 60, alignment: .leading)
                    ColorPicker("", selection: model.colorBinding(\.appearance.backgroundColor))
                        .labelsHidden()
                    Text("不透明度")
                        .frame(width: 64, alignment: .leading)
                    Slider(value: model.binding(\.appearance.backgroundOpacity), in: 0...1)
                        .frame(width: 170)
                    Text(String(format: "%.0f%%", model.settings.appearance.backgroundOpacity * 100))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                HStack(spacing: 14) {
                    Text("字体")
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: model.binding(\.appearance.fontFamily)) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)

                    Text("字重")
                        .frame(width: 44, alignment: .leading)
                    Picker("", selection: model.binding(\.appearance.fontWeight)) {
                        Text("粗体").tag(ClockFontWeight.bold)
                        Text("特粗").tag(ClockFontWeight.heavy)
                        Text("黑体").tag(ClockFontWeight.black)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                HStack(spacing: 14) {
                    Text("字体色")
                        .frame(width: 60, alignment: .leading)
                    ColorPicker("", selection: model.colorBinding(\.appearance.textColor))
                        .labelsHidden()

                    Toggle("阴影", isOn: model.binding(\.appearance.shadowEnabled))
                        .toggleStyle(.checkbox)

                    Text("强度")
                        .frame(width: 44, alignment: .leading)
                    Slider(value: model.binding(\.appearance.shadowRadius), in: 0...40)
                        .frame(width: 150)
                }
            }

            section("显示项") {
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    Toggle("显示秒", isOn: model.binding(\.appearance.showSeconds))
                    Toggle("显示日期", isOn: model.binding(\.appearance.showDate))
                    Toggle("显示底行", isOn: model.binding(\.appearance.showBottomLine))
                    Toggle("24 小时制", isOn: model.binding(\.appearance.use24Hour))
                    Toggle("冒号闪烁", isOn: model.binding(\.appearance.colonBlink))
                    Toggle("小时前导零", isOn: model.binding(\.appearance.showLeadingZero))
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var previewCard: some View {
        var settings = model.settings
        settings.appearance.fontSize = 30
        let metrics = ClockMetrics.floating(appearance: settings.appearance)
        let render = ClockRenderModel.make(snapshot: model.snapshot, settings: settings, metrics: metrics)

        return FlipClockView(model: render)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 通用

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("启动") {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LoginItem.set(newValue)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            section("菜单栏") {
                Picker("显示内容", selection: model.binding(\.menuBar.style)) {
                    Text("图标 + 时间").tag(MenuBarSettings.Style.iconAndTime)
                    Text("仅时间").tag(MenuBarSettings.Style.timeOnly)
                    Text("仅图标").tag(MenuBarSettings.Style.iconOnly)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Toggle("显示圆环进度", isOn: model.binding(\.menuBar.showProgressRing))
                    .toggleStyle(.checkbox)
            }

            section("重置") {
                Button("恢复默认设置") {
                    model.settings = TimeFlipSettings()
                    model.setClockVisible(true)
                    model.commitSettings()
                }
                Text("会同时重置桌面时钟的位置与外观。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 组件

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
                .frame(width: 110, alignment: .leading)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) 分钟")
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private var soundBinding: Binding<String> {
        Binding(
            get: { model.settings.timer.soundName ?? "" },
            set: { newValue in
                model.settings.timer.soundName = newValue.isEmpty ? nil : newValue
                model.commitSettings()
            }
        )
    }

    private var fontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }
}

extension AppModel {
    func binding<T>(_ keyPath: WritableKeyPath<TimeFlipSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                self.settings[keyPath: keyPath] = newValue
                self.commitSettings()
            }
        )
    }

    func colorBinding(_ keyPath: WritableKeyPath<TimeFlipSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { self.settings[keyPath: keyPath].color },
            set: { newValue in
                let nsColor = NSColor(newValue).usingColorSpace(.sRGB) ?? .black
                let existing = self.settings[keyPath: keyPath]
                self.settings[keyPath: keyPath] = RGBAColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    alpha: existing.alpha
                )
                self.commitSettings()
            }
        )
    }
}
