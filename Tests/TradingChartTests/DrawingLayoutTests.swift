import CoreGraphics
import Foundation
import Testing
@testable import TradingChart

// A plot 400 x 200 points that shows 1_000...2_000 s and prices 100...200: 0.4 pt per second, 2 pt per price unit.
private let plot = CGRect(x: 0, y: 0, width: 400, height: 200)
private let transform = ChartTransform(plotRect: plot, timeRange: date(1_000)...date(2_000), priceRange: 100...200)
// The tools get the whole X domain of the series (here 0...10_000 s) and the price range that is shown.
private let domain = ChartDomain(x: date(0)...date(10_000), y: 100...200)

private func anchor(_ seconds: TimeInterval, _ price: Double) -> ChartAnchor {
    ChartAnchor(time: date(seconds), price: price)
}

private func frame(
    _ drawings: [ChartDrawing],
    selected: ChartDrawing? = nil,
    pending: [ChartAnchor] = [],
    registry: DrawingToolRegistry = .standard
) -> DrawingFrame {
    DrawingLayout.frame(
        drawings: drawings,
        selectedID: selected?.id,
        pendingAnchors: pending,
        registry: registry,
        domain: domain,
        transform: transform
    )
}

private func expectPoint(_ point: CGPoint, _ x: Double, _ y: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(point.x - x) < 1e-6 && abs(point.y - y) < 1e-6, "\(point) is not (\(x), \(y))", sourceLocation: sourceLocation)
}

@Suite("Drawing layout")
struct DrawingLayoutTests {
    @Test("a trend line inside the window is drawn between the screen points of its anchors")
    func trendLine() throws {
        let drawing = ChartDrawing(kind: .trendLine, anchors: [anchor(1_200, 120), anchor(1_800, 180)])
        let result = frame([drawing])
        let line = try #require(result.strokes.first?.lines.first)
        expectPoint(line.from, 80, 160)
        expectPoint(line.to, 320, 40)
        #expect(result.strokes.first?.handles.isEmpty == true)
        #expect(result.strokes.first?.isSelected == false)
    }

    @Test("a horizontal line crosses the whole plot at the screen Y of its price")
    func horizontalLine() throws {
        let drawing = ChartDrawing(kind: .horizontalLine, anchors: [anchor(50_000, 150)])
        let line = try #require(frame([drawing]).strokes.first?.lines.first)
        expectPoint(line.from, 0, 100)
        expectPoint(line.to, 400, 100)
    }

    @Test("a horizontal line outside the price range is not drawn")
    func horizontalLineOutside() {
        let above = ChartDrawing(kind: .horizontalLine, anchors: [anchor(1_500, 250)])
        let below = ChartDrawing(kind: .horizontalLine, anchors: [anchor(1_500, 50)])
        #expect(frame([above, below]).isEmpty)
    }

    @Test("a ray is cut where it leaves the price range, on the line through its anchors")
    func ray() throws {
        // Through (1_200, 110) and (1_400, 140): 0.15 per second. It runs to the end of the series (10_000 s), far outside.
        let drawing = ChartDrawing(kind: .ray, anchors: [anchor(1_200, 110), anchor(1_400, 140)])
        let line = try #require(frame([drawing]).strokes.first?.lines.first)
        expectPoint(line.from, 80, 180)
        // It reaches the top of the price range (200) at t = 1_200 + 600 = 1_800.
        expectPoint(line.to, 320, 0)
    }

    @Test("a shallow ray is cut at the right margin of the window")
    func shallowRay() throws {
        // 0.05 per second: at the margin (t = 2_100) the price is 110 + 0.05 * 900 = 155.
        let drawing = ChartDrawing(kind: .ray, anchors: [anchor(1_200, 110), anchor(1_400, 120)])
        let line = try #require(frame([drawing]).strokes.first?.lines.first)
        expectPoint(line.to, 440, 90)
    }

    @Test("a ray pointing right ends at the right margin of the window when it is flat")
    func flatRay() throws {
        let drawing = ChartDrawing(kind: .ray, anchors: [anchor(1_200, 150), anchor(1_400, 150)])
        let line = try #require(frame([drawing]).strokes.first?.lines.first)
        expectPoint(line.from, 80, 100)
        expectPoint(line.to, 440, 100)  // 2_000 s + 10 % of the window
    }

    @Test("a drawing entirely outside the window is not drawn")
    func outsideWindow() {
        let before = ChartDrawing(kind: .trendLine, anchors: [anchor(100, 120), anchor(500, 180)])
        let after = ChartDrawing(kind: .trendLine, anchors: [anchor(5_000, 120), anchor(6_000, 180)])
        #expect(frame([before, after]).isEmpty)
    }

    @Test("a segment that comes in from outside is cut at the window")
    func cutAtTheEdge() throws {
        // From far left (t = -1_000, price 100) to (t = 1_500, price 200): 0.04 per second, so 176 at t = 900 (the margin).
        let drawing = ChartDrawing(kind: .trendLine, anchors: [anchor(-1_000, 100), anchor(1_500, 200)])
        let line = try #require(frame([drawing]).strokes.first?.lines.first)
        expectPoint(line.from, -40, 48)
        expectPoint(line.to, 200, 0)
    }

    @Test("a selected drawing has handles on the anchors that are inside the plot")
    func handles() throws {
        let drawing = ChartDrawing(kind: .trendLine, anchors: [anchor(500, 120), anchor(1_800, 180)])
        let stroke = try #require(frame([drawing], selected: drawing).strokes.first)
        #expect(stroke.isSelected)
        #expect(stroke.handles.count == 1)  // the first anchor is 200 pt left of the plot
        expectPoint(stroke.handles[0], 320, 40)
    }

    @Test("a handle just outside the plot edge is still there, one far outside is not")
    func handleReach() throws {
        let near = ChartDrawing(kind: .horizontalLine, anchors: [anchor(990, 150)])  // 4 pt left of the plot
        let far = ChartDrawing(kind: .horizontalLine, anchors: [anchor(950, 150)])  // 20 pt left of it
        #expect(try #require(frame([near], selected: near).strokes.first).handles.count == 1)
        #expect(try #require(frame([far], selected: far).strokes.first).handles.isEmpty)
    }

    @Test("only the selected drawing has handles, and the style travels with the stroke")
    func selectionAndStyle() throws {
        let style = DrawingStyle(color: ChartColor(red: 1, green: 0, blue: 0), lineWidth: 3, dash: [5, 2])
        let first = ChartDrawing(kind: .horizontalLine, anchors: [anchor(1_500, 150)], style: style)
        let second = ChartDrawing(kind: .horizontalLine, anchors: [anchor(1_500, 120)])
        let result = frame([first, second], selected: second)
        #expect(result.strokes.map(\.id) == [first.id, second.id])
        #expect(result.strokes.map(\.isSelected) == [false, true])
        #expect(result.strokes[0].style == style)
        #expect(result.strokes[0].handles.isEmpty)
        #expect(result.strokes[1].handles.count == 1)
    }

    @Test("a selected drawing that is entirely outside the price range shows nothing")
    func selectedOutside() {
        let drawing = ChartDrawing(kind: .trendLine, anchors: [anchor(1_100, 120), anchor(1_200, 130)])
        let narrow = DrawingLayout.frame(
            drawings: [drawing],
            selectedID: drawing.id,
            pendingAnchors: [],
            registry: .standard,
            domain: domain,
            transform: ChartTransform(plotRect: plot, timeRange: date(1_000)...date(2_000), priceRange: 140...200)
        )
        #expect(narrow.isEmpty)
    }

    @Test("anchors placed so far are shown while a drawing is being created")
    func pendingAnchors() {
        let result = frame([], pending: [anchor(1_500, 150), anchor(5_000, 150)])
        #expect(result.pending.count == 1)  // the second is far outside the plot
        expectPoint(result.pending[0], 200, 100)
        #expect(!result.isEmpty)
    }

    @Test("drawings of an unregistered kind are skipped; later drawings keep their order")
    func unregistered() {
        let unknown = ChartDrawing(kind: "fibonacci", anchors: [anchor(1_500, 150)])
        let known = ChartDrawing(kind: .horizontalLine, anchors: [anchor(1_500, 150)])
        #expect(frame([unknown, known]).strokes.map(\.id) == [known.id])
    }

    @Test("the layout follows the window: the same drawing, scrolled, is at the new place")
    func followsTheWindow() throws {
        let drawing = ChartDrawing(kind: .trendLine, anchors: [anchor(1_200, 120), anchor(1_800, 180)])
        let scrolled = ChartTransform(plotRect: plot, timeRange: date(900)...date(1_900), priceRange: 100...200)
        let result = DrawingLayout.frame(
            drawings: [drawing],
            selectedID: nil,
            pendingAnchors: [],
            registry: .standard,
            domain: domain,
            transform: scrolled
        )
        let line = try #require(result.strokes.first?.lines.first)
        expectPoint(line.from, 120, 160)  // 100 s later in the window: 40 pt to the right
        expectPoint(line.to, 360, 40)
    }
}

@Suite("Tooltip and the price badge")
struct TooltipBadgeReachTests {
    @Test("the badge reaches into the plot only by the part wider than the price column")
    func reach() {
        #expect(TooltipPlacement.badgeReach(badgeWidth: 86, columnWidth: 60, showsChevron: false) == 26)
        #expect(TooltipPlacement.badgeReach(badgeWidth: 56, columnWidth: 60, showsChevron: false) == 0)
    }

    @Test("the return chevron makes the badge reach further")
    func chevron() {
        #expect(TooltipPlacement.badgeReach(badgeWidth: 86, columnWidth: 60, showsChevron: true) == 26 + TooltipPlacement.badgeChevronWidth)
        #expect(TooltipPlacement.badgeReach(badgeWidth: 60, columnWidth: 60, showsChevron: true) == TooltipPlacement.badgeChevronWidth)
        // A narrow badge is measured at the width of the column, so the chevron is counted in full: a safe overestimate.
        #expect(TooltipPlacement.badgeReach(badgeWidth: 56, columnWidth: 60, showsChevron: true) == TooltipPlacement.badgeChevronWidth - 4)
    }

    @Test("an unmeasured badge reaches nowhere")
    func unmeasured() {
        #expect(TooltipPlacement.badgeReach(badgeWidth: 0, columnWidth: 60, showsChevron: true) == 0)
    }
}
