import CoreGraphics
import Foundation

/// Describes how one kind of drawing turns anchors into shapes.
public protocol DrawingTool: Sendable {
    /// The drawing kind this tool renders.
    var kind: DrawingKind { get }
    /// How many anchors the user places to create the drawing.
    var requiredAnchorCount: Int { get }
    /// The shapes for the given anchors. Returns an empty array when there are too few anchors to draw anything.
    func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive]
    /// Finds what lies under `point` (screen coordinates): an anchor, the body of the drawing, or nothing.
    ///
    /// Optional: the default works on the primitives (see the default implementation). A tool whose shapes are not made of
    /// segments and lines, or that wants a bigger target, implements this itself; the editor calls it whatever the static type
    /// of the tool is.
    func hitTest(
        _ point: CGPoint,
        anchors: [ChartAnchor],
        domain: ChartDomain,
        transform: ChartTransform,
        tolerance: CGFloat
    ) -> DrawingHit?
}

extension DrawingTool {
    /// Finds what lies under `point` (screen coordinates).
    ///
    /// An anchor within `tolerance * 1.5` of the point wins (the nearest one if several qualify);
    /// otherwise the drawing's body is hit when the point is within `tolerance` of any of its primitives.
    /// Primitives are projected through `transform`.
    public func hitTest(
        _ point: CGPoint,
        anchors: [ChartAnchor],
        domain: ChartDomain,
        transform: ChartTransform,
        tolerance: CGFloat
    ) -> DrawingHit? {
        var nearestAnchor: (index: Int, distance: CGFloat)?
        for (index, anchor) in anchors.enumerated() {
            let distance = Self.distance(from: point, to: transform.point(for: anchor))
            if distance <= tolerance * 1.5, distance < (nearestAnchor?.distance ?? .infinity) {
                nearestAnchor = (index, distance)
            }
        }
        if let nearestAnchor { return .anchor(nearestAnchor.index) }

        let rect = transform.plotRect
        for primitive in primitives(for: anchors, in: domain) {
            let start: CGPoint
            let end: CGPoint
            switch primitive {
            case .segment(let first, let second):
                start = transform.point(for: first)
                end = transform.point(for: second)
            case .horizontalLine(let price):
                let y = transform.y(for: price)
                start = CGPoint(x: rect.minX, y: y)
                end = CGPoint(x: rect.maxX, y: y)
            case .verticalLine(let time):
                let x = transform.x(for: time)
                start = CGPoint(x: x, y: rect.minY)
                end = CGPoint(x: x, y: rect.maxY)
            }
            if Self.distance(from: point, toSegmentFrom: start, to: end) <= tolerance {
                return .body
            }
        }
        return nil
    }

    private static func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(from: point, to: start) }
        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(projection, 0), 1)
        return distance(from: point, to: CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}

/// A horizontal line at the price of its single anchor.
public struct HorizontalLineTool: DrawingTool {
    /// ``DrawingKind/horizontalLine``.
    public var kind: DrawingKind { .horizontalLine }
    /// One anchor.
    public var requiredAnchorCount: Int { 1 }

    /// Creates the tool.
    public init() {}

    /// A single horizontal line at the first anchor's price.
    public func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        guard let anchor = anchors.first else { return [] }
        return [.horizontalLine(price: anchor.price)]
    }
}

/// A segment between two anchors.
public struct TrendLineTool: DrawingTool {
    /// ``DrawingKind/trendLine``.
    public var kind: DrawingKind { .trendLine }
    /// Two anchors.
    public var requiredAnchorCount: Int { 2 }

    /// Creates the tool.
    public init() {}

    /// The segment from the first to the second anchor.
    public func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        guard anchors.count >= 2 else { return [] }
        return [.segment(anchors[0], anchors[1])]
    }
}

/// A line that starts at the first anchor, passes through the second and continues to the edge of the X domain.
public struct RayTool: DrawingTool {
    /// ``DrawingKind/ray``.
    public var kind: DrawingKind { .ray }
    /// Two anchors.
    public var requiredAnchorCount: Int { 2 }

    /// Creates the tool.
    public init() {}

    /// A segment from the first anchor to the domain edge in the direction of the second anchor.
    ///
    /// The price at the edge is extrapolated linearly. A ray pointing right ends at `domain.x.upperBound`,
    /// one pointing left at `domain.x.lowerBound`; it never ends before the second anchor. A perfectly vertical
    /// ray ends at the top or bottom of `domain.y`.
    public func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        guard anchors.count >= 2 else { return [] }
        let start = anchors[0]
        let through = anchors[1]
        let deltaTime = through.time.timeIntervalSince(start.time)

        guard deltaTime != 0 else {
            let edgePrice = through.price >= start.price ? domain.y.upperBound : domain.y.lowerBound
            return [.segment(start, ChartAnchor(time: start.time, price: edgePrice))]
        }
        let edgeTime = deltaTime > 0
            ? max(domain.x.upperBound, through.time)
            : min(domain.x.lowerBound, through.time)
        let slope = (through.price - start.price) / deltaTime
        let edgePrice = start.price + slope * edgeTime.timeIntervalSince(start.time)
        return [.segment(start, ChartAnchor(time: edgeTime, price: edgePrice))]
    }
}
