import Foundation

// 极简断言 runner：本机没有 XCTest（仅有 Command Line Tools），因此自建。

nonisolated(unsafe) var checkCount = 0
nonisolated(unsafe) var failureCount = 0

func expect(_ condition: Bool, _ label: String, line: Int = #line) {
    checkCount += 1
    if !condition {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL [\(label)] (engine-tests:\(line))\n".utf8))
    }
}

func expectEqual<T: Equatable>(_ got: T, _ want: T, _ label: String, line: Int = #line) {
    checkCount += 1
    if got != want {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL [\(label)] want \(want) got \(got) (engine-tests:\(line))\n".utf8))
    }
}

func expectClose(_ got: Double, _ want: Double, tolerance: Double = 1.5, _ label: String, line: Int = #line) {
    checkCount += 1
    if abs(got - want) > tolerance {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL [\(label)] want \(want)±\(tolerance) got \(got) (engine-tests:\(line))\n".utf8))
    }
}

func expectCloseDouble(_ got: Double, _ want: Double, tolerance: Double = 0.001, _ label: String, line: Int = #line) {
    expectClose(got, want, tolerance: tolerance, label, line: line)
}

final class TestClock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

func makeEngine(
    _ durations: Durations = .standard,
    autoStartNext: Bool = false,
    clock: TestClock
) -> TimerEngine {
    TimerEngine(durations: durations, autoStartNext: autoStartNext, now: { clock.now })
}

// MARK: - Task 1

func testInitialState() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    expectEqual(engine.snapshot.phase, .idle, "初始 phase 为 idle")
    expectEqual(engine.snapshot.remaining, 1500, "初始剩余 = 25 分钟")
    expectEqual(engine.snapshot.total, 1500, "初始 total = 25 分钟")
    expectEqual(engine.snapshot.isRunning, false, "初始未运行")
    expectEqual(engine.snapshot.isFinished, false, "初始未结束")
}

func testStartFocus() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.start()
    expectEqual(engine.snapshot.phase, .focus, "start → focus")
    expectEqual(engine.snapshot.isRunning, true, "start 后运行中")
    clock.advance(60)
    engine.tick()
    expectClose(engine.snapshot.remaining, 1440, "60 秒后剩余 1440")
    expectClose(engine.snapshot.progress, 60.0 / 1500.0, tolerance: 0.01, "进度 4%")
}

// MARK: - Task 2

func testFocusCompletesToShortBreak() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var transitions: [PhaseTransition] = []
    engine.onPhaseTransition = { transitions.append($0) }

    engine.start()
    clock.advance(1500)
    engine.tick()

    expectEqual(engine.snapshot.phase, .idle, "完成后回到 idle")
    expectEqual(engine.snapshot.isFinished, true, "完成后 isFinished")
    expectEqual(engine.snapshot.nextPhase, .shortBreak, "下一阶段是短休")
    expectEqual(engine.snapshot.completedFocusSessions, 1, "完成 1 个专注")
    expectEqual(transitions.count, 1, "只发一次阶段事件")
    expectEqual(transitions.first?.from, .focus, "事件 from = focus")
    expectEqual(transitions.first?.to, nil, "未自动开始时 to = nil")
    expectEqual(transitions.first?.reason, .completed, "事件原因是完成")
    expectEqual(transitions.first?.plannedSeconds, 1500, "事件带计划时长")
    expectEqual(transitions.first?.spentSeconds, 1500, "事件带实际时长")
    expectEqual(transitions.first?.isCustom, false, "普通专注不算自定义")
}

func testTransitionSpentCapsOnSleep() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var transition: PhaseTransition?
    engine.onPhaseTransition = { transition = $0 }

    engine.start()
    clock.advance(7200)   // 睡眠两小时才回来
    engine.tick()

    expectEqual(transition?.plannedSeconds, 1500, "计划时长不变")
    expectEqual(transition?.spentSeconds, 1500, "实际时长封顶到计划时长")
}

func testLongBreakAfterConfiguredSessions() {
    let clock = TestClock()
    let durations = Durations(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 20, sessionsPerLongBreak: 2)
    let engine = makeEngine(durations, clock: clock)

    engine.start()
    clock.advance(1500)
    engine.tick()
    expectEqual(engine.snapshot.nextPhase, .shortBreak, "第 1 轮后短休")

    engine.start()
    clock.advance(300)
    engine.tick()
    expectEqual(engine.snapshot.nextPhase, .focus, "短休后回到专注")

    engine.start()
    clock.advance(1500)
    engine.tick()
    expectEqual(engine.snapshot.nextPhase, .longBreak, "第 2 轮后长休")

    engine.start()
    expectEqual(engine.snapshot.phase, .longBreak, "start 进入长休")
    expectEqual(engine.snapshot.total, 1200, "长休 20 分钟")
}

func testAutoStartNext() {
    let clock = TestClock()
    let engine = makeEngine(autoStartNext: true, clock: clock)
    var transitions: [PhaseTransition] = []
    engine.onPhaseTransition = { transitions.append($0) }

    engine.start()
    clock.advance(1500)
    engine.tick()

    expectEqual(engine.snapshot.phase, .shortBreak, "自动进入短休")
    expectEqual(engine.snapshot.isRunning, true, "自动开始时在运行")
    expectEqual(transitions.first?.to, .shortBreak, "事件 to = shortBreak")
}

func testStartFromFinishedIdle() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.start()
    clock.advance(1500)
    engine.tick()
    engine.start()
    expectEqual(engine.snapshot.phase, .shortBreak, "从 finished idle 启动短休")
    expectEqual(engine.snapshot.isFinished, false, "重新开始后 isFinished = false")
}

func testPauseResume() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.start()
    clock.advance(60)
    engine.pause()

    expectEqual(engine.snapshot.isPaused, true, "暂停中")
    expectEqual(engine.snapshot.isRunning, false, "暂停时不运行")
    expectClose(engine.snapshot.remaining, 1440, "暂停保留剩余")

    clock.advance(7200)
    engine.resume()
    expectEqual(engine.snapshot.isPaused, false, "恢复后不在暂停")
    expectEqual(engine.snapshot.phase, .focus, "恢复后仍是专注")
    engine.tick()
    expectClose(engine.snapshot.remaining, 1440, "长时间挂起后恢复不跳阶段")

    clock.advance(100)
    engine.tick()
    expectClose(engine.snapshot.remaining, 1340, "恢复后正常倒计时")
}

func testSleepWhileRunningFiresOnce() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var completed = 0
    engine.onPhaseTransition = { transition in
        if transition.reason == .completed { completed += 1 }
    }

    engine.start()
    clock.advance(7200)
    engine.tick()
    engine.tick()
    engine.tick()

    expectEqual(completed, 1, "跨睡眠只触发一次完成")
    expectEqual(engine.snapshot.phase, .idle, "补时后停在 idle")
}

func testSkip() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var transitions: [PhaseTransition] = []
    engine.onPhaseTransition = { transitions.append($0) }

    engine.start()
    clock.advance(600)
    engine.skip()

    expectEqual(engine.snapshot.completedFocusSessions, 0, "skip 不计入完成轮次")
    expectEqual(engine.snapshot.nextPhase, .shortBreak, "skip 后准备短休")
    expectEqual(transitions.first?.reason, .skipped, "事件原因是跳过")
}

func testReset() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.start()
    clock.advance(1500)
    engine.tick()
    engine.reset()

    expectEqual(engine.snapshot.phase, .idle, "reset 回 idle")
    expectEqual(engine.snapshot.completedFocusSessions, 0, "reset 清零轮次")
    expectEqual(engine.snapshot.remaining, 1500, "reset 恢复专注时长")
    expectEqual(engine.snapshot.nextPhase, nil, "reset 清空下一阶段")
    expectEqual(engine.snapshot.isFinished, false, "reset 清除 finished")
}

func testCustomCountdown() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)

    engine.startCustom(minutes: 3)
    expectEqual(engine.snapshot.phase, .focus, "自定义从专注开始")
    expectEqual(engine.snapshot.total, 180, "自定义 3 分钟 = 180s")
    expectEqual(engine.snapshot.isCustom, true, "标记为自定义")

    clock.advance(180)
    engine.tick()
    expectEqual(engine.snapshot.phase, .idle, "自定义结束回 idle")
    expectEqual(engine.snapshot.nextPhase, .focus, "自定义结束后准备普通专注")
    expectEqual(engine.snapshot.completedFocusSessions, 0, "自定义不计入轮次")
}

func testInvalidCustomIgnored() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.startCustom(minutes: 0)
    expectEqual(engine.snapshot.phase, .idle, "0 分钟被忽略")
    engine.startCustom(minutes: 181)
    expectEqual(engine.snapshot.phase, .idle, "181 分钟被忽略")
}

func testUpdateDurations() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    engine.updateDurations(Durations(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, sessionsPerLongBreak: 3))
    expectEqual(engine.snapshot.remaining, 3000, "空闲时改时长立即反映")
    engine.start()
    engine.updateDurations(Durations(focusMinutes: 30, shortBreakMinutes: 5, longBreakMinutes: 20, sessionsPerLongBreak: 3))
    expectEqual(engine.snapshot.total, 3000, "运行中改时长不影响当前阶段")
}

// MARK: - Task 8：非法设置不得把引擎带崩

func testEngineClampsIllegalDurations() {
    let clock = TestClock()
    let engine = makeEngine(
        Durations(focusMinutes: 0, shortBreakMinutes: 5, longBreakMinutes: 20, sessionsPerLongBreak: 0),
        clock: clock
    )
    expectEqual(engine.snapshot.total, 60, "0 分钟被夹到 1 分钟")

    engine.start()
    clock.advance(60)
    engine.tick()
    expectEqual(engine.snapshot.nextPhase, .shortBreak, "轮次 0 被夹到 2，首轮后仍是短休")
    expectEqual(engine.snapshot.completedFocusSessions, 1, "首轮正常计入")
}

// MARK: - Task 9：会话口径

func testSkipWhilePausedCountsSittingTimeOnly() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var transition: PhaseTransition?
    engine.onPhaseTransition = { transition = $0 }

    engine.start()
    clock.advance(60)
    engine.pause()
    clock.advance(600)      // 暂停后挂机 10 分钟
    engine.skip()

    expectEqual(transition?.spentSeconds, 60, "暂停时间不算坐着的时长")
    expectEqual(transition?.reason, .skipped, "记为跳过")
}

func testStartCustomClosesRunningPhase() {
    let clock = TestClock()
    let engine = makeEngine(clock: clock)
    var transitions: [PhaseTransition] = []
    engine.onPhaseTransition = { transitions.append($0) }

    engine.start()
    clock.advance(300)
    engine.startCustom(minutes: 5)

    expectEqual(transitions.count, 1, "换自定义前先把当前阶段收掉")
    expectEqual(transitions.first?.reason, .skipped, "记为中断，不静默丢弃")
    expectEqual(transitions.first?.spentSeconds, 300, "带实际坐了 5 分钟")
    expectEqual(engine.snapshot.isCustom, true, "进入自定义倒计时")
    expectEqual(engine.snapshot.total, 300, "自定义 5 分钟")
    expectEqual(engine.snapshot.phase, .focus, "自定义从专注开始")
}

// MARK: - Task 3

func makeTempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("timeflip-tests-\(UUID().uuidString)", isDirectory: true)
}

func testDefaultSettings() {
    let settings = TimeFlipSettings()
    expectEqual(settings.appearance.style, .flip, "默认卡片样式")
    expectEqual(settings.appearance.fontSize, 96, "默认字号")
    expectEqual(settings.behavior.form, .floating, "默认浮动形态")
    expectEqual(settings.behavior.layer, .desktop, "默认贴桌面")
    expectEqual(settings.behavior.showMode, .auto, "默认显示模式 auto")
    expectEqual(settings.menuBar.style, .iconAndTime, "默认菜单栏样式")
    expectEqual(settings.timer.soundName, "Glass", "默认提示音")
    expectEqual(settings.timer.durations.focusMinutes, 25, "默认专注 25 分钟")
    expectEqual(settings.timer.hotKey, .default, "默认快捷键")
}

func testColorHex() {
    let color = RGBAColor(hex: "#1A1A1A")
    expect(color != nil, "解析 #1A1A1A")
    expectEqual(color?.hexString, "#1A1A1A", "hex 往返一致")
    expect(RGBAColor(hex: "zzz") == nil, "非法 hex 返回 nil")
    expectEqual(RGBAColor(hex: "#FFFFFF", alpha: 0.9)?.alpha, 0.9, "alpha 生效")
    expect(RGBAColor(hex: "1A1A1A") != nil, "允许不带 #")
}

func testSettingsRoundTrip() {
    let dir = makeTempDir()
    let store = SettingsStore(directory: dir)
    _ = try? store.update { settings in
        settings.appearance.fontSize = 120
        settings.behavior.layer = .floating
        settings.windowPlacements["SCREEN-A"] = WindowOrigin(x: 10, y: 20)
    }

    let reloaded = SettingsStore(directory: dir)
    reloaded.load()
    expectEqual(reloaded.settings.appearance.fontSize, 120, "字号往返")
    expectEqual(reloaded.settings.behavior.layer, .floating, "层级往返")
    expectEqual(reloaded.settings.windowPlacements["SCREEN-A"], WindowOrigin(x: 10, y: 20), "窗口位置往返")
}

func testMissingSectionsFallback() {
    let dir = makeTempDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"version":1,"appearance":{"style":"digital","fontSize":140}}"#
    try? Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))

    let store = SettingsStore(directory: dir)
    store.load()
    expectEqual(store.settings.appearance.style, .digital, "保留已有字段")
    expectEqual(store.settings.appearance.fontSize, 140, "保留已有数值")
    expectEqual(store.settings.appearance.textColor, ClockAppearance().textColor, "缺失字段用默认值")
    expectEqual(store.settings.appearance.material, .paper, "新增材质字段缺失时用默认值")
    expectEqual(store.settings.lock.style, .off, "新增锁屏段缺失时默认关闭")
    expectEqual(store.settings.behavior.form, .floating, "缺失 section 用默认值")
    expectEqual(store.settings.menuBar.style, .iconAndTime, "缺失 section 用默认值")
}

func testDurationsClampedOnDecode() {
    let json = #"{"focusMinutes":0,"shortBreakMinutes":999,"longBreakMinutes":-5,"sessionsPerLongBreak":0}"#
    let decoded = try? JSONDecoder().decode(Durations.self, from: Data(json.utf8))
    expectEqual(decoded?.focusMinutes, 1, "专注时长下限夹到 1")
    expectEqual(decoded?.shortBreakMinutes, 180, "短休上限夹到 180")
    expectEqual(decoded?.longBreakMinutes, 1, "长休下限夹到 1")
    expectEqual(decoded?.sessionsPerLongBreak, 2, "轮次下限夹到 2")
}

func testPartialSectionKeepsSiblings() {
    let dir = makeTempDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"""
    {"version":1,
     "timer":{"autoStartNext":true,"soundName":"Ping","durations":{"focusMinutes":50}},
     "menuBar":{"style":"timeOnly"},
     "behavior":{"form":"fullScreen"},
     "windowPlacements":{"SCREEN-A":{"x":12}}}
    """#
    try? Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))

    let store = SettingsStore(directory: dir)
    store.load()

    expectEqual(store.settings.timer.durations.focusMinutes, 50, "已有字段保留")
    expectEqual(store.settings.timer.durations.shortBreakMinutes, 5, "段内缺失字段用默认值")
    expectEqual(store.settings.timer.durations.sessionsPerLongBreak, 4, "段内缺失字段用默认值")
    expectEqual(store.settings.timer.autoStartNext, true, "同段兄弟字段不被拖累")
    expectEqual(store.settings.timer.soundName, "Ping", "提示音保留")
    expectEqual(store.settings.timer.hotKey, .default, "缺失的快捷键用默认值")
    expectEqual(store.settings.menuBar.style, .timeOnly, "菜单栏样式保留")
    expectEqual(store.settings.menuBar.showProgressRing, true, "缺失字段用默认值")
    expectEqual(store.settings.behavior.form, .fullScreen, "形态保留")
    expectEqual(store.settings.behavior.layer, .desktop, "缺失字段用默认值")
    expectEqual(store.settings.windowPlacements["SCREEN-A"]?.x, 12, "半个窗口位置也能解出来")
    expectEqual(store.settings.windowPlacements["SCREEN-A"]?.y, 0, "缺失坐标回 0")
}

func testNilSoundNameSurvivesReload() {
    let dir = makeTempDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = #"{"timer":{"soundName":null}}"#
    try? Data(json.utf8).write(to: dir.appendingPathComponent("settings.json"))

    let store = SettingsStore(directory: dir)
    store.load()
    expectEqual(store.settings.timer.soundName, nil, "选了「无」要能读回 nil，不能被默认值顶掉")
}

func testCorruptSettingsFallback() {
    let dir = makeTempDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? Data("not json".utf8).write(to: dir.appendingPathComponent("settings.json"))

    let store = SettingsStore(directory: dir)
    store.load()
    expectEqual(store.settings.appearance.style, .flip, "损坏回默认值")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    expect(files.contains { $0.hasPrefix("settings.broken-") }, "损坏文件已备份")
}

// MARK: - Task 4

func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    let calendar = utcCalendar()
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) ?? Date()
}

func testCountdownFormats() {
    expectEqual(TimeStrings.countdown(seconds: 1499), "24:59", "1499 → 24:59")
    expectEqual(TimeStrings.countdown(seconds: 0), "00:00", "0 → 00:00")
    expectEqual(TimeStrings.countdown(seconds: 3661), "1:01:01", "3661 → 1:01:01")
    expectEqual(TimeStrings.countdown(seconds: -5), "00:00", "负数夹到 0")
}

func testClockFormats() {
    let calendar = utcCalendar()
    let date = utcDate(2026, 11, 9, 19, 28, 5)
    expectEqual(TimeStrings.clock(date: date, use24Hour: true, showSeconds: true, calendar: calendar), "19:28:05", "24 小时带秒")
    expectEqual(TimeStrings.clock(date: date, use24Hour: true, showSeconds: false, calendar: calendar), "19:28", "24 小时不带秒")
    expectEqual(TimeStrings.clock(date: date, use24Hour: false, showSeconds: true, calendar: calendar), "07:28:05 PM", "12 小时带秒")
    expectEqual(TimeStrings.clock(date: date, use24Hour: false, showSeconds: false, calendar: calendar), "07:28 PM", "12 小时不带秒")
}

func testDateAndBottomLine() {
    let calendar = utcCalendar()
    let date = utcDate(2026, 11, 9, 19, 28, 5)

    let line = TimeStrings.dateLine(date: date, calendar: calendar)
    expectEqual(line.left, "Nov 09 2026", "日期行左侧")
    expectEqual(line.right, "Mon", "日期行右侧是星期")

    let idleLine = TimeStrings.bottomLine(date: date, completedSessions: 0, perLongBreak: 4, calendar: calendar)
    expect(idleLine.hasPrefix("Week "), "空闲时显示周数")
    expect(idleLine.contains("Day 9"), "空闲时显示日期")

    expectEqual(TimeStrings.bottomLine(date: date, completedSessions: 2, perLongBreak: 4, calendar: calendar), "Focus 2/4", "中途显示进度")
    expectEqual(TimeStrings.bottomLine(date: date, completedSessions: 4, perLongBreak: 4, calendar: calendar), "Focus 4/4", "满轮显示满进度")
}

func testClockLayout() {
    let width = ClockLayout.digitWidth(containerWidth: 1000, slots: 6, colons: 2)
    expect(width > 0, "宽度为正")
    expect(width < 1000.0 / 6.0, "留出冒号与缝隙")
    expect(ClockLayout.digitWidth(containerWidth: 100, slots: 6, colons: 2) > 0, "小容器仍为正")
    expect(ClockLayout.digitWidth(containerWidth: 2000, slots: 6, colons: 2) > width, "宽度单调递增")
    expectEqual(ClockLayout.digitWidth(containerWidth: 0, slots: 6, colons: 2), 0, "零宽度返回 0")
}

// MARK: - Task 5：主题

func testThemePresets() {
    let presets = ThemePreset.all
    expectEqual(presets.count, 8, "共 8 套预设")
    expectEqual(Set(presets.map(\.id)).count, 8, "预设 id 唯一")
    expectEqual(Set(presets.map(\.name)).count, 8, "预设名不重复")

    for preset in presets {
        let appearance = preset.appearance
        expect((12...400).contains(appearance.fontSize), "\(preset.id) 字号合法")
        expect((0...1).contains(appearance.backgroundOpacity), "\(preset.id) 不透明度合法")
        expect((0...40).contains(appearance.shadowRadius), "\(preset.id) 投影半径合法")
        expect((0...1).contains(appearance.shadowOpacity), "\(preset.id) 投影透明度合法")
        expect(appearance.fontFamily.isEmpty == false, "\(preset.id) 有字体")
    }

    expectEqual(ThemePreset.preset(id: "cream")?.name, "奶油白", "按 id 取预设")
    expect(ThemePreset.preset(id: "不存在") == nil, "未知 id 返回 nil")
}

func testThemeApplyKeepsFontSize() {
    var current = ClockAppearance()
    current.fontSize = 233
    let applied = ThemePreset.all[1].applied(to: current)
    expectEqual(applied.fontSize, 233, "套用预设保留用户字号")
    expectEqual(applied.themeID, ThemePreset.all[1].id, "套用后记录 preset id")
    expectEqual(applied.style, ThemePreset.all[1].appearance.style, "套用后样式来自预设")
}

func testThemeDocumentRoundTrip() {
    var appearance = ClockAppearance()
    appearance.fontSize = 128
    appearance.material = .metal
    let document = ThemeDocument(name: "我的霓虹", appearance: appearance)

    guard let text = document.encoded() else {
        expect(false, "主题编码成功")
        return
    }
    expect(!text.contains("\n"), "编码结果是单行")

    let decoded = ThemeDocument.decode(text)
    expectEqual(decoded?.name, "我的霓虹", "名称往返")
    expectEqual(decoded?.appearance.fontSize, 128, "字号往返")
    expectEqual(decoded?.appearance.material, .metal, "材质往返")
}

func testThemeDocumentTolerance() {
    var appearance = ClockAppearance()
    appearance.fontSize = 9999
    appearance.backgroundOpacity = -3
    let text = "这是我的主题，复制这段就行："
        + (ThemeDocument(name: "   ", appearance: appearance).encoded() ?? "")
        + " 谢谢！"

    let decoded = ThemeDocument.decode(text)
    expect(decoded != nil, "容忍前后噪音")
    expectEqual(decoded?.appearance.fontSize, 400, "越界字号被夹回")
    expectEqual(decoded?.appearance.backgroundOpacity, 0, "越界不透明度被夹回")
    expectEqual(decoded?.name, "自定义主题", "空名称兜底")
    expect(ThemeDocument.decode("") == nil, "空串返回 nil")
    expect(ThemeDocument.decode("hello world") == nil, "非 JSON 返回 nil")
}

// MARK: - Task 6：会话与统计

func makesStatsCalendar() -> Calendar { utcCalendar() }

func statsRecord(
    calendar: Calendar,
    daysAgo: Int,
    hour: Int,
    completed: Bool = true,
    seconds: Int = 1500
) -> SessionRecord {
    let base = utcDate(2026, 11, 12, hour, 0, 0)
    let start = calendar.date(byAdding: .day, value: -daysAgo, to: base) ?? base
    return SessionRecord(
        startedAt: start,
        endedAt: start.addingTimeInterval(Double(seconds)),
        plannedSeconds: 1500,
        actualSeconds: seconds,
        completed: completed
    )
}

func testSessionRecordFromTransition() {
    let now = utcDate(2026, 11, 12, 15, 0, 0)
    let completed = PhaseTransition(
        from: .focus,
        to: .shortBreak,
        reason: .completed,
        plannedSeconds: 1500,
        spentSeconds: 1500,
        isCustom: false
    )
    let record = SessionRecord.make(transition: completed, now: now)
    expectEqual(record.phase, .focus, "只记专注阶段")
    expectEqual(record.completed, true, "完成记 true")
    expectEqual(record.plannedSeconds, 1500, "计划时长进账本")
    expectEqual(record.actualSeconds, 1500, "实际时长进账本")
    expectEqual(record.endedAt, now, "结束时间取事件时刻")
    expectEqual(record.startedAt, now.addingTimeInterval(-1500), "开始时间由实际时长反推")

    let skipped = PhaseTransition(
        from: .focus,
        to: .shortBreak,
        reason: .skipped,
        plannedSeconds: 1500,
        spentSeconds: 420,
        isCustom: false
    )
    let interrupted = SessionRecord.make(transition: skipped, now: now)
    expectEqual(interrupted.completed, false, "跳过记 false")
    expectEqual(interrupted.actualSeconds, 420, "跳过记录实际坐了多久")
}

func testSessionLogRoundTrip() {
    let dir = makeTempDir()
    let log = SessionLog(directory: dir)
    let calendar = utcCalendar()
    log.append(statsRecord(calendar: calendar, daysAgo: 0, hour: 9))
    log.append(statsRecord(calendar: calendar, daysAgo: 0, hour: 10, completed: false, seconds: 600))
    log.save()

    let reloaded = SessionLog(directory: dir)
    reloaded.load()
    expectEqual(reloaded.records.count, 2, "会话写入后能读回")
    expectEqual(reloaded.records.first?.actualSeconds, 1500, "按开始时间排序")
}

func testSessionLogCorruptFallback() {
    let dir = makeTempDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? Data("not json".utf8).write(to: dir.appendingPathComponent("sessions.json"))

    let log = SessionLog(directory: dir)
    log.load()
    expectEqual(log.records.count, 0, "损坏文件回退空表")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    expect(files.contains { $0.hasPrefix("sessions.broken-") }, "损坏文件已备份")
}

func testSessionLogPrune() {
    let dir = makeTempDir()
    let log = SessionLog(directory: dir)
    let calendar = utcCalendar()
    let now = utcDate(2026, 11, 12, 15, 0, 0)
    log.append(statsRecord(calendar: calendar, daysAgo: 0, hour: 9))
    log.append(statsRecord(calendar: calendar, daysAgo: 400, hour: 9))
    log.prune(keepingDays: 365, now: now, calendar: calendar)
    expectEqual(log.records.count, 1, "超过 365 天的记录被裁掉")
}

func testFocusStatsToday() {
    let calendar = makesStatsCalendar()
    let now = utcDate(2026, 11, 12, 15, 0, 0)
    var records = [
        statsRecord(calendar: calendar, daysAgo: 0, hour: 9),
        statsRecord(calendar: calendar, daysAgo: 0, hour: 10),
        statsRecord(calendar: calendar, daysAgo: 1, hour: 9),
        statsRecord(calendar: calendar, daysAgo: 2, hour: 9),
        statsRecord(calendar: calendar, daysAgo: 2, hour: 14, completed: false, seconds: 300)
    ]
    // 休息阶段不参与统计
    records.append(
        SessionRecord(
            startedAt: utcDate(2026, 11, 12, 11, 0, 0),
            endedAt: utcDate(2026, 11, 12, 11, 5, 0),
            phase: .shortBreak,
            plannedSeconds: 300,
            actualSeconds: 300,
            completed: true
        )
    )

    let stats = FocusStats.make(records: records, goal: 4, now: now, calendar: calendar)
    expectEqual(stats.todaySessions, 2, "今日完成 2 轮")
    expectEqual(stats.todayFocusSeconds, 3000, "今日专注 50 分钟")
    expectEqual(stats.streakDays, 3, "连续 3 天")
    expectEqual(stats.completedCount, 4, "只统计专注阶段")
    expectEqual(stats.interruptedCount, 1, "中断 1 次")
    expectCloseDouble(stats.interruptionRate, 0.2, "中断率 20%")
    expectEqual(stats.bestHour, 9, "最佳时段是 9 点")
    expectEqual(stats.last14Days.count, 14, "14 天柱状")
    expectEqual(stats.last14Days.last?.sessions, 2, "最后一格是今天")
    expectEqual(stats.goalReached, false, "2/4 未达成")
    expectCloseDouble(stats.goalProgress, 0.5, "目标进度 50%")
}

func testFocusStatsStreakFromYesterday() {
    let calendar = makesStatsCalendar()
    let now = utcDate(2026, 11, 12, 8, 0, 0)
    let records = [
        statsRecord(calendar: calendar, daysAgo: 1, hour: 9),
        statsRecord(calendar: calendar, daysAgo: 2, hour: 9)
    ]
    let stats = FocusStats.make(records: records, goal: 4, now: now, calendar: calendar)
    expectEqual(stats.streakDays, 2, "今天还没专注时从昨天起算")
    expectEqual(stats.todaySessions, 0, "今日 0 轮")
}

func testFocusStatsEmpty() {
    let calendar = makesStatsCalendar()
    let stats = FocusStats.make(
        records: [],
        goal: 4,
        now: utcDate(2026, 11, 12, 15, 0, 0),
        calendar: calendar
    )
    expectEqual(stats.streakDays, 0, "空账本连续 0 天")
    expectEqual(stats.interruptionRate, 0, "空账本中断率 0")
    expectEqual(stats.bestHour, nil, "空账本没有最佳时段")
}

func testStatsFormatting() {
    expectEqual(StatsFormatting.duration(seconds: 45 * 60), "45 分钟", "不足一小时")
    expectEqual(StatsFormatting.duration(seconds: 3 * 3600 + 12 * 60), "3 小时 12 分", "小时+分钟")
    expectEqual(StatsFormatting.compactDuration(seconds: 3 * 3600 + 12 * 60), "3h12m", "紧凑格式")
    expectEqual(StatsFormatting.compactDuration(seconds: 42 * 60), "42m", "紧凑分钟")
}

func testFocusStatsCustomExcludedFromCycles() {
    let calendar = utcCalendar()
    let now = utcDate(2026, 11, 12, 15, 0, 0)
    let custom = SessionRecord(
        startedAt: utcDate(2026, 11, 12, 10, 0, 0),
        endedAt: utcDate(2026, 11, 12, 10, 5, 0),
        plannedSeconds: 300,
        actualSeconds: 300,
        completed: true,
        isCustom: true
    )
    let records = [statsRecord(calendar: calendar, daysAgo: 0, hour: 9), custom]

    let stats = FocusStats.make(records: records, goal: 4, now: now, calendar: calendar)
    expectEqual(stats.todaySessions, 1, "自定义倒计时不计入轮次")
    expectEqual(stats.todayFocusSeconds, 1800, "自定义时长仍算专注时长")
    expectEqual(stats.completedCount, 1, "累计完成只数番茄轮")
    expectEqual(stats.streakDays, 1, "自定义不刷连续天数")
    expectEqual(stats.last14Days.last?.sessions, 1, "柱状图轮次不含自定义")
    expectEqual(stats.last14Days.last?.focusSeconds, 1800, "柱状图时长含自定义")
    expectEqual(stats.goalProgress, 0.25, "目标进度只算轮次")
}

// MARK: - Task 7：锁屏策略

func testLockPolicyFocus() {
    var settings = LockSettings()
    settings.style = .displaySleep
    settings.graceSeconds = 10

    let action = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: false
    )
    expectEqual(action.lock, .displaySleep, "专注结束后锁屏")
    expectEqual(action.delaySeconds, 10, "宽限 10 秒")
    expect(action.overlay, "仍然铺休息遮罩")
}

func testLockPolicyOff() {
    let settings = LockSettings()
    let action = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: false
    )
    expectEqual(action.lock, nil, "关闭时不锁屏")
    expectEqual(action.delaySeconds, 0, "关闭时无延迟")
}

func testLockPolicyBreakNeverLocks() {
    var settings = LockSettings()
    settings.style = .lock
    let action = LockPolicy.action(
        settings: settings,
        finishedPhase: .shortBreak,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: false
    )
    expectEqual(action.lock, nil, "休息结束不锁屏")
    expect(action.overlay, "休息结束仍提示")
}

func testLockPolicySleepNeverLocks() {
    var settings = LockSettings()
    settings.style = .lock
    let action = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: true,
        hasFullScreenApp: false
    )
    expectEqual(action.lock, nil, "睡眠唤醒后不锁屏")
}

func testLockPolicyFullScreenSkips() {
    var settings = LockSettings()
    settings.style = .lock
    let skip = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: true
    )
    expectEqual(skip.lock, nil, "全屏应用下不锁屏")

    settings.skipWhenFullScreenApp = false
    let force = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: true
    )
    expectEqual(force.lock, .lock, "关掉保护后全屏也锁")
}

func testLockPolicyCustomNeverLocks() {
    var settings = LockSettings()
    settings.style = .lock
    let action = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: true,
        wokeFromSleep: false,
        hasFullScreenApp: false
    )
    expectEqual(action.lock, nil, "自定义倒计时不锁屏")
}

func testLockPolicyGraceClamped() {
    let json = #"{"style":"lock","graceSeconds":999,"overlayEnabled":true,"skipWhenFullScreenApp":true}"#
    let decoded = try? JSONDecoder().decode(LockSettings.self, from: Data(json.utf8))
    expectEqual(decoded?.graceSeconds, 60, "宽限秒数夹到 60")

    var settings = LockSettings()
    settings.style = .lock
    settings.graceSeconds = 0
    let immediate = LockPolicy.action(
        settings: settings,
        finishedPhase: .focus,
        isCustom: false,
        wokeFromSleep: false,
        hasFullScreenApp: false
    )
    expectEqual(immediate.delaySeconds, 0, "0 秒表示立即")
    expectEqual(immediate.lock, .lock, "立即锁屏")
}

// MARK: - Runner

let tests: [(String, () -> Void)] = [
    ("初始状态", testInitialState),
    ("开始专注", testStartFocus),
    ("专注完成进入短休", testFocusCompletesToShortBreak),
    ("睡眠补时封顶实际时长", testTransitionSpentCapsOnSleep),
    ("轮次到点进入长休", testLongBreakAfterConfiguredSessions),
    ("自动接续", testAutoStartNext),
    ("从结束态启动下一阶段", testStartFromFinishedIdle),
    ("暂停恢复", testPauseResume),
    ("睡眠补时只触发一次", testSleepWhileRunningFiresOnce),
    ("跳过", testSkip),
    ("重置", testReset),
    ("自定义倒计时", testCustomCountdown),
    ("非法自定义被忽略", testInvalidCustomIgnored),
    ("更新时长", testUpdateDurations),
    ("非法时长被夹取", testEngineClampsIllegalDurations),
    ("暂停后跳过只算坐着时长", testSkipWhilePausedCountsSittingTimeOnly),
    ("换自定义先收掉当前阶段", testStartCustomClosesRunningPhase),
    ("默认设置", testDefaultSettings),
    ("颜色 hex 解析", testColorHex),
    ("设置往返", testSettingsRoundTrip),
    ("缺失段兜底", testMissingSectionsFallback),
    ("时长越界夹取", testDurationsClampedOnDecode),
    ("段内字段缺失兜底", testPartialSectionKeepsSiblings),
    ("无提示音往返", testNilSoundNameSurvivesReload),
    ("损坏文件兜底", testCorruptSettingsFallback),
    ("倒计时文案", testCountdownFormats),
    ("时钟文案", testClockFormats),
    ("日期与底行", testDateAndBottomLine),
    ("字号反算", testClockLayout),
    ("八套预设", testThemePresets),
    ("套用预设保留字号", testThemeApplyKeepsFontSize),
    ("主题 JSON 往返", testThemeDocumentRoundTrip),
    ("主题 JSON 容错", testThemeDocumentTolerance),
    ("会话记录由事件生成", testSessionRecordFromTransition),
    ("会话账本往返", testSessionLogRoundTrip),
    ("会话损坏兜底", testSessionLogCorruptFallback),
    ("会话裁剪", testSessionLogPrune),
    ("今日统计", testFocusStatsToday),
    ("连续天数", testFocusStatsStreakFromYesterday),
    ("空账本", testFocusStatsEmpty),
    ("统计文案", testStatsFormatting),
    ("自定义不计入轮次", testFocusStatsCustomExcludedFromCycles),
    ("锁屏：专注完成", testLockPolicyFocus),
    ("锁屏：关闭", testLockPolicyOff),
    ("锁屏：休息不锁", testLockPolicyBreakNeverLocks),
    ("锁屏：睡眠不锁", testLockPolicySleepNeverLocks),
    ("锁屏：全屏跳过", testLockPolicyFullScreenSkips),
    ("锁屏：自定义不锁", testLockPolicyCustomNeverLocks),
    ("锁屏：宽限夹取", testLockPolicyGraceClamped),
]

for (name, body) in tests {
    let before = failureCount
    body()
    print(failureCount == before ? "PASS  \(name)" : "FAIL  \(name)")
}

print("----")
if failureCount == 0 {
    print("ALL \(checkCount) CHECKS PASSED")
} else {
    print("\(failureCount) OF \(checkCount) CHECKS FAILED")
}
exit(failureCount == 0 ? 0 : 1)
