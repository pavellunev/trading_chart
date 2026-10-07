import Foundation
import Observation
import QuartzCore
import UIKit

/// Frame statistics of one recording.
struct FrameStats: Codable {
    var frames: Int
    var durationSeconds: Double
    /// The nominal frame period of the display, in milliseconds.
    var periodMs: Double
    var averageFPS: Double
    var p50Ms: Double
    var p95Ms: Double
    var p99Ms: Double
    var maxMs: Double
    /// The five longest frames, longest first, in milliseconds.
    var worstMs: [Double]
    /// Frames that took longer than 1.5 periods.
    var hitches: Int
    /// Frames the display missed because of hitches: `round(duration / period) - 1` summed over them.
    var droppedFrames: Int
    /// Milliseconds spent over the frame budget per second of recording (the Instruments "hitch time ratio" style).
    var hitchTimeMsPerSecond: Double
    /// CPU time of the process over the recording as a share of one core, in percent.
    var cpuPercent: Double

    /// Computes the statistics from the intervals between consecutive display link callbacks.
    static func make(durations: [Double], period: Double, wallSeconds: Double, cpuSeconds: Double) -> FrameStats {
        let sorted = durations.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
            return sorted[min(max(rank, 0), sorted.count - 1)]
        }
        let threshold = period * 1.5
        var hitches = 0
        var dropped = 0
        var overBudget = 0.0
        for duration in durations where duration > threshold {
            hitches += 1
            dropped += max(Int((duration / period).rounded()) - 1, 0)
            overBudget += duration - period
        }
        let total = durations.reduce(0, +)
        return FrameStats(
            frames: durations.count,
            durationSeconds: wallSeconds,
            periodMs: period * 1000,
            averageFPS: total > 0 ? Double(durations.count) / total : 0,
            p50Ms: percentile(0.5) * 1000,
            p95Ms: percentile(0.95) * 1000,
            p99Ms: percentile(0.99) * 1000,
            maxMs: (sorted.last ?? 0) * 1000,
            worstMs: sorted.suffix(5).reversed().map { $0 * 1000 },
            hitches: hitches,
            droppedFrames: dropped,
            hitchTimeMsPerSecond: wallSeconds > 0 ? overBudget * 1000 / wallSeconds : 0,
            cpuPercent: wallSeconds > 0 ? cpuSeconds / wallSeconds * 100 : 0
        )
    }
}

/// Measures frame durations with a `CADisplayLink` and, if asked, drives an animation from the same callback,
/// so that the work of an animation step lands in the frame it belongs to.
@MainActor
@Observable
final class FrameRecorder {
    /// A one-line summary for the HUD, refreshed twice a second while recording and kept after it ends.
    private(set) var summary = "perf: idle"
    /// A second HUD line set by whoever drives the recording (the consistency checks of `-diag`).
    var note = ""

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var target: Target?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var startTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var period: Double = 1.0 / 60.0
    @ObservationIgnored private var durations: [Double] = []
    @ObservationIgnored private var cpuAtStart: Double = 0
    @ObservationIgnored private var limit: TimeInterval = 0
    @ObservationIgnored private var driver: ((TimeInterval) -> Void)?
    @ObservationIgnored private var continuation: CheckedContinuation<FrameStats, Never>?
    @ObservationIgnored private var label = ""

    /// Records for `duration` seconds. `driver` is called on every frame with the seconds since the start.
    ///
    /// One recording at a time: a request made while another is running waits for it to end (overwriting the running one would
    /// leave its caller waiting for ever).
    func record(label: String, duration: TimeInterval, driver: ((TimeInterval) -> Void)? = nil) async -> FrameStats {
        while continuation != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        self.label = label
        limit = duration
        self.driver = driver
        durations = []
        durations.reserveCapacity(Int(duration * 125))
        lastTimestamp = nil
        cpuAtStart = Self.processCPUSeconds()
        let target = Target(self)
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.target = target
        self.link = link
        return await withCheckedContinuation { continuation = $0 }
    }

    fileprivate func handle(_ link: CADisplayLink) {
        guard let last = lastTimestamp else {
            lastTimestamp = link.timestamp
            startTimestamp = link.timestamp
            period = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
            driver?(0)
            return
        }
        durations.append(link.timestamp - last)
        lastTimestamp = link.timestamp
        let elapsed = link.timestamp - startTimestamp
        if durations.count % 30 == 0 { refreshSummary(elapsed: elapsed) }
        if elapsed >= limit {
            finish(elapsed: elapsed)
        } else {
            driver?(elapsed)
        }
    }

    /// Adds a note to the summary line, after a recording.
    func annotate(_ note: String) {
        summary += "  " + note
    }

    private func finish(elapsed: TimeInterval) {
        link?.invalidate()
        link = nil
        target = nil
        driver = nil
        let cpu = Self.processCPUSeconds() - cpuAtStart
        let stats = FrameStats.make(durations: durations, period: period, wallSeconds: elapsed, cpuSeconds: cpu)
        summary = Self.text(label: label, stats: stats, isFinal: true)
        continuation?.resume(returning: stats)
        continuation = nil
    }

    private func refreshSummary(elapsed: TimeInterval) {
        let cpu = Self.processCPUSeconds() - cpuAtStart
        let stats = FrameStats.make(durations: durations, period: period, wallSeconds: elapsed, cpuSeconds: cpu)
        summary = Self.text(label: label, stats: stats, isFinal: false)
    }

    private static func text(label: String, stats: FrameStats, isFinal: Bool) -> String {
        let fps = String(format: "%.1f", stats.averageFPS)
        let p95 = String(format: "%.1f", stats.p95Ms)
        let max = String(format: "%.1f", stats.maxMs)
        return "\(label)\(isFinal ? " done" : "")  \(fps) fps  p95 \(p95) ms  max \(max) ms  hitches \(stats.hitches)/\(stats.frames)"
    }

    /// User plus system CPU time of this process in seconds.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ value: timeval) -> Double { Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// `CADisplayLink` needs an Objective-C target.
    @MainActor
    private final class Target: NSObject {
        private weak var recorder: FrameRecorder?

        init(_ recorder: FrameRecorder) {
            self.recorder = recorder
        }

        @objc func tick(_ link: CADisplayLink) {
            recorder?.handle(link)
        }
    }
}
