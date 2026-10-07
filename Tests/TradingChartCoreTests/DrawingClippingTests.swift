import Foundation
import Testing
import TradingChartCore

private func anchor(_ seconds: TimeInterval, _ price: Double) -> ChartAnchor {
    ChartAnchor(time: date(seconds), price: price)
}

// Window: time 1_000...2_000, price 100...200.
private let domain = ChartDomain(x: date(1_000)...date(2_000), y: 100...200)

private func closeEnough(_ lhs: ChartAnchor, _ rhs: ChartAnchor, tolerance: Double = 1e-6) -> Bool {
    abs(lhs.time.timeIntervalSince(rhs.time)) < tolerance && abs(lhs.price - rhs.price) < tolerance
}

private func expectClip(
    _ first: ChartAnchor,
    _ second: ChartAnchor,
    equals expected: (ChartAnchor, ChartAnchor)?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let result = domain.clip(first, second)
    switch (result, expected) {
    case (nil, nil):
        break
    case (let result?, let expected?):
        #expect(
            closeEnough(result.0, expected.0) && closeEnough(result.1, expected.1),
            "clipped to \(result), expected \(expected)",
            sourceLocation: sourceLocation
        )
    default:
        Issue.record("clipped to \(String(describing: result)), expected \(String(describing: expected))", sourceLocation: sourceLocation)
    }
}

@Suite("Segment clipping")
struct SegmentClippingTests {
    @Test("A segment inside the domain comes back unchanged")
    func inside() {
        let first = anchor(1_200, 120)
        let second = anchor(1_800, 180)
        let result = domain.clip(first, second)
        #expect(result?.0 == first)
        #expect(result?.1 == second)
    }

    @Test("A segment outside the domain is dropped")
    func outside() {
        expectClip(anchor(100, 120), anchor(900, 180), equals: nil)  // left of the window
        expectClip(anchor(2_100, 120), anchor(3_000, 180), equals: nil)  // right of it
        expectClip(anchor(1_200, 210), anchor(1_800, 300), equals: nil)  // above
        expectClip(anchor(1_200, 10), anchor(1_800, 90), equals: nil)  // below
    }

    @Test("A segment that crosses the left edge is cut there")
    func crossesLeft() {
        // The line from (500, 100) to (1500, 200) rises 0.1 per second: at t = 1000 the price is 150.
        expectClip(anchor(500, 100), anchor(1_500, 200), equals: (anchor(1_000, 150), anchor(1_500, 200)))
    }

    @Test("A segment that crosses the right edge is cut there")
    func crossesRight() {
        expectClip(anchor(1_500, 100), anchor(2_500, 200), equals: (anchor(1_500, 100), anchor(2_000, 150)))
    }

    @Test("A segment that crosses the top and the bottom is cut at both")
    func crossesVertically() {
        // from (1250, 0) to (1750, 300): price 100 at t = 1000 + ... slope 0.6 per s: 100 at 1416.67, 200 at 1583.33.
        expectClip(
            anchor(1_250, 0),
            anchor(1_750, 300),
            equals: (anchor(1_250 + 100 / 0.6, 100), anchor(1_250 + 200 / 0.6, 200))
        )
    }

    @Test("A segment that passes through the whole window is cut at both sides")
    func spansWindow() {
        expectClip(anchor(0, 150), anchor(3_000, 150), equals: (anchor(1_000, 150), anchor(2_000, 150)))
        expectClip(anchor(1_500, 0), anchor(1_500, 400), equals: (anchor(1_500, 100), anchor(1_500, 200)))
    }

    @Test("A diagonal that passes outside a corner of the domain is dropped")
    func missesCorner() {
        // Rising line through (0, 150) and (1000, 250): at the left edge of the window it is already above the top.
        expectClip(anchor(0, 150), anchor(1_000, 250), equals: nil)
        // The same line for a price at the left edge of the window that is exactly the top: it touches the corner.
        expectClip(anchor(0, 150), anchor(1_000, 200), equals: (anchor(1_000, 200), anchor(1_000, 200)))
    }

    @Test("A segment that only touches the border is kept")
    func touchesBorder() {
        let first = anchor(1_200, 200)
        let second = anchor(1_800, 200)
        let result = domain.clip(first, second)
        #expect(result?.0 == first)
        #expect(result?.1 == second)
        expectClip(anchor(500, 250), anchor(1_500, 150), equals: (anchor(1_000, 200), anchor(1_500, 150)))
    }

    @Test("The direction of the segment is preserved")
    func direction() {
        expectClip(anchor(1_500, 200), anchor(500, 100), equals: (anchor(1_500, 200), anchor(1_000, 150)))
        expectClip(anchor(2_500, 200), anchor(1_500, 100), equals: (anchor(2_000, 150), anchor(1_500, 100)))
    }

    @Test("A point inside is kept, a point outside is dropped")
    func degenerate() {
        let inside = anchor(1_500, 150)
        let result = domain.clip(inside, inside)
        #expect(result?.0 == inside)
        #expect(result?.1 == inside)
        expectClip(anchor(500, 150), anchor(500, 150), equals: nil)
    }

    @Test("Vertical and horizontal segments are handled")
    func axisAligned() {
        expectClip(anchor(1_500, 50), anchor(1_500, 150), equals: (anchor(1_500, 100), anchor(1_500, 150)))
        expectClip(anchor(900, 150), anchor(1_500, 150), equals: (anchor(1_000, 150), anchor(1_500, 150)))
        expectClip(anchor(900, 150), anchor(950, 150), equals: nil)
        expectClip(anchor(2_100, 50), anchor(2_100, 250), equals: nil)
    }

    @Test("Non-finite coordinates are rejected")
    func nonFinite() {
        #expect(domain.clip(anchor(1_200, .nan), anchor(1_800, 150)) == nil)
        #expect(domain.clip(anchor(1_200, 120), anchor(1_800, .infinity)) == nil)
    }

    @Test("A ray to the far end of a long series is cut to the window")
    func rayToEdgeOfSeries() {
        // The ray tool extends to the end of a series of 1_000_000 s: the renderer only gets the visible part.
        let series = ChartDomain(x: date(0)...date(1_000_000), y: -1_000_000...1_000_000)
        let primitives = RayTool().primitives(for: [anchor(1_200, 110), anchor(1_400, 130)], in: series)
        guard case .segment(let start, let end) = primitives.first else {
            Issue.record("expected a segment")
            return
        }
        // Slope 0.1 per second: it leaves the window through the right edge, at t = 2000 and price 190.
        let clipped = domain.clip(start, end)
        #expect(clipped?.0 == start)
        #expect(clipped.map { closeEnough($0.1, anchor(2_000, 190)) } == true)
    }

    @Test("Clipped ends lie on the segment and inside the domain, and nothing is dropped that would be visible")
    func randomized() {
        var generator = SplitMix(seed: 42)
        for _ in 0..<2_000 {
            let first = anchor(generator.next(in: -2_000...4_000), generator.next(in: -100...400))
            let second = anchor(generator.next(in: -2_000...4_000), generator.next(in: -100...400))
            let result = domain.clip(first, second)

            // Brute force: is any of 400 samples along the segment inside the domain?
            var sampleInside = false
            for step in 0...400 {
                let t = Double(step) / 400
                let time = first.time.timeIntervalSince1970 + (second.time.timeIntervalSince1970 - first.time.timeIntervalSince1970) * t
                let price = first.price + (second.price - first.price) * t
                if time >= 1_000, time <= 2_000, price >= 100, price <= 200 { sampleInside = true }
            }
            if sampleInside {
                #expect(result != nil)
            }
            guard let (start, end) = result else { continue }
            for point in [start, end] {
                #expect(point.time >= date(1_000 - 1e-6) && point.time <= date(2_000 + 1e-6))
                #expect(point.price >= 100 - 1e-6 && point.price <= 200 + 1e-6)
                // On the original line: the cross product of (point - first) and (second - first) vanishes.
                let ax = point.time.timeIntervalSince(first.time)
                let ay = point.price - first.price
                let bx = second.time.timeIntervalSince(first.time)
                let by = second.price - first.price
                #expect(abs(ax * by - ay * bx) < 1e-6 * Swift.max(1, abs(bx) * abs(by) + abs(ax) * abs(ay)))
            }
        }
    }
}

@Suite("Primitive clipping")
struct PrimitiveClippingTests {
    @Test("A segment primitive is clipped like the segment")
    func segment() {
        let primitive = DrawingPrimitive.segment(anchor(500, 100), anchor(1_500, 200))
        #expect(primitive.clipped(to: domain) == .segment(anchor(1_000, 150), anchor(1_500, 200)))
        #expect(DrawingPrimitive.segment(anchor(0, 0), anchor(500, 50)).clipped(to: domain) == nil)
    }

    @Test("A horizontal line is kept only inside the price range")
    func horizontal() {
        #expect(DrawingPrimitive.horizontalLine(price: 150).clipped(to: domain) == .horizontalLine(price: 150))
        #expect(DrawingPrimitive.horizontalLine(price: 100).clipped(to: domain) == .horizontalLine(price: 100))
        #expect(DrawingPrimitive.horizontalLine(price: 200).clipped(to: domain) == .horizontalLine(price: 200))
        #expect(DrawingPrimitive.horizontalLine(price: 99.9).clipped(to: domain) == nil)
        #expect(DrawingPrimitive.horizontalLine(price: 250).clipped(to: domain) == nil)
    }

    @Test("A vertical line is kept only inside the time range")
    func vertical() {
        #expect(DrawingPrimitive.verticalLine(time: date(1_500)).clipped(to: domain) == .verticalLine(time: date(1_500)))
        #expect(DrawingPrimitive.verticalLine(time: date(999)).clipped(to: domain) == nil)
        #expect(DrawingPrimitive.verticalLine(time: date(2_001)).clipped(to: domain) == nil)
    }
}

/// A small deterministic generator for the randomized test.
private struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Double(z % 1_000_000) / 999_999 * (range.upperBound - range.lowerBound)
    }
}
