import Foundation

public enum TimerPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case focus
    case shortBreak
    case longBreak

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
    public var isFocus: Bool { self == .focus }
}

public struct Durations: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var sessionsPerLongBreak: Int

    public init(
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 20,
        sessionsPerLongBreak: Int = 4
    ) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.sessionsPerLongBreak = sessionsPerLongBreak
    }

    public static let standard = Durations()

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, sessionsPerLongBreak
    }

    /// 缺失字段逐个回退，越界数值直接夹回合法区间：
    /// settings.json 是用户能手改的文件，一个 0 轮就会让状态机除零崩掉。
    public init(from decoder: Decoder) throws {
        let fallback = Durations.standard
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallbackValue: Int) -> Int {
            (try? container.decode(Int.self, forKey: key)) ?? fallbackValue
        }
        let parsed = Durations(
            focusMinutes: value(.focusMinutes, fallback.focusMinutes),
            shortBreakMinutes: value(.shortBreakMinutes, fallback.shortBreakMinutes),
            longBreakMinutes: value(.longBreakMinutes, fallback.longBreakMinutes),
            sessionsPerLongBreak: value(.sessionsPerLongBreak, fallback.sessionsPerLongBreak)
        )
        self = parsed.clamped()
    }

    public func minutes(for phase: TimerPhase) -> Int {
        switch phase {
        case .focus, .idle: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        case .longBreak: return longBreakMinutes
        }
    }

    /// 夹回界面允许的区间（分钟 1…180、轮次 2…8）。
    public func clamped() -> Durations {
        Durations(
            focusMinutes: min(180, max(1, focusMinutes)),
            shortBreakMinutes: min(180, max(1, shortBreakMinutes)),
            longBreakMinutes: min(180, max(1, longBreakMinutes)),
            sessionsPerLongBreak: min(8, max(2, sessionsPerLongBreak))
        )
    }
}
