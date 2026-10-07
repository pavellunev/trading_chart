import CoreGraphics
import Foundation
import TradingChartCore

/// One straight piece of a drawing in screen coordinates.
@available(iOS 17.0, *)
struct DrawingLine: Equatable {
    var from: CGPoint
    var to: CGPoint
}

/// What the canvas draws for one drawing: its lines, and its anchors when it is selected.
@available(iOS 17.0, *)
struct DrawingStroke: Equatable {
    var id: UUID
    var lines: [DrawingLine]
    var style: DrawingStyle
    var isSelected: Bool
    /// The anchors that are inside the plot (selected drawings only).
    var handles: [CGPoint]
}

/// Everything the canvas draws for the drawings, in screen coordinates.
@available(iOS 17.0, *)
struct DrawingFrame: Equatable {
    var strokes: [DrawingStroke]
    /// The anchors placed so far for the drawing being created, inside the plot.
    var pending: [CGPoint]

    var isEmpty: Bool { strokes.isEmpty && pending.isEmpty }
}

/// Turns drawings into what the canvas draws. Pure.
///
/// A ray runs to the end of the series and a line can be anchored far outside the window, so the shapes are clipped to the
/// window in data space first (see ``DrawingPrimitive/clipped(to:)``): to the visible time range plus a margin, and to the
/// price range that is shown. Only then are they mapped to the screen, so far-off coordinates never reach the canvas.
@available(iOS 17.0, *)
enum DrawingLayout {
    /// How much of the visible window, on each side, the shapes are kept beyond it: the ends of a stroke are never seen.
    static let windowMargin = 0.1
    /// How far beyond the plot an anchor still gets a handle, in points (the radius of a handle).
    static let handleReach: CGFloat = 8

    static func frame(
        drawings: [ChartDrawing],
        selectedID: UUID?,
        pendingAnchors: [ChartAnchor],
        registry: DrawingToolRegistry,
        domain: ChartDomain,
        transform: ChartTransform
    ) -> DrawingFrame {
        let visible = transform.timeRange
        let margin = visible.upperBound.timeIntervalSince(visible.lowerBound) * windowMargin
        let clip = ChartDomain(
            x: visible.lowerBound.addingTimeInterval(-margin)...visible.upperBound.addingTimeInterval(margin),
            y: transform.priceRange
        )
        let reach = transform.plotRect.insetBy(dx: -handleReach, dy: -handleReach)

        var strokes: [DrawingStroke] = []
        strokes.reserveCapacity(drawings.count)
        for drawing in drawings {
            guard let tool = registry.tool(for: drawing.kind) else { continue }
            let isSelected = drawing.id == selectedID
            let lines = tool.primitives(for: drawing.anchors, in: domain).compactMap {
                line(of: $0, clip: clip, transform: transform)
            }
            let handles = isSelected
                ? drawing.anchors.map(transform.point(for:)).filter { reach.contains($0) }
                : []
            guard !lines.isEmpty || !handles.isEmpty else { continue }
            strokes.append(DrawingStroke(id: drawing.id, lines: lines, style: drawing.style, isSelected: isSelected, handles: handles))
        }
        let pending = pendingAnchors.map(transform.point(for:)).filter { reach.contains($0) }
        return DrawingFrame(strokes: strokes, pending: pending)
    }

    /// The screen line of one primitive, or `nil` when none of it is inside `clip`.
    static func line(of primitive: DrawingPrimitive, clip: ChartDomain, transform: ChartTransform) -> DrawingLine? {
        guard let visible = primitive.clipped(to: clip) else { return nil }
        let plot = transform.plotRect
        switch visible {
        case .segment(let first, let second):
            return DrawingLine(from: transform.point(for: first), to: transform.point(for: second))
        case .horizontalLine(let price):
            let y = transform.y(for: price)
            return DrawingLine(from: CGPoint(x: plot.minX, y: y), to: CGPoint(x: plot.maxX, y: y))
        case .verticalLine(let time):
            let x = transform.x(for: time)
            return DrawingLine(from: CGPoint(x: x, y: plot.minY), to: CGPoint(x: x, y: plot.maxY))
        }
    }
}
