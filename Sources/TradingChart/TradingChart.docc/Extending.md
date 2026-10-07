# Extending the chart

Write your own indicators and drawing tools.

## A custom indicator

An indicator is a pure function from bars to something drawable. Conform to ``ChartIndicator`` and return an ``IndicatorOutput`` from ``ChartIndicator/calculate(_:)``. It must be `Sendable` and deterministic: the chart recalculates it whenever the series changes, and caches the result by ``ChartIndicator/id``.

An output can hold any mix of:

- ``IndicatorLine``: a polyline of ``IndicatorValue``s with a ``IndicatorLineStyle`` (colour, width, dash);
- ``IndicatorBand``: a filled area between two edges, like Bollinger Bands;
- ``IndicatorHistogram``: bars of ``HistogramBar``s measured from a baseline, tinted by their ``HistogramTone``;
- ``IndicatorLevel``: a dashed horizontal reference line such as the 70 and 30 of RSI;
- ``IndicatorOutput/fixedRange``: a fixed scale for a pane, instead of the autoscale.

Rules that keep an indicator well behaved:

- ``ChartIndicator/id`` is made of the type and every parameter that changes the output (`"donchian(20)"`). Two indicators with the same id are the same indicator. Ids of lines, bands and histograms are unique within the output.
- Leave the bars of the warm-up period out of the lines instead of filling them with zeros.
- ``IndicatorInput/candles`` is oldest first. A series of points is expanded into candles with equal open, high, low and close and no volume, so an indicator works on any series.
- ``ChartIndicator/shortName`` is the label in an ``IndicatorBar`` and defaults to ``ChartIndicator/displayName``.

### An overlay

This draws the Donchian channel, the highest high and the lowest low of the last `period` bars, over the price:

```swift
import SwiftUI
import TradingChart

struct DonchianChannel: ChartIndicator {
    var period = 20
    var color: ChartColor?   // nil takes the next colour of the theme's palette

    var id: String { "donchian(\(period))" }
    var displayName: String { "Donchian \(period)" }
    var shortName: String { "DC" }
    var placement: IndicatorPlacement { .overlay }

    func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let candles = input.candles
        var upper: [IndicatorValue] = []
        var lower: [IndicatorValue] = []
        var middle: [IndicatorValue] = []
        for index in candles.indices.dropFirst(max(period, 1) - 1) {
            let window = candles[(index - max(period, 1) + 1)...index]
            let high = window.map(\.high).max() ?? candles[index].high
            let low = window.map(\.low).min() ?? candles[index].low
            let time = candles[index].time
            upper.append(IndicatorValue(time: time, value: high))
            lower.append(IndicatorValue(time: time, value: low))
            middle.append(IndicatorValue(time: time, value: (high + low) / 2))
        }
        let edge = IndicatorLineStyle(color: color, width: 1)
        return IndicatorOutput(
            lines: [
                IndicatorLine(id: "\(id).upper", name: "Upper", values: upper, style: edge),
                IndicatorLine(id: "\(id).lower", name: "Lower", values: lower, style: edge),
                IndicatorLine(
                    id: "\(id).middle",
                    name: "Middle",
                    values: middle,
                    style: IndicatorLineStyle(color: color, width: 1, dash: [4, 3])
                ),
            ],
            bands: [IndicatorBand(id: "\(id).band", upper: upper, lower: lower, fill: color)]
        )
    }
}
```

### A pane

An indicator with ``IndicatorPlacement/pane`` gets a pane of its own. This one shows the percentage change of the close over `period` bars as a histogram, with a line at zero:

```swift
import SwiftUI
import TradingChart

struct RateOfChange: ChartIndicator {
    var period = 12

    var id: String { "roc(\(period))" }
    var displayName: String { "ROC \(period)" }
    var placement: IndicatorPlacement { .pane }

    func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let candles = input.candles
        var bars: [HistogramBar] = []
        for index in candles.indices.dropFirst(max(period, 1)) {
            let previous = candles[index - max(period, 1)].close
            guard previous != 0 else { continue }
            let change = (candles[index].close - previous) / previous * 100
            bars.append(HistogramBar(time: candles[index].time, value: change, tone: change >= 0 ? .positive : .negative))
        }
        return IndicatorOutput(
            histograms: [IndicatorHistogram(id: "\(id).histogram", name: "ROC", bars: bars)],
            levels: [IndicatorLevel(id: "\(id).zero", value: 0)]
        )
    }
}
```

Add either to the chart like a built-in one: `model.indicators = [DonchianChannel(period: 20), RateOfChange()]`.

## A custom drawing tool

A ``DrawingTool`` turns the anchors of a drawing into shapes in chart coordinates (``DrawingPrimitive``: a segment between two anchors, a horizontal line at a price, a vertical line at a time). The package does the rest: it clips the shapes to the window, maps them to the screen on every frame, hit-tests them for selection and dragging, and snaps the anchors to the bars in time.

```swift
import TradingChart

struct RectangleTool: DrawingTool {
    var kind: DrawingKind { "rectangle" }
    var requiredAnchorCount: Int { 2 }

    func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        guard anchors.count >= 2 else { return [] }
        let first = anchors[0]
        let second = anchors[1]
        let topLeft = ChartAnchor(time: first.time, price: first.price)
        let topRight = ChartAnchor(time: second.time, price: first.price)
        let bottomRight = ChartAnchor(time: second.time, price: second.price)
        let bottomLeft = ChartAnchor(time: first.time, price: second.price)
        return [
            .segment(topLeft, topRight), .segment(topRight, bottomRight),
            .segment(bottomRight, bottomLeft), .segment(bottomLeft, topLeft),
        ]
    }
}

@MainActor
func enableRectangles(on model: TradingChartModel) {
    model.drawingTools.register(RectangleTool())
    model.activeDrawingTool = "rectangle"
}
```

- ``DrawingKind`` is an open set, like `Notification.Name`: it is `ExpressibleByStringLiteral` and `Codable`, and the name is what is saved with a drawing.
- ``DrawingTool/requiredAnchorCount`` is the number of taps that create the drawing.
- ``DrawingTool/primitives(for:in:)`` gets the ``ChartDomain`` (the visible extent) so that open-ended shapes such as a ray can run to its edge. Return an empty array while there are too few anchors.
- Selection and dragging need nothing more: the default ``DrawingTool/hitTest(_:anchors:domain:transform:tolerance:)`` finds an anchor first and then the body by the distance to the shapes. It is a requirement of the protocol, so a tool can implement it itself (a filled shape, a bigger target) and the chart uses that one.

## Formatting and colours

Prices and times are formatted by a ``PriceFormatter`` and a ``TimeFormatter`` set through the environment, and colours come from the ``TradingChartTheme``; see <doc:Customization>. ``ChartColor`` is a colour that does not depend on a UI framework, so an indicator in `TradingChartIndicators` or `TradingChartCore` can carry one: create it from components or from a hex string, `ChartColor(hex: "#F0B90B")`.
