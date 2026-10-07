import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

@Suite("MACD")
struct MACDTests {
    /// A wave: the histogram alternates between positive and negative.
    private var wave: [Double] {
        (0..<80).map { 100 + 10 * sin(Double($0) / 5) }
    }

    @Test("Defaults: 12 / 26 / 9, pane placement, id and name")
    func defaults() {
        let macd = MACD()
        #expect(macd.fast == 12)
        #expect(macd.slow == 26)
        #expect(macd.signal == 9)
        #expect(macd.id == "macd(12,26,9)")
        #expect(macd.displayName == "MACD 12 26 9")
        #expect(macd.placement == .pane)
    }

    @Test("Id follows the parameters")
    func identity() {
        #expect(MACD(fast: 5, slow: 35, signal: 5).id == "macd(5,35,5)")
        #expect(MACD(fast: 5, slow: 35, signal: 5).displayName == "MACD 5 35 5")
    }

    @Test("Two lines and one histogram match the reference, aligned with bar times")
    func output() {
        let output = MACD().calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.bands.isEmpty && output.levels.isEmpty)
        #expect(output.fixedRange == nil)
        #expect(output.lines.map(\.id) == ["macd(12,26,9).macd", "macd(12,26,9).signal"])
        #expect(output.lines.map(\.name) == ["MACD", "Signal"])
        expectValues(output.lines[0].values, match: reference_macd12_26_9)
        expectValues(output.lines[1].values, match: reference_macdSignal12_26_9)

        #expect(output.histograms.count == 1)
        let histogram = output.histograms[0]
        #expect(histogram.id == "macd(12,26,9).histogram")
        #expect(histogram.name == "Histogram")
        #expect(histogram.baseline == 0)
        let times = barTimes(referenceCloses.count)
        let expected = zip(times, reference_macdHistogram12_26_9).compactMap { time, value in value.map { (time, $0) } }
        #expect(histogram.bars.count == expected.count)
        for (bar, pair) in zip(histogram.bars, expected) {
            #expect(bar.time == pair.0)
            #expect(abs(bar.value - pair.1) <= 1e-9)
        }
    }

    @Test("Warm-up: MACD line from bar slow - 1, signal and histogram from bar slow + signal - 2")
    func warmUp() {
        let output = MACD().calculate(IndicatorInput(series: referenceSeries()))
        let times = barTimes(referenceCloses.count)
        #expect(output.lines[0].values.first?.time == times[25])
        #expect(output.lines[0].values.count == referenceCloses.count - 25)
        #expect(output.lines[1].values.first?.time == times[33])
        #expect(output.lines[1].values.count == referenceCloses.count - 33)
        #expect(output.histograms[0].bars.first?.time == times[33])
        #expect(output.histograms[0].bars.map(\.time) == output.lines[1].values.map(\.time))
    }

    @Test("Histogram tone follows the sign of the value")
    func tones() {
        let output = MACD(fast: 3, slow: 6, signal: 4).calculate(IndicatorInput(series: candleSeries(closes: wave)))
        let bars = output.histograms[0].bars
        #expect(!bars.isEmpty)
        for bar in bars {
            let expected: HistogramTone = bar.value > 0 ? .positive : (bar.value < 0 ? .negative : .neutral)
            #expect(bar.tone == expected, "\(bar.value)")
        }
        #expect(bars.contains { $0.tone == .positive })
        #expect(bars.contains { $0.tone == .negative })
        #expect(bars.allSatisfy { $0.color == nil })
    }

    @Test("A histogram value of exactly zero is neutral")
    func neutralTone() {
        // With all periods 1 each EMA reproduces the close, so MACD, signal and histogram are exactly zero.
        let output = MACD(fast: 1, slow: 1, signal: 1).calculate(IndicatorInput(series: candleSeries(closes: wave)))
        #expect(output.histograms[0].bars.count == wave.count)
        #expect(output.histograms[0].bars.allSatisfy { $0.value == 0 && $0.tone == .neutral })
    }

    @Test("A series too short for a line gives empty series, not a crash")
    func shortSeries() {
        // 26 bars: the MACD line has a single value, the signal needs 8 more.
        let almost = MACD().calculate(IndicatorInput(series: candleSeries(closes: Array(referenceCloses.prefix(26)))))
        #expect(almost.lines[0].values.count == 1)
        #expect(almost.lines[1].values.isEmpty)
        #expect(almost.histograms[0].bars.isEmpty)
        #expect(!almost.isEmpty)

        for count in [0, 1, 25] {
            let output = MACD().calculate(IndicatorInput(series: candleSeries(closes: Array(referenceCloses.prefix(count)))))
            #expect(output.lines.count == 2, "count \(count)")
            #expect(output.lines.allSatisfy { $0.values.isEmpty }, "count \(count)")
            #expect(output.histograms.count == 1 && output.histograms[0].bars.isEmpty, "count \(count)")
            #expect(output.isEmpty, "count \(count)")
        }
    }

    @Test("The signal line takes palette slot 1, the MACD line slot 0")
    func paletteSlots() {
        let output = MACD().calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines.map(\.paletteSlot) == [0, 1])
    }

    @Test("The line styles are kept separately")
    func styles() {
        let macdStyle = IndicatorLineStyle(color: ChartColor(red: 0, green: 0.4, blue: 1))
        let signalStyle = IndicatorLineStyle(color: ChartColor(red: 1, green: 0.4, blue: 0), dash: [3, 3])
        let output = MACD(macdStyle: macdStyle, signalStyle: signalStyle).calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines[0].style == macdStyle)
        #expect(output.lines[1].style == signalStyle)
        let plain = MACD().calculate(IndicatorInput(series: referenceSeries()))
        #expect(plain.lines.allSatisfy { $0.style.color == nil })
    }

    @Test("Output feeds the crosshair legend with lines and the histogram")
    func legend() {
        let output = MACD().calculate(IndicatorInput(series: referenceSeries()))
        let times = barTimes(referenceCloses.count)
        let legend = output.values(at: times[40])
        #expect(legend.map(\.name) == ["MACD", "Signal", "Histogram"])
        #expect(abs(legend[0].value - (reference_macd12_26_9[40] ?? .nan)) < 1e-9)
        #expect(output.values(at: times[30]).map(\.name) == ["MACD"])
    }
}
