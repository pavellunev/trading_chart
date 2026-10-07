import Foundation
import Testing
import TradingChartCore

@Suite("ChartSeries construction")
struct ChartSeriesConstructionTests {
    @Test("Points are sorted by time")
    func pointsSorted() {
        let series = ChartSeries(points: [point(120, 3), point(0, 1), point(60, 2)], interval: .minutes(1))
        #expect(series.points.map(\.time) == [date(0), date(60), date(120)])
        #expect(series.points.map(\.value) == [1, 2, 3])
        #expect(!series.hasCandles)
        #expect(series.candles == nil)
    }

    @Test("Duplicate timestamps keep the last occurrence")
    func duplicatesLastWins() {
        let series = ChartSeries(
            points: [point(0, 1), point(60, 2), point(60, 20), point(120, 3), point(0, 10)],
            interval: .minutes(1)
        )
        #expect(series.points == [point(0, 10), point(60, 20), point(120, 3)])
    }

    @Test("Candles are sorted and deduplicated, points mirror the closes")
    func candlesSortedAndDeduplicated() throws {
        let series = ChartSeries(
            candles: [
                candle(120, o: 5, h: 6, l: 4, c: 5.5),
                candle(0, o: 1, h: 2, l: 0.5, c: 1.5),
                candle(60, o: 2, h: 3, l: 1, c: 2.5),
                candle(60, o: 2, h: 4, l: 1, c: 3.5),
            ],
            interval: .minutes(1)
        )
        let candles = try #require(series.candles)
        #expect(candles.map(\.time) == [date(0), date(60), date(120)])
        #expect(candles[1].close == 3.5)
        #expect(series.hasCandles)
        #expect(series.points == [point(0, 1.5), point(60, 3.5), point(120, 5.5)])
    }

    @Test("Accessors describe the series")
    func accessors() {
        let series = tenCandleSeries()
        #expect(series.count == 10)
        #expect(!series.isEmpty)
        #expect(series.firstTime == date(0))
        #expect(series.lastTime == date(540))
        #expect(series.lastValue == 11)
        #expect(series.interval == .minutes(1))
    }

    @Test("Empty series has no bounds")
    func emptySeries() {
        let series = ChartSeries.empty(interval: .hours(1))
        #expect(series.isEmpty)
        #expect(series.count == 0)
        #expect(series.firstTime == nil)
        #expect(series.lastTime == nil)
        #expect(series.lastValue == nil)
        #expect(series.interval == .hours(1))
        #expect(series.index(nearestTo: date(0)) == nil)
        #expect(series.interpolatedValue(at: date(0)) == nil)
    }
}

@Suite("ChartSeries upsert and apply")
struct ChartSeriesMutationTests {
    // MARK: Candle upsert

    @Test("Upserting a candle with the last time replaces it")
    func candleUpdatesLast() throws {
        var series = tenCandleSeries()
        let replacement = candle(540, o: 11, h: 20, l: 9, c: 18, v: 5)
        #expect(series.upsert(replacement, maxCount: nil) == .updatedLast)
        #expect(series.count == 10)
        #expect(series.candles?.last == replacement)
        #expect(series.points.last == point(540, 18))
        #expect(series.lastValue == 18)
    }

    @Test("Upserting a newer candle appends it")
    func candleAppends() {
        var series = tenCandleSeries()
        let next = candle(600, o: 11, h: 12, l: 10, c: 12)
        #expect(series.upsert(next, maxCount: nil) == .appended)
        #expect(series.count == 11)
        #expect(series.candles?.last == next)
        #expect(series.points.count == 11)
        #expect(series.points.last == point(600, 12))
    }

    @Test("Upserting an older candle is ignored")
    func candleStaleIgnored() {
        var series = tenCandleSeries()
        let before = series
        #expect(series.upsert(candle(480, o: 1, h: 1, l: 1, c: 1), maxCount: nil) == .ignored)
        #expect(series == before)
    }

    @Test("maxCount trims the head when appending")
    func candleTrimsToMaxCount() {
        var series = tenCandleSeries()
        #expect(series.upsert(candle(600, o: 1, h: 2, l: 0, c: 1), maxCount: 10) == .appended)
        #expect(series.count == 10)
        #expect(series.firstTime == date(60))
        #expect(series.lastTime == date(600))
        #expect(series.candles?.count == 10)
        #expect(series.points.first == point(60, 12))

        // Updating the last bar never trims.
        #expect(series.upsert(candle(600, o: 1, h: 3, l: 0, c: 2), maxCount: 5) == .updatedLast)
        #expect(series.count == 10)
    }

    @Test("maxCount of zero or less keeps one bar")
    func maxCountIsClamped() {
        var series = tenCandleSeries()
        series.upsert(candle(600, o: 1, h: 1, l: 1, c: 1), maxCount: 0)
        #expect(series.count == 1)
        #expect(series.firstTime == date(600))
    }

    @Test("keepingFrom spares the bars from that time on, and trims the older ones only as far as maxCount asks")
    func trimSparesProtectedBars() {
        // Ten candles at 0, 60 ... 540; the new one is the 11th.
        var protected = tenCandleSeries()
        #expect(protected.upsert(candle(600, o: 1, h: 2, l: 0, c: 1), maxCount: 4, keepingFrom: date(300)) == .appended)
        // Bars older than 300 (0, 60, ... 240: five of them) may go, but not more than the 7 in excess.
        #expect(protected.firstTime == date(300))
        #expect(protected.count == 6)
        #expect(protected.candles?.count == 6)
        #expect(protected.points.first == point(300, 9))

        // The excess is smaller than the number of older bars: trimmed exactly to maxCount.
        var loose = tenCandleSeries()
        loose.upsert(candle(600, o: 1, h: 2, l: 0, c: 1), maxCount: 9, keepingFrom: date(300))
        #expect(loose.count == 9)
        #expect(loose.firstTime == date(120))

        // Nothing older than the boundary: nothing is trimmed.
        var all = tenCandleSeries()
        all.upsert(candle(600, o: 1, h: 2, l: 0, c: 1), maxCount: 4, keepingFrom: date(0))
        #expect(all.count == 11)
    }

    @Test("keepingFrom works for point series, ticks and a nil boundary")
    func trimProtectionOtherEntryPoints() {
        var points = tenPointSeries()
        points.upsert(point(600, 7), maxCount: 4, keepingFrom: date(420))
        #expect(points.points.map(\.time) == [date(420), date(480), date(540), date(600)])
        points.upsert(point(660, 8), maxCount: 4, keepingFrom: date(420))
        #expect(points.points.map(\.time) == [date(420), date(480), date(540), date(600), date(660)])

        var ticks = tenCandleSeries()
        ticks.apply(price: 50, at: date(660), maxCount: 3, keepingFrom: date(360))
        #expect(ticks.firstTime == date(360))
        #expect(ticks.candles?.first?.time == date(360))
        #expect(ticks.count == 5)

        var free = tenCandleSeries()
        free.apply(price: 50, at: date(660), maxCount: 3, keepingFrom: nil)
        #expect(free.count == 3)
    }

    // MARK: Point upsert

    @Test("Point series: update, append and stale")
    func pointSeriesUpsert() {
        var series = tenPointSeries()
        #expect(series.upsert(point(540, 99), maxCount: nil) == .updatedLast)
        #expect(series.lastValue == 99)
        #expect(series.count == 10)

        #expect(series.upsert(point(600, 7), maxCount: nil) == .appended)
        #expect(series.count == 11)
        #expect(series.lastTime == date(600))

        let before = series
        #expect(series.upsert(point(300, 1), maxCount: nil) == .ignored)
        #expect(series == before)
    }

    @Test("Point series trims to maxCount")
    func pointSeriesTrims() {
        var series = tenPointSeries()
        series.upsert(point(600, 7), maxCount: 4)
        #expect(series.points == [point(420, 16), point(480, 12), point(540, 11), point(600, 7)])
    }

    @Test("Upserting a candle into a point series stores its close")
    func candleIntoPointSeries() {
        var series = tenPointSeries()
        #expect(series.upsert(candle(540, o: 1, h: 50, l: 0, c: 30), maxCount: nil) == .updatedLast)
        #expect(series.points.last == point(540, 30))
        #expect(!series.hasCandles)
        #expect(series.upsert(candle(600, o: 1, h: 50, l: 0, c: 31), maxCount: nil) == .appended)
        #expect(series.points.last == point(600, 31))
        #expect(!series.hasCandles)
    }

    @Test("An empty series is a candle series by default: the first candle, or the first tick, opens a candle")
    func emptySeriesAdoptsCandles() {
        var series = ChartSeries.empty(interval: .minutes(1))
        #expect(series.hasCandles)
        #expect(series.upsert(candle(60, o: 1, h: 2, l: 0.5, c: 1.5), maxCount: nil) == .appended)
        #expect(series.hasCandles)
        #expect(series.points == [point(60, 1.5)])
        #expect(series.upsert(candle(120, o: 1.5, h: 2, l: 1, c: 2), maxCount: nil) == .appended)
        #expect(series.candles?.count == 2)

        var ticked = ChartSeries.empty(interval: .minutes(1))
        #expect(ticked.apply(price: 7, at: date(65), maxCount: nil) == .appended)
        #expect(ticked.candles == [flatCandle(60, 7)])
    }

    @Test("History of candles prepended after the first tick of an empty series is kept")
    func historyAfterFirstTick() {
        var series = ChartSeries.empty(interval: .minutes(1))
        series.apply(price: 7, at: date(600), maxCount: nil)
        series.apply(price: 8, at: date(660), maxCount: nil)
        let history = ChartSeries(candles: (0..<5).map { flatCandle(TimeInterval($0) * 60 + 300, 5) }, interval: .minutes(1))

        series.prepend(history)

        #expect(series.count == 7)
        #expect(series.firstTime == date(300))
        #expect(series.candles?.count == 7)
        #expect(series.points.count == 7)
    }

    @Test("An empty series of points stays a point series for the first point and takes candles as points")
    func emptySeriesKeepsPoints() {
        var series = ChartSeries.empty(interval: .minutes(1), kind: .points)
        #expect(!series.hasCandles)
        #expect(series.upsert(point(60, 5), maxCount: nil) == .appended)
        #expect(!series.hasCandles)
        #expect(series.points == [point(60, 5)])

        var ticked = ChartSeries.empty(interval: .minutes(1), kind: .points)
        #expect(ticked.apply(price: 7, at: date(65), maxCount: nil) == .appended)
        #expect(!ticked.hasCandles)
        #expect(ticked.points == [point(60, 7)])
    }

    @Test("A point upserted into an empty series of candles is a tick: it opens a candle at the start of its bucket")
    func pointIntoAnEmptyCandleSeriesIsATick() {
        var series = ChartSeries.empty(interval: .minutes(1))
        #expect(series.upsert(point(65, 5), maxCount: nil) == .appended)
        #expect(series.hasCandles)
        #expect(series.candles == [flatCandle(60, 5)])  // at the start of its bucket, not as it came

        // The next points of the bucket merge into its candle, like ticks.
        #expect(series.upsert(point(100, 7), maxCount: nil) == .updatedLast)
        #expect(series.upsert(point(110, 4), maxCount: nil) == .updatedLast)
        #expect(series.candles == [candle(60, o: 5, h: 7, l: 4, c: 4)])
        #expect(series.upsert(point(125, 6), maxCount: nil) == .appended)
        #expect(series.candles?.count == 2)
        #expect(series.points == [point(60, 4), point(120, 6)])
    }

    @Test("A candle upserted into an empty series of points makes it a candle series")
    func emptySeriesAdoptsCandlesFromACandle() {
        var series = ChartSeries.empty(interval: .minutes(1), kind: .points)
        #expect(!series.hasCandles)
        #expect(series.upsert(candle(120, o: 1, h: 2, l: 0.5, c: 1.5), maxCount: nil) == .appended)
        #expect(series.hasCandles)
        series.prepend(ChartSeries(candles: [flatCandle(60, 1)], interval: .minutes(1)))
        #expect(series.candles?.count == 2)
        #expect(series.points.count == 2)
    }

    @Test("A tick on an empty series opens what its kind says, whatever came before on another series")
    func tickKeepsTheKind() {
        var candles = ChartSeries.empty(interval: .minutes(1))
        #expect(candles.apply(price: 7, at: date(65), maxCount: nil) == .appended)
        #expect(candles.candles == [flatCandle(60, 7)])

        var line = ChartSeries.empty(interval: .minutes(1), kind: .points)
        #expect(line.apply(price: 7, at: date(65), maxCount: nil) == .appended)
        #expect(line.points == [point(60, 7)])
        #expect(!line.hasCandles)
    }

    // MARK: Ticks

    @Test("A tick inside the last bucket updates high, low and close")
    func tickUpdatesLastCandle() throws {
        var series = ChartSeries(
            candles: [candle(0, o: 10, h: 12, l: 9, c: 11, v: 100)],
            interval: .minutes(1)
        )
        #expect(series.apply(price: 13, at: date(30), volume: 5, maxCount: nil) == .updatedLast)
        #expect(series.candles == [candle(0, o: 10, h: 13, l: 9, c: 13, v: 105)])

        #expect(series.apply(price: 8, at: date(59), volume: nil, maxCount: nil) == .updatedLast)
        #expect(series.candles == [candle(0, o: 10, h: 13, l: 8, c: 8, v: 105)])

        // Inside the range: only the close changes.
        #expect(series.apply(price: 10.5, at: date(10), maxCount: nil) == .updatedLast)
        #expect(series.candles == [candle(0, o: 10, h: 13, l: 8, c: 10.5, v: 105)])
        #expect(series.points == [point(0, 10.5)])
    }

    @Test("A tick without prior volume starts the volume")
    func tickVolumeStartsFromNil() {
        var series = ChartSeries(candles: [flatCandle(0, 10)], interval: .minutes(1))
        series.apply(price: 10, at: date(5), volume: 3, maxCount: nil)
        #expect(series.candles?.last?.volume == 3)
    }

    @Test("A tick in a new bucket appends a flat candle at the bucket start")
    func tickAppendsCandle() {
        var series = ChartSeries(candles: [candle(0, o: 10, h: 12, l: 9, c: 11)], interval: .minutes(1))
        #expect(series.apply(price: 14, at: date(135), volume: 2, maxCount: nil) == .appended)
        #expect(series.candles?.last == candle(120, o: 14, h: 14, l: 14, c: 14, v: 2))
        #expect(series.points.last == point(120, 14))
        #expect(series.count == 2)
    }

    @Test("A tick in an older bucket is ignored")
    func tickStaleIgnored() {
        var series = ChartSeries(
            candles: [candle(0, o: 1, h: 1, l: 1, c: 1), candle(60, o: 2, h: 2, l: 2, c: 2)],
            interval: .minutes(1)
        )
        let before = series
        #expect(series.apply(price: 5, at: date(30), maxCount: nil) == .ignored)
        #expect(series == before)
    }

    @Test("A tick trims to maxCount when it opens a new bucket")
    func tickTrims() {
        var series = tenCandleSeries()
        series.apply(price: 1, at: date(605), maxCount: 10)
        #expect(series.count == 10)
        #expect(series.firstTime == date(60))
        #expect(series.lastTime == date(600))
    }

    @Test("A tick on a point series becomes a point at the bucket start")
    func tickOnPointSeries() {
        var series = ChartSeries(points: [point(0, 1), point(60, 2)], interval: .minutes(1))
        #expect(series.apply(price: 3, at: date(100), volume: 9, maxCount: nil) == .updatedLast)
        #expect(series.points == [point(0, 1), point(60, 3)])

        #expect(series.apply(price: 4, at: date(130), maxCount: nil) == .appended)
        #expect(series.points.last == point(120, 4))
        #expect(!series.hasCandles)

        #expect(series.apply(price: 9, at: date(10), maxCount: nil) == .ignored)
    }

    @Test("Upserting a point into a candle series applies it as a tick")
    func pointIntoCandleSeries() {
        var series = ChartSeries(candles: [candle(0, o: 10, h: 12, l: 9, c: 11)], interval: .minutes(1))
        #expect(series.upsert(point(30, 15), maxCount: nil) == .updatedLast)
        #expect(series.candles == [candle(0, o: 10, h: 15, l: 9, c: 15)])
        #expect(series.upsert(point(70, 16), maxCount: nil) == .appended)
        #expect(series.candles?.last == candle(60, o: 16, h: 16, l: 16, c: 16))
    }

    @Test("Ticks use the series interval for bucketing")
    func tickUsesSeriesInterval() {
        var series = ChartSeries(candles: [flatCandle(1_700_000_100, 10)], interval: .minutes(5))
        // 1_700_000_399 is still inside the 5-minute bucket that starts at 1_700_000_100.
        #expect(series.apply(price: 11, at: date(1_700_000_399), maxCount: nil) == .updatedLast)
        #expect(series.apply(price: 12, at: date(1_700_000_400), maxCount: nil) == .appended)
        #expect(series.lastTime == date(1_700_000_400))
    }
}

@Suite("ChartSeries prepend")
struct ChartSeriesPrependTests {
    @Test("Prepending adds only bars older than the first one")
    func prependTakesOlderBars() {
        var series = ChartSeries(points: [point(300, 4), point(360, 5)], interval: .minutes(1))
        let older = ChartSeries(
            points: [point(120, 1), point(180, 2), point(240, 3), point(300, 99), point(360, 99)],
            interval: .minutes(1)
        )
        series.prepend(older)
        #expect(series.points == [point(120, 1), point(180, 2), point(240, 3), point(300, 4), point(360, 5)])
    }

    @Test("Prepending candles keeps candles and points in sync")
    func prependCandles() {
        var series = ChartSeries(candles: [candle(120, o: 3, h: 4, l: 2, c: 3.5)], interval: .minutes(1))
        series.prepend(ChartSeries(
            candles: [candle(0, o: 1, h: 2, l: 0.5, c: 1.5), candle(60, o: 2, h: 3, l: 1.5, c: 2.5)],
            interval: .minutes(1)
        ))
        #expect(series.candles?.map(\.time) == [date(0), date(60), date(120)])
        #expect(series.points == [point(0, 1.5), point(60, 2.5), point(120, 3.5)])
    }

    @Test("Prepending a page with no older bars changes nothing")
    func prependNothingOlder() {
        var series = tenPointSeries()
        let before = series
        series.prepend(ChartSeries(points: [point(540, 1), point(600, 2)], interval: .minutes(1)))
        #expect(series == before)
    }

    @Test("Prepending a different interval is a no-op")
    func prependIntervalMismatch() {
        var series = tenPointSeries()
        let before = series
        series.prepend(ChartSeries(points: [point(-300, 1)], interval: .minutes(5)))
        #expect(series == before)
    }

    @Test("A page of points into a series of candles is converted to flat candles: the series stays candles")
    func pointsPageIntoCandles() {
        var series = ChartSeries(
            candles: [candle(120, o: 3, h: 5, l: 2, c: 4, v: 9), candle(180, o: 4, h: 6, l: 3, c: 5)],
            interval: .minutes(1)
        )
        series.prepend(ChartSeries(points: [point(0, 1), point(60, 2), point(120, 99)], interval: .minutes(1)))

        #expect(series.hasCandles)
        #expect(series.candles == [
            flatCandle(0, 1),
            flatCandle(60, 2),
            candle(120, o: 3, h: 5, l: 2, c: 4, v: 9),
            candle(180, o: 4, h: 6, l: 3, c: 5),
        ])
        #expect(series.points == [point(0, 1), point(60, 2), point(120, 4), point(180, 5)])
        #expect(series.candles?.prefix(2).allSatisfy { $0.volume == nil } == true)
    }

    @Test("A page of points that is off the grid snaps to the start of its bucket, and the points of a bucket make one candle")
    func offGridPointsPageSnapsAndMerges() {
        var series = ChartSeries(candles: [candle(600, o: 10, h: 12, l: 9, c: 11)], interval: .minutes(1))
        series.prepend(ChartSeries(
            points: [
                point(5, 3), point(20, 7), point(50, 1),  // one bucket: open 3, high 7, low 1, close 1
                point(65, 4),
                point(130, 9), point(139, 9),
                point(599, 8),  // the last second of the bucket before the series
                point(605, 99), point(640, 99),  // the bucket of the first candle: not older
            ],
            interval: .minutes(1)
        ))

        #expect(series.candles == [
            candle(0, o: 3, h: 7, l: 1, c: 1),
            flatCandle(60, 4),
            flatCandle(120, 9),
            flatCandle(540, 8),
            candle(600, o: 10, h: 12, l: 9, c: 11),
        ])
        #expect(series.points == [point(0, 1), point(60, 4), point(120, 9), point(540, 8), point(600, 11)])
    }

    @Test("A page of candles into a series of points is converted to points at their close: the series stays points")
    func candlesPageIntoPoints() {
        var series = ChartSeries(points: [point(120, 4), point(180, 5)], interval: .minutes(1))
        series.prepend(ChartSeries(
            candles: [candle(0, o: 1, h: 2, l: 0.5, c: 1.5, v: 7), candle(60, o: 2, h: 3, l: 1.5, c: 2.5)],
            interval: .minutes(1)
        ))

        #expect(!series.hasCandles)
        #expect(series.candles == nil)
        #expect(series.content == .points([point(0, 1.5), point(60, 2.5), point(120, 4), point(180, 5)]))
        #expect(series.points == [point(0, 1.5), point(60, 2.5), point(120, 4), point(180, 5)])
    }

    @Test("Whatever the series was fed first, it keeps its kind: ticks of candles then a page of points, points then candles")
    func seriesKeepsItsKind() {
        var ticked = ChartSeries.empty(interval: .minutes(1))
        ticked.apply(price: 7, at: date(605), maxCount: nil)
        ticked.apply(price: 8, at: date(665), maxCount: nil)
        ticked.prepend(ChartSeries(points: [point(300, 5), point(360, 6)], interval: .minutes(1)))
        #expect(ticked.candles == [flatCandle(300, 5), flatCandle(360, 6), flatCandle(600, 7), flatCandle(660, 8)])
        #expect(ticked.points == [point(300, 5), point(360, 6), point(600, 7), point(660, 8)])

        var line = ChartSeries.empty(interval: .minutes(1), kind: .points)
        line.apply(price: 7, at: date(605), maxCount: nil)
        line.prepend(ChartSeries(candles: [flatCandle(540, 6)], interval: .minutes(1)))
        #expect(!line.hasCandles)
        #expect(line.points == [point(540, 6), point(600, 7)])
    }

    @Test("After a page of the other kind the live rules are those of the kind the series kept")
    func liveUpdatesAfterAConvertedPage() {
        var candles = ChartSeries(candles: [flatCandle(600, 10)], interval: .minutes(1))
        candles.prepend(ChartSeries(points: [point(0, 1), point(60, 2)], interval: .minutes(1)))
        #expect(candles.upsert(point(630, 12), maxCount: nil) == .updatedLast)
        #expect(candles.upsert(point(645, 9), maxCount: nil) == .updatedLast)
        #expect(candles.apply(price: 11, at: date(650), volume: 3, maxCount: nil) == .updatedLast)
        #expect(candles.candles?.last == candle(600, o: 10, h: 12, l: 9, c: 11, v: 3))
        #expect(candles.upsert(point(670, 13), maxCount: nil) == .appended)
        #expect(candles.hasCandles)
        #expect(candles.count == 4)

        var points = ChartSeries(points: [point(600, 10)], interval: .minutes(1))
        points.prepend(ChartSeries(candles: [flatCandle(0, 1), flatCandle(60, 2)], interval: .minutes(1)))
        #expect(points.upsert(point(600, 12), maxCount: nil) == .updatedLast)
        #expect(points.upsert(point(630, 13), maxCount: nil) == .appended)
        #expect(points.apply(price: 14, at: date(700), maxCount: nil) == .appended)  // a tick of the next bucket, a point at 660
        #expect(!points.hasCandles)
        #expect(points.points == [point(0, 1), point(60, 2), point(600, 12), point(630, 13), point(660, 14)])
    }

    @Test("A page of the other kind that adds nothing changes nothing: the series keeps its kind")
    func pageOfTheOtherKindThatAddsNothing() {
        var candles = tenCandleSeries()
        let candlesBefore = candles
        candles.prepend(ChartSeries(points: [point(540, 1), point(600, 2)], interval: .minutes(1)))  // not older
        candles.prepend(ChartSeries.empty(interval: .minutes(1), kind: .points))
        #expect(candles == candlesBefore)

        var points = tenPointSeries()
        let pointsBefore = points
        points.prepend(ChartSeries(candles: [flatCandle(540, 1)], interval: .minutes(1)))
        points.prepend(.empty(interval: .minutes(1)))  // an empty series of candles: the default of `empty`
        #expect(points == pointsBefore)
        #expect(!points.hasCandles)
    }

    @Test("An empty series takes the page as it is, kind included; an empty page does not change an empty series")
    func emptySeriesTakesThePage() {
        var line = ChartSeries.empty(interval: .minutes(1), kind: .points)
        line.prepend(.empty(interval: .minutes(1)))
        #expect(!line.hasCandles)
        #expect(line.isEmpty)

        line.prepend(ChartSeries(candles: [flatCandle(60, 1)], interval: .minutes(1)))
        #expect(line.candles == [flatCandle(60, 1)])

        var candles = ChartSeries.empty(interval: .minutes(1))
        candles.prepend(ChartSeries(points: [point(65, 2)], interval: .minutes(1)))
        #expect(!candles.hasCandles)
        #expect(candles.points == [point(65, 2)])  // as it came: no snapping into a bucket
    }

    @Test("An empty series adopts the prepended one")
    func prependIntoEmpty() {
        var series = ChartSeries.empty(interval: .minutes(1))
        series.prepend(tenCandleSeries())
        #expect(series == tenCandleSeries())
    }
}

@Suite("ChartSeries queries")
struct ChartSeriesQueryTests {
    private let fourPoints = ChartSeries(
        points: [point(0, 10), point(60, 20), point(120, 40), point(180, 30)],
        interval: .minutes(1)
    )

    @Test("index(nearestTo:) picks the closest bar")
    func nearestIndex() {
        #expect(fourPoints.index(nearestTo: date(0)) == 0)
        #expect(fourPoints.index(nearestTo: date(10)) == 0)
        #expect(fourPoints.index(nearestTo: date(31)) == 1)
        #expect(fourPoints.index(nearestTo: date(60)) == 1)
        #expect(fourPoints.index(nearestTo: date(100)) == 2)
        #expect(fourPoints.index(nearestTo: date(179)) == 3)
    }

    @Test("index(nearestTo:) resolves ties to the earlier bar and clamps outside the series")
    func nearestIndexTiesAndEdges() {
        #expect(fourPoints.index(nearestTo: date(30)) == 0)
        #expect(fourPoints.index(nearestTo: date(90)) == 1)
        #expect(fourPoints.index(nearestTo: date(-1_000)) == 0)
        #expect(fourPoints.index(nearestTo: date(10_000)) == 3)
    }

    @Test("index(nearestTo:) works for candle series")
    func nearestIndexCandles() {
        #expect(tenCandleSeries().index(nearestTo: date(310)) == 5)
    }

    @Test("interpolatedValue interpolates linearly between bars")
    func interpolationInside() {
        #expect(fourPoints.interpolatedValue(at: date(30)) == 15)
        #expect(fourPoints.interpolatedValue(at: date(90)) == 30)
        #expect(fourPoints.interpolatedValue(at: date(150)) == 35)
        #expect(fourPoints.interpolatedValue(at: date(60)) == 20)
        #expect(fourPoints.interpolatedValue(at: date(15)) == 12.5)
    }

    @Test("interpolatedValue clamps to the edge values")
    func interpolationAtEdges() {
        #expect(fourPoints.interpolatedValue(at: date(-500)) == 10)
        #expect(fourPoints.interpolatedValue(at: date(0)) == 10)
        #expect(fourPoints.interpolatedValue(at: date(180)) == 30)
        #expect(fourPoints.interpolatedValue(at: date(9_999)) == 30)
    }

    @Test("interpolatedValue uses closes of a candle series")
    func interpolationCandles() {
        // closes: t=0 -> 10, t=60 -> 12
        #expect(tenCandleSeries().interpolatedValue(at: date(45)) == 11.5)
    }

    @Test("valueRange over points covers the inclusive window")
    func valueRangePoints() {
        let series = tenPointSeries()
        // bars at t=120...300 have values 11, 15, 14, 9
        #expect(series.valueRange(in: date(120)...date(300), style: .line) == 9...15)
        // window bounds between bars
        #expect(series.valueRange(in: date(100)...date(250), style: .area) == 11...15)
        // a single bar
        #expect(series.valueRange(in: date(420)...date(420), style: .line) == 16...16)
        // the whole series
        #expect(series.valueRange(in: date(-10)...date(10_000), style: .line) == 9...16)
    }

    @Test("valueRange is nil when no bar is in the window")
    func valueRangeEmptyWindow() {
        let series = tenPointSeries()
        #expect(series.valueRange(in: date(-500)...date(-1), style: .line) == nil)
        #expect(series.valueRange(in: date(1_000)...date(2_000), style: .line) == nil)
        #expect(series.valueRange(in: date(61)...date(119), style: .line) == nil)
        #expect(ChartSeries.empty(interval: .minutes(1)).valueRange(in: date(0)...date(10), style: .line) == nil)
    }

    @Test("valueRange uses low and high for candle style on a candle series")
    func valueRangeCandles() {
        let series = tenCandleSeries()
        // bars 2...5: lows 10, 14, 13, 8; highs 12, 16, 15, 10
        #expect(series.valueRange(in: date(120)...date(300), style: .candles) == 8...16)
        // the same window as a line uses the closes 11, 15, 14, 9
        #expect(series.valueRange(in: date(120)...date(300), style: .line) == 9...15)
    }

    @Test("valueRange for candle style on a point series falls back to values")
    func valueRangeCandlesWithoutOHLC() {
        #expect(tenPointSeries().valueRange(in: date(120)...date(300), style: .candles) == 9...15)
    }
}
