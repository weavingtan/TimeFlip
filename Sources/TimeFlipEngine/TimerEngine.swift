import Foundation

public struct PhaseTransition: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case completed
        case skipped
    }

    public let from: TimerPhase
    public let to: TimerPhase?
    public let reason: Reason

    public init(from: TimerPhase, to: TimerPhase?, reason: Reason) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}

public struct TimerSnapshot: Equatable, Sendable {
    public var phase: TimerPhase
    public var isRunning: Bool
    public var isPaused: Bool
    public var isFinished: Bool
    public var remaining: TimeInterval
    public var total: TimeInterval
    public var completedFocusSessions: Int
    public var nextPhase: TimerPhase?
    public var progress: Double
    public var isCustom: Bool

    public init(
        phase: TimerPhase,
        isRunning: Bool,
        isPaused: Bool,
        isFinished: Bool,
        remaining: TimeInterval,
        total: TimeInterval,
        completedFocusSessions: Int,
        nextPhase: TimerPhase?,
        progress: Double,
        isCustom: Bool
    ) {
        self.phase = phase
        self.isRunning = isRunning
        self.isPaused = isPaused
        self.isFinished = isFinished
        self.remaining = remaining
        self.total = total
        self.completedFocusSessions = completedFocusSessions
        self.nextPhase = nextPhase
        self.progress = progress
        self.isCustom = isCustom
    }

    public var displaySeconds: Int { max(0, Int(remaining.rounded(.up))) }
}

/// 纯逻辑计时状态机：只依赖注入的时钟，不持有 UI。
public final class TimerEngine {
    public private(set) var snapshot: TimerSnapshot
    public var onChange: ((TimerSnapshot) -> Void)?
    public var onPhaseTransition: ((PhaseTransition) -> Void)?
    public var autoStartNext: Bool

    private let now: () -> Date
    private var durations: Durations
    private var deadline: Date?
    private var pausedRemaining: TimeInterval?
    private var customMinutes: Int?
    private var completedFocusSessions = 0
    private var pendingNext: TimerPhase?

    public init(
        durations: Durations = .standard,
        autoStartNext: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.durations = durations
        self.autoStartNext = autoStartNext
        self.now = now
        let total = TimeInterval(durations.focusMinutes * 60)
        self.snapshot = TimerSnapshot(
            phase: .idle,
            isRunning: false,
            isPaused: false,
            isFinished: false,
            remaining: total,
            total: total,
            completedFocusSessions: 0,
            nextPhase: nil,
            progress: 0,
            isCustom: false
        )
    }

    // MARK: - 控制

    public func start() {
        if snapshot.isPaused {
            resume()
            return
        }
        guard snapshot.phase == .idle else { return }
        let next = pendingNext ?? .focus
        pendingNext = nil
        begin(next)
    }

    public func startCustom(minutes: Int) {
        guard (1...180).contains(minutes) else { return }
        customMinutes = minutes
        pendingNext = nil
        begin(.focus, overrideMinutes: minutes)
    }

    public func pause() {
        guard snapshot.phase != .idle, let deadline else { return }
        let remaining = max(0, deadline.timeIntervalSince(now()))
        pausedRemaining = remaining
        self.deadline = nil
        snapshot.isPaused = true
        snapshot.isRunning = false
        snapshot.remaining = remaining
        emit()
    }

    public func resume() {
        guard snapshot.isPaused, let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        deadline = now().addingTimeInterval(remaining)
        snapshot.isPaused = false
        snapshot.isRunning = true
        snapshot.remaining = remaining
        emit()
    }

    public func skip() {
        guard snapshot.phase != .idle else { return }
        finish(reason: .skipped)
    }

    public func reset() {
        deadline = nil
        pausedRemaining = nil
        customMinutes = nil
        pendingNext = nil
        completedFocusSessions = 0
        let total = TimeInterval(durations.focusMinutes * 60)
        snapshot = TimerSnapshot(
            phase: .idle,
            isRunning: false,
            isPaused: false,
            isFinished: false,
            remaining: total,
            total: total,
            completedFocusSessions: 0,
            nextPhase: nil,
            progress: 0,
            isCustom: false
        )
        emit()
    }

    public func updateDurations(_ newValue: Durations) {
        durations = newValue
        guard snapshot.phase == .idle, !snapshot.isFinished else { return }
        let total = TimeInterval(newValue.focusMinutes * 60)
        snapshot.remaining = total
        snapshot.total = total
        snapshot.progress = 0
        emit()
    }

    /// 由外部定时器（或测试）驱动。一次调用最多推进一个阶段。
    public func tick() {
        guard let deadline else { return }
        let remaining = deadline.timeIntervalSince(now())
        if remaining <= 0 {
            finish(reason: .completed)
        } else {
            snapshot.remaining = remaining
            snapshot.isRunning = true
            snapshot.isPaused = false
            emit()
        }
    }

    // MARK: - 内部

    private func begin(_ phase: TimerPhase, overrideMinutes: Int? = nil) {
        let minutes = overrideMinutes ?? durations.minutes(for: phase)
        let total = TimeInterval(minutes * 60)
        deadline = now().addingTimeInterval(total)
        pausedRemaining = nil
        snapshot = TimerSnapshot(
            phase: phase,
            isRunning: true,
            isPaused: false,
            isFinished: false,
            remaining: total,
            total: total,
            completedFocusSessions: completedFocusSessions,
            nextPhase: nil,
            progress: 0,
            isCustom: overrideMinutes != nil
        )
        emit()
    }

    private func finish(reason: PhaseTransition.Reason) {
        let finished = snapshot.phase
        guard finished != .idle else { return }

        let wasCustom = customMinutes != nil
        if finished == .focus, !wasCustom, reason == .completed {
            completedFocusSessions += 1
        }

        let next: TimerPhase
        if finished == .focus {
            if wasCustom {
                next = .focus
            } else if reason == .skipped {
                next = .shortBreak
            } else {
                next = completedFocusSessions % durations.sessionsPerLongBreak == 0 ? .longBreak : .shortBreak
            }
        } else {
            next = .focus
        }

        customMinutes = nil
        deadline = nil
        pausedRemaining = nil

        if autoStartNext {
            pendingNext = nil
            begin(next)
            onPhaseTransition?(PhaseTransition(from: finished, to: next, reason: reason))
        } else {
            pendingNext = next
            let nextTotal = TimeInterval(durations.minutes(for: next) * 60)
            snapshot = TimerSnapshot(
                phase: .idle,
                isRunning: false,
                isPaused: false,
                isFinished: true,
                remaining: nextTotal,
                total: nextTotal,
                completedFocusSessions: completedFocusSessions,
                nextPhase: next,
                progress: 0,
                isCustom: false
            )
            emit()
            onPhaseTransition?(PhaseTransition(from: finished, to: nil, reason: reason))
        }
    }

    private func emit() {
        if snapshot.total > 0 {
            let elapsed = snapshot.total - snapshot.remaining
            snapshot.progress = min(1, max(0, elapsed / snapshot.total))
        } else {
            snapshot.progress = 0
        }
        onChange?(snapshot)
    }
}
