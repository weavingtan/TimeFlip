import Foundation

struct ClockRenderModel: Equatable {
    struct DateLine: Equatable {
        var left: String
        var right: String
    }

    var characters: [Character]
    var dateLine: DateLine?
    var bottomLine: String?
    var appearance: ClockAppearance
    var metrics: ClockMetrics
    var colonVisible: Bool
    var isFinished: Bool

    var slotCount: Int { characters.filter { $0 != ":" }.count }
    var colonCount: Int { characters.filter { $0 == ":" }.count }

    static func make(
        snapshot: TimerSnapshot,
        settings: TimeFlipSettings,
        metrics: ClockMetrics,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClockRenderModel {
        let appearance = settings.appearance
        let text = displayText(snapshot: snapshot, settings: settings, now: now, calendar: calendar)

        return ClockRenderModel(
            characters: Array(text),
            dateLine: appearance.showDate
                ? {
                    let line = TimeStrings.dateLine(date: now, calendar: calendar)
                    return DateLine(left: line.left, right: line.right)
                }()
                : nil,
            bottomLine: appearance.showBottomLine
                ? TimeStrings.bottomLine(
                    date: now,
                    completedSessions: snapshot.completedFocusSessions,
                    perLongBreak: settings.timer.durations.sessionsPerLongBreak,
                    calendar: calendar
                )
                : nil,
            appearance: appearance,
            metrics: metrics,
            colonVisible: Int(now.timeIntervalSince1970) % 2 == 0,
            isFinished: snapshot.isFinished
        )
    }

    static func displayText(
        snapshot: TimerSnapshot,
        settings: TimeFlipSettings,
        now: Date,
        calendar: Calendar
    ) -> String {
        let appearance = settings.appearance

        switch settings.behavior.showMode {
        case .clockOnly:
            return clockText(now: now, appearance: appearance, calendar: calendar)
        case .countdownOnly:
            return countdownText(snapshot)
        case .auto:
            if snapshot.phase == .idle {
                return clockText(now: now, appearance: appearance, calendar: calendar)
            }
            return countdownText(snapshot)
        }
    }

    private static func countdownText(_ snapshot: TimerSnapshot) -> String {
        TimeStrings.countdown(seconds: snapshot.displaySeconds)
    }

    private static func clockText(now: Date, appearance: ClockAppearance, calendar: Calendar) -> String {
        var text = TimeStrings.clock(
            date: now,
            use24Hour: appearance.use24Hour,
            showSeconds: appearance.showSeconds,
            calendar: calendar
        )
        if !appearance.showLeadingZero, text.hasPrefix("0"), text.count > 5 {
            text.removeFirst()
        }
        return text
    }
}
