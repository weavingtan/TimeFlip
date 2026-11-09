import AppKit
import SwiftUI

/// 开发期离屏渲染：`TimeFlip --render-preview <目录>` 输出 PNG，
/// 用于在不依赖屏幕录制权限的情况下核对挂件外观。
@MainActor
enum PreviewRenderer {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var snapshot = TimerSnapshot(
            phase: .focus,
            isRunning: true,
            isPaused: false,
            isFinished: false,
            remaining: 1439,
            total: 1500,
            completedFocusSessions: 2,
            nextPhase: nil,
            progress: 1 - 1439.0 / 1500.0,
            isCustom: false
        )

        var defaults = TimeFlipSettings()
        defaults.appearance.fontSize = 64
        write(model: render(settings: defaults, snapshot: snapshot), to: directory.appendingPathComponent("1-flip-light.png"))

        var digital = TimeFlipSettings()
        digital.appearance.style = .digital
        digital.appearance.fontSize = 64
        write(model: render(settings: digital, snapshot: snapshot), to: directory.appendingPathComponent("2-digital.png"))

        var darkCards = TimeFlipSettings()
        darkCards.appearance.fontSize = 72
        darkCards.appearance.backgroundColor = RGBAColor(hex: "#111214", alpha: 1) ?? .ink
        darkCards.appearance.backgroundOpacity = 0.92
        darkCards.appearance.textColor = RGBAColor(hex: "#F5F5F7") ?? .paper
        darkCards.appearance.backgroundOpacity = 0.92
        write(model: render(settings: darkCards, snapshot: snapshot), to: directory.appendingPathComponent("3-flip-dark.png"))

        writeFlipAngles(to: directory.appendingPathComponent("5-flip-angles.png"))

        snapshot.phase = .idle
        snapshot.isRunning = false
        snapshot.remaining = 1500
        snapshot.progress = 0
        var clockOnly = TimeFlipSettings()
        clockOnly.behavior.showMode = .clockOnly
        clockOnly.appearance.fontSize = 64
        clockOnly.appearance.showBottomLine = false
        write(model: render(settings: clockOnly, snapshot: snapshot), to: directory.appendingPathComponent("4-clock-only.png"))
    }

    static func renderSettings(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = TimerSnapshot(
            phase: .focus,
            isRunning: true,
            isPaused: false,
            isFinished: false,
            remaining: 1439,
            total: 1500,
            completedFocusSessions: 2,
            nextPhase: nil,
            progress: 1 - 1439.0 / 1500.0,
            isCustom: false
        )
        let model = AppModel(snapshot: snapshot, settings: TimeFlipSettings())

        let panel = MenuPanelView(model: model)
            .frame(width: 320, height: 420)
        if let png = pngData(for: panel) {
            let url = directory.appendingPathComponent("menu-panel.png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }

        for page in SettingsView.Page.allCases {
            let view = SettingsView(model: model, initialPage: page, rendering: true)
                .frame(width: 860, height: 620)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("settings render failed: \(page.rawValue)\n".utf8))
                continue
            }
            let url = directory.appendingPathComponent("settings-\(page.rawValue).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }

    /// 翻页角度展开图：7 个关键角度 × 不透明/半透明两种卡面，
    /// 用来核对"揭开"是否严丝合缝（不漏背景、不重影），且半透明卡面下依然没有旧数字透出。
    private static func writeFlipAngles(to url: URL) {
        let angles: [Double] = [0, -30, -60, -90, -120, -150, -180]
        let appearances: [ClockAppearance] = [1.0, 0.35].map { opacity in
            var settings = TimeFlipSettings()
            settings.appearance.fontSize = 140
            settings.appearance.backgroundOpacity = opacity
            return settings.appearance
        }

        let rows = VStack(alignment: .leading, spacing: 28) {
            ForEach(appearances.indices, id: \.self) { row in
                flipRow(appearance: appearances[row], angles: angles)
            }
        }
        .padding(48)
        .background(Color(white: 0.24))

        if let png = pngData(for: rows) {
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }

    private static func flipRow(appearance: ClockAppearance, angles: [Double]) -> some View {
        let metrics = ClockMetrics.floating(appearance: appearance)
        return HStack(spacing: 30) {
            ForEach(angles.indices, id: \.self) { index in
                VStack(spacing: 10) {
                    FlipDigitView(
                        text: "8",
                        metrics: metrics,
                        appearance: appearance,
                        previewAngle: angles[index],
                        previewPrevious: "1"
                    )
                    Text("\(Int(angles[index]))°")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private static func pngData(for view: some View) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func render(settings: TimeFlipSettings, snapshot: TimerSnapshot) -> ClockRenderModel {
        let metrics = ClockMetrics.floating(appearance: settings.appearance)
        return ClockRenderModel.make(snapshot: snapshot, settings: settings, metrics: metrics)
    }

    private static func write(model: ClockRenderModel, to url: URL) {
        let content = ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.28, blue: 0.32), Color(red: 0.18, green: 0.22, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            FlipClockView(model: model)
        }
        .frame(width: model.metrics.contentSize(
            slots: model.slotCount,
            colons: model.colonCount,
            showDate: model.dateLine != nil,
            showBottom: model.bottomLine != nil
        ).width + 80,
        height: model.metrics.contentSize(
            slots: model.slotCount,
            colons: model.colonCount,
            showDate: model.dateLine != nil,
            showBottom: model.bottomLine != nil
        ).height + 80)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed: \(url.lastPathComponent)\n".utf8))
            return
        }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
