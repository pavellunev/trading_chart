# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2026-10-07

### Added

- Built-in persistence of the chart's settings. Set `TradingChartConfiguration.persistence` to a `ChartPersistence` and the
  model restores the style, the indicators and (with a `drawingsKey`) the drawings the user left, and saves them again when
  they change: no code on the host's side besides that one setting. The indicators come back from the catalog of the
  `IndicatorBar` by `id`, in the order of the catalog. The drawings are saved when one is added, changed (at the end of a drag)
  or removed, and follow `drawingsKey`, so a chart that changes its symbol keeps the drawings of each. The records are small
  versioned JSON values in a `ChartPreferencesStore` (`UserDefaultsChartPreferencesStore` by default; implement the protocol to
  keep them elsewhere); damaged or foreign data is ignored.

## [0.1.2] - 2026-10-07

### Fixed

- The package compiles with Xcode 26 (Swift 6.2): a closure in the overlay of the main pane captured a local constant
  declared after it, which Swift 6.2 rejects.

### Changed

- The requirements name the oldest toolchain the package is built with in CI: Xcode 26 (Swift 6.2).

## [0.1.1] - 2026-10-07

### Fixed

- A chart inside a vertical scroll view (a SwiftUI `ScrollView`, a `List`, a `UIScrollView`) no longer scrolls the page along with
  itself. A horizontal drag on the chart scrolls only the chart and a vertical one only the page (which starts at once); while the
  crosshair (long press and drag), a pinch or the drag of a drawing is in progress the page stays still. A chart with no scroll
  view around it, or one in a scroll view that cannot scroll vertically (a horizontal pager, a `ScrollView` with
  `.scrollDisabled(true)`), takes a drag in any direction as before.

### Changed

- A horizontal scroll view above the chart (a paged `TabView`, a horizontal `ScrollView`) no longer flips together with the
  chart: a horizontal drag that starts on the chart scrolls the chart and not the pager, and the pager's own drag begins only
  where the chart is not under the finger. This is the same arbitration as for a vertical page, and it applies to every
  `UIScrollView` above the chart.

## [0.1.0] - 2026-10-07

The first version.

### Added

- `TradingChartView` and `TradingChartModel`: a scrollable chart in the line, area and candlestick styles, built on Swift
  Charts. The chart UI needs iOS 17 or later; the package can be added to apps that target iOS 16 (every type of the UI is
  `@available(iOS 17.0, *)`, so gate it with `if #available(iOS 17, *)`).
- Bad data is kept out of a series: a candle or a point with a time or a price that is not finite is dropped, a candle whose
  `high` or `low` does not enclose its other prices is repaired, and such an update is ignored.
- Live updates: `update(price:at:volume:)`, `update(_:interval:)` for candles and points with an interval gate, a window that
  follows the live edge, a dashed current price line and a price badge on the price axis, and
  `maxLiveBarCount` to cap a growing series.
- `setSeries(_:scroll:)` with the scroll behaviours `automatic`, `liveEdge` and `preserve`; the scroll anchor changes in the same
  mutation as the data.
- History paging: `TradingChartEvent.approachedHistoryStart`, `prependHistory(_:)`, `isLoadingHistory`, `hasMoreHistory`,
  `historyPrefetchThreshold` and a loading indicator. Prepending history does not move the window, and a live update never
  trims the bars the user is looking at.
- Touch scrolling with inertia, pinch zoom (`zoom(by:anchor:)`) and a crosshair (long press and drag) with a tooltip (open, high,
  low, close, change, range, volume) and legends with the values of the indicators.
- Indicators: `SMA`, `EMA`, `WMA`, `BollingerBands`, `Volume`, `RSI` and `MACD` as overlays and as panes that scroll together
  with the price, and the `ChartIndicator` protocol (with `shortName`) for your own, with lines, bands, histograms, levels and
  fixed ranges as output.
- `IndicatorBar`, a row of indicator switches in the style of exchange apps, and `SeriesStylePicker` with
  `StylePickerOptions`, a menu of the chart styles on the chart.
- Drawing tools: horizontal line, trend line and ray, created with taps, selected and dragged by anchor or body, with
  `Codable` drawings, `DrawingEvent`s and the `DrawingTool` protocol with `DrawingToolRegistry` for custom tools.
- The highest and the lowest price of the window labelled (`showsHighLowMarkers`), buy and sell markers (`ChartMarker`).
- `TradingChartTheme`, `PriceFormatter` (with the `compact` context for volumes and indicator values) and `TimeFormatter`,
  injected through the SwiftUI environment; light and dark appearance.
- VoiceOver: a label and a value for the chart, scrolling by a window width and named actions.
- `TradingChartStrings` and the `tradingChartStrings(_:)` modifier: every word the chart says (VoiceOver texts, the
  "Scroll to latest" badge, the loading spinner, the rows of the tooltip, the entries of the style picker), replaceable.
- Localization: the words of the chart are translated into 14 languages (English, German, Spanish, French, Hindi, Indonesian,
  Italian, Dutch, Brazilian Portuguese, Russian, Turkish, Vietnamese, Simplified Chinese and Arabic) by a String Catalog in the
  package. `TradingChartStrings.standard` is in the language of the app (the one its main bundle is localized to), worked out
  once; `TradingChartStrings.localized(for:)` is in the language of a locale, for an app with an in-app language. `StylePickerOptions` takes its titles and label from the strings
  (`titles` and `accessibilityLabel` replace them; `accessibilityLabel` is optional).
- Right-to-left: the chart is never mirrored (time runs from left to right, the price scale stays at the right); the words of the
  tooltip follow the layout direction of the host.
- `ChartInterval` has an `origin`: buckets start on a grid in UTC, and `.weeks(_:startingOn:)` starts on Monday by default
  (or on the weekday of your exchange); `ChartSeries.empty(interval:kind:)` makes an empty series of candles (the default)
  or of points. A series that has bars keeps its kind, and a page of the other kind passed to `prepend(_:)` /
  `prependHistory(_:)` is converted to it rather than dropped (candles to points by close; points to flat candles, moved to the
  start of their bucket and merged within a bucket).
- Three library products: `TradingChart`, `TradingChartCore` (Foundation and CoreGraphics only) and
  `TradingChartIndicators`; the last two support iOS 16.
- DocC catalogs with articles, `Docs/Architecture.md`, `Docs/Performance.md`, and a demo app in `Examples/TradingChartDemo`.
- `scripts/verify.sh` (build, tests and the demo build) and a GitHub Actions workflow that runs it.

### Known limitations

- Monthly bars are not supported: a month is not a fixed number of seconds, and a `ChartInterval` is.
- `onEvent` holds one handler; the model does not have several subscribers.

[Unreleased]: https://github.com/pavellunev/trading_chart/compare/0.1.3...HEAD
[0.1.3]: https://github.com/pavellunev/trading_chart/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/pavellunev/trading_chart/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/pavellunev/trading_chart/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/pavellunev/trading_chart/releases/tag/0.1.0
