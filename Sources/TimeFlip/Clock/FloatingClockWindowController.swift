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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if ProcessInfo.processInfo.environment["TIMEFLIP_DEBUG"] == "1" {
            NSLog("TimeFlip clock drag began")
        }
        window?.performDrag(with: event)
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

    var onMove: ((String, WindowOrigin) -> Void)?

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
            if formChanged || !didInitialLayout || sizeChanged {
                let origin = originFor(screen: targetScreen, size: size)
                apply(frame: NSRect(origin: origin, size: size))
            }
            setRoot(render: render, fill: size, draggable: true)
        }

        didInitialLayout = true
        applyLayer(behavior)
        window.orderFrontRegardless()

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

        var origin: CGPoint
        if let saved = lastPlacements[id] {
            origin = CGPoint(x: saved.x, y: saved.y)
        } else {
            origin = CGPoint(x: visible.maxX - size.width - 48, y: visible.minY + 48)
        }

        let maxX = visible.maxX - size.width
        let maxY = visible.maxY - size.height
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, maxX))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, maxY))
        return origin
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
        guard let screen = window.screen else { return }
        let visible = screen.visibleFrame
        var frame = window.frame

        let maxX = max(visible.minX, visible.maxX - frame.width)
        let maxY = max(visible.minY, visible.maxY - frame.height)
        let clamped = NSRect(
            x: min(max(frame.origin.x, visible.minX), maxX),
            y: min(max(frame.origin.y, visible.minY), maxY),
            width: frame.width,
            height: frame.height
        )

        if clamped != frame {
            frame = clamped
            apply(frame: frame)
        }

        onMove?(
            Self.screenID(screen),
            WindowOrigin(x: Double(frame.origin.x), y: Double(frame.origin.y))
        )
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
