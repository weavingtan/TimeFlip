import AppKit
import ApplicationServices
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var page: Page
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    enum Page: String, CaseIterable, Identifiable {
        case timer = "计时器"
        case clock = "桌面时钟"
        case stats = "统计"
        case general = "通用"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .timer: return "timer"
            case .clock: return "clock"
            case .stats: return "chart.bar.fill"
            case .general: return "gearshape"
            }
        }

        var caption: String {
            switch self {
            case .timer: return "番茄流程、时长与结束后的强制休息"
            case .clock: return "主题、外观与挂在桌面上的翻转时钟"
            case .stats: return "每日目标、连续天数与分享卡片"
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
        .frame(minWidth: 800, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { accessibilityTrusted = AXIsProcessTrusted() }
        // 用户去系统设置里授权后切回来，状态要立刻更新，不能等下次打开窗口。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    private var pageArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.rawValue)
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
            case .stats: statsPage
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

            Text(versionText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
        }
        .padding(16)
        .frame(width: 200)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        return "v\(version)"
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

            lockCard

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

    private var lockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("结束专注后")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Toggle("铺全屏休息提示", isOn: model.binding(\.lock.overlayEnabled))
                .toggleStyle(.checkbox)
            hint("专注到点时盖住所有屏幕，显示休息倒计时和呼吸引导，休息结束自动消失。")

            row("锁屏") {
                Picker("", selection: model.binding(\.lock.style)) {
                    Text("关闭").tag(LockStyle.off)
                    Text("关闭屏幕").tag(LockStyle.displaySleep)
                    Text("锁定屏幕").tag(LockStyle.lock)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }

            HStack(spacing: 10) {
                Text("宽限")
                    .font(.system(size: 12))
                    .frame(width: 76, alignment: .leading)
                Stepper(value: model.binding(\.lock.graceSeconds), in: 0...60) {
                    Text(settings.lock.graceSeconds == 0 ? "立刻锁屏" : "\(settings.lock.graceSeconds) 秒后可取消")
                        .font(.system(size: 12))
                        .monospacedDigit()
                }
                .disabled(!settings.lock.isEnabled)
            }

            Toggle("前台是全屏应用时不打扰（演示 / 录屏 / 视频）", isOn: model.binding(\.lock.skipWhenFullScreenApp))
                .toggleStyle(.checkbox)

            hint("「关闭屏幕」不需要任何权限；「锁定屏幕」会发系统快捷键 ⌃⌘Q，首次需要在「系统设置 → 隐私与安全性 → 辅助功能」里授权。自定义倒计时与睡眠唤醒后都不会锁屏。")

            if settings.lock.style == .lock, !accessibilityTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("还没拿到辅助功能授权，现在会退化为「关闭屏幕」。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("去授权") {
                        model.requestAccessibility()
                        accessibilityTrusted = AXIsProcessTrusted()
                    }
                    .buttonStyle(TFChipButtonStyle(prominent: true))
                    .frame(width: 80)
                }
            }
        }
        .tfCard()
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

            themeCard

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

                    Text("材质")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    Picker("", selection: model.binding(\.appearance.material)) {
                        Text("纸面").tag(ClockMaterial.paper)
                        Text("玻璃").tag(ClockMaterial.glass)
                        Text("金属").tag(ClockMaterial.metal)
                        Text("木质").tag(ClockMaterial.wood)
                        Text("像素").tag(ClockMaterial.pixel)
                    }
                    .labelsHidden()
                    .frame(width: 100)
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
                        Text("常规").tag(ClockFontWeight.regular)
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

                Toggle("显示机身托盘", isOn: model.binding(\.appearance.showChassis))
                    .toggleStyle(.checkbox)
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

    private var themeCard: some View {
        card("主题") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(ThemePreset.all) { preset in
                    themeChip(preset)
                }
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                Button("复制我的主题") { model.copyTheme() }
                    .buttonStyle(TFChipButtonStyle())
                    .frame(width: 118)
                Button("从剪贴板导入") { model.importThemeFromClipboard() }
                    .buttonStyle(TFChipButtonStyle())
                    .frame(width: 130)
                Button("存为文件…") { model.exportThemeFile() }
                    .buttonStyle(TFChipButtonStyle())
                    .frame(width: 100)
                Button("从文件导入…") { model.importThemeFile() }
                    .buttonStyle(TFChipButtonStyle())
                    .frame(width: 110)
                Spacer(minLength: 0)
            }

            hint("主题是一串 JSON，发给朋友让他点「从剪贴板导入」即可，不需要账号也不会联网。套用预设只换外观，字号保持你现在的设置。")
        }
    }

    private func themeChip(_ preset: ThemePreset) -> some View {
        let selected = settings.appearance.themeID == preset.id

        return Button {
            model.applyTheme(preset.id)
        } label: {
            themeChipLabel(preset, selected: selected)
        }
        .buttonStyle(.plain)
        .help("套用「\(preset.name)」")
    }

    private func themeChipLabel(_ preset: ThemePreset, selected: Bool) -> some View {
        let background: Color = selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)
        let border: Color = selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08)

        return VStack(alignment: .leading, spacing: 7) {
            themeSwatch(preset.appearance)
            Text(preset.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Text(preset.subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                .strokeBorder(border, lineWidth: selected ? 1.4 : 1)
        )
    }

    private func themeSwatch(_ appearance: ClockAppearance) -> some View {
        // 用文字色判断深浅：磨砂玻璃是浅色卡配白字，底色必须按深色主题托一下才看得见。
        let isDark = appearance.textColor.luminance > 0.55
        // 玻璃材质真实不透明度很低，色板上抬到 0.55 才看得出卡面在哪。
        let minOpacity = appearance.material == .glass ? 0.55 : 0.35
        let cardFill = appearance.backgroundColor.color(
            opacity: max(minOpacity, appearance.backgroundOpacity)
        )
        let trayFill: Color = isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
        let edge: Color = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)

        return HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
                themeSwatchCard(fill: cardFill, textColor: appearance.textColor.color, edge: edge, font: appearance)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(trayFill)
        )
    }

    private func themeSwatchCard(
        fill: Color,
        textColor: Color,
        edge: Color,
        font appearance: ClockAppearance
    ) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .overlay(
                Text("8")
                    .font(.custom(appearance.fontFamily, size: 15).weight(appearance.fontWeight.swiftUI))
                    .foregroundStyle(textColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(edge, lineWidth: 0.5)
            )
    }

    private var previewCard: some View {
        var previewSettings = model.settings
        previewSettings.appearance.fontSize = 40
        let metrics = ClockMetrics.floating(appearance: previewSettings.appearance)
        let render = ClockRenderModel.make(snapshot: model.snapshot, settings: previewSettings, metrics: metrics)

        return FlipClockView(model: render)
            .frame(maxWidth: .infinity, minHeight: 172)
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

    // MARK: - 统计

    private var statsPage: some View {
        let stats = model.stats

        return VStack(spacing: 16) {
            card("概览") {
                HStack(spacing: 0) {
                    statBlock(
                        value: StatsFormatting.duration(seconds: stats.todayFocusSeconds),
                        label: "今日专注",
                        tint: TFTheme.accent(for: .focus)
                    )
                    divider
                    statBlock(
                        value: StatsFormatting.duration(seconds: stats.weekFocusSeconds),
                        label: "本周专注",
                        tint: TFTheme.accent(for: .longBreak)
                    )
                    divider
                    statBlock(
                        value: "\(stats.streakDays) 天",
                        label: "连续专注",
                        tint: TFTheme.accent(for: .shortBreak)
                    )
                    divider
                    statBlock(
                        value: "\(stats.completedCount)",
                        label: "累计完成",
                        tint: .secondary
                    )
                }
            }

            card("每日目标") {
                row("目标") {
                    Stepper(value: model.binding(\.stats.dailyGoalSessions), in: 0...24) {
                        Text(
                            settings.stats.dailyGoalSessions == 0
                                ? "不设目标"
                                : "每天 \(settings.stats.dailyGoalSessions) 轮"
                        )
                        .font(.system(size: 12))
                        .monospacedDigit()
                    }
                }

                HStack(spacing: 10) {
                    Text("今日进度")
                        .font(.system(size: 12))
                        .frame(width: 76, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                            .frame(height: 6)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(stats.goalReached ? TFTheme.accent(for: .shortBreak) : TFTheme.accent(for: .focus))
                                .frame(width: max(6, proxy.size.width * stats.goalProgress), height: 6)
                        }
                        .frame(height: 6)
                    }
                    .frame(width: 260)
                    Text("\(stats.todaySessions)/\(max(1, stats.dailyGoalSessions))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                hint("只统计走完的专注；跳过或提前放弃的会算进中断率，不算完成。")
            }

            card("最近 14 天") {
                statsBars(days: stats.last14Days)
                HStack(spacing: 18) {
                    Text("最佳时段 \(stats.bestHour.map { String(format: "%02d:00", $0) } ?? "—")")
                    Text("中断率 \(Int((stats.interruptionRate * 100).rounded()))%")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            card("分享") {
                HStack(spacing: 8) {
                    Button("复制统计图") { model.copyStatsImage() }
                        .buttonStyle(TFChipButtonStyle(prominent: true))
                        .frame(width: 110)
                    Button("保存到桌面…") { model.saveStatsImage() }
                        .buttonStyle(TFChipButtonStyle())
                        .frame(width: 118)
                    Spacer(minLength: 0)
                }
                hint("生成一张 1080×1350 的竖图：本周专注时长、连续天数、14 天曲线，直接发朋友圈或群聊。")
            }

            card("数据") {
                hint("会话记录保存在 ~/Library/Application Support/TimeFlip/sessions.json（本地，不上传，保留一年）。")
                Button("在访达中显示设置文件") {
                    model.revealSettings()
                }
                .buttonStyle(TFChipButtonStyle())
                .frame(width: 190)
            }
        }
    }

    private func statBlock(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
    }

    private func statsBars(days: [DayBucket]) -> some View {
        let maxSeconds = max(1, days.map(\.focusSeconds).max() ?? 1)

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { bucket in
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            bucket.sessions > 0
                                ? TFTheme.accent(for: .focus).opacity(0.85)
                                : Color.primary.opacity(0.10)
                        )
                        .frame(height: max(4, CGFloat(Double(bucket.focusSeconds) / Double(maxSeconds)) * 76))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 84)
        .accessibilityLabel("最近 14 天专注柱状图")
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
                    model.confirmReset()
                }
                .buttonStyle(TFChipButtonStyle(tint: TFTheme.accent(for: .focus), prominent: true))
                .frame(width: 140)
                hint("会同时重置桌面时钟的位置、外观与计时轮次，点击后还会再确认一次。")
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
