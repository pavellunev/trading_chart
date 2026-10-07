import SwiftUI
import TradingChartCore

/// A line of an indicator, culled to the render window and with its colour resolved.
@available(iOS 17.0, *)
struct IndicatorLineItem: Identifiable {
    var id: String
    var color: Color
    var width: CGFloat
    var dash: [CGFloat]
    var values: ArraySlice<IndicatorValue>
}

/// One point of a filled band.
@available(iOS 17.0, *)
struct BandPoint: Equatable {
    var time: Date
    var upper: Double
    var lower: Double
}

/// A band of an indicator, culled to the render window and with its colour resolved.
@available(iOS 17.0, *)
struct IndicatorBandItem: Identifiable {
    var id: String
    var color: Color
    var opacity: Double
    var points: [BandPoint]
}

/// A histogram of an indicator, culled to the render window.
@available(iOS 17.0, *)
struct IndicatorHistogramItem: Identifiable {
    var id: String
    var baseline: Double
    var bars: ArraySlice<HistogramBar>
}

/// Culling and scaling helpers shared by the main pane and the indicator panes. Pure functions.
@available(iOS 17.0, *)
enum IndicatorRendering {

    /// The values whose time falls into `range` (bounds inclusive), found by binary search.
    static func slice(_ values: [IndicatorValue], in range: ClosedRange<Date>) -> ArraySlice<IndicatorValue> {
        let lower = values.partitionPoint { $0.time >= range.lowerBound }
        let upper = values.partitionPoint { $0.time > range.upperBound }
        return values[lower..<Swift.max(lower, upper)]
    }

    /// The histogram bars whose time falls into `range` (bounds inclusive), found by binary search.
    static func slice(_ bars: [HistogramBar], in range: ClosedRange<Date>) -> ArraySlice<HistogramBar> {
        let lower = bars.partitionPoint { $0.time >= range.lowerBound }
        let upper = bars.partitionPoint { $0.time > range.upperBound }
        return bars[lower..<Swift.max(lower, upper)]
    }

    /// The value whose time is exactly `time`, or `nil`.
    static func value(in values: [IndicatorValue], at time: Date) -> Double? {
        let index = values.partitionPoint { $0.time >= time }
        guard index < values.count, values[index].time == time else { return nil }
        return values[index].value
    }

    /// The histogram bar whose time is exactly `time`, or `nil`.
    static func bar(in bars: [HistogramBar], at time: Date) -> HistogramBar? {
        let index = bars.partitionPoint { $0.time >= time }
        guard index < bars.count, bars[index].time == time else { return nil }
        return bars[index]
    }

    /// The points where both edges of a band are defined, inside `range`, merged by time.
    static func bandPoints(upper: [IndicatorValue], lower: [IndicatorValue], in range: ClosedRange<Date>) -> [BandPoint] {
        let uppers = slice(upper, in: range)
        let lowers = slice(lower, in: range)
        var points: [BandPoint] = []
        points.reserveCapacity(Swift.min(uppers.count, lowers.count))
        var u = uppers.startIndex
        var l = lowers.startIndex
        while u < uppers.endIndex, l < lowers.endIndex {
            if uppers[u].time == lowers[l].time {
                points.append(BandPoint(time: uppers[u].time, upper: uppers[u].value, lower: lowers[l].value))
                u += 1
                l += 1
            } else if uppers[u].time < lowers[l].time {
                u += 1
            } else {
                l += 1
            }
        }
        return points
    }

    /// The text of a Y label of an indicator pane. The values are not prices (a volume, a MACD line), so they use
    /// ``PriceFormatter/Context/compact`` (`3K`, not a `3.000` that a locale with a dot as the group separator
    /// reads as three). A pane with a fixed range (the RSI) shows whole numbers.
    static func paneAxisLabel(_ value: Double, hasFixedRange: Bool, formatter: PriceFormatter) -> String {
        formatter.format(hasFixedRange ? value.rounded() : value, context: .compact)
    }

    /// The range an indicator pane has to show, before padding: a `fixedRange`, or else the plotted values inside
    /// `visibleRange` (histograms contribute their baseline) together with the reference levels. `nil` when the window
    /// holds no values.
    ///
    /// With an `edgeMargin` it also holds what is drawn at the edges of the window without a point inside it (see
    /// ``AutoscaleEdges``): the value of a line where it crosses an edge, a bar whose centre is up to `edgeMargin` outside.
    static func paneYExtent(
        output: IndicatorOutput,
        visibleRange: ClosedRange<Date>,
        edgeMargin: TimeInterval? = nil,
        edgeSlack: TimeInterval = 0
    ) -> ClosedRange<Double>? {
        if let fixed = output.fixedRange, fixed.lowerBound.isFinite, fixed.upperBound.isFinite { return fixed }
        let edges = edgeMargin.map {
            AutoscaleEdges.paneRanges(of: output, window: visibleRange, margin: $0, slack: edgeSlack)
        } ?? []
        guard var range = output.valueRange(in: visibleRange) ?? edges.first else { return nil }
        for edge in edges {
            range = Swift.min(range.lowerBound, edge.lowerBound)...Swift.max(range.upperBound, edge.upperBound)
        }
        for level in output.levels where level.value.isFinite {
            range = Swift.min(range.lowerBound, level.value)...Swift.max(range.upperBound, level.value)
        }
        return range
    }

    /// The Y domain that shows `extent` of an indicator pane: widened by `paddingFraction` of the span on both sides.
    /// Padding a fixed range as well keeps the labels of its end ticks (`0` and `100` of the RSI) inside the pane
    /// instead of over the neighbouring one. A flat range is opened to `±max(|value| * 0.01, 1e-9)`;
    /// with nothing in the window (`nil`) the domain is `0...1`.
    static func paneYDomain(extent: ClosedRange<Double>?, paddingFraction: Double) -> ClosedRange<Double> {
        guard let extent, extent.lowerBound.isFinite, extent.upperBound.isFinite else { return 0...1 }
        var low = extent.lowerBound
        var high = extent.upperBound
        if low == high {
            let pad = Swift.max(abs(low) * 0.01, 1e-9)
            return (low - pad)...(high + pad)
        }
        let pad = (high - low) * Swift.max(paddingFraction, 0)
        guard pad.isFinite else { return low...high }
        low -= pad
        high += pad
        return low...high
    }

    /// The Y domain of an indicator pane for a window: ``paneYDomain(extent:paddingFraction:)`` of
    /// ``paneYExtent(output:visibleRange:)``.
    static func paneYDomain(
        output: IndicatorOutput,
        visibleRange: ClosedRange<Date>,
        paddingFraction: Double,
        edgeMargin: TimeInterval? = nil,
        edgeSlack: TimeInterval = 0
    ) -> ClosedRange<Double> {
        paneYDomain(
            extent: paneYExtent(output: output, visibleRange: visibleRange, edgeMargin: edgeMargin, edgeSlack: edgeSlack),
            paddingFraction: paddingFraction
        )
    }

}
