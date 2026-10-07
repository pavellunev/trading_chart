# Getting started

Add the package, show a chart, and feed it data.

## Add the package

In Xcode choose **File > Add Package Dependencies...**, enter `https://github.com/pavellunev/trading_chart`, pick **Up to Next Minor Version** from `0.1.0` and add the `TradingChart` product to your app target. In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pavellunev/trading_chart", .upToNextMinor(from: "0.1.1")),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "TradingChart", package: "trading_chart"),
        ]
    ),
]
```

The chart UI (the `TradingChart` module) needs iOS 17 or later; `TradingChartCore` and `TradingChartIndicators` need iOS 16 or later. The package needs a Swift 6 toolchain.

### Apps that target iOS 16

The package can be added to an app that targets iOS 16. Every type of the chart UI is marked `@available(iOS 17.0, *)`, so gate the chart with `if #available(iOS 17, *)` and show something else on iOS 16:

```swift
import SwiftUI
import TradingChart

struct ChartScreen: View {
    var body: some View {
        if #available(iOS 17, *) {
            NativeChart()
        } else {
            Text("The chart needs iOS 17")   // your fallback
        }
    }
}

@available(iOS 17, *)
struct NativeChart: View {
    @State private var model = TradingChartModel(style: .candles)

    var body: some View {
        TradingChartView(model: model)
    }
}
```

## Show a line chart

A chart is a ``TradingChartView`` that shows a ``TradingChartModel``. Keep the model in `@State` (or in your own observable object) and give it a ``ChartSeries``:

```swift
import SwiftUI
import TradingChart

struct PriceChart: View {
    @State private var model = TradingChartModel(style: .line)

    var body: some View {
        TradingChartView(model: model)
            .frame(height: 320)
            .task {
                let points: [PricePoint] = await loadPoints()   // your data source
                model.setSeries(ChartSeries(points: points, interval: .minutes(5)))
                model.currentPrice = points.last?.value
            }
    }
}
```

``TradingChartModel/currentPrice`` draws the dashed price line and the badge on the price axis; leave it `nil` to show neither.

## Show candles

Use ``Candle`` values and the ``SeriesStyle/candles`` style:

```swift
import SwiftUI
import TradingChart

struct CandleChart: View {
    @State private var model = TradingChartModel(style: .candles)

    var body: some View {
        TradingChartView(model: model)
            .frame(height: 420)
            .task {
                let candles: [Candle] = await loadCandles()   // your data source
                model.setSeries(ChartSeries(candles: candles, interval: .minutes(15)))
                model.currentPrice = candles.last?.close
            }
    }
}
```

The ``Candle/time`` of a candle, or of a ``PricePoint``, is the start of its bucket: 12:15:00 for a 15-minute bar. A ``ChartSeries`` sorts its bars and keeps one bar per timestamp. A series that carries candles can also be drawn as a line or an area (change ``TradingChartModel/style``); a series of points is drawn as a line even in the candles style.

The ``ChartInterval`` belongs to the series: everything that depends on the size of a bar (the window, the axes, the width of a candle, live ticks) is derived from ``ChartSeries/interval``. Bars start on a fixed grid in UTC: days at midnight, and weeks on Monday (``ChartInterval/weeks(_:startingOn:)`` takes the weekday an exchange starts its week on). A live tick falls into the bucket of that grid, so it has to be the grid the candles of your data source are on. Monthly bars are not supported in this version.

A bar the chart cannot draw never gets into a series: a candle or a point whose time or price is not finite (`nan`, `inf`) is dropped, a candle whose `high` is below its `low` is repaired, and an update with such values is ignored (``ChartSeries/UpdateResult/ignored``).

A new model starts with an empty series of candles (``ChartSeries/empty(interval:kind:)``), so the first tick opens a candle and a page of candles can be prepended afterwards; ask for ``ChartSeries/Kind/points`` for a line series that never has candles. Once a series has bars it keeps its kind: ``TradingChartModel/prependHistory(_:)`` converts a page of the other kind to it (candles to points by close, points to flat candles on the grid of the interval), so a page is never dropped.

## Add indicators

Set ``TradingChartModel/indicators``. Overlays such as ``SMA`` or ``BollingerBands`` are drawn over the price; ``Volume``, ``RSI`` and ``MACD`` get a pane of their own below it.

```swift
model.indicators = [SMA(period: 20), BollingerBands(), Volume(movingAveragePeriod: 20), RSI(), MACD()]
```

For a row of switches that lets the user choose, use ``IndicatorBar``. See <doc:Indicators>.

## Where next

- <doc:LiveData> keeps the chart up to date with a feed, and loads older history on demand.
- <doc:Customization> changes colours, number formats and what the chart shows.
- <doc:Indicators> and <doc:Extending> cover the built-in indicators and writing your own.
- <doc:Drawings> adds drawing tools.
