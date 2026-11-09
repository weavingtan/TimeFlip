import AppKit

final class ChimePlayer {
    private var cache: [String: NSSound] = [:]

    static var availableSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

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
