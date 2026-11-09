import Foundation

/// 菜单栏弹窗与设置窗口共享的唯一可变状态源。
final class AppModel: ObservableObject {
    @Published var snapshot: TimerSnapshot
    @Published var settings: TimeFlipSettings
    @Published var clockVisible: Bool

    var toggle: () -> Void = {}
    var skip: () -> Void = {}
    var reset: () -> Void = {}
    var startPreset: (Int) -> Void = { _ in }
    var startCustom: (Int) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var setClockVisible: (Bool) -> Void = { _ in }
    var adjustPosition: () -> Void = {}
    var quit: () -> Void = {}
    var previewChime: (String?) -> Void = { _ in }
    var commitSettings: () -> Void = {}

    init(snapshot: TimerSnapshot, settings: TimeFlipSettings) {
        self.snapshot = snapshot
        self.settings = settings
        self.clockVisible = settings.behavior.visible
    }
}
