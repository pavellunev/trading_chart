import Foundation
import TradingChartCore

/// A date `seconds` after the Unix epoch.
func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// A candle at `seconds` with explicit OHLC values.
func candle(
    _ seconds: TimeInterval,
    o: Double,
    h: Double,
    l: Double,
    c: Double,
    v: Double? = nil
) -> Candle {
    Candle(time: date(seconds), open: o, high: h, low: l, close: c, volume: v)
}

/// A flat candle (`open == high == low == close`).
func flatCandle(_ seconds: TimeInterval, _ price: Double) -> Candle {
    candle(seconds, o: price, h: price, l: price, c: price)
}

/// A point at `seconds`.
func point(_ seconds: TimeInterval, _ value: Double) -> PricePoint {
    PricePoint(time: date(seconds), value: value)
}

/// `true` when `lhs` and `rhs` differ by less than `tolerance`.
func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) < tolerance
}

func approximatelyEqual(_ lhs: ClosedRange<Double>, _ rhs: ClosedRange<Double>, tolerance: Double = 1e-9) -> Bool {
    approximatelyEqual(lhs.lowerBound, rhs.lowerBound, tolerance: tolerance)
        && approximatelyEqual(lhs.upperBound, rhs.upperBound, tolerance: tolerance)
}

/// One-minute series of ten points at `t = 0, 60, ... 540` with the values below.
let tenPointValues: [Double] = [10, 12, 11, 15, 14, 9, 13, 16, 12, 11]

func tenPointSeries() -> ChartSeries {
    ChartSeries(
        points: tenPointValues.enumerated().map { point(TimeInterval($0.offset) * 60, $0.element) },
        interval: .minutes(1)
    )
}

/// One-minute series of ten candles at `t = 0, 60, ... 540` (close values match ``tenPointValues``).
func tenCandleSeries() -> ChartSeries {
    let lows: [Double] = [9, 11, 10, 14, 13, 8, 12, 15, 11, 10]
    let highs: [Double] = [11, 13, 12, 16, 15, 10, 14, 17, 13, 12]
    let candles = (0..<10).map { index in
        candle(
            TimeInterval(index) * 60,
            o: tenPointValues[index],
            h: highs[index],
            l: lows[index],
            c: tenPointValues[index]
        )
    }
    return ChartSeries(candles: candles, interval: .minutes(1))
}
