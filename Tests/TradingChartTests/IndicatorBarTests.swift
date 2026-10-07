import Foundation
import SwiftUI
import Testing
import UIKit
@testable import TradingChart

@Suite("Indicator bar")
struct IndicatorBarTests {
    private let catalog: [any ChartIndicator] = [
        SMA(), EMA(period: 50), BollingerBands(), Volume(), RSI(), MACD(),
    ]

    private func ids(_ indicators: [any ChartIndicator]) -> [String] {
        indicators.map(\.id)
    }

    private func toggle(_ id: String, in current: [any ChartIndicator]) -> [any ChartIndicator] {
        let indicator = catalog.first { $0.id == id }!
        return IndicatorSelection.toggled(current, toggling: indicator, catalog: catalog)
    }

    @Test("the catalog is split into overlays and panes, keeping its order")
    func groups() {
        let groups = IndicatorSelection.groups(of: catalog)

        #expect(groups.overlays.map(\.shortName) == ["MA", "EMA", "BOLL"])
        #expect(groups.panes.map(\.shortName) == ["VOL", "RSI", "MACD"])
    }

    @Test("an id that repeats is listed once")
    func repeatedIDs() {
        let groups = IndicatorSelection.groups(of: catalog + [SMA(), RSI()])
        #expect(groups.overlays.count == 3)
        #expect(groups.panes.count == 3)
    }

    @Test("a tap switches an indicator on, and another tap switches it off")
    func toggleOnAndOff() {
        let on = toggle("rsi(14,70,30)", in: [])
        #expect(ids(on) == ["rsi(14,70,30)"])

        let off = toggle("rsi(14,70,30)", in: on)
        #expect(off.isEmpty)
    }

    @Test("indicators come out in the order of the catalog, whatever order they were switched on in")
    func catalogOrder() {
        var current: [any ChartIndicator] = []
        for id in ["macd(12,26,9)", "bb(20,2,close)", "sma(20,close)", "volume"] {
            current = toggle(id, in: current)
        }

        #expect(ids(current) == ["sma(20,close)", "bb(20,2,close)", "volume", "macd(12,26,9)"])

        current = toggle("sma(20,close)", in: current)
        current = toggle("rsi(14,70,30)", in: current)
        #expect(ids(current) == ["bb(20,2,close)", "volume", "rsi(14,70,30)", "macd(12,26,9)"])
    }

    @Test("indicators the catalog does not know stay, after the catalog ones")
    func foreignIndicators() {
        let custom = WMA(period: 7)
        let current: [any ChartIndicator] = [custom, RSI()]

        let added = toggle("sma(20,close)", in: current)
        #expect(ids(added) == ["sma(20,close)", "rsi(14,70,30)", "wma(7,close)"])

        let removed = toggle("rsi(14,70,30)", in: added)
        #expect(ids(removed) == ["sma(20,close)", "wma(7,close)"])
    }

    @Test("an indicator that is already on keeps its own instance")
    func keepsInstance() {
        let styled = SMA(style: IndicatorLineStyle(width: 4))
        let current = toggle("rsi(14,70,30)", in: [styled])

        let kept = current.first { $0.id == styled.id } as? SMA
        #expect(kept?.style.width == 4)
    }

    @MainActor
    @Test("the model gets the toggled list, drops duplicates and calculates the outputs")
    func modelIntegration() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .candles)

        model.indicators = toggle("volume", in: model.indicators)
        model.indicators = toggle("sma(20,close)", in: model.indicators)

        #expect(ids(model.indicators) == ["sma(20,close)", "volume"])
        #expect(model.output(for: "sma(20,close)") != nil)
        #expect(model.output(for: "volume") != nil)

        model.indicators = toggle("sma(20,close)", in: model.indicators)
        #expect(ids(model.indicators) == ["volume"])
        #expect(model.output(for: "sma(20,close)") == nil)
    }

    @Test("the theme carries the colours and the font of the bar")
    func themeDefaults() {
        let theme = TradingChartTheme.standard
        #expect(theme.indicatorBarSelected != theme.indicatorBarUnselected)
        #expect(theme.indicatorBarDivider != theme.indicatorBarUnselected)
    }

    @Test("the bar is compact by default: labels 14 points apart in a row 30 points high")
    func compactDefaults() {
        let theme = TradingChartTheme.standard
        #expect(theme.indicatorBarSpacing == 14)
        #expect(theme.indicatorBarHeight == 30)
    }

    @MainActor
    @Test("the row is as high as the theme says, whatever the labels, and the theme can change it")
    func rowHeight() {
        let model = TradingChartModel(series: makeSeries(count: 50), style: .candles)
        model.indicators = [SMA()]
        func height(_ theme: TradingChartTheme) -> CGFloat {
            let bar = IndicatorBar(model: model, catalog: catalog).tradingChartTheme(theme)
            return UIHostingController(rootView: bar).sizeThatFits(in: CGSize(width: 390, height: 400)).height
        }
        #expect(height(.standard) == 30)
        var tall = TradingChartTheme.standard
        tall.indicatorBarHeight = 44
        #expect(height(tall) == 44)

        let accessory = IndicatorBar(model: model, catalog: catalog) { Image(systemName: "gearshape") }
        #expect(UIHostingController(rootView: accessory).sizeThatFits(in: CGSize(width: 390, height: 400)).height == 30)
    }
}
