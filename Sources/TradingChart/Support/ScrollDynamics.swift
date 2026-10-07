import Foundation
import QuartzCore

/// The inertia of a fling. Pure.
///
/// After the finger lifts the window keeps moving and slows down exponentially, the way a scroll view's normal deceleration
/// does: the speed falls by a constant share per unit of time, so the distance covered after `t` seconds is
/// `v * τ * (1 - e^(-t/τ))` and the whole fling travels `v * τ`.
@available(iOS 17.0, *)
enum ScrollDeceleration {
    /// Seconds in which the speed falls to `1/e` of itself (`UIScrollView.DecelerationRate.normal`, 0.998 per millisecond).
    static let timeConstant: TimeInterval = 0.5
    /// A fling slower than this many points per second does not start.
    static let minimumStartSpeed: Double = 40
    /// The motion ends when it has slowed to this many points per second.
    static let stopSpeed: Double = 6

    /// How far a fling that started at `velocity` has moved after `elapsed` seconds, in the unit of `velocity`.
    static func distance(velocity: Double, elapsed: TimeInterval) -> Double {
        velocity * timeConstant * (1 - exp(-Swift.max(elapsed, 0) / timeConstant))
    }

    /// The speed a fling that started at `velocity` has after `elapsed` seconds.
    static func speed(velocity: Double, elapsed: TimeInterval) -> Double {
        velocity * exp(-Swift.max(elapsed, 0) / timeConstant)
    }
}

/// A fling in progress: where it started, how fast, and how long it has run.
@available(iOS 17.0, *)
struct ScrollMomentum {
    var start: Date
    /// Seconds of chart time per second; positive towards the future.
    var velocity: Double
    var elapsed: TimeInterval = 0
}

/// Calls a closure once per display frame; replaceable in tests.
@available(iOS 17.0, *)
struct FrameTicker {
    /// Starts calling `tick` with the seconds since the previous call, and returns the function that stops it.
    ///
    /// `tick` answers whether to go on: when it returns `false` the ticker stops itself, so a display link whose owner has gone
    /// away (the closure holds it weakly and answers `false` once it is gone) does not keep running for ever.
    var start: @MainActor (_ tick: @escaping @MainActor (TimeInterval) -> Bool) -> (@MainActor () -> Void)

    /// A `CADisplayLink` on the main run loop.
    static var display: FrameTicker {
        FrameTicker { tick in
            let driver = DisplayLinkDriver(tick: tick)
            return { driver.stop() }
        }
    }
}

/// `CADisplayLink` needs an Objective-C target. The link retains the driver until it is invalidated, so the driver
/// invalidates itself as soon as the tick says to stop, and drops the tick when it does.
@available(iOS 17.0, *)
@MainActor
private final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var tick: (@MainActor (TimeInterval) -> Bool)?

    init(tick: @escaping @MainActor (TimeInterval) -> Bool) {
        self.tick = tick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let tick else {
            stop()
            return
        }
        let now = link.timestamp
        let delta = last.map { now - $0 } ?? link.targetTimestamp - link.timestamp
        last = now
        if !tick(Swift.min(delta, 0.1)) { stop() }
    }

    func stop() {
        link?.invalidate()
        link = nil
        tick = nil
    }
}
