import Foundation

/// How far the dashed current price line reaches. Pure.
@available(iOS 17.0, *)
enum PriceLine {
    enum Span: Equatable {
        /// The price is outside the visible price range: nothing to draw (a mark outside the plot would not be clipped).
        case hidden
        /// From the newest bar to the end of the x domain, where the price badge sits.
        case fromLastBar(Date)
        /// Across the whole window: the newest bar is to the right of it.
        case fullWidth
    }

    /// The span of the line for a window `visibleRange` that shows prices `yDomain`.
    /// A series without bars gets a full-width line.
    static func span(
        lastTime: Date?,
        visibleRange: ClosedRange<Date>,
        price: Double,
        yDomain: ClosedRange<Double>
    ) -> Span {
        guard yDomain.contains(price) else { return .hidden }
        guard let lastTime, lastTime <= visibleRange.upperBound else { return .fullWidth }
        return .fromLastBar(lastTime)
    }
}
