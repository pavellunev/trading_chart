import CoreGraphics
import Foundation
import Observation
import TradingChartCore

/// The data the chart bodies build marks from, handed over by the model (see ``TradingChartModel/renderInput``).
@available(iOS 17.0, *)
struct RenderData {
    var series: ChartSeries
    var outputs: [String: IndicatorOutput]
    var paletteBases: [String: Int]

    /// The first palette index of the indicator with the given id (see ``IndicatorPalette``).
    func paletteBase(for indicatorID: String) -> Int {
        paletteBases[indicatorID] ?? 0
    }
}

/// What an indicator pane draws apart from the data: the Y domain its chart is laid out for (`yBase`) and the
/// Y domain it has to show (`yTarget`). The chart is rebuilt only when `yBase` changes; `yTarget` follows the window on
/// every scroll step and reaches the screen as a transform of the chart (see ``YTransformMath``).
@available(iOS 17.0, *)
@MainActor
@Observable
final class PaneRenderState {
    /// The domain the chart is laid out for.
    var yBase: ClosedRange<Double> = 0...1
    /// The domain that is shown: the autoscaled domain of the visible window.
    var yTarget: ClosedRange<Double> = 0...1
}

/// Decides where the render window (the time range marks are built for) stands. Pure.
///
/// Building the marks of a chart is the expensive part of a scroll step, so the window is moved rarely. It is built
/// `bufferWindows` window widths wide on each side of the visible window, and shifted towards the direction the window
/// is moving, so that a fling finds marks ahead of it. It is moved again before the visible window reaches its edge,
/// or at once when it already has.
@available(iOS 17.0, *)
enum RenderWindowPolicy {
    /// Window widths of marks the visible window must keep on each side, at rest.
    static let restMargin = 0.25
    /// Seconds of travel the margin ahead of the window has to cover (a move of the window takes a few frames).
    static let leadTime = 0.12
    /// How much of the buffer is moved from behind the visible window to ahead of it at full speed.
    static let maxBias = 0.5
    /// The speed (window widths per second) at which the buffer has doubled: a fling builds marks for more of the
    /// way ahead, so that the window has to be moved less often (every move rebuilds every chart).
    static let doublingSpeed = 2.0

    /// The buffer for a speed: `bufferWindows` at rest, up to twice that at `doublingSpeed` and above.
    static func effectiveBuffer(_ bufferWindows: Double, velocity: Double) -> Double {
        Swift.max(bufferWindows, 0) * (1 + Swift.min(abs(velocity) / doublingSpeed, 1))
    }

    /// The render window for `visible`.
    ///
    /// - Parameters:
    ///   - bufferWindows: Window widths of buffer on each side when at rest (`renderBufferWindows`).
    ///   - velocity: Window widths per second, positive towards the future; `0` at rest.
    static func window(for visible: ClosedRange<Date>, bufferWindows: Double, velocity: Double) -> ClosedRange<Date> {
        let width = visible.upperBound.timeIntervalSince(visible.lowerBound)
        let buffer = effectiveBuffer(bufferWindows, velocity: velocity)
        let bias = Swift.min(abs(velocity) * 0.25, maxBias) * (velocity < 0 ? -1 : 1)
        let after = buffer * (1 + bias) * width
        let before = buffer * (1 - bias) * width
        return visible.lowerBound.addingTimeInterval(-before)...visible.upperBound.addingTimeInterval(after)
    }

    /// Whether `window` is more than `tolerance` times as wide as the window built for `visible` at rest: after zooming
    /// in, or after a fling that built marks for more of the way ahead than rest needs.
    static func isTooWide(
        _ window: ClosedRange<Date>,
        visible: ClosedRange<Date>,
        bufferWindows: Double,
        tolerance: Double
    ) -> Bool {
        let width = visible.upperBound.timeIntervalSince(visible.lowerBound)
        let restWidth = (1 + 2 * Swift.max(bufferWindows, 0)) * width
        return window.upperBound.timeIntervalSince(window.lowerBound) > restWidth * tolerance
    }

    /// Whether `window` still serves `visible`: it leaves the margin on both sides (the larger one ahead of the
    /// motion, see `leadTime`). With no buffer that is never so once the window moves.
    static func isValid(
        _ window: ClosedRange<Date>,
        visible: ClosedRange<Date>,
        bufferWindows: Double,
        velocity: Double
    ) -> Bool {
        let width = visible.upperBound.timeIntervalSince(visible.lowerBound)
        let buffer = Swift.max(bufferWindows, 0)
        let rest = Swift.min(restMargin, buffer / 2)
        let lead = Swift.min(
            Swift.max(restMargin, abs(velocity) * leadTime),
            effectiveBuffer(buffer, velocity: velocity) * 0.75
        )
        let before = (velocity < 0 ? lead : rest) * width
        let after = (velocity < 0 ? rest : lead) * width
        return window.lowerBound <= visible.lowerBound.addingTimeInterval(-before)
            && window.upperBound >= visible.upperBound.addingTimeInterval(after)
    }
}

/// The transform that shows an autoscaled domain on a chart that was laid out for another one. Pure.
///
/// The chart is `frameRatio` plot heights tall and laid out for a base domain that holds the target domain with a margin of
/// one plot height above and below. To show another target (the window scrolled, the autoscale changed) the chart is
/// moved and scaled in Y: a mapping of data to pixels that is exact, costs no layout (the chart is a layer), and can follow
/// the window on every frame. Marks are stretched with the scale, so when it drifts too far from 1 or the target leaves the
/// base domain (the chart has nothing to show beyond it) the chart is laid out again, for the current target (a "rebase"),
/// with the transform reset in the same update, which is invisible.
@available(iOS 17.0, *)
enum YTransformMath {
    struct Parameters: Equatable {
        /// Vertical scale, about the top edge of the chart.
        var scale: Double
        /// Vertical offset after scaling, as a fraction of the plot height.
        var offset: Double
    }

    /// How many plot heights tall the chart is.
    static let frameRatio = 3.0
    /// The margin of the base domain around the target, in spans of the target (the chart's extra height above and below).
    static let margin = (frameRatio - 1) / 2

    /// The scale range in which a chart is not laid out again for the transform alone: marks are stretched by at most
    /// 70 % (and in practice far less: a chart that is laid out anyway, for a move of the render window, is based on
    /// the current target, so the scale starts from 1 and the window moves about seven times a second in a fling).
    static let scaleRange = 0.6...1.7
    /// How close to the rebased state the transform has to be to be left alone when scrolling stops (a fraction of the
    /// plot height for the offset).
    static let restTolerance = 0.002

    /// The base domain for a chart that has to show `target`: the target with the margin around it.
    static func base(for target: ClosedRange<Double>) -> ClosedRange<Double> {
        let span = target.upperBound - target.lowerBound
        guard span.isFinite else { return target }
        return (target.lowerBound - margin * span)...(target.upperBound + margin * span)
    }

    static func parameters(base: ClosedRange<Double>, target: ClosedRange<Double>) -> Parameters {
        let baseSpan = base.upperBound - base.lowerBound
        let targetSpan = target.upperBound - target.lowerBound
        guard baseSpan > 0, targetSpan > 0, baseSpan.isFinite, targetSpan.isFinite else {
            return Parameters(scale: 1, offset: -margin)
        }
        return Parameters(
            scale: baseSpan / (frameRatio * targetSpan),
            offset: -(base.upperBound - target.upperBound) / targetSpan
        )
    }

    /// Whether `target` lies inside `base`: the chart has marks (and room) for all of it.
    static func covers(base: ClosedRange<Double>, target: ClosedRange<Double>) -> Bool {
        base.lowerBound <= target.lowerBound && target.upperBound <= base.upperBound
    }

    /// Whether a chart laid out for `base` must be laid out again to show `target`.
    static func needsRebase(base: ClosedRange<Double>, target: ClosedRange<Double>) -> Bool {
        !covers(base: base, target: target) || !scaleRange.contains(parameters(base: base, target: target).scale)
    }

    /// Whether the chart is laid out for `target` as it is: no scale and no shift to leave in place when scrolling stops.
    static func isNearIdentity(base: ClosedRange<Double>, target: ClosedRange<Double>) -> Bool {
        let parameters = parameters(base: base, target: target)
        return abs(parameters.scale - 1) < restTolerance && abs(parameters.offset + margin) < restTolerance
    }
}

/// Maps prices to Y positions in a plot for a domain. Pure.
@available(iOS 17.0, *)
struct YMapping {
    var domain: ClosedRange<Double>
    var height: CGFloat

    /// The Y of `value` from the top of the plot (grows downwards).
    func y(of value: Double) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, height > 0 else { return height / 2 }
        return height * CGFloat(1 - (value - domain.lowerBound) / span)
    }
}

/// The tick values of a price axis. Pure.
@available(iOS 17.0, *)
enum YAxisTicks {
    /// Round values inside `domain`, about `desiredCount` of them: multiples of 1, 2, 2.5 or 5 times a power of ten,
    /// whichever gives a count closest to `desiredCount` (fewer on a tie).
    static func values(in domain: ClosedRange<Double>, desiredCount: Int) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite, desiredCount > 0 else { return [] }
        let raw = span / Double(Swift.max(desiredCount - 1, 1))
        let magnitude = pow(10, floor(log10(raw)))
        var best: (step: Double, distance: Int)?
        for multiplier in [1.0, 2, 2.5, 5, 10] {
            let step = multiplier * magnitude
            let distance = abs(count(of: step, in: domain) - desiredCount)
            if best == nil || distance < best!.distance { best = (step, distance) }
        }
        guard let step = best?.step, step > 0 else { return [] }
        var result: [Double] = []
        var index = (domain.lowerBound / step).rounded(.up)
        while index * step <= domain.upperBound, result.count < 64 {
            // Rounding in the division can leave the first value an ulp below the domain.
            if index * step >= domain.lowerBound { result.append(index * step) }
            index += 1
        }
        return result
    }

    private static func count(of step: Double, in domain: ClosedRange<Double>) -> Int {
        let first = (domain.lowerBound / step).rounded(.up)
        let last = (domain.upperBound / step).rounded(.down)
        return Swift.max(Int(last - first) + 1, 0)
    }
}

/// The time source and the one-shot timer the model uses to notice that scrolling has stopped. Replaceable in tests.
@available(iOS 17.0, *)
struct ScrollClock {
    /// A monotonic time in seconds.
    var now: @MainActor () -> TimeInterval
    /// Runs `work` once, `delay` seconds from now.
    var after: @MainActor (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    static var system: ScrollClock {
        ScrollClock(
            now: { ProcessInfo.processInfo.systemUptime },
            after: { delay, work in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    work()
                }
            }
        )
    }
}

/// What the panes were last built with and how often they were built; see ``ChartDiagnostics``. One per model, so two charts
/// do not count into each other.
@available(iOS 17.0, *)
@MainActor
final class RenderCounters {
    var mainBodies = 0
    var paneBodies = 0
    var axisBodies = 0
    var drawingBodies = 0
    var crosshairBodies = 0
    var crosshairHapticBodies = 0
    /// Builds of the chart itself (its marks), in the main pane and in the indicator panes: what the closure of the `GeometryReader`
    /// of a pane evaluates, so a pane that reads something that changes often in there shows up here and not in the bodies.
    var chartBuilds = 0
    var commits = 0
    var windowMoves = 0
    var rebases = 0
    /// The render window and the base Y domain each pane was last built for, by pane key.
    var builtWindows: [String: ClosedRange<Date>] = [:]
    var builtBases: [String: ClosedRange<Double>] = [:]
}

/// How a theme draws candles: what the autoscale at the edges of the window needs to know to keep a candle whose centre is
/// outside the window, and half in view, inside the plot. Reported by the view, which has the theme of its environment.
@available(iOS 17.0, *)
struct CandleMetrics: Equatable {
    var bodyWidthFactor: CGFloat
    var minBodyWidth: CGFloat
    var maxBodyWidth: CGFloat
    var wickWidth: CGFloat

    init(theme: TradingChartTheme) {
        bodyWidthFactor = theme.candleBodyWidthFactor
        minBodyWidth = theme.minCandleBodyWidth
        maxBodyWidth = theme.maxCandleBodyWidth
        wickWidth = theme.wickWidth
    }
}

/// Counters and consistency checks of what the chart builds, for performance work. Not part of the supported API.
@available(iOS 17.0, *)
@_spi(Diagnostics)
@MainActor
public enum ChartDiagnostics {
    /// What a check found, per pane (the main pane and every indicator pane).
    public struct Violations: Sendable, Equatable {
        /// Panes whose marks were built for a render window that does not cover the visible window.
        public var windowCoverage = 0
        /// Panes whose chart is laid out for another base domain than the model holds (a scroll step the pane has not
        /// caught up with).
        public var staleBase = 0
        /// Panes whose shown domain does not contain the visible data.
        public var dataOutsideDomain = 0
        /// Panes whose chart is laid out for a domain that does not contain the domain shown: there is nothing drawn in
        /// the part that sticks out.
        public var targetOutsideBase = 0

        /// The sum of all four counters.
        public var total: Int { windowCoverage + staleBase + dataOutsideDomain + targetOutsideBase }

        /// Creates a result with every counter at zero.
        public init() {}

        /// Adds the counters of `rhs` to `lhs`.
        public static func += (lhs: inout Violations, rhs: Violations) {
            lhs.windowCoverage += rhs.windowCoverage
            lhs.staleBase += rhs.staleBase
            lhs.dataOutsideDomain += rhs.dataOutsideDomain
            lhs.targetOutsideBase += rhs.targetOutsideBase
        }
    }

    /// Evaluations of the body of the main pane, of an indicator pane and of an axes view, builds of the charts themselves,
    /// and the commits of render state, of one model.
    public static func counts(
        of model: TradingChartModel
    ) -> (main: Int, panes: Int, axes: Int, charts: Int, commits: Int, windowMoves: Int, rebases: Int) {
        let counters = model.renderCounters
        return (
            counters.mainBodies, counters.paneBodies, counters.axisBodies, counters.chartBuilds,
            counters.commits, counters.windowMoves, counters.rebases
        )
    }

    /// Sets every counter of `model` to zero.
    public static func reset(_ model: TradingChartModel) {
        let counters = model.renderCounters
        counters.mainBodies = 0
        counters.paneBodies = 0
        counters.axisBodies = 0
        counters.drawingBodies = 0
        counters.crosshairBodies = 0
        counters.crosshairHapticBodies = 0
        counters.chartBuilds = 0
        counters.commits = 0
        counters.windowMoves = 0
        counters.rebases = 0
    }

    /// Checks the model and the panes as they stand: that every pane's marks cover the visible window, that every pane's
    /// chart is laid out for the base domain of the model, and that the domains shown hold the visible data.
    public static func violations(of model: TradingChartModel) -> Violations {
        var result = Violations()
        let visible = model.visibleTimeRange
        let tolerance = model.series.interval.seconds * 0.001
        let counters = model.renderCounters
        func checkWindow(_ key: String) {
            guard let window = counters.builtWindows[key] else { return }
            if window.lowerBound > visible.lowerBound.addingTimeInterval(tolerance)
                || window.upperBound < visible.upperBound.addingTimeInterval(-tolerance) {
                result.windowCoverage += 1
            }
        }
        func contains(_ target: ClosedRange<Double>, _ extent: ClosedRange<Double>?) -> Bool {
            guard let extent else { return true }
            let slack = (target.upperBound - target.lowerBound) * 1e-9
            return extent.lowerBound >= target.lowerBound - slack && extent.upperBound <= target.upperBound + slack
        }

        checkWindow("main")
        if let base = counters.builtBases["main"], base != model.mainYBase { result.staleBase += 1 }
        if !YTransformMath.covers(base: model.mainYBase, target: model.mainYTarget) { result.targetOutsideBase += 1 }
        let xDomain = model.naturalXDomain
        if !contains(model.mainYTarget, model.mainYExact(visible: visible, xDomain: xDomain).extent) {
            result.dataOutsideDomain += 1
        }
        for (id, state) in model.paneStates {
            checkWindow(id)
            if let base = counters.builtBases[id], base != state.yBase { result.staleBase += 1 }
            if !YTransformMath.covers(base: state.yBase, target: state.yTarget) { result.targetOutsideBase += 1 }
            if let output = model.output(for: id),
               !contains(state.yTarget, IndicatorRendering.paneYExtent(output: output, visibleRange: visible, edgeMargin: model.edgeMargin, edgeSlack: model.edgeSlack)) {
                result.dataOutsideDomain += 1
            }
        }
        return result
    }
}
