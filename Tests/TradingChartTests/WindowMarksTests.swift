import Foundation
import Testing
@testable import TradingChart

@Suite("High and low markers")
struct HighLowMarksTests {
    /// 100 one-minute candles; candle `i` spans open 100 + i ... close 101 + i, low = open - 1, high = open + 2.
    private let series = makeSeries(count: 100, lastStart: baseTime + 99 * 60)

    private func time(_ index: Int) -> Date {
        date(baseTime + Double(index) * 60)
    }

    private func window(_ first: Int, _ last: Int) -> ClosedRange<Date> {
        time(first)...time(last)
    }

    @Test("candles are marked by their high and low")
    func candleExtremes() throws {
        let extremes = try #require(HighLowMarks.extremes(in: series, style: .candles, range: window(10, 20)))

        // the newest bar of the window has the highest high: open 120 + 2; the oldest the lowest low: open 110 - 1
        #expect(extremes.high == WindowExtreme(time: time(20), value: 122))
        #expect(extremes.low == WindowExtreme(time: time(10), value: 109))
    }

    @Test("line and area series are marked by value")
    func lineExtremes() throws {
        let line = makeSeries(count: 100, lastStart: baseTime + 99 * 60, candles: false)
        let extremes = try #require(HighLowMarks.extremes(in: line, style: .line, range: window(10, 20)))

        // close = open + 1 = 101 + i
        #expect(extremes.high == WindowExtreme(time: time(20), value: 121))
        #expect(extremes.low == WindowExtreme(time: time(10), value: 111))
    }

    @Test("candle style on a point series falls back to values")
    func candlesWithoutOHLC() throws {
        let line = makeSeries(count: 10, lastStart: baseTime + 9 * 60, candles: false)
        #expect(try #require(HighLowMarks.extremes(in: line, style: .candles, range: window(0, 9))).high.value == 110)
    }

    @Test("only bars of the window count, bounds included")
    func windowBounds() throws {
        let inside = try #require(HighLowMarks.extremes(in: series, style: .candles, range: window(40, 41)))
        #expect(inside.high.time == time(41))
        #expect(inside.low.time == time(40))

        // between two bars: nothing inside
        #expect(HighLowMarks.extremes(in: series, style: .candles, range: time(40).addingTimeInterval(10)...time(40).addingTimeInterval(20)) == nil)
    }

    @Test("a window with fewer than two bars has no markers")
    func tooFewBars() {
        #expect(HighLowMarks.extremes(in: series, style: .candles, range: window(5, 5)) == nil)
        #expect(HighLowMarks.extremes(in: series, style: .candles, range: window(500, 600)) == nil)
        #expect(HighLowMarks.extremes(in: .empty(interval: .minutes(1)), style: .line, range: window(0, 10)) == nil)
    }

    @Test("a swing in the middle of the window is found")
    func swingInTheMiddle() throws {
        var candles = series.candles ?? []
        candles[30] = Candle(time: time(30), open: Double(130), high: Double(500), low: Double(129), close: Double(131))
        candles[32] = Candle(time: time(32), open: Double(132), high: Double(133), low: Double(5), close: Double(132))
        let swing = ChartSeries(candles: candles, interval: .minutes(1))
        let extremes = try #require(HighLowMarks.extremes(in: swing, style: .candles, range: window(20, 40)))

        #expect(extremes.high == WindowExtreme(time: time(30), value: 500))
        #expect(extremes.low == WindowExtreme(time: time(32), value: 5))
    }

    @Test("on a tie the earliest bar wins")
    func ties() throws {
        let flat = ChartSeries(
            points: (0..<5).map { PricePoint(time: time($0), value: Double(10)) },
            interval: .minutes(1)
        )
        let extremes = try #require(HighLowMarks.extremes(in: flat, style: .line, range: window(0, 4)))
        #expect(extremes.high.time == time(0))
        #expect(extremes.low.time == time(0))
    }

    @Test("the label goes to the side with more room")
    func labelSide() {
        let range = window(0, 40)
        #expect(!HighLowMarks.labelGoesLeft(of: time(5), in: range))
        #expect(!HighLowMarks.labelGoesLeft(of: time(20), in: range))
        #expect(HighLowMarks.labelGoesLeft(of: time(21), in: range))
        #expect(HighLowMarks.labelGoesLeft(of: time(40), in: range))
        #expect(!HighLowMarks.labelGoesLeft(of: time(40), in: time(0)...time(0)))
    }
}

@Suite("Time axis label fit")
struct TimeAxisLabelFitTests {
    // A 200pt plot showing 100 seconds: 2pt per second.
    private let range = date(1_000)...date(1_100)

    private func fits(_ second: Double, labelWidth: CGFloat = 30, plotWidth: CGFloat = 200) -> Bool {
        TimeAxisLabelFit.fits(tick: date(second), visibleRange: range, plotWidth: plotWidth, labelWidth: labelWidth)
    }

    @Test("a label inside the plot fits")
    func inside() {
        #expect(fits(1_000))
        #expect(fits(1_050))
        // x = 2 * 80 = 160; 160 + 6 + 30 = 196 <= 200
        #expect(fits(1_080))
    }

    @Test("a label that the right edge would cut does not fit")
    func rightEdge() {
        // x = 170; 170 + 6 + 30 = 206 > 200
        #expect(!fits(1_085))
        #expect(!fits(1_100))
        #expect(!fits(1_200))
    }

    @Test("a label whose tick is left of the window does not fit")
    func leftEdge() {
        #expect(!fits(999))
        #expect(!fits(900))
    }

    @Test("a wider label needs more room")
    func widerLabel() {
        #expect(fits(1_080, labelWidth: 30))
        #expect(!fits(1_080, labelWidth: 40))
    }

    @Test("an unmeasured plot or label does not hide anything")
    func unmeasured() {
        #expect(fits(1_500, labelWidth: 0))
        #expect(fits(1_500, plotWidth: 0))
        #expect(TimeAxisLabelFit.fits(tick: date(1_500), visibleRange: date(5)...date(5), plotWidth: 200, labelWidth: 30))
    }
}

@Suite("Current price line span")
struct PriceLineTests {
    private let window = date(1_000)...date(1_600)
    private let yDomain: ClosedRange<Double> = 90...110

    @Test("with the newest bar in the window the line starts at that bar")
    func fromLastBar() {
        #expect(PriceLine.span(lastTime: date(1_500), visibleRange: window, price: 100, yDomain: yDomain)
            == .fromLastBar(date(1_500)))
        // exactly at the right edge still counts as inside
        #expect(PriceLine.span(lastTime: date(1_600), visibleRange: window, price: 100, yDomain: yDomain)
            == .fromLastBar(date(1_600)))
    }

    @Test("with the newest bar left of the window the line starts at that bar too, so it fills the window")
    func newestBarLeftOfWindow() {
        #expect(PriceLine.span(lastTime: date(500), visibleRange: window, price: 100, yDomain: yDomain)
            == .fromLastBar(date(500)))
    }

    @Test("scrolled into the history, with the newest bar right of the window, the line spans the window")
    func fullWidth() {
        #expect(PriceLine.span(lastTime: date(1_601), visibleRange: window, price: 100, yDomain: yDomain) == .fullWidth)
        #expect(PriceLine.span(lastTime: date(9_000), visibleRange: window, price: 100, yDomain: yDomain) == .fullWidth)
    }

    @Test("a series without bars gets a full-width line")
    func noBars() {
        #expect(PriceLine.span(lastTime: nil, visibleRange: window, price: 100, yDomain: yDomain) == .fullWidth)
    }

    @Test("a price outside the visible price range is not drawn")
    func outsideRange() {
        #expect(PriceLine.span(lastTime: date(1_500), visibleRange: window, price: 120, yDomain: yDomain) == .hidden)
        #expect(PriceLine.span(lastTime: date(9_000), visibleRange: window, price: 80, yDomain: yDomain) == .hidden)
        #expect(PriceLine.span(lastTime: date(1_500), visibleRange: window, price: 110, yDomain: yDomain)
            == .fromLastBar(date(1_500)))
    }
}
