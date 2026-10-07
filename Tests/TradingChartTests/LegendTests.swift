import Foundation
import SwiftUI
import Testing
@testable import TradingChart

private let plainFormatter = PriceFormatter { value, context in
    (context == .compact ? "c" : "p") + String(format: "%.2f", value)
}

private func text(_ row: AttributedString) -> String {
    String(row.characters)
}

/// The colour of the first run that contains `fragment`.
private func color(of fragment: String, in row: AttributedString) -> Color? {
    for run in row.runs where String(row[run.range].characters).contains(fragment) {
        return run.foregroundColor
    }
    return nil
}

@Suite("Legend naming")
struct LegendNamingTests {
    @Test("numeric parameters go into parentheses")
    func parameters() {
        #expect(LegendNaming.title(for: "SMA 20") == "SMA(20)")
        #expect(LegendNaming.title(for: "BB 20 2") == "BB(20,2)")
        #expect(LegendNaming.title(for: "MACD 12 26 9") == "MACD(12,26,9)")
        #expect(LegendNaming.title(for: "RSI 14") == "RSI(14)")
        #expect(LegendNaming.title(for: "SMA 20 hl2") == "SMA(20,hl2)")
        #expect(LegendNaming.title(for: "BB 20 1.5") == "BB(20,1.5)")
    }

    @Test("a name without parameters is shortened or upper-cased")
    func withoutParameters() {
        #expect(LegendNaming.title(for: "Volume") == "VOL")
        #expect(LegendNaming.title(for: "Upper") == "UP")
        #expect(LegendNaming.title(for: "Middle") == "MB")
        #expect(LegendNaming.title(for: "Lower") == "DN")
        #expect(LegendNaming.title(for: "Histogram") == "HIST")
        #expect(LegendNaming.title(for: "Signal") == "SIGNAL")
        #expect(LegendNaming.title(for: "MACD") == "MACD")
    }

    @Test("a name with a tail that is not a parameter is kept")
    func unknownTail() {
        #expect(LegendNaming.title(for: "My Indicator") == "My Indicator")
        #expect(LegendNaming.title(for: "") == "")
    }

    @Test("parameters are recognised only after a word")
    func hasParameters() {
        #expect(LegendNaming.hasParameters("SMA 20"))
        #expect(LegendNaming.hasParameters("BB 20 2"))
        #expect(!LegendNaming.hasParameters("Volume"))
        #expect(!LegendNaming.hasParameters("My Indicator"))
    }

    @Test("an element label drops the name of its indicator")
    func elementLabels() {
        #expect(LegendNaming.elementLabel(valueName: "BB Upper", indicatorName: "BB 20 2") == "UP")
        #expect(LegendNaming.elementLabel(valueName: "BB Middle", indicatorName: "BB 20 2") == "MB")
        #expect(LegendNaming.elementLabel(valueName: "BB Lower", indicatorName: "BB 20 2") == "DN")
        #expect(LegendNaming.elementLabel(valueName: "Volume MA 20", indicatorName: "Volume") == "MA(20)")
        #expect(LegendNaming.elementLabel(valueName: "Volume", indicatorName: "Volume") == "VOL")
        #expect(LegendNaming.elementLabel(valueName: "MACD", indicatorName: "MACD 12 26 9") == "MACD")
        #expect(LegendNaming.elementLabel(valueName: "Signal", indicatorName: "MACD 12 26 9") == "SIGNAL")
        #expect(LegendNaming.elementLabel(valueName: "Histogram", indicatorName: "MACD 12 26 9") == "HIST")
    }
}

@Suite("Legend rows")
struct LegendRowTests {
    private let theme = TradingChartTheme()
    private var formatter: LegendFormatter { LegendFormatter(theme: theme, priceFormatter: plainFormatter) }

    private func line(_ name: String, _ value: Double, slot: Int, id: String = "i") -> CrosshairIndicatorValue {
        CrosshairIndicatorValue(indicatorID: id, name: name, value: value, paletteIndex: slot)
    }

    @Test("a single line shows its title and value in the colour of the line")
    func singleLine() {
        let row = formatter.indicatorRow(name: "SMA 20", values: [line("SMA 20", 120_641.21, slot: 0)], context: .legend)

        #expect(text(row) == "SMA(20): p120641.21")
        #expect(color(of: "SMA(20):", in: row) == theme.paletteColor(at: 0))
        #expect(color(of: "p120641.21", in: row) == theme.paletteColor(at: 0))
    }

    @Test("an indicator with several lines gets a title and a labelled value for each line")
    func bollinger() {
        let values = [
            line("BB Middle", 2, slot: 0),
            line("BB Upper", 3, slot: 0),
            line("BB Lower", 1, slot: 0),
        ]
        let row = formatter.indicatorRow(name: "BB 20 2", values: values, context: .legend)

        #expect(text(row) == "BB(20,2) MB: p2.00 UP: p3.00 DN: p1.00")
        #expect(color(of: "BB(20,2)", in: row) == theme.legendLabel)
        #expect(color(of: "UP:", in: row) == theme.paletteColor(at: 0))
    }

    @Test("a volume has no title; its bar wears the tone, its name the label colour, its average the line colour")
    func volume() {
        // The crosshair lists lines before histograms; the volume bars still lead the legend row.
        let values = [
            line("Volume MA 20", 38.2, slot: 1, id: "v"),
            CrosshairIndicatorValue(indicatorID: "v", name: "Volume", value: 45.5, tone: .positive),
        ]
        let row = formatter.indicatorRow(name: "Volume", values: values, context: .compact)

        #expect(text(row) == "VOL: c45.50 MA(20): c38.20")
        #expect(color(of: "VOL:", in: row) == theme.legendLabel)
        #expect(color(of: "c45.50", in: row) == theme.bullish)
        #expect(color(of: "MA(20):", in: row) == theme.paletteColor(at: 1))
    }

    @Test("MACD shows its lines and its histogram")
    func macd() {
        let values = [
            line("MACD", 432.95, slot: 2, id: "m"),
            line("Signal", 439.43, slot: 3, id: "m"),
            CrosshairIndicatorValue(indicatorID: "m", name: "Histogram", value: -6.48, tone: .negative),
        ]
        let row = formatter.indicatorRow(name: "MACD 12 26 9", values: values, context: .compact)

        #expect(text(row) == "MACD(12,26,9) MACD: c432.95 SIGNAL: c439.43 HIST: c-6.48")
        #expect(color(of: "c-6.48", in: row) == theme.bearish)
        #expect(color(of: "SIGNAL:", in: row) == theme.paletteColor(at: 3))
    }

    @Test("the context decides how values are formatted")
    func context() {
        let values = [line("RSI 14", 63.515, slot: 0)]
        #expect(text(formatter.indicatorRow(name: "RSI 14", values: values, context: .compact)) == "RSI(14): c63.52")
        #expect(text(formatter.indicatorRow(name: "RSI 14", values: values, context: .legend)) == "RSI(14): p63.52")
    }

    @Test("an indicator that has no value yet shows its title")
    func warmUp() {
        let row = formatter.indicatorRow(name: "SMA 20", values: [], context: .legend)
        #expect(text(row) == "SMA(20)")
        #expect(color(of: "SMA(20)", in: row) == theme.legendLabel)
    }

    @Test("the header joins the rows with three spaces and skips empty ones")
    func header() {
        let first = formatter.indicatorRow(name: "SMA 20", values: [line("SMA 20", 1, slot: 0)], context: .legend)
        let second = formatter.indicatorRow(name: "RSI 14", values: [line("RSI 14", 2, slot: 1)], context: .legend)

        #expect(text(formatter.header([first, AttributedString(), second])) == "SMA(20): p1.00   RSI(14): p2.00")
        #expect(text(formatter.header([])) == "")
    }
}

@Suite("Crosshair tooltip")
struct TooltipTests {
    private var formatter: LegendFormatter {
        LegendFormatter(theme: TradingChartTheme(), priceFormatter: plainFormatter, strings: english)
    }

    private func state(volume: Double? = 1_500, previousClose: Double? = 100) -> CrosshairState {
        let candle = Candle(time: date(baseTime), open: 102, high: 110, low: 95, close: 105, volume: volume)
        return CrosshairState(time: date(baseTime), candle: candle, value: 105, previousClose: previousClose)
    }

    @Test("a candle shows time, prices, change, range and volume in that order")
    func candleRows() {
        let rows = formatter.tooltipRows(for: state(), drawnStyle: .candles, time: "14 Nov 22:14")

        #expect(rows.map(\.label) == ["Time", "Open", "High", "Low", "Close", "Change", "Change %", "Range", "Volume"])
        #expect(rows[0].value == "14 Nov 22:14")
        #expect(rows[1].value == "p102.00")
        #expect(rows[4].value == "p105.00")
        // The change is measured against the open of the bar (102), not against the previous close (100).
        #expect(rows[5].value == "+p3.00")
        #expect(rows[5].tint == TooltipRow.Tint.rising)
        #expect(rows[6].value.hasPrefix("+") && rows[6].value.hasSuffix("%"))
        #expect(rows[7].value == "p15.00")
        #expect(rows[8].value == "c1500.00")
    }

    @Test("the change can be measured against the previous close instead")
    func changeAgainstPreviousClose() {
        var formatter = formatter
        formatter.changeReference = .previousClose
        let rows = formatter.tooltipRows(for: state(), drawnStyle: .candles, time: "t")

        #expect(rows.first { $0.label == "Change" }?.value == "+p5.00")
    }

    @Test("a falling bar is tinted as falling and the volume is left out when there is none")
    func fallingBar() {
        let candle = Candle(time: date(baseTime), open: Double(100), high: Double(101), low: Double(80), close: Double(90))
        let falling = CrosshairState(time: date(baseTime), candle: candle, value: 90, previousClose: 98)
        let rows = formatter.tooltipRows(for: falling, drawnStyle: .candles, time: "t")

        #expect(!rows.contains { $0.label == "Volume" })
        let change = rows.first { $0.label == "Change" }
        #expect(change?.value == "p-10.00")
        #expect(change?.tint == TooltipRow.Tint.falling)
        let percent = rows.first { $0.label == "Change %" }
        #expect(percent?.tint == TooltipRow.Tint.falling)
    }

    @Test("a line series shows the price instead of the OHLC rows and has no range")
    func lineRows() {
        let point = CrosshairState(time: date(baseTime), value: 50, previousClose: 40)
        let rows = formatter.tooltipRows(for: point, drawnStyle: .line, time: "t")

        #expect(rows.map(\.label) == ["Time", "Price", "Change", "Change %"])
        #expect(rows[1].value == "p50.00")
    }

    @Test("candles drawn as a line (no OHLC) do not show OHLC rows either")
    func candlesDrawnAsLine() {
        let rows = formatter.tooltipRows(for: state(), drawnStyle: .line, time: "t")
        #expect(!rows.contains { $0.label == "Open" || $0.label == "Range" })
        #expect(rows.contains { $0.label == "Price" })
    }

    @Test("no reference bar, no change rows")
    func noReference() {
        let lone = CrosshairState(time: date(baseTime), value: 50)
        let rows = formatter.tooltipRows(for: lone, drawnStyle: .line, time: "t")
        #expect(rows.map(\.label) == ["Time", "Price"])
    }

    @Test("the change in price units follows the same reference as the percentage")
    func changeAmount() throws {
        // open 102, close 105, previous close 100
        #expect(abs(try #require(LegendFormatter.change(of: state())) - 3) < 1e-9)
        #expect(abs(try #require(LegendFormatter.change(of: state(), against: .previousClose)) - 5) < 1e-9)
        let first = CrosshairState(
            time: date(baseTime),
            candle: Candle(time: date(baseTime), open: Double(200), high: Double(205), low: Double(185), close: Double(190)),
            value: 190
        )
        #expect(abs(try #require(LegendFormatter.change(of: first)) + 10) < 1e-9)
        #expect(LegendFormatter.change(of: CrosshairState(time: date(baseTime), value: 1)) == nil)
    }

    @Test("the tooltip goes to the side away from the crosshair")
    func side() {
        #expect(TooltipPlacement.side(crosshairX: 20, plotWidth: 300, current: .leading) == .trailing)
        #expect(TooltipPlacement.side(crosshairX: 280, plotWidth: 300, current: .trailing) == .leading)
    }

    @Test("around the middle of the plot the tooltip stays where it is")
    func sideDeadBand() {
        #expect(TooltipPlacement.side(crosshairX: 150, plotWidth: 300, current: .leading) == .leading)
        #expect(TooltipPlacement.side(crosshairX: 150, plotWidth: 300, current: .trailing) == .trailing)
        #expect(TooltipPlacement.side(crosshairX: 136, plotWidth: 300, current: .leading) == .leading)
        #expect(TooltipPlacement.side(crosshairX: 164, plotWidth: 300, current: .trailing) == .trailing)
    }

    @Test("without a position the tooltip stays where it is")
    func sideWithoutPosition() {
        #expect(TooltipPlacement.side(crosshairX: nil, plotWidth: 300, current: .leading) == .leading)
        #expect(TooltipPlacement.side(crosshairX: 10, plotWidth: 0, current: .leading) == .leading)
    }
}
