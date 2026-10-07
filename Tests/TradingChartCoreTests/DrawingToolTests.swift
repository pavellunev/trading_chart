import CoreGraphics
import Foundation
import Testing
import TradingChartCore

private func anchor(_ seconds: TimeInterval, _ price: Double) -> ChartAnchor {
    ChartAnchor(time: date(seconds), price: price)
}

private let domain = ChartDomain(x: date(0)...date(1_000), y: 0...200)

@Suite("Built-in drawing tools")
struct BuiltInToolTests {
    @Test("Tools report their kind and anchor count")
    func metadata() {
        #expect(HorizontalLineTool().kind == .horizontalLine)
        #expect(HorizontalLineTool().requiredAnchorCount == 1)
        #expect(TrendLineTool().kind == .trendLine)
        #expect(TrendLineTool().requiredAnchorCount == 2)
        #expect(RayTool().kind == .ray)
        #expect(RayTool().requiredAnchorCount == 2)
    }

    @Test("Horizontal line is a single price line")
    func horizontalPrimitives() {
        let primitives = HorizontalLineTool().primitives(for: [anchor(300, 100)], in: domain)
        #expect(primitives == [.horizontalLine(price: 100)])
        #expect(HorizontalLineTool().primitives(for: [], in: domain).isEmpty)
    }

    @Test("Trend line is the segment between its anchors")
    func trendPrimitives() {
        let first = anchor(100, 50)
        let second = anchor(300, 150)
        #expect(TrendLineTool().primitives(for: [first, second], in: domain) == [.segment(first, second)])
        #expect(TrendLineTool().primitives(for: [first], in: domain).isEmpty)
    }

    @Test("A ray to the right extends to the end of the X domain")
    func rayRight() {
        // slope 10 / 100 s = 0.1 per second; at t = 1000: 50 + 0.1 * 900 = 140
        let start = anchor(100, 50)
        let primitives = RayTool().primitives(for: [start, anchor(200, 60)], in: domain)
        #expect(primitives == [.segment(start, anchor(1_000, 140))])
    }

    @Test("A ray to the left extends to the start of the X domain")
    func rayLeft() {
        // slope (60 - 50) / (400 - 500) = -0.1; at t = 0: 50 - 0.1 * (0 - 500) = 100
        let start = anchor(500, 50)
        let primitives = RayTool().primitives(for: [start, anchor(400, 60)], in: domain)
        #expect(primitives == [.segment(start, anchor(0, 100))])
    }

    @Test("A ray never ends before its second anchor")
    func rayBeyondDomain() {
        let start = anchor(900, 50)
        let primitives = RayTool().primitives(for: [start, anchor(1_200, 80)], in: domain)
        #expect(primitives == [.segment(start, anchor(1_200, 80))])
    }

    @Test("A vertical ray runs to the top or bottom of the Y domain")
    func rayVertical() {
        let start = anchor(100, 50)
        #expect(RayTool().primitives(for: [start, anchor(100, 80)], in: domain) == [.segment(start, anchor(100, 200))])
        #expect(RayTool().primitives(for: [start, anchor(100, 20)], in: domain) == [.segment(start, anchor(100, 0))])
    }

    @Test("A ray needs two anchors")
    func rayIncomplete() {
        #expect(RayTool().primitives(for: [anchor(1, 1)], in: domain).isEmpty)
    }
}

@Suite("DrawingTool hit testing")
struct HitTestTests {
    // 1 px = 1 s on X; y = 200 - price on Y
    private let transform = ChartTransform(
        plotRect: CGRect(x: 0, y: 0, width: 1_000, height: 200),
        timeRange: date(0)...date(1_000),
        priceRange: 0...200
    )

    private func hit(
        _ tool: some DrawingTool,
        _ point: CGPoint,
        anchors: [ChartAnchor],
        tolerance: CGFloat = 12
    ) -> DrawingHit? {
        tool.hitTest(point, anchors: anchors, domain: domain, transform: transform, tolerance: tolerance)
    }

    // Screen positions: first anchor (100, 150), second anchor (300, 50)
    private let trend = [anchor(100, 50), anchor(300, 150)]

    @Test("A point near an anchor hits that anchor")
    func anchorHit() {
        #expect(hit(TrendLineTool(), CGPoint(x: 105, y: 145), anchors: trend) == .anchor(0))
        #expect(hit(TrendLineTool(), CGPoint(x: 298, y: 52), anchors: trend) == .anchor(1))
    }

    @Test("The anchor radius is tolerance * 1.5")
    func anchorRadius() {
        // 17 px from the first anchor (inside 18), 19 px (outside 18)
        #expect(hit(TrendLineTool(), CGPoint(x: 117, y: 150), anchors: trend) == .anchor(0))
        // (119, 150) is 19 px from the anchor but only ~8.5 px from the line -> body
        #expect(hit(TrendLineTool(), CGPoint(x: 119, y: 150), anchors: trend) == .body)
    }

    @Test("A point on the stroke away from the anchors hits the body")
    func bodyHit() {
        // midpoint of the segment
        #expect(hit(TrendLineTool(), CGPoint(x: 200, y: 100), anchors: trend) == .body)
        // 8 px above the line vertically, ~7.2 px perpendicular
        #expect(hit(TrendLineTool(), CGPoint(x: 200, y: 108), anchors: trend) == .body)
    }

    @Test("A point far from the drawing misses")
    func miss() {
        // 30 px vertically, ~26.8 px perpendicular
        #expect(hit(TrendLineTool(), CGPoint(x: 200, y: 130), anchors: trend) == nil)
        #expect(hit(TrendLineTool(), CGPoint(x: 800, y: 10), anchors: trend) == nil)
    }

    @Test("The segment ends where its anchors are")
    func segmentEnds() {
        // On the extension of the line, beyond the second anchor, far from both anchors
        #expect(hit(TrendLineTool(), CGPoint(x: 400, y: 0), anchors: trend) == nil)
    }

    @Test("A smaller tolerance shrinks both radii")
    func smallTolerance() {
        #expect(hit(TrendLineTool(), CGPoint(x: 200, y: 108), anchors: trend, tolerance: 4) == nil)
        #expect(hit(TrendLineTool(), CGPoint(x: 200, y: 101), anchors: trend, tolerance: 4) == .body)
    }

    @Test("A horizontal line is hit anywhere along its price level")
    func horizontalLine() {
        let anchors = [anchor(500, 100)] // screen (500, 100)
        #expect(hit(HorizontalLineTool(), CGPoint(x: 50, y: 105), anchors: anchors) == .body)
        #expect(hit(HorizontalLineTool(), CGPoint(x: 900, y: 95), anchors: anchors) == .body)
        #expect(hit(HorizontalLineTool(), CGPoint(x: 50, y: 130), anchors: anchors) == nil)
        #expect(hit(HorizontalLineTool(), CGPoint(x: 505, y: 102), anchors: anchors) == .anchor(0))
    }

    @Test("A ray is hit along its extension up to the domain edge")
    func rayExtension() {
        // from (100, 50) through (200, 60); at t = 600 the price is 100 -> screen (600, 100)
        let anchors = [anchor(100, 50), anchor(200, 60)]
        #expect(hit(RayTool(), CGPoint(x: 600, y: 100), anchors: anchors) == .body)
        #expect(hit(RayTool(), CGPoint(x: 600, y: 140), anchors: anchors) == nil)
        // before the start of the ray
        #expect(hit(RayTool(), CGPoint(x: 20, y: 80), anchors: anchors) == nil)
    }

    @Test("A drawing with too few anchors only exposes its anchors")
    func incomplete() {
        let single = [anchor(100, 50)] // screen (100, 150)
        #expect(hit(TrendLineTool(), CGPoint(x: 101, y: 151), anchors: single) == .anchor(0))
        #expect(hit(TrendLineTool(), CGPoint(x: 400, y: 150), anchors: single) == nil)
    }

    @Test("A custom tool gets the default hit test for free")
    func customTool() {
        struct VerticalLineTool: DrawingTool {
            var kind: DrawingKind { "verticalLine" }
            var requiredAnchorCount: Int { 1 }
            func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
                anchors.first.map { [.verticalLine(time: $0.time)] } ?? []
            }
        }
        let anchors = [anchor(400, 100)] // screen (400, 100)
        #expect(hit(VerticalLineTool(), CGPoint(x: 405, y: 20), anchors: anchors) == .body)
        #expect(hit(VerticalLineTool(), CGPoint(x: 450, y: 20), anchors: anchors) == nil)
    }
}

@Suite("DrawingToolRegistry and drawing models")
struct RegistryTests {
    @Test("The standard registry has the three built-in tools")
    func standard() {
        let registry = DrawingToolRegistry.standard
        #expect(registry.tool(for: .horizontalLine)?.requiredAnchorCount == 1)
        #expect(registry.tool(for: .trendLine)?.requiredAnchorCount == 2)
        #expect(registry.tool(for: .ray)?.requiredAnchorCount == 2)
        #expect(registry.tool(for: "fibonacci") == nil)
    }

    @Test("Registering replaces a tool of the same kind and does not affect the standard registry")
    func register() {
        struct ThreePointTrend: DrawingTool {
            var kind: DrawingKind { .trendLine }
            var requiredAnchorCount: Int { 3 }
            func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] { [] }
        }
        var registry = DrawingToolRegistry.standard
        registry.register(ThreePointTrend())
        #expect(registry.tool(for: .trendLine)?.requiredAnchorCount == 3)
        #expect(registry.tool(for: .ray) != nil)
        #expect(DrawingToolRegistry.standard.tool(for: .trendLine)?.requiredAnchorCount == 2)
    }

    @Test("DrawingKind is expressible by string literal and encodes as a plain string")
    func kindCoding() throws {
        let kind: DrawingKind = "custom"
        #expect(kind.rawValue == "custom")
        #expect(DrawingKind.trendLine == "trendLine")
        #expect(DrawingKind(rawValue: "ray") == .ray)

        let data = try JSONEncoder().encode([DrawingKind.ray])
        #expect(String(decoding: data, as: UTF8.self) == #"["ray"]"#)
        #expect(try JSONDecoder().decode([DrawingKind].self, from: data) == [.ray])
    }

    @Test("ChartDrawing survives a Codable round trip")
    func drawingCoding() throws {
        let drawing = ChartDrawing(
            kind: .trendLine,
            anchors: [anchor(100, 1.5), anchor(200, 2.5)],
            style: DrawingStyle(color: ChartColor(red: 1, green: 0, blue: 0), lineWidth: 3, dash: [4, 2]),
            isLocked: true
        )
        let decoded = try JSONDecoder().decode(ChartDrawing.self, from: JSONEncoder().encode(drawing))
        #expect(decoded == drawing)
    }

    @Test("New drawings are unlocked with the default style")
    func drawingDefaults() {
        let drawing = ChartDrawing(kind: .ray, anchors: [])
        #expect(!drawing.isLocked)
        #expect(drawing.style == DrawingStyle())
        #expect(drawing.style.lineWidth == 1.5)
        #expect(drawing.style.dash.isEmpty)
        #expect(drawing.style.color == nil)
        #expect(ChartDrawing(kind: .ray, anchors: []).id != drawing.id)
    }
}

/// A tool that decides for itself what is under a finger: always the body, or never anything.
private struct FixedHitTool: DrawingTool {
    var kind: DrawingKind { "fixedHit" }
    var requiredAnchorCount: Int { 1 }
    var result: DrawingHit?

    func primitives(for anchors: [ChartAnchor], in domain: ChartDomain) -> [DrawingPrimitive] {
        anchors.first.map { [.horizontalLine(price: $0.price)] } ?? []
    }

    func hitTest(
        _ point: CGPoint,
        anchors: [ChartAnchor],
        domain: ChartDomain,
        transform: ChartTransform,
        tolerance: CGFloat
    ) -> DrawingHit? {
        result
    }
}

@Suite("A hit test of the host's own")
struct CustomHitTestTests {
    private let transform = ChartTransform(
        plotRect: CGRect(x: 0, y: 0, width: 1_000, height: 200),
        timeRange: date(0)...date(6_000),
        priceRange: 0...200
    )

    private func context(_ tool: FixedHitTool) -> DrawingContext {
        DrawingContext(
            registry: DrawingToolRegistry(tools: [tool]),
            domain: ChartDomain(x: date(0)...date(6_000), y: 0...200),
            transform: transform,
            interval: .minutes(1)
        )
    }

    private let drawing = ChartDrawing(kind: "fixedHit", anchors: [anchor(600, 100)])
    private let farAway = CGPoint(x: 900, y: 10)

    @Test("The editor asks the tool of the drawing, whatever the static type of the tool is")
    func editorUsesTheToolsOwnHitTest() {
        let tool = FixedHitTool(result: .body)
        var editor = DrawingEditor(drawings: [drawing])
        let event = editor.tap(at: transform.anchor(at: farAway), screenPoint: farAway, context: context(tool))
        // The default hit test would find nothing 800 points from the line.
        #expect(event == .selectionChanged(drawing.id))
        #expect(editor.selectedID == drawing.id)
        let began = editor.beginDrag(at: farAway, context: context(tool))
        #expect(began)
    }

    @Test("A tool that never hits cannot be selected, even right on its line")
    func neverHitting() {
        let tool = FixedHitTool(result: nil)
        var editor = DrawingEditor(drawings: [drawing])
        let onTheLine = transform.point(for: anchor(3_000, 100))
        #expect(editor.tap(at: anchor(3_000, 100), screenPoint: onTheLine, context: context(tool)) == nil)
        #expect(editor.selectedID == nil)
    }

    @Test("Through the protocol the built-in default is what a tool without its own gets")
    func defaultStillWorks() {
        let tool: any DrawingTool = HorizontalLineTool()
        let onTheLine = transform.point(for: anchor(3_000, 100))
        let hit = tool.hitTest(
            onTheLine,
            anchors: [anchor(600, 100)],
            domain: ChartDomain(x: date(0)...date(6_000), y: 0...200),
            transform: transform,
            tolerance: 12
        )
        #expect(hit == .body)
    }
}
