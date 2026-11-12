import AppKit

final class ChimePlayer {
    private var cache: [String: NSSound] = [:]

    /// 目录只读一次：这个列表会被设置面板的 Picker 反复求值，别每次刷 UI 都扫盘。
    static let availableSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }()

    func play(name: String?) {
        guard let name, !name.isEmpty else { return }
        if let cached = cache[name] {
            if cached.isPlaying { cached.stop() }
            cached.play()
            return
        }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        cache[name] = sound
        sound.play()
    }
}
