import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

/// One of the three single-line moving averages, with a TA-Lib reference for `period`.
struct MovingAverageSpec: Sendable, CustomTestStringConvertible {
    let title: String
    let prefix: String
    let period: Int
    let expected: [Double?]
    let math: @Sendable ([Double], Int) -> [Double?]
    let make: @Sendable (Int, PriceSource, IndicatorLineStyle) -> any ChartIndicator
    let makeDefault: @Sendable () -> any ChartIndicator

    var testDescription: String { title }

    static let all: [MovingAverageSpec] = [
        MovingAverageSpec(
            title: "SMA",
            prefix: "sma",
            period: 20,
            expected: reference_sma20,
            math: { IndicatorMath.sma($0, period: $1) },
            make: { SMA(period: $0, source: $1, style: $2) },
            makeDefault: { SMA() }
        ),
        MovingAverageSpec(
            title: "EMA",
            prefix: "ema",
            period: 12,
            expected: reference_ema12,
            math: { IndicatorMath.ema($0, period: $1) },
            make: { EMA(period: $0, source: $1, style: $2) },
            makeDefault: { EMA() }
        ),
        MovingAverageSpec(
            title: "WMA",
            prefix: "wma",
            period: 10,
            expected: reference_wma10,
            math: { IndicatorMath.wma($0, period: $1) },
            make: { WMA(period: $0, source: $1, style: $2) },
            makeDefault: { WMA() }
        ),
    ]
}

@Suite("SMA / EMA / WMA indicators")
struct MovingAverageIndicatorTests {
    @Test("Defaults: period 20 on close, overlay, id and name", arguments: MovingAverageSpec.all)
    func defaults(spec: MovingAverageSpec) {
        let indicator = spec.makeDefault()
        #expect(indicator.id == "\(spec.prefix)(20,close)")
        #expect(indicator.displayName == "\(spec.title) 20")
        #expect(indicator.placement == .overlay)
    }

    @Test("Id and name follow the parameters; a non-close source is spelled out", arguments: MovingAverageSpec.all)
    func identity(spec: MovingAverageSpec) {
        let indicator = spec.make(50, .close, IndicatorLineStyle())
        #expect(indicator.id == "\(spec.prefix)(50,close)")
        #expect(indicator.displayName == "\(spec.title) 50")
        let hl2 = spec.make(7, .hl2, IndicatorLineStyle())
        #expect(hl2.id == "\(spec.prefix)(7,hl2)")
        #expect(hl2.displayName == "\(spec.title) 7 hl2")
    }

    @Test("Output is a single line of the reference values, aligned with bar times", arguments: MovingAverageSpec.all)
    func output(spec: MovingAverageSpec) {
        let indicator = spec.make(spec.period, .close, IndicatorLineStyle())
        let output = indicator.calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines.count == 1)
        #expect(output.bands.isEmpty && output.histograms.isEmpty && output.levels.isEmpty)
        #expect(output.fixedRange == nil)
        let line = output.lines[0]
        #expect(line.id == indicator.id)
        #expect(line.name == indicator.displayName)
        expectValues(line.values, match: spec.expected)
        // Warm-up bars are not part of the output: the first value sits at bar `period - 1`.
        #expect(line.values.count == referenceCloses.count - spec.period + 1)
        #expect(line.values.first?.time == barTimes(referenceCloses.count)[spec.period - 1])
        #expect(line.values.last?.time == barTimes(referenceCloses.count).last)
    }

    @Test("Source picks the price: hl2 averages (high + low) / 2", arguments: MovingAverageSpec.all)
    func source(spec: MovingAverageSpec) {
        let series = candleSeries(closes: [10, 12, 11, 15, 14, 9, 13])
        let input = IndicatorInput(series: series)
        let output = spec.make(3, .hl2, IndicatorLineStyle()).calculate(input)
        let hl2 = (series.candles ?? []).map { ($0.high + $0.low) / 2 }
        expectValues(output.lines[0].values, match: spec.math(hl2, 3))
        let close = spec.make(3, .close, IndicatorLineStyle()).calculate(input)
        #expect(close.lines[0].values != output.lines[0].values)
    }

    @Test("A series shorter than the period gives an empty line, not a crash", arguments: MovingAverageSpec.all)
    func shortSeries(spec: MovingAverageSpec) {
        let indicator = spec.make(20, .close, IndicatorLineStyle())
        for count in [0, 1, 19] {
            let output = indicator.calculate(IndicatorInput(series: candleSeries(closes: Array(repeating: 5, count: count))))
            #expect(output.lines.count == 1, "count \(count)")
            #expect(output.lines[0].values.isEmpty, "count \(count)")
            #expect(output.isEmpty, "count \(count)")
        }
        let exact = indicator.calculate(IndicatorInput(series: candleSeries(closes: Array(repeating: 5, count: 20))))
        #expect(exact.lines[0].values.count == 1)
    }

    @Test("Period 1 reproduces the closes", arguments: MovingAverageSpec.all)
    func periodOne(spec: MovingAverageSpec) {
        let output = spec.make(1, .close, IndicatorLineStyle()).calculate(IndicatorInput(series: referenceSeries()))
        expectValues(output.lines[0].values, match: referenceCloses.map { $0 })
    }

    @Test("Point series are averaged like flat candles", arguments: MovingAverageSpec.all)
    func fromPointSeries(spec: MovingAverageSpec) {
        let values: [Double] = [1, 4, 2, 8, 5, 7]
        let output = spec.make(3, .close, IndicatorLineStyle()).calculate(
            IndicatorInput(series: pointSeries(values: values))
        )
        expectValues(output.lines[0].values, match: spec.math(values, 3))
    }

    @Test("The line keeps the given style", arguments: MovingAverageSpec.all)
    func style(spec: MovingAverageSpec) {
        let style = IndicatorLineStyle(color: ChartColor(red: 1, green: 0.5, blue: 0), width: 3, dash: [2, 2])
        let output = spec.make(5, .close, style).calculate(IndicatorInput(series: referenceSeries()))
        #expect(output.lines[0].style == style)
        let plain = spec.make(5, .close, IndicatorLineStyle()).calculate(IndicatorInput(series: referenceSeries()))
        #expect(plain.lines[0].style.color == nil)
    }

    @Test("Output feeds autoscaling and the crosshair legend")
    func integratesWithOutputHelpers() {
        let series = referenceSeries()
        let output = SMA(period: 5).calculate(IndicatorInput(series: series))
        let times = barTimes(referenceCloses.count)
        let range = output.valueRange(in: times[10]...times[12])
        #expect(range != nil)
        let legend = output.values(at: times[10])
        #expect(legend.count == 1)
        #expect(legend.first?.name == "SMA 5")
        #expect(abs((legend.first?.value ?? 0) - (reference_sma5[10] ?? -1)) < 1e-9)
        #expect(output.values(at: times[2]).isEmpty)
    }
}
