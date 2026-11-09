import AppKit
import SwiftUI

@main
struct TimeFlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }

        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"),
           CommandLine.arguments.count > index + 1 {
            PreviewRenderer.renderSettings(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            NSApp.terminate(nil)
            return
        }

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()

        if CommandLine.arguments.contains("--open-settings") {
            coordinator.openSettings()
        }

        if CommandLine.arguments.contains("--selftest-hit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("HITTEST \(coordinator.hitTestReport())")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
