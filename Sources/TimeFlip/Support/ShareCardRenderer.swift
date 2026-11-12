import AppKit
import SwiftUI

/// 统计分享图：一张 1080×1350 的竖图，直接发朋友圈/小红书/群聊。
/// 没有任何服务端参与，渲染完全在本地完成。
@MainActor
enum ShareCardRenderer {
    static let pointSize = CGSize(width: 540, height: 675)

    static func makeImage(stats: FocusStats, now: Date = Date()) -> NSImage? {
        let view = ShareCardView(stats: stats, now: now)
            .frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }

    static func pngData(stats: FocusStats, now: Date = Date()) -> Data? {
        guard let image = makeImage(stats: stats, now: now),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// 存到用户选的路径（默认「桌面」）。取消返回 nil。
    @discardableResult
    static func savePNG(stats: FocusStats, now: Date = Date()) -> URL? {
        guard let data = pngData(stats: stats, now: now) else { return nil }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName(now: now)
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktop
        }
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func copyToPasteboard(stats: FocusStats, now: Date = Date()) -> Bool {
        guard let image = makeImage(stats: stats, now: now) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    static func fileName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "TimeFlip-\(formatter.string(from: now)).png"
    }
}

private struct ShareCardView: View {
    let stats: FocusStats
    let now: Date

    private var accent: Color { TFTheme.accent(for: .focus) }

    private var maxSeconds: Int {
        max(1, stats.last14Days.map(\.focusSeconds).max() ?? 1)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, TFTheme.accent(for: .longBreak)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    Text("TIMEFLIP")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Text(dateText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer(minLength: 0)

            Text("本周专注")
                .font(.system(size: 12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.45))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StatsFormatting.compactDuration(seconds: stats.weekFocusSeconds))
                    .font(.system(size: 92, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.top, 2)

            Text("本周 \(stats.weekSessions) 轮 · 累计完成 \(stats.completedCount) 次")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)

            Spacer(minLength: 0)

            barChart

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                badge(text: "连续 \(stats.streakDays) 天", tint: accent)
                badge(
                    text: "今日 \(stats.todaySessions)/\(max(1, stats.dailyGoalSessions))",
                    tint: stats.goalReached ? TFTheme.accent(for: .shortBreak) : .white.opacity(0.55)
                )
                Spacer(minLength: 0)
            }

            Text("把专注放在桌面上")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 14)
        }
        .padding(38)
        .frame(width: ShareCardRenderer.pointSize.width, height: ShareCardRenderer.pointSize.height, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14),
                        Color(red: 0.05, green: 0.05, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [accent.opacity(0.24), Color.clear],
                    center: UnitPoint(x: 0.12, y: 0.05),
                    startRadius: 0,
                    endRadius: 460
                )
            }
        )
    }

    private var barChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近 14 天")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
                Text("最佳时段 \(stats.bestHour.map { String(format: "%02d:00", $0) } ?? "—")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(stats.last14Days) { bucket in
                    let ratio = Double(bucket.focusSeconds) / Double(maxSeconds)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                bucket.sessions > 0
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(0.08))
                            )
                            .frame(height: max(4, CGFloat(ratio) * 96))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
    }
}
