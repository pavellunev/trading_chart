# Drawings

Let the user draw horizontal lines, trend lines and rays on the chart, and save what they drew.

## Tools and your own toolbar

Three tools ship with the package: ``DrawingKind/horizontalLine`` (one tap), ``DrawingKind/trendLine`` and ``DrawingKind/ray`` (two taps each). The package has no toolbar: you decide how the user picks a tool and tell the model with ``TradingChartModel/activeDrawingTool``.

```swift
import SwiftUI
import TradingChart

struct DrawingToolbar: View {
    let model: TradingChartModel

    var body: some View {
        HStack(spacing: 20) {
            tool("minus", .horizontalLine)
            tool("chart.line.uptrend.xyaxis", .trendLine)
            tool("arrow.up.right", .ray)
            Button("Delete", systemImage: "trash") { model.deleteSelectedDrawing() }
                .disabled(model.selectedDrawingID == nil)
        }
        .labelStyle(.iconOnly)
    }

    private func tool(_ symbol: String, _ kind: DrawingKind) -> some View {
        let isActive = model.activeDrawingTool == kind
        return Button {
            model.activeDrawingTool = isActive ? nil : kind
        } label: {
            Image(systemName: symbol)
        }
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
    }
}
```

With a tool active, each tap on the chart places an anchor. The last anchor adds the drawing, selects it and ends the tool; ``DrawingEvent/added(_:)`` is sent. Setting the tool to `nil` cancels a half-placed drawing. A drag still scrolls the chart, and the crosshair and the pinch work as usual.

## Selecting and editing

A tap on a drawing selects it (``TradingChartModel/selectedDrawingID``), a tap on empty space clears the selection. A selected drawing shows handles on its anchors. A drag that starts on a handle moves that anchor; a drag that starts on the body moves the whole drawing; any other drag scrolls the chart. Anchors snap to the bars in time and are free in price. A drawing with ``ChartDrawing/isLocked`` can be selected but not moved.

``TradingChartModel/deleteSelectedDrawing()``, ``TradingChartModel/removeDrawing(id:)`` and ``TradingChartModel/removeAllDrawings()`` delete drawings. ``TradingChartModel/drawings`` is the whole list, and you can assign it.

The model reports changes as ``TradingChartEvent/drawing(_:)`` with a ``DrawingEvent``: ``DrawingEvent/added(_:)``, ``DrawingEvent/changed(_:)`` (at the end of a drag, not on every step of it), ``DrawingEvent/removed(_:)`` and ``DrawingEvent/selectionChanged(_:)``.

Set ``TradingChartConfiguration/isDrawingEnabled`` to `false` to turn creating and editing off. Drawings you assigned to ``TradingChartModel/drawings`` stay visible.

## Saving drawings

``ChartDrawing`` is `Codable` and anchored to absolute times and prices, so drawings survive scrolling, zooming and changes of the interval and the style.

```swift
import Foundation
import TradingChart

@MainActor
func restoreDrawings(into model: TradingChartModel) {
    if let data = UserDefaults.standard.data(forKey: "drawings"),
       let saved = try? JSONDecoder().decode([ChartDrawing].self, from: data) {
        model.drawings = saved
    }
}

@MainActor
func saveDrawings(of model: TradingChartModel) {
    if let data = try? JSONEncoder().encode(model.drawings) {
        UserDefaults.standard.set(data, forKey: "drawings")
    }
}
```

Call `saveDrawings` from the `.drawing(.added)`, `.drawing(.changed)` and `.drawing(.removed)` cases of the handler of ``TradingChartModel/onEvent``. There is one handler (assigning it again replaces the previous one), so handle every event you need in the same `switch`; see <doc:LiveData>.

A drawing can also be created in code:

```swift
model.drawings.append(
    ChartDrawing(
        kind: .horizontalLine,
        anchors: [ChartAnchor(time: .now, price: 120_000)],
        style: DrawingStyle(lineWidth: 1, dash: [6, 4])
    )
)
```

Drawings of a custom kind are saved with the name of the kind. Register the tool again (``TradingChartModel/drawingTools``) before you restore them; a drawing whose tool is not registered is kept but not drawn. See <doc:Extending> for writing a tool.
