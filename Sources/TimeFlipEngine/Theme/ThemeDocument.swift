import Foundation

/// 主题的可交换载体：一串 JSON，可以存成文件，也可以直接粘进聊天窗口。
/// 没有服务端，也不需要账号——分享链路就是「复制这段文字」。
public struct ThemeDocument: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var name: String
    public var appearance: ClockAppearance

    public init(name: String, appearance: ClockAppearance) {
        self.schema = Self.currentSchema
        self.name = name
        self.appearance = appearance
    }

    /// 单行 JSON（不换行、键排序），适合放进剪贴板或聊天框。
    public func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// 宽容解析：允许前后有解释文字，只取第一个 `{` 到最后一个 `}` 之间的内容。
    /// 越界数值会被夹回合法区间，未知字段被忽略。
    public static func decode(_ text: String) -> ThemeDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            candidate = String(trimmed[start...end])
        } else {
            candidate = trimmed
        }

        guard let data = candidate.data(using: .utf8),
              let document = try? JSONDecoder().decode(ThemeDocument.self, from: data) else { return nil }
        return document.sanitized()
    }

    public func sanitized() -> ThemeDocument {
        var copy = self
        copy.schema = Self.currentSchema
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = clean.isEmpty ? "自定义主题" : String(clean.prefix(24))
        copy.appearance = appearance.clamped()
        copy.appearance.themeID = nil
        return copy
    }
}
