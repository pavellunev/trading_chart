/// Tunable geometry of the scrolling window of a chart. All distances are measured in bars.
public struct ViewportConfiguration: Sendable, Hashable {
    /// Number of bars visible at once for line and area series.
    public var visibleBars: Double
    /// Number of bars visible at once for candle series (narrower so candle bodies stay readable).
    public var candleVisibleBars: Double
    /// Lower bound of the zoomed window width.
    public var minVisibleBars: Double
    /// Upper bound of the zoomed window width.
    public var maxVisibleBars: Double
    /// Gap between the last bar and the right edge of the window at the live edge.
    ///
    /// A zoomed-in window gets less: the gap never exceeds ``maxTrailingPaddingFraction`` of the window.
    public var trailingPaddingBars: Double
    /// The largest share of the window the gap at the live edge may take, so a zoomed-in window is not mostly empty space.
    ///
    /// The baseline gap of a window `visibleBars` wide is `min(trailingPaddingBars, visibleBars * maxTrailingPaddingFraction)`;
    /// see ``ViewportMath/effectiveConfiguration(_:visibleBars:plotWidth:badgeOverhang:)``.
    public var maxTrailingPaddingFraction: Double
    /// How far from the live edge the window may be and still count as "at the live edge".
    ///
    /// A zoomed-in window gets less: the tolerance never exceeds a tenth of the window.
    public var liveEdgeToleranceBars: Double
    /// Extra space before the first candle so it is not clipped by the left edge of the domain.
    public var candleLeadingPaddingBars: Double
    /// Fraction of the visible price span added above and below when autoscaling the Y domain.
    public var verticalPaddingFraction: Double

    /// Creates a configuration; every parameter has a default.
    public init(
        visibleBars: Double = 60,
        candleVisibleBars: Double = 40,
        minVisibleBars: Double = 10,
        maxVisibleBars: Double = 400,
        trailingPaddingBars: Double = 6,
        maxTrailingPaddingFraction: Double = 0.2,
        liveEdgeToleranceBars: Double = 2,
        candleLeadingPaddingBars: Double = 1,
        verticalPaddingFraction: Double = 0.08
    ) {
        self.visibleBars = visibleBars
        self.candleVisibleBars = candleVisibleBars
        self.minVisibleBars = minVisibleBars
        self.maxVisibleBars = maxVisibleBars
        self.trailingPaddingBars = trailingPaddingBars
        self.maxTrailingPaddingFraction = maxTrailingPaddingFraction
        self.liveEdgeToleranceBars = liveEdgeToleranceBars
        self.candleLeadingPaddingBars = candleLeadingPaddingBars
        self.verticalPaddingFraction = verticalPaddingFraction
    }

    /// The default window width for a style: ``candleVisibleBars`` for candles, ``visibleBars`` otherwise.
    public func defaultVisibleBars(for style: SeriesStyle) -> Double {
        style == .candles ? candleVisibleBars : visibleBars
    }
}

/// The point of the window that stays fixed while zooming.
public enum ZoomAnchor: Sendable, Hashable {
    /// Keep the last bar at the right edge of the window.
    case liveEdge
    /// Keep the middle of the window in place.
    case center
    /// Keep the given fraction of the window in place: `0` is the left edge, `1` is the right edge.
    case fraction(Double)
}
