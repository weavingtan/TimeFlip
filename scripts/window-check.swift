import CoreGraphics
import Foundation

// 用法: window-check <期望层级> <期望模式 floating|full>
// 主屏尺寸从 Wallpaper 窗口（kCGDesktopWindowLevel）推导，避免 TCC 与多屏 union 干扰。
// 退出码 0 = 通过，1 = 不通过，2 = 参数错误。

guard CommandLine.arguments.count >= 3, let expectedLevel = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-check <level> <floating|full>\n".utf8))
    exit(2)
}

let mode = CommandLine.arguments[2]
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

var screenWidth: Double = 0
var screenHeight: Double = 0
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    guard owner == "Wallpaper", layer == -2147483625 else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    if x == 0, y == 0 {
        screenWidth = bounds["Width"] as? Double ?? 0
        screenHeight = bounds["Height"] as? Double ?? 0
    }
}

if screenWidth <= 0 || screenHeight <= 0 {
    FileHandle.standardError.write(Data("FAIL: 无法推导主屏尺寸\n".utf8))
    exit(1)
}

var clockWindow: [String: Any]?
var statusItemWindows = 0
var normalWindows = 0

for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner == "TimeFlip" else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    if layer == expectedLevel {
        clockWindow = window
    } else if layer == 25 {
        statusItemWindows += 1
    } else if layer == 0 {
        normalWindows += 1
    }
}

if CommandLine.arguments.contains("--require-settings-window"), normalWindows == 0 {
    FileHandle.standardError.write(Data("FAIL: 设置窗口（layer 0）未出现\n".utf8))
    exit(1)
}
print("settings windows: \(normalWindows)")

guard let clockWindow else {
    FileHandle.standardError.write(Data("FAIL: 未找到层级 \(expectedLevel) 的 TimeFlip 窗口\n".utf8))
    exit(1)
}

let bounds = clockWindow[kCGWindowBounds as String] as? [String: Any] ?? [:]
let width = bounds["Width"] as? Double ?? 0
let height = bounds["Height"] as? Double ?? 0
let onscreen = clockWindow[kCGWindowIsOnscreen as String] as? Bool ?? false
let alpha = clockWindow[kCGWindowAlpha as String] as? Double ?? 0

print("clock window: level=\(expectedLevel) size=\(Int(width))x\(Int(height)) onscreen=\(onscreen) alpha=\(alpha)")
print("status item windows: \(statusItemWindows)")

var failures = 0

if !onscreen { print("FAIL: 窗口不在屏上"); failures += 1 }
if alpha <= 0 { print("FAIL: 窗口透明"); failures += 1 }
if width <= 0 || height <= 0 { print("FAIL: 窗口尺寸异常"); failures += 1 }
if statusItemWindows == 0 { print("FAIL: 菜单栏状态项窗口缺失"); failures += 1 }

switch mode {
case "full":
    if abs(width - screenWidth) > 2 || abs(height - screenHeight) > 2 {
        print("FAIL: 铺满模式尺寸应为 \(Int(screenWidth))x\(Int(screenHeight))")
        failures += 1
    }
case "floating":
    if width >= screenWidth || height >= screenHeight {
        print("FAIL: 浮动模式窗口不应铺满屏幕")
        failures += 1
    }
default:
    print("FAIL: 未知模式 \(mode)")
    failures += 1
}

if failures == 0 {
    print("WINDOW CHECK PASSED")
    exit(0)
} else {
    print("WINDOW CHECK FAILED (\(failures))")
    exit(1)
}
