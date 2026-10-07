import CoreGraphics
import Foundation
import TradingChartCore

/// Scrolling by touch.
///
/// The chart does not scroll by itself: Swift Charts' own scroll gesture loses its place when the view it sits in is
/// transformed on every frame (which is how the autoscale reaches the screen, see ``YTransformMath``): the position it reports
/// jumps to the start of the series and back while a fling runs, and the panes show different windows. So the charts only
/// follow ``scrollPosition`` (the binding of ``chartScrollBinding`` moves them), and a transparent layer over each pane
/// (``ChartInputLayer``) takes the finger: it moves the window while the finger drags, and the model keeps it going after the
/// finger lifts. Everything here is in chart time, so a prepend, a trim or a zoom in the middle of a fling does not disturb it.
@available(iOS 17.0, *)
extension TradingChartModel {

    /// The positions the window can be scrolled to by touch: from the first bar (the start of the time domain without the
    /// reserve, see ``chartXDomain``) to the last position at which the window is still full (the live edge). Bars that the
    /// charts' domain does not hold yet (history prepended beyond the reserve while the window moved) are not in it.
    var touchScrollRange: ClosedRange<Date> {
        let domain = naturalXDomain
        let lower = Swift.max(domain.lowerBound, chartDomainStart ?? domain.lowerBound)
        let upper = domain.upperBound.addingTimeInterval(-visibleDuration)
        return lower...Swift.max(upper, lower)
    }

    private func clampedForTouchScroll(_ position: Date) -> Date {
        let range = touchScrollRange
        return Swift.min(Swift.max(position, range.lowerBound), range.upperBound)
    }

    /// Sets the position as the finger or the fling does, without that counting as an outside change (which would stop a fling).
    private func driveScroll(to position: Date) {
        guard position != scrollPosition else { return }
        isDrivingScroll = true
        scrollPosition = position
        isDrivingScroll = false
    }

    /// A finger went down and started to drag: stops a fling and remembers the window.
    func beginTouchScroll() {
        stopScrollMomentum()
        touchScrollStart = scrollPosition
    }

    /// The finger moved `translation` points to the right since the drag began: the window shows earlier times.
    ///
    /// A chart without bars does not scroll: there is no time to scroll along (the window of an empty series is laid out around
    /// ``scrollPosition`` itself, so every step would move it).
    func touchScroll(translation: CGFloat, plotWidth: CGFloat) {
        guard let start = touchScrollStart, !series.isEmpty, plotWidth > 0, visibleDuration > 0 else { return }
        let shift = -Double(translation) / Double(plotWidth) * visibleDuration
        driveScroll(to: clampedForTouchScroll(start.addingTimeInterval(shift)))
    }

    /// The finger lifted at `velocity` points per second (positive to the right): the window keeps going.
    func endTouchScroll(velocity: CGFloat, plotWidth: CGFloat) {
        touchScrollStart = nil
        // History that arrived while the finger was down may have to extend the domain now that the finger is up.
        defer { applyPendingDomainExpansion() }
        guard !series.isEmpty, plotWidth > 0, visibleDuration > 0,
              abs(Double(velocity)) >= ScrollDeceleration.minimumStartSpeed
        else { return }
        let chartVelocity = -Double(velocity) / Double(plotWidth) * visibleDuration
        // Already at the end it is heading for: nothing to do.
        let range = touchScrollRange
        if (chartVelocity > 0 && scrollPosition >= range.upperBound) || (chartVelocity < 0 && scrollPosition <= range.lowerBound) {
            return
        }
        // One fling at a time: a second one (another pane's finger lifting) must not leave the first one's ticker running.
        stopScrollMomentum()
        scrollMomentum = ScrollMomentum(start: scrollPosition, velocity: chartVelocity)
        scrollMomentumPlotWidth = Double(plotWidth)
        cancelMomentumTicker = frameTicker.start { [weak self] delta in
            self?.advanceMomentum(by: delta) ?? false
        }
    }

    /// The finger was taken away without a fling (a second finger, a long press).
    func cancelTouchScroll() {
        touchScrollStart = nil
        applyPendingDomainExpansion()
    }

    /// Stops the fling, if there is one.
    func stopScrollMomentum() {
        scrollMomentum = nil
        cancelMomentumTicker?()
        cancelMomentumTicker = nil
    }

    /// Moves the window along the fling by `delta` seconds (called once per display frame).
    ///
    /// - Returns: Whether the fling goes on; `false` once it has ended, or when there was none.
    @discardableResult
    func advanceMomentum(by delta: TimeInterval) -> Bool {
        guard var momentum = scrollMomentum else { return false }
        momentum.elapsed += delta
        let travelled = ScrollDeceleration.distance(velocity: momentum.velocity, elapsed: momentum.elapsed)
        let target = momentum.start.addingTimeInterval(travelled)
        let clamped = clampedForTouchScroll(target)
        driveScroll(to: clamped)
        let pointsPerSecond = abs(ScrollDeceleration.speed(velocity: momentum.velocity, elapsed: momentum.elapsed))
            / Swift.max(visibleDuration, 1) * scrollMomentumPlotWidth
        if clamped != target || pointsPerSecond < ScrollDeceleration.stopSpeed {
            stopScrollMomentum()
            return false
        }
        scrollMomentum = momentum
        return true
    }

    /// Puts the crosshair at the time under `x` points from the left edge of the plot.
    func touchCrosshair(atX x: CGFloat, plotWidth: CGFloat) {
        guard configuration.isCrosshairEnabled, plotWidth > 0 else { return }
        let fraction = Swift.min(Swift.max(Double(x) / Double(plotWidth), 0), 1)
        crosshairTime = visibleTimeRange.lowerBound.addingTimeInterval(fraction * visibleDuration)
    }

    /// Takes the crosshair away.
    func clearTouchCrosshair() {
        if crosshairTime != nil { crosshairTime = nil }
    }
}
