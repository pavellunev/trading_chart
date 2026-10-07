import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

@Suite("BollingerBands")
struct BollingerBandsTests {
    @Test("Defaults: 20 / 2 on close, overlay, id and name")
    func defaults() {
        let bands = BollingerBands()
        #expect(bands.period == 20)
        #expect(bands.multiplier == 2)
        #expect(bands.source == .close)
        #expect(bands.color == nil)
        #expect(bands.id == "bb(20,2,close)")
        #expect(bands.displayName == "BB 20 2")
        #expect(bands.placement == .overlay)
    }

    @Test("Id and name spell out fractional multipliers and non-close sources")
    func identity() {
        let bands = BollingerBands(period: 10, multiplier: 2.5, source: .hlc3)
        #expect(bands.id == "bb(10,2.5,hlc3)")
        #expect(bands.displayName == "BB 10 2.5 hlc3")
    }

    @Test("Three lines and one band match the TA-Lib reference, aligned with bar times")
    func output() {
        let output = BollingerBands().calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines.map(\.id) == ["bb(20,2,close).middle", "bb(20,2,close).upper", "bb(20,2,close).lower"])
        #expect(output.lines.map(\.name) == ["BB Middle", "BB Upper", "BB Lower"])
        #expect(output.bands.count == 1)
        #expect(output.histograms.isEmpty && output.levels.isEmpty)
        #expect(output.fixedRange == nil)

        expectValues(output.lines[0].values, match: reference_bbMiddle20_2)
        expectValues(output.lines[1].values, match: reference_bbUpper20_2)
        expectValues(output.lines[2].values, match: reference_bbLower20_2)

        let band = output.bands[0]
        #expect(band.id == "bb(20,2,close).band")
        #expect(band.upper == output.lines[1].values)
        #expect(band.lower == output.lines[2].values)
        // Warm-up: 19 bars have no value.
        #expect(band.upper.count == referenceCloses.count - 19)
        #expect(band.upper.first?.time == barTimes(referenceCloses.count)[19])
    }

    @Test("All lines and the band share palette slot 0, so the whole indicator gets one color")
    func paletteSlots() {
        let output = BollingerBands().calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines.map(\.paletteSlot) == [0, 0, 0])
        #expect(output.bands.map(\.paletteSlot) == [0])
    }

    @Test("Edges are middle +- multiplier * population sigma")
    func formula() {
        // Window 2 4 4 4 5 5 7 9: mean 5, population sigma 2.
        let series = candleSeries(closes: [2, 4, 4, 4, 5, 5, 7, 9])
        let output = BollingerBands(period: 8, multiplier: 1.5).calculate(IndicatorInput(series: series))
        #expect(output.lines[0].values.map(\.value) == [5])
        #expect(abs(output.lines[1].values[0].value - 8) < 1e-12)
        #expect(abs(output.lines[2].values[0].value - 2) < 1e-12)
    }

    @Test("A constant series collapses the bands onto the middle line")
    func constantSeries() {
        let output = BollingerBands(period: 5).calculate(
            IndicatorInput(series: candleSeries(closes: Array(repeating: 30, count: 12)))
        )
        let middle = output.lines[0].values
        #expect(middle.count == 8)
        for (center, (upper, lower)) in zip(middle, zip(output.lines[1].values, output.lines[2].values)) {
            #expect(abs(upper.value - center.value) < 1e-9)
            #expect(abs(lower.value - center.value) < 1e-9)
        }
    }

    @Test("Period 1 has zero width")
    func periodOne() {
        let output = BollingerBands(period: 1).calculate(IndicatorInput(series: referenceSeries()))
        expectValues(output.lines[0].values, match: referenceCloses.map { $0 })
        expectValues(output.lines[1].values, match: referenceCloses.map { $0 })
        expectValues(output.lines[2].values, match: referenceCloses.map { $0 })
    }

    @Test("A series shorter than the period gives empty lines and band, not a crash")
    func shortSeries() {
        for count in [0, 1, 19] {
            let output = BollingerBands().calculate(
                IndicatorInput(series: candleSeries(closes: Array(repeating: 5, count: count)))
            )
            #expect(output.lines.count == 3, "count \(count)")
            #expect(output.lines.allSatisfy { $0.values.isEmpty }, "count \(count)")
            #expect(output.bands.count == 1 && output.bands[0].upper.isEmpty && output.bands[0].lower.isEmpty)
            #expect(output.isEmpty, "count \(count)")
        }
    }

    @Test("Source picks the price")
    func source() {
        let series = candleSeries(closes: [10, 12, 11, 15, 14, 9, 13])
        let hl2 = (series.candles ?? []).map { ($0.high + $0.low) / 2 }
        let output = BollingerBands(period: 3, source: .hl2).calculate(IndicatorInput(series: series))
        expectValues(output.lines[0].values, match: IndicatorMath.sma(hl2, period: 3))
    }

    @Test("The color is shared by the lines and the band fill")
    func color() {
        let color = ChartColor(red: 0.2, green: 0.4, blue: 0.9)
        let output = BollingerBands(color: color).calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines.allSatisfy { $0.style.color == color })
        #expect(output.bands[0].fill == color)

        let themed = BollingerBands().calculate(IndicatorInput(series: referenceSeries()))
        #expect(themed.lines.allSatisfy { $0.style.color == nil })
        #expect(themed.bands[0].fill == nil)
    }

    @Test("Output feeds autoscaling: the range covers the outer bands")
    func autoscale() {
        let output = BollingerBands().calculate(IndicatorInput(series: referenceSeries()))
        let times = barTimes(referenceCloses.count)
        let range = output.valueRange(in: times[19]...times[59])
        let upper = output.lines[1].values.map(\.value).max()
        let lower = output.lines[2].values.map(\.value).min()
        #expect(range?.upperBound == upper)
        #expect(range?.lowerBound == lower)
    }
}
