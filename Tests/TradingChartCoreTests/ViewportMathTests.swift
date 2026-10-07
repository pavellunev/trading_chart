import CoreGraphics
import Foundation
import Testing
import TradingChartCore

private let config = ViewportConfiguration()
private let minute = ChartInterval.minutes(1)

@Suite("ViewportConfiguration")
struct ViewportConfigurationTests {
    @Test("the defaults are the documented ones")
    func defaults() {
        let configuration = ViewportConfiguration()
        #expect(configuration.visibleBars == 60)
        #expect(configuration.candleVisibleBars == 40)
        #expect(configuration.minVisibleBars == 10)
        #expect(configuration.maxVisibleBars == 400)
        #expect(configuration.trailingPaddingBars == 6)
        #expect(configuration.maxTrailingPaddingFraction == 0.2)
        #expect(configuration.liveEdgeToleranceBars == 2)
        #expect(configuration.candleLeadingPaddingBars == 1)
        #expect(configuration.verticalPaddingFraction == 0.08)
    }

    @Test("Default window width depends on the style")
    func defaultVisibleBars() {
        #expect(config.defaultVisibleBars(for: .line) == 60)
        #expect(config.defaultVisibleBars(for: .area) == 60)
        #expect(config.defaultVisibleBars(for: .candles) == 40)

        let custom = ViewportConfiguration(visibleBars: 100, candleVisibleBars: 25)
        #expect(custom.defaultVisibleBars(for: .line) == 100)
        #expect(custom.defaultVisibleBars(for: .candles) == 25)
    }
}

@Suite("ViewportMath effective configuration")
struct EffectiveConfigurationTests {
    private func effective(
        _ bars: Double,
        plotWidth: CGFloat = 0,
        overhang: CGFloat? = nil,
        configuration: ViewportConfiguration = config
    ) -> ViewportConfiguration {
        ViewportMath.effectiveConfiguration(configuration, visibleBars: bars, plotWidth: plotWidth, badgeOverhang: overhang)
    }

    @Test("At the default window widths the padding and the tolerance match the reference chart")
    func parityAtDefaultWidths() {
        for bars in [40.0, 60.0] {
            let result = effective(bars)
            #expect(result.trailingPaddingBars == 6)
            #expect(result.liveEdgeToleranceBars == 2)
        }
    }

    @Test("A zoomed-in window gets at most a fifth of its width as padding and a tenth as tolerance")
    func zoomedInWindow() {
        // min(6, 10 * 0.2) = 2 and min(2, 10 * 0.1) = 1
        let ten = effective(10)
        #expect(ten.trailingPaddingBars == 2)
        #expect(ten.liveEdgeToleranceBars == 1)
        // min(6, 20 * 0.2) = 4 and min(2, 20 * 0.1) = 2
        let twenty = effective(20)
        #expect(twenty.trailingPaddingBars == 4)
        #expect(twenty.liveEdgeToleranceBars == 2)
        // 400 bars: the configured values win
        let wide = effective(400)
        #expect(wide.trailingPaddingBars == 6)
        #expect(wide.liveEdgeToleranceBars == 2)
    }

    @Test("The fraction is configurable")
    func customFraction() {
        let custom = ViewportConfiguration(maxTrailingPaddingFraction: 0.5)
        #expect(effective(10, configuration: custom).trailingPaddingBars == 5)
        #expect(effective(40, configuration: custom).trailingPaddingBars == 6)
        #expect(effective(10, configuration: ViewportConfiguration(maxTrailingPaddingFraction: 0)).trailingPaddingBars == 0)
    }

    @Test("Only the padding and the tolerance change")
    func otherFieldsUntouched() {
        var custom = ViewportConfiguration(visibleBars: 90, candleVisibleBars: 33, verticalPaddingFraction: 0.3)
        custom.minVisibleBars = 7
        let result = effective(10, configuration: custom)
        #expect(result.visibleBars == 90)
        #expect(result.candleVisibleBars == 33)
        #expect(result.minVisibleBars == 7)
        #expect(result.verticalPaddingFraction == 0.3)
        #expect(result.candleLeadingPaddingBars == custom.candleLeadingPaddingBars)
    }

    @Test("A badge that reaches far into the plot widens the padding")
    func badgeWidensPadding() {
        // 320pt / 40 bars = 8pt per bar; overhang 64 -> ceil((64 + 6) / 8) = 9 bars
        #expect(effective(40, plotWidth: 320, overhang: 64).trailingPaddingBars == 9)
        // overhang 24 -> ceil(30 / 8) = 4 bars, the baseline of 6 wins
        #expect(effective(40, plotWidth: 320, overhang: 24).trailingPaddingBars == 6)
        // 100 bars: 3.2pt per bar, overhang 24 -> ceil(30 / 3.2) = 10 bars
        #expect(effective(100, plotWidth: 320, overhang: 24).trailingPaddingBars == 10)
    }

    @Test("A badge that sits inside the axis column still keeps one clearance")
    func badgeWithoutOverhang() {
        // 6pt / 8pt per bar -> 1 bar, below the baseline
        #expect(effective(40, plotWidth: 320, overhang: 0).trailingPaddingBars == 6)
        // a negative overhang counts as none
        #expect(effective(40, plotWidth: 320, overhang: -30).trailingPaddingBars == 6)
        // 10 bars, 32pt per bar: ceil(6 / 32) = 1 bar, the baseline of 2 wins
        #expect(effective(10, plotWidth: 320, overhang: 0).trailingPaddingBars == 2)
    }

    @Test("Without a badge or without a measured plot only the baseline applies")
    func noBadgeTerm() {
        #expect(effective(40, plotWidth: 320, overhang: nil).trailingPaddingBars == 6)
        #expect(effective(40, plotWidth: 0, overhang: 200).trailingPaddingBars == 6)
        #expect(effective(10, plotWidth: 0, overhang: 200).trailingPaddingBars == 2)
    }

    @Test("The badge never takes more than half of the window")
    func badgeCappedAtHalfWindow() {
        // 100pt / 10 bars = 10pt per bar; overhang 500 would need 51 bars
        #expect(effective(10, plotWidth: 100, overhang: 500).trailingPaddingBars == 5)
    }

    @Test("A degenerate window width returns the configuration unchanged")
    func degenerateWidth() {
        #expect(effective(0, plotWidth: 320, overhang: 50) == config)
        #expect(effective(-5) == config)
        #expect(effective(.infinity) == config)
    }

    @Test("The padding of the effective configuration places the live edge")
    func feedsEndAnchor() {
        let last = date(1_000_000)
        let result = effective(10)
        // (2 - 10) * 60
        #expect(ViewportMath.endAnchor(lastTime: last, interval: minute, visibleBars: 10, configuration: result)
            == last.addingTimeInterval(-480))
        // one bar of tolerance at 10 bars
        let anchor = last.addingTimeInterval(-480)
        #expect(ViewportMath.isAtLiveEdge(
            scrollPosition: anchor.addingTimeInterval(-60), lastTime: last, interval: minute, visibleBars: 10, configuration: result
        ))
        #expect(!ViewportMath.isAtLiveEdge(
            scrollPosition: anchor.addingTimeInterval(-61), lastTime: last, interval: minute, visibleBars: 10, configuration: result
        ))
    }
}

@Suite("ViewportMath live edge")
struct LiveEdgeTests {
    private let last = date(1_000_000)

    @Test("endAnchor places the last bar trailingPaddingBars before the right edge")
    func endAnchor() {
        // (6 - 60) * 60 = -3240; (6 - 40) * 60 = -2040
        #expect(ViewportMath.endAnchor(lastTime: last, interval: minute, visibleBars: 60, configuration: config)
            == last.addingTimeInterval(-3_240))
        #expect(ViewportMath.endAnchor(lastTime: last, interval: minute, visibleBars: 40, configuration: config)
            == last.addingTimeInterval(-2_040))
        // 5-minute bars scale the offset: (6 - 60) * 300 = -16200
        #expect(ViewportMath.endAnchor(lastTime: last, interval: .minutes(5), visibleBars: 60, configuration: config)
            == last.addingTimeInterval(-16_200))
    }

    @Test("endAnchor honours custom trailing padding")
    func endAnchorCustomPadding() {
        let custom = ViewportConfiguration(trailingPaddingBars: 10)
        // (10 - 60) * 60 = -3000
        #expect(ViewportMath.endAnchor(lastTime: last, interval: minute, visibleBars: 60, configuration: custom)
            == last.addingTimeInterval(-3_000))
    }

    @Test("isAtLiveEdge is true within the two-bar tolerance")
    func liveEdgeTolerance() {
        // anchor = last - 3240, tolerance = 2 * 60 = 120 -> boundary at last - 3360
        func atLiveEdge(_ offset: TimeInterval) -> Bool {
            ViewportMath.isAtLiveEdge(
                scrollPosition: last.addingTimeInterval(offset),
                lastTime: last,
                interval: minute,
                visibleBars: 60,
                configuration: config
            )
        }
        #expect(atLiveEdge(-3_240))
        #expect(atLiveEdge(-3_360))
        #expect(!atLiveEdge(-3_361))
        #expect(!atLiveEdge(-10_000))
        #expect(atLiveEdge(0))
        #expect(atLiveEdge(5_000))
    }

    @Test("isAtLiveEdge depends on the visible bar count")
    func liveEdgeCandles() {
        // For 40 candles the anchor is last - 2040, boundary last - 2160.
        let scroll = last.addingTimeInterval(-2_200)
        #expect(!ViewportMath.isAtLiveEdge(
            scrollPosition: scroll, lastTime: last, interval: minute, visibleBars: 40, configuration: config
        ))
        // The same scroll position is at the live edge for a 60-bar window (boundary last - 3360).
        #expect(ViewportMath.isAtLiveEdge(
            scrollPosition: scroll, lastTime: last, interval: minute, visibleBars: 60, configuration: config
        ))
    }

    @Test("isAtLiveEdge is true when there is no data")
    func liveEdgeWithoutData() {
        #expect(ViewportMath.isAtLiveEdge(
            scrollPosition: date(0), lastTime: nil, interval: minute, visibleBars: 60, configuration: config
        ))
    }
}

@Suite("ViewportMath xDomain")
struct XDomainTests {
    private func series(count: Int, candles: Bool) -> ChartSeries {
        if candles {
            return ChartSeries(candles: (0..<count).map { flatCandle(TimeInterval($0) * 60, 1) }, interval: minute)
        }
        return ChartSeries(points: (0..<count).map { point(TimeInterval($0) * 60, 1) }, interval: minute)
    }

    @Test("Line domain runs from the first bar to the last bar plus trailing padding")
    func lineDomain() {
        // last = 99 * 60 = 5940, trailing = 6 * 60 = 360
        let domain = ViewportMath.xDomain(series: series(count: 100, candles: false), style: .line, configuration: config, now: date(0))
        #expect(domain == date(0)...date(6_300))
        #expect(ViewportMath.xDomain(series: series(count: 100, candles: false), style: .area, configuration: config, now: date(0))
            == date(0)...date(6_300))
    }

    @Test("Candle domain adds one bar of leading padding")
    func candleDomain() {
        let domain = ViewportMath.xDomain(series: series(count: 100, candles: true), style: .candles, configuration: config, now: date(0))
        #expect(domain == date(-60)...date(6_300))
    }

    @Test("Domain scales with the series interval and configuration")
    func domainScalesWithInterval() {
        let hourly = ChartSeries(
            points: [point(0, 1), point(3_600, 2), point(7_200, 3)],
            interval: .hours(1)
        )
        let custom = ViewportConfiguration(trailingPaddingBars: 2)
        #expect(ViewportMath.xDomain(series: hourly, style: .line, configuration: custom, now: date(0))
            == date(0)...date(7_200 + 7_200))
    }

    @Test("A series of one bar is laid out around that bar, whatever its interval, and the answer does not depend on the clock")
    func singleBarDomain() {
        for interval in [ChartInterval.minutes(1), .hours(1), .days(1)] {
            let bar = date(1_700_000_000)
            let single = ChartSeries(points: [point(1_700_000_000, 1)], interval: interval)
            let line = ViewportMath.xDomain(series: single, style: .line, configuration: config, now: date(0))
            #expect(line.contains(bar))
            #expect(line == bar...bar.addingTimeInterval(6 * interval.seconds))

            let one = ChartSeries(candles: [flatCandle(1_700_000_000, 1)], interval: interval)
            let candles = ViewportMath.xDomain(series: one, style: .candles, configuration: config, now: date(0))
            #expect(candles == bar.addingTimeInterval(-interval.seconds)...bar.addingTimeInterval(6 * interval.seconds))

            // The same whenever it is asked: it has nothing to do with the current time.
            #expect(ViewportMath.xDomain(series: single, style: .line, configuration: config, now: date(5_000_000_000)) == line)
        }
    }

    @Test("A series of one bar is never a domain of no width")
    func singleBarWithoutPadding() {
        let bare = ViewportConfiguration(trailingPaddingBars: 0, candleLeadingPaddingBars: 0)
        let single = ChartSeries(points: [point(600, 1)], interval: .minutes(5))
        let domain = ViewportMath.xDomain(series: single, style: .line, configuration: bare, now: date(0))
        #expect(domain.lowerBound == date(600))
        #expect(domain.upperBound == date(600 + 300))
    }

    @Test("A series without bars is the last minute up to the time it is given")
    func emptyDomain() {
        let domain = ViewportMath.xDomain(series: .empty(interval: minute), style: .line, configuration: config, now: date(10_000))
        #expect(domain == date(9_940)...date(10_000))
    }
}

@Suite("ViewportMath yDomain")
struct YDomainTests {
    private let points = tenPointSeries()
    private let candles = tenCandleSeries()

    private func yDomain(
        _ series: ChartSeries,
        style: SeriesStyle,
        window: ClosedRange<Date>,
        currentPrice: Double? = nil,
        upperBound: Date = date(10_000),
        additional: [ClosedRange<Double>] = []
    ) -> ClosedRange<Double> {
        ViewportMath.yDomain(
            series: series,
            style: style,
            visibleRange: window,
            currentPrice: currentPrice,
            xDomainUpperBound: upperBound,
            additionalRanges: additional,
            configuration: config
        )
    }

    @Test("Domain follows the visible window with 8% padding")
    func windowDomain() {
        // window t=120...300 -> values 11, 15, 14, 9 -> 9...15, padding 0.48
        let domain = yDomain(points, style: .line, window: date(120)...date(300))
        #expect(approximatelyEqual(domain, 8.52...15.48))
    }

    @Test("Candle style uses lows and highs")
    func candleWindowDomain() {
        // lows/highs of bars 2...5 -> 8...16, padding 0.64
        let domain = yDomain(candles, style: .candles, window: date(120)...date(300))
        #expect(approximatelyEqual(domain, 7.36...16.64))
    }

    @Test("Current price joins the domain when the x-domain end is inside the window")
    func currentPriceInsideWindow() {
        let window = date(120)...date(300)
        let domain = yDomain(points, style: .line, window: window, currentPrice: 20, upperBound: date(300))
        // 9...20, padding 0.88
        #expect(approximatelyEqual(domain, 8.12...20.88))
    }

    @Test("Current price is ignored when the x-domain end is outside the window")
    func currentPriceOutsideWindow() {
        let window = date(120)...date(300)
        let domain = yDomain(points, style: .line, window: window, currentPrice: 20, upperBound: date(301))
        #expect(approximatelyEqual(domain, 8.52...15.48))
        let domainBefore = yDomain(points, style: .line, window: window, currentPrice: 20, upperBound: date(119))
        #expect(approximatelyEqual(domainBefore, 8.52...15.48))
    }

    @Test("A current price inside the visible values does not change the domain")
    func currentPriceInsideValues() {
        let window = date(120)...date(300)
        let domain = yDomain(points, style: .line, window: window, currentPrice: 12, upperBound: date(200))
        #expect(approximatelyEqual(domain, 8.52...15.48))
    }

    @Test("A window without bars falls back to the whole series")
    func emptyWindowUsesWholeSeries() {
        // whole series 9...16, padding 0.56
        let domain = yDomain(points, style: .line, window: date(-5_000)...date(-1_000))
        #expect(approximatelyEqual(domain, 8.44...16.56))
        let afterDomain = yDomain(points, style: .line, window: date(5_000)...date(6_000))
        #expect(approximatelyEqual(afterDomain, 8.44...16.56))
    }

    @Test("The whole-series fallback includes the current price")
    func emptyWindowIncludesCurrentPrice() {
        // 9...30, span 21, padding 1.68
        let domain = yDomain(points, style: .line, window: date(5_000)...date(6_000), currentPrice: 30)
        #expect(approximatelyEqual(domain, 7.32...31.68))
    }

    @Test("A flat range is widened by 1% of its magnitude")
    func flatRange() {
        // a single bar with value 16 at t=420
        let single = yDomain(points, style: .line, window: date(420)...date(420))
        #expect(approximatelyEqual(single, 15.84...16.16))

        let hundred = ChartSeries(points: [point(0, 100)], interval: minute)
        #expect(approximatelyEqual(yDomain(hundred, style: .line, window: date(0)...date(60)), 99...101))

        let nearOne = ChartSeries(points: [point(0, 1)], interval: minute)
        #expect(approximatelyEqual(yDomain(nearOne, style: .line, window: date(0)...date(60)), 0.99...1.01))
    }

    @Test("A flat range at zero uses the absolute minimum margin")
    func flatRangeAtZero() {
        let zero = ChartSeries(points: [point(0, 0)], interval: minute)
        let domain = yDomain(zero, style: .line, window: date(0)...date(60))
        #expect(domain.lowerBound < 0 && domain.upperBound > 0)
        #expect(approximatelyEqual(domain, -1e-9...1e-9, tolerance: 1e-15))
    }

    @Test("Additional ranges extend the domain")
    func additionalRanges() {
        // window 9...15 united with 5...20 -> 5...20, padding 1.2
        let domain = yDomain(points, style: .line, window: date(120)...date(300), additional: [5...12, 14...20])
        #expect(approximatelyEqual(domain, 3.8...21.2))
    }

    @Test("Additional ranges inside the window leave it unchanged")
    func additionalRangesInside() {
        let domain = yDomain(points, style: .line, window: date(120)...date(300), additional: [10...12])
        #expect(approximatelyEqual(domain, 8.52...15.48))
    }

    @Test("An empty series without a price gives 0...1")
    func emptySeries() {
        let domain = yDomain(.empty(interval: minute), style: .line, window: date(0)...date(60))
        #expect(domain == 0...1)
    }

    @Test("An empty series with a current price is widened around it")
    func emptySeriesWithPrice() {
        let domain = yDomain(.empty(interval: minute), style: .line, window: date(0)...date(60), currentPrice: 50)
        #expect(approximatelyEqual(domain, 49.5...50.5))
    }

    private func extent(
        _ series: ChartSeries,
        style: SeriesStyle,
        window: ClosedRange<Date>,
        currentPrice: Double? = nil,
        upperBound: Date = date(10_000),
        additional: [ClosedRange<Double>] = []
    ) -> ClosedRange<Double>? {
        ViewportMath.yExtent(
            series: series,
            style: style,
            visibleRange: window,
            currentPrice: currentPrice,
            xDomainUpperBound: upperBound,
            additionalRanges: additional
        )
    }

    @Test("The extent is the data of the window, before padding")
    func windowExtent() {
        #expect(extent(points, style: .line, window: date(120)...date(300)) == 9...15)
        #expect(extent(candles, style: .candles, window: date(120)...date(300)) == 8...16)
    }

    @Test("The extent follows the rules of the domain: current price, additional ranges, whole series, no data")
    func extentRules() {
        let window = date(120)...date(300)
        // The price counts only with the live edge on screen.
        #expect(extent(points, style: .line, window: window, currentPrice: 20, upperBound: date(200)) == 9...20)
        #expect(extent(points, style: .line, window: window, currentPrice: 20, upperBound: date(301)) == 9...15)
        #expect(extent(points, style: .line, window: window, additional: [5...12, 14...20]) == 5...20)
        // A window without bars falls back to the whole series.
        let whole = extent(points, style: .line, window: date(5_000)...date(6_000))
        #expect(whole == extent(points, style: .line, window: date(0)...date(10_000)))
        #expect(extent(.empty(interval: minute), style: .line, window: window) == nil)
        #expect(extent(.empty(interval: minute), style: .line, window: window, currentPrice: 50) == 50...50)
    }

    @Test("The domain is the padded extent")
    func domainOfExtent() {
        let window = date(120)...date(300)
        for current in [nil, 12.0, 20.0] {
            let direct = yDomain(points, style: .line, window: window, currentPrice: current, upperBound: date(200))
            let viaExtent = ViewportMath.yDomain(
                for: extent(points, style: .line, window: window, currentPrice: current, upperBound: date(200)),
                configuration: config
            )
            #expect(direct == viaExtent)
        }
        #expect(approximatelyEqual(ViewportMath.yDomain(for: 9...15, configuration: config), 8.52...15.48))
        #expect(approximatelyEqual(ViewportMath.yDomain(for: 100...100, configuration: config), 99...101))
        #expect(ViewportMath.yDomain(for: nil, configuration: config) == 0...1)
    }

    @Test("Padding fraction comes from the configuration")
    func customPadding() {
        let custom = ViewportConfiguration(verticalPaddingFraction: 0.5)
        let domain = ViewportMath.yDomain(
            series: points,
            style: .line,
            visibleRange: date(120)...date(300),
            currentPrice: nil,
            xDomainUpperBound: date(10_000),
            additionalRanges: [],
            configuration: custom
        )
        // 9...15, padding 3
        #expect(approximatelyEqual(domain, 6...18))
    }
}

@Suite("ViewportMath zoom")
struct ZoomTests {
    private let start = date(1_000_000)
    private let last = date(2_000_000)

    private func zoom(
        scale: Double,
        anchor: ZoomAnchor,
        bars: Double = 60,
        lastTime: Date? = date(2_000_000),
        configuration: ViewportConfiguration = config
    ) -> (scrollPosition: Date, visibleBars: Double) {
        ViewportMath.zoomed(
            scrollPosition: start,
            visibleBars: bars,
            scale: scale,
            anchor: anchor,
            lastTime: lastTime,
            interval: minute,
            configuration: configuration
        )
    }

    @Test("Zooming in halves the window; the center stays in place")
    func zoomInCenter() {
        let result = zoom(scale: 2, anchor: .center)
        #expect(result.visibleBars == 30)
        // center before: start + 30 * 60; the window moves right by (60 - 30) / 2 bars = 900 s
        #expect(result.scrollPosition == start.addingTimeInterval(900))
    }

    @Test("Zooming out doubles the window; the center stays in place")
    func zoomOutCenter() {
        let result = zoom(scale: 0.5, anchor: .center)
        #expect(result.visibleBars == 120)
        #expect(result.scrollPosition == start.addingTimeInterval(-1_800))
    }

    @Test("Fraction anchors keep that point of the window fixed")
    func fractionAnchors() {
        let left = zoom(scale: 2, anchor: .fraction(0))
        #expect(left.visibleBars == 30)
        #expect(left.scrollPosition == start)

        let right = zoom(scale: 2, anchor: .fraction(1))
        #expect(right.scrollPosition == start.addingTimeInterval(1_800))

        let quarter = zoom(scale: 2, anchor: .fraction(0.25))
        #expect(quarter.scrollPosition == start.addingTimeInterval(450))
    }

    @Test("The anchored time maps to the same window fraction before and after")
    func anchorTimeIsInvariant() {
        for fraction in [0.0, 0.1, 0.5, 0.9, 1.0] {
            for scale in [0.4, 0.8, 1.5, 3.0] {
                let result = zoom(scale: scale, anchor: .fraction(fraction))
                let before = start.addingTimeInterval(fraction * 60 * 60)
                let after = result.scrollPosition.addingTimeInterval(fraction * result.visibleBars * 60)
                #expect(approximatelyEqual(before.timeIntervalSince(after), 0, tolerance: 1e-6))
            }
        }
    }

    @Test("Fractions outside 0...1 are clamped")
    func fractionClamped() {
        #expect(zoom(scale: 2, anchor: .fraction(-3)).scrollPosition == start)
        #expect(zoom(scale: 2, anchor: .fraction(7)).scrollPosition == start.addingTimeInterval(1_800))
    }

    @Test("The live-edge anchor places the last bar at the end anchor of the new width")
    func liveEdgeAnchor() {
        let result = zoom(scale: 2, anchor: .liveEdge)
        #expect(result.visibleBars == 30)
        // (6 - 30) * 60 = -1440
        #expect(result.scrollPosition == last.addingTimeInterval(-1_440))
    }

    @Test("The live-edge anchor without data keeps the scroll position")
    func liveEdgeWithoutData() {
        let result = zoom(scale: 2, anchor: .liveEdge, lastTime: nil)
        #expect(result.visibleBars == 30)
        #expect(result.scrollPosition == start)
    }

    @Test("The window width is clamped to the configured bounds")
    func clamping() {
        // 60 / 100 = 0.6 -> 10
        #expect(zoom(scale: 100, anchor: .center).visibleBars == 10)
        // 60 / 0.01 = 6000 -> 400
        #expect(zoom(scale: 0.01, anchor: .center).visibleBars == 400)

        let custom = ViewportConfiguration(minVisibleBars: 20, maxVisibleBars: 80)
        #expect(zoom(scale: 100, anchor: .center, configuration: custom).visibleBars == 20)
        #expect(zoom(scale: 0.01, anchor: .center, configuration: custom).visibleBars == 80)
    }

    @Test("A clamped zoom only moves the window by the width actually changed")
    func clampedShift() {
        // 60 -> 10 bars: shift = 0.5 * 50 * 60 = 1500
        #expect(zoom(scale: 100, anchor: .center).scrollPosition == start.addingTimeInterval(1_500))
        // Already at the limit: nothing changes.
        let atLimit = zoom(scale: 2, anchor: .center, bars: 10)
        #expect(atLimit.visibleBars == 10)
        #expect(atLimit.scrollPosition == start)
    }

    @Test("A scale of 1 keeps the window")
    func unitScale() {
        let result = zoom(scale: 1, anchor: .center)
        #expect(result.visibleBars == 60)
        #expect(result.scrollPosition == start)
    }

    @Test("Invalid scales leave the window unchanged", arguments: [0.0, -1.0, Double.nan, Double.infinity * -1])
    func invalidScale(_ scale: Double) {
        let result = zoom(scale: scale, anchor: .center)
        #expect(result.visibleBars == 60)
        #expect(result.scrollPosition == start)
    }
}

@Suite("ViewportMath candles")
struct CandleGeometryTests {
    @Test("Body width is plotWidth / visibleBars * factor")
    func bodyWidth() {
        // 400 / 40 * 0.78 = 7.8
        let width = ViewportMath.candleBodyWidth(plotWidth: 400, visibleBars: 40, factor: 0.78, min: 2, max: 32)
        #expect(abs(width - 7.8) < 1e-9)
    }

    @Test("Body width is clamped to min and max")
    func bodyWidthClamped() {
        // 4000 / 40 * 0.78 = 78 -> 32
        #expect(ViewportMath.candleBodyWidth(plotWidth: 4_000, visibleBars: 40, factor: 0.78, min: 2, max: 32) == 32)
        // 40 / 400 * 0.78 = 0.078 -> 2
        #expect(ViewportMath.candleBodyWidth(plotWidth: 40, visibleBars: 400, factor: 0.78, min: 2, max: 32) == 2)
    }

    @Test("Body width falls back to 4 while the plot has no size")
    func bodyWidthWithoutPlot() {
        #expect(ViewportMath.candleBodyWidth(plotWidth: 0, visibleBars: 40, factor: 0.78, min: 2, max: 32) == 4)
        #expect(ViewportMath.candleBodyWidth(plotWidth: -10, visibleBars: 40, factor: 0.78, min: 2, max: 32) == 4)
        #expect(ViewportMath.candleBodyWidth(plotWidth: 400, visibleBars: 0, factor: 0.78, min: 2, max: 32) == 4)
    }

    @Test("Body range spans open to close regardless of direction")
    func bodyRange() {
        let yDomain: ClosedRange<Double> = 0...100
        #expect(ViewportMath.candleBodyRange(candle(0, o: 10, h: 15, l: 8, c: 12), yDomain: yDomain) == 10...12)
        #expect(ViewportMath.candleBodyRange(candle(0, o: 12, h: 15, l: 8, c: 10), yDomain: yDomain) == 10...12)
    }

    @Test("A doji body is widened by 0.1% of the Y span on each side")
    func dojiBodyRange() {
        let range = ViewportMath.candleBodyRange(candle(0, o: 10, h: 12, l: 8, c: 10), yDomain: 0...100)
        #expect(approximatelyEqual(range, 9.9...10.1))

        let narrow = ViewportMath.candleBodyRange(candle(0, o: 50, h: 51, l: 49, c: 50), yDomain: 40...60)
        #expect(approximatelyEqual(narrow, 49.98...50.02))
    }
}
