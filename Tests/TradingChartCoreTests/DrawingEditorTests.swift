import CoreGraphics
import Foundation
import Testing
import TradingChartCore

private func anchor(_ seconds: TimeInterval, _ price: Double) -> ChartAnchor {
    ChartAnchor(time: date(seconds), price: price)
}

// Geometry: 6 s per px on X (a 60 s bar is 10 px wide), 1 price unit per px on Y (y = 200 - price).
private let transform = ChartTransform(
    plotRect: CGRect(x: 0, y: 0, width: 1_000, height: 200),
    timeRange: date(0)...date(6_000),
    priceRange: 0...200
)

private func context(interval: ChartInterval = .minutes(1)) -> DrawingContext {
    DrawingContext(
        domain: ChartDomain(x: date(0)...date(6_000), y: 0...200),
        transform: transform,
        interval: interval
    )
}

private func screen(_ time: TimeInterval, _ price: Double) -> CGPoint {
    transform.point(for: anchor(time, price))
}

/// A tap at a data position, with the matching screen point.
private func tap(_ editor: inout DrawingEditor, _ time: TimeInterval, _ price: Double) -> DrawingEvent? {
    editor.tap(at: anchor(time, price), screenPoint: screen(time, price), context: context())
}

private let trendAnchors = [anchor(1_200, 50), anchor(2_400, 150)]

private func editorWithTrendLine(isLocked: Bool = false, selected: Bool = false) -> DrawingEditor {
    var editor = DrawingEditor(drawings: [ChartDrawing(kind: .trendLine, anchors: trendAnchors, isLocked: isLocked)])
    if selected {
        _ = tap(&editor, 1_800, 100)
    }
    return editor
}

@Suite("DrawingEditor creation")
struct DrawingEditorCreationTests {
    @Test("A trend line is created by two taps")
    func trendLine() throws {
        var editor = DrawingEditor()
        editor.beginCreating(.trendLine)
        #expect(editor.activeTool == .trendLine)

        #expect(tap(&editor, 125, 50) == nil)
        #expect(editor.pendingAnchors == [anchor(120, 50)])
        #expect(editor.activeTool == .trendLine)
        #expect(editor.drawings.isEmpty)

        let event = tap(&editor, 610, 150)
        guard case .added(let drawing) = event else {
            Issue.record("Expected .added, got \(String(describing: event))")
            return
        }
        #expect(drawing.kind == .trendLine)
        #expect(drawing.anchors == [anchor(120, 50), anchor(600, 150)])
        #expect(drawing.style == DrawingStyle())
        #expect(!drawing.isLocked)
        #expect(editor.drawings == [drawing])
        #expect(editor.selectedID == drawing.id)
        #expect(editor.activeTool == nil)
        #expect(editor.pendingAnchors.isEmpty)
    }

    @Test("A horizontal line is created by one tap")
    func horizontalLine() {
        var editor = DrawingEditor()
        editor.beginCreating(.horizontalLine)
        let event = tap(&editor, 3_000, 80)
        guard case .added(let drawing) = event else {
            Issue.record("Expected .added, got \(String(describing: event))")
            return
        }
        #expect(drawing.kind == .horizontalLine)
        #expect(drawing.anchors == [anchor(3_000, 80)])
        #expect(editor.selectedID == drawing.id)
        #expect(editor.activeTool == nil)
    }

    @Test("A ray is created by two taps")
    func ray() {
        var editor = DrawingEditor()
        editor.beginCreating(.ray)
        #expect(tap(&editor, 600, 40) == nil)
        let event = tap(&editor, 1_200, 60)
        #expect(event != nil)
        #expect(editor.drawings.first?.kind == .ray)
        #expect(editor.drawings.first?.anchors.count == 2)
    }

    @Test("Anchor times snap to the nearest bucket start, prices stay free")
    func snapsTimeOnly() {
        var editor = DrawingEditor()
        editor.beginCreating(.horizontalLine)
        _ = tap(&editor, 3_025, 80.123) // 25 s after 3_000, 35 s before 3_060
        #expect(editor.drawings.first?.anchors == [anchor(3_000, 80.123)])

        editor.beginCreating(.horizontalLine)
        _ = tap(&editor, 3_035, 80.5) // 35 s after 3_000, 25 s before 3_060
        #expect(editor.drawings.last?.anchors == [anchor(3_060, 80.5)])

        editor.beginCreating(.horizontalLine)
        _ = tap(&editor, 3_060, 1) // exactly on a bucket start
        #expect(editor.drawings.last?.anchors == [anchor(3_060, 1)])

        var hourly = DrawingEditor()
        hourly.beginCreating(.horizontalLine)
        _ = hourly.tap(at: anchor(7_300, 10), screenPoint: .zero, context: context(interval: .hours(1)))
        #expect(hourly.drawings.first?.anchors == [anchor(7_200, 10)])
    }

    @Test("Each committed drawing gets its own id")
    func uniqueIDs() {
        var editor = DrawingEditor()
        for _ in 0..<2 {
            editor.beginCreating(.horizontalLine)
            _ = tap(&editor, 600, 100)
        }
        #expect(editor.drawings.count == 2)
        #expect(editor.drawings[0].id != editor.drawings[1].id)
    }

    @Test("Cancelling creation discards the pending anchors")
    func cancel() {
        var editor = DrawingEditor()
        editor.beginCreating(.trendLine)
        _ = tap(&editor, 600, 40)
        editor.beginCreating(nil)
        #expect(editor.activeTool == nil)
        #expect(editor.pendingAnchors.isEmpty)
        #expect(editor.drawings.isEmpty)
    }

    @Test("Restarting creation discards the pending anchors")
    func restart() {
        var editor = DrawingEditor()
        editor.beginCreating(.trendLine)
        _ = tap(&editor, 600, 40)
        editor.beginCreating(.ray)
        #expect(editor.activeTool == .ray)
        #expect(editor.pendingAnchors.isEmpty)
    }

    @Test("A kind without a registered tool cancels creation")
    func unknownKind() {
        var editor = DrawingEditor()
        editor.beginCreating("fibonacci")
        #expect(tap(&editor, 600, 40) == nil)
        #expect(editor.activeTool == nil)
        #expect(editor.pendingAnchors.isEmpty)
        #expect(editor.drawings.isEmpty)
    }

    @Test("A custom registered tool drives the anchor count")
    func customTool() {
        struct ThreePointTool: DrawingTool {
            var kind: DrawingKind { "triangle" }
            var requiredAnchorCount: Int { 3 }
            func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] { [] }
        }
        var registry = DrawingToolRegistry.standard
        registry.register(ThreePointTool())
        var custom = context()
        custom.registry = registry

        var editor = DrawingEditor()
        editor.beginCreating("triangle")
        #expect(editor.tap(at: anchor(60, 1), screenPoint: .zero, context: custom) == nil)
        #expect(editor.tap(at: anchor(120, 2), screenPoint: .zero, context: custom) == nil)
        #expect(editor.tap(at: anchor(180, 3), screenPoint: .zero, context: custom) != nil)
        #expect(editor.drawings.first?.anchors.count == 3)
    }
}

@Suite("DrawingEditor selection")
struct DrawingEditorSelectionTests {
    private let level = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)])

    @Test("Tapping a drawing selects it")
    func selects() {
        var editor = DrawingEditor(drawings: [level])
        let event = editor.tap(at: anchor(300, 104), screenPoint: CGPoint(x: 50, y: 96), context: context())
        #expect(event == .selectionChanged(level.id))
        #expect(editor.selectedID == level.id)
    }

    @Test("Tapping the selected drawing again reports nothing")
    func reselect() {
        var editor = DrawingEditor(drawings: [level])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        let second = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        #expect(second == nil)
        #expect(editor.selectedID == level.id)
    }

    @Test("Tapping empty space clears the selection once")
    func deselects() {
        var editor = DrawingEditor(drawings: [level])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())

        let miss = editor.tap(at: anchor(300, 20), screenPoint: CGPoint(x: 50, y: 180), context: context())
        #expect(miss == .selectionChanged(nil))
        #expect(editor.selectedID == nil)

        let again = editor.tap(at: anchor(300, 20), screenPoint: CGPoint(x: 50, y: 180), context: context())
        #expect(again == nil)
    }

    @Test("The topmost drawing wins when drawings overlap")
    func topmostWins() {
        let lower = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)])
        let upper = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)])
        var editor = DrawingEditor(drawings: [lower, upper])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        #expect(editor.selectedID == upper.id)
    }

    @Test("Switching selection between drawings reports the new id")
    func switchSelection() {
        let other = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 40)])
        var editor = DrawingEditor(drawings: [level, other])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        let event = editor.tap(at: anchor(300, 40), screenPoint: CGPoint(x: 50, y: 160), context: context())
        #expect(event == .selectionChanged(other.id))
    }

    @Test("Locked drawings can be selected")
    func lockedSelectable() {
        let locked = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)], isLocked: true)
        var editor = DrawingEditor(drawings: [locked])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        #expect(editor.selectedID == locked.id)
    }

    @Test("select(_:) selects an existing drawing and reports the change once")
    func programmaticSelect() {
        var editor = DrawingEditor(drawings: [level])
        let first = editor.select(level.id)
        #expect(first == .selectionChanged(level.id))
        #expect(editor.selectedID == level.id)
        let second = editor.select(level.id)
        #expect(second == nil)
    }

    @Test("select(nil) and select(unknown id) clear the selection")
    func programmaticDeselect() {
        var editor = DrawingEditor(drawings: [level])
        _ = editor.select(level.id)
        let cleared = editor.select(nil)
        #expect(cleared == .selectionChanged(nil))
        #expect(editor.selectedID == nil)

        _ = editor.select(level.id)
        let unknown = editor.select(UUID())
        #expect(unknown == .selectionChanged(nil))
        #expect(editor.selectedID == nil)
        let again = editor.select(UUID())
        #expect(again == nil)
    }

    @Test("Changing the selection cancels a drag in progress")
    func selectEndsDrag() {
        var editor = editorWithTrendLine(selected: true)
        let original = editor.drawings[0]
        let started = editor.beginDrag(at: screen(1_200, 50), context: context())
        #expect(started)
        _ = editor.select(nil)
        editor.drag(to: anchor(3_000, 10))
        #expect(editor.drawings == [original])
    }

    @Test("Drawings of an unregistered kind are not hit")
    func unknownKindNotHit() {
        let unknown = ChartDrawing(kind: "fibonacci", anchors: [anchor(3_000, 100)])
        var editor = DrawingEditor(drawings: [unknown])
        let event = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        #expect(event == nil)
        #expect(editor.selectedID == nil)
    }
}

@Suite("DrawingEditor snapping to the grid of the interval")
struct DrawingEditorGridTests {
    private func place(_ editor: inout DrawingEditor, at time: TimeInterval, interval: ChartInterval) {
        let context = DrawingContext(
            domain: ChartDomain(x: date(0)...date(6_000), y: 0...200),
            transform: transform,
            interval: interval
        )
        editor.tap(at: anchor(time, 10), screenPoint: .zero, context: context)
    }

    @Test("Anchors snap to the weeks of the interval: Monday by default, the day asked for otherwise")
    func weeklyGrid() {
        let monday = 1_699_833_600.0  // 2023-11-13 00:00 UTC
        let day = 86_400.0
        for (interval, expected) in [
            (ChartInterval.weeks(1), [monday, monday + 7 * day]),
            (ChartInterval.weeks(1, startingOn: .sunday), [monday - day, monday + 6 * day]),
        ] {
            var editor = DrawingEditor()
            editor.beginCreating(.horizontalLine)
            place(&editor, at: monday + 1.5 * day, interval: interval)  // a Tuesday noon: the start of its week is nearer
            editor.beginCreating(.horizontalLine)
            place(&editor, at: monday + 4.5 * day, interval: interval)  // a Friday noon: the start of the next week is nearer
            #expect(editor.drawings.map { $0.anchors[0].time } == expected.map(date))
        }
    }
}

@Suite("DrawingEditor dragging")
struct DrawingEditorDragTests {
    @Test("Dragging an anchor moves only that anchor, with time snapped")
    func dragAnchor() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        #expect(editor.selectedID == drawing.id)

        // first anchor sits at screen (200, 150)
        let began = editor.beginDrag(at: CGPoint(x: 202, y: 148), context: context())
        #expect(began)
        editor.drag(to: anchor(3_010, 80))
        #expect(editor.drawings[0].anchors == [anchor(3_000, 80), anchor(2_400, 150)])

        let event = editor.endDrag()
        var moved = drawing
        moved.anchors = [anchor(3_000, 80), anchor(2_400, 150)]
        #expect(event == .changed(moved))
        #expect(editor.drawings == [moved])
    }

    @Test("Dragging the second anchor leaves the first one alone")
    func dragSecondAnchor() {
        var editor = editorWithTrendLine(selected: true)
        // second anchor at screen (400, 50)
        let began = editor.beginDrag(at: CGPoint(x: 399, y: 52), context: context())
        #expect(began)
        editor.drag(to: anchor(3_600, 175))
        #expect(editor.drawings[0].anchors == [anchor(1_200, 50), anchor(3_600, 175)])
    }

    @Test("Dragging the body shifts every anchor by the travelled distance")
    func dragBody() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        // midpoint of the segment: time 1_800, price 100 -> screen (300, 100)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(began)
        editor.drag(to: anchor(2_400, 120)) // +600 s, +20
        #expect(editor.drawings[0].anchors == [anchor(1_800, 70), anchor(3_000, 170)])

        // keep dragging: the shift is measured from the grab, not accumulated
        editor.drag(to: anchor(1_800, 100))
        #expect(editor.drawings[0].anchors == trendAnchors)

        // returning to the start is not a change
        #expect(editor.endDrag() == nil)
        #expect(editor.drawings == [drawing])
    }

    @Test("Body drag snaps every anchor to the nearest bucket")
    func dragBodySnaps() {
        var editor = editorWithTrendLine(selected: true)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(began)
        // +620 s is closer to 600 s than to 660 s: 1_200 -> 1_800, 2_400 -> 3_000
        editor.drag(to: anchor(1_800 + 620, 100))
        #expect(editor.drawings[0].anchors == [anchor(1_800, 50), anchor(3_000, 150)])
        // +640 s is closer to 660 s
        editor.drag(to: anchor(1_800 + 640, 100))
        #expect(editor.drawings[0].anchors == [anchor(1_860, 50), anchor(3_060, 150)])
        // moving left by a fraction of a bar rounds symmetrically
        editor.drag(to: anchor(1_800 - 20, 100))
        #expect(editor.drawings[0].anchors == trendAnchors)
    }

    @Test("Body drag moves anchors that are off the grid by one shift: the shape of the drawing does not change")
    func dragBodyKeepsTheShapeOffTheGrid() {
        // Drawn on another interval: neither anchor is on the grid of a minute.
        let off = [anchor(1_220, 50), anchor(2_390, 150)]
        var editor = DrawingEditor(drawings: [ChartDrawing(kind: .trendLine, anchors: off)])
        _ = tap(&editor, 1_805, 100)
        let began = editor.beginDrag(at: screen(1_805, 100), context: context())
        #expect(began)

        // The first anchor goes to the nearest bucket start of 1_820 (1_800), the other one by the same 580 s.
        editor.drag(to: anchor(1_805 + 600, 100))
        let moved = editor.drawings[0].anchors
        #expect(moved == [anchor(1_800, 50), anchor(2_970, 150)])
        #expect(moved[1].time.timeIntervalSince(moved[0].time) == 1_170)

        // And again, further: the time between the anchors never changes.
        for travel in stride(from: -900.0, through: 900, by: 37) {
            editor.drag(to: anchor(1_805 + travel, 100))
            let anchors = editor.drawings[0].anchors
            #expect(anchors[1].time.timeIntervalSince(anchors[0].time) == 1_170)
            #expect(anchors[0].time.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
        }
    }

    @Test("A locked drawing cannot be dragged")
    func lockedDoesNotMove() {
        var editor = editorWithTrendLine(isLocked: true, selected: true)
        let drawing = editor.drawings[0]
        #expect(editor.selectedID == drawing.id)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(!began)
        editor.drag(to: anchor(2_400, 120))
        #expect(editor.endDrag() == nil)
        #expect(editor.drawings == [drawing])
    }

    @Test("Only the selected drawing can be dragged")
    func requiresSelection() {
        var editor = editorWithTrendLine(selected: false)
        let drawing = editor.drawings[0]
        #expect(editor.selectedID == nil)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(!began)
        editor.drag(to: anchor(2_400, 120))
        #expect(editor.drawings == [drawing])
    }

    @Test("A drag that starts away from the drawing is rejected")
    func missedDrag() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        let began = editor.beginDrag(at: CGPoint(x: 800, y: 20), context: context())
        #expect(!began)
        editor.drag(to: anchor(3_000, 10))
        #expect(editor.drawings == [drawing])
    }

    @Test("Ending a drag without moving reports nothing")
    func noMovement() {
        var editor = editorWithTrendLine(selected: true)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(began)
        #expect(editor.endDrag() == nil)
    }

    @Test("drag(to:) without a started drag does nothing")
    func dragWithoutBegin() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        editor.drag(to: anchor(3_000, 10))
        #expect(editor.endDrag() == nil)
        #expect(editor.drawings == [drawing])
    }

    @Test("A finished drag cannot be continued")
    func dragEnds() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(began)
        editor.drag(to: anchor(2_400, 120))
        _ = editor.endDrag()
        let moved = editor.drawings
        editor.drag(to: anchor(5_000, 10))
        #expect(editor.drawings == moved)
        #expect(moved != [drawing])
    }

    @Test("Dragging is not possible while a tool is active")
    func noDragWhileCreating() {
        var editor = editorWithTrendLine(selected: true)
        editor.beginCreating(.ray)
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(!began)
    }

    @Test("Dragging a horizontal line moves it vertically")
    func dragHorizontalLine() {
        let level = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)])
        var editor = DrawingEditor(drawings: [level])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        let began = editor.beginDrag(at: CGPoint(x: 50, y: 100), context: context())
        #expect(began)
        editor.drag(to: anchor(300, 130)) // same time, +30
        #expect(editor.drawings[0].anchors == [anchor(3_000, 130)])
        #expect(editor.endDrag() != nil)
    }
}

@Suite("DrawingEditor removal")
struct DrawingEditorRemovalTests {
    @Test("Removing a drawing reports it and clears its selection")
    func removeSelected() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        #expect(editor.remove(id: drawing.id) == .removed(drawing.id))
        #expect(editor.drawings.isEmpty)
        #expect(editor.selectedID == nil)
    }

    @Test("Removing another drawing keeps the selection")
    func removeOther() {
        let first = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 100)])
        let second = ChartDrawing(kind: .horizontalLine, anchors: [anchor(3_000, 40)])
        var editor = DrawingEditor(drawings: [first, second])
        _ = editor.tap(at: anchor(300, 100), screenPoint: CGPoint(x: 50, y: 100), context: context())
        #expect(editor.remove(id: second.id) == .removed(second.id))
        #expect(editor.drawings == [first])
        #expect(editor.selectedID == first.id)
    }

    @Test("Removing an unknown id does nothing")
    func removeUnknown() {
        var editor = editorWithTrendLine()
        let drawing = editor.drawings[0]
        #expect(editor.remove(id: UUID()) == nil)
        #expect(editor.drawings == [drawing])
    }

    @Test("A locked drawing can still be removed")
    func removeLocked() {
        var editor = editorWithTrendLine(isLocked: true)
        let drawing = editor.drawings[0]
        #expect(editor.remove(id: drawing.id) == .removed(drawing.id))
    }

    @Test("Removing the drawing being dragged ends the drag")
    func removeWhileDragging() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        let began = editor.beginDrag(at: CGPoint(x: 300, y: 100), context: context())
        #expect(began)
        _ = editor.remove(id: drawing.id)
        editor.drag(to: anchor(2_400, 120))
        #expect(editor.endDrag() == nil)
        #expect(editor.drawings.isEmpty)
    }

    @Test("removeAll clears drawings and selection")
    func removeAll() {
        var editor = editorWithTrendLine(selected: true)
        editor.removeAll()
        #expect(editor.drawings.isEmpty)
        #expect(editor.selectedID == nil)
    }

    @Test("setDrawings replaces the drawings and keeps a still-valid selection")
    func setDrawingsKeepsSelection() {
        var editor = editorWithTrendLine(selected: true)
        let drawing = editor.drawings[0]
        let extra = ChartDrawing(kind: .horizontalLine, anchors: [anchor(600, 10)])
        editor.setDrawings([extra, drawing])
        #expect(editor.drawings == [extra, drawing])
        #expect(editor.selectedID == drawing.id)
    }

    @Test("setDrawings drops a selection that no longer exists")
    func setDrawingsDropsSelection() {
        var editor = editorWithTrendLine(selected: true)
        let replacement = ChartDrawing(kind: .horizontalLine, anchors: [anchor(600, 10)])
        editor.setDrawings([replacement])
        #expect(editor.drawings == [replacement])
        #expect(editor.selectedID == nil)
    }

    @Test("Editors with the same state are equal")
    func equality() {
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [anchor(600, 10)])
        #expect(DrawingEditor(drawings: [drawing]) == DrawingEditor(drawings: [drawing]))
        #expect(DrawingEditor(drawings: [drawing]) != DrawingEditor())
    }
}
