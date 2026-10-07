import CoreGraphics
import Foundation
import Testing
import TradingChartCore

@Suite("ChartTransform")
struct ChartTransformTests {
    // plot: x 10...210, y 20...120; time 0...100 s; price 50...150
    private let transform = ChartTransform(
        plotRect: CGRect(x: 10, y: 20, width: 200, height: 100),
        timeRange: date(0)...date(100),
        priceRange: 50...150
    )

    @Test("Time maps linearly onto the horizontal extent")
    func timeToX() {
        #expect(transform.x(for: date(0)) == 10)
        #expect(transform.x(for: date(50)) == 110)
        #expect(transform.x(for: date(100)) == 210)
        #expect(transform.x(for: date(25)) == 60)
    }

    @Test("Price maps linearly onto the inverted vertical extent")
    func priceToY() {
        #expect(transform.y(for: 150) == 20)
        #expect(transform.y(for: 100) == 70)
        #expect(transform.y(for: 50) == 120)
        #expect(transform.y(for: 125) == 45)
    }

    @Test("Values outside the ranges map outside the plot")
    func outsideRanges() {
        #expect(transform.x(for: date(-50)) == -90)
        #expect(transform.x(for: date(150)) == 310)
        #expect(transform.y(for: 200) == -30)
        #expect(transform.y(for: 0) == 170)
    }

    @Test("Inverse mapping returns time and price")
    func inverse() {
        #expect(transform.time(atX: 110) == date(50))
        #expect(transform.time(atX: 10) == date(0))
        #expect(transform.price(atY: 70) == 100)
        #expect(transform.price(atY: 20) == 150)
        #expect(transform.price(atY: 120) == 50)
    }

    @Test("Anchor and point conversions round-trip")
    func roundTrip() {
        let anchors = [
            ChartAnchor(time: date(0), price: 50),
            ChartAnchor(time: date(37.5), price: 88.25),
            ChartAnchor(time: date(100), price: 150),
            ChartAnchor(time: date(-20), price: 170),
        ]
        for anchor in anchors {
            let restored = transform.anchor(at: transform.point(for: anchor))
            #expect(abs(restored.time.timeIntervalSince(anchor.time)) < 1e-9)
            #expect(abs(restored.price - anchor.price) < 1e-9)
        }
        #expect(transform.point(for: ChartAnchor(time: date(50), price: 100)) == CGPoint(x: 110, y: 70))
        #expect(transform.anchor(at: CGPoint(x: 110, y: 70)) == ChartAnchor(time: date(50), price: 100))
    }

    @Test("Screen-to-data-to-screen round trip")
    func screenRoundTrip() {
        for point in [CGPoint(x: 10, y: 20), CGPoint(x: 77.7, y: 33.3), CGPoint(x: 210, y: 120), CGPoint(x: 300, y: -40)] {
            let back = transform.point(for: transform.anchor(at: point))
            #expect(abs(back.x - point.x) < 1e-6)
            #expect(abs(back.y - point.y) < 1e-6)
        }
    }

    @Test("Degenerate ranges do not produce NaN")
    func degenerate() {
        let flat = ChartTransform(
            plotRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            timeRange: date(5)...date(5),
            priceRange: 10...10
        )
        #expect(flat.x(for: date(7)).isFinite)
        #expect(flat.y(for: 11).isFinite)
        let empty = ChartTransform(plotRect: .zero, timeRange: date(0)...date(10), priceRange: 0...1)
        #expect(empty.time(atX: 5) == date(0))
        #expect(empty.price(atY: 5) == 1)
    }
}
