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

    public func minutes(for phase: TimerPhase) -> Int {
        switch phase {
        case .focus, .idle: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        case .longBreak: return longBreakMinutes
        }
    }

    public var isValid: Bool {
        (1...180).contains(focusMinutes)
            && (1...180).contains(shortBreakMinutes)
            && (1...180).contains(longBreakMinutes)
            && (2...8).contains(sessionsPerLongBreak)
    }
}
