import Foundation
import TradingChartCore

@available(iOS 17.0, *)
extension RandomAccessCollection where Index == Int {
    /// The first index whose element satisfies `isPastBoundary` (binary search over a partitioned collection).
    func partitionPoint(where isPastBoundary: (Element) -> Bool) -> Int {
        var low = startIndex
        var high = endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if isPastBoundary(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}

@available(iOS 17.0, *)
extension ChartSeries {
    /// Indices of the bars whose time falls into `range` (bounds inclusive), found by binary search.
    func indexRange(in range: ClosedRange<Date>) -> Range<Int> {
        let lower = points.partitionPoint { $0.time >= range.lowerBound }
        let upper = points.partitionPoint { $0.time > range.upperBound }
        return lower..<Swift.max(lower, upper)
    }
}

@available(iOS 17.0, *)
extension TradingChartModel {
    /// The time range in which marks are actually rendered: the visible window extended on both sides
    /// by `renderBufferWindows` window widths.
    var renderTimeRange: ClosedRange<Date> {
        let visible = visibleTimeRange
        let buffer = Swift.max(configuration.renderBufferWindows, 0) * visibleDuration
        return visible.lowerBound.addingTimeInterval(-buffer)...visible.upperBound.addingTimeInterval(buffer)
    }
}
