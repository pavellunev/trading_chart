import SwiftUI
import TradingChart

/// The drawing tools of the demo in one row of icons: horizontal line, trend line, ray, then the hint, then delete the selected
/// drawing and clear all. The active tool is highlighted; tapping it again cancels it.
struct DrawingToolbar: View {
    let model: TradingChartModel

    /// The side of a button.
    private static let side: CGFloat = 30

    var body: some View {
        HStack(spacing: 2) {
            tool(.horizontalLine, title: "Horizontal line", systemImage: "minus", id: "tool.horizontal")
            tool(.trendLine, title: "Trend line", systemImage: "chart.line.uptrend.xyaxis", id: "tool.trend")
            tool(.ray, title: "Ray", systemImage: "arrow.up.right", id: "tool.ray")
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .accessibilityIdentifier("drawing.hint")
            button(systemImage: "trash", title: "Delete selected drawing", id: "drawing.delete") {
                model.deleteSelectedDrawing()
            }
            .disabled(model.selectedDrawingID == nil)
            button(systemImage: "xmark.bin", title: "Clear all drawings", id: "drawing.clear") {
                model.removeAllDrawings()
            }
            .disabled(model.drawings.isEmpty)
        }
        .frame(height: Self.side + 4)
    }

    private var hint: String {
        if let kind = model.activeDrawingTool {
            kind == .horizontalLine ? "Tap the chart to place the line" : "Tap the chart twice: start, end"
        } else if model.selectedDrawingID != nil {
            "Drag a handle or the line"
        } else if model.drawings.isEmpty {
            "Pick a tool, then tap the chart"
        } else {
            "Tap a drawing to select it"
        }
    }

    private func button(systemImage: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .frame(width: Self.side, height: Self.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private func tool(_ kind: DrawingKind, title: String, systemImage: String, id: String) -> some View {
        let isActive = model.activeDrawingTool == kind
        return Button {
            model.activeDrawingTool = isActive ? nil : kind
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : Color.accentColor)
                .frame(width: Self.side, height: Self.side)
                .background(isActive ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
