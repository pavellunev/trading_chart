import Foundation
import TradingChartCore

/// A value of one indicator line or histogram bar at the crosshair position.
@available(iOS 17.0, *)
public struct CrosshairIndicatorValue: Hashable, Sendable {
    /// The ``ChartIndicator/id`` of the indicator the value belongs to.
    public var indicatorID: String
    /// Display name of the line or histogram.
    public var name: String
    /// The value at the snapped bar.
    public var value: Double
    /// The explicit colour of the line, or `nil` when the theme applies one (see ``paletteIndex`` and ``tone``).
    public var color: ChartColor?
    /// Position in the theme's indicator palette for a line without an explicit colour; the chart wraps it
    /// around the palette size. `nil` for histograms and for lines with an explicit colour.
    public var paletteIndex: Int?
    /// The tone of a histogram bar, which the theme maps to a colour. `nil` for lines.
    public var tone: HistogramTone?

    /// Creates an indicator value.
    public init(
        indicatorID: String,
        name: String,
        value: Double,
        color: ChartColor? = nil,
        paletteIndex: Int? = nil,
        tone: HistogramTone? = nil
    ) {
        self.indicatorID = indicatorID
        self.name = name
        self.value = value
        self.color = color
        self.paletteIndex = paletteIndex
        self.tone = tone
    }
}

/// The bar under the crosshair, snapped to the series.
@available(iOS 17.0, *)
public struct CrosshairState: Equatable, Sendable {
    /// Time of the snapped bar.
    public var time: Date
    /// The candle at that bar, or `nil` for a point series.
    public var candle: Candle?
    /// The price at that bar (the close).
    public var value: Double
    /// The close of the previous bar, when there is one.
    public var previousClose: Double?
    /// Values of the chart indicators at that bar.
    public var indicatorValues: [CrosshairIndicatorValue]

    /// Creates a crosshair state.
    public init(
        time: Date,
        candle: Candle? = nil,
        value: Double,
        previousClose: Double? = nil,
        indicatorValues: [CrosshairIndicatorValue] = []
    ) {
        self.time = time
        self.candle = candle
        self.value = value
        self.previousClose = previousClose
        self.indicatorValues = indicatorValues
    }
}

/// Notifications a ``TradingChartModel`` delivers through ``TradingChartModel/onEvent``.
@available(iOS 17.0, *)
public enum TradingChartEvent: Sendable {
    /// A drawing was added, changed or removed, or the selection changed.
    case drawing(DrawingEvent)
    /// The crosshair moved to another bar, or went away (`nil`).
    case crosshairChanged(CrosshairState?)
    /// The left edge of the window got within ``TradingChartConfiguration/historyPrefetchThreshold`` of the oldest loaded
    /// bar: a good moment to load more history and call ``TradingChartModel/prependHistory(_:)``.
    ///
    /// Sent only while ``TradingChartModel/hasMoreHistory`` is `true` and ``TradingChartModel/isLoadingHistory`` is `false`,
    /// and at most once until the series (a new series, older bars prepended) or one of those two flags changes.
    case approachedHistoryStart
    /// The window reached (`true`) or left (`false`) the live edge.
    case liveEdgeChanged(Bool)
}
