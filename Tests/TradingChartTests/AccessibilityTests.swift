import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

/// What VoiceOver does to the chart: the scroll actions of the model and the words it hears.
@MainActor
@Suite("Accessibility")
struct AccessibilityTests {
    private static let minute: TimeInterval = 60

    /// 600 one-minute candles with the window (40 bars) at the live edge, and a clock the test drives.
    private func makeModel() -> (TradingChartModel, ManualClock) {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute)
        let model = TradingChartModel(series: series, style: .candles)
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        let clock = ManualClock()
        model.scrollClock = clock.scrollClock
        return (model, clock)
    }

    // MARK: - Scroll actions

    @Test("earlier moves the window back by exactly one window width")
    func earlier() {
        let (model, _) = makeModel()
        let start = model.scrollPosition
        let moved = model.accessibilityScroll(.earlier)

        #expect(moved)
        #expect(abs(model.scrollPosition.timeIntervalSince(start) + model.visibleDuration) < 1e-6)
        #expect(!model.isAtLiveEdge)
    }

    @Test("later moves the window forward by one window width, and the last step ends at the live edge")
    func later() {
        let (model, _) = makeModel()
        let live = model.scrollPosition
        for _ in 0..<5 { model.accessibilityScroll(.earlier) }
        let far = model.scrollPosition
        #expect(abs(far.timeIntervalSince(live) + 5 * model.visibleDuration) < 1e-6)

        #expect(model.accessibilityScroll(.later))
        #expect(abs(model.scrollPosition.timeIntervalSince(far) - model.visibleDuration) < 1e-6)

        while model.accessibilityScroll(.later) {}
        #expect(model.isAtLiveEdge)
        #expect(model.scrollPosition == live)
    }

    @Test("at the live edge later does nothing, and at the first bar earlier does nothing")
    func limits() {
        let (model, _) = makeModel()
        let live = model.scrollPosition
        #expect(!model.accessibilityScroll(.later))
        #expect(model.scrollPosition == live)

        while model.accessibilityScroll(.earlier) {}
        let first = model.scrollPosition
        #expect(first == model.touchScrollRange.lowerBound)
        #expect(!model.accessibilityScroll(.earlier))
        #expect(model.scrollPosition == first)
    }

    @Test("latest returns to the live edge, and does nothing when the window is there")
    func latest() {
        let (model, _) = makeModel()
        let live = model.scrollPosition
        #expect(!model.accessibilityScroll(.latest))

        model.accessibilityScroll(.earlier)
        model.accessibilityScroll(.earlier)
        #expect(model.accessibilityScroll(.latest))
        #expect(model.scrollPosition == live)
        #expect(model.isAtLiveEdge)
    }

    @Test("an empty chart does not move: no action walks the window into the past, and each says that it did not move")
    func emptyChartDoesNotMove() {
        let model = TradingChartModel(series: .empty(interval: .minutes(1)), style: .candles)
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        let start = model.scrollPosition
        let log = EventLog(model)

        for _ in 0..<5 {
            #expect(!model.accessibilityScroll(.earlier))
            #expect(!model.accessibilityScroll(.later))
            #expect(!model.accessibilityScroll(.latest))
        }
        #expect(model.scrollPosition == start)
        #expect(log.liveEdgeChanges.isEmpty)

        // With bars the same actions scroll.
        model.setSeries(makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute), scroll: .liveEdge)
        #expect(model.accessibilityScroll(.earlier))
    }

    @Test("a scroll action ends a fling and reports the live edge like any other move")
    func endsAFling() {
        let (model, _) = makeModel()
        let log = EventLog(model)
        let ticker = ManualTicker()
        model.frameTicker = ticker.ticker
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 600, plotWidth: 300)
        #expect(ticker.isRunning)

        model.accessibilityScroll(.earlier)

        #expect(!ticker.isRunning)
        #expect(log.liveEdgeChanges == [false])
    }

    @Test("the window after a scroll action follows the zoom: one window is whatever is visible")
    func followsZoom() {
        let (model, _) = makeModel()
        model.zoom(by: 2, anchor: .liveEdge)
        let start = model.scrollPosition
        model.accessibilityScroll(.earlier)
        #expect(abs(start.timeIntervalSince(model.scrollPosition) - model.visibleDuration) < 1e-6)
        #expect(model.visibleBars < 40)
    }

    // MARK: - The window the value describes

    @Test("the window of the accessibility value follows the window once scrolling has come to rest, not on every step")
    func settledWindow() {
        let (model, clock) = makeModel()
        let atRest = model.settledWindow
        #expect(atRest == model.visibleTimeRange)

        model.scrollPosition = model.scrollPosition.addingTimeInterval(-600)
        #expect(model.settledWindow == atRest)  // still the window it came to rest in
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-600)
        #expect(model.settledWindow == atRest)

        clock.advance(by: 0.2)  // scrolling stops
        #expect(model.settledWindow == model.visibleTimeRange)
        #expect(model.settledWindow != atRest)
    }

    @Test("a change of the data or the zoom updates the window of the value at once")
    func settledWindowStructural() {
        let (model, _) = makeModel()
        model.zoom(by: 2, anchor: .liveEdge)
        #expect(model.settledWindow == model.visibleTimeRange)
        model.scrollToLiveEdge()
        model.update(price: 130, at: date(baseTime + 600 * Self.minute))
        #expect(model.settledWindow == model.visibleTimeRange)
    }

    // MARK: - The words

    @Test("the label says what kind of chart it is")
    func label() {
        #expect(ChartAccessibilityText.label(for: .line, strings: english) == "Line chart")
        #expect(ChartAccessibilityText.label(for: .area, strings: english) == "Area chart")
        #expect(ChartAccessibilityText.label(for: .candles, strings: english) == "Candlestick chart")
    }

    private let window = date(1_000_000)...date(1_002_400)
    private func format(_ date: Date) -> String { "t\(Int(date.timeIntervalSince1970 - 1_000_000))" }

    @Test("the value has the last price, the visible range and where the window is")
    func value() {
        #expect(
            ChartAccessibilityText.value(lastPrice: "120.50", window: window, atLiveEdge: true, format: format, strings: english)
                == "Last price 120.50. Showing t0 to t2400. At the latest bar."
        )
        #expect(
            ChartAccessibilityText.value(lastPrice: "120.50", window: window, atLiveEdge: false, format: format, strings: english)
                == "Last price 120.50. Showing t0 to t2400. Scrolled into the past."
        )
        #expect(
            ChartAccessibilityText.value(lastPrice: nil, window: window, atLiveEdge: true, format: format, strings: english)
                == "Showing t0 to t2400. At the latest bar."
        )
    }

    @Test("after a scroll the new range is announced, at a limit the limit is")
    func announcement() {
        #expect(
            ChartAccessibilityText.announcement(after: .earlier, moved: true, window: window, format: format, strings: english)
                == "Showing t0 to t2400"
        )
        #expect(
            ChartAccessibilityText.announcement(after: .earlier, moved: false, window: window, format: format, strings: english)
                == "At the start of the loaded history"
        )
        #expect(
            ChartAccessibilityText.announcement(after: .later, moved: false, window: window, format: format, strings: english)
                == "At the latest bar"
        )
        #expect(
            ChartAccessibilityText.announcement(after: .latest, moved: false, window: window, format: format, strings: english)
                == "At the latest bar"
        )
    }

    @Test("the value of the chart uses the formatters of the host's times")
    func valueWithTheRealFormatter() {
        let formatted = TimeFormatter.automaticString(
            date(baseTime), interval: .minutes(1), context: .crosshair, locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt
        )
        let text = ChartAccessibilityText.value(
            lastPrice: "1.0", window: date(baseTime)...date(baseTime + 60), atLiveEdge: true, format: { _ in formatted }
        )
        #expect(text.contains(formatted))
    }
}
