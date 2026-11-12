import Foundation

/// 一次专注会话。只记录 focus 阶段（含自定义倒计时），休息不落盘。
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var phase: TimerPhase
    public var plannedSeconds: Int
    public var actualSeconds: Int
    /// 走完流程为 true；跳过 / 提前放弃为 false。
    public var completed: Bool
    public var isCustom: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        phase: TimerPhase = .focus,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        isCustom: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.phase = phase
        self.plannedSeconds = plannedSeconds
        self.actualSeconds = actualSeconds
        self.completed = completed
        self.isCustom = isCustom
    }

    /// 从一次阶段结束事件落一条记录：只有专注阶段会进账本。
    public static func make(transition: PhaseTransition, now: Date = Date()) -> SessionRecord {
        SessionRecord(
            startedAt: now.addingTimeInterval(-Double(transition.spentSeconds)),
            endedAt: now,
            phase: transition.from,
            plannedSeconds: transition.plannedSeconds,
            actualSeconds: transition.spentSeconds,
            completed: transition.reason == .completed,
            isCustom: transition.isCustom
        )
    }
}

/// 本地会话账本：一个 JSON 文件，没有账号也不联网。
public final class SessionLog {
    public private(set) var records: [SessionRecord] = []
    public let directory: URL

    public var fileURL: URL { directory.appendingPathComponent("sessions.json") }

    /// 上限保护：一年按每天 30 次算也才一万条，超过就丢最旧的。
    private static let capacity = 20_000

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            records = []
            return
        }
        do {
            records = try JSONDecoder().decode([SessionRecord].self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("sessions.broken-\(stamp).json")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            records = []
        }
    }

    public func append(_ record: SessionRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.startedAt < $1.startedAt }
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
        }
    }

    public func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 只保留最近 N 天，避免文件无限增长。
    public func prune(keepingDays: Int = 365, now: Date = Date(), calendar: Calendar = .current) {
        guard keepingDays > 0,
              let cutoff = calendar.date(byAdding: .day, value: -(keepingDays - 1), to: calendar.startOfDay(for: now))
        else { return }
        records.removeAll { $0.startedAt < cutoff }
    }
}
