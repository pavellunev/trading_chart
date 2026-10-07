import Foundation
import SwiftUI
import TradingChartCore

@available(iOS 17.0, *)
extension TradingChartModel {

    /// Why the render state is brought up to date.
    enum RenderRefresh {
        /// The window moved: the render window keeps its place while it is valid, the base Y domains while their
        /// transform is mild.
        case scrolling
        /// The window stopped moving: charts are laid out for the exact Y domains again.
        case settled
        /// The data, the zoom or the layout changed: everything is recomputed exactly.
        case structural
    }

    /// The time the window has to stand still before it counts as stopped.
    static let settleDelay: TimeInterval = 0.12

    /// The scroll position changed (by the chart or by the host), outside a batch.
    func scrollDidChange() {
        refreshRenderState(.scrolling)
        reportViewportEvents()
        scheduleSettle()
    }

    private func scheduleSettle() {
        isScrollActive = true
        guard !isSettlePending else { return }
        isSettlePending = true
        scrollClock.after(Self.settleDelay) { [weak self] in self?.settleTimerFired() }
    }

    private func settleTimerFired() {
        isSettlePending = false
        let idle = scrollClock.now() - lastScrollTime
        if idle >= Self.settleDelay - 0.002 {
            isScrollActive = false
            scrollVelocity = 0
            refreshRenderState(.settled)
            applyPendingDomainExpansion()
        } else {
            isSettlePending = true
            scrollClock.after(Self.settleDelay - idle) { [weak self] in self?.settleTimerFired() }
        }
    }

    /// Tracks how fast the window moves, in window widths per second.
    private func updateScrollVelocity() {
        let now = scrollClock.now()
        let dt = now - lastScrollTime
        if dt > 0.0005, dt < 0.1, visibleDuration > 0 {
            let instantaneous = scrollPosition.timeIntervalSince(lastScrollPosition) / dt / visibleDuration
            scrollVelocity = scrollVelocity * 0.5 + instantaneous * 0.5
        } else if dt >= 0.1 {
            scrollVelocity = 0
        }
        lastScrollTime = now
        lastScrollPosition = scrollPosition
    }

    /// Brings the render state in line with the window and the data. Every property is assigned only when its value
    /// changes, so a view is rebuilt only by a change of what it reads.
    func refreshRenderState(_ mode: RenderRefresh, dataChanged: Bool = false) {
        if mode == .scrolling { updateScrollVelocity() }
        let live = liveEdgeNow
        if live != isAtLiveEdge { isAtLiveEdge = live }

        let visible = visibleTimeRange
        let xDomain = naturalXDomain
        if mode != .scrolling, settledWindow != visible { settledWindow = visible }

        var windowMoved = false
        let buffer = configuration.renderBufferWindows
        let velocity = isScrollActive ? scrollVelocity : 0
        // A window is moved when the visible window nears its edge, when it is far wider than rest needs (after a zoom,
        // and once scrolling has stopped after a fling), and for a change of what it is made of (the series, the style).
        let tolerance = mode == .settled ? 1.3 : 2.4
        if !RenderWindowPolicy.isValid(renderWindow, visible: visible, bufferWindows: buffer, velocity: velocity)
            || RenderWindowPolicy.isTooWide(renderWindow, visible: visible, bufferWindows: buffer, tolerance: tolerance) {
            let desired = RenderWindowPolicy.window(for: visible, bufferWindows: buffer, velocity: velocity)
            if renderWindow != desired {
                renderWindow = desired
                windowMoved = true
                renderCounters.commits += 1
                renderCounters.windowMoves += 1
            }
        }
        if windowMoved || mode == .structural { refreshXTicks(xDomain: xDomain) }

        refreshMainYDomain(mode, visible: visible, xDomain: xDomain, windowMoved: windowMoved || dataChanged)
        refreshPaneDomains(mode, visible: visible, windowMoved: windowMoved || dataChanged)
    }

    private func refreshXTicks(xDomain: ClosedRange<Date>) {
        let lower = Swift.max(renderWindow.lowerBound, xDomain.lowerBound)
        let upper = Swift.min(renderWindow.upperBound, xDomain.upperBound)
        let interval = series.interval
        let ticks = lower <= upper
            ? TimeAxisTicks.values(
                in: lower...upper,
                visibleDuration: visibleDuration,
                interval: interval,
                desiredCount: interval.seconds < 86_400 ? 4 : 5
            )
            : []
        if ticks != xTicks { xTicks = ticks }
    }

    /// How far outside the window the centre of a bar can be and the bar still shows: half the width of its body (as the
    /// theme draws it, ``TradingChartTheme/candleBodyWidthFactor``) and a point and a half more (anti-aliasing, and the chart
    /// can trail the window by a pixel or two).
    var edgeMargin: TimeInterval {
        guard plotWidth > 0, visibleDuration > 0 else { return series.interval.seconds / 2 }
        let bodyWidth = ViewportMath.candleBodyWidth(
            plotWidth: plotWidth,
            visibleBars: visibleBars,
            factor: candleMetrics.bodyWidthFactor,
            min: candleMetrics.minBodyWidth,
            max: candleMetrics.maxBodyWidth
        )
        return (Double(bodyWidth) / 2 + 1.5) / Double(plotWidth) * visibleDuration
    }

    /// How far beyond the edge of the window a line is followed: a point and a half (the chart can trail the window by a pixel
    /// or two).
    var edgeSlack: TimeInterval {
        guard plotWidth > 0, visibleDuration > 0 else { return 0 }
        return 1.5 / Double(plotWidth) * visibleDuration
    }

    /// The same for the wick of a candle: half its width and a point and a half.
    var edgeWickMargin: TimeInterval {
        guard plotWidth > 0, visibleDuration > 0 else { return 0 }
        return (Double(candleMetrics.wickWidth) / 2 + 1.5) / Double(plotWidth) * visibleDuration
    }

    /// The autoscaled domain of the main pane for a window, and the price range it has to hold.
    func mainYExact(visible: ClosedRange<Date>, xDomain: ClosedRange<Date>) -> (extent: ClosedRange<Double>?, domain: ClosedRange<Double>) {
        let showsPrice = configuration.showsCurrentPriceLine || configuration.showsPriceBadge
        let overlays = indicators.compactMap { indicator in
            indicator.placement == .overlay ? indicatorOutputs[indicator.id] : nil
        }
        let extent = ViewportMath.yExtent(
            series: series,
            style: style,
            visibleRange: visible,
            currentPrice: showsPrice ? currentPrice : nil,
            xDomainUpperBound: xDomain.upperBound,
            additionalRanges: overlays.compactMap { $0.valueRange(in: visible) }
                + AutoscaleEdges.ranges(
                    series: series,
                    style: style,
                    overlays: overlays,
                    window: visible,
                    margin: edgeMargin,
                    wickMargin: edgeWickMargin,
                    slack: edgeSlack
                )
        )
        return (extent, ViewportMath.yDomain(for: extent, configuration: viewport))
    }

    private func refreshMainYDomain(_ mode: RenderRefresh, visible: ClosedRange<Date>, xDomain: ClosedRange<Date>, windowMoved: Bool) {
        let exact = mainYExact(visible: visible, xDomain: xDomain).domain
        if exact != mainYTarget { mainYTarget = exact }
        if rebaseNeeded(mode, base: mainYBase, target: exact, windowMoved: windowMoved),
           YTransformMath.base(for: exact) != mainYBase {
            mainYBase = YTransformMath.base(for: exact)
            renderCounters.commits += 1
            renderCounters.rebases += 1
        }
    }

    private func refreshPaneDomains(_ mode: RenderRefresh, visible: ClosedRange<Date>, windowMoved: Bool) {
        var states: [String: PaneRenderState] = [:]
        for indicator in indicators where indicator.placement == .pane {
            guard let output = indicatorOutputs[indicator.id], !output.isEmpty else { continue }
            let state = paneStates[indicator.id] ?? PaneRenderState()
            states[indicator.id] = state
            let exact = IndicatorRendering.paneYDomain(
                output: output,
                visibleRange: visible,
                paddingFraction: viewport.verticalPaddingFraction,
                edgeMargin: edgeMargin,
                edgeSlack: edgeSlack
            )
            if exact != state.yTarget { state.yTarget = exact }
            if rebaseNeeded(mode, base: state.yBase, target: exact, windowMoved: windowMoved),
               YTransformMath.base(for: exact) != state.yBase {
                state.yBase = YTransformMath.base(for: exact)
                renderCounters.commits += 1
                renderCounters.rebases += 1
            }
        }
        paneStates = states
    }

    /// Whether a chart laid out for `base` must be laid out again for `target`: when the render window moved or the data
    /// changed (the charts are laid out then anyway), once the transform gets too strong, and when scrolling stops
    /// unless the transform is negligible.
    private func rebaseNeeded(
        _ mode: RenderRefresh,
        base: ClosedRange<Double>,
        target: ClosedRange<Double>,
        windowMoved: Bool
    ) -> Bool {
        switch mode {
        case .structural, .scrolling: windowMoved || YTransformMath.needsRebase(base: base, target: target)
        case .settled: !YTransformMath.isNearIdentity(base: base, target: target)
        }
    }

    /// The state of the pane of an indicator (created on first use).
    func paneState(for indicatorID: String) -> PaneRenderState {
        if let state = paneStates[indicatorID] { return state }
        let state = PaneRenderState()
        paneStates[indicatorID] = state
        return state
    }
}
