# ``TradingChartIndicators``

The built-in technical indicators and the math behind them.

## Overview

Each indicator is a value that conforms to `ChartIndicator` (from `TradingChartCore`): a pure function from bars to drawable output. Put them in `TradingChartModel.indicators`, or call ``IndicatorMath`` directly when you need the numbers without a chart.

| Indicator | Placement | Output |
| --- | --- | --- |
| ``SMA``, ``EMA``, ``WMA`` | overlay | one line |
| ``BollingerBands`` | overlay | three lines and a band |
| ``Volume`` | pane | a histogram and an optional moving average |
| ``RSI`` | pane | one line on a fixed 0 to 100 scale, two levels |
| ``MACD`` | pane | two lines and a histogram |

The math follows the common definitions: EMAs are seeded with the SMA of the first `period` values, RSI uses Wilder smoothing, Bollinger Bands use the population standard deviation, MACD is `EMA(fast) - EMA(slow)` with an EMA signal line. The tests compare the functions with reference values computed with TA-Lib, to a tolerance of `1e-9`.

## Topics

### Overlays

- ``SMA``
- ``EMA``
- ``WMA``
- ``BollingerBands``

### Panes

- ``Volume``
- ``RSI``
- ``MACD``

### Math

- ``IndicatorMath``
- ``MACDResult``
