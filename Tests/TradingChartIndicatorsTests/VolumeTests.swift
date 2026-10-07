import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

@Suite("Volume")
struct VolumeTests {
    private let series = ChartSeries(
        candles: [
            candle(0, o: 10, h: 12, l: 9, c: 11, v: 100),    // up
            candle(60, o: 11, h: 12, l: 8, c: 9, v: 250),    // down
            candle(120, o: 9, h: 10, l: 9, c: 9, v: 50),     // doji: close == open
            candle(180, o: 9, h: 14, l: 9, c: 13, v: 400),   // up
            candle(240, o: 13, h: 13, l: 7, c: 8, v: 150),   // down
        ],
        interval: .minutes(1)
    )

    @Test("Defaults: pane placement, id and name")
    func defaults() {
        let volume = Volume()
        #expect(volume.movingAveragePeriod == nil)
        #expect(volume.id == "volume")
        #expect(volume.displayName == "Volume")
        #expect(volume.placement == .pane)
        #expect(Volume(movingAveragePeriod: 20).id == "volume(20)")
    }

    @Test("One histogram, no lines, baseline 0, autoscaled")
    func shape() {
        let output = Volume().calculate(IndicatorInput(series: series))
        #expect(output.lines.isEmpty && output.bands.isEmpty && output.levels.isEmpty)
        #expect(output.fixedRange == nil)
        #expect(output.histograms.count == 1)
        let histogram = output.histograms[0]
        #expect(histogram.id == "volume.volume")
        #expect(histogram.name == "Volume")
        #expect(histogram.baseline == 0)
        #expect(histogram.bars.map(\.value) == [100, 250, 50, 400, 150])
        #expect(histogram.bars.map(\.time) == barTimes(5))
        #expect(histogram.bars.allSatisfy { $0.color == nil })
    }

    @Test("Tone follows the candle direction; a doji counts as up")
    func tones() {
        let bars = Volume().calculate(IndicatorInput(series: series)).histograms[0].bars
        #expect(bars.map(\.tone) == [.positive, .negative, .positive, .positive, .negative])
    }

    @Test("No volume at all gives the empty output")
    func withoutVolume() {
        let noVolume = ChartSeries(
            candles: [candle(0, o: 1, h: 2, l: 1, c: 2), candle(60, o: 2, h: 3, l: 2, c: 3)],
            interval: .minutes(1)
        )
        #expect(Volume().calculate(IndicatorInput(series: noVolume)) == .empty)
        #expect(Volume(movingAveragePeriod: 2).calculate(IndicatorInput(series: noVolume)) == .empty)
        #expect(Volume().calculate(IndicatorInput(series: pointSeries(values: [1, 2, 3]))) == .empty)
        #expect(Volume().calculate(IndicatorInput(series: .empty(interval: .minutes(1)))) == .empty)
    }

    @Test("The moving average line is the SMA of the volumes, from bar period - 1")
    func movingAverage() {
        let output = Volume(movingAveragePeriod: 3).calculate(IndicatorInput(series: series))
        #expect(output.histograms.count == 1)
        #expect(output.lines.count == 1)
        let line = output.lines[0]
        #expect(line.id == "volume(3).ma")
        #expect(line.name == "Volume MA 3")
        // (100 + 250 + 50) / 3, (250 + 50 + 400) / 3, (50 + 400 + 150) / 3
        expectValues(line.values, match: [nil, nil, 400.0 / 3, 700.0 / 3, 200])
    }

    @Test("A series shorter than the average period keeps the bars and gives an empty line")
    func shortSeries() {
        let output = Volume(movingAveragePeriod: 20).calculate(IndicatorInput(series: series))
        #expect(output.histograms[0].bars.count == 5)
        #expect(output.lines.count == 1)
        #expect(output.lines[0].values.isEmpty)
        #expect(!output.isEmpty)
    }

    @Test("Bars without a volume are skipped and count as zero in the average")
    func partialVolume() {
        let mixed = ChartSeries(
            candles: [
                candle(0, o: 1, h: 2, l: 1, c: 2, v: 30),
                candle(60, o: 2, h: 3, l: 2, c: 3),
                candle(120, o: 3, h: 4, l: 3, c: 4, v: 60),
            ],
            interval: .minutes(1)
        )
        let output = Volume(movingAveragePeriod: 3).calculate(IndicatorInput(series: mixed))
        #expect(output.histograms[0].bars.map(\.time) == [date(0), date(120)])
        #expect(output.lines[0].values.map(\.value) == [30])
    }

    @Test("The average line keeps the given style")
    func style() {
        let style = IndicatorLineStyle(color: ChartColor(red: 1, green: 1, blue: 0), width: 2)
        let output = Volume(movingAveragePeriod: 2, movingAverageStyle: style).calculate(IndicatorInput(series: series))
        #expect(output.lines[0].style == style)
        #expect(Volume(movingAveragePeriod: 2).calculate(IndicatorInput(series: series)).lines[0].style.color == nil)
    }

    @Test("The histogram feeds autoscaling with its baseline included")
    func autoscale() {
        let output = Volume().calculate(IndicatorInput(series: series))
        let times = barTimes(5)
        #expect(output.valueRange(in: times[1]...times[3]) == 0...400)
    }
}
