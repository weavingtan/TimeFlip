import SwiftUI

/// 全 App 统一的视觉语言：阶段配色、卡片与按钮样式。
/// 菜单栏弹窗、设置面板、离屏预览共用这一份，避免各处各写一套。
enum TFTheme {
    static let panelWidth: CGFloat = 336
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9

    /// 阶段主色：专注=番茄红，短休=青，长休=靛蓝。
    /// 空闲沿用专注色，让「开始专注」这个主操作保持醒目。
    static func accent(for phase: TimerPhase) -> Color {
        switch phase {
        case .focus, .idle: return Color(red: 0.93, green: 0.36, blue: 0.30)
        case .shortBreak: return Color(red: 0.18, green: 0.62, blue: 0.52)
        case .longBreak: return Color(red: 0.35, green: 0.47, blue: 0.86)
        }
    }

    static func accent(for snapshot: TimerSnapshot) -> Color {
        snapshot.isFinished ? Color(red: 0.88, green: 0.24, blue: 0.22) : accent(for: snapshot.phase)
    }

    static func icon(for phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "flame.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        case .idle: return "leaf.fill"
        }
    }
}

/// 主操作按钮：整行胶囊、阶段色实心。
struct TFPrimaryButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(configuration.isPressed ? tint.opacity(0.82) : tint))
            .contentShape(Capsule())
    }
}

/// 次级图标按钮：圆形底，用于跳过 / 重置。
struct TFIconButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
            .contentShape(Circle())
    }
}

/// 选项胶囊：快捷倒计时、试听、开始等轻量按钮。
struct TFChipButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(prominent ? tint : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: TFTheme.controlRadius, style: .continuous))
    }

    private func fill(pressed: Bool) -> Color {
        if prominent {
            return tint.opacity(pressed ? 0.24 : 0.14)
        }
        return Color.primary.opacity(pressed ? 0.12 : 0.06)
    }

    private var stroke: Color {
        prominent ? tint.opacity(0.35) : Color.primary.opacity(0.10)
    }
}

/// 弹窗底部的小文字按钮（设置 / 时钟 / 退出）。
struct TFFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension View {
    /// 设置面板里的分组卡片。
    func tfCard() -> some View {
        padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TFTheme.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: TFTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    /// 数值徽标（"96 pt" / "90%"）。
    func tfValueBadge() -> some View {
        font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 48, alignment: .trailing)
    }
}
