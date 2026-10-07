# Live data and history

Keep the chart up to date with a feed, and load older bars as the user scrolls back.

## Replace or update

``TradingChartModel/setSeries(_:scroll:)`` replaces the whole series. Use it for the first load, a new symbol and a new interval. The update methods change only the newest bar, or append one:

| Method | Use it for |
| --- | --- |
| ``TradingChartModel/update(price:at:volume:)`` | a trade or a quote tick: it goes into the bar its time falls into, or starts a new bar |
| ``TradingChartModel/update(_:interval:)-(Candle,_)`` | a candle from a stream: it replaces the last bar, is appended when newer, and is dropped when older |
| ``TradingChartModel/update(_:interval:)-(PricePoint,_)`` | the same for a point of a line series |

```swift
@MainActor
func receive(price: Double, at time: Date, size: Double, into model: TradingChartModel) {
    model.update(price: price, at: time, volume: size)
    model.currentPrice = price
}
```

### The interval gate

The candle and point methods take the interval the bar was built for. When it is not the interval of the series on the screen the update is dropped and ``ChartSeries/UpdateResult/ignored`` is returned. This guards against the usual race of a feed: the user switches from 1m to 5m, the request for the 5m series is in flight, and a 1m candle arrives. Pass the interval of the stream with every candle.

```swift
@MainActor
func receive(candle: Candle, builtFor interval: ChartInterval, into model: TradingChartModel) {
    model.update(candle, interval: interval)
}
```

``TradingChartModel/update(price:at:volume:)`` has no interval parameter: the tick is placed by the interval of the series.

## The live edge

The window is at the *live edge* when the newest bar is at its right edge, with a small tolerance (``ViewportConfiguration/liveEdgeToleranceBars``). Then:

- a tick or a new bar keeps the newest bar where it is, so the chart follows the feed;
- ``TradingChartModel/isAtLiveEdge`` is `true`.

When the user scrolls into the history the window stays still, new bars appear off to the right, and the price badge turns into a button with a chevron that calls ``TradingChartModel/scrollToLiveEdge()``. ``TradingChartEvent/liveEdgeChanged(_:)`` reports the change.

The scroll position moves in the same synchronous mutation as the data, so the chart never draws a frame with new data and the old window. ``TradingChartModel/setSeries(_:scroll:)`` follows the same rule by default (``TradingChartModel/ScrollBehavior/automatic``: to the live edge when the interval changed or the window was at the live edge); say ``TradingChartModel/ScrollBehavior/liveEdge`` or ``TradingChartModel/ScrollBehavior/preserve`` to override.

### How many bars are kept

``TradingChartConfiguration/maxLiveBarCount`` (600 by default) caps the series while it grows at the live edge: the oldest bars are dropped. A live update never trims the bars the user is looking at or has just scrolled past, so the series may be longer than the cap while the window is in the history. While ``TradingChartModel/isLoadingHistory`` is `true` nothing is trimmed at all: a page of history ends at the first bar you had when you asked for it, and a bar cut off from the head meanwhile would leave a hole between the page and the series. The next update after the request trims the surplus.

## Trade markers

``TradingChartModel/markers`` takes ``ChartMarker`` values: a buy (**B**) is drawn above its price, a sell (**S**) below it. Without a `price` the marker snaps to the series at its time.

```swift
model.markers = [
    ChartMarker(id: "b1", time: buyTime, kind: .buy),
    ChartMarker(id: "s1", time: sellTime, price: 121_345.5, kind: .sell, label: "TP"),
]
```

## Loading older history

When the left edge of the window gets within ``TradingChartConfiguration/historyPrefetchThreshold`` of the oldest loaded bar (one window width by default, so that even a fast fling does not reach the end before the data arrives), the model sends ``TradingChartEvent/approachedHistoryStart``. Load an older page, then call ``TradingChartModel/prependHistory(_:)``:

```swift
@MainActor
func loadOlderHistory(into model: TradingChartModel) {
    guard let oldest = model.series.firstTime else { return }
    model.isLoadingHistory = true
    let interval = model.series.interval
    Task {
        let page: [Candle] = await loadCandles(before: oldest, count: 300)   // your data source
        if page.isEmpty {
            model.hasMoreHistory = false
            model.isLoadingHistory = false
        } else {
            model.prependHistory(ChartSeries(candles: page, interval: interval))
        }
    }
}
```

Call it from the `.approachedHistoryStart` case of the handler of ``TradingChartModel/onEvent``, which is described in [Handling events](#Handling-events).

- Set ``TradingChartModel/isLoadingHistory`` to `true` when you start a request. The chart shows a spinner at the left edge, and sends no second event while the request is running.
- ``TradingChartModel/prependHistory(_:)`` takes only the bars older than the first one, so pages that overlap are safe. A page of the other kind (points for candles, candles for points) is taken too, converted to the kind of the series: candles become points at their close, points become flat candles, moved to the start of their bucket (the points of one bucket make one candle). The window does not move: ``TradingChartModel/scrollPosition`` and ``TradingChartModel/visibleTimeRange`` are the same before and after, and the indicators are recalculated over the longer series. It also resets `isLoadingHistory`, as does ``TradingChartModel/setSeries(_:scroll:)``. If a request fails, reset it yourself.
- Set ``TradingChartModel/hasMoreHistory`` to `false` when the source has nothing older, and back to `true` for a new instrument.
- The event is sent once per request: a new series, a page that adds bars, the end of a request or `hasMoreHistory` turning `true` allow the next one.

## Handling events

``TradingChartModel/onEvent`` holds one handler: assigning it again replaces the previous one. Handle every event you need in a single `switch`, or the last assignment wins and, say, the paging stops:

```swift
import Foundation
import TradingChart

@MainActor func loadOlderHistory(into model: TradingChartModel) { /* see above */ }
@MainActor func saveDrawings(of model: TradingChartModel) { /* see <doc:Drawings> */ }

@MainActor
func observe(_ model: TradingChartModel) {
    model.onEvent = { [weak model] event in
        guard let model else { return }
        switch event {
        case .approachedHistoryStart:
            loadOlderHistory(into: model)
        case .drawing(.added), .drawing(.changed), .drawing(.removed):
            saveDrawings(of: model)
        case .drawing:
            break
        case .crosshairChanged(let state):
            print(state?.time as Any)
        case .liveEdgeChanged(let isAtLiveEdge):
            print("at the live edge:", isAtLiveEdge)
        }
    }
}
```
