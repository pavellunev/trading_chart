import Foundation
@testable import TradingChart

/// The English words of the chart, whatever the language of the machine that runs the tests.
let english = TradingChartStrings.localized(for: Locale(identifier: "en"))

/// A minute-aligned timestamp (1_700_000_040 / 60 is an integer).
let baseTime: TimeInterval = 1_700_000_040

func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// `count` candles of `interval`, the last one starting at `lastStart`; closes walk from 100 upwards.
func makeSeries(
    count: Int,
    interval: ChartInterval = .minutes(1),
    lastStart: TimeInterval = baseTime + 199 * 60,
    candles: Bool = true
) -> ChartSeries {
    let items = (0..<count).map { index -> Candle in
        let time = lastStart - Double(count - 1 - index) * interval.seconds
        let open = 100 + Double(index)
        return Candle(time: date(time), open: open, high: open + 2, low: open - 1, close: open + 1, volume: 10)
    }
    if candles {
        return ChartSeries(candles: items, interval: interval)
    }
    return ChartSeries(points: items.map { PricePoint(time: $0.time, value: $0.close) }, interval: interval)
}

/// A model with `count` one-minute candles and a collector for its events.
@MainActor
final class EventLog {
    private(set) var events: [TradingChartEvent] = []

    init(_ model: TradingChartModel) {
        model.onEvent = { [weak self] event in self?.events.append(event) }
    }

    var historyRequests: Int {
        events.filter { if case .approachedHistoryStart = $0 { true } else { false } }.count
    }

    var crosshairChanges: [CrosshairState?] {
        events.compactMap { if case .crosshairChanged(let state) = $0 { .some(state) } else { nil } }
    }

    var liveEdgeChanges: [Bool] {
        events.compactMap { if case .liveEdgeChanged(let value) = $0 { value } else { nil } }
    }
}

/// An indicator that echoes the close of every candle, so the cache contents depend on the series.
struct EchoIndicator: ChartIndicator {
    var id: String { "echo" }
    var displayName: String { "Echo" }
    var placement: IndicatorPlacement { .overlay }

    func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let values = input.candles.map { IndicatorValue(time: $0.time, value: $0.close) }
        return IndicatorOutput(lines: [IndicatorLine(id: "echo", name: "Echo", values: values)])
    }
}

/// An indicator with several kinds of output: a warm-up, explicit and palette colours, slots and a histogram.
struct PaletteIndicator: ChartIndicator {
    var id: String { "palette" }
    var displayName: String { "Palette" }
    var placement: IndicatorPlacement { .pane }

    func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let times = input.candles.map(\.time)
        let all = times.enumerated().map { IndicatorValue(time: $1, value: Double($0)) }
        let late = Array(all.dropFirst(10))
        return IndicatorOutput(
            lines: [
                IndicatorLine(id: "palette.a", name: "A", values: all, paletteSlot: 0),
                IndicatorLine(
                    id: "palette.b",
                    name: "B",
                    values: late,
                    style: IndicatorLineStyle(color: ChartColor(red: 1, green: 0, blue: 0)),
                    paletteSlot: 1
                ),
                IndicatorLine(id: "palette.c", name: "C", values: late, paletteSlot: 1),
            ],
            histograms: [
                IndicatorHistogram(
                    id: "palette.h",
                    name: "H",
                    bars: times.suffix(3).map { HistogramBar(time: $0, value: -2, tone: .negative) }
                )
            ]
        )
    }
}
