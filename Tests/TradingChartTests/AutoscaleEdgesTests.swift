import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

@Suite("Autoscale edges")
struct AutoscaleEdgesTests {
    private func values(_ pairs: [(Double, Double)]) -> [IndicatorValue] {
        pairs.map { IndicatorValue(time: date($0.0), value: $0.1) }
    }

    private func output(_ pairs: [(Double, Double)]) -> IndicatorOutput {
        IndicatorOutput(lines: [IndicatorLine(id: "line", name: "Line", values: values(pairs))])
    }

    private func candle(_ time: Double, open: Double, high: Double, low: Double, close: Double) -> Candle {
        Candle(time: date(time), open: open, high: high, low: low, close: close, volume: 1)
    }

    private let window = date(100)...date(200)

    // MARK: - Lines

    @Test("a line that runs in from outside shows its value at the edge, between the two points that straddle it")
    func lineAtTheEdges() {
        // Points at 80 (value 10), 120 (30), 180 (50), 220 (10): the window cuts the segments 80..120 and 180..220.
        let line = output([(80, 10), (120, 30), (180, 50), (220, 10)])
        let ranges = AutoscaleEdges.paneRanges(of: line, window: window, margin: 0)
        #expect(ranges.count == 2)
        // At 100 the first segment is half way between 10 and 30; at 200 the last is half way between 50 and 10.
        #expect(ranges[0] == 20...20)
        #expect(ranges[1] == 30...30)
    }

    @Test("a point on the edge, or no point on one side of it, adds nothing: the line stops there or is a point inside")
    func lineWithoutAStraddle() {
        let line = output([(100, 10), (150, 20), (200, 30)])
        #expect(AutoscaleEdges.paneRanges(of: line, window: window, margin: 0).isEmpty)
        // A line that starts after the left edge has nothing on the left; the right edge is straddled.
        let late = output([(130, 10), (180, 20), (230, 40)])
        let ranges = AutoscaleEdges.paneRanges(of: late, window: window, margin: 0)
        #expect(ranges.count == 1)
        #expect(abs(ranges[0].lowerBound - 28) < 1e-9)
    }

    @Test("with a slack the line is followed beyond the edges: its points there and its value where the stretch ends")
    func lineSlack() {
        // Points every 40 s; the window is 100...200, the slack 10 s: 90...210.
        let line = output([(80, 10), (95, 40), (120, 30), (180, 50), (205, 5), (220, 90)])
        let ranges = AutoscaleEdges.paneRanges(of: line, window: window, margin: 0, slack: 10)
        // The points at 95 and 205 are outside the window and inside the slack; the line is at 80..95 -> 90: 10 + 30 * (10/15)
        // = 30 at 90 and at 210: 5 + 85 * (5/15) between 205 and 220.
        #expect(ranges.contains(40...40))
        #expect(ranges.contains(5...5))
        #expect(ranges.contains { abs($0.lowerBound - 30) < 1e-9 })
        #expect(ranges.contains { abs($0.lowerBound - (5 + 85.0 * 5 / 15)) < 1e-9 })
        #expect(ranges.count == 4)
    }

    @Test("the edge of a band is followed on its upper and its lower side")
    func bandEdges() {
        let band = IndicatorBand(
            id: "band",
            upper: values([(80, 30), (120, 50)]),
            lower: values([(80, 10), (120, 20)])
        )
        let ranges = AutoscaleEdges.paneRanges(of: IndicatorOutput(bands: [band]), window: window, margin: 0)
        #expect(ranges.contains(40...40))
        #expect(ranges.contains(15...15))
        #expect(ranges.count == 2)
    }

    // MARK: - Bars

    @Test("the body of a candle whose centre is just outside the window counts, its wick only when it is closer still")
    func candleBodies() {
        let candles = [
            candle(80, open: 10, high: 99, low: 1, close: 12),  // 20 s outside
            candle(90, open: 20, high: 90, low: 2, close: 25),  // 10 s outside
            candle(150, open: 50, high: 60, low: 40, close: 55),
            candle(205, open: 30, high: 70, low: 5, close: 35),  // 5 s outside
            candle(230, open: 3, high: 999, low: -999, close: 4),  // 30 s outside
        ]
        let series = ChartSeries(candles: candles, interval: .minutes(1))
        let ranges = AutoscaleEdges.ranges(series: series, style: .candles, overlays: [], window: window, margin: 12, wickMargin: 6)

        // The left neighbour is 10 s away: within the body's margin (12), not the wick's (6): the body only.
        #expect(ranges.contains(20...25))
        // The right neighbour is 5 s away: within the wick's margin: all of it.
        #expect(ranges.contains(5...70))
        // Nothing for the bars that are farther out.
        #expect(!ranges.contains { $0.upperBound > 900 || $0.upperBound == 99 })
        #expect(ranges.count == 2)
    }

    @Test("a line series is followed through its points like any line")
    func lineSeries() {
        let points = [(80.0, 10.0), (120.0, 30.0), (180.0, 50.0), (220.0, 10.0)].map { PricePoint(time: date($0.0), value: $0.1) }
        let series = ChartSeries(points: points, interval: .minutes(1))
        let ranges = AutoscaleEdges.ranges(series: series, style: .line, overlays: [], window: window, margin: 5, wickMargin: 1)
        #expect(ranges == [20...20, 30...30])
    }

    @Test("histogram bars that are half in view count with their baseline")
    func histogramBars() {
        let bars = [
            HistogramBar(time: date(95), value: 8),  // 5 s outside
            HistogramBar(time: date(150), value: 3),
            HistogramBar(time: date(215), value: 9),  // 15 s outside
        ]
        let output = IndicatorOutput(histograms: [IndicatorHistogram(id: "h", name: "H", bars: bars)])
        let ranges = AutoscaleEdges.paneRanges(of: output, window: window, margin: 6)
        #expect(ranges == [0...8])
    }

    // MARK: - In the extent of a pane

    @Test("a pane's extent holds the value of its line at the edges when it is given a margin, and only then")
    func paneExtent() {
        let line = output([(80, 10), (120, 30), (180, 50), (220, 90)])
        let inside = IndicatorRendering.paneYExtent(output: line, visibleRange: window)
        #expect(inside == 30...50)
        let edged = IndicatorRendering.paneYExtent(output: line, visibleRange: window, edgeMargin: 5)
        #expect(edged == 20...(50 + (90 - 50) * 0.5))
        #expect(edged!.upperBound == 70)
    }

    @Test("a window with no point inside is still scaled to what crosses it")
    func paneExtentWithoutPointsInside() {
        let line = output([(50, 10), (250, 90)])
        #expect(IndicatorRendering.paneYExtent(output: line, visibleRange: window) == nil)
        let edged = IndicatorRendering.paneYExtent(output: line, visibleRange: window, edgeMargin: 5)
        #expect(edged == 30...70)
    }
}

@Suite("Autoscale with values that are not finite")
struct AutoscaleNonFiniteTests {
    private let window = date(100)...date(200)

    private func output(_ pairs: [(Double, Double)]) -> IndicatorOutput {
        IndicatorOutput(lines: [
            IndicatorLine(id: "line", name: "Line", values: pairs.map { IndicatorValue(time: date($0.0), value: $0.1) })
        ])
    }

    @Test("a line with a value that is not finite adds nothing at the edges where it is, and the rest is as before")
    func edgesIgnoreBadValues() {
        // At 100 the line is between NaN and 30, at 200 between inf and 10 (both NaN by interpolation).
        let bad = output([(80, .nan), (120, 30), (180, .infinity), (220, 10), (260, 20)])
        let ranges = AutoscaleEdges.paneRanges(of: bad, window: window, margin: 6, slack: 30)
        #expect(ranges.allSatisfy { $0.lowerBound.isFinite && $0.upperBound.isFinite })
        // The point at 220 is outside the window and inside the slack: it is held; the edge values are not made.
        #expect(ranges.contains(10...10))

        let histogram = IndicatorOutput(histograms: [
            IndicatorHistogram(id: "h", name: "H", bars: [HistogramBar(time: date(95), value: .nan)], baseline: .nan)
        ])
        #expect(AutoscaleEdges.paneRanges(of: histogram, window: window, margin: 6).isEmpty)
    }

    @Test("the extent and the domain of a pane with values that are not finite exist")
    func paneWithBadValues() {
        let bad = output([(110, .nan), (150, 5), (190, .infinity)])
        #expect(IndicatorRendering.paneYExtent(output: bad, visibleRange: window, edgeMargin: 5) == 5...5)

        let levels = IndicatorOutput(
            lines: bad.lines,
            levels: [IndicatorLevel(id: "a", value: .nan), IndicatorLevel(id: "b", value: .infinity), IndicatorLevel(id: "c", value: 9)]
        )
        #expect(IndicatorRendering.paneYExtent(output: levels, visibleRange: window) == 5...9)

        // A fixed range with an end that is not finite is not used.
        var fixed = output([(150, 5)])
        fixed.fixedRange = 0...Double.infinity
        #expect(IndicatorRendering.paneYExtent(output: fixed, visibleRange: window) == 5...5)

        #expect(IndicatorRendering.paneYDomain(extent: 1...Double.infinity, paddingFraction: 0.1) == 0...1)
        #expect(IndicatorRendering.paneYDomain(extent: -Double.infinity...2, paddingFraction: 0.1) == 0...1)
        #expect(IndicatorRendering.paneYDomain(extent: nil, paddingFraction: 0.1) == 0...1)
    }

    @Test("a base domain for a target that is not finite is the target itself")
    func baseOfAnUnboundedTarget() {
        #expect(YTransformMath.base(for: -Double.infinity...Double.infinity) == -Double.infinity...Double.infinity)
        #expect(YTransformMath.base(for: 0...1) == -1...2)
    }
}

@MainActor
@Suite("Autoscale of the model at the edges of the window")
struct ModelAutoscaleEdgeTests {
    @Test("the shown domain holds the line where it crosses the edge of the window, not only the points inside")
    func domainHoldsTheEdges() {
        // Closes rise by one a bar. A line series with a window that starts and ends half way between two bars.
        let series = makeSeries(count: 300, lastStart: baseTime + 299 * 60, candles: false)
        let model = TradingChartModel(series: series, style: .line)
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        let first = model.series.firstTime!
        model.scrollPosition = first.addingTimeInterval(100.5 * 60)

        let visible = model.visibleTimeRange
        let barSeconds = 60.0
        func value(at time: Date) -> Double { 101 + time.timeIntervalSince(first) / barSeconds }  // close of bar i is 101 + i
        // The line is followed a little beyond each edge (the chart can trail the window by a pixel or two).
        let slack = model.edgeSlack
        #expect(slack > 0)
        let low = value(at: visible.lowerBound.addingTimeInterval(-slack))
        let high = value(at: visible.upperBound.addingTimeInterval(slack))
        let padding = (high - low) * model.viewport.verticalPaddingFraction

        // The points inside the window are the bars 101 to 160, a half bar inside each edge: the line is followed from
        // there to the edges and a little beyond them.
        #expect(abs(model.mainYTarget.lowerBound - (low - padding)) < 1e-6)
        #expect(abs(model.mainYTarget.upperBound - (high + padding)) < 1e-6)
    }
}
