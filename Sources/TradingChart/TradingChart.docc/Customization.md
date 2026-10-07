# Customization

Change how the chart looks, how it formats numbers and dates, and what it shows.

## Theme

``TradingChartTheme`` holds the colours, fonts and strokes of the chart. Start from ``TradingChartTheme/standard``, which adapts to light and dark appearance, change what you need, and attach it to a view with the `tradingChartTheme(_:)` modifier. It goes through the SwiftUI environment, so it applies to every chart below that view.

```swift
import SwiftUI
import TradingChart

struct ThemedChart: View {
    let model: TradingChartModel

    private var theme: TradingChartTheme {
        var theme = TradingChartTheme.standard
        theme.bullish = Color(red: 0.03, green: 0.78, blue: 0.51)
        theme.bearish = Color(red: 0.96, green: 0.27, blue: 0.36)
        theme.lineInterpolation = .catmullRom
        theme.indicatorPalette = [.orange, .purple, .teal]
        return theme
    }

    var body: some View {
        TradingChartView(model: model)
            .tradingChartTheme(theme)
    }
}
```

The theme covers the candles (``TradingChartTheme/bullish``, ``TradingChartTheme/bearish``, ``TradingChartTheme/candleBodyWidthFactor``), the line and the area gradient (``TradingChartTheme/line``, ``TradingChartTheme/areaTopOpacity``, ``SeriesInterpolation``), the grid and the axes, the price badge and the price line, the crosshair, the legends and the tooltip, the labels of the window's high and low, the markers, the palette that indicator lines take their colours from, the drawings, and the fonts and colours of ``IndicatorBar``.

## Number and time formats

``PriceFormatter`` turns prices into text and ``TimeFormatter`` turns times into text. Both are told where the text goes, so one formatter can show fewer digits on the axis than in the badge:

```swift
TradingChartView(model: model)
    .tradingChartPriceFormatter(PriceFormatter { value, context in
        switch context {
        case .compact: value.formatted(.number.notation(.compactName))   // volumes, indicator panes
        default: value.formatted(.currency(code: "USD"))
        }
    })
    .tradingChartTimeFormatter(TimeFormatter { date, interval, context in
        context == .crosshair
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .omitted, time: .shortened)
    })
```

The defaults, ``PriceFormatter/automatic`` and ``TimeFormatter/automatic``, pick the number of decimals from the magnitude of the price (and follow the locale), and the time format from the interval. ``PriceFormatter/fractionDigits(_:)`` always shows the same number of decimals.

## Strings

What the chart says by itself (what VoiceOver reads and offers, the "Scroll to latest" badge, the "Loading history" spinner, the rows of the crosshair tooltip, the entries of the style picker) is translated into 14 languages (English, German, Spanish, French, Hindi, Indonesian, Italian, Dutch, Brazilian Portuguese, Russian, Turkish, Vietnamese, Simplified Chinese and Arabic) by resources of the package. ``TradingChartStrings/standard`` is in the language of the app (the one its main bundle is localized to, so an app that is only in English gets English whatever the device is set to), which is what the chart says when nothing is set. An app with a language of its own passes it with the `tradingChartStrings(_:)` modifier and ``TradingChartStrings/localized(for:)``; a locale that the package has no language for gets English. Change single words on top of a language:

```swift
struct LocalizedChart: View {
    let model: TradingChartModel
    let appLocale: Locale

    var body: some View {
        TradingChartView(model: model)
            .tradingChartStrings(strings)
    }

    private var strings: TradingChartStrings {
        var strings = TradingChartStrings.localized(for: appLocale)
        strings.scrollToLatest = String(localized: "chart.scrollToLatest")
        strings.volume = String(localized: "chart.volume")
        return strings
    }
}
```

A string with `%@` is a format (the last price, the two ends of the visible range): keep the placeholders, and reorder them with `%1$@` and `%2$@` when your language needs another order.

The chart is never mirrored in a right-to-left language: time runs from left to right and the price scale stays at the right. Only the words of the crosshair tooltip are laid out as the layout direction of your app says. The time axis and the prices follow the locale of the device; give the chart your own ``TimeFormatter`` and ``PriceFormatter`` to format them for another one.

## Configuration

``TradingChartConfiguration`` switches features on and off and sets the geometry. Pass it to ``TradingChartModel/init(series:style:configuration:)``, or change ``TradingChartModel/configuration`` later:

```swift
var configuration = TradingChartConfiguration()
configuration.maxLiveBarCount = 1_000
configuration.paneHeight = 80
configuration.showsHighLowMarkers = false
configuration.isDrawingEnabled = false
configuration.viewport.candleVisibleBars = 50
let model = TradingChartModel(style: .candles, configuration: configuration)
```

| Option | Effect |
| --- | --- |
| ``TradingChartConfiguration/showsCurrentPriceLine``, ``TradingChartConfiguration/showsPriceBadge`` | the dashed line at the current price and its badge on the price axis |
| ``TradingChartConfiguration/showsLegend`` | the legend rows above the panes and the tooltip of the crosshair |
| ``TradingChartConfiguration/showsHighLowMarkers`` | labels at the highest and the lowest price of the window |
| ``TradingChartConfiguration/isCrosshairEnabled``, ``TradingChartConfiguration/isZoomEnabled``, ``TradingChartConfiguration/isDrawingEnabled``, ``TradingChartConfiguration/isHapticsEnabled`` | the interactions |
| ``TradingChartConfiguration/paneHeight`` | the height of every indicator pane |
| ``TradingChartConfiguration/viewport`` | the number of bars in the window, its limits when zooming, and the gap at the live edge (see ``ViewportConfiguration``) |
| ``TradingChartConfiguration/historyPrefetchThreshold``, ``TradingChartConfiguration/historyReserveBars`` | paging of history, see <doc:LiveData> |
| ``TradingChartConfiguration/maxLiveBarCount`` | how many bars a growing live series keeps |
| ``TradingChartConfiguration/renderBufferWindows`` | how far outside the window the marks are built, a trade of memory and rebuilds for scroll smoothness |

## Style picker

``SeriesStylePicker`` is a small icon that opens a menu of the chart styles (line, area, candles). Set ``TradingChartConfiguration/stylePicker`` to show it in the legend row of the main pane, or place the same view in a toolbar of your own. The titles and the label are the words of ``TradingChartStrings`` (translated, in the language of the chart); pass your own through ``StylePickerOptions/titles`` and ``StylePickerOptions/accessibilityLabel`` to replace them.

```swift
var configuration = TradingChartConfiguration()
configuration.stylePicker = StylePickerOptions(
    availableStyles: [.area, .candles],
    titles: [.area: String(localized: "Line")],
    accessibilityLabel: String(localized: "Chart style")
)
```

## Accessibility

The chart is one accessibility element with a label (the style) and a value (the last price and the visible range). VoiceOver can scroll it by a window width with the three-finger scroll gesture, and offers the actions *Show earlier bars*, *Show later bars* and *Show latest bar*; the range is announced after every move. All of these words are in ``TradingChartStrings``.
