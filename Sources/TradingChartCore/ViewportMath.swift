import CoreGraphics
import Foundation

/// Pure geometry of the scrolling window, shared by the chart model and the chart view
/// so that both always agree on where the live edge is.
public enum ViewportMath {

    /// The window geometry for a window `visibleBars` bars wide: `configuration` with its right padding and
    /// live-edge tolerance adapted to the zoom level and to the price badge.
    ///
    /// - The right padding is `max(baseline, badgeBars)` in bars, where
    ///   `baseline = min(trailingPaddingBars, visibleBars * maxTrailingPaddingFraction)` and
    ///   `badgeBars = ceil((badgeOverhang + 6) / barWidth)` with `barWidth = plotWidth / visibleBars`
    ///   (6 points of clearance between the last bar and the badge). `badgeBars` counts only when `badgeOverhang`
    ///   is not `nil` and `plotWidth` is positive, and never exceeds half of the window.
    /// - The live-edge tolerance is `min(liveEdgeToleranceBars, visibleBars * 0.1)`.
    ///
    /// Hand the result to every other `ViewportMath` call, so that all of them agree on where the live edge is.
    ///
    /// - Parameters:
    ///   - configuration: The configured geometry to adapt.
    ///   - visibleBars: The window width in bars. A non-positive value returns `configuration` unchanged.
    ///   - plotWidth: The width of the visible plot in points; `0` while it is not measured.
    ///   - badgeOverhang: How far the price badge reaches into the plot, in points (the badge width minus the width
    ///     of the price axis column, at least `0`); `nil` when there is no badge to keep clear of.
    public static func effectiveConfiguration(
        _ configuration: ViewportConfiguration,
        visibleBars: Double,
        plotWidth: CGFloat,
        badgeOverhang: CGFloat?
    ) -> ViewportConfiguration {
        guard visibleBars > 0, visibleBars.isFinite else { return configuration }
        var effective = configuration
        let baseline = Swift.min(
            configuration.trailingPaddingBars,
            visibleBars * Swift.max(configuration.maxTrailingPaddingFraction, 0)
        )
        effective.trailingPaddingBars = baseline
        if let badgeOverhang, plotWidth > 0 {
            let barWidth = Double(plotWidth) / visibleBars
            let needed = ((Double(Swift.max(badgeOverhang, 0)) + badgeClearance) / barWidth).rounded(.up)
            effective.trailingPaddingBars = Swift.max(baseline, Swift.min(needed, visibleBars / 2))
        }
        effective.liveEdgeToleranceBars = Swift.min(
            configuration.liveEdgeToleranceBars,
            visibleBars * liveEdgeToleranceFraction
        )
        return effective
    }

    /// Points kept between the last bar and the price badge.
    private static let badgeClearance: Double = 6
    /// The largest share of the window the live-edge tolerance may take.
    private static let liveEdgeToleranceFraction: Double = 0.1

    /// The scroll position (left edge of the window) at which the last bar sits near the right edge.
    ///
    /// Equals `lastTime + (trailingPaddingBars - visibleBars) * interval.seconds`.
    public static func endAnchor(
        lastTime: Date,
        interval: ChartInterval,
        visibleBars: Double,
        configuration: ViewportConfiguration
    ) -> Date {
        lastTime.addingTimeInterval((configuration.trailingPaddingBars - visibleBars) * interval.seconds)
    }

    /// Whether the window is at the live edge: the scroll position is no further than
    /// `liveEdgeToleranceBars` before the end anchor. Always `true` when there is no data (`lastTime == nil`).
    public static func isAtLiveEdge(
        scrollPosition: Date,
        lastTime: Date?,
        interval: ChartInterval,
        visibleBars: Double,
        configuration: ViewportConfiguration
    ) -> Bool {
        guard let lastTime else { return true }
        let anchor = endAnchor(
            lastTime: lastTime,
            interval: interval,
            visibleBars: visibleBars,
            configuration: configuration
        )
        return scrollPosition >= anchor.addingTimeInterval(-configuration.liveEdgeToleranceBars * interval.seconds)
    }

    /// The scrollable X domain of a series.
    ///
    /// Runs from the first bar (minus `candleLeadingPaddingBars` for candle style) to the last bar plus
    /// `trailingPaddingBars`; a series of one bar is laid out the same way, around that bar, and is never narrower than one
    /// interval. A series without bars has no time of its own: its domain is the last minute up to `now`.
    ///
    /// Pure: the same arguments always give the same domain.
    ///
    /// - Parameters:
    ///   - series: The series.
    ///   - style: How it is drawn; candles get leading padding.
    ///   - configuration: The padding.
    ///   - now: The time an empty series is laid out around. Pass the current time for live data, or the position of the window.
    ///     A series with bars does not use it.
    public static func xDomain(
        series: ChartSeries,
        style: SeriesStyle,
        configuration: ViewportConfiguration,
        now: Date
    ) -> ClosedRange<Date> {
        guard let first = series.firstTime, let last = series.lastTime else {
            return now.addingTimeInterval(-60)...now
        }
        let bucketSeconds = series.interval.seconds
        let leading = style == .candles ? configuration.candleLeadingPaddingBars * bucketSeconds : 0
        let trailing = configuration.trailingPaddingBars * bucketSeconds
        let lower = first.addingTimeInterval(-leading)
        let upper = last.addingTimeInterval(trailing)
        return lower...Swift.max(upper, lower.addingTimeInterval(bucketSeconds))
    }

    /// The autoscaled Y domain for the visible window.
    ///
    /// - The domain covers the bars inside `visibleRange` (candle low/high for candle style) plus every
    ///   range in `additionalRanges` (e.g. overlay indicator values in the window).
    /// - `currentPrice` is included only when `xDomainUpperBound` lies inside `visibleRange`,
    ///   i.e. when the live edge is on screen.
    /// - A window without bars falls back to the extremes of the whole series, plus `currentPrice`.
    /// - The result is padded by `verticalPaddingFraction` of its span. A flat range (`lo == hi`) is widened
    ///   to `±max(|lo| * 0.01, 1e-9)` instead, so prices around 1.0 stay readable. With no data at all the result is `0...1`.
    ///
    /// Equals ``yDomain(for:configuration:)`` of ``yExtent(series:style:visibleRange:currentPrice:xDomainUpperBound:additionalRanges:)``.
    public static func yDomain(
        series: ChartSeries,
        style: SeriesStyle,
        visibleRange: ClosedRange<Date>,
        currentPrice: Double?,
        xDomainUpperBound: Date,
        additionalRanges: [ClosedRange<Double>],
        configuration: ViewportConfiguration
    ) -> ClosedRange<Double> {
        yDomain(
            for: yExtent(
                series: series,
                style: style,
                visibleRange: visibleRange,
                currentPrice: currentPrice,
                xDomainUpperBound: xDomainUpperBound,
                additionalRanges: additionalRanges
            ),
            configuration: configuration
        )
    }

    /// The range of values the Y axis has to show for the visible window, before padding: what
    /// ``yDomain(series:style:visibleRange:currentPrice:xDomainUpperBound:additionalRanges:configuration:)`` pads.
    ///
    /// Takes the same inputs and follows the same rules (window bars, `currentPrice` only with the live edge on screen,
    /// the whole series for a window without bars, `additionalRanges`). `nil` when there is no data at all.
    public static func yExtent(
        series: ChartSeries,
        style: SeriesStyle,
        visibleRange: ClosedRange<Date>,
        currentPrice: Double?,
        xDomainUpperBound: Date,
        additionalRanges: [ClosedRange<Double>]
    ) -> ClosedRange<Double>? {
        var extent = Extent()

        if let windowRange = series.valueRange(in: visibleRange, style: style) {
            extent.include(windowRange)
            if let currentPrice, visibleRange.contains(xDomainUpperBound) {
                extent.include(currentPrice)
            }
        } else {
            if let first = series.firstTime, let last = series.lastTime,
               let fullRange = series.valueRange(in: first...last, style: style) {
                extent.include(fullRange)
            }
            if let currentPrice {
                extent.include(currentPrice)
            }
        }
        for range in additionalRanges {
            extent.include(range)
        }

        guard let low = extent.low, let high = extent.high else { return nil }
        return low...high
    }

    /// The Y domain that shows `extent`: padded by `verticalPaddingFraction` of its span on both sides. A flat range is
    /// widened to `±max(|value| * 0.01, 1e-9)` instead; `nil` (no data), or an extent that is not finite, gives `0...1`.
    public static func yDomain(for extent: ClosedRange<Double>?, configuration: ViewportConfiguration) -> ClosedRange<Double> {
        guard let extent, extent.lowerBound.isFinite, extent.upperBound.isFinite else { return 0...1 }
        let low = extent.lowerBound
        let high = extent.upperBound
        guard low != high else {
            let margin = Swift.max(abs(low) * 0.01, 1e-9)
            return (low - margin)...(high + margin)
        }
        let padding = (high - low) * configuration.verticalPaddingFraction
        guard padding.isFinite else { return low...high }
        return (low - padding)...(high + padding)
    }

    /// The window after a zoom gesture.
    ///
    /// The new width is `visibleBars / scale` clamped to `minVisibleBars...maxVisibleBars`.
    /// With ``ZoomAnchor/liveEdge`` the last bar stays at the right edge (the scroll position becomes the end anchor
    /// for the new width, or stays unchanged when `lastTime` is `nil`); otherwise the time under the anchor
    /// fraction of the old window stays under the same fraction of the new one. A non-positive or non-finite `scale`
    /// leaves the window unchanged.
    public static func zoomed(
        scrollPosition: Date,
        visibleBars: Double,
        scale: Double,
        anchor: ZoomAnchor,
        lastTime: Date?,
        interval: ChartInterval,
        configuration: ViewportConfiguration
    ) -> (scrollPosition: Date, visibleBars: Double) {
        guard scale > 0, scale.isFinite else { return (scrollPosition, visibleBars) }
        let newBars = Swift.min(
            Swift.max(visibleBars / scale, configuration.minVisibleBars),
            configuration.maxVisibleBars
        )
        let fraction: Double
        switch anchor {
        case .liveEdge:
            guard let lastTime else { return (scrollPosition, newBars) }
            let position = endAnchor(
                lastTime: lastTime,
                interval: interval,
                visibleBars: newBars,
                configuration: configuration
            )
            return (position, newBars)
        case .center:
            fraction = 0.5
        case .fraction(let value):
            fraction = Swift.min(Swift.max(value, 0), 1)
        }
        let shift = fraction * (visibleBars - newBars) * interval.seconds
        return (scrollPosition.addingTimeInterval(shift), newBars)
    }

    /// The width of a candle body in points: the plot width divided by the visible bar count, times `factor`,
    /// clamped to `min...max`. Returns 4 while the plot width (or the bar count) is not positive.
    public static func candleBodyWidth(
        plotWidth: CGFloat,
        visibleBars: Double,
        factor: CGFloat,
        min: CGFloat,
        max: CGFloat
    ) -> CGFloat {
        guard plotWidth > 0, visibleBars > 0 else { return 4 }
        let perBar = plotWidth / CGFloat(visibleBars)
        return Swift.min(Swift.max(perBar * factor, min), max)
    }

    /// The price range a candle body should be drawn over.
    ///
    /// Normally `min(open, close)...max(open, close)`. A doji (`open == close`) would be invisible,
    /// so it is widened by `0.1%` of the Y domain span on each side. A candle whose open or close is not finite
    /// has no body: the range is empty (a single value) at the one that is, or at the lower end of `yDomain`.
    public static func candleBodyRange(_ candle: Candle, yDomain: ClosedRange<Double>) -> ClosedRange<Double> {
        guard candle.open.isFinite, candle.close.isFinite else {
            let value = [candle.open, candle.close, yDomain.lowerBound].first { $0.isFinite } ?? 0
            return value...value
        }
        let bodyLow = Swift.min(candle.open, candle.close)
        let bodyHigh = Swift.max(candle.open, candle.close)
        guard candle.open == candle.close else { return bodyLow...bodyHigh }
        let span = yDomain.upperBound - yDomain.lowerBound
        guard span.isFinite else { return bodyLow...bodyHigh }
        return (bodyLow - span * 0.001)...(bodyHigh + span * 0.001)
    }
}

private struct Extent {
    var low: Double?
    var high: Double?

    /// Adds a price. One that is not finite (`nan`, `inf`) is left out, so it cannot break the range.
    mutating func include(_ value: Double) {
        guard value.isFinite else { return }
        low = low.map { Swift.min($0, value) } ?? value
        high = high.map { Swift.max($0, value) } ?? value
    }

    mutating func include(_ range: ClosedRange<Double>) {
        include(range.lowerBound)
        include(range.upperBound)
    }
}
