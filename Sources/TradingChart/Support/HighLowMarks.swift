import CoreGraphics
import Foundation
import TradingChartCore

/// The price of one extreme bar of the visible window.
@available(iOS 17.0, *)
struct WindowExtreme: Equatable {
    var time: Date
    var value: Double
}

/// The bars with the highest and the lowest price of the visible window.
@available(iOS 17.0, *)
struct WindowExtremes: Equatable {
    var high: WindowExtreme
    var low: WindowExtreme
}

/// Finds the extremes of the visible window for the high/low markers. Pure.
@available(iOS 17.0, *)
enum HighLowMarks {
    /// The highest and the lowest bar inside `range` (bounds inclusive): by candle high and low when `style` is
    /// `.candles` and the series has OHLC data, by value otherwise. The window is located by binary search, so the
    /// cost does not depend on the length of the series. `nil` when the window holds fewer than two bars.
    /// On a tie the earliest bar wins.
    static func extremes(
        in series: ChartSeries,
        style: SeriesStyle,
        range: ClosedRange<Date>
    ) -> WindowExtremes? {
        let indices = series.indexRange(in: range)
        guard indices.count >= 2 else { return nil }
        var high = WindowExtreme(time: .distantPast, value: -.infinity)
        var low = WindowExtreme(time: .distantPast, value: .infinity)
        if style == .candles, let candles = series.candles {
            for candle in candles[indices] {
                if candle.high > high.value { high = WindowExtreme(time: candle.time, value: candle.high) }
                if candle.low < low.value { low = WindowExtreme(time: candle.time, value: candle.low) }
            }
        } else {
            for point in series.points[indices] {
                if point.value > high.value { high = WindowExtreme(time: point.time, value: point.value) }
                if point.value < low.value { low = WindowExtreme(time: point.time, value: point.value) }
            }
        }
        guard high.value.isFinite, low.value.isFinite else { return nil }
        return WindowExtremes(high: high, low: low)
    }

    /// Whether the price label goes to the left of the short line: it does for a bar in the right half of the window,
    /// where there is more room on the left.
    static func labelGoesLeft(of time: Date, in range: ClosedRange<Date>) -> Bool {
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        guard duration > 0 else { return false }
        return time.timeIntervalSince(range.lowerBound) / duration > 0.5
    }
}

/// Where the mark of an extreme goes: a short line from the tip of the bar, and the price beyond its end. Pure.
///
/// The mark goes towards the side with more room (``HighLowMarks/labelGoesLeft(of:in:)``), unless something sits there that
/// it must not cover (the price badge, which reaches into the plot): then it goes to the other side, and when both sides are
/// taken it is left out. The decision is made on measured rectangles, in the coordinates of the plot.
@available(iOS 17.0, *)
enum ExtremeLabelLayout {
    /// The length of the short line.
    static let lineLength: CGFloat = 12
    /// The space between the end of the line and the text.
    static let gap: CGFloat = 2
    /// How close to an obstacle the mark may come.
    static let clearance: CGFloat = 2

    struct Placement: Equatable {
        /// Whether the mark goes to the left of the bar.
        var goesLeft: Bool
        /// The end of the short line, away from the bar.
        var lineEnd: CGPoint
        /// Where the text is: the rectangle it takes, centred on the height of the bar's tip.
        var labelRect: CGRect
        /// The line and the text together.
        var markRect: CGRect
    }

    /// The placement of a mark whose line starts at `point`, or `nil` when it has no room.
    ///
    /// - Parameters:
    ///   - point: The tip of the bar the mark points at.
    ///   - labelSize: The measured size of the text.
    ///   - prefersLeft: The side with more room.
    ///   - plot: The plot; a side on which the mark would stick out of it sideways is taken only when the other one is not free.
    ///   - obstacles: The rectangles the mark must keep ``clearance`` away from.
    static func place(
        at point: CGPoint,
        labelSize: CGSize,
        prefersLeft: Bool,
        plot: CGRect,
        avoiding obstacles: [CGRect]
    ) -> Placement? {
        let candidates = [prefersLeft, !prefersLeft].map { placement(at: point, labelSize: labelSize, goesLeft: $0) }
        let free = candidates.filter { candidate in
            obstacles.allSatisfy { !overlaps(candidate.markRect, $0.insetBy(dx: -clearance, dy: -clearance)) }
        }
        return free.first { $0.markRect.minX >= plot.minX && $0.markRect.maxX <= plot.maxX } ?? free.first
    }

    private static func placement(at point: CGPoint, labelSize: CGSize, goesLeft: Bool) -> Placement {
        let sign: CGFloat = goesLeft ? -1 : 1
        let lineEnd = CGPoint(x: point.x + sign * lineLength, y: point.y)
        let near = lineEnd.x + sign * gap
        let far = near + sign * labelSize.width
        let labelRect = CGRect(
            x: Swift.min(near, far),
            y: point.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        let markRect = labelRect.union(CGRect(x: Swift.min(point.x, lineEnd.x), y: point.y, width: lineLength, height: 0))
        return Placement(goesLeft: goesLeft, lineEnd: lineEnd, labelRect: labelRect, markRect: markRect)
    }

    /// Whether two rectangles share area (rectangles that only touch do not).
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }
}
