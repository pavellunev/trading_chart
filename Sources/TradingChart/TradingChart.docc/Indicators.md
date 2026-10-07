# Indicators

Draw technical indicators over the price or in panes below it, and let the user choose them.

## Add indicators

Set ``TradingChartModel/indicators``:

```swift
model.indicators = [
    SMA(period: 20),
    EMA(period: 50),
    BollingerBands(period: 20, multiplier: 2),
    Volume(movingAveragePeriod: 20),
    RSI(period: 14),
    MACD(fast: 12, slow: 26, signal: 9),
]
```

An indicator whose ``ChartIndicator/id`` repeats one that is already in the list is dropped. The indicators are recalculated whenever the series changes (a tick, an appended bar, a prepended page); a live update costs about a millisecond for five indicators on 5,000 bars in a release build.

## The built-in indicators

| Indicator | Placement | Output |
| --- | --- | --- |
| ``SMA``, ``EMA``, ``WMA`` | overlay | one line; the price `source` and the line style are parameters |
| ``BollingerBands`` | overlay | the middle line, the two edges and a filled band between them; sigma is the population standard deviation |
| ``Volume`` | pane | a histogram tinted by the direction of each candle, and an optional moving average line |
| ``RSI`` | pane | one line on a fixed 0 to 100 scale with the overbought and oversold levels |
| ``MACD`` | pane | the MACD and signal lines and a histogram |

Bars inside the warm-up period of an indicator (the first 19 bars of a 20-bar average) have no value and are not drawn. The math is public in ``IndicatorMath`` if you need the numbers without a chart.

## Overlay or pane

An indicator with ``IndicatorPlacement/overlay`` is drawn over the price and shares its axis; its values take part in the autoscale. An indicator with ``IndicatorPlacement/pane`` gets a pane of its own below the price, with its own axis: the height is ``TradingChartConfiguration/paneHeight``, the panes scroll together with the price, and the crosshair runs through all of them. A pane indicator whose output has nothing to draw (a ``Volume`` of a series without volumes) gets no pane.

The legend row above each pane lists the values of its indicators: at the crosshair when there is one, at the newest bar otherwise.

## Colours

A line without an explicit colour takes the next colour of ``TradingChartTheme/indicatorPalette``. The palette is dealt out *per indicator*, in the order of ``TradingChartModel/indicators``: all three lines of Bollinger Bands share a colour, and the two lines of MACD differ because the signal line has ``IndicatorLine/paletteSlot`` 1. Give an indicator its colour explicitly through its style parameter (``IndicatorLineStyle``, or the `color` of ``BollingerBands``) to opt out.

## Letting the user choose

``IndicatorBar`` is a row of switches in the style of exchange apps. It lists the indicators of a catalog by their ``ChartIndicator/shortName``: the overlays first, a divider, then the panes. A tap adds or removes an indicator from ``TradingChartModel/indicators``, and the indicators stay in the order of the catalog.

```swift
import SwiftUI
import TradingChart

struct ChartScreen: View {
    let model: TradingChartModel

    private let catalog: [any ChartIndicator] = [
        SMA(), EMA(), BollingerBands(), Volume(movingAveragePeriod: 20), RSI(), MACD(),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TradingChartView(model: model)
            IndicatorBar(model: model, catalog: catalog) {
                Button("Settings", systemImage: "gearshape") { /* your settings */ }
            }
        }
    }
}
```

The chart can remember which indicators are on between launches: give ``ChartPersistence`` the same catalog (see <doc:Persistence>).

The font, the spacing, the height and the colours of the bar come from the theme (``TradingChartTheme/indicatorBarFont``, ``TradingChartTheme/indicatorBarSpacing``, ``TradingChartTheme/indicatorBarHeight``, ``TradingChartTheme/indicatorBarSelected``, ``TradingChartTheme/indicatorBarUnselected``, ``TradingChartTheme/indicatorBarDivider``).

To write your own indicator, see <doc:Extending>.
