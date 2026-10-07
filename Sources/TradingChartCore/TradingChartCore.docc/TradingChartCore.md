# ``TradingChartCore``

The data model, the viewport math, the indicator types and the drawing model of the chart, with no UI.

## Overview

`TradingChartCore` imports only Foundation and CoreGraphics. A ``ChartSeries`` holds the bars, ``ViewportMath`` knows where the window is, ``ChartIndicator`` is the protocol that indicators implement, and ``DrawingEditor`` is the state machine behind the drawing tools. All of it is pure and covered by unit tests, so it can be used without the chart view, for example in a non-UI target or in a test. The module supports iOS 16 and later.

Most apps depend on the `TradingChart` product, which re-exports this module and `TradingChartIndicators`.

## Topics

### Bars and series

- ``Candle``
- ``PricePoint``
- ``ChartSeries``
- ``ChartInterval``
- ``SeriesStyle``
- ``ChartMarker``
- ``ChartColor``

### The viewport

- ``ViewportConfiguration``
- ``ZoomAnchor``
- ``ViewportMath``
- ``ChartTransform``

### Indicators

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
