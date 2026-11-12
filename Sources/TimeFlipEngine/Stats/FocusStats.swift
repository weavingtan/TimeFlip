import Foundation

public struct DayBucket: Equatable, Sendable, Identifiable {
    public var date: Date
    public var focusSeconds: Int
    public var sessions: Int
    public var id: Date { date }

    public init(date: Date, focusSeconds: Int, sessions: Int) {
        self.date = date
        self.focusSeconds = focusSeconds
        self.sessions = sessions
    }
}

/// 从本地会话账本算出来的当日/本周/连续天数等指标。
/// 纯函数式汇总，方便在测试里注入固定日历。
public struct FocusStats: Equatable, Sendable {
    public var todaySessions: Int
    public var todayFocusSeconds: Int
    public var weekSessions: Int
    public var weekFocusSeconds: Int
    public var totalFocusSeconds: Int
    /// 连续达成天数：只要某天完成过至少一次专注就算达成；今天还没记录时从昨天起算。
    public var streakDays: Int
    public var dailyGoalSessions: Int
    public var last14Days: [DayBucket]
    public var interruptedCount: Int
    public var completedCount: Int
    public var bestHour: Int?

    public var goalReached: Bool {
        dailyGoalSessions > 0 && todaySessions >= dailyGoalSessions
    }

    public var goalProgress: Double {
        guard dailyGoalSessions > 0 else { return 0 }
        return min(1, Double(todaySessions) / Double(dailyGoalSessions))
    }

    /// 中断率：跳过 / 提前放弃的专注占全部专注的比例。
    public var interruptionRate: Double {
        let total = completedCount + interruptedCount
        guard total > 0 else { return 0 }
        return Double(interruptedCount) / Double(total)
    }

    public static let empty = FocusStats(
        todaySessions: 0,
        todayFocusSeconds: 0,
        weekSessions: 0,
        weekFocusSeconds: 0,
        totalFocusSeconds: 0,
        streakDays: 0,
        dailyGoalSessions: 0,
        last14Days: [],
        interruptedCount: 0,
        completedCount: 0,
        bestHour: nil
    )

    public static func make(
        records: [SessionRecord],
        goal: Int,
        now: Date,
        calendar: Calendar
    ) -> FocusStats {
        let focus = records.filter { $0.phase == .focus }
        let completed = focus.filter(\.completed)

        let todayStart = calendar.startOfDay(for: now)
        /// 今天为 0，昨天为 1，往前递增。
        func dayOffset(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? 0
        }

        func completedRecords(onOffset offset: Int) -> [SessionRecord] {
            completed.filter { dayOffset($0.startedAt) == offset }
        }

        let today = completedRecords(onOffset: 0)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekRecords = completed.filter { weekInterval?.contains($0.startedAt) ?? false }

        var buckets: [DayBucket] = []
        for offset in stride(from: 13, through: 0, by: -1) {
            let day = completedRecords(onOffset: offset)
            let start = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            buckets.append(
                DayBucket(
                    date: start,
                    focusSeconds: day.reduce(0) { $0 + $1.actualSeconds },
                    sessions: day.count
                )
            )
        }

        // 连续天数：今天还没开始专注时，从昨天往前数，避免早上一睁眼看到 streak 归零。
        var streak = 0
        var offset = completedRecords(onOffset: 0).isEmpty ? 1 : 0
        while offset < 3_660, !completedRecords(onOffset: offset).isEmpty {
            streak += 1
            offset += 1
        }

        var hourHistogram: [Int: Int] = [:]
        for record in completed {
            let hour = calendar.component(.hour, from: record.startedAt)
            hourHistogram[hour, default: 0] += 1
        }
        let bestHour = hourHistogram.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key

        return FocusStats(
            todaySessions: today.count,
            todayFocusSeconds: today.reduce(0) { $0 + $1.actualSeconds },
            weekSessions: weekRecords.count,
            weekFocusSeconds: weekRecords.reduce(0) { $0 + $1.actualSeconds },
            totalFocusSeconds: completed.reduce(0) { $0 + $1.actualSeconds },
            streakDays: streak,
            dailyGoalSessions: max(0, goal),
            last14Days: buckets,
            interruptedCount: focus.count - completed.count,
            completedCount: completed.count,
            bestHour: bestHour
        )
    }
}

public enum StatsFormatting {
    /// "3 小时 12 分" / "42 分钟"，用于统计页与分享图。
    public static func duration(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }

    /// 紧凑版："3h12m" / "42m"，分享图上用。
    public static func compactDuration(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
