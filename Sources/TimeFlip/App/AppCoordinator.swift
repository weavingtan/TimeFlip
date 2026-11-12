import AppKit
import Foundation

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
    private var tickTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    /// 每秒都会刷新，用上一次的输入做去重：菜单栏图标与挂件只在真正变化时重绘。
    private var lastStatusSnapshot: TimerSnapshot?
    private var lastMenuBar: MenuBarSettings?
    private var lastRender: ClockRenderModel?
    private var lastBehavior: ClockBehavior?
    private var lastPlacements: [String: WindowOrigin] = [:]
    private var hasRenderedClock = false

    override init() {
        let store = SettingsStore(directory: AppPaths.supportDirectory)
        store.load()

        self.store = store
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

        registerHotKey()
        notifier.requestAuthorization()
        updateStatusItem()
        refreshClock()
        startTicking()
    }

    // MARK: - 装配

    private func wireEngine() {
        engine.onChange = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.handleSnapshot(snapshot)
            }
        }
        engine.onPhaseTransition = { [weak self] transition in
            DispatchQueue.main.async {
                self?.handleTransition(transition)
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
        let behavior = model.settings.behavior
        let placements = model.settings.windowPlacements

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
        if behavior.form == .fullScreen {
            // 铺满要按挂件实际所在屏幕算，副屏与主屏尺寸不同时字号才能贴合。
            let width = clockController.currentScreen?.frame.width
                ?? NSScreen.main?.frame.width
                ?? 1512
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

        guard !hasRenderedClock
            || render != lastRender
            || behavior != lastBehavior
            || placements != lastPlacements
        else { return }

        hasRenderedClock = true
        lastRender = render
        lastBehavior = behavior
        lastPlacements = placements
        clockController.update(render: render, behavior: behavior, placements: placements)
    }

    private func updateStatusItem() {
        guard let statusItemController else { return }
        guard lastStatusSnapshot != model.snapshot || lastMenuBar != model.settings.menuBar else {
            return
        }
        lastStatusSnapshot = model.snapshot
        lastMenuBar = model.settings.menuBar
        statusItemController.update(snapshot: model.snapshot, settings: model.settings)
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

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
        }
        settingsController?.show()
    }

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
        engine.tick()
        refreshClock()
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
