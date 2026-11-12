import Foundation

/// 菜单栏弹窗与设置窗口共享的唯一可变状态源。
final class AppModel: ObservableObject {
    @Published var snapshot: TimerSnapshot
    @Published var settings: TimeFlipSettings
    @Published var clockVisible: Bool
    @Published var stats: FocusStats

    var toggle: () -> Void = {}
    var skip: () -> Void = {}
    var reset: () -> Void = {}
    var startCustom: (Int) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var setClockVisible: (Bool) -> Void = { _ in }
    var quit: () -> Void = {}
    var previewChime: (String?) -> Void = { _ in }
    var commitSettings: () -> Void = {}
    var revealSettings: () -> Void = {}

    var applyTheme: (String) -> Void = { _ in }
    var copyTheme: () -> Void = {}
    var importThemeFromClipboard: () -> Void = {}
    var exportThemeFile: () -> Void = {}
    var importThemeFile: () -> Void = {}
    var copyStatsImage: () -> Void = {}
    var saveStatsImage: () -> Void = {}
    var requestAccessibility: () -> Void = {}
    var confirmReset: () -> Void = {}

    init(snapshot: TimerSnapshot, settings: TimeFlipSettings, stats: FocusStats = .empty) {
        self.snapshot = snapshot
        self.settings = settings
        self.stats = stats
        self.clockVisible = settings.behavior.visible
    }
}
