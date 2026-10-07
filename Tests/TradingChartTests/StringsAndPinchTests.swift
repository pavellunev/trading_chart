import SwiftUI
import Testing
import TradingChartCore
import UIKit
@testable import TradingChart

private let plainFormatter = PriceFormatter { value, _ in String(format: "%.2f", value) }

/// German, to be sure that nothing of the English one is left in what is said.
private func german() -> TradingChartStrings {
    var strings = english
    strings.lineChart = "Liniendiagramm"
    strings.areaChart = "Flaechendiagramm"
    strings.candlestickChart = "Kerzendiagramm"
    strings.lastPrice = "Letzter Kurs %@"
    strings.showingRange = "Von %1$@ bis %2$@"
    strings.atLatestBar = "Bei der neuesten Kerze"
    strings.scrolledIntoThePast = "In der Vergangenheit"
    strings.atStartOfHistory = "Am Anfang des Verlaufs"
    strings.showEarlierBars = "Frueher"
    strings.showLaterBars = "Spaeter"
    strings.showLatestBar = "Neueste"
    strings.scrollToLatest = "Zur neuesten Kerze"
    strings.loadingHistory = "Verlauf wird geladen"
    strings.time = "Zeit"
    strings.open = "Eroeffnung"
    strings.high = "Hoch"
    strings.low = "Tief"
    strings.close = "Schluss"
    strings.price = "Kurs"
    strings.change = "Aenderung"
    strings.changePercent = "Aenderung %"
    strings.range = "Spanne"
    strings.volume = "Umsatz"
    strings.lineStyle = "Linie"
    strings.areaStyle = "Flaeche"
    strings.candlesStyle = "Kerzen"
    strings.chartStyle = "Diagrammstil"
    return strings
}

@Suite("Strings of the chart")
struct StringsTests {
    @Test("the English strings are the words the chart always said")
    func defaults() {
        let strings = english
        #expect(strings.lineChart == "Line chart")
        #expect(strings.scrollToLatest == "Scroll to latest")
        #expect(strings.loadingHistory == "Loading history")
        #expect([strings.time, strings.open, strings.high, strings.low, strings.close, strings.price, strings.change,
                 strings.changePercent, strings.range, strings.volume]
            == ["Time", "Open", "High", "Low", "Close", "Price", "Change", "Change %", "Range", "Volume"])
        #expect([strings.lineStyle, strings.areaStyle, strings.candlesStyle, strings.chartStyle]
            == ["Line", "Area", "Candles", "Chart style"])
        #expect(german() != strings)
    }

    @Test("without anything set the strings are those of the language of the app")
    func standardIsTheLanguageOfTheApp() {
        #expect(TradingChartStrings() == .standard)
        #expect(TradingChartStrings.standard == TradingChartStrings(language: StringCatalog.standardLanguage()))
    }

    #if DEBUG
    @Test("the standard strings are worked out once: neither reading them nor the environment default builds a set again")
    func standardIsCached() {
        _ = TradingChartStrings.standard  // the first read may build it
        let environment = EnvironmentValues()
        _ = environment.tradingChartStrings
        let before = StringCatalog.buildsOnThisThread

        for _ in 0..<100 {
            _ = TradingChartStrings.standard
            _ = TradingChartStrings()
            _ = environment.tradingChartStrings
            _ = EnvironmentValues().tradingChartStrings
        }
        #expect(StringCatalog.buildsOnThisThread == before)
        #expect(environment.tradingChartStrings == .standard)
    }
    #endif

    @Test("the legend formatter holds no strings unless it is given some: the legend rows, built per crosshair step, copy none")
    func legendFormatterHoldsNoStrings() {
        let value = CrosshairIndicatorValue(indicatorID: "sma", name: "SMA 20", value: 1, paletteIndex: 0)
        let formatter = LegendFormatter(theme: TradingChartTheme(), priceFormatter: plainFormatter)

        #expect(formatter.strings == nil)
        _ = formatter.header([formatter.indicatorRow(name: "SMA 20", values: [value], context: .legend)])
        #expect(formatter.strings == nil)
        #expect(LegendFormatter(theme: TradingChartTheme(), priceFormatter: plainFormatter, strings: german()).strings == german())
    }

    @Test("a format keeps the order its language needs")
    func formatting() {
        let strings = german()
        #expect(strings.format("Kurs %@", "1,5") == "Kurs 1,5")
        #expect(strings.format("%2$@ <- %1$@", "a", "b") == "b <- a")
    }

    @Test("the tooltip rows say what the strings say")
    func tooltipRows() {
        let candle = Candle(time: date(baseTime), open: 102.0, high: 110.0, low: 95.0, close: 105.0, volume: 1_500.0)
        let state = CrosshairState(time: date(baseTime), candle: candle, value: 105, previousClose: 100)
        let formatter = LegendFormatter(theme: TradingChartTheme(), priceFormatter: plainFormatter, strings: german())

        let rows = formatter.tooltipRows(for: state, drawnStyle: .candles, time: "t")
        #expect(rows.map(\.label) == [
            "Zeit", "Eroeffnung", "Hoch", "Tief", "Schluss", "Aenderung", "Aenderung %", "Spanne", "Umsatz",
        ])
        let line = formatter.tooltipRows(for: state, drawnStyle: .line, time: "t")
        #expect(line.map(\.label).prefix(2) == ["Zeit", "Kurs"])
        // Without strings of its own the formatter speaks the standard language: that of the app.
        let standard = LegendFormatter(theme: TradingChartTheme(), priceFormatter: plainFormatter)
        #expect(standard.tooltipRows(for: state, drawnStyle: .candles, time: "t").first?.label == TradingChartStrings.standard.time)
    }

    @Test("what VoiceOver hears is in the strings: the label, the value, the announcements")
    func accessibilityText() {
        let strings = german()
        let window = date(1_000_000)...date(1_002_400)
        let format = { (date: Date) in "t\(Int(date.timeIntervalSince1970 - 1_000_000))" }

        #expect(ChartAccessibilityText.label(for: .line, strings: strings) == "Liniendiagramm")
        #expect(ChartAccessibilityText.label(for: .area, strings: strings) == "Flaechendiagramm")
        #expect(ChartAccessibilityText.label(for: .candles, strings: strings) == "Kerzendiagramm")
        #expect(
            ChartAccessibilityText.value(lastPrice: "1,5", window: window, atLiveEdge: true, format: format, strings: strings)
                == "Letzter Kurs 1,5. Von t0 bis t2400. Bei der neuesten Kerze."
        )
        #expect(
            ChartAccessibilityText.value(lastPrice: nil, window: window, atLiveEdge: false, format: format, strings: strings)
                == "Von t0 bis t2400. In der Vergangenheit."
        )
        #expect(
            ChartAccessibilityText.announcement(after: .earlier, moved: false, window: window, format: format, strings: strings)
                == "Am Anfang des Verlaufs"
        )
        #expect(
            ChartAccessibilityText.announcement(after: .later, moved: false, window: window, format: format, strings: strings)
                == "Bei der neuesten Kerze"
        )
        #expect(
            ChartAccessibilityText.announcement(after: .latest, moved: true, window: window, format: format, strings: strings)
                == "Von t0 bis t2400"
        )
    }
}

@MainActor
@Suite("Strings in the environment", .serialized)
struct StringsEnvironmentTests {
    @MainActor
    private final class Sink {
        var strings: TradingChartStrings?
    }

    private struct Probe: View {
        let sink: Sink
        @Environment(\.tradingChartStrings) private var strings

        var body: some View {
            let _ = sink.strings = strings
            Color.clear
        }
    }

    private func read<Content: View>(_ content: (Probe) -> Content, sink: Sink) {
        let controller = UIHostingController(rootView: content(Probe(sink: sink)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.isHidden = true
    }

    @Test("a view hierarchy has the strings of the device until the modifier says otherwise")
    func modifierSetsTheStrings() {
        let plain = Sink()
        read({ $0 }, sink: plain)
        #expect(plain.strings == .standard)

        let custom = Sink()
        read({ $0.tradingChartStrings(german()) }, sink: custom)
        #expect(custom.strings == german())
        #expect(custom.strings?.scrollToLatest == "Zur neuesten Kerze")
    }
}

@MainActor
@Suite("Pinch")
struct PinchTests {
    private func makeModel() -> TradingChartModel {
        let model = TradingChartModel(series: makeSeries(count: 600, lastStart: baseTime + 599 * 60), style: .candles)
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        return model
    }

    @Test("the magnification is the total since the first change: repeated changes do not add up")
    func totalMagnification() {
        let model = makeModel()
        let start = model.visibleBars
        let pinch = PinchTracker()

        pinch.magnified(by: 1.5, in: model)
        #expect(abs(model.visibleBars - start / 1.5) < 1e-9)
        pinch.magnified(by: 1.5, in: model)
        pinch.magnified(by: 1.5, in: model)
        #expect(abs(model.visibleBars - start / 1.5) < 1e-9)
        pinch.magnified(by: 2, in: model)
        #expect(abs(model.visibleBars - start / 2) < 1e-9)
        #expect(pinch.isActive)
    }

    @Test("a pinch that was cancelled lets go of its window: the next one starts from the window as it is then")
    func cancelledPinchLetsGo() {
        let model = makeModel()
        let start = model.visibleBars
        let pinch = PinchTracker()
        pinch.magnified(by: 1.5, in: model)
        let zoomed = model.visibleBars

        // The pinch is cancelled (SwiftUI does not call onEnded for that; the view calls end() when its gesture state resets).
        pinch.end()
        #expect(!pinch.isActive)

        pinch.magnified(by: 1.5, in: model)
        #expect(abs(model.visibleBars - zoomed / 1.5) < 1e-9)  // from the zoomed window, not from the one before the first pinch
        #expect(abs(model.visibleBars - start / 1.5) > 1)
    }

    @Test("without letting go, the old window is what a new pinch would zoom: this is what a missed cancel looked like")
    func staleBaselineWithoutEnd() {
        let model = makeModel()
        let start = model.visibleBars
        let pinch = PinchTracker()
        pinch.magnified(by: 1.5, in: model)
        pinch.magnified(by: 1.5, in: model)
        #expect(abs(model.visibleBars - start / 1.5) < 1e-9)  // still the first pinch's window as the baseline
    }

    @Test("a pinch at the live edge keeps the newest bar in place; away from it, the middle of the window")
    func anchors() {
        let model = makeModel()
        let pinch = PinchTracker()
        let last = model.series.lastTime!
        pinch.magnified(by: 2, in: model)
        #expect(model.isAtLiveEdge)
        #expect(model.visibleTimeRange.upperBound > last)

        pinch.end()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-3_600)
        #expect(!model.isAtLiveEdge)
        let middle = model.visibleTimeRange.lowerBound.addingTimeInterval(model.visibleDuration / 2)
        pinch.magnified(by: 2, in: model)
        let after = model.visibleTimeRange.lowerBound.addingTimeInterval(model.visibleDuration / 2)
        #expect(abs(after.timeIntervalSince(middle)) < 1e-6)
    }
}
