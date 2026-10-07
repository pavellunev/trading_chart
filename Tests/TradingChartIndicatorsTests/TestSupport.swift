import Foundation
import Testing
import TradingChartCore
@testable import TradingChartIndicators

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

/// A one-minute candle series whose closes are `closes`; each candle opens at the previous close and spans +-0.5.
func candleSeries(closes: [Double]) -> ChartSeries {
    var previous = closes.first ?? 0
    var candles: [Candle] = []
    for (index, close) in closes.enumerated() {
        candles.append(candle(
            TimeInterval(index) * 60,
            o: previous,
            h: max(previous, close) + 0.5,
            l: min(previous, close) - 0.5,
            c: close
        ))
        previous = close
    }
    return ChartSeries(candles: candles, interval: .minutes(1))
}

/// A one-minute point series with the given values.
func pointSeries(values: [Double]) -> ChartSeries {
    ChartSeries(
        points: values.enumerated().map { PricePoint(time: date(TimeInterval($0.offset) * 60), value: $0.element) },
        interval: .minutes(1)
    )
}

/// Bar times of ``candleSeries(closes:)`` / ``pointSeries(values:)`` with `count` bars.
func barTimes(_ count: Int) -> [Date] {
    (0..<count).map { date(TimeInterval($0) * 60) }
}

/// The series of ``referenceCloses``.
func referenceSeries() -> ChartSeries {
    candleSeries(closes: referenceCloses)
}

/// Expects two index-aligned series to be defined at the same indices and equal within `tolerance` elsewhere.
func expectAligned(
    _ actual: [Double?],
    _ expected: [Double?],
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.count == expected.count, "length differs", sourceLocation: sourceLocation)
    guard actual.count == expected.count else { return }
    for index in actual.indices {
        switch (actual[index], expected[index]) {
        case (nil, nil):
            break
        case let (actualValue?, expectedValue?):
            #expect(
                abs(actualValue - expectedValue) <= tolerance,
                "index \(index): \(actualValue) vs \(expectedValue)",
                sourceLocation: sourceLocation
            )
        default:
            Issue.record(
                "index \(index): \(String(describing: actual[index])) vs \(String(describing: expected[index]))",
                sourceLocation: sourceLocation
            )
        }
    }
}

/// Expects output values to be exactly the defined entries of `expected`, paired with the matching bar times.
func expectValues(
    _ actual: [IndicatorValue],
    match expected: [Double?],
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let times = barTimes(expected.count)
    let defined = zip(times, expected).compactMap { time, value in value.map { (time, $0) } }
    #expect(actual.count == defined.count, "count differs", sourceLocation: sourceLocation)
    guard actual.count == defined.count else { return }
    for (value, pair) in zip(actual, defined) {
        #expect(value.time == pair.0, sourceLocation: sourceLocation)
        #expect(abs(value.value - pair.1) <= tolerance, "\(value.value) vs \(pair.1)", sourceLocation: sourceLocation)
    }
}
