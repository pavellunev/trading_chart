import Foundation
import Testing
import TradingChartCore

private func value(_ seconds: TimeInterval, _ value: Double) -> IndicatorValue {
    IndicatorValue(time: date(seconds), value: value)
}

@Suite("IndicatorInput")
struct IndicatorInputTests {
    private let ohlc = ChartSeries(
        candles: [
            candle(0, o: 10, h: 14, l: 8, c: 12, v: 100),
            candle(60, o: 12, h: 20, l: 10, c: 16, v: 200),
        ],
        interval: .minutes(1)
    )

    @Test("Candle series keep their candles and interval")
    func fromCandles() {
        let input = IndicatorInput(series: ohlc)
        #expect(input.candles == ohlc.candles)
        #expect(input.interval == .minutes(1))
    }

    @Test("Point series are expanded to flat candles without volume")
    func fromPoints() {
        let input = IndicatorInput(series: ChartSeries(points: [point(0, 5), point(300, 7)], interval: .minutes(5)))
        #expect(input.candles == [flatCandle(0, 5), flatCandle(300, 7)])
        #expect(input.candles.allSatisfy { $0.volume == nil })
        #expect(input.interval == .minutes(5))
    }

    @Test("values(_:) picks the requested price of each bar")
    func priceSources() {
        let input = IndicatorInput(series: ohlc)
        #expect(input.values(.open) == [10, 12])
        #expect(input.values(.high) == [14, 20])
        #expect(input.values(.low) == [8, 10])
        #expect(input.values(.close) == [12, 16])
        // (14 + 8) / 2 = 11, (20 + 10) / 2 = 15
        #expect(input.values(.hl2) == [11, 15])
        // (14 + 8 + 12) / 3 = 34/3, (20 + 10 + 16) / 3 = 46/3
        let hlc3 = input.values(.hlc3)
        #expect(approximatelyEqual(hlc3[0], 34.0 / 3.0))
        #expect(approximatelyEqual(hlc3[1], 46.0 / 3.0))
        // (10 + 14 + 8 + 12) / 4 = 11, (12 + 20 + 10 + 16) / 4 = 14.5
        #expect(input.values(.ohlc4) == [11, 14.5])
    }

    @Test("PriceSource lists all seven sources")
    func allSources() {
        #expect(PriceSource.allCases.count == 7)
        #expect(PriceSource.hlc3.rawValue == "hlc3")
    }
}

@Suite("IndicatorOutput")
struct IndicatorOutputTests {
    private let line = IndicatorLine(
        id: "sma",
        name: "SMA 3",
        values: [value(120, 11), value(180, 12), value(240, 9)],
        style: IndicatorLineStyle(color: ChartColor(red: 1, green: 0, blue: 0))
    )
    private let band = IndicatorBand(
        id: "bb",
        upper: [value(120, 20), value(180, 22)],
        lower: [value(120, 5), value(180, 4)]
    )
    private let histogram = IndicatorHistogram(
        id: "vol",
        name: "Volume",
        bars: [
            HistogramBar(time: date(0), value: 100, tone: .positive),
            HistogramBar(time: date(60), value: 300, tone: .negative, color: ChartColor(red: 0, green: 0, blue: 1)),
        ]
    )

    @Test("The empty output is empty")
    func emptyOutput() {
        #expect(IndicatorOutput.empty.isEmpty)
        #expect(IndicatorOutput().isEmpty)
        #expect(IndicatorOutput.empty == IndicatorOutput())
    }

    @Test("Outputs with plotted data are not empty")
    func nonEmpty() {
        #expect(!IndicatorOutput(lines: [line]).isEmpty)
        #expect(!IndicatorOutput(bands: [band]).isEmpty)
        #expect(!IndicatorOutput(histograms: [histogram]).isEmpty)
    }

    @Test("Series without values and bare levels count as empty")
    func hollowOutputIsEmpty() {
        let hollowLine = IndicatorLine(id: "rsi", name: "RSI", values: [])
        let hollowBand = IndicatorBand(id: "bb", upper: [], lower: [])
        let hollowHistogram = IndicatorHistogram(id: "h", name: "H", bars: [])
        let level = IndicatorLevel(id: "70", value: 70)
        let output = IndicatorOutput(
            lines: [hollowLine],
            bands: [hollowBand],
            histograms: [hollowHistogram],
            levels: [level],
            fixedRange: 0...100
        )
        #expect(output.isEmpty)
    }

    @Test("valueRange covers lines inside the window")
    func valueRangeLines() {
        let output = IndicatorOutput(lines: [line])
        #expect(output.valueRange(in: date(0)...date(1_000)) == 9...12)
        #expect(output.valueRange(in: date(120)...date(180)) == 11...12)
        #expect(output.valueRange(in: date(181)...date(1_000)) == 9...9)
        #expect(output.valueRange(in: date(0)...date(119)) == nil)
        #expect(output.valueRange(in: date(241)...date(1_000)) == nil)
    }

    @Test("valueRange covers both edges of bands")
    func valueRangeBands() {
        let output = IndicatorOutput(bands: [band])
        #expect(output.valueRange(in: date(0)...date(1_000)) == 4...22)
        #expect(output.valueRange(in: date(0)...date(150)) == 5...20)
    }

    @Test("valueRange unites all plotted series and includes the histogram baseline")
    func valueRangeCombined() {
        let output = IndicatorOutput(lines: [line], bands: [band], histograms: [histogram])
        // line 9...12, band 4...22, histogram bars 100...300 plus baseline 0
        #expect(output.valueRange(in: date(0)...date(1_000)) == 0...300)
        // window t = 120...180 excludes the histogram bars: line + band only
        #expect(output.valueRange(in: date(120)...date(180)) == 4...22)
    }

    @Test("valueRange ignores levels and the fixed range")
    func valueRangeIgnoresLevels() {
        let output = IndicatorOutput(
            lines: [line],
            levels: [IndicatorLevel(id: "70", value: 70)],
            fixedRange: 0...100
        )
        #expect(output.valueRange(in: date(0)...date(1_000)) == 9...12)
        #expect(IndicatorOutput.empty.valueRange(in: date(0)...date(1_000)) == nil)
    }

    @Test("values(at:) reports lines and histograms defined at exactly that time")
    func valuesAtTime() {
        let output = IndicatorOutput(lines: [line], bands: [band], histograms: [histogram])

        let atLine = output.values(at: date(180))
        #expect(atLine.count == 1)
        #expect(atLine[0].name == "SMA 3")
        #expect(atLine[0].value == 12)
        #expect(atLine[0].color == ChartColor(red: 1, green: 0, blue: 0))

        let atHistogram = output.values(at: date(60))
        #expect(atHistogram.count == 1)
        #expect(atHistogram[0].name == "Volume")
        #expect(atHistogram[0].value == 300)
        #expect(atHistogram[0].color == ChartColor(red: 0, green: 0, blue: 1))

        #expect(output.values(at: date(0)).map(\.name) == ["Volume"])
        #expect(output.values(at: date(61)).isEmpty)
        #expect(output.values(at: date(9_999)).isEmpty)
    }

    @Test("values(at:) lists lines before histograms in output order")
    func valuesOrder() {
        let second = IndicatorLine(id: "ema", name: "EMA 3", values: [value(120, 10)])
        let output = IndicatorOutput(
            lines: [line, second],
            histograms: [IndicatorHistogram(id: "h", name: "Hist", bars: [HistogramBar(time: date(120), value: 1)])]
        )
        #expect(output.values(at: date(120)).map(\.name) == ["SMA 3", "EMA 3", "Hist"])
    }
}

@Suite("Indicator model defaults")
struct IndicatorDefaultsTests {
    @Test("Style and level defaults")
    func defaults() {
        #expect(IndicatorLineStyle() == IndicatorLineStyle(color: nil, width: 1.5, dash: []))
        #expect(IndicatorBand(id: "b", upper: [], lower: []).fillOpacity == 0.12)
        #expect(IndicatorHistogram(id: "h", name: "H", bars: []).baseline == 0)
        #expect(IndicatorLevel(id: "l", value: 1).dash == [4, 3])
        #expect(IndicatorLine(id: "l", name: "L", values: []).style == IndicatorLineStyle())
    }

    @Test("Palette slots default to zero and take part in equality")
    func paletteSlotDefaults() {
        #expect(IndicatorLine(id: "l", name: "L", values: []).paletteSlot == 0)
        #expect(IndicatorBand(id: "b", upper: [], lower: []).paletteSlot == 0)
        #expect(IndicatorLine(id: "l", name: "L", values: [], paletteSlot: 2).paletteSlot == 2)
        #expect(IndicatorBand(id: "b", upper: [], lower: [], paletteSlot: 1).paletteSlot == 1)
        #expect(IndicatorLine(id: "l", name: "L", values: [], paletteSlot: 1) != IndicatorLine(id: "l", name: "L", values: []))
    }

    @Test("ChartMarker has sensible defaults")
    func markerDefaults() {
        let marker = ChartMarker(id: "trade-1", time: date(60), kind: .buy)
        #expect(marker.price == nil)
        #expect(marker.label == nil)
        #expect(marker.color == nil)
        #expect(marker.id == "trade-1")
    }

    @Test("A custom indicator can be defined against the public protocol")
    func customIndicator() {
        struct LastClose: ChartIndicator {
            var id: String { "last-close" }
            var displayName: String { "Last close" }
            var placement: IndicatorPlacement { .overlay }
            func calculate(_ input: IndicatorInput) -> IndicatorOutput {
                IndicatorOutput(lines: [
                    IndicatorLine(
                        id: id,
                        name: displayName,
                        values: input.candles.map { IndicatorValue(time: $0.time, value: $0.close) }
                    ),
                ])
            }
        }
        let indicator: any ChartIndicator = LastClose()
        let output = indicator.calculate(IndicatorInput(series: tenCandleSeries()))
        #expect(output.lines.first?.values.count == 10)
        #expect(output.valueRange(in: date(0)...date(540)) == 9...16)
        #expect(indicator.placement == .overlay)
        // The short name defaults to the display name for an indicator that does not provide one.
        #expect(indicator.shortName == "Last close")
    }
}
