import CoreGraphics
import Foundation

/// A pure state machine behind chart drawing: creation, selection, dragging and removal.
///
/// The UI only feeds it taps and drags (with the current geometry in a ``DrawingContext``) and renders
/// ``drawings`` and ``selectedID``. Anchor times are snapped to the bucket grid of the series interval
/// (to the nearest bucket start, via `interval.bucketStart(for:)`); prices are free.
public struct DrawingEditor: Sendable, Equatable {
    /// All drawings, bottom to top.
    public private(set) var drawings: [ChartDrawing]
    /// The kind being created, or `nil` when not in creation mode.
    public private(set) var activeTool: DrawingKind?
    /// Anchors placed so far for the drawing being created.
    public private(set) var pendingAnchors: [ChartAnchor]
    /// The selected drawing.
    public private(set) var selectedID: UUID?

    private var activeDrag: Drag?

    private struct Drag: Sendable, Equatable {
        enum Target: Sendable, Equatable {
            case anchor(Int)
            case body(grabbedAt: ChartAnchor)
        }

        var id: UUID
        var target: Target
        var originalAnchors: [ChartAnchor]
        var interval: ChartInterval
    }

    /// Creates an editor, optionally pre-populated with drawings.
    public init(drawings: [ChartDrawing] = []) {
        self.drawings = drawings
        self.activeTool = nil
        self.pendingAnchors = []
        self.selectedID = nil
        self.activeDrag = nil
    }

    /// Enters creation mode for `kind`, discarding any half-placed drawing. Pass `nil` to cancel.
    public mutating func beginCreating(_ kind: DrawingKind?) {
        activeTool = kind
        pendingAnchors = []
        activeDrag = nil
    }

    /// Handles a tap.
    ///
    /// In creation mode the tap places an anchor (time snapped to the nearest bucket start). Once the tool's
    /// `requiredAnchorCount` is reached the drawing is committed with a new id and the default style, selected,
    /// creation mode ends and ``DrawingEvent/added(_:)`` is returned.
    ///
    /// Otherwise the drawings are hit-tested from top to bottom: the first hit becomes selected, a miss clears
    /// the selection. Returns ``DrawingEvent/selectionChanged(_:)`` when the selection actually changed.
    ///
    /// - Parameters:
    ///   - anchor: The tap in data space.
    ///   - screenPoint: The tap in screen coordinates (used for hit testing).
    ///   - context: The tools, geometry and snapping interval of the chart at the moment of the tap.
    @discardableResult
    public mutating func tap(at anchor: ChartAnchor, screenPoint: CGPoint, context: DrawingContext) -> DrawingEvent? {
        if let kind = activeTool {
            return placeAnchor(anchor, kind: kind, context: context)
        }
        let hitID = drawings.reversed().first { drawing in
            guard let tool = context.registry.tool(for: drawing.kind) else { return false }
            return tool.hitTest(
                screenPoint,
                anchors: drawing.anchors,
                domain: context.domain,
                transform: context.transform,
                tolerance: context.tolerance
            ) != nil
        }?.id
        guard hitID != selectedID else { return nil }
        selectedID = hitID
        return .selectionChanged(hitID)
    }

    /// Selects the drawing with `id`, or clears the selection with `nil`. An id that is not in ``drawings`` clears it.
    /// Returns ``DrawingEvent/selectionChanged(_:)`` when the selection actually changed.
    @discardableResult
    public mutating func select(_ id: UUID?) -> DrawingEvent? {
        let target = id.flatMap { id in drawings.contains { $0.id == id } ? id : nil }
        guard target != selectedID else { return nil }
        selectedID = target
        activeDrag = nil
        return .selectionChanged(target)
    }

    /// Starts dragging if `screenPoint` hits the selected, unlocked drawing (an anchor or its body).
    ///
    /// - Returns: `true` when a drag started. Always `false` in creation mode.
    public mutating func beginDrag(at screenPoint: CGPoint, context: DrawingContext) -> Bool {
        activeDrag = nil
        guard activeTool == nil,
              let selectedID,
              let drawing = drawings.first(where: { $0.id == selectedID }),
              !drawing.isLocked,
              let tool = context.registry.tool(for: drawing.kind),
              let hit = tool.hitTest(
                screenPoint,
                anchors: drawing.anchors,
                domain: context.domain,
                transform: context.transform,
                tolerance: context.tolerance
              )
        else { return false }

        let target: Drag.Target
        switch hit {
        case .anchor(let index):
            target = .anchor(index)
        case .body:
            target = .body(grabbedAt: context.transform.anchor(at: screenPoint))
        }
        activeDrag = Drag(id: drawing.id, target: target, originalAnchors: drawing.anchors, interval: context.interval)
        return true
    }

    /// Moves the dragged anchor to `anchor`, or shifts the whole drawing by the distance travelled since the grab.
    ///
    /// A dragged anchor is snapped to the nearest bucket start. A dragged body moves by one snapped shift: the first anchor
    /// goes to the nearest bucket start of where the travel would take it, and every other anchor moves by the same time, so
    /// the shape of the drawing (the time between its anchors) does not change, also when its anchors are not on the grid of the
    /// interval (it was drawn on another interval). Does nothing when no drag is active.
    public mutating func drag(to anchor: ChartAnchor) {
        guard let drag = activeDrag, let index = drawings.firstIndex(where: { $0.id == drag.id }) else { return }
        switch drag.target {
        case .anchor(let anchorIndex):
            guard drag.originalAnchors.indices.contains(anchorIndex) else { return }
            var anchors = drag.originalAnchors
            anchors[anchorIndex] = ChartAnchor(
                time: Self.snapped(anchor.time, to: drag.interval),
                price: anchor.price
            )
            drawings[index].anchors = anchors
        case .body(let grabbedAt):
            guard let first = drag.originalAnchors.first else { return }
            let deltaTime = anchor.time.timeIntervalSince(grabbedAt.time)
            let deltaPrice = anchor.price - grabbedAt.price
            // One shift for the whole drawing, snapped by its first anchor: snapping every anchor by itself would pull
            // anchors that are off the grid on to it, each by its own amount, and change the slope.
            let shift = Self.snapped(first.time.addingTimeInterval(deltaTime), to: drag.interval).timeIntervalSince(first.time)
            drawings[index].anchors = drag.originalAnchors.map {
                ChartAnchor(time: $0.time.addingTimeInterval(shift), price: $0.price + deltaPrice)
            }
        }
    }

    /// Finishes the drag. Returns ``DrawingEvent/changed(_:)`` if the drawing moved, `nil` otherwise.
    @discardableResult
    public mutating func endDrag() -> DrawingEvent? {
        defer { activeDrag = nil }
        guard let drag = activeDrag,
              let drawing = drawings.first(where: { $0.id == drag.id }),
              drawing.anchors != drag.originalAnchors
        else { return nil }
        return .changed(drawing)
    }

    /// Deletes a drawing (also when it is locked), clearing the selection if it was selected.
    /// Returns ``DrawingEvent/removed(_:)``, or `nil` if there is no such drawing.
    @discardableResult
    public mutating func remove(id: UUID) -> DrawingEvent? {
        guard let index = drawings.firstIndex(where: { $0.id == id }) else { return nil }
        drawings.remove(at: index)
        if selectedID == id { selectedID = nil }
        if activeDrag?.id == id { activeDrag = nil }
        return .removed(id)
    }

    /// Deletes every drawing and clears the selection and any drag.
    public mutating func removeAll() {
        drawings = []
        selectedID = nil
        activeDrag = nil
    }

    /// Replaces all drawings, e.g. when restoring persisted ones. Drops the selection if it no longer exists
    /// and cancels any drag.
    public mutating func setDrawings(_ newDrawings: [ChartDrawing]) {
        drawings = newDrawings
        activeDrag = nil
        if let selectedID, !newDrawings.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    private mutating func placeAnchor(_ anchor: ChartAnchor, kind: DrawingKind, context: DrawingContext) -> DrawingEvent? {
        guard let tool = context.registry.tool(for: kind) else {
            activeTool = nil
            pendingAnchors = []
            return nil
        }
        pendingAnchors.append(ChartAnchor(
            time: Self.snapped(anchor.time, to: context.interval),
            price: anchor.price
        ))
        guard pendingAnchors.count >= tool.requiredAnchorCount else { return nil }

        let drawing = ChartDrawing(kind: kind, anchors: pendingAnchors)
        drawings.append(drawing)
        selectedID = drawing.id
        activeTool = nil
        pendingAnchors = []
        return .added(drawing)
    }

    /// The bucket start nearest to `time`. Bars are drawn centered on their bucket start, so rounding (rather than
    /// flooring) keeps the anchor under the finger instead of up to a full bar to its left.
    private static func snapped(_ time: Date, to interval: ChartInterval) -> Date {
        interval.bucketStart(for: time.addingTimeInterval(interval.seconds / 2))
    }
}
