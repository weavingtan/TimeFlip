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
        writeThemeStrip(to: directory.appendingPathComponent("6-themes.png"))
        writeShareCard(to: directory.appendingPathComponent("7-share-card.png"))

        snapshot.phase = .idle
        snapshot.isRunning = false
        snapshot.remaining = 1500
        snapshot.progress = 0
        var clockOnly = TimeFlipSettings()
        clockOnly.behavior.showMode = .clockOnly
        clockOnly.appearance.fontSize = 64
        clockOnly.appearance.showBottomLine = false
        write(model: render(settings: clockOnly, snapshot: snapshot), to: directory.appendingPathComponent("4-clock-only.png"))

        // 6. 按本机已保存的设置再画一张：核对真实配置下的观感（只读设置，不写回）。
        let store = SettingsStore(directory: AppPaths.supportDirectory)
        store.load()
        var current = store.settings
        if current.appearance.fontSize > 240 {
            current.appearance.fontSize = 240
        }
        write(
            model: render(settings: current, snapshot: snapshot),
            to: directory.appendingPathComponent("6-current-settings.png")
        )
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
        let model = AppModel(snapshot: snapshot, settings: TimeFlipSettings(), stats: demoStats())

        // 弹窗的四种状态都画出来：运行中 / 空闲 / 休息 / 刚结束，避免某一种状态排版塌掉。
        let states: [(name: String, snapshot: TimerSnapshot)] = [
            ("menu-panel", snapshot),
            ("menu-panel-idle", TimerSnapshot(
                phase: .idle, isRunning: false, isPaused: false, isFinished: false,
                remaining: 1500, total: 1500, completedFocusSessions: 0,
                nextPhase: nil, progress: 0, isCustom: false
            )),
            ("menu-panel-break", TimerSnapshot(
                phase: .shortBreak, isRunning: true, isPaused: false, isFinished: false,
                remaining: 268, total: 300, completedFocusSessions: 1,
                nextPhase: nil, progress: 1 - 268.0 / 300.0, isCustom: false
            )),
            ("menu-panel-finished", TimerSnapshot(
                phase: .idle, isRunning: false, isPaused: false, isFinished: true,
                remaining: 300, total: 300, completedFocusSessions: 4,
                nextPhase: .longBreak, progress: 0, isCustom: false
            ))
        ]

        for state in states {
            let panelModel = AppModel(snapshot: state.snapshot, settings: TimeFlipSettings())
            let panel = MenuPanelView(model: panelModel)
                .frame(width: TFTheme.panelWidth, height: 470)
            if let png = pngData(for: panel) {
                let url = directory.appendingPathComponent("\(state.name).png")
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }

        for page in SettingsView.Page.allCases {
            // 不滚动的整页渲染：给足高度，保证每张卡片都完整可见。
            let view = SettingsView(model: model, initialPage: page, rendering: true)
                .frame(width: 880, height: 1240)
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

    /// 八套预设一览：核对每套的卡面材质、机身与配色是否真的分得开。
    private static func writeThemeStrip(to url: URL) {
        let snapshot = TimerSnapshot(
            phase: .focus, isRunning: true, isPaused: false, isFinished: false,
            remaining: 1439, total: 1500, completedFocusSessions: 2,
            nextPhase: nil, progress: 0.04, isCustom: false
        )

        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4),
            spacing: 18
        ) {
            ForEach(ThemePreset.all) { preset in
                themeTile(preset, snapshot: snapshot)
            }
        }
        .padding(28)
        .frame(width: 1120)
        .background(Color(white: 0.12))

        if let png = pngData(for: grid) {
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }

    private static func themeTile(_ preset: ThemePreset, snapshot: TimerSnapshot) -> some View {
        var settings = TimeFlipSettings()
        settings.appearance = preset.applied(to: settings.appearance)
        settings.appearance.fontSize = 32
        let metrics = ClockMetrics.floating(appearance: settings.appearance)
        let model = ClockRenderModel.make(snapshot: snapshot, settings: settings, metrics: metrics)

        return VStack(spacing: 8) {
            FlipClockView(model: model)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.27, blue: 0.32),
                            Color(red: 0.16, green: 0.19, blue: 0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(preset.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private static func writeShareCard(to url: URL) {
        guard let image = ShareCardRenderer.makeImage(stats: demoStats()),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("share card render failed\n".utf8))
            return
        }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }

    /// 造一份有起伏的假数据，只为核对分享图的排版。
    private static func demoStats() -> FocusStats {
        let calendar = Calendar.current
        let now = Date()
        let pattern = [3, 4, 2, 5, 4, 0, 2, 3, 4, 5, 1, 3, 4, 2]
        var records: [SessionRecord] = []
        for (index, count) in pattern.enumerated() {
            let daysAgo = pattern.count - 1 - index
            guard let day = calendar.date(
                byAdding: .day,
                value: -daysAgo,
                to: calendar.startOfDay(for: now)
            ) else { continue }
            for slot in 0..<count {
                let start = day.addingTimeInterval(Double(9 + slot) * 3600)
                records.append(
                    SessionRecord(
                        startedAt: start,
                        endedAt: start.addingTimeInterval(1500),
                        plannedSeconds: 1500,
                        actualSeconds: 1500,
                        completed: true
                    )
                )
            }
        }
        return FocusStats.make(records: records, goal: 4, now: now, calendar: calendar)
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
