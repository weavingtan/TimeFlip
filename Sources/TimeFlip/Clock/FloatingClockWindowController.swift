import AppKit
import SwiftUI

/// 不抢焦点的挂件窗口：nonactivatingPanel 让点击它不会把 TimeFlip 变成前台 App，
/// 菜单栏不会突然切成 TimeFlip，拖动时也不会打断当前 App。
private final class ClockWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 盖在 SwiftUI 内容上的拖拽层：按住任意位置即可拖动窗口，且第一下点击就生效。
private final class DragCatcherView: NSView {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if ProcessInfo.processInfo.environment["TIMEFLIP_DEBUG"] == "1" {
            NSLog("TimeFlip clock drag began")
        }
        onDragBegan?()
        window?.performDrag(with: event)
        // performDrag 是同步的：松手后才返回，这里就是拖拽结束点。
        onDragEnded?()
    }
}

@MainActor
final class FloatingClockWindowController: NSObject, NSWindowDelegate {
    /// 贴桌面层级：位于 Finder 桌面图标窗口（kCGDesktopIconWindowLevel）之上，
    /// 但仍然远低于普通窗口（0），因此不会挡住任何 App。
    /// 用 desktopWindow 层级会被 Finder 的桌面窗口完整遮住（实测 Finder 在 -2147483603）。
    static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    private let window: ClockWindow
    private let container = NSView(frame: .zero)
    private let dragCatcher = DragCatcherView(frame: .zero)
    private var hosting: NSHostingView<ClockHostView>?
    private var display: ClockDisplayModel?
    private var lastRender: ClockRenderModel?
    private var lastBehavior: ClockBehavior?
    private var lastPlacements: [String: WindowOrigin] = [:]
    private var isApplyingFrame = false
    private var lastAppliedFrame: NSRect = .zero
    private var persistWorkItem: DispatchWorkItem?
    private var didInitialLayout = false
    private var lastForm: WindowForm?
    /// 拖拽进行中：此时绝不改窗口 frame，否则会和 performDrag 抢位置。
    private var isDragging = false
    /// 自检期间不把窗口位置写进用户设置。
    private var isSelfTesting = false

    var onMove: ((String, WindowOrigin) -> Void)?

    /// 挂件所在屏幕（用于铺满模式下按该屏宽度反算字号）。
    var currentScreen: NSScreen? { targetScreen }

    override init() {
        window = ClockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = Self.desktopLevel
        window.title = "TimeFlip Clock"
        window.delegate = self

        container.wantsLayer = true
        container.addSubview(dragCatcher)
        window.contentView = container

        dragCatcher.onDragBegan = { [weak self] in
            self?.isDragging = true
        }
        dragCatcher.onDragEnded = { [weak self] in
            guard let self else { return }
            self.isDragging = false
            // 松手立刻夹回屏幕内并记住位置，不等 0.35s 去抖：
            // 去抖窗口里只要来一次尺寸变化（数字位数变了 / 改了字号），就会用旧位置把窗口拽回原处。
            self.settlePosition()
            if let render = self.lastRender, let behavior = self.lastBehavior {
                self.update(render: render, behavior: behavior, placements: self.lastPlacements)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshWindow),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func update(render: ClockRenderModel, behavior: ClockBehavior, placements: [String: WindowOrigin]) {
        lastRender = render
        lastBehavior = behavior
        lastPlacements = placements

        guard behavior.visible else {
            window.orderOut(nil)
            return
        }

        let contentSize = render.metrics.contentSize(
            slots: render.slotCount,
            colons: render.colonCount,
            showDate: render.dateLine != nil,
            showBottom: render.bottomLine != nil
        )

        let formChanged = lastForm != behavior.form
        lastForm = behavior.form

        if behavior.form == .fullScreen, let screen = targetScreen {
            let frame = screen.frame
            if formChanged || !didInitialLayout || window.frame != frame {
                apply(frame: frame)
            }
            setRoot(render: render, fill: frame.size, draggable: false)
        } else {
            let size = contentSize
            let sizeChanged = abs(window.frame.width - size.width) > 0.5
                || abs(window.frame.height - size.height) > 0.5

            // 只在需要时改窗口 frame：每秒刷新不能把用户拖动后的位置拽回去。
            if formChanged || !didInitialLayout {
                // 首次布局 / 切换形态：用记住的位置。
                apply(frame: NSRect(origin: originFor(screen: targetScreen, size: size), size: size))
            } else if sizeChanged, !isDragging {
                // 只是尺寸变了（数字位数、字号、显示项）：位置以窗口当前所在为准。
                // 这里绝不能回退到"记住的位置"——落盘是异步的，用旧位置就会在拖动后把窗口弹回原处。
                let origin = clamped(origin: window.frame.origin, screen: targetScreen, size: size)
                apply(frame: NSRect(origin: origin, size: size))
                rememberCurrentPosition()
            }
            setRoot(render: render, fill: size, draggable: true)
        }

        didInitialLayout = true
        applyLayer(behavior)
        // 每秒都会走到这里，已在屏上就别再反复 orderFront（无谓的窗口服务器调用）。
        if !window.isVisible {
            window.orderFrontRegardless()
        }

        if ProcessInfo.processInfo.environment["TIMEFLIP_DEBUG"] == "1" {
            NSLog(
                "TimeFlip clock level=%d frame=%@ occluded=%@",
                window.level.rawValue,
                NSStringFromRect(window.frame),
                window.occlusionState.contains(.visible) ? "false" : "true"
            )
        }
    }

    // MARK: - 内部

    private var targetScreen: NSScreen? {
        window.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func apply(frame: NSRect) {
        isApplyingFrame = true
        window.setFrame(frame, display: true)
        isApplyingFrame = false
        lastAppliedFrame = frame
        layoutContent()
    }

    private func layoutContent() {
        let bounds = NSRect(origin: .zero, size: window.frame.size)
        container.frame = bounds
        hosting?.frame = bounds
        dragCatcher.frame = bounds
    }

    private func setRoot(render: ClockRenderModel, fill: CGSize, draggable: Bool) {
        dragCatcher.isHidden = !draggable
        window.isMovableByWindowBackground = false

        if let display {
            display.render = render
            display.fill = fill
            layoutContent()
            return
        }

        let display = ClockDisplayModel(render: render, fill: fill)
        let host = NSHostingView(rootView: ClockHostView(display: display))
        host.frame = NSRect(origin: .zero, size: fill)
        container.addSubview(host, positioned: .below, relativeTo: dragCatcher)
        hosting = host
        self.display = display
        layoutContent()
    }

    private func applyLayer(_ behavior: ClockBehavior) {
        switch behavior.layer {
        case .desktop:
            window.level = Self.desktopLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case .floating:
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
    }

    private func originFor(screen: NSScreen?, size: CGSize) -> CGPoint {
        guard let screen else { return CGPoint(x: 48, y: 48) }
        let visible = screen.visibleFrame
        let id = Self.screenID(screen)

        let origin: CGPoint
        if let saved = lastPlacements[id] {
            origin = CGPoint(x: saved.x, y: saved.y)
        } else {
            origin = CGPoint(x: visible.maxX - size.width - 48, y: visible.minY + 48)
        }
        return clamped(origin: origin, screen: screen, size: size)
    }

    /// 夹回屏幕可见区域内（不压菜单栏与 Dock）。
    private func clamped(origin: CGPoint, screen: NSScreen?, size: CGSize) -> CGPoint {
        guard let screen else { return origin }
        let visible = screen.visibleFrame
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return CGPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }

    @objc private func refreshWindow() {
        guard let render = lastRender, let behavior = lastBehavior else { return }
        update(render: render, behavior: behavior, placements: lastPlacements)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame,
              lastBehavior?.form != .fullScreen,
              window.frame != lastAppliedFrame else { return }
        if ProcessInfo.processInfo.environment["TIMEFLIP_DEBUG"] == "1" {
            NSLog("TimeFlip clock didMove frame=%@", NSStringFromRect(window.frame))
        }
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.settlePosition()
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// 拖动停下后：夹回屏幕内并记住位置（按屏幕 UUID）。
    private func settlePosition() {
        // window.screen 在窗口跨屏/部分离屏时会是 nil，此时退回 targetScreen；
        // 否则一次拖到边缘的移动就不会被记住，下次尺寸变化又弹回旧位置。
        guard let screen = window.screen ?? targetScreen else { return }
        let size = window.frame.size
        let origin = clamped(origin: window.frame.origin, screen: screen, size: size)

        if origin != window.frame.origin {
            apply(frame: NSRect(origin: origin, size: size))
        }

        let id = Self.screenID(screen)
        let saved = WindowOrigin(x: Double(origin.x), y: Double(origin.y))
        lastPlacements[id] = saved
        guard !isSelfTesting else { return }
        onMove?(id, saved)
    }

    /// 位置变了就立刻同步进内存里的 placements，后续任何重排都用新位置。
    private func rememberCurrentPosition() {
        guard let screen = window.screen ?? targetScreen else { return }
        let id = Self.screenID(screen)
        let saved = WindowOrigin(x: Double(window.frame.origin.x), y: Double(window.frame.origin.y))
        lastPlacements[id] = saved
        guard !isSelfTesting else { return }
        onMove?(id, saved)
    }

    /// 回归自检：模拟"拖动中窗口移动 + 紧接着一次尺寸变化"，确认窗口停在拖动后的位置，
    /// 而不是被旧的记忆位置拽回去（历史 bug：拖走了又自己回到原处）。
    func dragRegressionReport() -> String {
        guard let render = lastRender, let behavior = lastBehavior else { return "DRAGTEST skip=no-render" }
        guard behavior.form != .fullScreen, let screen = window.screen ?? targetScreen else {
            return "DRAGTEST skip=unavailable"
        }

        isSelfTesting = true
        defer { isSelfTesting = false }

        let before = window.frame
        let visible = screen.visibleFrame
        let start = NSPoint(x: visible.minX + 120, y: visible.minY + 120)
        apply(frame: NSRect(origin: start, size: before.size))

        let moved = NSPoint(x: start.x + 160, y: start.y + 100)
        window.setFrameOrigin(moved)   // 等同拖动过程中的一次移动（会触发 windowDidMove）

        var shorter = render
        shorter.characters = Array("1:23")   // 位数变少 → contentSize 变小，走 sizeChanged 分支
        let expected = shorter.metrics.contentSize(
            slots: shorter.slotCount,
            colons: shorter.colonCount,
            showDate: shorter.dateLine != nil,
            showBottom: shorter.bottomLine != nil
        )
        update(render: shorter, behavior: behavior, placements: lastPlacements)

        let after = window.frame
        let stayed = abs(after.origin.x - moved.x) <= 1 && abs(after.origin.y - moved.y) <= 1
        let resized = abs(after.width - expected.width) <= 1 && abs(after.height - expected.height) <= 1

        // 第二阶段：走一遍"按下 → 移动 → 松手"的通知链，确认松手就把位置记进 placements。
        let second = NSPoint(x: start.x + 60, y: start.y + 40)
        dragCatcher.onDragBegan?()
        window.setFrameOrigin(second)
        dragCatcher.onDragEnded?()
        let savedOrigin = lastPlacements[Self.screenID(screen)]
        let saved = savedOrigin.map {
            abs($0.x - Double(second.x)) <= 1 && abs($0.y - Double(second.y)) <= 1
        } ?? false

        let report = "DRAGTEST stayed=\(stayed) resized=\(resized) saved=\(saved) "
            + "moved=\(NSStringFromPoint(moved)) after=\(NSStringFromRect(after))"

        // 还原，别把自检位置写进用户设置
        persistWorkItem?.cancel()
        apply(frame: before)
        update(render: render, behavior: behavior, placements: lastPlacements)
        return report
    }

    /// 自检：确认拖拽层在内容之上、可见、且能命中（用于 --selftest-hit）。
    func hitTestReport() -> String {
        let point = NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        let hit = container.hitTest(point)
        return "level=\(window.level.rawValue) frame=\(NSStringFromRect(window.frame)) "
            + "catcherHidden=\(dragCatcher.isHidden) "
            + "hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")"
    }

    static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "screen-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }
}
