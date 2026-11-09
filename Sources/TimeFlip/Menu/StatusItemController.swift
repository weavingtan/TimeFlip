import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private var flashTimer: Timer?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.toolTip = "TimeFlip"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuPanelView(model: model))

        update(snapshot: model.snapshot, settings: model.settings)
    }

    func update(snapshot: TimerSnapshot, settings: TimeFlipSettings) {
        guard let button = statusItem.button else { return }

        let style = settings.menuBar.style
        button.image = style == .timeOnly
            ? nil
            : Self.icon(
                progress: snapshot.progress,
                finished: snapshot.isFinished,
                showRing: settings.menuBar.showProgressRing
            )
        button.title = style == .iconOnly ? "" : Self.title(for: snapshot)
        button.image?.isTemplate = true

        if snapshot.isFinished {
            button.contentTintColor = .systemRed
        } else if flashTimer == nil {
            button.contentTintColor = nil
        }
    }

    func flashRed(seconds: TimeInterval = 3) {
        guard let button = statusItem.button else { return }
        button.contentTintColor = .systemRed
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.flashTimer = nil
                if let snapshot = self?.model.snapshot {
                    self?.update(snapshot: snapshot, settings: self?.model.settings ?? TimeFlipSettings())
                }
            }
        }
    }

    // MARK: - 交互

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true

        if isSecondary {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMenu() {
        let menu = NSMenu()

        let toggleClock = NSMenuItem(
            title: model.clockVisible ? "隐藏桌面时钟" : "显示桌面时钟",
            action: #selector(menuToggleClock),
            keyEquivalent: ""
        )
        toggleClock.target = self
        menu.addItem(toggleClock)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 TimeFlip", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggleClock() {
        model.setClockVisible(!model.clockVisible)
    }

    @objc private func menuSettings() {
        model.openSettings()
    }

    @objc private func menuQuit() {
        model.quit()
    }

    // MARK: - 绘制

    private static func title(for snapshot: TimerSnapshot) -> String {
        if snapshot.isFinished {
            return TimeStrings.countdown(seconds: 0)
        }
        return TimeStrings.countdown(seconds: snapshot.displaySeconds)
    }

    private static func icon(progress: Double, finished: Bool, showRing: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let color = finished ? NSColor.systemRed : NSColor.labelColor

            guard showRing else {
                let dot = NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8)
                color.setFill()
                NSBezierPath(ovalIn: dot).fill()
                return true
            }

            let lineWidth: CGFloat = 2
            let circle = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let track = NSBezierPath(ovalIn: circle)
            color.withAlphaComponent(0.28).setStroke()
            track.lineWidth = lineWidth
            track.stroke()

            if progress > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: NSPoint(x: rect.midX, y: rect.midY),
                    radius: circle.width / 2,
                    startAngle: 90,
                    endAngle: 90 - 360 * CGFloat(min(1, max(0, progress))),
                    clockwise: true
                )
                color.setStroke()
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
