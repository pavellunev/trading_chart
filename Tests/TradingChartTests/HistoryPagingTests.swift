import Foundation
import Testing
@testable import TradingChart

@MainActor
@Suite("History paging")
struct HistoryPagingTests {
    private static let minute: TimeInterval = 60

    /// 600 one-minute candles from `baseTime` on; the window shows the newest 40 bars.
    private func makeModel(
        configuration: TradingChartConfiguration = TradingChartConfiguration(),
        count: Int = 600
    ) -> TradingChartModel {
        let series = makeSeries(count: count, lastStart: baseTime + Double(count - 1) * Self.minute)
        return TradingChartModel(series: series, style: .candles, configuration: configuration)
    }

    /// `count` candles that end right before `time`.
    private func page(_ count: Int, before time: Date) -> ChartSeries {
        makeSeries(count: count, lastStart: time.timeIntervalSince1970 - Self.minute)
    }

    private func scroll(_ model: TradingChartModel, barsFromStart bars: Double) {
        model.scrollPosition = model.series.firstTime!.addingTimeInterval(bars * Self.minute)
    }

    // MARK: - Flags and the event

    @Test("a new model is not loading and has more history")
    func defaults() {
        let model = makeModel()
        #expect(!model.isLoadingHistory)
        #expect(model.hasMoreHistory)
        #expect(TradingChartConfiguration().historyPrefetchThreshold == .visibleWindows(1))
    }

    @Test("no request while a request is running; prepending finishes it")
    func noRequestWhileLoading() {
        let model = makeModel()
        let log = EventLog(model)
        model.isLoadingHistory = true

        scroll(model, barsFromStart: 10)
        scroll(model, barsFromStart: 5)
        #expect(log.historyRequests == 0)

        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(!model.isLoadingHistory)
        #expect(model.series.count == 900)
        // The new start is 300 bars away from the window.
        #expect(log.historyRequests == 0)

        scroll(model, barsFromStart: 10)
        #expect(log.historyRequests == 1)
    }

    @Test("a host that marks the request in the handler gets one event per page")
    func handlerMarksRequest() {
        let model = makeModel()
        var requests = 0
        model.onEvent = { event in
            guard case .approachedHistoryStart = event else { return }
            requests += 1
            model.isLoadingHistory = true
        }

        scroll(model, barsFromStart: 30)
        scroll(model, barsFromStart: 20)
        scroll(model, barsFromStart: 2)
        #expect(requests == 1)
        #expect(model.isLoadingHistory)

        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(!model.isLoadingHistory)
        scroll(model, barsFromStart: 4)
        #expect(requests == 2)
    }

    @Test("no request once the source is exhausted; more history re-arms it")
    func exhaustedSource() {
        let model = makeModel()
        let log = EventLog(model)
        model.hasMoreHistory = false

        scroll(model, barsFromStart: 10)
        scroll(model, barsFromStart: 3)
        #expect(log.historyRequests == 0)

        // Still near the start when the flag comes back: the request is due right away.
        model.hasMoreHistory = true
        #expect(log.historyRequests == 1)
        model.hasMoreHistory = true
        scroll(model, barsFromStart: 2)
        #expect(log.historyRequests == 1)
    }

    @Test("a failed request that resets the flag allows the event again")
    func failedRequestRearms() {
        let model = makeModel()
        let log = EventLog(model)
        scroll(model, barsFromStart: 10)
        #expect(log.historyRequests == 1)
        model.isLoadingHistory = true

        model.isLoadingHistory = false

        #expect(log.historyRequests == 2)
    }

    @Test("the event fires once, however much the window moves near the start")
    func onceUntilSomethingChanges() {
        let model = makeModel()
        let log = EventLog(model)

        scroll(model, barsFromStart: 35)
        scroll(model, barsFromStart: 20)
        scroll(model, barsFromStart: 5)
        scroll(model, barsFromStart: 0)

        #expect(log.historyRequests == 1)
    }

    @Test("a line chart from the default model is a series of candles: a page of points becomes candles, and live points still merge")
    func lineChartFromAnEmptyModel() {
        let model = TradingChartModel(style: .line)
        let start = baseTime + 600
        model.update(PricePoint(time: date(start + 7), value: 10.0))
        model.update(PricePoint(time: date(start + 30), value: 12.0))
        #expect(model.series.hasCandles)
        #expect(model.series.count == 1)
        let page = ChartSeries(
            points: (0..<5).map { PricePoint(time: date(baseTime + Double($0) * Self.minute), value: 1 + Double($0)) },
            interval: .minutes(1)
        )
        model.isLoadingHistory = true

        model.prependHistory(page)

        #expect(model.series.hasCandles)
        #expect(model.series.count == 6)
        #expect(model.series.firstTime == date(baseTime))
        #expect(model.series.points.map(\.value) == [1, 2, 3, 4, 5, 12])
        #expect(model.series.candles?.prefix(5).allSatisfy { $0.open == $0.close && $0.high == $0.low && $0.volume == nil } == true)
        #expect(!model.isLoadingHistory)

        // The live rules did not change: a point of the last bucket merges into its candle, a newer one opens a candle.
        #expect(model.update(PricePoint(time: date(start + 50), value: 9.0)) == .updatedLast)
        #expect(model.series.count == 6)
        #expect(model.series.candles?.last == Candle(time: date(start), open: 10.0, high: 12.0, low: 9.0, close: 9.0))
        #expect(model.update(PricePoint(time: date(start + 65), value: 11.0)) == .appended)
        #expect(model.series.count == 7)
        #expect(model.series.hasCandles)
    }

    @Test("a point and the ticks after it on a default model share the bucket")
    func pointThenTicksShareTheBucket() {
        let model = TradingChartModel(style: .line)
        let start = baseTime + 600
        let (first, high, low, last): (Double, Double, Double, Double) = (10, 12, 9, 11)
        #expect(model.update(PricePoint(time: date(start + 7), value: first)) == .appended)
        #expect(model.update(price: high, at: date(start + 30)) == .updatedLast)
        #expect(model.update(price: low, at: date(start + 50)) == .updatedLast)
        #expect(model.update(PricePoint(time: date(start + 55), value: last)) == .updatedLast)

        #expect(model.series.count == 1)
        #expect(model.series.candles == [Candle(time: date(start), open: first, high: high, low: low, close: last)])
    }

    @Test("candles on the chart, then a page of points: the page becomes candles, and the candles are as they were")
    func pointsPageForACandleModel() {
        let model = makeModel()
        let oldFirst = model.series.firstTime!
        let candles = model.series.candles!
        let page = ChartSeries(
            points: (0..<50).map { PricePoint(time: oldFirst.addingTimeInterval(-Double(50 - $0) * Self.minute), value: Double($0)) },
            interval: .minutes(1)
        )
        model.isLoadingHistory = true

        model.prependHistory(page)

        #expect(model.series.hasCandles)
        #expect(model.series.count == 650)
        #expect(model.series.firstTime == oldFirst.addingTimeInterval(-50 * Self.minute))
        #expect(Array(model.series.candles!.suffix(600)) == candles)
        #expect(model.series.candles!.prefix(50).map(\.close) == (0..<50).map(Double.init))
        #expect(!model.isLoadingHistory)
    }

    @Test("a page of points that is off the grid of the interval snaps into buckets and merges when the chart shows candles")
    func offGridPointsPage() {
        let model = makeModel(count: 100)
        let first = model.series.firstTime!
        let candles = model.series.candles!
        let page = ChartSeries(
            points: [
                PricePoint(time: first.addingTimeInterval(-295), value: 1.0),
                PricePoint(time: first.addingTimeInterval(-270), value: 3.0),
                PricePoint(time: first.addingTimeInterval(-245), value: 2.0),  // the three are one bucket
                PricePoint(time: first.addingTimeInterval(-230), value: 5.0),
                PricePoint(time: first.addingTimeInterval(-1), value: 8.0),
                PricePoint(time: first.addingTimeInterval(5), value: 99.0),  // the bucket of the first candle: not older
            ],
            interval: .minutes(1)
        )
        model.isLoadingHistory = true

        model.prependHistory(page)

        #expect(model.series.count == 103)
        #expect(Array(model.series.candles!.prefix(3)) == [
            Candle(time: first.addingTimeInterval(-300), open: 1.0, high: 3.0, low: 1.0, close: 2.0),
            Candle(time: first.addingTimeInterval(-240), open: 5.0, high: 5.0, low: 5.0, close: 5.0),
            Candle(time: first.addingTimeInterval(-60), open: 8.0, high: 8.0, low: 8.0, close: 8.0),
        ])
        #expect(Array(model.series.candles!.suffix(100)) == candles)
        #expect(!model.isLoadingHistory)
    }

    @Test("points on the chart, then a page of candles: the page becomes points, and live points go on as before")
    func candlesPageForAPointModel() {
        let points = (0..<100).map { PricePoint(time: date(baseTime + 1_000 * Self.minute + Double($0) * Self.minute), value: 100 + Double($0)) }
        let model = TradingChartModel(series: ChartSeries(points: points, interval: .minutes(1)), style: .line)
        let oldFirst = model.series.firstTime!
        let older = page(30, before: oldFirst)
        model.isLoadingHistory = true

        model.prependHistory(older)

        #expect(!model.series.hasCandles)
        #expect(model.series.count == 130)
        #expect(model.series.points.prefix(30).map(\.value) == older.points.map(\.value))
        #expect(model.series.points.suffix(100).map(\.value) == points.map(\.value))
        #expect(!model.isLoadingHistory)

        // The live rules did not change: the same time replaces the last point, a newer one appends.
        let last = points[99].time
        #expect(model.update(PricePoint(time: last, value: 1.0)) == .updatedLast)
        #expect(model.update(PricePoint(time: last.addingTimeInterval(Self.minute), value: 2.0)) == .appended)
        #expect(model.series.count == 131)
        #expect(model.series.points.suffix(2).map(\.value) == [1, 2])
        #expect(!model.series.hasCandles)
    }

    @Test("a page of the other kind that adds nothing leaves the series as it is, and ends the request")
    func emptyPageOfTheOtherKind() {
        let points = (0..<20).map { PricePoint(time: date(baseTime + Double($0) * Self.minute), value: 100 + Double($0)) }
        let model = TradingChartModel(series: ChartSeries(points: points, interval: .minutes(1)), style: .line)
        let before = model.series
        model.isLoadingHistory = true

        model.prependHistory(.empty(interval: .minutes(1)))

        #expect(model.series == before)
        #expect(!model.series.hasCandles)
        #expect(!model.isLoadingHistory)
    }

    @Test("a page that adds nothing finishes the request without asking again")
    func emptyPageFinishesRequest() {
        let model = makeModel()
        let log = EventLog(model)
        scroll(model, barsFromStart: 10)
        model.isLoadingHistory = true
        #expect(log.historyRequests == 1)

        model.prependHistory(.empty(interval: .minutes(1)))

        #expect(!model.isLoadingHistory)
        #expect(model.series.count == 600)
        #expect(log.historyRequests == 1)
    }

    @Test("a page of another interval is a no-op that still finishes the request")
    func foreignPageFinishesRequest() {
        let model = makeModel()
        let log = EventLog(model)
        scroll(model, barsFromStart: 10)
        model.isLoadingHistory = true
        let before = model.series

        model.prependHistory(makeSeries(count: 50, interval: .minutes(5), lastStart: baseTime - 3_000))

        #expect(model.series == before)
        #expect(!model.isLoadingHistory)
        #expect(log.historyRequests == 1)
    }

    @Test("a new series ends the running request but keeps hasMoreHistory")
    func setSeriesEndsRequest() {
        let model = makeModel()
        model.isLoadingHistory = true
        model.hasMoreHistory = false

        model.setSeries(makeSeries(count: 100, interval: .minutes(5), lastStart: baseTime))

        #expect(!model.isLoadingHistory)
        #expect(!model.hasMoreHistory)
    }

    // MARK: - Threshold

    @Test("the threshold in window widths follows the zoom level")
    func thresholdInWindows() {
        let model = makeModel()
        let log = EventLog(model)

        // 40 bars in the window: the threshold is 40 bars.
        scroll(model, barsFromStart: 41)
        #expect(log.historyRequests == 0)
        scroll(model, barsFromStart: 39)
        #expect(log.historyRequests == 1)

        // Zoomed in to 20 bars, the threshold is 20 bars.
        let zoomed = makeModel()
        let zoomedLog = EventLog(zoomed)
        zoomed.zoom(by: 2, anchor: .center)
        #expect(zoomed.visibleBars == 20)
        scroll(zoomed, barsFromStart: 30)
        #expect(zoomedLog.historyRequests == 0)
        scroll(zoomed, barsFromStart: 19)
        #expect(zoomedLog.historyRequests == 1)
    }

    @Test("the threshold in bars does not depend on the zoom level")
    func thresholdInBars() {
        var configuration = TradingChartConfiguration()
        configuration.historyPrefetchThreshold = .bars(100)
        let model = makeModel(configuration: configuration)
        let log = EventLog(model)

        scroll(model, barsFromStart: 101)
        #expect(log.historyRequests == 0)
        scroll(model, barsFromStart: 99)
        #expect(log.historyRequests == 1)
    }

    @Test("a threshold converts to a time span")
    func thresholdDuration() {
        let interval = ChartInterval.minutes(5)
        #expect(HistoryPrefetchThreshold.bars(20).duration(interval: interval, visibleDuration: 999) == 6_000)
        #expect(HistoryPrefetchThreshold.visibleWindows(1.5).duration(interval: interval, visibleDuration: 1_000) == 1_500)
    }

    // MARK: - Prepend

    @Test("prepending does not move the window and fills the warm-up of the indicators")
    func prependIsVisuallyStable() throws {
        let model = makeModel()
        model.indicators = [SMA(period: 20)]
        scroll(model, barsFromStart: 10)
        let scrollPosition = model.scrollPosition
        let visibleRange = model.visibleTimeRange
        let bars = model.visibleBars
        let oldFirst = try #require(model.series.firstTime)
        let before = try #require(model.output(for: "sma(20,close)")?.lines.first?.values)
        #expect(before.first?.time == oldFirst.addingTimeInterval(19 * Self.minute))

        model.prependHistory(page(300, before: oldFirst))

        #expect(model.scrollPosition == scrollPosition)
        #expect(model.visibleTimeRange == visibleRange)
        #expect(model.visibleBars == bars)
        let after = try #require(model.output(for: "sma(20,close)")?.lines.first?.values)
        #expect(after.count == before.count + 300)
        // The bars that used to be the warm-up now have values, and the old values are unchanged.
        #expect(after.contains { $0.time == oldFirst })
        #expect(after.suffix(before.count).map(\.time) == before.map(\.time))
    }

    // MARK: - Scroll binding

    @Test("the chart is given a different position whenever the left end of its domain moves, the model's own position never")
    func scrollNudge() {
        var configuration = TradingChartConfiguration()
        configuration.historyReserveBars = 100
        let model = makeModel(configuration: configuration)
        let position = model.scrollPosition
        #expect(model.chartScrollBinding.wrappedValue == position)

        // Older bars than the reserve holds: the domain grows to the left, the charts have to look at the position again.
        model.prependHistory(page(300, before: model.series.firstTime!))
        let nudged = model.chartScrollBinding.wrappedValue
        #expect(model.scrollPosition == position)
        #expect(nudged != position)
        #expect(abs(nudged.timeIntervalSince(position) - 0.06) < 1e-6)

        // Every move of the left end flips it: back to nothing, then again.
        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(model.chartScrollBinding.wrappedValue == position)
        model.setSeries(page(50, before: model.series.firstTime!), scroll: .preserve)
        #expect(model.chartScrollBinding.wrappedValue != position)
    }

    @Test("a prepend that adds nothing, and updates of the last bar, leave the position alone")
    func scrollNudgeStaysPut() {
        var configuration = TradingChartConfiguration()
        configuration.maxLiveBarCount = nil
        let model = makeModel(configuration: configuration)
        let position = model.scrollPosition

        model.prependHistory(.empty(interval: .minutes(1)))
        model.update(price: 500, at: model.series.lastTime!)
        model.update(price: 501, at: model.series.lastTime!.addingTimeInterval(Self.minute))

        #expect(model.series.count == 601)
        #expect(model.chartScrollBinding.wrappedValue == model.scrollPosition)
        #expect(model.scrollPosition != position)  // the live edge moved with the new bar
    }

    @Test("trimming the head, and a prepend inside the reserve, do not move the domain: no nudge")
    func noNudgeWhileTheDomainStaysPut() {
        let model = makeModel()
        let domainStart = model.chartXDomain.lowerBound
        #expect(model.chartScrollBinding.wrappedValue == model.scrollPosition)

        model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        #expect(model.series.count == 600)
        #expect(model.chartXDomain.lowerBound == domainStart)
        #expect(model.chartScrollBinding.wrappedValue == model.scrollPosition)

        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(model.chartXDomain.lowerBound == domainStart)
        #expect(model.chartScrollBinding.wrappedValue == model.scrollPosition)
    }

    @Test("the binding follows the position and a write through it is ignored: the finger is the input layer's")
    func scrollBindingIsReadOnly() {
        let model = makeModel()
        model.prependHistory(page(300, before: model.series.firstTime!))
        let position = model.scrollPosition
        let binding = model.chartScrollBinding

        binding.wrappedValue = model.series.firstTime!.addingTimeInterval(100 * Self.minute)

        #expect(model.scrollPosition == position)
        let target = model.series.firstTime!.addingTimeInterval(100 * Self.minute)
        model.scrollPosition = target
        #expect(model.chartScrollBinding.wrappedValue == target.addingTimeInterval(model.scrollNudge))
    }

    // MARK: - Trimming

    @Test("a live update never trims the bars around the window")
    func updateKeepsViewedBars() {
        let model = makeModel()
        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(model.series.count == 900)
        scroll(model, barsFromStart: 100)
        let position = model.scrollPosition
        // The window starts 100 bars after the first one, the render buffer reaches 40 bars before it.
        let boundary = model.renderTimeRange.lowerBound
        #expect(boundary == model.series.firstTime!.addingTimeInterval(60 * Self.minute))

        let result = model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))

        #expect(result == .appended)
        #expect(model.scrollPosition == position)
        // 901 bars would be trimmed to 600, but only the 60 bars before the boundary may go.
        #expect(model.series.firstTime == boundary)
        #expect(model.series.count == 841)
        #expect(model.series.candles?.count == 841)
        #expect(model.series.points.count == 841)
        #expect(model.series.indexRange(in: model.visibleTimeRange).count == 41)
    }

    @Test("ticks keep appending without cutting into the viewed bars")
    func ticksAfterPrepend() {
        let model = makeModel()
        model.prependHistory(page(300, before: model.series.firstTime!))
        scroll(model, barsFromStart: 100)
        let viewed = model.series.indexRange(in: model.renderTimeRange).map { model.series.points[$0].time }

        for step in 1...5 {
            model.update(price: 100 + Double(step), at: model.series.lastTime!.addingTimeInterval(Self.minute))
        }

        let remaining = Set(model.series.points.map(\.time))
        #expect(viewed.allSatisfy(remaining.contains))
        #expect(model.series.count > 600)
    }

    @Test("at the live edge the bound applies as before")
    func liveEdgeTrimsToMax() {
        let model = makeModel()
        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(model.isAtLiveEdge)

        model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))

        #expect(model.series.count == 600)
        #expect(model.isAtLiveEdge)
    }

    @Test("returning to the live edge lets the next update trim the surplus")
    func trimsAfterReturningToLiveEdge() {
        let model = makeModel()
        model.prependHistory(page(300, before: model.series.firstTime!))
        scroll(model, barsFromStart: 100)
        model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        #expect(model.series.count > 600)

        model.scrollToLiveEdge()
        model.update(price: 501, at: model.series.lastTime!.addingTimeInterval(Self.minute))

        #expect(model.series.count == 600)
    }

    @Test("a point series is protected the same way")
    func pointSeriesProtection() {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute, candles: false)
        let model = TradingChartModel(series: series, style: .line)
        model.prependHistory(makeSeries(count: 300, lastStart: baseTime - Self.minute, candles: false))
        scroll(model, barsFromStart: 100)
        let boundary = model.renderTimeRange.lowerBound

        model.update(PricePoint(time: model.series.lastTime!.addingTimeInterval(Self.minute), value: Double(500)))

        #expect(model.series.firstTime! <= boundary)
        #expect(model.series.count > 600)
    }

    @Test("without maxLiveBarCount nothing is trimmed")
    func noBound() {
        var configuration = TradingChartConfiguration()
        configuration.maxLiveBarCount = nil
        let model = makeModel(configuration: configuration)

        model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))

        #expect(model.series.count == 601)
    }

    @Test("while history is loading no live update cuts the head, so the page fits the series without a hole")
    func noTrimWhileHistoryIsLoading() throws {
        let model = makeModel()
        let oldFirst = try #require(model.series.firstTime)
        model.isLoadingHistory = true

        // The request is out; live bars arrive at a series that is at its bound.
        for step in 1...5 {
            model.update(price: 500 + Double(step), at: model.series.lastTime!.addingTimeInterval(Self.minute))
        }
        #expect(model.series.firstTime == oldFirst)
        #expect(model.series.count == 605)
        #expect(model.series.points.count == 605)

        model.prependHistory(page(300, before: oldFirst))

        let times = model.series.points.map(\.time)
        #expect(times.count == 905)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == Self.minute })  // no hole
        #expect(model.series.candles?.count == 905)
        #expect(!model.isLoadingHistory)
    }

    @Test("the same for the other ways in: a candle, a point and a tick")
    func noTrimWhileLoadingByAnyUpdate() {
        let candles = makeModel()
        candles.isLoadingHistory = true
        candles.update(Candle(time: candles.series.lastTime!.addingTimeInterval(Self.minute), open: 1, high: 2, low: 1, close: 1.5))
        #expect(candles.series.count == 601)

        let series = makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute, candles: false)
        let points = TradingChartModel(series: series, style: .line)
        points.isLoadingHistory = true
        points.update(PricePoint(time: points.series.lastTime!.addingTimeInterval(Self.minute), value: Double(500)))
        #expect(points.series.count == 601)
    }

    @Test("when the request is over, whether it brought a page or failed, the next update trims the surplus again")
    func trimResumesAfterTheRequest() {
        let model = makeModel()
        model.isLoadingHistory = true
        model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        #expect(model.series.count == 601)

        // A failed request: the host puts the flag back.
        model.isLoadingHistory = false
        model.update(price: 501, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        #expect(model.series.count == 600)

        // A page that arrives: the request ends with it.
        model.isLoadingHistory = true
        model.update(price: 502, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        model.prependHistory(page(100, before: model.series.firstTime!))
        #expect(model.series.count == 701)
        model.update(price: 503, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        #expect(model.series.count == 600)
    }

    // MARK: - Loading indicator

    @Test("the spinner shows while loading and the oldest bar is in the window or one window away")
    func spinnerVisibility() {
        let first = date(baseTime)
        let width = 40 * Self.minute
        func window(startingAt offset: TimeInterval) -> ClosedRange<Date> {
            first.addingTimeInterval(offset)...first.addingTimeInterval(offset + width)
        }

        #expect(HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: 0)))
        #expect(HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: -Self.minute)))
        #expect(HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: width - 1)))
        #expect(!HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: width)))
        #expect(!HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: 5_000)))
        #expect(!HistoryLoadingIndicator.isVisible(isLoading: false, firstTime: first, visibleRange: window(startingAt: 0)))
        #expect(!HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: nil, visibleRange: window(startingAt: 0)))
        // The oldest bar to the right of the window: nothing to show at the left edge.
        #expect(!HistoryLoadingIndicator.isVisible(isLoading: true, firstTime: first, visibleRange: window(startingAt: -width - 1)))
    }
}
