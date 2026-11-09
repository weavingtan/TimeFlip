import Foundation

public enum TimeStrings {
    /// "24:59" / "1:01:01"
    public static func countdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, secs)
        }
        return String(format: "%02ld:%02ld", minutes, secs)
    }

    public static func clock(
        date: Date,
        use24Hour: Bool,
        showSeconds: Bool,
        calendar: Calendar = .current
    ) -> String {
        let format: String
        switch (use24Hour, showSeconds) {
        case (true, true): format = "HH:mm:ss"
        case (true, false): format = "HH:mm"
        case (false, true): format = "hh:mm:ss a"
        case (false, false): format = "hh:mm a"
        }
        return formatter(format, calendar: calendar).string(from: date)
    }

    /// ("Nov 09 2026", "Mon")
    public static func dateLine(date: Date, calendar: Calendar = .current) -> (left: String, right: String) {
        let left = formatter("MMM dd yyyy", calendar: calendar).string(from: date)
        let right = formatter("EEE", calendar: calendar).string(from: date)
        return (left, right)
    }

    /// 有专注记录时显示 "Focus 2/4"，否则显示 "Week 45, Day 9"
    public static func bottomLine(
        date: Date,
        completedSessions: Int,
        perLongBreak: Int,
        calendar: Calendar = .current
    ) -> String {
        if completedSessions > 0, perLongBreak > 0 {
            let inCycle = completedSessions % perLongBreak
            let shown = inCycle == 0 ? perLongBreak : inCycle
            return "Focus \(shown)/\(perLongBreak)"
        }
        let week = calendar.component(.weekOfYear, from: date)
        let day = calendar.component(.day, from: date)
        return "Week \(week), Day \(day)"
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
