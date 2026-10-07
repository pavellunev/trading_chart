import CoreGraphics
import Foundation
import TradingChartCore

/// How close to the oldest loaded bar the window may get before ``TradingChartEvent/approachedHistoryStart`` fires.
@available(iOS 17.0, *)
public enum HistoryPrefetchThreshold: Sendable, Hashable {
    /// A fixed number of bars between the left edge of the window and the first bar.
    case bars(Double)
    /// A number of window widths: scales with the zoom level, so a wider window asks for history earlier.
    case visibleWindows(Double)

    /// The threshold as a time span for a series with bars of `interval` and a window `visibleDuration` seconds wide.
    func duration(interval: ChartInterval, visibleDuration: TimeInterval) -> TimeInterval {
        switch self {
        case .bars(let bars): bars * interval.seconds
        case .visibleWindows(let windows): windows * visibleDuration
        }
    }
}

/// Behaviour and layout options of a ``TradingChartModel``.
@available(iOS 17.0, *)
public struct TradingChartConfiguration: Sendable {
    /// Geometry of the scrolling window.
    public var viewport: ViewportConfiguration
    /// Upper bound for the number of bars kept when live updates append new bars; `nil` keeps everything.
    ///
    /// A live update never trims the bars the user is looking at or has just scrolled past: bars newer than
    /// `visibleTimeRange.lowerBound - renderBufferWindows * visibleDuration` are always kept, so the series may
    /// exceed this bound while the window is away from the live edge (for example after history was prepended).
    /// At the live edge the bound applies as usual. Bars that were trimmed can be loaded again through history paging.
    public var maxLiveBarCount: Int?
    /// Shows the dashed horizontal line at the current price.
    public var showsCurrentPriceLine: Bool
    /// Shows the current price badge at the right edge of the plot.
    public var showsPriceBadge: Bool
    /// Shows the legend row above every pane with the values of the last or the selected bar, and the tooltip
    /// with the values of the selected bar while the crosshair is active.
    public var showsLegend: Bool
    /// Marks the highest and the lowest price of the visible window with a short line and a price label.
    public var showsHighLowMarkers: Bool
    /// Enables the crosshair interaction.
    public var isCrosshairEnabled: Bool
    /// Enables pinch zoom.
    public var isZoomEnabled: Bool
    /// Enables the drawing tools.
    public var isDrawingEnabled: Bool
    /// Enables haptic feedback of the interactions.
    public var isHapticsEnabled: Bool
    /// The style picker on the chart: a small icon in the legend row of the main pane that opens a menu of styles
    /// (``SeriesStylePicker``). `nil`, the default, shows none.
    public var stylePicker: StylePickerOptions?
    /// What the chart remembers between launches: the style, the indicators and, with a key, the drawings (see
    /// ``ChartPersistence``). `nil`, the default, saves and restores nothing.
    ///
    /// A model created with it restores before its first frame. Set later, it restores what is saved and keeps the rest as
    /// it is: to start with defaults of your own on the first launch, set them first and set this afterwards.
    public var persistence: ChartPersistence?
    /// Height of every indicator pane below the main chart.
    public var paneHeight: CGFloat
    /// Preferred number of labels on the price axis.
    public var yAxisDesiredCount: Int
    /// How close to the first bar the left edge of the window may get before ``TradingChartEvent/approachedHistoryStart``
    /// fires. The default is one window width, so a fast fling does not reach the edge before the data arrives.
    public var historyPrefetchThreshold: HistoryPrefetchThreshold
    /// How many bars of empty time the chart keeps before the oldest loaded bar while the source has more history
    /// (``TradingChartModel/hasMoreHistory``).
    ///
    /// The time domain of the charts does not move when history is prepended or the head of the series is trimmed, as long as
    /// the oldest bar stays inside this reserve: a domain that moves makes the charts blank for a frame. The reserve is not
    /// scrollable; it only has to be longer than the history loaded between two replacements of the series.
    public var historyReserveBars: Int
    /// Marks are rendered only within this many window widths on each side of the visible window.
    ///
    /// Building the marks is the expensive part of scrolling, so the range they are built for moves rarely: while the
    /// visible window stays clear of its edges nothing is rebuilt, and when it nears one (or has left it) the range is
    /// moved at once, in the same update, so the marks always cover the visible window. During a fling the range is built
    /// wider (up to twice this buffer) and reaches further ahead of the motion than behind it. A larger buffer means
    /// fewer rebuilds of more marks; `0` rebuilds the marks on every scroll step.
    public var renderBufferWindows: Double

    /// Creates a configuration; every parameter has a sensible default.
    public init(
        viewport: ViewportConfiguration = ViewportConfiguration(),
        maxLiveBarCount: Int? = 600,
        showsCurrentPriceLine: Bool = true,
        showsPriceBadge: Bool = true,
        showsLegend: Bool = true,
        showsHighLowMarkers: Bool = true,
        isCrosshairEnabled: Bool = true,
        isZoomEnabled: Bool = true,
        isDrawingEnabled: Bool = true,
        isHapticsEnabled: Bool = true,
        paneHeight: CGFloat = 90,
        yAxisDesiredCount: Int = 5,
        historyPrefetchThreshold: HistoryPrefetchThreshold = .visibleWindows(1),
        renderBufferWindows: Double = 1,
        historyReserveBars: Int = 1_000,
        stylePicker: StylePickerOptions? = nil,
        persistence: ChartPersistence? = nil
    ) {
        self.viewport = viewport
        self.maxLiveBarCount = maxLiveBarCount
        self.showsCurrentPriceLine = showsCurrentPriceLine
        self.showsPriceBadge = showsPriceBadge
        self.showsLegend = showsLegend
        self.showsHighLowMarkers = showsHighLowMarkers
        self.isCrosshairEnabled = isCrosshairEnabled
        self.isZoomEnabled = isZoomEnabled
        self.isDrawingEnabled = isDrawingEnabled
        self.isHapticsEnabled = isHapticsEnabled
        self.paneHeight = paneHeight
        self.yAxisDesiredCount = yAxisDesiredCount
        self.historyPrefetchThreshold = historyPrefetchThreshold
        self.renderBufferWindows = renderBufferWindows
        self.historyReserveBars = historyReserveBars
        self.stylePicker = stylePicker
        self.persistence = persistence
    }
}
