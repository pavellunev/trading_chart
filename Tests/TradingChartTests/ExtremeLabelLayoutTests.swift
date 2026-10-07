import CoreGraphics
import Foundation
import Testing
@testable import TradingChart

/// The labels of the highest and the lowest price keep clear of the price badge: decided on rectangles.
@Suite("High/low label layout")
struct ExtremeLabelLayoutTests {
    private let plot = CGRect(x: 0, y: 0, width: 300, height: 300)
    private let label = CGSize(width: 50, height: 12)

    @Test("with nothing in the way the mark goes to the preferred side: a line of 12 points, 2 points of space, the text")
    func freePlacement() throws {
        let left = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 200, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: []
        ))
        #expect(left.goesLeft)
        #expect(left.lineEnd == CGPoint(x: 188, y: 100))
        #expect(left.labelRect == CGRect(x: 136, y: 94, width: 50, height: 12))
        #expect(left.markRect == CGRect(x: 136, y: 94, width: 64, height: 12))

        let right = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 100, y: 100), labelSize: label, prefersLeft: false, plot: plot, avoiding: []
        ))
        #expect(!right.goesLeft)
        #expect(right.lineEnd == CGPoint(x: 112, y: 100))
        #expect(right.labelRect == CGRect(x: 114, y: 94, width: 50, height: 12))
        #expect(right.markRect == CGRect(x: 100, y: 94, width: 64, height: 12))
    }

    @Test("an obstacle that is not near leaves the mark where it is")
    func farObstacle() throws {
        let badge = CGRect(x: 280, y: 90, width: 56, height: 20)
        let placement = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 200, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: [badge]
        ))
        #expect(placement.goesLeft)
    }

    @Test("a badge over the preferred side sends the mark to the other side")
    func flips() throws {
        // The bar is just left of the badge, the label to its right would run under the badge: it goes left.
        let badge = CGRect(x: 250, y: 90, width: 56, height: 20)
        let toTheRight = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 200, y: 100), labelSize: label, prefersLeft: false, plot: plot, avoiding: [badge]
        ))
        #expect(toTheRight.goesLeft)
        #expect(toTheRight.markRect.maxX <= 200)

        // The other way round: the preferred side is left, the badge sits on the left of the bar.
        let leftBadge = CGRect(x: 120, y: 90, width: 56, height: 20)
        let toTheLeft = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 200, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: [leftBadge]
        ))
        #expect(!toTheLeft.goesLeft)
    }

    @Test("when both sides are taken the mark is left out")
    func bothTaken() {
        // The bar is under the badge itself, as when the price is at the high.
        let badge = CGRect(x: 180, y: 90, width: 120, height: 20)
        #expect(ExtremeLabelLayout.place(
            at: CGPoint(x: 240, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: [badge]
        ) == nil)
        #expect(ExtremeLabelLayout.place(
            at: CGPoint(x: 240, y: 100), labelSize: label, prefersLeft: false, plot: plot, avoiding: [badge]
        ) == nil)
    }

    @Test("the mark keeps 2 points clear of an obstacle: at exactly that distance it stays, closer it moves")
    func clearance() {
        // The mark on the left spans x 136...200 and y 94...106; the obstacle is above it and ends before x 200, so that the
        // right side is free in every case.
        func goesLeft(obstacleBottom: CGFloat) -> Bool? {
            let obstacle = CGRect(x: 120, y: obstacleBottom - 20, width: 70, height: 20)
            return ExtremeLabelLayout.place(
                at: CGPoint(x: 200, y: 100), labelSize: CGSize(width: 50, height: 12), prefersLeft: true, plot: plot, avoiding: [obstacle]
            )?.goesLeft
        }
        #expect(goesLeft(obstacleBottom: 80) == true)  // well clear
        #expect(goesLeft(obstacleBottom: 92) == true)  // exactly the clearance away: stays
        #expect(goesLeft(obstacleBottom: 92.5) == false)  // closer than the clearance: the other side
        #expect(goesLeft(obstacleBottom: 94) == false)  // touching the mark
        #expect(goesLeft(obstacleBottom: 110) == false)  // over it
    }

    @Test("a side that would stick out of the plot is taken only when the other one is not free")
    func plotBounds() throws {
        // A bar near the left edge, the preferred side (left) does not fit in the plot: the right side is chosen.
        let right = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 20, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: []
        ))
        #expect(!right.goesLeft)

        // Both stick out (a plot too narrow): the preferred side is kept.
        let narrow = CGRect(x: 0, y: 0, width: 60, height: 300)
        let kept = try #require(ExtremeLabelLayout.place(
            at: CGPoint(x: 30, y: 100), labelSize: label, prefersLeft: true, plot: narrow, avoiding: []
        ))
        #expect(kept.goesLeft)

        // The side that fits is blocked by the badge: the one that sticks out is still better than none.
        let badge = CGRect(x: 40, y: 90, width: 60, height: 20)
        let sticking = ExtremeLabelLayout.place(
            at: CGPoint(x: 20, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: [badge]
        )
        #expect(sticking?.goesLeft == true)
    }

    @Test("several obstacles all count: each can take one side")
    func severalObstacles() {
        let leftSide = CGRect(x: 150, y: 90, width: 20, height: 20)
        let rightSide = CGRect(x: 210, y: 90, width: 20, height: 20)
        func place(_ obstacles: [CGRect]) -> ExtremeLabelLayout.Placement? {
            ExtremeLabelLayout.place(at: CGPoint(x: 200, y: 100), labelSize: label, prefersLeft: true, plot: plot, avoiding: obstacles)
        }
        #expect(place([leftSide])?.goesLeft == false)
        #expect(place([rightSide])?.goesLeft == true)
        #expect(place([leftSide, rightSide]) == nil)
    }

    // MARK: - The badge rectangle

    @Test("the badge sits at the right edge of the pane, centred on the price, pressed into the plot at the edges")
    func badgeRect() {
        let size = CGSize(width: 76, height: 20)
        let middle = PriceBadgeLayout.rect(size: size, priceY: 150, plotHeight: 300, chartWidth: 376)
        #expect(middle == CGRect(x: 300, y: 140, width: 76, height: 20))

        let top = PriceBadgeLayout.rect(size: size, priceY: -50, plotHeight: 300, chartWidth: 376)
        #expect(top.midY == PriceBadgeLayout.edgeInset)
        let bottom = PriceBadgeLayout.rect(size: size, priceY: 900, plotHeight: 300, chartWidth: 376)
        #expect(bottom.midY == 300 - PriceBadgeLayout.edgeInset)
        #expect(PriceBadgeLayout.centerY(priceY: 5, plotHeight: 8) == PriceBadgeLayout.edgeInset)
    }

    @Test("the case of the report: a high near the right edge with the badge reaching into the plot above it")
    func overBadge() throws {
        // A plot 317 wide and a pane 377 wide; the badge (84 by 20, a long price) at the top of the plot reaches 24 points
        // into the plot (x 293...377, y 10...30).
        let plot = CGRect(x: 0, y: 0, width: 317, height: 368)
        let badge = PriceBadgeLayout.rect(size: CGSize(width: 84, height: 20), priceY: 20, plotHeight: 368, chartWidth: 377)
        #expect(badge == CGRect(x: 293, y: 10, width: 84, height: 20))
        let size = CGSize(width: 44, height: 12)
        func place(_ point: CGPoint, left: Bool, avoiding obstacles: [CGRect]) -> ExtremeLabelLayout.Placement? {
            ExtremeLabelLayout.place(at: point, labelSize: size, prefersLeft: left, plot: plot, avoiding: obstacles)
        }

        // The bar is under the badge: the mark would run into it on either side, so it is left out.
        let under = CGPoint(x: 300, y: 24)
        #expect(place(under, left: true, avoiding: []) != nil)
        #expect(place(under, left: true, avoiding: [badge]) == nil)

        // Left of the badge by more than the clearance: unchanged. By less: the mark would touch it, and goes to the right
        // side, which is under the badge as well, so it is left out.
        #expect(place(CGPoint(x: 280, y: 24), left: true, avoiding: [badge])?.goesLeft == true)
        #expect(place(CGPoint(x: 292, y: 24), left: true, avoiding: [badge]) == nil)

        // At another height the same bar is not in the way.
        #expect(place(CGPoint(x: 300, y: 200), left: true, avoiding: [badge])?.goesLeft == true)
    }
}
