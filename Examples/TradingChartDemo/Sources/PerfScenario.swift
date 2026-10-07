import Foundation
import UIKit

/// The scroll-stress scenarios behind `Docs/Performance.md`: `-perf <name>` on the launch arguments runs one.
enum PerfScenario: String, CaseIterable {
    /// 600 candles, no indicators.
    case s1
    /// 600 candles with SMA, Bollinger Bands, Volume, RSI and MACD.
    case s2
    /// 5 000 candles with the same indicators.
    case s3
    /// Scenario 2 with 10 live ticks per second.
    case s4

    var title: String {
        switch self {
        case .s1: "600 candles, no indicators"
        case .s2: "600 candles, SMA+BB+Volume+RSI+MACD"
        case .s3: "5000 candles, SMA+BB+Volume+RSI+MACD"
        case .s4: "600 candles, SMA+BB+Volume+RSI+MACD, 10 ticks/s"
        }
    }

    var barCount: Int { self == .s3 ? 5_000 : 600 }

    var indicators: [DemoViewModel.Indicator] {
        self == .s1 ? [] : [.sma20, .bollinger, .volume, .rsi, .macd]
    }

    var tickHz: Double { self == .s4 ? 10 : 0 }

    /// Seconds the chart settles (first layout, indicator caches) before recording starts.
    static let warmUp: TimeInterval = 2
    /// Seconds of recording: one sweep from the live edge into the history and back. `-perf-seconds <n>` makes it longer,
    /// for a profiler to attach to.
    static let duration: TimeInterval = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-perf-seconds"), flag + 1 < arguments.count,
              let seconds = Double(arguments[flag + 1]), seconds > 0
        else { return 5 }
        return seconds
    }()
    /// How many bars the sweep reaches back from the live edge.
    static let sweepBars = 560
}

/// What one run writes to `Documents/perf-<scenario>.json`.
struct PerfReport: Codable {
    var scenario: String
    var title: String
    /// `debug` or `release`.
    var build: String
    var device: String
    var systemVersion: String
    var bars: Int
    var indicators: [String]
    var tickHz: Double
    var sweepBars: Int
    var visibleBars: Double
    /// The one-minute load average of the Mac when the run ended: a noisy host spoils the numbers.
    var loadAverage: Double
    var stats: FrameStats
    /// What the chart rebuilt during the recording: bodies of the main pane, of the indicator panes and of the time axes,
    /// and commits of the render state (`ChartDiagnostics`).
    var bodies: [String: Int]?
    /// Frames on which a pane was inconsistent (`ChartDiagnostics.violations`), summed over the run; the target is zero.
    var violations: [String: Int]?

    static var currentLoadAverage: Double {
        var load = [Double](repeating: 0, count: 1)
        return getloadavg(&load, 1) == 1 ? load[0] : -1
    }

    static var buildConfiguration: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    /// The simulator reports itself as the Mac it runs on; the model name of the simulated device is in the environment.
    @MainActor
    static var deviceName: String {
        if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return identifier }
        return UIDevice.current.model
    }

    func write(named name: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = documents.appendingPathComponent("perf-\(name).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }
}
