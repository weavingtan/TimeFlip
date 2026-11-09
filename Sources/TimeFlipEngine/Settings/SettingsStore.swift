import Foundation

public final class SettingsStore {
    public private(set) var settings: TimeFlipSettings
    public let directory: URL

    public var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public init(directory: URL, settings: TimeFlipSettings = TimeFlipSettings()) {
        self.directory = directory
        self.settings = settings
    }

    /// 读取失败或 JSON 损坏时回退默认值，并把坏文件改名备份，绝不崩溃。
    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            settings = TimeFlipSettings()
            return
        }
        do {
            settings = try JSONDecoder().decode(TimeFlipSettings.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("settings.broken-\(stamp).json")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            settings = TimeFlipSettings()
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func update(_ body: (inout TimeFlipSettings) -> Void) throws -> TimeFlipSettings {
        body(&settings)
        try save()
        return settings
    }
}
