import Foundation
import Testing
@testable import TradingChart

@MainActor
@Suite("Crosshair and pinch zoom")
struct CrosshairTests {

    // MARK: - Snapping

    @Test("the crosshair snaps to the nearest bar")
    func snapsBetweenBars() {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)
        let bar = series.points[50].time

        model.crosshairTime = bar.addingTimeInterval(20)
        #expect(model.crosshair?.time == bar)

        model.crosshairTime = bar.addingTimeInterval(40)
        #expect(model.crosshair?.time == series.points[51].time)

        model.crosshairTime = bar.addingTimeInterval(-40)
        #expect(model.crosshair?.time == series.points[49].time)
    }

    @Test("times outside the series snap to the first or the last bar")
    func snapsAtTheEdges() {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)

        model.crosshairTime = series.firstTime!.addingTimeInterval(-3_600)
        #expect(model.crosshair?.time == series.firstTime)

        // The right padding of the x domain lies beyond the last bar.
        model.crosshairTime = series.lastTime!.addingTimeInterval(5 * 60)
        #expect(model.crosshair?.time == series.lastTime)
    }

    @Test("a candle bar reports the candle, its close and the previous close")
    func candleState() throws {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)

        model.crosshairTime = series.points[30].time.addingTimeInterval(5)
        let state = try #require(model.crosshair)

        #expect(state.candle == series.candles?[30])
        #expect(state.value == series.candles?[30].close)
        #expect(state.previousClose == series.candles?[29].close)
    }

    @Test("the first bar has no previous close")
    func firstBarHasNoPreviousClose() throws {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)

        model.crosshairTime = series.firstTime
        let state = try #require(model.crosshair)

        #expect(state.time == series.firstTime)
        #expect(state.previousClose == nil)
    }

    @Test("a point series reports the value without a candle")
    func pointSeriesState() throws {
        let series = makeSeries(count: 100, candles: false)
        let model = TradingChartModel(series: series, style: .line)

        model.crosshairTime = series.points[70].time
        let state = try #require(model.crosshair)

        #expect(state.candle == nil)
        #expect(state.value == series.points[70].value)
        #expect(state.previousClose == series.points[69].value)
    }

    @Test("there is no crosshair without a selection, without data or when disabled")
    func noCrosshair() {
        let model = TradingChartModel(series: makeSeries(count: 100), style: .candles)
        #expect(model.crosshair == nil)

        model.crosshairTime = date(baseTime)
        #expect(model.crosshair != nil)

        model.configuration.isCrosshairEnabled = false
        #expect(model.crosshairTime == nil)
        #expect(model.crosshair == nil)

        let empty = TradingChartModel()
        empty.crosshairTime = Date()
        #expect(empty.crosshair == nil)
    }

    @Test("the latest bar state feeds the legend while there is no crosshair")
    func latestBarState() throws {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)

        let state = try #require(model.latestBarState)
        #expect(state.time == series.lastTime)
        #expect(state.previousClose == series.candles?[98].close)
        #expect(TradingChartModel().latestBarState == nil)
    }

    // MARK: - Indicator values

    @Test("indicator values at the snapped bar carry names, colours, palette positions and tones")
    func indicatorValues() throws {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = [EchoIndicator(), PaletteIndicator()]

        model.crosshairTime = series.points[99].time
        let values = try #require(model.crosshair).indicatorValues

        // Echo takes palette position 0; the palette indicator starts at 1 (its colour-less lines use slots 0 and 1).
        #expect(values.map(\.indicatorID) == ["echo", "palette", "palette", "palette", "palette"])
        #expect(values.map(\.name) == ["Echo", "A", "B", "C", "H"])
        #expect(values[0].paletteIndex == 0)
        #expect(values[1].paletteIndex == 1)
        #expect(values[2].color == ChartColor(red: 1, green: 0, blue: 0))
        #expect(values[2].paletteIndex == nil)
        #expect(values[3].paletteIndex == 2)
        #expect(values[4].tone == .negative)
        #expect(values[4].value == -2)
        #expect(values[1].value == 99)
    }

    @Test("a line inside its warm-up has no value at the crosshair")
    func warmUpIsSkipped() throws {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)
        model.indicators = [PaletteIndicator()]

        model.crosshairTime = series.points[5].time
        let values = try #require(model.crosshair).indicatorValues

        // Only line A is defined at bar 5; B and C start at bar 10 and the histogram covers the last three bars.
        #expect(values.map(\.name) == ["A"])
    }

    @Test("palette positions are dealt out per indicator")
    func paletteBases() {
        let model = TradingChartModel(series: makeSeries(count: 50), style: .candles)
        model.indicators = [EchoIndicator(), PaletteIndicator()]

        #expect(model.paletteBase(for: "echo") == 0)
        #expect(model.paletteBase(for: "palette") == 1)
        #expect(model.paletteBase(for: "unknown") == 0)

        model.indicators = [PaletteIndicator(), EchoIndicator()]
        #expect(model.paletteBase(for: "palette") == 0)
        #expect(model.paletteBase(for: "echo") == 2)
    }

    // MARK: - Events

    @Test("crosshairChanged fires when the snapped bar changes, not on every raw time")
    func crosshairEvents() {
        let series = makeSeries(count: 100)
        let model = TradingChartModel(series: series, style: .candles)
        let log = EventLog(model)
        let bar = series.points[50].time

        model.crosshairTime = bar.addingTimeInterval(5)
        model.crosshairTime = bar.addingTimeInterval(12)
        model.crosshairTime = bar.addingTimeInterval(-9)
        #expect(log.crosshairChanges.count == 1)
        #expect(log.crosshairChanges.first??.time == bar)

        model.crosshairTime = bar.addingTimeInterval(61)
        #expect(log.crosshairChanges.count == 2)
        #expect(log.crosshairChanges.last??.time == series.points[51].time)

        model.crosshairTime = nil
        #expect(log.crosshairChanges.count == 3)
        #expect(log.crosshairChanges.last! == nil)

        model.crosshairTime = nil
        #expect(log.crosshairChanges.count == 3)
    }

    @Test("a new interval drops the crosshair")
    func intervalChangeClearsCrosshair() {
        let model = TradingChartModel(series: makeSeries(count: 100), style: .candles)
        model.crosshairTime = date(baseTime)

        model.setSeries(makeSeries(count: 100, interval: .minutes(5), lastStart: baseTime + 199 * 60))

        #expect(model.crosshairTime == nil)
    }

    // MARK: - Pinch zoom through the model

    @Test("zooming from a baseline does not accumulate and returns to the start width")
    func zoomFromBaseline() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        let baseline = model.zoomBaseline()

        model.zoom(from: baseline, by: 2, anchor: .center)
        #expect(model.visibleBars == 20)
        model.zoom(from: baseline, by: 2, anchor: .center)
        #expect(model.visibleBars == 20)

        model.zoom(from: baseline, by: 1, anchor: .center)
        #expect(model.visibleBars == 40)
        #expect(model.scrollPosition == baseline.scrollPosition)
    }

    @Test("a clamped width is not lost when the pinch reverses")
    func zoomClampDoesNotDrift() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        let baseline = model.zoomBaseline()

        model.zoom(from: baseline, by: 100, anchor: .center)
        #expect(model.visibleBars == 10)

        // The incremental form would need 100x again to get back; relative to the baseline, 1x is the start.
        model.zoom(from: baseline, by: 1, anchor: .center)
        #expect(model.visibleBars == 40)
    }

    @Test("the centre anchor keeps the middle of the window in place")
    func zoomCenterAnchor() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-50 * 60)
        let baseline = model.zoomBaseline()
        let middle = baseline.scrollPosition.addingTimeInterval(20 * 60)

        model.zoom(from: baseline, by: 4, anchor: .center)

        #expect(model.visibleBars == 10)
        #expect(model.scrollPosition.addingTimeInterval(5 * 60) == middle)
        #expect(!model.isAtLiveEdge)
    }

    @Test("the live-edge anchor keeps the newest bar at the right edge through a whole pinch")
    func zoomLiveEdgeAnchor() {
        let series = makeSeries(count: 200)
        let model = TradingChartModel(series: series, style: .candles)
        let baseline = model.zoomBaseline()

        for scale in [1.2, 1.8, 2.5, 1.4] {
            model.zoom(from: baseline, by: scale, anchor: .liveEdge)
            #expect(model.isAtLiveEdge)
            let expected = ViewportMath.endAnchor(
                lastTime: series.lastTime!,
                interval: series.interval,
                visibleBars: model.visibleBars,
                configuration: model.viewport
            )
            #expect(model.scrollPosition == expected)
        }
    }
}
