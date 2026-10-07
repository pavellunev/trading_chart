import Foundation
import SwiftUI
import Testing
@testable import TradingChart

@Suite("Indicator colours")
struct IndicatorPaletteTests {
    private func line(slot: Int, color: ChartColor? = nil) -> IndicatorLine {
        IndicatorLine(id: "l\(slot)", name: "L", values: [], style: IndicatorLineStyle(color: color), paletteSlot: slot)
    }

    private let red = ChartColor(red: 1, green: 0, blue: 0)

    @Test("an indicator takes as many palette positions as its highest slot needs")
    func slotCount() {
        #expect(IndicatorPalette.slotCount(of: .empty) == 0)
        #expect(IndicatorPalette.slotCount(of: IndicatorOutput(lines: [line(slot: 0)])) == 1)
        #expect(IndicatorPalette.slotCount(of: IndicatorOutput(lines: [line(slot: 0), line(slot: 1)])) == 2)
        #expect(IndicatorPalette.slotCount(of: IndicatorOutput(lines: [line(slot: 0), line(slot: 0), line(slot: 0)])) == 1)
        let band = IndicatorBand(id: "b", upper: [], lower: [], paletteSlot: 2)
        #expect(IndicatorPalette.slotCount(of: IndicatorOutput(bands: [band])) == 3)
    }

    @Test("lines with an explicit colour do not take palette positions")
    func explicitColoursTakeNothing() {
        let output = IndicatorOutput(lines: [line(slot: 0, color: red), line(slot: 1, color: red)])
        #expect(IndicatorPalette.slotCount(of: output) == 0)
        let mixed = IndicatorOutput(lines: [line(slot: 0, color: red), line(slot: 1)])
        #expect(IndicatorPalette.slotCount(of: mixed) == 2)
    }

    @Test("every indicator starts where the previous one ended")
    func baseIndices() {
        let single = IndicatorOutput(lines: [line(slot: 0)])
        let pair = IndicatorOutput(lines: [line(slot: 0), line(slot: 1)])
        let histogramOnly = IndicatorOutput(histograms: [IndicatorHistogram(id: "h", name: "H", bars: [])])

        // SMA, Volume (histogram only), MACD (two slots), RSI.
        #expect(IndicatorPalette.baseIndices(for: [single, histogramOnly, pair, single]) == [0, 1, 1, 3])
        #expect(IndicatorPalette.baseIndices(for: []) == [])
    }

    @Test("positions wrap around the palette")
    func position() {
        #expect(IndicatorPalette.position(base: 0, slot: 0, paletteCount: 6) == 0)
        #expect(IndicatorPalette.position(base: 4, slot: 1, paletteCount: 6) == 5)
        #expect(IndicatorPalette.position(base: 5, slot: 1, paletteCount: 6) == 0)
        #expect(IndicatorPalette.position(base: 13, slot: 0, paletteCount: 6) == 1)
        #expect(IndicatorPalette.position(base: 3, slot: -2, paletteCount: 6) == 3)
        #expect(IndicatorPalette.position(base: 3, slot: 0, paletteCount: 0) == 0)
    }

    @Test("the theme wraps palette positions and falls back to the line colour")
    func themeColours() {
        var theme = TradingChartTheme.standard
        theme.indicatorPalette = [.red, .green]
        #expect(theme.paletteColor(at: 0) == .red)
        #expect(theme.paletteColor(at: 3) == .green)
        theme.indicatorPalette = []
        #expect(theme.paletteColor(at: 3) == theme.line)
    }

    @Test("histogram bars are coloured by tone unless a colour is given")
    func histogramColours() {
        let theme = TradingChartTheme.standard
        #expect(theme.histogramColor(tone: .positive, explicit: nil) == theme.bullish)
        #expect(theme.histogramColor(tone: .negative, explicit: nil) == theme.bearish)
        #expect(theme.histogramColor(tone: .neutral, explicit: nil) == theme.axisLabel)
        #expect(theme.histogramColor(tone: .positive, explicit: red) == Color(red))
    }
}

@Suite("Indicator rendering helpers")
struct IndicatorRenderingTests {
    private func values(_ range: Range<Int>, step: TimeInterval = 60) -> [IndicatorValue] {
        range.map { IndicatorValue(time: date(baseTime + Double($0) * step), value: Double($0)) }
    }

    private func window(_ from: Int, _ to: Int) -> ClosedRange<Date> {
        date(baseTime + Double(from) * 60)...date(baseTime + Double(to) * 60)
    }

    // MARK: Culling

    @Test("slicing keeps the values inside the window, bounds included")
    func slicing() {
        let all = values(0..<100)

        let slice = IndicatorRendering.slice(all, in: window(10, 20))

        #expect(slice.map(\.value) == (10...20).map(Double.init))
        #expect(IndicatorRendering.slice(all, in: window(200, 300)).isEmpty)
        #expect(IndicatorRendering.slice(all, in: window(-50, -10)).isEmpty)
        #expect(IndicatorRendering.slice(all, in: window(-50, 500)).count == 100)
        #expect(IndicatorRendering.slice([IndicatorValue](), in: window(0, 10)).isEmpty)
    }

    @Test("histogram bars are sliced the same way")
    func barSlicing() {
        let bars = (0..<50).map { HistogramBar(time: date(baseTime + Double($0) * 60), value: Double($0)) }
        #expect(IndicatorRendering.slice(bars, in: window(5, 9)).map(\.value) == [5, 6, 7, 8, 9])
    }

    @Test("indicator marks are limited to the visible window plus the render buffer")
    @MainActor
    func indicatorCulling() {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * 60)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = [EchoIndicator()]
        let output = model.output(for: "echo")!
        let line = output.lines[0]

        let drawn = IndicatorRendering.slice(line.values, in: model.renderTimeRange)

        // The same bars the series itself draws, a small fraction of the 600 calculated values.
        #expect(drawn.count == series.indexRange(in: model.renderTimeRange).count)
        #expect(drawn.count == 75)
        #expect(drawn.count < line.values.count / 4)

        model.configuration.renderBufferWindows = 0
        #expect(IndicatorRendering.slice(line.values, in: model.renderTimeRange).count == 35)
    }

    @Test("zooming out widens the render window with the visible bars, not beyond")
    @MainActor
    func cullingFollowsZoom() {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * 60)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = [EchoIndicator()]
        model.zoom(by: 0.1, anchor: .liveEdge)
        #expect(model.visibleBars == 400)

        let drawn = IndicatorRendering.slice(model.output(for: "echo")!.lines[0].values, in: model.renderTimeRange)

        #expect(drawn.count <= 600)
        #expect(drawn.count > 400)
    }

    // MARK: Lookups

    @Test("exact lookups find a value only at its own time")
    func exactLookup() {
        let all = values(0..<10)
        #expect(IndicatorRendering.value(in: all, at: date(baseTime + 3 * 60)) == 3)
        #expect(IndicatorRendering.value(in: all, at: date(baseTime + 3 * 60 + 1)) == nil)
        #expect(IndicatorRendering.value(in: all, at: date(baseTime - 60)) == nil)
        #expect(IndicatorRendering.value(in: all, at: date(baseTime + 99 * 60)) == nil)

        let bars = [HistogramBar(time: date(baseTime), value: 4, tone: .positive)]
        #expect(IndicatorRendering.bar(in: bars, at: date(baseTime))?.value == 4)
        #expect(IndicatorRendering.bar(in: bars, at: date(baseTime + 1)) == nil)
    }

    // MARK: Bands

    @Test("band points need both edges at the same time")
    func bandPoints() {
        let upper = (0..<10).map { IndicatorValue(time: date(baseTime + Double($0) * 60), value: 10 + Double($0)) }
        let lower = (3..<12).map { IndicatorValue(time: date(baseTime + Double($0) * 60), value: Double($0)) }

        let points = IndicatorRendering.bandPoints(upper: upper, lower: lower, in: window(0, 20))

        #expect(points.map(\.time) == (3..<10).map { date(baseTime + Double($0) * 60) })
        #expect(points.first == BandPoint(time: date(baseTime + 180), upper: 13, lower: 3))
        #expect(IndicatorRendering.bandPoints(upper: upper, lower: lower, in: window(5, 6)).count == 2)
        #expect(IndicatorRendering.bandPoints(upper: upper, lower: [], in: window(0, 20)).isEmpty)
    }

    // MARK: Pane Y domain

    private func output(_ numbers: [Double], baseline: Double? = nil) -> IndicatorOutput {
        let vs = numbers.enumerated().map { IndicatorValue(time: date(baseTime + Double($0) * 60), value: $1) }
        if let baseline {
            let bars = vs.map { HistogramBar(time: $0.time, value: $0.value) }
            return IndicatorOutput(histograms: [IndicatorHistogram(id: "h", name: "H", bars: bars, baseline: baseline)])
        }
        return IndicatorOutput(lines: [IndicatorLine(id: "l", name: "L", values: vs)])
    }

    private func expectDomain(
        _ domain: ClosedRange<Double>,
        _ low: Double,
        _ high: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(domain.lowerBound - low) < 1e-9, sourceLocation: sourceLocation)
        #expect(abs(domain.upperBound - high) < 1e-9, sourceLocation: sourceLocation)
    }

    @Test("a pane autoscales to the values in the window and pads the span")
    func autoscale() {
        let domain = IndicatorRendering.paneYDomain(
            output: output([10, 20, 30, 1_000]),
            visibleRange: window(0, 2),
            paddingFraction: 0.1
        )
        // Window values 10...30, span 20, padding 2 on each side; the value outside the window is ignored.
        expectDomain(domain, 8, 32)
    }

    @Test("a histogram contributes its baseline")
    func histogramBaseline() {
        let domain = IndicatorRendering.paneYDomain(
            output: output([5, 8, 6], baseline: 0),
            visibleRange: window(0, 2),
            paddingFraction: 0.1
        )
        expectDomain(domain, -0.8, 8.8)
    }

    @Test("a fixed range is used and padded, so end-tick labels stay inside the pane")
    func fixedRange() {
        var rsi = output([30, 40, 50])
        rsi.fixedRange = 0...100
        let domain = IndicatorRendering.paneYDomain(output: rsi, visibleRange: window(0, 2), paddingFraction: 0.08)
        expectDomain(domain, -8, 108)
    }

    @Test("reference levels are inside an autoscaled domain")
    func levelsAreIncluded() {
        var withLevel = output([10, 12])
        withLevel.levels = [IndicatorLevel(id: "x", value: 20)]
        let domain = IndicatorRendering.paneYDomain(output: withLevel, visibleRange: window(0, 1), paddingFraction: 0)
        expectDomain(domain, 10, 20)
    }

    // MARK: Pane axis labels

    @Test("pane axis labels use the compact context, whole numbers on a fixed range")
    func paneAxisLabels() {
        let contexts = PriceFormatter { value, context in
            "\(context == .compact ? "compact" : "other"):\(value)"
        }

        #expect(IndicatorRendering.paneAxisLabel(3_000, hasFixedRange: false, formatter: contexts) == "compact:3000.0")
        #expect(IndicatorRendering.paneAxisLabel(-6.5, hasFixedRange: false, formatter: contexts) == "compact:-6.5")
        #expect(IndicatorRendering.paneAxisLabel(49.6, hasFixedRange: true, formatter: contexts) == "compact:50.0")
    }

    @Test("with the automatic formatter a volume reads 3K and an RSI tick 50")
    func paneAxisLabelsAutomatic() {
        #expect(PriceFormatter.automaticString(3_000, context: .compact, locale: Locale(identifier: "ru_RU")) == "3K")
        #expect(PriceFormatter.automaticString(3_000, context: .compact, locale: Locale(identifier: "en_US")) == "3K")
        #expect(PriceFormatter.automaticString(50, context: .compact, locale: Locale(identifier: "en_US")) == "50")
    }

    @Test("a flat window opens up, an empty window falls back to 0...1")
    func degenerateDomains() {
        let flat = IndicatorRendering.paneYDomain(output: output([50, 50]), visibleRange: window(0, 1), paddingFraction: 0.08)
        expectDomain(flat, 49.5, 50.5)

        let empty = IndicatorRendering.paneYDomain(output: output([1, 2]), visibleRange: window(10, 20), paddingFraction: 0.08)
        expectDomain(empty, 0, 1)
    }
}

@Suite("Legend and crosshair layout")
struct LegendTests {
    private func candle(open: Double, close: Double) -> Candle {
        Candle(time: date(baseTime), open: open, high: max(open, close) + 1, low: min(open, close) - 1, close: close)
    }

    @Test("the change is measured against the open of the bar by default")
    func changeAgainstOpenByDefault() throws {
        let state = CrosshairState(time: date(baseTime), candle: candle(open: 100, close: 105), value: 105, previousClose: 104)
        #expect(abs(try #require(LegendFormatter.change(of: state)) - 5) < 1e-9)
        #expect(abs(try #require(LegendFormatter.changePercent(of: state)) - 5) < 1e-9)

        let down = CrosshairState(time: date(baseTime), candle: candle(open: 120, close: 90), value: 90, previousClose: 100)
        #expect(abs(try #require(LegendFormatter.changePercent(of: down)) + 25) < 1e-9)
    }

    @Test("the previous close is available as the reference")
    func changeAgainstPreviousClose() throws {
        let state = CrosshairState(time: date(baseTime), candle: candle(open: 100, close: 105), value: 105, previousClose: 104)
        #expect(abs(try #require(LegendFormatter.change(of: state, against: .previousClose)) - 1) < 1e-9)
        let first = CrosshairState(time: date(baseTime), candle: candle(open: 200, close: 190), value: 190)
        #expect(abs(try #require(LegendFormatter.changePercent(of: first, against: .previousClose)) + 5) < 1e-9)
    }

    @Test("a point series has no open: the previous value is the reference")
    func changeOfPointSeries() throws {
        let state = CrosshairState(time: date(baseTime), value: 90, previousClose: 120)
        #expect(abs(try #require(LegendFormatter.changePercent(of: state)) + 25) < 1e-9)
    }

    @Test("a single bar is measured against its own open")
    func changeOfFirstBar() throws {
        let state = CrosshairState(time: date(baseTime), candle: candle(open: 200, close: 190), value: 190)
        #expect(abs(try #require(LegendFormatter.changePercent(of: state)) + 5) < 1e-9)
    }

    @Test("no reference, no change")
    func changeWithoutReference() {
        #expect(LegendFormatter.changePercent(of: CrosshairState(time: date(baseTime), value: 10)) == nil)
        #expect(LegendFormatter.changePercent(of: CrosshairState(time: date(baseTime), value: 10, previousClose: 0)) == nil)
        let zeroOpen = CrosshairState(time: date(baseTime), candle: candle(open: 0, close: 1), value: 1, previousClose: 5)
        #expect(LegendFormatter.changePercent(of: zeroOpen) == nil)
    }

    @Test("the time label sits at the share of the window the bar has")
    func labelPosition() {
        let window = date(1_000)...date(1_100)
        #expect(CrosshairLayout.x(of: date(1_025), visibleRange: window, plotWidth: 200) == 50)
        #expect(CrosshairLayout.x(of: date(1_100), visibleRange: window, plotWidth: 200) == 200)
        #expect(CrosshairLayout.x(of: date(1_300), visibleRange: window, plotWidth: 200) == nil)
        #expect(CrosshairLayout.x(of: date(1_050), visibleRange: window, plotWidth: 0) == nil)
    }

    @Test("a label is kept inside the plot")
    func labelClamp() {
        #expect(CrosshairLayout.clamped(5, width: 90, plotWidth: 300) == 45)
        #expect(CrosshairLayout.clamped(299, width: 90, plotWidth: 300) == 255)
        #expect(CrosshairLayout.clamped(150, width: 90, plotWidth: 300) == 150)
        #expect(CrosshairLayout.clamped(10, width: 90, plotWidth: 60) == 30)
    }
}
