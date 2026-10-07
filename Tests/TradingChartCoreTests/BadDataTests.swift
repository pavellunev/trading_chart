import Foundation
import Testing
import TradingChartCore

private let bad: [Double] = [.nan, .infinity, -.infinity]

@Suite("Bad data at the edge of the API")
struct BadDataTests {

    // MARK: Candles

    @Test("A candle whose high is below its low is repaired: the high becomes the highest price, the low the lowest")
    func invertedCandleIsRepaired() {
        let series = ChartSeries(candles: [candle(0, o: 10, h: 8, l: 12, c: 11)], interval: .minutes(1))
        #expect(series.candles == [candle(0, o: 10, h: 12, l: 8, c: 11)])
    }

    @Test("A candle whose open or close is outside its high and low is repaired")
    func outsideCandleIsRepaired() {
        let series = ChartSeries(
            candles: [candle(0, o: 20, h: 15, l: 12, c: 5), candle(60, o: 10, h: 11, l: 9, c: 10)],
            interval: .minutes(1)
        )
        #expect(series.candles == [candle(0, o: 20, h: 20, l: 5, c: 5), candle(60, o: 10, h: 11, l: 9, c: 10)])
        #expect(series.points.map(\.value) == [5, 10])
    }

    @Test("A candle with a price that is not finite is dropped, in whichever price it is")
    func nonFiniteCandleIsDropped() {
        for value in bad {
            let candles = [
                candle(0, o: value, h: 2, l: 1, c: 1.5),
                candle(60, o: 1, h: value, l: 1, c: 1.5),
                candle(120, o: 1, h: 2, l: value, c: 1.5),
                candle(180, o: 1, h: 2, l: 1, c: value),
                candle(240, o: 1, h: 2, l: 1, c: 1.5),
            ]
            let series = ChartSeries(candles: candles, interval: .minutes(1))
            #expect(series.candles == [candle(240, o: 1, h: 2, l: 1, c: 1.5)])
            #expect(series.points == [point(240, 1.5)])
        }
    }

    @Test("A candle built from a Decimal that is not a number is dropped")
    func decimalNaNIsDropped() {
        let candle = Candle(time: date(0), open: Decimal.nan, high: 2, low: 1, close: 1.5)
        #expect(ChartSeries(candles: [candle], interval: .minutes(1)).isEmpty)
        var series = ChartSeries.empty(interval: .minutes(1))
        #expect(series.upsert(candle, maxCount: nil) == .ignored)
        #expect(series.isEmpty)
        #expect(PricePoint(time: date(0), value: Decimal.nan).value.isNaN)
        #expect(ChartSeries(points: [PricePoint(time: date(0), value: Decimal.nan)], interval: .minutes(1)).isEmpty)
    }

    @Test("A volume that is not finite is dropped from the candle, which stays")
    func nonFiniteVolume() {
        for value in bad {
            let series = ChartSeries(candles: [candle(0, o: 1, h: 2, l: 1, c: 1.5, v: value)], interval: .minutes(1))
            #expect(series.candles == [candle(0, o: 1, h: 2, l: 1, c: 1.5, v: nil)])
        }
    }

    @Test("A bar at a time that is not finite is dropped")
    func nonFiniteTime() {
        let nan = Date(timeIntervalSince1970: .nan)
        #expect(ChartSeries(candles: [Candle(time: nan, open: 1, high: 2, low: 1, close: 1.5)], interval: .minutes(1)).isEmpty)
        #expect(ChartSeries(points: [PricePoint(time: nan, value: 1.0)], interval: .minutes(1)).isEmpty)
        var series = tenCandleSeries()
        let before = series
        #expect(series.apply(price: 5, at: nan, maxCount: nil) == .ignored)
        #expect(series == before)
    }

    // MARK: Updates

    @Test("Updates with bad data are ignored and change nothing")
    func badUpdatesAreIgnored() {
        for value in bad {
            var candles = tenCandleSeries()
            let before = candles
            #expect(candles.upsert(candle(540, o: 1, h: 2, l: value, c: 1.5), maxCount: nil) == .ignored)
            #expect(candles.upsert(candle(600, o: value, h: 2, l: 1, c: 1.5), maxCount: nil) == .ignored)
            #expect(candles.apply(price: value, at: date(600), maxCount: nil) == .ignored)
            #expect(candles.apply(price: value, at: date(540), maxCount: nil) == .ignored)
            #expect(candles.upsert(point(600, value), maxCount: nil) == .ignored)
            #expect(candles == before)

            var points = tenPointSeries()
            let pointsBefore = points
            #expect(points.upsert(point(540, value), maxCount: nil) == .ignored)
            #expect(points.upsert(point(600, value), maxCount: nil) == .ignored)
            #expect(points.apply(price: value, at: date(600), maxCount: nil) == .ignored)
            #expect(points.upsert(candle(600, o: 1, h: 2, l: 1, c: value), maxCount: nil) == .ignored)
            #expect(points == pointsBefore)
        }
    }

    @Test("A candle that is not consistent is repaired when it arrives live, and a volume that is not finite is left out of a tick")
    func repairsLive() {
        var series = tenCandleSeries()
        #expect(series.upsert(candle(600, o: 5, h: 4, l: 6, c: 5.5), maxCount: nil) == .appended)
        #expect(series.candles?.last == candle(600, o: 5, h: 6, l: 4, c: 5.5))

        #expect(series.apply(price: 5.8, at: date(610), volume: .nan, maxCount: nil) == .updatedLast)
        #expect(series.candles?.last == candle(600, o: 5, h: 6, l: 4, c: 5.8))
        #expect(series.apply(price: 5.9, at: date(615), volume: 3, maxCount: nil) == .updatedLast)
        #expect(series.candles?.last?.volume == 3)
    }

    // MARK: Queries never trap

    @Test("The value range of a series made of bad candles can be asked for")
    func valueRangeWithBadData() throws {
        let series = ChartSeries(
            candles: [
                candle(0, o: 10, h: 8, l: 12, c: 11),
                candle(60, o: .nan, h: 9, l: 8, c: 8.5),
                candle(120, o: 10, h: 14, l: 9, c: 12),
            ],
            interval: .minutes(1)
        )
        #expect(series.valueRange(in: date(0)...date(120), style: .candles) == 8...14)
        // The window holds only the candle that was upside down: its range is the repaired one (it used to be 12...8, a trap).
        #expect(series.valueRange(in: date(0)...date(0), style: .candles) == 8...12)
        #expect(series.valueRange(in: date(0)...date(120), style: .line) == 11...12)
        let domain = ViewportMath.yDomain(
            series: series,
            style: .candles,
            visibleRange: date(0)...date(120),
            currentPrice: .nan,
            xDomainUpperBound: date(120),
            additionalRanges: [],
            configuration: ViewportConfiguration()
        )
        #expect(domain.lowerBound < 8 && domain.upperBound > 14)
    }

    @Test("A current price that is not finite does not take part in the autoscale, and an extent that is not finite gives 0...1")
    func yDomainIgnoresBadPrices() {
        let configuration = ViewportConfiguration()
        // A range cannot have a bound that is `nan` (making one traps), so the prices that are `nan` come in as the price alone.
        for value in bad {
            let extent = ViewportMath.yExtent(
                series: tenPointSeries(),
                style: .line,
                visibleRange: date(0)...date(540),
                currentPrice: value,
                xDomainUpperBound: date(540),
                additionalRanges: [9...16]
            )
            #expect(extent == 9...16)
        }
        for value in [Double.infinity, -Double.infinity] {
            let extent = ViewportMath.yExtent(
                series: tenPointSeries(),
                style: .line,
                visibleRange: date(0)...date(540),
                currentPrice: nil,
                xDomainUpperBound: date(540),
                additionalRanges: [value...value, Swift.min(9, value)...Swift.max(16, value)]
            )
            #expect(extent == 9...16)
            #expect(ViewportMath.yDomain(for: value...value, configuration: configuration) == 0...1)
            #expect(ViewportMath.yDomain(for: Swift.min(1, value)...Swift.max(1, value), configuration: configuration) == 0...1)
        }
        #expect(ViewportMath.yDomain(for: -Double.infinity...Double.infinity, configuration: configuration) == 0...1)
        #expect(ViewportMath.yExtent(
            series: .empty(interval: .minutes(1)),
            style: .line,
            visibleRange: date(0)...date(60),
            currentPrice: .nan,
            xDomainUpperBound: date(60),
            additionalRanges: []
        ) == nil)
    }

    @Test("The body of a candle that is not finite is a range that exists")
    func candleBodyRangeWithBadData() {
        let domain = 0.0...100
        for value in bad {
            let range = ViewportMath.candleBodyRange(candle(0, o: value, h: 2, l: 1, c: 1.5), yDomain: domain)
            #expect(range == 1.5...1.5)
            let both = ViewportMath.candleBodyRange(candle(0, o: value, h: 2, l: 1, c: value), yDomain: domain)
            #expect(both == 0...0)
        }
        #expect(ViewportMath.candleBodyRange(candle(0, o: 5, h: 5, l: 5, c: 5), yDomain: 0...(.infinity)) == 5...5)
    }

    @Test("An indicator output with values that are not finite still has a range")
    func indicatorRangeWithBadData() {
        let values = [
            IndicatorValue(time: date(0), value: .nan),
            IndicatorValue(time: date(60), value: 3),
            IndicatorValue(time: date(120), value: .infinity),
            IndicatorValue(time: date(180), value: 7),
        ]
        let output = IndicatorOutput(lines: [IndicatorLine(id: "x", name: "X", values: values)])
        #expect(output.valueRange(in: date(0)...date(180)) == 3...7)
        let onlyBad = IndicatorOutput(lines: [IndicatorLine(id: "y", name: "Y", values: [values[0], values[2]])])
        #expect(onlyBad.valueRange(in: date(0)...date(180)) == nil)
    }
}
