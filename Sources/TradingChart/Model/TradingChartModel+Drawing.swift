import CoreGraphics
import Foundation
import TradingChartCore

// The drawings of a chart: a thin layer over ``DrawingEditor`` (Core), which makes every decision. The model owns the
// editor, feeds it the taps and drags the view reports (with the geometry the chart shows at that moment) and passes the
// events it returns on to ``TradingChartModel/onEvent``.

@available(iOS 17.0, *)
extension TradingChartModel {

    /// The drawings, bottom to top.
    ///
    /// Assigning replaces all of them, for example to restore saved ones (``ChartDrawing`` is `Codable`). Drawings are
    /// anchored to absolute times and prices, so they survive changes of the interval, the style, scrolling and zooming.
    /// No ``DrawingEvent`` is sent for an assignment, except ``DrawingEvent/selectionChanged(_:)`` with `nil` when the
    /// selected drawing is no longer among the new ones.
    ///
    /// Drawings show whether or not ``TradingChartConfiguration/isDrawingEnabled`` is on; that setting only turns off
    /// creating and editing them by touch.
    public var drawings: [ChartDrawing] {
        get { drawingEditor.drawings }
        set {
            guard newValue != drawingEditor.drawings else { return }
            let hadSelection = drawingEditor.selectedID != nil
            drawingEditor.setDrawings(newValue)
            if hadSelection, drawingEditor.selectedID == nil { emit(.selectionChanged(nil)) }
        }
    }

    /// The kind of drawing being created, or `nil`.
    ///
    /// Setting a kind starts creation: the next taps on the chart place its anchors (one for a horizontal line, two for a
    /// trend line or a ray), and when the last one is placed the drawing is added and selected, ``DrawingEvent/added(_:)``
    /// is sent and this goes back to `nil`. Setting `nil` cancels a half-placed drawing. Starting a tool clears the
    /// selection. Only taps place anchors: a drag still scrolls the chart, and the crosshair and the pinch work as usual.
    ///
    /// Ignored while ``TradingChartConfiguration/isDrawingEnabled`` is `false`.
    public var activeDrawingTool: DrawingKind? {
        get { drawingEditor.activeTool }
        set {
            let kind = configuration.isDrawingEnabled ? newValue : nil
            guard kind != drawingEditor.activeTool else { return }
            drawingEditor.beginCreating(kind)
            if kind != nil { emit(drawingEditor.select(nil)) }
        }
    }

    /// The selected drawing. A selected drawing shows handles on its anchors and can be dragged (by an anchor or by its
    /// body) unless it is locked: a drag that starts on it moves it, any other drag scrolls the chart as usual. A tap on
    /// empty space clears the selection.
    ///
    /// Setting an id that is not among ``drawings`` clears the selection. Changes are reported as
    /// ``DrawingEvent/selectionChanged(_:)``.
    public var selectedDrawingID: UUID? {
        get { drawingEditor.selectedID }
        set { emit(drawingEditor.select(newValue)) }
    }

    /// Deletes the selected drawing, if there is one. Sends ``DrawingEvent/removed(_:)`` and then
    /// ``DrawingEvent/selectionChanged(_:)`` with `nil`.
    public func deleteSelectedDrawing() {
        guard let id = drawingEditor.selectedID else { return }
        removeDrawing(id: id)
    }

    /// Deletes the drawing with `id`, locked or not; unknown ids are ignored. Sends ``DrawingEvent/removed(_:)`` and, when
    /// the drawing was selected, ``DrawingEvent/selectionChanged(_:)`` with `nil`.
    public func removeDrawing(id: UUID) {
        let wasSelected = drawingEditor.selectedID == id
        guard let event = drawingEditor.remove(id: id) else { return }
        emit(event)
        if wasSelected { emit(.selectionChanged(nil)) }
    }

    /// Deletes every drawing: one ``DrawingEvent/removed(_:)`` for each, then ``DrawingEvent/selectionChanged(_:)`` with
    /// `nil` if one was selected.
    public func removeAllDrawings() {
        let ids = drawingEditor.drawings.map(\.id)
        guard !ids.isEmpty else { return }
        let hadSelection = drawingEditor.selectedID != nil
        drawingEditor.removeAll()
        for id in ids { emit(.removed(id)) }
        if hadSelection { emit(.selectionChanged(nil)) }
    }

    // MARK: - Input from the view

    /// Whether a touch at `point` (in the coordinates of the plot) would grab the selected drawing, an anchor or its body: then
    /// a drag from there moves the drawing instead of scrolling the chart. Never while a tool is active (taps place anchors,
    /// drags scroll). Changes nothing.
    func drawingGrabsSelected(at point: CGPoint, plot: CGRect) -> Bool {
        guard configuration.isDrawingEnabled, drawingEditor.selectedID != nil, drawingEditor.activeTool == nil else { return false }
        var probe = drawingEditor
        return probe.beginDrag(at: point, context: drawingContext(plot: plot))
    }

    /// The mapping between the plot of the main pane (in its own coordinates) and data: the visible window and the
    /// autoscaled price range that is shown.
    func drawingTransform(plot: CGRect) -> ChartTransform {
        ChartTransform(plotRect: plot, timeRange: visibleTimeRange, priceRange: mainYTarget)
    }

    /// Everything the editor needs to read a touch at the current window.
    func drawingContext(plot: CGRect) -> DrawingContext {
        DrawingContext(
            registry: drawingTools,
            domain: drawingDomain(),
            transform: drawingTransform(plot: plot),
            interval: series.interval
        )
    }

    /// The data-space extent tools are given: the whole X domain of the series (so a ray runs to its end and is clipped
    /// to the window when drawn) and the price range that is shown.
    func drawingDomain() -> ChartDomain {
        ChartDomain(
            x: naturalXDomain,
            y: mainYTarget
        )
    }

    /// A tap at `point` (in the coordinates of the plot): places an anchor while a tool is active, otherwise selects or
    /// deselects the drawing under it.
    func drawingTap(at point: CGPoint, plot: CGRect) {
        guard configuration.isDrawingEnabled, plot.contains(point) else { return }
        let context = drawingContext(plot: plot)
        emit(drawingEditor.tap(at: context.transform.anchor(at: point), screenPoint: point, context: context))
    }

    /// A touch went down at `point`. Returns whether it grabbed the selected drawing (an anchor or its body).
    func drawingBeginDrag(at point: CGPoint, plot: CGRect) -> Bool {
        drawingGrabOffset = .zero
        guard configuration.isDrawingEnabled else { return false }
        let context = drawingContext(plot: plot)
        guard drawingEditor.beginDrag(at: point, context: context) else { return false }
        // An anchor stays where it is relative to the finger instead of jumping under it.
        if let id = drawingEditor.selectedID,
           let drawing = drawingEditor.drawings.first(where: { $0.id == id }),
           let tool = context.registry.tool(for: drawing.kind),
           case .anchor(let index)? = tool.hitTest(
               point,
               anchors: drawing.anchors,
               domain: context.domain,
               transform: context.transform,
               tolerance: context.tolerance
           ),
           drawing.anchors.indices.contains(index) {
            let anchorPoint = context.transform.point(for: drawing.anchors[index])
            drawingGrabOffset = CGSize(width: anchorPoint.x - point.x, height: anchorPoint.y - point.y)
        }
        return true
    }

    /// The finger moved to `point` while dragging. A drawing cannot be dragged out of the plot.
    func drawingContinueDrag(to point: CGPoint, plot: CGRect) {
        let target = CGPoint(
            x: Swift.min(Swift.max(point.x, plot.minX), plot.maxX) + drawingGrabOffset.width,
            y: Swift.min(Swift.max(point.y, plot.minY), plot.maxY) + drawingGrabOffset.height
        )
        drawingEditor.drag(to: drawingTransform(plot: plot).anchor(at: target))
    }

    /// The finger lifted: ends the drag and reports the change.
    func drawingEndDrag() {
        drawingGrabOffset = .zero
        emit(drawingEditor.endDrag())
    }

    /// Drawing is switched off: cancel what is half done and clear the selection.
    func cancelDrawingInteraction() {
        if drawingEditor.activeTool != nil { drawingEditor.beginCreating(nil) }
        emit(drawingEditor.select(nil))
    }

    private func emit(_ event: DrawingEvent?) {
        guard let event else { return }
        onEvent?(.drawing(event))
    }
}
