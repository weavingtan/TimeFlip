import AppKit
import ApplicationServices
import CoreGraphics

/// 结束专注后把用户从椅子上赶走。
///
/// macOS 15 已经移除了 `CGSession -suspend` 和 `login.framework` 的 `SACLockScreenImmediate`，
/// 所以这里只走两条真实可用的路：
/// - `⌃⌘Q` 系统快捷键（真锁屏，需要一次性「辅助功能」授权）
/// - `pmset displaysleepnow`（关屏，不需要任何权限；系统设置里「需要密码」为立即时即锁屏）
@MainActor
final class ScreenLocker {
    static let lockKeyCode: CGKeyCode = 12   // kVK_ANSI_Q

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统授权提示（只会弹一次，之后由用户在系统设置里手动开）。
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 执行一次锁定，返回是否真的做了点什么。
    @discardableResult
    func perform(_ style: LockStyle) -> Bool {
        switch style {
        case .off:
            return true
        case .displaySleep:
            return sleepDisplay()
        case .lock:
            if lockWithShortcut() { return true }
            return sleepDisplay()
        }
    }

    /// 账户没有密码时，锁屏等于没锁——设置页据此给出提示。
    var hasAccountPassword: Bool {
        let user = NSUserName()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(user)", "AuthenticationAuthority"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return true
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("ShadowHash")
    }

    /// 前台是否有铺满整块屏幕的窗口（演示 / 录屏 / 全屏视频）：这时候黑屏是灾难。
    func hasFullScreenApp() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let screens = NSScreen.screens.map(\.frame)

        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            for frame in screens where abs(bounds.width - frame.width) < 2 && abs(bounds.height - frame.height) < 2 {
                return true
            }
        }
        return false
    }

    // MARK: - 私有

    private func lockWithShortcut() -> Bool {
        guard isAccessibilityTrusted else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: Self.lockKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.lockKeyCode, keyDown: false)
        else { return false }

        down.flags = [.maskCommand, .maskControl]
        up.flags = [.maskCommand, .maskControl]
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func sleepDisplay() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
