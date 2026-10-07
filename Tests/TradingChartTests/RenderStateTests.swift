import Foundation
import Observation
import Testing
@_spi(Diagnostics) @testable import TradingChart

// MARK: - Pure functions

@Suite("Render window policy")
struct RenderWindowPolicyTests {
    private let visible = date(1_000)...date(1_100)  // 100 s wide

    @Test("at rest the window has the buffer on both sides")
    func atRest() {
        let window = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 0)
        #expect(window == date(900)...date(1_200))
        #expect(RenderWindowPolicy.window(for: visible, bufferWindows: 0, velocity: 0) == visible)
    }

    @Test("a moving window gets more of the buffer ahead of the motion")
    func leadsTheMotion() {
        let forward = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 4)
        let backward = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: -4)
        #expect(forward.upperBound.timeIntervalSince(visible.upperBound) > visible.lowerBound.timeIntervalSince(forward.lowerBound))
        #expect(backward.lowerBound.timeIntervalSince(visible.lowerBound) < visible.upperBound.timeIntervalSince(backward.upperBound) * -1)
        // The buffer follows the motion without growing beyond the effective buffer.
        let width = RenderWindowPolicy.effectiveBuffer(1, velocity: 4) * 2 * 100 + 100
        #expect(abs(forward.upperBound.timeIntervalSince(forward.lowerBound) - width) < 1e-9)
    }

    @Test("a fling doubles the buffer, a slow scroll part of it")
    func effectiveBuffer() {
        #expect(RenderWindowPolicy.effectiveBuffer(1, velocity: 0) == 1)
        #expect(RenderWindowPolicy.effectiveBuffer(1, velocity: 1) == 1.5)
        #expect(RenderWindowPolicy.effectiveBuffer(1, velocity: 2) == 2)
        #expect(RenderWindowPolicy.effectiveBuffer(1, velocity: -9) == 2)
        #expect(RenderWindowPolicy.effectiveBuffer(0, velocity: 5) == 0)
    }

    @Test("a window is valid while the visible window keeps a margin from its edges")
    func validity() {
        let window = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 0)
        #expect(RenderWindowPolicy.isValid(window, visible: visible, bufferWindows: 1, velocity: 0))
        // 0.74 windows to the right: 0.26 left of buffer on the right side, still more than the 0.25 margin
        let nearly = date(1_074)...date(1_174)
        #expect(RenderWindowPolicy.isValid(window, visible: nearly, bufferWindows: 1, velocity: 0))
        let tooFar = date(1_076)...date(1_176)
        #expect(!RenderWindowPolicy.isValid(window, visible: tooFar, bufferWindows: 1, velocity: 0))
        // Outside altogether.
        #expect(!RenderWindowPolicy.isValid(window, visible: date(2_000)...date(2_100), bufferWindows: 1, velocity: 0))
    }

    @Test("a fast window needs more room ahead of it")
    func validityAhead() {
        let window = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 0)
        let ahead = date(1_050)...date(1_150)  // margin 0.5 windows on the right
        #expect(RenderWindowPolicy.isValid(window, visible: ahead, bufferWindows: 1, velocity: 0))
        // At 5 windows per second the margin to keep ahead is 0.6 s * 1 window.
        #expect(!RenderWindowPolicy.isValid(window, visible: ahead, bufferWindows: 1, velocity: 5))
        // The same speed in the other direction looks at the left margin, which is 1.5 windows.
        #expect(RenderWindowPolicy.isValid(window, visible: ahead, bufferWindows: 1, velocity: -5))
    }

    @Test("without a buffer the window is valid only while it does not move")
    func noBuffer() {
        let window = RenderWindowPolicy.window(for: visible, bufferWindows: 0, velocity: 0)
        #expect(RenderWindowPolicy.isValid(window, visible: visible, bufferWindows: 0, velocity: 0))
        #expect(!RenderWindowPolicy.isValid(window, visible: date(1_001)...date(1_101), bufferWindows: 0, velocity: 0))
    }

    @Test("a window much wider than rest needs is too wide")
    func tooWide() {
        let window = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 0)
        #expect(!RenderWindowPolicy.isTooWide(window, visible: visible, bufferWindows: 1, tolerance: 1.3))
        let fling = RenderWindowPolicy.window(for: visible, bufferWindows: 1, velocity: 3)
        #expect(RenderWindowPolicy.isTooWide(fling, visible: visible, bufferWindows: 1, tolerance: 1.3))
        #expect(!RenderWindowPolicy.isTooWide(fling, visible: visible, bufferWindows: 1, tolerance: 2.4))
        // After zooming in by 5 the same window is far too wide for the new visible window.
        #expect(RenderWindowPolicy.isTooWide(window, visible: date(1_000)...date(1_020), bufferWindows: 1, tolerance: 2.4))
    }
}

@Suite("Y transform math")
struct YTransformMathTests {
    @Test("a chart laid out for a target needs no transform")
    func rebasedIsIdentity() {
        let target = 100.0...120.0
        let base = YTransformMath.base(for: target)
        #expect(base.upperBound - base.lowerBound == (target.upperBound - target.lowerBound) * YTransformMath.frameRatio)
        #expect(YTransformMath.covers(base: base, target: target))
        let parameters = YTransformMath.parameters(base: base, target: target)
        #expect(abs(parameters.scale - 1) < 1e-12)
        #expect(abs(parameters.offset + YTransformMath.margin) < 1e-12)
        #expect(YTransformMath.isNearIdentity(base: base, target: target))
        #expect(!YTransformMath.needsRebase(base: base, target: target))
    }

    /// The Y of a price on the screen: laid out in the chart (`frameRatio` plot heights tall, base domain), then scaled about
    /// the top and moved, as ``YTransform`` does.
    private func shown(_ value: Double, base: ClosedRange<Double>, target: ClosedRange<Double>, plotHeight: Double) -> Double {
        let chartY = YMapping(domain: base, height: plotHeight * YTransformMath.frameRatio).y(of: value)
        let parameters = YTransformMath.parameters(base: base, target: target)
        return parameters.scale * Double(chartY) + plotHeight * parameters.offset
    }

    @Test("the transform puts every price where the target domain puts it")
    func mapsLikeTheTarget() {
        let plotHeight = 280.0
        let base = YTransformMath.base(for: 100.0...120.0)
        // Shifted up and down, narrower and wider, all inside the base.
        let targets: [ClosedRange<Double>] = [100...120, 105...125, 92...112, 101...115, 96...126, 90...130]
        for target in targets {
            #expect(YTransformMath.covers(base: base, target: target))
            let mapping = YMapping(domain: target, height: CGFloat(plotHeight))
            for value in stride(from: 90.0, through: 130.0, by: 2.5) {
                let expected = Double(mapping.y(of: value))
                #expect(abs(shown(value, base: base, target: target, plotHeight: plotHeight) - expected) < 1e-9)
            }
        }
    }

    @Test("a chart is laid out again when the target leaves its domain or the scale drifts")
    func needsRebase() {
        let base = YTransformMath.base(for: 100.0...120.0)  // 80...140
        #expect(!YTransformMath.needsRebase(base: base, target: 110...130))
        #expect(!YTransformMath.needsRebase(base: base, target: 98...122))
        #expect(YTransformMath.needsRebase(base: base, target: 70...90))      // left the base
        #expect(YTransformMath.needsRebase(base: base, target: 125...145))    // left the base above
        #expect(YTransformMath.needsRebase(base: base, target: 100...105))    // scale 4 / 1
        #expect(YTransformMath.needsRebase(base: base, target: 82...138))     // scale 60 / 112
    }

    @Test("scrolling stops: a transform that is not the identity is laid out again")
    func restTolerance() {
        let base = YTransformMath.base(for: 100.0...120.0)
        #expect(YTransformMath.isNearIdentity(base: base, target: 100...120))
        #expect(!YTransformMath.isNearIdentity(base: base, target: 100.5...120.5))
        #expect(!YTransformMath.isNearIdentity(base: base, target: 100...121))
    }

    @Test("degenerate domains leave the chart alone")
    func degenerate() {
        let parameters = YTransformMath.parameters(base: 5...5, target: 1...2)
        #expect(parameters.scale == 1)
        #expect(YTransformMath.parameters(base: 0...10, target: 3...3).scale == 1)
    }
}

@Suite("Y axis ticks")
struct YAxisTicksTests {
    @Test("round values inside the domain, about the desired number")
    func roundValues() {
        #expect(YAxisTicks.values(in: 120.4...122.2, desiredCount: 5) == [120.5, 121, 121.5, 122])
        #expect(YAxisTicks.values(in: -8...108, desiredCount: 3) == [0, 50, 100])
        #expect(YAxisTicks.values(in: -150...320, desiredCount: 3) == [0, 200])
    }

    @Test("every tick is inside the domain, ascending, and there are about as many as asked for")
    func properties() {
        var domain = 0.0...1.0
        for step in 0..<200 {
            let lower = Double(step) * 0.37 - 20
            let span = pow(10, Double(step % 9) - 4) * (1 + Double(step % 7))
            domain = lower...(lower + span)
            for desired in [3, 5] {
                let ticks = YAxisTicks.values(in: domain, desiredCount: desired)
                #expect(!ticks.isEmpty)
                #expect(ticks.count <= desired + 2)
                #expect(ticks == ticks.sorted())
                #expect(ticks.allSatisfy { domain.contains($0) })
            }
        }
    }

    @Test("a degenerate domain has no ticks")
    func degenerate() {
        #expect(YAxisTicks.values(in: 5...5, desiredCount: 5).isEmpty)
        #expect(YAxisTicks.values(in: 0...10, desiredCount: 0).isEmpty)
    }

    @Test("the prices map to Y from the top of the plot")
    func mapping() {
        let mapping = YMapping(domain: 100...200, height: 400)
        #expect(mapping.y(of: 200) == 0)
        #expect(mapping.y(of: 100) == 400)
        #expect(mapping.y(of: 150) == 200)
        #expect(mapping.y(of: 250) == -200)
    }
}

// MARK: - Model

/// A clock the test advances by hand, and the timers set on it.
@MainActor
final class ManualClock {
    var time: TimeInterval = 1_000
    private var pending: [(due: TimeInterval, work: @MainActor () -> Void)] = []

    var scrollClock: ScrollClock {
        ScrollClock(
            now: { self.time },
            after: { delay, work in self.pending.append((self.time + delay, work)) }
        )
    }

    /// Moves the time on and runs the timers that came due.
    func advance(by seconds: TimeInterval) {
        time += seconds
        let due = pending.filter { $0.due <= time }
        pending.removeAll { $0.due <= time }
        for item in due { item.work() }
    }

    var hasPendingTimer: Bool { !pending.isEmpty }
}

/// Counts how often what a body reads was invalidated, as the views would be.
@MainActor
final class InvalidationCounter {
    private(set) var count = 0
    private var needsRearm = true
    private let read: @MainActor () -> Void

    init(_ read: @escaping @MainActor () -> Void) {
        self.read = read
        arm()
    }

    /// Re-registers after an invalidation, as a body that was evaluated again would.
    func rearmIfNeeded() {
        if needsRearm { arm() }
    }

    private func arm() {
        needsRearm = false
        withObservationTracking(read) { [weak self] in
            // Runs synchronously from the mutation, on the main actor in these tests.
            MainActor.assumeIsolated {
                self?.count += 1
                self?.needsRearm = true
            }
        }
    }
}

/// 600 one-minute candles that swing, so that the autoscale has something to follow.
@MainActor
private func swingingModel(
    count: Int = 600,
    indicators: Bool = true,
    configuration: TradingChartConfiguration = TradingChartConfiguration()
) -> (model: TradingChartModel, clock: ManualClock) {
    let candles = (0..<count).map { index -> Candle in
        let phase = Double(index)
        let mid = 100 + 12 * sin(phase / 17) + 4 * sin(phase / 3.1) + phase * 0.02
        let wiggle = 1 + abs(sin(phase * 1.3)) * 2
        return Candle(
            time: date(baseTime + phase * 60),
            open: mid - wiggle / 2,
            high: mid + wiggle,
            low: mid - wiggle,
            close: mid + wiggle / 2,
            volume: 50 + 40 * abs(sin(phase / 5))
        )
    }
    let model = TradingChartModel(
        series: ChartSeries(candles: candles, interval: .minutes(1)),
        style: .candles,
        configuration: configuration
    )
    if indicators {
        model.indicators = [SMA(period: 20), Volume(), RSI(), MACD()]
    }
    model.currentPrice = candles.last?.close
    let clock = ManualClock()
    model.scrollClock = clock.scrollClock
    return (model, clock)
}

@MainActor
@Suite("Render state of the model")
struct RenderStateModelTests {
    /// The window, the domains and the stored live-edge flag against what the geometry says, for the current position.
    private func expectConsistent(_ model: TradingChartModel, sourceLocation: SourceLocation = #_sourceLocation) {
        let visible = model.visibleTimeRange
        #expect(model.renderWindow.lowerBound <= visible.lowerBound, sourceLocation: sourceLocation)
        #expect(model.renderWindow.upperBound >= visible.upperBound, sourceLocation: sourceLocation)
        let xDomain = model.naturalXDomain
        let main = model.mainYExact(visible: visible, xDomain: xDomain)
        if let extent = main.extent {
            #expect(model.mainYTarget.lowerBound <= extent.lowerBound, sourceLocation: sourceLocation)
            #expect(model.mainYTarget.upperBound >= extent.upperBound, sourceLocation: sourceLocation)
        }
        #expect(YTransformMath.covers(base: model.mainYBase, target: model.mainYTarget), sourceLocation: sourceLocation)
        for (id, state) in model.paneStates {
            guard let output = model.output(for: id) else { continue }
            if let extent = IndicatorRendering.paneYExtent(output: output, visibleRange: visible) {
                #expect(state.yTarget.lowerBound <= extent.lowerBound, sourceLocation: sourceLocation)
                #expect(state.yTarget.upperBound >= extent.upperBound, sourceLocation: sourceLocation)
            }
            #expect(YTransformMath.covers(base: state.yBase, target: state.yTarget), sourceLocation: sourceLocation)
        }
        #expect(model.isAtLiveEdge == model.liveEdgeNow, sourceLocation: sourceLocation)
    }

    @Test("a new model shows the exact autoscale, laid out for it")
    func initialState() {
        let (model, _) = swingingModel()
        let visible = model.visibleTimeRange
        let xDomain = model.naturalXDomain
        let exact = model.mainYExact(visible: visible, xDomain: xDomain).domain
        #expect(model.mainYTarget == exact)
        #expect(model.mainYBase == YTransformMath.base(for: exact))
        #expect(model.paneStates.count == 3)  // Volume, RSI, MACD
        expectConsistent(model)
    }

    @Test("the pane domains are the exact ones of the window")
    func paneDomains() throws {
        let (model, _) = swingingModel()
        for indicator in model.indicators where indicator.placement == .pane {
            let output = try #require(model.output(for: indicator.id))
            let exact = IndicatorRendering.paneYDomain(
                output: output,
                visibleRange: model.visibleTimeRange,
                paddingFraction: model.viewport.verticalPaddingFraction
            )
            #expect(model.paneStates[indicator.id]?.yTarget == exact)
        }
    }

    @Test("while the window scrolls, the marks cover it and the shown domains hold its data at every step")
    func sweepStaysConsistent() {
        let (model, clock) = swingingModel()
        let barSeconds = model.series.interval.seconds
        let live = model.scrollPosition
        var windowMoves = 0
        var baseChanges = 0
        var previousWindow = model.renderWindow
        var previousBase = model.mainYBase
        // A fling into the past and back: 3.7 bars per frame, a frame every 16.7 ms.
        let steps = 300
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let depth = progress < 0.5 ? 2 * progress : 2 - 2 * progress
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-depth * 520 * barSeconds)
            expectConsistent(model)
            if model.renderWindow != previousWindow { windowMoves += 1 }
            if model.mainYBase != previousBase { baseChanges += 1 }
            previousWindow = model.renderWindow
            previousBase = model.mainYBase
        }
        // The charts are laid out again a handful of times, not on every step.
        #expect(windowMoves <= steps / 12)
        #expect(baseChanges <= steps / 3)
        #expect(windowMoves > 0)
    }

    @Test("a jump of many windows is covered at once")
    func jump() {
        let (model, _) = swingingModel()
        for bars in [-300.0, -40, -450, -5, -120] {
            model.scrollPosition = model.scrollPosition.addingTimeInterval(bars * 60)
            expectConsistent(model)
        }
    }

    @Test("small moves leave the render window where it is")
    func hysteresis() {
        let (model, _) = swingingModel()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-200 * 60)
        let window = model.renderWindow
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-3 * 60)
        #expect(model.renderWindow == window)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-6 * 60)
        #expect(model.renderWindow == window)
        expectConsistent(model)
    }

    @Test("a fling gets a window that reaches further ahead of it than behind")
    func flingLeadsTheWindow() {
        let (model, clock) = swingingModel()
        // Scroll into the past quickly: 3 bars (0.075 windows) every 16.7 ms is 4.5 windows per second.
        for _ in 0..<40 {
            clock.advance(by: 0.0167)
            model.scrollPosition = model.scrollPosition.addingTimeInterval(-3 * 60)
        }
        #expect(model.scrollVelocity < -3)
        let visible = model.visibleTimeRange
        let ahead = visible.lowerBound.timeIntervalSince(model.renderWindow.lowerBound)
        let behind = model.renderWindow.upperBound.timeIntervalSince(visible.upperBound)
        #expect(ahead > behind)
        #expect(ahead + behind > 2.5 * model.visibleDuration)  // the buffer grows with speed
    }

    @Test("once scrolling has stopped the domains are exact and the charts are laid out for them")
    func settles() {
        let (model, clock) = swingingModel()
        let barSeconds = model.series.interval.seconds
        let live = model.scrollPosition
        for step in 1...40 {
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-Double(step) * 3.3 * barSeconds)
        }
        #expect(clock.hasPendingTimer)
        // Still moving 50 ms ago: not stopped yet.
        clock.advance(by: 0.05)
        #expect(model.isScrollActive)
        // Quiet for longer than the settle delay.
        clock.advance(by: 0.2)
        #expect(!model.isScrollActive)
        #expect(model.scrollVelocity == 0)

        let visible = model.visibleTimeRange
        let xDomain = model.naturalXDomain
        let exact = model.mainYExact(visible: visible, xDomain: xDomain).domain
        #expect(model.mainYTarget == exact)
        #expect(YTransformMath.isNearIdentity(base: model.mainYBase, target: model.mainYTarget))
        for state in model.paneStates.values {
            #expect(YTransformMath.isNearIdentity(base: state.yBase, target: state.yTarget))
        }
        // Back to a window of the size rest needs.
        #expect(!RenderWindowPolicy.isTooWide(model.renderWindow, visible: visible, bufferWindows: 1, tolerance: 1.3))
        expectConsistent(model)
    }

    @Test("every scroll step postpones the end of the scroll")
    func settleIsDebounced() {
        let (model, clock) = swingingModel()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-60)
        clock.advance(by: 0.09)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-60)
        clock.advance(by: 0.09)  // 180 ms after the first step, 90 ms after the last
        #expect(model.isScrollActive)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-60)
        clock.advance(by: 0.11)
        #expect(model.isScrollActive)
        clock.advance(by: 0.1)
        #expect(!model.isScrollActive)
    }

    @Test("the live-edge flag is assigned only when the answer changes")
    func liveEdgeIsStored() {
        let (model, _) = swingingModel()
        #expect(model.isAtLiveEdge)
        let counter = InvalidationCounter { _ = model.isAtLiveEdge }
        // Scrolling a little back stays within the tolerance of one bar... then leaves it once.
        var notifications = 0
        for _ in 0..<60 {
            model.scrollPosition = model.scrollPosition.addingTimeInterval(-30)
            if counter.count > notifications {
                notifications = counter.count
                counter.rearmIfNeeded()
            }
        }
        #expect(!model.isAtLiveEdge)
        #expect(counter.count == 1)
        model.scrollToLiveEdge()
        #expect(model.isAtLiveEdge)
        #expect(counter.count == 2)
    }

    @Test("what the panes read is invalidated by a handful of steps of a fling, not by every frame")
    func panesAreNotRebuiltPerFrame() {
        let (model, clock) = swingingModel()
        let barSeconds = model.series.interval.seconds
        let live = model.scrollPosition
        // What the bodies of the panes read: the data of the marks, the window, the domain they are laid out for.
        let panes = InvalidationCounter {
            _ = model.renderInput
            _ = model.renderWindow
            _ = model.mainYBase
            _ = model.paneStates.values.map(\.yBase)
        }
        // What the small views read: the scroll position and the shown domains.
        let leaves = InvalidationCounter {
            _ = model.scrollPosition
            _ = model.mainYTarget
        }
        let steps = 300
        var paneChanges = 0
        var leafChanges = 0
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let depth = progress < 0.5 ? 2 * progress : 2 - 2 * progress
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-depth * 520 * barSeconds)
            if panes.count > paneChanges {
                paneChanges = panes.count
                panes.rearmIfNeeded()
            }
            if leaves.count > leafChanges {
                leafChanges = leaves.count
                leaves.rearmIfNeeded()
            }
        }
        // The leaves follow every frame; the panes only a few times.
        #expect(leaves.count > steps / 2)
        #expect(panes.count <= steps / 5)
        #expect(panes.count >= 2)
    }

    @Test("a live update of a bar the render window does not reach does not rebuild the charts")
    func tickOutsideTheWindow() {
        let (model, _) = swingingModel()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-300 * 60)
        let revision = model.renderRevision
        let charts = InvalidationCounter { _ = model.renderInput }
        let series = InvalidationCounter { _ = model.series }
        for tick in 1...20 {
            model.update(price: 100 + Double(tick) * 0.01, at: model.series.lastTime!.addingTimeInterval(1))
            charts.rearmIfNeeded()
            series.rearmIfNeeded()
        }
        #expect(model.renderRevision == revision)
        #expect(charts.count == 0)
        #expect(series.count > 0)  // the public series still notifies
        // The data the charts will be given next time is the current one.
        #expect(model.renderInput.series.lastValue == model.series.lastValue)
    }

    @Test("a live update the window shows, a new bar and a new series do rebuild the charts")
    func tickInsideTheWindow() {
        let (model, _) = swingingModel()
        var revision = model.renderRevision
        model.update(price: 101, at: model.series.lastTime!.addingTimeInterval(1))
        #expect(model.renderRevision > revision)
        revision = model.renderRevision
        model.update(price: 101, at: model.series.lastTime!.addingTimeInterval(61))  // a new bar
        #expect(model.renderRevision > revision)
        revision = model.renderRevision
        model.setSeries(makeSeries(count: 50))
        #expect(model.renderRevision > revision)
        revision = model.renderRevision
        // Scrolling alone changes no data.
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-600)
        #expect(model.renderRevision == revision)
    }

    @Test("a tick keeps the render window and the layout of the charts where they are")
    func tickKeepsLayout() {
        let (model, _) = swingingModel()
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-300 * 60)
        let window = model.renderWindow
        let base = model.mainYBase
        model.update(price: 101, at: model.series.lastTime!.addingTimeInterval(1))
        #expect(model.renderWindow == window)
        #expect(model.mainYBase == base)
    }

    @Test("the render revision is part of the pattern: the anchor moves in the same mutation as the data")
    func anchorWithData() {
        let (model, _) = swingingModel()
        let revision = model.renderRevision
        model.update(price: 101, at: model.series.lastTime!.addingTimeInterval(61))  // at the live edge: the window follows
        #expect(model.isAtLiveEdge)
        #expect(model.renderRevision > revision)
        expectConsistentAfterTick(model)
    }

    private func expectConsistentAfterTick(_ model: TradingChartModel, sourceLocation: SourceLocation = #_sourceLocation) {
        expectConsistent(model, sourceLocation: sourceLocation)
        #expect(model.renderInput.series.lastTime == model.series.lastTime, sourceLocation: sourceLocation)
    }

    @Test("zooming resizes the render window to the new window")
    func zoomResizes() {
        let (model, _) = swingingModel()
        let width = model.renderWindow.upperBound.timeIntervalSince(model.renderWindow.lowerBound)
        model.zoom(by: 4, anchor: .liveEdge)
        let zoomed = model.renderWindow.upperBound.timeIntervalSince(model.renderWindow.lowerBound)
        #expect(zoomed < width / 3)
        expectConsistent(model)
        model.zoom(by: 0.25, anchor: .liveEdge)
        expectConsistent(model)
    }

    @Test("the price in the autoscale of the live edge follows the ticks")
    func priceInAutoscale() {
        let (model, _) = swingingModel()
        let before = model.mainYTarget
        model.currentPrice = (model.series.lastValue ?? 100) + 50
        #expect(model.mainYTarget.upperBound > before.upperBound)
        expectConsistent(model)
    }

    @Test("without a render buffer every step moves the window, as before")
    func noBuffer() {
        var configuration = TradingChartConfiguration()
        configuration.renderBufferWindows = 0
        let (model, _) = swingingModel(configuration: configuration)
        for _ in 0..<10 {
            let before = model.renderWindow
            model.scrollPosition = model.scrollPosition.addingTimeInterval(-60)
            #expect(model.renderWindow != before)
            #expect(model.renderWindow == model.visibleTimeRange)
        }
    }

    @Test("the checks of the demo find a consistent chart consistent")
    func diagnostics() {
        let (model, clock) = swingingModel()
        for step in 0..<50 {
            clock.advance(by: 0.0167)
            model.scrollPosition = model.scrollPosition.addingTimeInterval(-Double(step % 5) * 60)
            #expect(ChartDiagnostics.violations(of: model).total == 0)
        }
    }
}

@Suite("Pane geometry")
struct PaneGeometryTests {
    @Test("the plot is what remains of the pane after the price column and the time strip")
    func plot() {
        let theme = TradingChartTheme.standard
        let bottom = PaneGeometry(size: CGSize(width: 337, height: 120), theme: theme, isBottomPane: true)
        let inner = PaneGeometry(size: CGSize(width: 337, height: 120), theme: theme, isBottomPane: false)
        #expect(bottom.columnWidth == theme.yAxisLabelWidth + PaneGeometry.labelGap)
        #expect(bottom.plot.width == 337 - bottom.columnWidth)
        #expect(bottom.plot.height == 120 - PaneGeometry.timeStrip)
        #expect(inner.plot.height == 120)
        #expect(PaneGeometry(size: CGSize(width: 10, height: 5), theme: theme, isBottomPane: true).plot.width == 0)
    }
}
