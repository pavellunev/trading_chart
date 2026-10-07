import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

/// A frame ticker the test drives by hand. Every ticker that was started and not stopped gets every frame, as every display
/// link that is alive would.
@MainActor
final class ManualTicker {
    private final class Run {
        var isActive = true
        let tick: @MainActor (TimeInterval) -> Bool

        init(_ tick: @escaping @MainActor (TimeInterval) -> Bool) {
            self.tick = tick
        }
    }

    private var runs: [Run] = []
    private(set) var starts = 0

    /// Tickers started and not stopped yet (by their stop function, or by answering `false`): each one would be a display link
    /// ticking.
    var activeCount: Int { runs.filter(\.isActive).count }

    var isRunning: Bool { activeCount > 0 }

    var ticker: FrameTicker {
        FrameTicker { [self] tick in
            let run = Run(tick)
            runs.append(run)
            starts += 1
            return { run.isActive = false }
        }
    }

    /// One display frame.
    func advance(by delta: TimeInterval = 1.0 / 60) {
        for run in runs where run.isActive {
            if !run.tick(delta) { run.isActive = false }
        }
    }

    /// Runs frames until every ticker has stopped or `seconds` have passed.
    func run(seconds: TimeInterval) {
        var elapsed = 0.0
        while isRunning, elapsed < seconds {
            advance()
            elapsed += 1.0 / 60
        }
    }
}

@Suite("Deceleration")
struct ScrollDecelerationTests {
    @Test("a fling travels velocity * time constant in the end, and a share of it on the way")
    func distance() {
        #expect(ScrollDeceleration.distance(velocity: 100, elapsed: 0) == 0)
        #expect(abs(ScrollDeceleration.distance(velocity: 100, elapsed: 20) - 100 * ScrollDeceleration.timeConstant) < 1e-9)
        let half = ScrollDeceleration.distance(velocity: 100, elapsed: ScrollDeceleration.timeConstant)
        #expect(abs(half - 100 * ScrollDeceleration.timeConstant * (1 - exp(-1))) < 1e-9)
        #expect(ScrollDeceleration.distance(velocity: -100, elapsed: 1) < 0)
    }

    @Test("the speed falls to 1/e in one time constant, and never below zero time")
    func speed() {
        #expect(ScrollDeceleration.speed(velocity: 100, elapsed: 0) == 100)
        #expect(abs(ScrollDeceleration.speed(velocity: 100, elapsed: ScrollDeceleration.timeConstant) - 100 / exp(1)) < 1e-9)
        #expect(ScrollDeceleration.speed(velocity: 100, elapsed: -5) == 100)
    }
}

@MainActor
@Suite("Scrolling by touch")
struct TouchScrollTests {
    private static let minute: TimeInterval = 60
    private let plotWidth: CGFloat = 300

    /// 600 one-minute candles; the window (40 bars) at the live edge, in a plot 300 points wide.
    private func makeModel(configuration: TradingChartConfiguration = TradingChartConfiguration()) -> (TradingChartModel, ManualTicker) {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute)
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)
        model.updateLayoutMetrics(plotWidth: plotWidth, yAxisColumnWidth: 60)
        let ticker = ManualTicker()
        model.frameTicker = ticker.ticker
        return (model, ticker)
    }

    // MARK: - The finger

    @Test("a drag moves the window by the width of the finger's travel: to the right is to the past")
    func dragMovesTheWindow() {
        let (model, _) = makeModel()
        let start = model.scrollPosition
        model.beginTouchScroll()

        model.touchScroll(translation: 75, plotWidth: plotWidth)  // a quarter of the plot to the right
        #expect(abs(model.scrollPosition.timeIntervalSince(start) + 0.25 * model.visibleDuration) < 1e-6)

        model.touchScroll(translation: 30, plotWidth: plotWidth)  // the translation is from the start of the drag
        #expect(abs(model.scrollPosition.timeIntervalSince(start) + 0.1 * model.visibleDuration) < 1e-6)
    }

    @Test("a drag cannot go before the first bar or past the live edge")
    func dragIsClamped() {
        let (model, _) = makeModel()
        let range = model.touchScrollRange
        model.beginTouchScroll()

        model.touchScroll(translation: 100_000, plotWidth: plotWidth)
        #expect(model.scrollPosition == range.lowerBound)

        model.touchScroll(translation: -100_000, plotWidth: plotWidth)
        #expect(model.scrollPosition == range.upperBound)
        // The live edge is where a new window starts.
        #expect(model.isAtLiveEdge)
    }

    @Test("the range stops at the first bar even when the chart keeps a reserve of empty time before it")
    func rangeIgnoresTheReserve() {
        let (model, _) = makeModel()
        let natural = model.naturalXDomain
        #expect(model.chartXDomain.lowerBound < natural.lowerBound)
        #expect(model.touchScrollRange.lowerBound == natural.lowerBound)
    }

    @Test("a drag that was not begun does nothing")
    func dragWithoutBegin() {
        let (model, _) = makeModel()
        let start = model.scrollPosition
        model.touchScroll(translation: 100, plotWidth: plotWidth)
        #expect(model.scrollPosition == start)
        model.beginTouchScroll()
        model.cancelTouchScroll()
        model.touchScroll(translation: 100, plotWidth: plotWidth)
        #expect(model.scrollPosition == start)
    }

    // MARK: - An empty chart

    @Test("a chart without bars stays where it is under the finger: a drag does not walk the window into the past")
    func emptyChartDoesNotScroll() {
        let model = TradingChartModel(series: .empty(interval: .minutes(1)), style: .candles)
        model.updateLayoutMetrics(plotWidth: plotWidth, yAxisColumnWidth: 60)
        let ticker = ManualTicker()
        model.frameTicker = ticker.ticker
        let start = model.scrollPosition
        let bars = model.visibleBars

        for _ in 0..<20 {
            model.beginTouchScroll()
            model.touchScroll(translation: 50, plotWidth: plotWidth)
            model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        }
        #expect(model.scrollPosition == start)
        #expect(ticker.starts == 0)  // no fling

        model.zoom(by: 2, anchor: .center)
        model.zoom(by: 0.5, anchor: .liveEdge)
        #expect(model.scrollPosition == start)
        #expect(model.visibleBars == bars)

        // With bars the chart scrolls as any other.
        model.setSeries(makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute), scroll: .liveEdge)
        let live = model.scrollPosition
        model.beginTouchScroll()
        model.touchScroll(translation: 75, plotWidth: plotWidth)
        #expect(model.scrollPosition < live)
    }

    // MARK: - The fling

    @Test("a fling keeps the window going and ends where the deceleration says")
    func flingTravels() {
        let (model, ticker) = makeModel()
        let start = model.scrollPosition
        let velocity: CGFloat = 900  // points per second to the right

        model.beginTouchScroll()
        model.endTouchScroll(velocity: velocity, plotWidth: plotWidth)
        #expect(ticker.isRunning)
        ticker.run(seconds: 10)

        #expect(!ticker.isRunning)
        let expected = -Double(velocity) / Double(plotWidth) * model.visibleDuration * ScrollDeceleration.timeConstant
        let travelled = model.scrollPosition.timeIntervalSince(start)
        // It stops when the speed is a few points per second, a little short of the whole distance.
        #expect(travelled < 0)
        #expect(abs(travelled - expected) < abs(expected) * 0.02)
    }

    @Test("the moves of a fling are not outside changes: they do not stop it")
    func flingIsNotStoppedByItself() {
        let (model, ticker) = makeModel()
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        for _ in 0..<30 { ticker.advance() }
        #expect(ticker.isRunning)
        #expect(model.scrollMomentum != nil)
    }

    @Test("a slow lift does not start a fling")
    func slowLift() {
        let (model, ticker) = makeModel()
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 10, plotWidth: plotWidth)
        #expect(!ticker.isRunning)
        #expect(ticker.starts == 0)
    }

    @Test("a fling stops at the first bar")
    func flingStopsAtTheStart() {
        let (model, ticker) = makeModel()
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 20_000, plotWidth: plotWidth)
        ticker.run(seconds: 10)
        #expect(model.scrollPosition == model.touchScrollRange.lowerBound)
        #expect(!ticker.isRunning)
        // A fling into the end it is already at does not start.
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 5_000, plotWidth: plotWidth)
        #expect(!ticker.isRunning)
    }

    @Test("a finger that goes down stops a fling")
    func newTouchStopsIt() {
        let (model, ticker) = makeModel()
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        for _ in 0..<10 { ticker.advance() }
        let position = model.scrollPosition

        model.stopScrollMomentum()  // what ChartInputView.touchesBegan does
        ticker.advance()

        #expect(!ticker.isRunning)
        #expect(model.scrollPosition == position)
    }

    @Test("the host, a zoom or a new series stop a fling too")
    func outsideChangesStopIt() {
        let (model, ticker) = makeModel()
        func fling() {
            model.beginTouchScroll()
            model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
            for _ in 0..<5 { ticker.advance() }
            #expect(ticker.isRunning)
        }

        fling()
        model.scrollToLiveEdge()
        #expect(!ticker.isRunning)
        #expect(model.isAtLiveEdge)

        fling()
        model.zoom(by: 2, anchor: .center)
        #expect(!ticker.isRunning)

        fling()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-600)
        #expect(!ticker.isRunning)

        fling()
        model.setSeries(makeSeries(count: 300, lastStart: baseTime + 299 * Self.minute), scroll: .liveEdge)
        #expect(!ticker.isRunning)
    }

    @Test("history that arrives in the middle of a fling does not disturb it")
    func prependDuringAFling() {
        let (model, ticker) = makeModel()
        let start = model.scrollPosition
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        for _ in 0..<20 { ticker.advance() }
        let before = model.scrollPosition

        model.prependHistory(makeSeries(count: 300, lastStart: model.series.firstTime!.timeIntervalSince1970 - Self.minute))
        #expect(model.scrollPosition == before)
        #expect(ticker.isRunning)

        ticker.run(seconds: 10)
        let travelled = model.scrollPosition.timeIntervalSince(start)
        let expected = -900.0 / Double(plotWidth) * model.visibleDuration * ScrollDeceleration.timeConstant
        #expect(abs(travelled - expected) < abs(expected) * 0.02)
    }

    // MARK: - The crosshair

    @Test("a long press puts the crosshair at the time under the finger, and lifting takes it away")
    func crosshair() {
        let (model, _) = makeModel()
        let visible = model.visibleTimeRange

        model.touchCrosshair(atX: plotWidth / 2, plotWidth: plotWidth)
        #expect(model.crosshairTime == visible.lowerBound.addingTimeInterval(0.5 * model.visibleDuration))
        #expect(model.crosshair != nil)

        model.touchCrosshair(atX: -50, plotWidth: plotWidth)  // clamped to the plot
        #expect(model.crosshairTime == visible.lowerBound)
        model.touchCrosshair(atX: 5_000, plotWidth: plotWidth)
        #expect(model.crosshairTime == visible.upperBound)

        model.clearTouchCrosshair()
        #expect(model.crosshairTime == nil)
        #expect(model.crosshair == nil)
    }

    @Test("with the crosshair switched off a long press does nothing")
    func crosshairDisabled() {
        var configuration = TradingChartConfiguration()
        configuration.isCrosshairEnabled = false
        let (model, _) = makeModel(configuration: configuration)
        model.touchCrosshair(atX: 100, plotWidth: plotWidth)
        #expect(model.crosshairTime == nil)
    }
}
