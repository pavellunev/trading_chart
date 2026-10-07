import Foundation
import XCTest
@testable import TradingChart

/// Micro-benchmarks of the work the chart does outside SwiftUI: indicator recalculation, the per-frame window
/// computations, live updates and history paging. They only measure (`XCTClockMetric`): there are no baselines and no
/// time assertions, so they cannot flap. The budgets and the numbers are in `Docs/Performance.md`.
///
/// Run one with, for example,
/// `xcodebuild test -scheme TradingChart-Package -destination '...' -only-testing:TradingChartTests/PerformanceTests/testLiveUpdate5000`
/// and read the `measured [Clock Monotonic Time, s] average:` line. Add `-configuration Release ENABLE_TESTABILITY=YES`
/// for optimised numbers. Loops are divided out in the report: a frame is one iteration of `frameWork`, a live update
/// one `update(candle)`.
@MainActor
final class PerformanceTests: XCTestCase {

    /// Frames per measured iteration of the per-frame benchmarks.
    private static let framesPerIteration = 1_000
    /// Live updates per measured iteration.
    private static let updatesPerIteration = 50

    private static let interval = ChartInterval.minutes(1)
    private static let start = Date(timeIntervalSince1970: 1_700_000_040)

    /// A deterministic random walk of `count` one-minute candles ending at `lastStart + count - 1` minutes.
    private static func walk(count: Int, endingBefore end: Date? = nil, seed: UInt64 = 7) -> ChartSeries {
        var state = seed
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        let last = end.map { $0.addingTimeInterval(-interval.seconds) }
            ?? start.addingTimeInterval(Double(count - 1) * interval.seconds)
        var close = 121_345.67
        var candles: [Candle] = []
        candles.reserveCapacity(count)
        for index in 0..<count {
            let open = close
            close = open * (1 + next() * 0.004)
            let high = max(open, close) * (1 + abs(next()) * 0.002)
            let low = min(open, close) * (1 - abs(next()) * 0.002)
            let time = last.addingTimeInterval(-Double(count - 1 - index) * interval.seconds)
            candles.append(Candle(time: time, open: open, high: high, low: low, close: close, volume: 1_000 + abs(next()) * 4_000))
        }
        return ChartSeries(candles: candles, interval: interval)
    }

    private static let allIndicators: [any ChartIndicator] = [
        SMA(), EMA(), WMA(), BollingerBands(), Volume(movingAveragePeriod: 20), RSI(), MACD(),
    ]

    private static let chartIndicators: [any ChartIndicator] = [
        SMA(), BollingerBands(), Volume(movingAveragePeriod: 20), RSI(), MACD(),
    ]

    private var metrics: [XCTMetric] { [XCTClockMetric()] }

    // MARK: - Indicators

    private func measureAllIndicators(count: Int) {
        let series = Self.walk(count: count)
        var checksum = 0
        measure(metrics: metrics) {
            let input = IndicatorInput(series: series)
            for indicator in Self.allIndicators {
                checksum &+= indicator.calculate(input).lines.count
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    func testIndicatorsAll600() { measureAllIndicators(count: 600) }
    func testIndicatorsAll2000() { measureAllIndicators(count: 2_000) }
    func testIndicatorsAll5000() { measureAllIndicators(count: 5_000) }

    // MARK: - Per-frame window work

    /// `yDomain` and the slice of the visible bars on 5 000 bars: the cheapest part of a frame.
    func testYDomainAndSlice5000() {
        let series = Self.walk(count: 5_000)
        let model = TradingChartModel(series: series, style: .candles)
        let configuration = model.viewport
        var checksum = 0.0
        measure(metrics: metrics) {
            for frame in 0..<Self.framesPerIteration {
                let start = series.firstTime!.addingTimeInterval(Double(frame % 4_000) * Self.interval.seconds)
                let visible = start...start.addingTimeInterval(40 * Self.interval.seconds)
                let domain = ViewportMath.yDomain(
                    series: series,
                    style: .candles,
                    visibleRange: visible,
                    currentPrice: nil,
                    xDomainUpperBound: .distantFuture,
                    additionalRanges: [],
                    configuration: configuration
                )
                let slice = series.indexRange(in: visible)
                checksum += domain.upperBound + Double(slice.count)
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    /// Everything a frame computes before SwiftUI sees it: x and y domains, culled marks of five indicators, the
    /// extremes of the window and the Y domains of the three panes.
    func testFrameWork5000() {
        let series = Self.walk(count: 5_000)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = Self.chartIndicators
        let configuration = model.viewport
        let outputs = Self.chartIndicators.compactMap { model.output(for: $0.id) }
        var checksum = 0.0
        measure(metrics: metrics) {
            for frame in 0..<Self.framesPerIteration {
                let start = series.firstTime!.addingTimeInterval(Double(frame % 4_000) * Self.interval.seconds)
                let duration = 40 * Self.interval.seconds
                let visible = start...start.addingTimeInterval(duration)
                let render = start.addingTimeInterval(-duration)...start.addingTimeInterval(2 * duration)
                let xDomain = ViewportMath.xDomain(series: series, style: .candles, configuration: configuration, now: start)
                let overlays = outputs.prefix(2)
                let yDomain = ViewportMath.yDomain(
                    series: series,
                    style: .candles,
                    visibleRange: visible,
                    currentPrice: nil,
                    xDomainUpperBound: xDomain.upperBound,
                    additionalRanges: overlays.compactMap { $0.valueRange(in: visible) },
                    configuration: configuration
                )
                var marks = series.indexRange(in: render).count
                for output in outputs {
                    for line in output.lines { marks += IndicatorRendering.slice(line.values, in: render).count }
                    for band in output.bands {
                        marks += IndicatorRendering.bandPoints(upper: band.upper, lower: band.lower, in: render).count
                    }
                    for histogram in output.histograms { marks += IndicatorRendering.slice(histogram.bars, in: render).count }
                }
                for output in outputs.dropFirst(2) {
                    let pane = IndicatorRendering.paneYDomain(
                        output: output,
                        visibleRange: visible,
                        paddingFraction: configuration.verticalPaddingFraction
                    )
                    checksum += pane.upperBound
                }
                let extremes = HighLowMarks.extremes(in: series, style: .candles, range: visible)
                checksum += yDomain.upperBound + Double(marks) + (extremes?.high.value ?? 0)
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    /// What the model does on one scroll step (`scrollPosition` set by the chart or by the host): the render window, the
    /// autoscaled domains of the main pane and of three panes, the stored live-edge flag, the stop timer. 1 000 steps
    /// of 2.5 bars per iteration, back and forth over 5 000 bars with five indicators.
    func testScrollStep5000() {
        let series = Self.walk(count: 5_000)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = Self.chartIndicators
        model.scrollClock = ScrollClock(now: { 0 }, after: { _, _ in })
        let first = series.firstTime!
        var checksum = 0.0
        measure(metrics: metrics) {
            for frame in 0..<Self.framesPerIteration {
                let phase = Double(frame % 1_000) / 1_000
                let bars = (phase < 0.5 ? 2 * phase : 2 - 2 * phase) * 4_000
                model.scrollPosition = first.addingTimeInterval(bars * Self.interval.seconds)
                checksum += model.mainYTarget.upperBound
            }
        }
        XCTAssertGreaterThan(checksum, 0)
    }

    // MARK: - Live updates

    private func measureLiveUpdates(count: Int) {
        let series = Self.walk(count: count)
        var configuration = TradingChartConfiguration()
        configuration.maxLiveBarCount = nil
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)
        model.indicators = Self.chartIndicators
        var candle = series.candles!.last!
        measure(metrics: metrics) {
            for step in 0..<Self.updatesPerIteration {
                candle.close += Double(step % 7) - 3
                candle.high = max(candle.high, candle.close)
                candle.low = min(candle.low, candle.close)
                model.update(candle)
            }
        }
        XCTAssertEqual(model.series.count, count)
    }

    /// `update(candle)` end to end (series, the five indicators, the window) on the last bar: 50 updates per iteration.
    func testLiveUpdate600() { measureLiveUpdates(count: 600) }
    func testLiveUpdate5000() { measureLiveUpdates(count: 5_000) }

    /// Appending a new bar: the same plus the trim of the head to `maxLiveBarCount`.
    func testLiveAppendWithTrim600() {
        let series = Self.walk(count: 600)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = Self.chartIndicators
        var next = series.lastTime!
        measure(metrics: metrics) {
            for _ in 0..<Self.updatesPerIteration {
                next = next.addingTimeInterval(Self.interval.seconds)
                model.update(Candle(time: next, open: 1, high: 2, low: 0.5, close: 1.5, volume: 10))
            }
        }
        XCTAssertEqual(model.series.count, 600)
    }

    // MARK: - History

    private func measurePrepend(indicators: [any ChartIndicator]) {
        let series = Self.walk(count: 5_000)
        let older = Self.walk(count: 300, endingBefore: series.firstTime)
        // The model is built outside the measurement; the measurement stops at the end of the block.
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart]
        var total = 0
        measure(metrics: metrics, options: options) {
            var configuration = TradingChartConfiguration()
            configuration.maxLiveBarCount = nil
            let model = TradingChartModel(series: series, style: .candles, configuration: configuration)
            model.indicators = indicators
            startMeasuring()
            model.prependHistory(older)
            total = model.series.count
        }
        XCTAssertEqual(total, 5_300)
    }

    func testPrepend300Into5000() { measurePrepend(indicators: []) }
    func testPrepend300Into5000WithIndicators() { measurePrepend(indicators: Self.chartIndicators) }
}
