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

        var title: String {
            switch self {
            case .timer: return "计时器"
            case .clock: return "桌面时钟"
            case .general: return "通用"
            }
        }

        var caption: String {
            switch self {
            case .timer: return "番茄流程、时长与提醒"
            case .clock: return "挂在桌面上的翻转时钟"
            case .general: return "启动项、菜单栏与数据"
            }
        }
    }

    /// `rendering`：离屏渲染时不用 ScrollView（ImageRenderer 渲染不了滚动容器），
    /// 直接把整页铺开画出来。
    private let rendering: Bool

    init(model: AppModel, initialPage: Page = .timer, rendering: Bool = false) {
        self.model = model
        self.rendering = rendering
        _page = State(initialValue: initialPage)
    }

    private var settings: TimeFlipSettings { model.settings }
    private var durations: Durations { model.settings.timer.durations }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().opacity(0.6)
            pageArea
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 19, weight: .semibold))
                Text(page.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().opacity(0.5)

            if rendering {
                pageBody.padding(28)
            } else {
                ScrollView {
                    pageBody.padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pageBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch page {
            case .timer: timerPage
            case .clock: clockPage
            case .general: generalPage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 侧栏

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [TFTheme.accent(for: .focus), TFTheme.accent(for: .longBreak)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text("TimeFlip")
                        .font(.system(size: 13, weight: .semibold))
                    Text("翻转时钟")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(Page.allCases) { item in
                Button {
                    page = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(page == item ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
        }
        .padding(16)
        .frame(width: 200)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - 计时器

    private var timerPage: some View {
        VStack(spacing: 16) {
            card("阶段时长") {
                stepperRow("专注", value: model.binding(\.timer.durations.focusMinutes), range: 1...180)
                stepperRow("短休", value: model.binding(\.timer.durations.shortBreakMinutes), range: 1...180)
                stepperRow("长休", value: model.binding(\.timer.durations.longBreakMinutes), range: 1...180)
                row("几轮后长休") {
                    Stepper(value: model.binding(\.timer.durations.sessionsPerLongBreak), in: 2...8) {
                        Text("\(durations.sessionsPerLongBreak) 轮")
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                }
                hint("时长改动会立刻作用于空闲状态的倒计时，不影响正在跑的计时。")
            }

            card("流程") {
                Toggle("自动开始下一阶段", isOn: model.binding(\.timer.autoStartNext))
                    .toggleStyle(.checkbox)
                hint("关闭时，阶段结束会停在菜单栏等待手动开始。")
                cycleHint
            }

            card("提醒") {
                row("提示音") {
                    Picker("", selection: soundBinding) {
                        Text("无").tag("")
                        ForEach(ChimePlayer.availableSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)

                    Button("试听") {
                        model.previewChime(model.settings.timer.soundName)
                    }
                    .buttonStyle(TFChipButtonStyle())
                    .frame(width: 62)
                }
                hint("通知被系统拦下时，会改为菜单栏图标变红 + 提示音。")
            }

            card("快捷键") {
                HStack(spacing: 6) {
                    ForEach(["⌃", "⌥", "⌘", "T"], id: \.self) { key in
                        Text(key)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(minWidth: 22, minHeight: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                    }
                    Text("开始 / 暂停（全局生效）")
                        .font(.system(size: 12))
                        .padding(.leading, 4)
                }
                hint("若与其他应用冲突，会自动回退到默认组合。")
            }
        }
    }

    private var cycleHint: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(2, durations.sessionsPerLongBreak), id: \.self) { index in
                Capsule()
                    .fill(TFTheme.accent(for: .focus).opacity(0.75))
                    .frame(width: 16, height: 4)
                    .opacity(index == durations.sessionsPerLongBreak - 1 ? 0.35 : 1)
            }
            Text("每 \(durations.sessionsPerLongBreak) 轮一次长休")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }

    // MARK: - 桌面时钟

    private var clockPage: some View {
        VStack(spacing: 16) {
            previewCard

            card("显示") {
                row("内容") {
                    Picker("", selection: model.binding(\.behavior.showMode)) {
                        Text("自动").tag(ShowMode.auto)
                        Text("仅倒计时").tag(ShowMode.countdownOnly)
                        Text("仅时钟").tag(ShowMode.clockOnly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                row("形态") {
                    Picker("", selection: model.binding(\.behavior.form)) {
                        Text("浮动窗口").tag(WindowForm.floating)
                        Text("铺满屏幕").tag(WindowForm.fullScreen)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                row("层级") {
                    Picker("", selection: model.binding(\.behavior.layer)) {
                        Text("贴桌面").tag(WindowLayer.desktop)
                        Text("始终置顶").tag(WindowLayer.floating)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                row("桌面") {
                    Toggle(
                        "在桌面显示",
                        isOn: Binding(
                            get: { model.settings.behavior.visible },
                            set: { model.setClockVisible($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }

                hint("贴桌面时落在所有窗口之下，不挡任何 App；按住时钟任意位置即可拖动，位置按屏幕记住。")
            }

            card("外观") {
                row("样式") {
                    Picker("", selection: model.binding(\.appearance.style)) {
                        Text("翻转卡片").tag(ClockStyle.flip)
                        Text("纯数字").tag(ClockStyle.digital)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                row("字体") {
                    Picker("", selection: model.binding(\.appearance.fontFamily)) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family)
                                .font(.custom(family, size: 12))
                                .tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)

                    Text("字重")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    Picker("", selection: model.binding(\.appearance.fontWeight)) {
                        Text("粗体").tag(ClockFontWeight.bold)
                        Text("特粗").tag(ClockFontWeight.heavy)
                        Text("黑体").tag(ClockFontWeight.black)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                sliderRow("字号", value: fontSizeBinding, range: 12...400, badge: "\(Int(settings.appearance.fontSize.rounded())) pt")

                row("字体色") {
                    ColorPicker("", selection: model.colorBinding(\.appearance.textColor))
                        .labelsHidden()
                        .accessibilityLabel("字体颜色")
                    Toggle("阴影", isOn: model.binding(\.appearance.shadowEnabled))
                        .toggleStyle(.checkbox)
                        .padding(.leading, 10)
                    Slider(value: model.binding(\.appearance.shadowRadius), in: 0...40)
                        .frame(width: 130)
                    Text("\(Int(settings.appearance.shadowRadius.rounded()))")
                        .tfValueBadge()
                }

                row("背景色") {
                    ColorPicker("", selection: model.colorBinding(\.appearance.backgroundColor))
                        .labelsHidden()
                        .accessibilityLabel("背景颜色")
                    Text("不透明度")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                    Slider(value: opacityBinding, in: 0...1)
                        .frame(width: 150)
                    Text(String(format: "%.0f%%", settings.appearance.backgroundOpacity * 100))
                        .tfValueBadge()
                }
            }

            card("显示项") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
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
        var previewSettings = model.settings
        previewSettings.appearance.fontSize = 30
        let metrics = ClockMetrics.floating(appearance: previewSettings.appearance)
        let render = ClockRenderModel.make(snapshot: model.snapshot, settings: previewSettings, metrics: metrics)

        return FlipClockView(model: render)
            .frame(maxWidth: .infinity, minHeight: 158)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.30, blue: 0.40),
                            Color(red: 0.12, green: 0.14, blue: 0.21)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .overlay(alignment: .topLeading) {
                Text("实时预览")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: TFTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TFTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: - 通用

    private var generalPage: some View {
        VStack(spacing: 16) {
            card("启动") {
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
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            card("菜单栏") {
                row("显示内容") {
                    Picker("", selection: model.binding(\.menuBar.style)) {
                        Text("图标 + 时间").tag(MenuBarSettings.Style.iconAndTime)
                        Text("仅时间").tag(MenuBarSettings.Style.timeOnly)
                        Text("仅图标").tag(MenuBarSettings.Style.iconOnly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                Toggle("显示圆环进度", isOn: model.binding(\.menuBar.showProgressRing))
                    .toggleStyle(.checkbox)
                hint("圆环随当前阶段推进，结束时数字变红。")
            }

            card("数据") {
                hint("设置与窗口位置保存在 ~/Library/Application Support/TimeFlip/settings.json")
                Button("在访达中显示设置文件") {
                    model.revealSettings()
                }
                .buttonStyle(TFChipButtonStyle())
                .frame(width: 190)
            }

            card("重置") {
                Button("恢复默认设置") {
                    model.settings = TimeFlipSettings()
                    model.setClockVisible(true)
                    model.commitSettings()
                }
                .buttonStyle(TFChipButtonStyle(tint: TFTheme.accent(for: .focus), prominent: true))
                .frame(width: 140)
                hint("会同时重置桌面时钟的位置与外观。")
            }
        }
    }

    // MARK: - 组件

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
        .tfCard()
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        row(title) {
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) 分钟")
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        badge: String
    ) -> some View {
        row(title) {
            Slider(value: value, in: range)
                .frame(width: 260)
            Text(badge).tfValueBadge()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 绑定

    private var soundBinding: Binding<String> {
        Binding(
            get: { model.settings.timer.soundName ?? "" },
            set: { newValue in
                model.settings.timer.soundName = newValue.isEmpty ? nil : newValue
                model.commitSettings()
            }
        )
    }

    /// 字号滑杆按整数 pt 吸附，避免设置面板里出现 96.372 pt。
    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { model.settings.appearance.fontSize.rounded() },
            set: { newValue in
                model.settings.appearance.fontSize = newValue.rounded()
                model.commitSettings()
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { model.settings.appearance.backgroundOpacity },
            set: { newValue in
                model.settings.appearance.backgroundOpacity = (newValue * 100).rounded() / 100
                model.commitSettings()
            }
        )
    }

    /// 枚举全部字族开销不小，缓存一次；否则拖滑杆时每帧都会重新枚举。
    private static let allFontFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    private var fontFamilies: [String] { Self.allFontFamilies }
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
