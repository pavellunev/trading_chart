import CoreGraphics
import Foundation
import Testing
@testable import TradingChart

extension EventLog {
    var drawingEvents: [DrawingEvent] {
        events.compactMap { if case .drawing(let event) = $0 { event } else { nil } }
    }
}

/// A custom tool defined by the host: a vertical line through its single anchor.
struct VerticalLineTool: DrawingTool {
    var kind: DrawingKind { "verticalLine" }
    var requiredAnchorCount: Int { 1 }

    func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        anchors.first.map { [.verticalLine(time: $0.time)] } ?? []
    }
}

private let plot = CGRect(x: 0, y: 0, width: 300, height: 240)

@MainActor
private func makeDrawingModel(count: Int = 200) -> TradingChartModel {
    let model = TradingChartModel(series: makeSeries(count: count), style: .candles)
    model.currentPrice = model.series.lastValue
    return model
}

/// The screen point of a bar's time and a price at the model's current window.
@MainActor
private func screenPoint(_ model: TradingChartModel, barsFromEnd: Double, price: Double) -> CGPoint {
    let time = model.series.lastTime!.addingTimeInterval(-barsFromEnd * model.series.interval.seconds)
    return model.drawingTransform(plot: plot).point(for: ChartAnchor(time: time, price: price))
}

@MainActor
@Suite("Drawings in the model")
struct DrawingModelTests {

    // MARK: - Creation

    @Test("two taps create a trend line at the tapped bars and prices, and report it")
    func createsTrendLine() throws {
        let model = makeDrawingModel()
        let log = EventLog(model)
        let price = model.mainYTarget.lowerBound + (model.mainYTarget.upperBound - model.mainYTarget.lowerBound) * 0.3

        model.activeDrawingTool = .trendLine
        #expect(model.activeDrawingTool == .trendLine)
        model.drawingTap(at: screenPoint(model, barsFromEnd: 20, price: price), plot: plot)
        #expect(model.drawings.isEmpty)
        #expect(model.activeDrawingTool == .trendLine)
        model.drawingTap(at: screenPoint(model, barsFromEnd: 5, price: price * 1.01), plot: plot)

        let drawing = try #require(model.drawings.first)
        #expect(model.drawings.count == 1)
        #expect(drawing.kind == .trendLine)
        let times = [20.0, 5.0].map { model.series.lastTime!.addingTimeInterval(-$0 * 60) }
        #expect(drawing.anchors.map(\.time) == times)
        #expect(abs(drawing.anchors[0].price - price) < 1e-6)
        #expect(abs(drawing.anchors[1].price - price * 1.01) < 1e-6)
        #expect(model.activeDrawingTool == nil)
        #expect(model.selectedDrawingID == drawing.id)
        #expect(log.drawingEvents == [.added(drawing)])
    }

    @Test("a horizontal line takes one tap, a ray two")
    func otherTools() {
        let model = makeDrawingModel()
        model.activeDrawingTool = .horizontalLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 10, price: 285), plot: plot)
        #expect(model.drawings.map(\.kind) == [.horizontalLine])

        model.activeDrawingTool = .ray
        model.drawingTap(at: screenPoint(model, barsFromEnd: 30, price: 270), plot: plot)
        #expect(model.drawings.count == 1)
        model.drawingTap(at: screenPoint(model, barsFromEnd: 15, price: 280), plot: plot)
        #expect(model.drawings.map(\.kind) == [.horizontalLine, .ray])
    }

    @Test("cancelling a tool discards the placed anchors")
    func cancelling() {
        let model = makeDrawingModel()
        model.activeDrawingTool = .trendLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 20, price: 280), plot: plot)
        model.activeDrawingTool = nil
        model.drawingTap(at: screenPoint(model, barsFromEnd: 10, price: 280), plot: plot)
        #expect(model.drawings.isEmpty)
        #expect(model.drawingEditor.pendingAnchors.isEmpty)
    }

    @Test("taps outside the plot are ignored")
    func tapsOutsideThePlot() {
        let model = makeDrawingModel()
        model.activeDrawingTool = .horizontalLine
        model.drawingTap(at: CGPoint(x: plot.maxX + 20, y: 100), plot: plot)
        model.drawingTap(at: CGPoint(x: 100, y: plot.maxY + 5), plot: plot)
        #expect(model.drawings.isEmpty)
        #expect(model.activeDrawingTool == .horizontalLine)
    }

    @Test("starting a tool clears the selection")
    func toolClearsSelection() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id
        let log = EventLog(model)

        model.activeDrawingTool = .trendLine
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == [.selectionChanged(nil)])
    }

    // MARK: - Selection, removal

    @Test("a tap on a drawing selects it and a tap on empty space deselects it")
    func selection() {
        let model = makeDrawingModel()
        let first = ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-30 * 60), price: 270)
        let second = ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-10 * 60), price: 285)
        let drawing = ChartDrawing(kind: .trendLine, anchors: [first, second])
        model.drawings = [drawing]
        let log = EventLog(model)

        let middle = model.drawingTransform(plot: plot).point(for: ChartAnchor(
            time: first.time.addingTimeInterval(10 * 60),
            price: 277.5
        ))
        model.drawingTap(at: middle, plot: plot)
        #expect(model.selectedDrawingID == drawing.id)
        model.drawingTap(at: CGPoint(x: 20, y: 20), plot: plot)
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == [.selectionChanged(drawing.id), .selectionChanged(nil)])
    }

    @Test("deleting the selected drawing reports the removal, then the cleared selection")
    func deleteSelected() {
        let model = makeDrawingModel()
        let keep = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 270)])
        let drop = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [keep, drop]
        model.selectedDrawingID = drop.id
        let log = EventLog(model)

        model.deleteSelectedDrawing()
        #expect(model.drawings == [keep])
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == [.removed(drop.id), .selectionChanged(nil)])

        model.deleteSelectedDrawing()
        #expect(log.drawingEvents.count == 2)
    }

    @Test("removing a drawing that is not selected leaves the selection alone")
    func removeOther() {
        let model = makeDrawingModel()
        let keep = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 270)])
        let drop = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [keep, drop]
        model.selectedDrawingID = keep.id
        let log = EventLog(model)

        model.removeDrawing(id: drop.id)
        #expect(model.selectedDrawingID == keep.id)
        #expect(log.drawingEvents == [.removed(drop.id)])

        model.removeDrawing(id: UUID())
        #expect(log.drawingEvents.count == 1)
    }

    @Test("removeAllDrawings reports every removal and the cleared selection")
    func removeAll() {
        let model = makeDrawingModel()
        let drawings = [270.0, 280, 290].map {
            ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: $0)])
        }
        model.drawings = drawings
        model.selectedDrawingID = drawings[1].id
        let log = EventLog(model)

        model.removeAllDrawings()
        #expect(model.drawings.isEmpty)
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == drawings.map { .removed($0.id) } + [.selectionChanged(nil)])

        model.removeAllDrawings()
        #expect(log.drawingEvents.count == 4)
    }

    @Test("setting drawings sends no events, and drops a selection that is gone")
    func setDrawings() {
        let model = makeDrawingModel()
        let kept = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 270)])
        let gone = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [kept, gone]
        let log = EventLog(model)
        #expect(log.drawingEvents.isEmpty)

        model.selectedDrawingID = kept.id
        model.drawings = [gone, kept]
        #expect(model.selectedDrawingID == kept.id)

        model.drawings = [gone]
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == [.selectionChanged(kept.id), .selectionChanged(nil)])
    }

    @Test("selecting an id that is not there clears the selection")
    func selectUnknown() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 270)])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id
        model.selectedDrawingID = UUID()
        #expect(model.selectedDrawingID == nil)
    }

    // MARK: - Dragging

    private func trendLineModel() -> (TradingChartModel, ChartDrawing) {
        let model = makeDrawingModel()
        let last = model.series.lastTime!
        let drawing = ChartDrawing(kind: .trendLine, anchors: [
            ChartAnchor(time: last.addingTimeInterval(-30 * 60), price: 270),
            ChartAnchor(time: last.addingTimeInterval(-10 * 60), price: 285),
        ])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id
        return (model, drawing)
    }

    @Test("dragging an anchor moves it, snaps its time, and reports the change once at the end")
    func dragAnchor() throws {
        let (model, drawing) = trendLineModel()
        let log = EventLog(model)
        let start = model.drawingTransform(plot: plot).point(for: drawing.anchors[1])

        #expect(model.drawingBeginDrag(at: start, plot: plot))
        let target = screenPoint(model, barsFromEnd: 4.2, price: 288)
        model.drawingContinueDrag(to: target, plot: plot)
        #expect(log.drawingEvents.isEmpty)  // nothing is reported until the finger lifts
        model.drawingEndDrag()

        let moved = try #require(model.drawings.first)
        #expect(moved.anchors[0] == drawing.anchors[0])
        #expect(moved.anchors[1].time == model.series.lastTime!.addingTimeInterval(-4 * 60))
        #expect(abs(moved.anchors[1].price - 288) < 1e-6)
        #expect(log.drawingEvents == [.changed(moved)])
    }

    @Test("a grabbed anchor stays where it is relative to the finger")
    func grabOffset() throws {
        let (model, drawing) = trendLineModel()
        let anchorPoint = model.drawingTransform(plot: plot).point(for: drawing.anchors[0])
        let grab = CGPoint(x: anchorPoint.x + 6, y: anchorPoint.y - 5)

        #expect(model.drawingBeginDrag(at: grab, plot: plot))
        model.drawingContinueDrag(to: grab, plot: plot)  // the finger has not moved relative to the anchor
        model.drawingEndDrag()
        let anchor = try #require(model.drawings.first?.anchors[0])
        #expect(anchor.time == drawing.anchors[0].time)
        #expect(abs(anchor.price - drawing.anchors[0].price) < 1e-6)
    }

    @Test("dragging the body shifts every anchor")
    func dragBody() throws {
        let (model, drawing) = trendLineModel()
        let transform = model.drawingTransform(plot: plot)
        let middle = transform.point(for: ChartAnchor(
            time: drawing.anchors[0].time.addingTimeInterval(10 * 60),
            price: 277.5
        ))
        #expect(model.drawingBeginDrag(at: middle, plot: plot))
        let threeBars = 3 * plot.width / model.visibleBars
        model.drawingContinueDrag(to: CGPoint(x: middle.x + threeBars, y: middle.y), plot: plot)
        model.drawingEndDrag()

        let moved = try #require(model.drawings.first)
        #expect(moved.anchors.map(\.time) == drawing.anchors.map { $0.time.addingTimeInterval(3 * 60) })
        #expect(zip(moved.anchors, drawing.anchors).allSatisfy { abs($0.price - $1.price) < 1e-6 })
    }

    @Test("a drag cannot take a drawing out of the plot")
    func dragIsClampedToThePlot() throws {
        let (model, drawing) = trendLineModel()
        let start = model.drawingTransform(plot: plot).point(for: drawing.anchors[1])
        #expect(model.drawingBeginDrag(at: start, plot: plot))
        model.drawingContinueDrag(to: CGPoint(x: plot.maxX + 500, y: -500), plot: plot)
        model.drawingEndDrag()

        let moved = try #require(model.drawings.first?.anchors[1])
        let point = model.drawingTransform(plot: plot).point(for: moved)
        // The anchor was grabbed at its centre, so it sits on the clamped finger: on the top right corner of the plot (the
        // time snaps to the nearest bar, which can be half a bar beyond it).
        #expect(point.x <= plot.maxX + plot.width / model.visibleBars / 2 + 1e-6)
        #expect(abs(point.y - plot.minY) < 1e-6)
    }

    @Test("a touch that misses the selected drawing does not start a drag")
    func missedDrag() {
        let (model, _) = trendLineModel()
        #expect(!model.drawingBeginDrag(at: CGPoint(x: 150, y: 230), plot: plot))
        model.drawingContinueDrag(to: CGPoint(x: 100, y: 100), plot: plot)
        model.drawingEndDrag()
        #expect(model.drawings.count == 1)
    }

    @Test("a locked drawing cannot be dragged")
    func lockedDrawing() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(
            kind: .horizontalLine,
            anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)],
            isLocked: true
        )
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id
        let point = screenPoint(model, barsFromEnd: 0, price: 280)
        #expect(!model.drawingBeginDrag(at: point, plot: plot))
    }

    // MARK: - Whose a drag is

    @Test("a drag from the selected drawing (an anchor or the body) is the drawing's, any other drag is the chart's")
    func grabsSelected() {
        let (model, drawing) = trendLineModel()
        let transform = model.drawingTransform(plot: plot)
        let first = transform.point(for: drawing.anchors[0])
        let second = transform.point(for: drawing.anchors[1])
        let middle = CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)

        #expect(model.drawingGrabsSelected(at: first, plot: plot))
        #expect(model.drawingGrabsSelected(at: second, plot: plot))
        #expect(model.drawingGrabsSelected(at: middle, plot: plot))
        #expect(!model.drawingGrabsSelected(at: CGPoint(x: middle.x, y: middle.y + 60), plot: plot))
        #expect(!model.drawingGrabsSelected(at: CGPoint(x: 5, y: 5), plot: plot))
    }

    @Test("without a selection, or while a tool is active, no drag is the drawing's; asking changes nothing")
    func grabsNothingElse() throws {
        let (model, drawing) = trendLineModel()
        let point = model.drawingTransform(plot: plot).point(for: drawing.anchors[1])

        model.selectedDrawingID = nil
        #expect(!model.drawingGrabsSelected(at: point, plot: plot))

        model.selectedDrawingID = drawing.id
        #expect(model.drawingGrabsSelected(at: point, plot: plot))
        // Asking did not start a drag: continuing and ending one that was never begun leaves the drawing alone.
        model.drawingContinueDrag(to: CGPoint(x: 100, y: 100), plot: plot)
        model.drawingEndDrag()
        #expect(model.drawings == [drawing])

        model.activeDrawingTool = .ray  // starting a tool clears the selection; a tap on the drawing selects nothing now
        #expect(!model.drawingGrabsSelected(at: point, plot: plot))
    }

    @Test("a locked drawing is not grabbed, and neither is anything once drawing is switched off")
    func grabsLockedAndDisabled() {
        let model = makeDrawingModel()
        let locked = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)], isLocked: true)
        model.drawings = [locked]
        model.selectedDrawingID = locked.id
        #expect(!model.drawingGrabsSelected(at: screenPoint(model, barsFromEnd: 0, price: 280), plot: plot))

        let (other, drawing) = trendLineModel()
        let point = other.drawingTransform(plot: plot).point(for: drawing.anchors[1])
        other.configuration.isDrawingEnabled = false
        #expect(!other.drawingGrabsSelected(at: point, plot: plot))
    }

    @Test("with drawing disabled no tool starts, no tap lands, but drawings given by the host are kept")
    func disabled() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [drawing]
        model.configuration.isDrawingEnabled = false

        model.activeDrawingTool = .trendLine
        #expect(model.activeDrawingTool == nil)
        model.drawingTap(at: screenPoint(model, barsFromEnd: 0, price: 280), plot: plot)
        #expect(model.selectedDrawingID == nil)
        #expect(model.drawings == [drawing])
    }

    @Test("switching drawing off cancels a tool and clears the selection")
    func switchingOff() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id
        let log = EventLog(model)

        model.configuration.isDrawingEnabled = false
        #expect(model.selectedDrawingID == nil)
        #expect(log.drawingEvents == [.selectionChanged(nil)])

        model.configuration.isDrawingEnabled = true
        model.activeDrawingTool = .trendLine
        model.configuration.isDrawingEnabled = false
        #expect(model.activeDrawingTool == nil)
        #expect(model.drawingEditor.pendingAnchors.isEmpty)
    }

    // MARK: - Absolute positions

    @Test("drawings survive a change of interval, style, scrolling and zoom unchanged")
    func survivesViewChanges() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: .trendLine, anchors: [
            ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-30 * 60), price: 270),
            ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-10 * 60), price: 285),
        ])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id

        model.scrollPosition = model.scrollPosition.addingTimeInterval(-100 * 60)
        model.zoom(by: 2, anchor: .center)
        model.style = .line
        model.setSeries(makeSeries(count: 200, interval: .minutes(5), lastStart: baseTime + 199 * 60))
        model.update(price: 301, at: date(baseTime + 200 * 60), volume: 1)

        #expect(model.drawings == [drawing])
        #expect(model.selectedDrawingID == drawing.id)
    }

    @Test("a tap lands on the bar and the price under the finger after scrolling into the history and zooming")
    func coordinatesAfterScrollAndZoom() throws {
        let model = makeDrawingModel(count: 400)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-150 * 60)
        model.zoom(by: 2.5, anchor: .center)
        let transform = model.drawingTransform(plot: plot)
        let barWidth = plot.width / model.visibleBars

        model.activeDrawingTool = .trendLine
        for point in [CGPoint(x: 60.3, y: 80.7), CGPoint(x: 240.9, y: 160.2)] {
            model.drawingTap(at: point, plot: plot)
        }
        let anchors = try #require(model.drawings.first?.anchors)
        for (anchor, point) in zip(anchors, [CGPoint(x: 60.3, y: 80.7), CGPoint(x: 240.9, y: 160.2)]) {
            let back = transform.point(for: anchor)
            #expect(abs(back.x - point.x) <= barWidth / 2 + 1e-6)  // time snaps to the nearest bar
            #expect(abs(back.y - point.y) < 1e-6)  // price is free
            #expect(model.series.index(nearestTo: anchor.time).map { model.series.points[$0].time } == anchor.time)
        }
    }

    // MARK: - Persistence and custom tools

    @Test("drawings round-trip through JSON")
    func codable() throws {
        let model = makeDrawingModel()
        let drawings = [
            ChartDrawing(kind: .ray, anchors: [
                ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-30 * 60), price: 270),
                ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-10 * 60), price: 285),
            ], style: DrawingStyle(color: ChartColor(red: 1, green: 0.5, blue: 0), lineWidth: 2, dash: [4, 2])),
            ChartDrawing(kind: "verticalLine", anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)], isLocked: true),
        ]
        model.drawings = drawings
        let data = try JSONEncoder().encode(model.drawings)

        let restored = makeDrawingModel()
        restored.drawings = try JSONDecoder().decode([ChartDrawing].self, from: data)
        #expect(restored.drawings == drawings)
    }

    @Test("a custom tool registered with the model creates, hit-tests and drags like a built-in one")
    func customTool() throws {
        let model = makeDrawingModel()
        #expect(model.drawingTools.tool(for: "verticalLine") == nil)
        model.drawingTools.register(VerticalLineTool())
        #expect(model.drawingTools.tool(for: "verticalLine")?.requiredAnchorCount == 1)

        model.activeDrawingTool = "verticalLine"
        let tapPoint = screenPoint(model, barsFromEnd: 12, price: 280)
        model.drawingTap(at: tapPoint, plot: plot)
        let drawing = try #require(model.drawings.first)
        #expect(drawing.kind == "verticalLine")
        #expect(drawing.anchors[0].time == model.series.lastTime!.addingTimeInterval(-12 * 60))

        // The vertical line is hit anywhere along its height ...
        model.drawingTap(at: CGPoint(x: 5, y: 5), plot: plot)
        #expect(model.selectedDrawingID == nil)
        model.drawingTap(at: CGPoint(x: tapPoint.x + 3, y: 30), plot: plot)
        #expect(model.selectedDrawingID == drawing.id)

        // ... and dragged by its body, sideways.
        let grab = CGPoint(x: tapPoint.x, y: 200)
        #expect(model.drawingBeginDrag(at: grab, plot: plot))
        model.drawingContinueDrag(to: CGPoint(x: grab.x + 20, y: 200), plot: plot)
        model.drawingEndDrag()
        let moved = try #require(model.drawings.first?.anchors[0].time)
        #expect(moved > drawing.anchors[0].time)

        // It is drawn without any change to the package: a vertical line across the plot at the time of its anchor.
        let frame = DrawingLayout.frame(
            drawings: model.drawings,
            selectedID: nil,
            pendingAnchors: [],
            registry: model.drawingTools,
            domain: model.drawingDomain(),
            transform: model.drawingTransform(plot: plot)
        )
        let line = try #require(frame.strokes.first?.lines.first)
        #expect(line.from.y == plot.minY && line.to.y == plot.maxY)
        #expect(abs(line.from.x - model.drawingTransform(plot: plot).x(for: moved)) < 1e-9)
    }

    @Test("a kind without a registered tool is kept but not drawn")
    func unknownKind() {
        let model = makeDrawingModel()
        let drawing = ChartDrawing(kind: "fibonacci", anchors: [ChartAnchor(time: model.series.lastTime!, price: 280)])
        model.drawings = [drawing]
        let frame = DrawingLayout.frame(
            drawings: model.drawings,
            selectedID: drawing.id,
            pendingAnchors: [],
            registry: model.drawingTools,
            domain: model.drawingDomain(),
            transform: model.drawingTransform(plot: plot)
        )
        #expect(frame.isEmpty)
        #expect(model.drawings == [drawing])
    }
}
