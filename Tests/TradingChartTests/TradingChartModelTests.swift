import Foundation
import Testing
@testable import TradingChart

@MainActor
@Suite("TradingChartModel")
struct TradingChartModelTests {

    private func endAnchor(
        of series: ChartSeries,
        bars: Double,
        configuration: ViewportConfiguration = ViewportConfiguration()
    ) -> Date {
        ViewportMath.endAnchor(
            lastTime: series.lastTime ?? .distantPast,
            interval: series.interval,
            visibleBars: bars,
            configuration: configuration
        )
    }

    // MARK: - Initial state and viewport

    @Test("a new model starts at the live edge with the default width of its style")
    func initialState() {
        let series = makeSeries(count: 200)
        let candles = TradingChartModel(series: series, style: .candles)
        let line = TradingChartModel(series: series, style: .line)

        #expect(candles.visibleBars == 40)
        #expect(candles.scrollPosition == endAnchor(of: series, bars: 40))
        #expect(candles.isAtLiveEdge)
        #expect(line.visibleBars == 60)
        #expect(line.scrollPosition == endAnchor(of: series, bars: 60))
    }

    @Test("visible duration and range follow the series interval")
    func visibleWindow() {
        let model = TradingChartModel(series: makeSeries(count: 200, interval: .minutes(5), lastStart: baseTime), style: .candles)

        #expect(model.visibleDuration == 40 * 300)
        #expect(model.visibleTimeRange.lowerBound == model.scrollPosition)
        #expect(model.visibleTimeRange.upperBound == model.scrollPosition.addingTimeInterval(40 * 300))
    }

    @Test("scrolling away from the live edge and scrollToLiveEdge")
    func scrollToLiveEdge() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)

        model.scrollPosition = series.firstTime!.addingTimeInterval(600)
        #expect(!model.isAtLiveEdge)

        model.scrollToLiveEdge()
        #expect(model.isAtLiveEdge)
        #expect(model.scrollPosition == endAnchor(of: series, bars: 40))
    }

    @Test("zoom clamps the window to the configured bounds")
    func zoomClamp() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)

        model.zoom(by: 100, anchor: .liveEdge)
        #expect(model.visibleBars == 10)

        model.zoom(by: 0.0001, anchor: .liveEdge)
        #expect(model.visibleBars == 400)
    }

    @Test("zoom keeps the live edge for the liveEdge anchor")
    func zoomLiveEdgeAnchor() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)

        model.zoom(by: 2, anchor: .liveEdge)

        // A zoomed-in window keeps a smaller gap: min(6, 20 * 0.2) = 4 bars.
        #expect(model.visibleBars == 20)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((4 - 20) * 60))
        #expect(model.isAtLiveEdge)
    }

    @Test("zoom around the centre keeps the middle of the window in place")
    func zoomCenterAnchor() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 80)
        let centreBefore = model.scrollPosition.addingTimeInterval(model.visibleDuration / 2)

        model.zoom(by: 2, anchor: .center)

        let centreAfter = model.scrollPosition.addingTimeInterval(model.visibleDuration / 2)
        #expect(model.visibleBars == 20)
        #expect(abs(centreAfter.timeIntervalSince(centreBefore)) < 1e-6)
    }

    // MARK: - setSeries

    @Test("setSeries with a new interval anchors at the end, even from the history")
    func setSeriesIntervalChange() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        model.scrollPosition = model.series.firstTime!.addingTimeInterval(600)
        #expect(!model.isAtLiveEdge)

        let fiveMinutes = makeSeries(count: 150, interval: .minutes(5), lastStart: baseTime + 3_000)
        model.setSeries(fiveMinutes)

        #expect(model.series.interval == .minutes(5))
        #expect(model.scrollPosition == endAnchor(of: fiveMinutes, bars: 40))
        #expect(model.isAtLiveEdge)
    }

    @Test("setSeries with the same interval at the live edge follows the new data")
    func setSeriesAtLiveEdge() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        let longer = makeSeries(count: 210, lastStart: baseTime + 209 * 60)

        model.setSeries(longer)

        #expect(model.scrollPosition == endAnchor(of: longer, bars: 40))
    }

    @Test("setSeries with the same interval in the history keeps the position")
    func setSeriesInHistory() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        let inHistory = model.series.firstTime!.addingTimeInterval(60 * 50)
        model.scrollPosition = inHistory

        model.setSeries(makeSeries(count: 210, lastStart: baseTime + 209 * 60))

        #expect(model.scrollPosition == inHistory)
        #expect(!model.isAtLiveEdge)
    }

    @Test("explicit scroll behaviours override the automatic rule")
    func setSeriesExplicitBehaviour() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let inHistory = series.firstTime!.addingTimeInterval(60 * 50)

        model.scrollPosition = inHistory
        model.setSeries(series, scroll: .liveEdge)
        #expect(model.scrollPosition == endAnchor(of: series, bars: 40))

        let fiveMinutes = makeSeries(count: 150, interval: .minutes(5), lastStart: baseTime + 3_000)
        model.scrollPosition = inHistory
        model.setSeries(fiveMinutes, scroll: .preserve)
        #expect(model.scrollPosition == inHistory)
    }

    @Test("the first series of an empty model lands at the live edge")
    func setSeriesIntoEmptyModel() {
        let model = TradingChartModel(style: .line)
        let series = makeSeries(count: 120)

        model.setSeries(series)

        #expect(model.scrollPosition == endAnchor(of: series, bars: 60))
    }

    // MARK: - update

    @Test("a live update at the live edge moves the window")
    func updateAtLiveEdge() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let nextBucket = series.lastTime!.addingTimeInterval(60)

        let appended = model.update(price: 500, at: nextBucket.addingTimeInterval(5))

        #expect(appended == .appended)
        #expect(model.series.count == 201)
        #expect(model.series.lastTime == nextBucket)
        #expect(model.scrollPosition == endAnchor(of: model.series, bars: 40))

        let updated = model.update(price: 510, at: nextBucket.addingTimeInterval(20))
        #expect(updated == .updatedLast)
        #expect(model.series.lastValue == 510)
        #expect(model.scrollPosition == endAnchor(of: model.series, bars: 40))
    }

    @Test("a live update does not move a window that sits in the history")
    func updateInHistory() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let inHistory = series.firstTime!.addingTimeInterval(60 * 50)
        model.scrollPosition = inHistory

        let result = model.update(price: 500, at: series.lastTime!.addingTimeInterval(60))

        #expect(result == .appended)
        #expect(model.scrollPosition == inHistory)
    }

    @Test("an update stamped with a foreign interval is ignored")
    func updateForeignInterval() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let nextCandle = Candle(time: series.lastTime!.addingTimeInterval(60), open: 1, high: 2, low: 0.5, close: 1.5)
        let nextPoint = PricePoint(time: series.lastTime!.addingTimeInterval(60), value: 1.5)

        #expect(model.update(nextCandle, interval: .minutes(5)) == .ignored)
        #expect(model.update(nextPoint, interval: .hours(1)) == .ignored)
        #expect(model.series == series)

        #expect(model.update(nextCandle, interval: .minutes(1)) == .appended)
        #expect(model.series.count == 201)
    }

    @Test("updates honour maxLiveBarCount")
    func updateTrimsToMaxCount() {
        var configuration = TradingChartConfiguration()
        configuration.maxLiveBarCount = 200
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)

        model.update(price: 500, at: series.lastTime!.addingTimeInterval(60))

        #expect(model.series.count == 200)
        #expect(model.series.firstTime == series.firstTime!.addingTimeInterval(60))
    }

    @Test("an update to an empty model creates the first bar and anchors the window")
    func updateIntoEmptyModel() {
        let model = TradingChartModel(style: .line)
        let time = date(baseTime + 10)

        let result = model.update(price: 42, at: time)

        #expect(result == .appended)
        #expect(model.series.lastValue == 42)
        #expect(model.scrollPosition == endAnchor(of: model.series, bars: 60))
    }

    // MARK: - Style

    @Test("changing the style restores the default width of the style and returns to the live edge")
    func styleChange() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.zoom(by: 2, anchor: .liveEdge)
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 50)
        #expect(model.visibleBars == 20)

        model.style = .line

        #expect(model.visibleBars == 60)
        #expect(model.scrollPosition == endAnchor(of: series, bars: 60))
        #expect(model.isAtLiveEdge)

        model.style = .candles
        #expect(model.visibleBars == 40)
        #expect(model.scrollPosition == endAnchor(of: series, bars: 40))
    }

    @Test("assigning the same style changes nothing")
    func styleUnchanged() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.zoom(by: 2, anchor: .liveEdge)

        model.style = .candles

        #expect(model.visibleBars == 20)
    }

    // MARK: - Events

    @Test("approachedHistoryStart fires once per revision of the series")
    func approachedHistoryStartOncePerRevision() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let log = EventLog(model)
        let first = series.firstTime!

        model.scrollPosition = first.addingTimeInterval(60 * 100)
        #expect(log.historyRequests == 0)

        model.scrollPosition = first.addingTimeInterval(60 * 15)
        #expect(log.historyRequests == 1)

        model.scrollPosition = first.addingTimeInterval(60 * 10)
        model.scrollPosition = first.addingTimeInterval(60 * 2)
        #expect(log.historyRequests == 1)

        // Older bars arrive: a new revision, and the window is far from the new start.
        let older = makeSeries(count: 100, lastStart: first.timeIntervalSince1970 - 60)
        model.prependHistory(older)
        #expect(model.series.count == 300)
        #expect(log.historyRequests == 1)

        // Scrolling to the new start asks again, once.
        model.scrollPosition = model.series.firstTime!.addingTimeInterval(60 * 5)
        model.scrollPosition = model.series.firstTime!.addingTimeInterval(60 * 3)
        #expect(log.historyRequests == 2)
    }

    @Test("a prepend that adds nothing does not re-arm the history request")
    func emptyPrependDoesNotRearm() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let log = EventLog(model)
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 5)
        #expect(log.historyRequests == 1)

        model.prependHistory(.empty(interval: .minutes(1)))
        model.prependHistory(makeSeries(count: 50, interval: .minutes(5), lastStart: baseTime - 3_000))
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 4)

        #expect(model.series == series)
        #expect(log.historyRequests == 1)
    }

    @Test("setSeries starts a new revision")
    func setSeriesRearmsHistoryRequest() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let log = EventLog(model)
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 5)
        #expect(log.historyRequests == 1)

        model.setSeries(series, scroll: .preserve)

        #expect(log.historyRequests == 2)
    }

    @Test("liveEdgeChanged fires only when the state flips")
    func liveEdgeChanged() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let log = EventLog(model)

        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 100)
        model.scrollPosition = series.firstTime!.addingTimeInterval(60 * 90)
        #expect(log.liveEdgeChanges == [false])

        model.scrollToLiveEdge()
        #expect(log.liveEdgeChanges == [false, true])
    }

    // MARK: - Prepend

    @Test("prependHistory keeps the scroll position and adds older bars")
    func prependKeepsScrollPosition() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let inHistory = series.firstTime!.addingTimeInterval(60 * 80)
        model.scrollPosition = inHistory

        model.prependHistory(makeSeries(count: 100, lastStart: series.firstTime!.timeIntervalSince1970 - 60))

        #expect(model.series.count == 300)
        #expect(model.scrollPosition == inHistory)
    }

    @Test("prependHistory ignores a series with another interval")
    func prependForeignInterval() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)

        model.prependHistory(makeSeries(count: 100, interval: .minutes(5), lastStart: baseTime - 3_000))

        #expect(model.series == series)
    }

    // MARK: - Indicators

    @Test("indicator outputs are cached and recomputed when the series changes")
    func indicatorCache() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)

        model.indicators = [EchoIndicator()]
        #expect(model.output(for: "echo")?.lines.first?.values.count == 200)
        #expect(model.output(for: "echo")?.lines.first?.values.last?.value == series.lastValue)
        #expect(model.output(for: "unknown") == nil)

        model.update(price: 777, at: series.lastTime!.addingTimeInterval(10))
        #expect(model.output(for: "echo")?.lines.first?.values.last?.value == 777)

        model.update(price: 800, at: series.lastTime!.addingTimeInterval(60))
        #expect(model.output(for: "echo")?.lines.first?.values.count == 201)

        model.prependHistory(makeSeries(count: 50, lastStart: series.firstTime!.timeIntervalSince1970 - 60))
        #expect(model.output(for: "echo")?.lines.first?.values.count == 251)

        model.setSeries(makeSeries(count: 30))
        #expect(model.output(for: "echo")?.lines.first?.values.count == 30)
    }

    @Test("duplicate indicator ids are dropped and removed indicators leave the cache")
    func indicatorDeduplication() {
        let model = TradingChartModel(series: makeSeries(count: 50), style: .candles)

        model.indicators = [EchoIndicator(), EchoIndicator()]
        #expect(model.indicators.count == 1)
        #expect(model.output(for: "echo") != nil)

        model.indicators = []
        #expect(model.output(for: "echo") == nil)
    }

    // MARK: - Price badge clearance

    // Metrics used below: a 320pt plot with 40 bars is 8pt per bar; the price axis column is 56pt wide.
    // A 120pt badge reaches 64pt into the plot and needs ceil((64 + 6) / 8) = 9 bars of padding (more than the 6 configured).

    @Test("a badge that reaches far into the plot widens the right padding and a window at the live edge follows")
    func badgePaddingAtLiveEdge() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        #expect(model.viewport.trailingPaddingBars == 6)

        model.updateLayoutMetrics(plotWidth: 320, yAxisColumnWidth: 56)
        model.updateLayoutMetrics(badgeWidth: 120)

        #expect(model.viewport.trailingPaddingBars == 9)
        #expect(model.isAtLiveEdge)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((9 - 40) * 60))
        let xDomain = model.naturalXDomain
        #expect(xDomain.upperBound == series.lastTime!.addingTimeInterval(9 * 60))
    }

    @Test("a badge that mostly sits on the price axis column leaves the padding at its baseline")
    func badgeOnAxisColumn() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        // 84pt badge on a 61pt column reaches 23pt into the plot: ceil(29 / 8) = 4 bars < 6.
        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 84, yAxisColumnWidth: 61)

        #expect(model.viewport.trailingPaddingBars == 6)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((6 - 40) * 60))
        #expect(model.isAtLiveEdge)
    }

    @Test("the live edge keeps the last bar clear of the badge after updates")
    func badgePaddingSurvivesUpdates() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120, yAxisColumnWidth: 56)

        model.update(price: 121_400, at: series.lastTime!.addingTimeInterval(60))

        #expect(model.scrollPosition == model.series.lastTime!.addingTimeInterval((9 - 40) * 60))
        #expect(model.isAtLiveEdge)
    }

    @Test("a window in the history keeps its position when the padding changes")
    func badgePaddingInHistory() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        let inHistory = series.firstTime!.addingTimeInterval(60 * 80)
        model.scrollPosition = inHistory

        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120, yAxisColumnWidth: 56)

        #expect(model.viewport.trailingPaddingBars == 9)
        #expect(model.scrollPosition == inHistory)
        #expect(!model.isAtLiveEdge)
    }

    @Test("metric changes below one point are ignored")
    func badgeMetricsHysteresis() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120, yAxisColumnWidth: 56)
        let position = model.scrollPosition

        model.updateLayoutMetrics(plotWidth: 320.9, badgeWidth: 120.9, yAxisColumnWidth: 56.9)
        #expect(model.plotWidth == 320)
        #expect(model.badgeWidth == 120)
        #expect(model.yAxisColumnWidth == 56)
        #expect(model.scrollPosition == position)

        // 136pt badge on a 56pt column: 80pt overhang, ceil(86 / 8) = 11 bars.
        model.updateLayoutMetrics(badgeWidth: 136)
        #expect(model.badgeWidth == 136)
        #expect(model.viewport.trailingPaddingBars == 11)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((11 - 40) * 60))

        // A wider column takes the badge in: back to the baseline.
        model.updateLayoutMetrics(yAxisColumnWidth: 140)
        #expect(model.viewport.trailingPaddingBars == 6)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((6 - 40) * 60))
    }

    @Test("the padding ignores the badge when it is hidden, there is no price, or the column is not measured")
    func badgePaddingOnlyWhileBadgeIsShown() {
        var configuration = TradingChartConfiguration()
        configuration.showsPriceBadge = false
        let series = makeSeries(count: 200)
        let hiddenBadge = TradingChartModel(series: series, style: .candles, configuration: configuration)
        hiddenBadge.currentPrice = 121_345.67
        hiddenBadge.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120, yAxisColumnWidth: 56)
        #expect(hiddenBadge.viewport.trailingPaddingBars == 6)

        let noPrice = TradingChartModel(series: series, style: .candles)
        noPrice.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120, yAxisColumnWidth: 56)
        #expect(noPrice.viewport.trailingPaddingBars == 6)

        // The badge appears and disappears with the price; the window follows.
        noPrice.currentPrice = 121_345.67
        #expect(noPrice.viewport.trailingPaddingBars == 9)
        #expect(noPrice.scrollPosition == series.lastTime!.addingTimeInterval((9 - 40) * 60))
        noPrice.currentPrice = nil
        #expect(noPrice.viewport.trailingPaddingBars == 6)
        #expect(noPrice.scrollPosition == series.lastTime!.addingTimeInterval((6 - 40) * 60))

        let noColumn = TradingChartModel(series: series, style: .candles)
        noColumn.currentPrice = 121_345.67
        noColumn.updateLayoutMetrics(plotWidth: 320, badgeWidth: 120)
        #expect(noColumn.viewport.trailingPaddingBars == 6)
    }

    @Test("a configured padding larger than the badge needs wins, within a fifth of the window")
    func configuredPaddingWins() {
        var configuration = TradingChartConfiguration()
        configuration.viewport.trailingPaddingBars = 20
        configuration.viewport.maxTrailingPaddingFraction = 0.5
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles, configuration: configuration)
        model.currentPrice = 100
        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 84, yAxisColumnWidth: 56)

        // min(20, 40 * 0.5) = 20
        #expect(model.viewport.trailingPaddingBars == 20)
    }

    // MARK: - Zoomed-in padding

    @Test("the padding and the tolerance at the default widths are the documented ones")
    func parityAtDefaultWidths() {
        let candles = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        #expect(candles.visibleBars == 40)
        #expect(candles.viewport.trailingPaddingBars == 6)
        #expect(candles.viewport.liveEdgeToleranceBars == 2)

        let line = TradingChartModel(series: makeSeries(count: 200), style: .line)
        #expect(line.visibleBars == 60)
        #expect(line.viewport.trailingPaddingBars == 6)
        #expect(line.viewport.liveEdgeToleranceBars == 2)
    }

    @Test("zooming in shrinks the padding to a fifth of the window and the tolerance to a tenth")
    func zoomShrinksPadding() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.currentPrice = 121_345.67
        model.updateLayoutMetrics(plotWidth: 320, badgeWidth: 84, yAxisColumnWidth: 61)

        // 20 bars: 16pt per bar, the badge needs ceil(29 / 16) = 2 bars; the baseline is min(6, 4) = 4.
        model.zoom(by: 2, anchor: .liveEdge)
        #expect(model.visibleBars == 20)
        #expect(model.viewport.trailingPaddingBars == 4)
        #expect(model.viewport.liveEdgeToleranceBars == 2)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((4 - 20) * 60))

        // 10 bars: the baseline is min(6, 2) = 2, the tolerance min(2, 1) = 1.
        model.zoom(by: 2, anchor: .liveEdge)
        #expect(model.visibleBars == 10)
        #expect(model.viewport.trailingPaddingBars == 2)
        #expect(model.viewport.liveEdgeToleranceBars == 1)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((2 - 10) * 60))
        #expect(model.isAtLiveEdge)

        // Zooming back out restores the reference padding.
        model.zoom(by: 0.25, anchor: .liveEdge)
        #expect(model.visibleBars == 40)
        #expect(model.viewport.trailingPaddingBars == 6)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((6 - 40) * 60))
    }

    @Test("the live-edge tolerance of a zoomed-in window is one bar")
    func zoomedLiveEdgeTolerance() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        model.zoom(by: 4, anchor: .liveEdge)
        #expect(model.visibleBars == 10)
        let anchor = model.scrollPosition

        model.scrollPosition = anchor.addingTimeInterval(-60)
        #expect(model.isAtLiveEdge)
        model.scrollPosition = anchor.addingTimeInterval(-90)
        #expect(!model.isAtLiveEdge)
    }

    @Test("a model created with a narrow default window starts with the zoomed-in padding")
    func narrowDefaultWindow() {
        var configuration = TradingChartConfiguration()
        configuration.viewport.candleVisibleBars = 20
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)

        #expect(model.viewport.trailingPaddingBars == 4)
        #expect(model.scrollPosition == series.lastTime!.addingTimeInterval((4 - 20) * 60))
        #expect(model.isAtLiveEdge)
    }

    // MARK: - Rendering window

    @Test("only bars inside the render buffer get marks")
    func renderCulling() {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * 60)
        let model = TradingChartModel(series: series, style: .candles)

        let indices = series.indexRange(in: model.renderTimeRange)

        // Window [last - 34 bars, last + 6 bars] extended by one window (40 bars) on each side.
        #expect(indices.count == 75)
        #expect(indices.upperBound == 600)
    }

    @Test("a zero buffer renders the visible window only")
    func renderCullingWithoutBuffer() {
        var configuration = TradingChartConfiguration()
        configuration.renderBufferWindows = 0
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * 60)
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)

        #expect(series.indexRange(in: model.renderTimeRange).count == 35)
    }
}
