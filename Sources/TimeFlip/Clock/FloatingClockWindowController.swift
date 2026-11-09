import AppKit
import SwiftUI

@MainActor
final class FloatingClockWindowController: NSObject, NSWindowDelegate {
    /// 贴桌面层级：位于 Finder 桌面图标窗口（kCGDesktopIconWindowLevel）之上，
    /// 但仍然远低于普通窗口（0），因此不会挡住任何 App。
    /// 用 desktopWindow 层级会被 Finder 的桌面窗口完整遮住（实测 Finder 在 -2147483603）。
    static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    private let window: NSWindow
    private var hosting: NSHostingView<ClockHostView>?
    private var display: ClockDisplayModel?
    private var lastRender: ClockRenderModel?
    private var lastBehavior: ClockBehavior?
    private var lastPlacements: [String: WindowOrigin] = [:]
    private var isApplyingFrame = false
    private var isRepositioning = false
    private var repositionTimer: Timer?

    var onMove: ((String, WindowOrigin) -> Void)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = Self.desktopLevel
        window.title = "TimeFlip Clock"
        window.delegate = self

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

        if behavior.form == .fullScreen, let screen = targetScreen {
            let frame = screen.frame
            apply(frame: frame)
            setRoot(render: render, fill: frame.size)
        } else {
            let size = contentSize
            let origin = originFor(screen: targetScreen, size: size)
            apply(frame: NSRect(origin: origin, size: size))
            setRoot(render: render, fill: size)
        }

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

    func beginRepositioning() {
        guard let render = lastRender else { return }
        isRepositioning = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setRoot(render: render, fill: window.frame.size)

        repositionTimer?.invalidate()
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.endRepositioning()
            }
        }
    }

    private func endRepositioning() {
        guard isRepositioning else { return }
        isRepositioning = false
        repositionTimer?.invalidate()
        repositionTimer = nil
        if let behavior = lastBehavior {
            applyLayer(behavior)
        }
        if let render = lastRender {
            setRoot(render: render, fill: window.frame.size)
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
        hosting?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func setRoot(render: ClockRenderModel, fill: CGSize) {
        if let display {
            display.render = render
            display.fill = fill
            display.repositioning = isRepositioning
            hosting?.frame = NSRect(origin: .zero, size: fill)
            return
        }

        let display = ClockDisplayModel(render: render, fill: fill, repositioning: isRepositioning)
        let host = NSHostingView(rootView: ClockHostView(display: display))
        host.frame = NSRect(origin: .zero, size: fill)
        window.contentView = host
        hosting = host
        self.display = display
    }

    private func applyLayer(_ behavior: ClockBehavior) {
        if isRepositioning {
            window.ignoresMouseEvents = false
            window.isMovableByWindowBackground = true
            return
        }

        switch behavior.layer {
        case .desktop:
            window.level = Self.desktopLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isMovableByWindowBackground = false
        case .floating:
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.isMovableByWindowBackground = true
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
        guard isRepositioning, !isApplyingFrame, let screen = window.screen else { return }
        onMove?(
            Self.screenID(screen),
            WindowOrigin(x: Double(window.frame.origin.x), y: Double(window.frame.origin.y))
        )
    }

    static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "screen-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }
}
