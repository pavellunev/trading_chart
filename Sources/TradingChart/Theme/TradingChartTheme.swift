import SwiftUI
import UIKit

/// How consecutive points of a line or area are connected.
@available(iOS 17.0, *)
public enum SeriesInterpolation: Sendable {
    /// Straight segments.
    case linear
    /// A smooth Catmull-Rom spline.
    case catmullRom
    /// A smooth curve that never overshoots the data.
    case monotone
}

/// Colours, strokes and fonts of a chart. Inject one with the `tradingChartTheme(_:)` view modifier.
///
/// Start from ``standard`` (it adapts to light and dark appearance) and change what you need:
///
/// ```swift
/// var theme = TradingChartTheme.standard
/// theme.bullish = .mint
/// theme.lineInterpolation = .catmullRom
/// ```
@available(iOS 17.0, *)
public struct TradingChartTheme: Sendable {
    /// Colour of rising candles, buy markers and positive histogram bars.
    public var bullish: Color = .green
    /// Colour of falling candles, sell markers and negative histogram bars.
    public var bearish: Color = .red
    /// Colour of the line and area series.
    public var line: Color = .blue
    /// Opacity of the area gradient at the line.
    public var areaTopOpacity: Double = 0.28
    /// Opacity of the area gradient at the bottom.
    public var areaBottomOpacity: Double = 0.0
    /// Width of the series line.
    public var lineWidth: CGFloat = 2
    /// How the series line is interpolated.
    public var lineInterpolation: SeriesInterpolation = .linear

    /// Width of candle wicks.
    public var wickWidth: CGFloat = 1.5
    /// Share of a bar's width taken by the candle body; the rest is the gap between candles.
    public var candleBodyWidthFactor: CGFloat = 0.78
    /// Lower bound of the candle body width in points.
    public var minCandleBodyWidth: CGFloat = 2
    /// Upper bound of the candle body width in points.
    public var maxCandleBodyWidth: CGFloat = 32
    /// Corner radius of candle bodies.
    public var candleCornerRadius: CGFloat = 1

    /// Colour of grid lines.
    public var grid: Color = Color.secondary.opacity(0.25)
    /// Dash pattern of grid lines.
    public var gridDash: [CGFloat] = [3, 4]
    /// Colour of axis labels.
    public var axisLabel: Color = .secondary
    /// Font of axis labels.
    public var axisFont: Font = .system(size: 10)
    /// Fixed width of the price axis labels. Keeps the plots of all panes aligned horizontally.
    public var yAxisLabelWidth: CGFloat = 56

    /// Colour of the current price line; `nil` uses ``line`` at reduced opacity.
    public var currentPriceLine: Color?
    /// Dash pattern of the current price line.
    public var currentPriceLineDash: [CGFloat] = [4, 3]
    /// Background of the price badge; `nil` uses ``line``.
    public var priceBadgeBackground: Color?
    /// Text colour of the price badge.
    public var priceBadgeText: Color = .white
    /// Font of the price badge.
    public var priceBadgeFont: Font = .system(size: 12, weight: .semibold, design: .monospaced)

    /// Colour of the crosshair lines.
    public var crosshair: Color = Color.secondary
    /// Background of the crosshair labels.
    public var crosshairLabelBackground: Color = Color.primary
    /// Text colour of the crosshair labels.
    public var crosshairLabelText: Color = Color(uiColor: .systemBackground)
    /// Font of the legend rows above the panes and of the crosshair tooltip.
    public var legendFont: Font = .system(size: 11).monospacedDigit()
    /// Text colour of legend values that have no colour of their own.
    public var legendText: Color = .primary
    /// Text colour of legend items that carry no colour of their own: the title of an indicator with several values
    /// and the name of a volume.
    public var legendLabel: Color = .secondary
    /// Background of the crosshair tooltip with the values of the selected bar.
    public var tooltipBackground: Color = Color(uiColor: .systemBackground).opacity(0.94)
    /// Text colour of the crosshair tooltip.
    public var tooltipText: Color = .primary

    /// Font of the price labels of the highest and the lowest price of the visible window.
    public var extremeLabelFont: Font = .system(size: 10).monospacedDigit()
    /// Colour of those labels and of the short lines that point at the bars.
    public var extremeLabel: Color = .secondary

    /// Text colour of marker labels.
    public var markerText: Color = .white
    /// Colour of the ring around marker dots.
    public var markerBorder: Color = Color(uiColor: .systemBackground)
    /// Diameter of marker dots.
    public var markerSize: CGFloat = 9

    /// Colours assigned in order to indicator lines without an explicit colour.
    public var indicatorPalette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown]
    /// Default colour of drawings.
    public var drawingDefault: Color = .indigo
    /// Colour of the handles of a selected drawing.
    public var drawingHandle: Color = .primary
    /// Colour of the separator between panes.
    public var paneSeparator: Color = Color.secondary.opacity(0.3)

    /// Font of the labels of ``IndicatorBar``. A selected label is drawn semibold.
    public var indicatorBarFont: Font = .system(size: 13)
    /// Space between the labels of ``IndicatorBar``, in points.
    public var indicatorBarSpacing: CGFloat = 14
    /// Height of the row of ``IndicatorBar``, in points. The whole height of a label is its tap target.
    public var indicatorBarHeight: CGFloat = 30
    /// Text colour of a selected indicator in ``IndicatorBar``.
    public var indicatorBarSelected: Color = .primary
    /// Text colour of an indicator that is switched off in ``IndicatorBar``.
    public var indicatorBarUnselected: Color = .secondary
    /// Colour of the divider between the overlay group and the pane group of ``IndicatorBar``.
    public var indicatorBarDivider: Color = Color.secondary.opacity(0.4)

    /// Creates the standard theme.
    public init() {}

    /// The standard theme built from adaptive system colours.
    public static let standard = TradingChartTheme()
}
