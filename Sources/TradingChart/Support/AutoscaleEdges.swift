import Foundation
import TradingChartCore

/// What the plot shows at the two edges of the window that the points inside the window do not tell. Pure.
///
/// The autoscale has to hold everything that is drawn inside the plot, or it is cut off at the plot's edge (a candle that flies
/// off the top). Points whose time is inside the window are one part of it. The others are at the edges: a line (or the edge
/// of a band) runs in from the point outside the window, so its value at the edge is between the two points that straddle the
/// edge; and a candle body or a histogram bar whose centre is just outside the window is half in view.
///
/// A value that is not finite (an indicator of the host may produce one) adds nothing: a range cannot be built from it.
@available(iOS 17.0, *)
enum AutoscaleEdges {

    /// The values, drawn at the edges of `window` and not told by the points inside it, of the series and of overlay
    /// indicators.
    ///
    /// - Parameters:
    ///   - margin: How far outside the window the centre of a bar can be and the bar still shows: half the width of its body.
    ///   - wickMargin: The same for the wick (half its width): a bar this close shows its whole wick, from the low to the high.
    ///   - slack: How far outside of the window a line is followed: the chart can trail the window by a pixel or two.
    static func ranges(
        series: ChartSeries,
        style: SeriesStyle,
        overlays: [IndicatorOutput],
        window: ClosedRange<Date>,
        margin: TimeInterval,
        wickMargin: TimeInterval,
        slack: TimeInterval = 0
    ) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        if style == .candles, let candles = series.candles {
            let lower = candles.partitionPoint { $0.time >= window.lowerBound }
            let upper = candles.partitionPoint { $0.time > window.upperBound }
            if lower > 0 {
                let candle = candles[lower - 1]
                let distance = window.lowerBound.timeIntervalSince(candle.time)
                if distance <= wickMargin {
                    add(candle.low, candle.high, to: &result)
                } else if distance <= margin {
                    add(candle.open, candle.close, to: &result)
                }
            }
            if upper < candles.count {
                let candle = candles[upper]
                let distance = candle.time.timeIntervalSince(window.upperBound)
                if distance <= wickMargin {
                    add(candle.low, candle.high, to: &result)
                } else if distance <= margin {
                    add(candle.open, candle.close, to: &result)
                }
            }
        } else {
            let points = series.points
            result += edgeValues(points.map { ($0.time, $0.value) }, window: window, slack: slack)
        }
        for output in overlays {
            result += lineAndBandRanges(of: output, window: window, slack: slack)
        }
        return result
    }

    /// The same for an indicator pane: the lines and bands, and the histogram bars that are half in view.
    static func paneRanges(
        of output: IndicatorOutput,
        window: ClosedRange<Date>,
        margin: TimeInterval,
        slack: TimeInterval = 0
    ) -> [ClosedRange<Double>] {
        var result = lineAndBandRanges(of: output, window: window, slack: slack)
        for histogram in output.histograms {
            let bars = histogram.bars
            let lower = bars.partitionPoint { $0.time >= window.lowerBound }
            let upper = bars.partitionPoint { $0.time > window.upperBound }
            if lower > 0, window.lowerBound.timeIntervalSince(bars[lower - 1].time) <= margin {
                add(histogram.baseline, bars[lower - 1].value, to: &result)
            }
            if upper < bars.count, bars[upper].time.timeIntervalSince(window.upperBound) <= margin {
                add(histogram.baseline, bars[upper].value, to: &result)
            }
        }
        return result
    }

    private static func lineAndBandRanges(
        of output: IndicatorOutput,
        window: ClosedRange<Date>,
        slack: TimeInterval
    ) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        for line in output.lines {
            result += edgeValues(line.values.map { ($0.time, $0.value) }, window: window, slack: slack)
        }
        for band in output.bands {
            result += edgeValues(band.upper.map { ($0.time, $0.value) }, window: window, slack: slack)
            result += edgeValues(band.lower.map { ($0.time, $0.value) }, window: window, slack: slack)
        }
        return result
    }

    /// What the polyline `points` (oldest first) shows outside of `window`, up to `slack` beyond each edge: its points there,
    /// and its value at the edge of that stretch where it falls between two points.
    private static func edgeValues(
        _ points: [(time: Date, value: Double)],
        window: ClosedRange<Date>,
        slack: TimeInterval
    ) -> [ClosedRange<Double>] {
        let extended = window.lowerBound.addingTimeInterval(-slack)...window.upperBound.addingTimeInterval(slack)
        var result: [ClosedRange<Double>] = []
        if slack > 0 {
            let lower = points.partitionPoint { $0.time >= extended.lowerBound }
            let upper = points.partitionPoint { $0.time > extended.upperBound }
            for point in points[lower..<Swift.max(lower, upper)] where !window.contains(point.time) {
                add(point.value, point.value, to: &result)
            }
        }
        for edge in [extended.lowerBound, extended.upperBound] {
            let next = points.partitionPoint { $0.time >= edge }
            guard next > 0, next < points.count, points[next].time > edge else { continue }
            let before = points[next - 1]
            let after = points[next]
            let span = after.time.timeIntervalSince(before.time)
            guard span > 0 else { continue }
            let fraction = edge.timeIntervalSince(before.time) / span
            let value = before.value + (after.value - before.value) * fraction
            add(value, value, to: &result)
        }
        return result
    }

    /// Adds the range between two values, in either order: nothing when one of them is not finite (a range with a bound that is `nan`
    /// cannot be made, it traps).
    private static func add(_ first: Double, _ second: Double, to result: inout [ClosedRange<Double>]) {
        guard first.isFinite, second.isFinite else { return }
        result.append(Swift.min(first, second)...Swift.max(first, second))
    }
}
