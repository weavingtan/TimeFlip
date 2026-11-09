import SwiftUI

/// 挂件窗口的唯一根视图模型：每秒只更新 `render`，
/// 保证 FlipDigitView 的 @State（翻页动画进度）不会被整体重建掉。
@MainActor
final class ClockDisplayModel: ObservableObject {
    @Published var render: ClockRenderModel
    @Published var fill: CGSize
    @Published var repositioning: Bool

    init(render: ClockRenderModel, fill: CGSize, repositioning: Bool = false) {
        self.render = render
        self.fill = fill
        self.repositioning = repositioning
    }
}

struct ClockHostView: View {
    @ObservedObject var display: ClockDisplayModel

    var body: some View {
        FlipClockView(model: display.render)
            .frame(width: display.fill.width, height: display.fill.height)
            .overlay {
                if display.repositioning {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                        )
                        .padding(3)
                }
            }
    }
}
