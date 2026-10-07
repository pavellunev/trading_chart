import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

@Suite("RSI")
struct RSITests {
    @Test("Defaults: 14 / 70 / 30, pane placement, id and name")
    func defaults() {
        let rsi = RSI()
        #expect(rsi.period == 14)
        #expect(rsi.overbought == 70)
        #expect(rsi.oversold == 30)
        #expect(rsi.id == "rsi(14,70,30)")
        #expect(rsi.displayName == "RSI 14")
        #expect(rsi.placement == .pane)
    }

    @Test("Id follows the parameters")
    func identity() {
        #expect(RSI(period: 7, overbought: 80, oversold: 20).id == "rsi(7,80,20)")
        #expect(RSI(period: 7, overbought: 72.5, oversold: 27.5).id == "rsi(7,72.5,27.5)")
        #expect(RSI(period: 7).displayName == "RSI 7")
    }

    @Test("One line with the reference values, a fixed 0...100 range and two levels")
    func output() {
        let output = RSI().calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.fixedRange == 0...100)
        #expect(output.bands.isEmpty && output.histograms.isEmpty)
        #expect(output.lines.count == 1)
        let line = output.lines[0]
        #expect(line.id == "rsi(14,70,30)")
        #expect(line.name == "RSI 14")
        expectValues(line.values, match: reference_rsi14)
        // Warm-up: the first `period` bars have no value.
        #expect(line.values.count == referenceCloses.count - 14)
        #expect(line.values.first?.time == barTimes(referenceCloses.count)[14])

        #expect(output.levels.map(\.value) == [70, 30])
        #expect(output.levels.map(\.id) == ["rsi(14,70,30).overbought", "rsi(14,70,30).oversold"])
    }

    @Test("Custom levels and period are reflected in the output")
    func customParameters() {
        let output = RSI(period: 5, overbought: 80, oversold: 20).calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.levels.map(\.value) == [80, 20])
        expectValues(output.lines[0].values, match: reference_rsi5)
    }

    @Test("Conventions: avgLoss == 0 gives 100, no movement gives 50")
    func flatMarketConventions() {
        let rising = RSI().calculate(IndicatorInput(series: candleSeries(closes: (1...30).map(Double.init))))
        #expect(rising.lines[0].values.count == 16)
        #expect(rising.lines[0].values.allSatisfy { $0.value == 100 })

        let flat = RSI().calculate(IndicatorInput(series: candleSeries(closes: Array(repeating: 9, count: 30))))
        #expect(flat.lines[0].values.count == 16)
        #expect(flat.lines[0].values.allSatisfy { $0.value == 50 })

        let falling = RSI().calculate(IndicatorInput(series: candleSeries(closes: (1...30).reversed().map(Double.init))))
        #expect(falling.lines[0].values.allSatisfy { $0.value == 0 })
    }

    @Test("A series with at most `period` bars gives an empty line, not a crash")
    func shortSeries() {
        for count in [0, 1, 13, 14] {
            let output = RSI().calculate(
                IndicatorInput(series: candleSeries(closes: (0..<count).map { Double($0 % 3) + 1 }))
            )
            #expect(output.lines.count == 1, "count \(count)")
            #expect(output.lines[0].values.isEmpty, "count \(count)")
            #expect(output.isEmpty, "count \(count)")
            #expect(output.fixedRange == 0...100, "count \(count)")
            #expect(output.levels.count == 2, "count \(count)")
        }
        let single = RSI().calculate(IndicatorInput(series: candleSeries(closes: (0..<15).map { Double($0 % 3) + 1 })))
        #expect(single.lines[0].values.count == 1)
    }

    @Test("The line keeps the given style")
    func style() {
        let style = IndicatorLineStyle(color: ChartColor(red: 0.5, green: 0, blue: 0.5), width: 2)
        let output = RSI(style: style).calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines[0].style == style)
        #expect(RSI().calculate(IndicatorInput(series: referenceSeries())).lines[0].style.color == nil)
    }

    @Test("Point series work like flat candles")
    func fromPointSeries() {
        let values = (0..<30).map { 50 + 10 * sin(Double($0) / 3) }
        let output = RSI(period: 5).calculate(IndicatorInput(series: pointSeries(values: values)))
        expectValues(output.lines[0].values, match: IndicatorMath.rsi(values, period: 5))
    }
}
