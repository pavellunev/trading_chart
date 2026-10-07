import Foundation

extension ChartDomain {
    /// Clips the segment from `first` to `second` to this rectangle of data space (Liang–Barsky).
    ///
    /// The result is the part of the segment inside the domain, the bounds included, in the original direction; an end that
    /// already lies inside is returned unchanged. `nil` when no part of the segment is inside the domain, or when an
    /// anchor is not a finite number. A segment of zero length is kept (unchanged) if its point is inside.
    ///
    /// The UI clips the shapes of the drawings to the window it shows, so that far-off ends (a ray to the edge of a long
    /// series) never reach the renderer.
    public func clip(_ first: ChartAnchor, _ second: ChartAnchor) -> (ChartAnchor, ChartAnchor)? {
        let x0 = first.time.timeIntervalSince(x.lowerBound)
        let x1 = second.time.timeIntervalSince(x.lowerBound)
        let y0 = first.price
        let y1 = second.price
        guard x0.isFinite, x1.isFinite, y0.isFinite, y1.isFinite else { return nil }
        let width = x.upperBound.timeIntervalSince(x.lowerBound)

        let dx = x1 - x0
        let dy = y1 - y0
        var entering = 0.0
        var leaving = 1.0
        // For every edge: p is the rate at which the segment moves towards the outside, q the distance to that edge.
        let edges: [(p: Double, q: Double)] = [
            (-dx, x0),
            (dx, width - x0),
            (-dy, y0 - y.lowerBound),
            (dy, y.upperBound - y0),
        ]
        for edge in edges {
            if edge.p == 0 {
                if edge.q < 0 { return nil }
            } else {
                let t = edge.q / edge.p
                if edge.p < 0 {
                    entering = Swift.max(entering, t)
                } else {
                    leaving = Swift.min(leaving, t)
                }
            }
        }
        guard entering <= leaving else { return nil }

        let start = entering == 0 ? first : point(of: first, second, at: entering)
        let end = leaving == 1 ? second : point(of: first, second, at: leaving)
        return (start, end)
    }

    private func point(of first: ChartAnchor, _ second: ChartAnchor, at t: Double) -> ChartAnchor {
        let seconds = second.time.timeIntervalSince(first.time)
        return ChartAnchor(
            time: first.time.addingTimeInterval(seconds * t),
            price: first.price + (second.price - first.price) * t
        )
    }
}

extension DrawingPrimitive {
    /// The part of the shape inside `domain`, or `nil` when none of it is.
    ///
    /// A segment is clipped to the rectangle (see ``ChartDomain/clip(_:_:)``); a horizontal line is kept only when its
    /// price is within the Y range of the domain, a vertical line only when its time is within the X range.
    public func clipped(to domain: ChartDomain) -> DrawingPrimitive? {
        switch self {
        case .segment(let first, let second):
            guard let (start, end) = domain.clip(first, second) else { return nil }
            return .segment(start, end)
        case .horizontalLine(let price):
            return domain.y.contains(price) ? self : nil
        case .verticalLine(let time):
            return domain.x.contains(time) ? self : nil
        }
    }
}
