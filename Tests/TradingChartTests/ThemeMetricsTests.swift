import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

@MainActor
@Suite("Candle metrics of the theme")
struct ThemeMetricsTests {
    /// 100 one-minute candles, flat at 100, except the one at index 50: its body runs from 100 to 300.
    private func makeModel() -> TradingChartModel {
        let candles = (0..<100).map { index -> Candle in
            let time = date(baseTime + Double(index) * 60)
            return index == 50
                ? Candle(time: time, open: 100.0, high: 300.0, low: 100.0, close: 300.0)
                : Candle(time: time, open: 100.0, high: 100.5, low: 99.5, close: 100.0)
        }
        let model = TradingChartModel(series: ChartSeries(candles: candles, interval: .minutes(1)), style: .candles)
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        return model
    }

    private func wideCandles() -> CandleMetrics {
        var theme = TradingChartTheme.standard
        theme.candleBodyWidthFactor = 1.0
        theme.wickWidth = 4
        return CandleMetrics(theme: theme)
    }

    @Test("a model that has been told nothing assumes the standard theme")
    func defaults() {
        let model = makeModel()
        #expect(model.candleMetrics == CandleMetrics(theme: .standard))
    }

    @Test("the margins at the edges of the window follow the candle width and the wick width the view reports")
    func marginsFollowTheTheme() {
        let model = makeModel()
        let body = model.edgeMargin
        let wick = model.edgeWickMargin

        model.updateCandleMetrics(wideCandles())

        // 300 pt for 40 bars: 7.5 pt a bar. A body of 0.78 of it is 5.85 pt, of the whole bar 7.5 pt.
        #expect(model.edgeMargin > body)
        #expect(abs(model.edgeMargin - (7.5 / 2 + 1.5) / 300 * model.visibleDuration) < 1e-9)
        #expect(model.edgeWickMargin > wick)
        #expect(abs(model.edgeWickMargin - (4.0 / 2 + 1.5) / 300 * model.visibleDuration) < 1e-9)
    }

    @Test("a candle that is half in view is held by the autoscale as wide as the theme draws it")
    func edgeCandleIsHeld() {
        let model = makeModel()
        // 38 s before the left edge of the window is the centre of the tall candle: farther than the standard theme's
        // margin (35 s), nearer than that of wide candles (42 s).
        let candleTime = date(baseTime + 50 * 60)
        model.scrollPosition = candleTime.addingTimeInterval(38)
        #expect(model.mainYTarget.upperBound < 150)  // the standard theme draws that candle outside the plot

        model.updateCandleMetrics(wideCandles())
        #expect(model.mainYTarget.upperBound > 300)  // the wide candle reaches into the plot, and the scale holds all of it

        model.updateCandleMetrics(CandleMetrics(theme: .standard))
        #expect(model.mainYTarget.upperBound < 150)
    }

    @Test("the same metrics change nothing, and a change recomputes the render state once")
    func sameMetricsAreIgnored() {
        let model = makeModel()
        let revision = model.renderRevision
        model.updateCandleMetrics(CandleMetrics(theme: .standard))
        #expect(model.renderRevision == revision)
        model.updateCandleMetrics(wideCandles())
        #expect(model.renderRevision == revision + 1)
    }
}
