import CoreGraphics
import Foundation

/// A linear mapping between screen coordinates and chart data (time on X, price on Y).
///
/// Screen Y grows downwards, so `priceRange.upperBound` maps to `plotRect.minY`.
public struct ChartTransform: Sendable, Equatable {
    /// The plot area in screen coordinates.
    public var plotRect: CGRect
    /// The time range mapped onto `plotRect` horizontally.
    public var timeRange: ClosedRange<Date>
    /// The price range mapped onto `plotRect` vertically.
    public var priceRange: ClosedRange<Double>

    /// Creates a transform for the given plot area and data ranges.
    public init(plotRect: CGRect, timeRange: ClosedRange<Date>, priceRange: ClosedRange<Double>) {
        self.plotRect = plotRect
        self.timeRange = timeRange
        self.priceRange = priceRange
    }

    /// The screen X of `date`. Dates outside `timeRange` map outside `plotRect`.
    public func x(for date: Date) -> CGFloat {
        let span = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard span > 0 else { return plotRect.minX }
        let fraction = date.timeIntervalSince(timeRange.lowerBound) / span
        return plotRect.minX + CGFloat(fraction) * plotRect.width
    }

    /// The screen Y of `price`. Prices outside `priceRange` map outside `plotRect`.
    public func y(for price: Double) -> CGFloat {
        let span = priceRange.upperBound - priceRange.lowerBound
        guard span > 0 else { return plotRect.maxY }
        let fraction = (priceRange.upperBound - price) / span
        return plotRect.minY + CGFloat(fraction) * plotRect.height
    }

    /// The screen point of an anchor.
    public func point(for anchor: ChartAnchor) -> CGPoint {
        CGPoint(x: x(for: anchor.time), y: y(for: anchor.price))
    }

    /// The time at screen X `x` (inverse of ``x(for:)``).
    public func time(atX x: CGFloat) -> Date {
        let span = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard plotRect.width > 0 else { return timeRange.lowerBound }
        let fraction = Double((x - plotRect.minX) / plotRect.width)
        return timeRange.lowerBound.addingTimeInterval(fraction * span)
    }

    /// The price at screen Y `y` (inverse of ``y(for:)``).
    public func price(atY y: CGFloat) -> Double {
        let span = priceRange.upperBound - priceRange.lowerBound
        guard plotRect.height > 0 else { return priceRange.upperBound }
        let fraction = Double((y - plotRect.minY) / plotRect.height)
        return priceRange.upperBound - fraction * span
    }

    /// The chart anchor under a screen point.
    public func anchor(at point: CGPoint) -> ChartAnchor {
        ChartAnchor(time: time(atX: point.x), price: price(atY: point.y))
    }
}
