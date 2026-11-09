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
    expectEqual(store.settings.appearance.textColor, .ink, "缺失字段用默认值")
    expectEqual(store.settings.behavior.form, .floating, "缺失 section 用默认值")
    expectEqual(store.settings.menuBar.style, .iconAndTime, "缺失 section 用默认值")
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

// MARK: - Runner

let tests: [(String, () -> Void)] = [
    ("初始状态", testInitialState),
    ("开始专注", testStartFocus),
    ("专注完成进入短休", testFocusCompletesToShortBreak),
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
    ("默认设置", testDefaultSettings),
    ("颜色 hex 解析", testColorHex),
    ("设置往返", testSettingsRoundTrip),
    ("缺失段兜底", testMissingSectionsFallback),
    ("损坏文件兜底", testCorruptSettingsFallback),
    ("倒计时文案", testCountdownFormats),
    ("时钟文案", testClockFormats),
    ("日期与底行", testDateAndBottomLine),
    ("字号反算", testClockLayout),
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
