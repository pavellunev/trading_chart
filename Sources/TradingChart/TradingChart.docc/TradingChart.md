# ``TradingChart``

A native SwiftUI trading chart for iOS: candlesticks, lines and areas, technical indicators, a crosshair, pinch zoom, drawing tools and paged history, built on Swift Charts.

## Overview

A ``TradingChartView`` draws a ``TradingChartModel``. The model owns the data (a ``ChartSeries``), the scroll position, the indicators, the markers and the drawings; the view shows them and reports what the user does back to the model.

```swift
import SwiftUI
import TradingChart

struct ChartScreen: View {
    @State private var model = TradingChartModel(style: .candles)

    var body: some View {
        TradingChartView(model: model)
            .frame(height: 420)
            .task {
                let candles: [Candle] = await loadCandles()   // your data source
                model.setSeries(ChartSeries(candles: candles, interval: .minutes(15)))
                model.indicators = [SMA(period: 20), Volume(), RSI()]
            }
    }
}
```

The package is made of three modules. `TradingChartCore` holds the data model, the viewport math, the indicator types and the drawing model, and needs only Foundation and CoreGraphics. `TradingChartIndicators` holds the built-in indicators and their math. `TradingChart` is the SwiftUI layer, and it re-exports the other two: `import TradingChart` gives you everything on this page. The SwiftUI layer needs iOS 17; the other two modules run on iOS 16, and an app that targets iOS 16 gates the chart with `if #available(iOS 17, *)` (see <doc:GettingStarted>).

Start with <doc:GettingStarted>. The architecture, the scroll patterns and the rendering are described in [Architecture](https://github.com/pavellunev/trading_chart/blob/main/Docs/Architecture.md); the measurements in [Performance](https://github.com/pavellunev/trading_chart/blob/main/Docs/Performance.md).

## Topics

### Essentials

- <doc:GettingStarted>
- ``TradingChartView``
- ``TradingChartModel``
- ``TradingChartConfiguration``

### Guides

- <doc:LiveData>
- <doc:Customization>
- <doc:Persistence>
- <doc:Indicators>
- <doc:Drawings>
- <doc:Extending>

### Data

- ``ChartSeries``
- ``Candle``
- ``PricePoint``
- ``ChartInterval``
- ``SeriesStyle``
- ``ChartMarker``
- ``ChartColor``

### Scrolling, zooming and history

- ``ViewportConfiguration``
- ``ZoomAnchor``
- ``HistoryPrefetchThreshold``
- ``ViewportMath``
- ``ChartTransform``

### Events and the crosshair

- ``TradingChartEvent``
- ``CrosshairState``
- ``CrosshairIndicatorValue``

### Persistence

- ``ChartPersistence``
- ``ChartPreferencesStore``
- ``UserDefaultsChartPreferencesStore``

### Appearance

- ``TradingChartTheme``
- ``SeriesInterpolation``
- ``PriceFormatter``
- ``TimeFormatter``
- ``TradingChartStrings``

### Controls

- ``IndicatorBar``
- ``SeriesStylePicker``
- ``StylePickerOptions``

### Built-in indicators

- ``SMA``
- ``EMA``
- ``WMA``
- ``BollingerBands``
- ``Volume``
- ``RSI``
- ``MACD``
- ``IndicatorMath``
- ``MACDResult``

### Writing an indicator

- ``ChartIndicator``
- ``IndicatorPlacement``
- ``PriceSource``
- ``IndicatorInput``
- ``IndicatorOutput``
- ``IndicatorValue``
- ``IndicatorLine``
- ``IndicatorLineStyle``
- ``IndicatorBand``
- ``IndicatorHistogram``
- ``HistogramBar``
- ``HistogramTone``
- ``IndicatorLevel``

### Drawings

- ``ChartDrawing``
- ``ChartAnchor``
- ``DrawingKind``
- ``DrawingStyle``
- ``DrawingEvent``

### Writing a drawing tool

- ``DrawingTool``
- ``DrawingToolRegistry``
- ``DrawingPrimitive``
- ``DrawingHit``
- ``DrawingContext``
- ``DrawingEditor``
- ``ChartDomain``
- ``HorizontalLineTool``
- ``TrendLineTool``
- ``RayTool``
