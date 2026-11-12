import AppKit
import Foundation
import UniformTypeIdentifiers

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("TimeFlip", isDirectory: true)
    }
}

@MainActor
final class AppCoordinator: NSObject {
    private let store: SettingsStore
    private let engine: TimerEngine
    private let model: AppModel

    private var statusItemController: StatusItemController?
    private var clockController: FloatingClockWindowController?
    private var settingsController: SettingsWindowController?
    private var hotKey: HotKey?
    private let chime = ChimePlayer()
    private let notifier = Notifier()
    private let sessionLog: SessionLog
    private let locker = ScreenLocker()
    private let breakOverlay = BreakOverlayController()
    private let graceOverlay = GraceOverlayController()
    private var tickTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?
    /// 上一次 tick 的时刻：间隔过大说明刚从睡眠里出来，不能一醒来就锁屏。
    private var lastTickDate = Date()
    private var wokeFromSleep = false

    override init() {
        let store = SettingsStore(directory: AppPaths.supportDirectory)
        store.load()

        let log = SessionLog(directory: AppPaths.supportDirectory)
        log.load()
        log.prune()

        self.store = store
        self.sessionLog = log
        let timerSettings = store.settings.timer
        self.engine = TimerEngine(
            durations: timerSettings.durations,
            autoStartNext: timerSettings.autoStartNext
        )
        self.model = AppModel(snapshot: engine.snapshot, settings: store.settings)
        super.init()
    }

    func start() {
        wireEngine()
        wireActions()

        statusItemController = StatusItemController(model: model)

        let clock = FloatingClockWindowController()
        clock.onMove = { [weak self] screenID, origin in
            self?.persistPlacement(screenID: screenID, origin: origin)
        }
        clockController = clock

        model.stats = computeStats()
        registerHotKey()
        notifier.requestAuthorization()
        updateStatusItem()
        refreshClock()
        startTicking()
    }

    // MARK: - 装配

    private func wireEngine() {
        // 引擎只在主线程被驱动，因此同步回调即可：
        // 「睡眠唤醒后不锁屏」这个判断依赖 tick 内同步消费 wokeFromSleep。
        engine.onChange = { [weak self] snapshot in
            guard let self else { return }
            if Thread.isMainThread {
                self.handleSnapshot(snapshot)
            } else {
                DispatchQueue.main.async { self.handleSnapshot(snapshot) }
            }
        }
        engine.onPhaseTransition = { [weak self] transition in
            guard let self else { return }
            if Thread.isMainThread {
                self.handleTransition(transition)
            } else {
                DispatchQueue.main.async { self.handleTransition(transition) }
            }
        }
    }

    private func wireActions() {
        model.toggle = { [weak self] in self?.toggleTimer() }
        model.skip = { [weak self] in self?.engine.skip() }
        model.reset = { [weak self] in self?.engine.reset() }
        model.startPreset = { [weak self] minutes in self?.engine.startCustom(minutes: minutes) }
        model.startCustom = { [weak self] minutes in self?.engine.startCustom(minutes: minutes) }
        model.openSettings = { [weak self] in self?.openSettings() }
        model.setClockVisible = { [weak self] visible in self?.setClockVisible(visible) }
        model.quit = { NSApp.terminate(nil) }
        model.previewChime = { [weak self] name in self?.chime.play(name: name) }
        model.commitSettings = { [weak self] in self?.applySettings() }
        model.revealSettings = { [weak self] in self?.revealSettingsFile() }
        model.applyTheme = { [weak self] id in self?.applyTheme(id: id) }
        model.copyTheme = { [weak self] in self?.copyThemeToPasteboard() }
        model.importThemeFromClipboard = { [weak self] in self?.importThemeFromPasteboard() }
        model.exportThemeFile = { [weak self] in self?.exportThemeFile() }
        model.importThemeFile = { [weak self] in self?.importThemeFile() }
        model.copyStatsImage = { [weak self] in self?.copyStatsImage() }
        model.saveStatsImage = { [weak self] in self?.saveStatsImage() }
        model.requestAccessibility = { ScreenLocker().requestAccessibility() }
    }

    private func registerHotKey() {
        let spec = model.settings.timer.hotKey
        let hotKey = HotKey(spec: spec) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleTimer()
            }
        }
        self.hotKey = hotKey

        if ProcessInfo.processInfo.environment["TIMEFLIP_DEBUG"] == "1" {
            NSLog("TimeFlip hotkey registered=%@ spec=%@", hotKey.isRegistered ? "true" : "false", String(describing: spec))
        }

        if !hotKey.isRegistered, spec != .default {
            _ = hotKey.reload(spec: .default)
            model.settings.timer.hotKey = .default
            showAlert("快捷键注册失败", "原组合可能已被其他应用占用，已回退到 ⌃⌥⌘T。")
        }
    }

    // MARK: - 事件

    private func handleSnapshot(_ snapshot: TimerSnapshot) {
        model.snapshot = snapshot
        updateStatusItem()
        refreshClock()
    }

    private func handleTransition(_ transition: PhaseTransition) {
        if transition.from == .focus {
            recordSession(transition)
            model.stats = computeStats()
        }

        let woke = wokeFromSleep
        wokeFromSleep = false

        guard transition.reason == .completed else { return }

        chime.play(name: model.settings.timer.soundName)

        let title: String
        switch transition.from {
        case .focus: title = "专注完成"
        case .shortBreak, .longBreak: title = "休息结束"
        case .idle: title = "时间到"
        }

        let next = transition.to ?? model.snapshot.nextPhase
        let body: String
        if let next {
            body = "下一阶段：\(displayName(next))"
        } else {
            body = "点击菜单栏图标继续"
        }

        notifier.notify(title: title, body: body)
        if !notifier.isAuthorized {
            statusItemController?.flashRed()
        }

        applyRestPolicy(transition: transition, wokeFromSleep: woke)
    }

    /// 阶段结束后的"强制休息"：铺遮罩、倒计时、必要时锁屏。
    private func applyRestPolicy(transition: PhaseTransition, wokeFromSleep: Bool) {
        let settings = model.settings.lock
        let next = transition.to ?? model.snapshot.nextPhase
        let needsScreenCheck = settings.isEnabled && transition.from == .focus
        let action = LockPolicy.action(
            settings: settings,
            finishedPhase: transition.from,
            isCustom: transition.isCustom,
            wokeFromSleep: wokeFromSleep,
            hasFullScreenApp: needsScreenCheck ? locker.hasFullScreenApp() : false
        )

        if action.overlay, transition.from == .focus, let next, next.isBreak {
            // 遮罩开启时顺手把休息跑起来：否则遮罩上的倒计时不会动。
            if model.snapshot.phase == .idle {
                engine.start()
            }
            showBreakOverlay(phase: next)
        }

        guard let style = action.lock else { return }
        if action.delaySeconds <= 0 {
            lockNow(style: style)
        } else {
            showGrace(style: style, seconds: action.delaySeconds)
        }
    }

    private func showBreakOverlay(phase: TimerPhase) {
        let total = model.settings.timer.durations.minutes(for: phase) * 60
        let remaining = model.snapshot.phase == phase ? model.snapshot.displaySeconds : total
        breakOverlay.show(phase: phase, remaining: remaining, total: total) { [weak self] in
            guard let self else { return }
            self.breakOverlay.hide()
            self.engine.skip()
        }
    }

    private func showGrace(style: LockStyle, seconds: Int) {
        graceOverlay.show(seconds: seconds, style: style) { [weak self] in
            self?.lockNow(style: style)
        } onSnooze: { [weak self] in
            // 再来 5 分钟：直接开一轮自定义倒计时，结束后不再锁屏（自定义不锁）。
            self?.engine.startCustom(minutes: 5)
        } onSkip: {
            // 用户明确放弃这次强制休息，不写进统计（这本来就不是一次专注）。
        }
    }

    private func lockNow(style: LockStyle) {
        breakOverlay.hide()
        guard locker.perform(style) else {
            notifier.notify(title: "锁屏失败", body: "系统拒绝了这次锁屏，可以手动按 ⌃⌘Q。")
            statusItemController?.flashRed()
            return
        }
    }

    private func toggleTimer() {
        if engine.snapshot.isRunning {
            engine.pause()
        } else {
            engine.start()
        }
    }

    // MARK: - 时钟

    private func refreshClock() {
        guard let clockController else { return }

        let now = Date()
        let appearance = model.settings.appearance
        updateStatusItem()
        let text = ClockRenderModel.displayText(
            snapshot: model.snapshot,
            settings: model.settings,
            now: now,
            calendar: .current
        )
        let characters = Array(text)
        let slots = characters.filter { $0 != ":" }.count
        let colons = characters.count - slots

        let metrics: ClockMetrics
        if model.settings.behavior.form == .fullScreen {
            let width = NSScreen.main?.frame.width ?? 1512
            metrics = ClockMetrics.fullScreen(
                screenWidth: width,
                appearance: appearance,
                slots: slots,
                colons: colons
            )
        } else {
            metrics = ClockMetrics.floating(appearance: appearance)
        }

        let render = ClockRenderModel.make(
            snapshot: model.snapshot,
            settings: model.settings,
            metrics: metrics,
            now: now
        )
        clockController.update(
            render: render,
            behavior: model.settings.behavior,
            placements: model.settings.windowPlacements
        )
    }

    private func updateStatusItem() {
        statusItemController?.update(snapshot: model.snapshot, settings: model.settings)
    }

    private func setClockVisible(_ visible: Bool) {
        model.settings.behavior.visible = visible
        model.clockVisible = visible
        refreshClock()
        scheduleSave()
    }

    private func persistPlacement(screenID: String, origin: WindowOrigin) {
        model.settings.windowPlacements[screenID] = origin
        scheduleSave()
    }

    // MARK: - 设置

    private func applySettings() {
        let settings = model.settings
        engine.autoStartNext = settings.timer.autoStartNext
        engine.updateDurations(settings.timer.durations)
        model.clockVisible = settings.behavior.visible

        if let hotKey, !hotKey.reload(spec: settings.timer.hotKey), settings.timer.hotKey != .default {
            _ = hotKey.reload(spec: .default)
            model.settings.timer.hotKey = .default
        }

        model.stats = computeStats()
        updateStatusItem()
        refreshClock()
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushPendingSave()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// 退出前把待落盘的设置（含窗口位置）立刻写掉：拖完马上退出也不会丢位置。
    func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        _ = try? store.update { settings in
            settings = self.model.settings
        }
    }

    func hitTestReport() -> String {
        clockController?.hitTestReport() ?? "no clock window"
    }

    func dragRegressionReport() -> String {
        clockController?.dragRegressionReport() ?? "DRAGTEST skip=no-clock"
    }

    /// 自检：不真的锁屏，只把锁屏决策链和系统前提打印出来。
    func restPolicyReport() -> String {
        var probe = model.settings.lock
        probe.style = .displaySleep
        probe.graceSeconds = 7
        let action = LockPolicy.action(
            settings: probe,
            finishedPhase: .focus,
            isCustom: false,
            wokeFromSleep: false,
            hasFullScreenApp: false
        )
        return "RESTTEST lock=\(action.lock?.rawValue ?? "nil") delay=\(action.delaySeconds) "
            + "overlay=\(action.overlay) ax=\(locker.isAccessibilityTrusted) "
            + "password=\(locker.hasAccountPassword) fullscreen=\(locker.hasFullScreenApp())"
    }

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
        }
        settingsController?.show()
    }

    /// 「在访达中显示设置文件」：文件还没落盘时退回到目录本身。
    private func revealSettingsFile() {
        try? FileManager.default.createDirectory(
            at: AppPaths.supportDirectory,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: store.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } else {
            NSWorkspace.shared.open(AppPaths.supportDirectory)
        }
    }

    // MARK: - 定时器

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(onTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    @objc private func onTick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        // 相邻两次 tick 差了 20 秒以上，基本就是刚从睡眠里出来。
        wokeFromSleep = gap > LockPolicy.wakeGapThreshold

        engine.tick()
        wokeFromSleep = false

        refreshClock()
        updateBreakOverlay()
    }

    private func updateBreakOverlay() {
        guard breakOverlay.isVisible else { return }
        if model.snapshot.phase.isBreak {
            breakOverlay.update(
                remaining: model.snapshot.displaySeconds,
                total: Int(model.snapshot.total.rounded())
            )
        } else {
            breakOverlay.hide()
        }
    }

    // MARK: - 统计

    private func recordSession(_ transition: PhaseTransition) {
        let record = SessionRecord.make(transition: transition)
        sessionLog.append(record)
        sessionLog.prune()
        sessionLog.save()
    }

    private func computeStats() -> FocusStats {
        FocusStats.make(
            records: sessionLog.records,
            goal: model.settings.stats.dailyGoalSessions,
            now: Date(),
            calendar: .current
        )
    }

    private func copyStatsImage() {
        if !ShareCardRenderer.copyToPasteboard(stats: model.stats) {
            showAlert("生成失败", "这张统计图没能画出来，请稍后再试。")
        }
    }

    private func saveStatsImage() {
        if ShareCardRenderer.savePNG(stats: model.stats) == nil {
            // 用户取消保存不需要提示，只有真的写失败才说一声。
            showAlert("保存失败", "统计图没有保存成功，请检查目标文件夹权限。")
        }
    }

    // MARK: - 主题

    private func applyTheme(id: String) {
        guard let preset = ThemePreset.preset(id: id) else { return }
        model.settings.appearance = preset.applied(to: model.settings.appearance)
        applySettings()
    }

    private func apply(document: ThemeDocument) {
        model.settings.appearance = document.appearance
        applySettings()
        showAlert("已应用主题：\(document.name)", "外观来自别人分享的配置，字号保持你原来的设置。")
    }

    private func copyThemeToPasteboard() {
        let document = ThemeDocument(name: currentThemeName, appearance: model.settings.appearance)
        guard let text = document.encoded() else {
            showAlert("导出失败", "当前外观没能编码成 JSON。")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showAlert("已复制主题", "把这串文字发给朋友，他在设置里点「从剪贴板导入」就能用。")
    }

    private func importThemeFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            showAlert("剪贴板是空的", "先复制一段主题 JSON 再回来。")
            return
        }
        guard let document = ThemeDocument.decode(text) else {
            showAlert("这不是主题", "剪贴板里的内容不是有效的主题配置。")
            return
        }
        apply(document: document)
    }

    private func exportThemeFile() {
        let document = ThemeDocument(name: currentThemeName, appearance: model.settings.appearance)
        guard let text = document.encoded() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TimeFlip-theme.json"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func importThemeFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard let document = ThemeDocument.decode(text) else {
            showAlert("这不是主题", "选中的文件不是有效的主题配置。")
            return
        }
        apply(document: document)
    }

    private var currentThemeName: String {
        ThemePreset.preset(id: model.settings.appearance.themeID)?.name ?? "自定义主题"
    }

    // MARK: - 辅助

    private func displayName(_ phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "专注"
        case .shortBreak: return "短休"
        case .longBreak: return "长休"
        case .idle: return "空闲"
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
