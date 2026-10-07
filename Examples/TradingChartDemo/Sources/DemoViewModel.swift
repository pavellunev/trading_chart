import Foundation
import Observation
import TradingChart
import UIKit
@_spi(Diagnostics) import TradingChart

/// The "host" side of the demo: owns the chart model, simulates a data feed and loads history on demand.
@MainActor
@Observable
final class DemoViewModel {
    struct IntervalOption: Identifiable, Hashable {
        let title: String
        let interval: ChartInterval
        var id: ChartInterval { interval }
    }

    static let intervalOptions: [IntervalOption] = [
        IntervalOption(title: "1m", interval: .minutes(1)),
        IntervalOption(title: "5m", interval: .minutes(5)),
        IntervalOption(title: "15m", interval: .minutes(15)),
        IntervalOption(title: "1h", interval: .hours(1)),
        IntervalOption(title: "4h", interval: .hours(4)),
        IntervalOption(title: "1D", interval: .days(1)),
    ]

    /// The indicators the demo can switch on, in the order they are handed to the chart (it fixes their colours).
    enum Indicator: String, CaseIterable, Identifiable {
        case sma20, ema50, bollinger, volume, rsi, macd

        var id: String { rawValue }

        var chartIndicator: any ChartIndicator {
            switch self {
            case .sma20: SMA(period: 20)
            case .ema50: EMA(period: 50)
            case .bollinger: BollingerBands()
            case .volume: Volume(movingAveragePeriod: 20)
            case .rsi: RSI()
            case .macd: MACD()
            }
        }

        /// The token used by the `indicators=` launch script action.
        var scriptName: String {
            self == .bollinger ? "bb" : rawValue
        }
    }

    /// What the indicator bar offers, in the order the chart draws the indicators.
    static let catalog: [any ChartIndicator] = Indicator.allCases.map(\.chartIndicator)

    /// Bars per page of the emulated history source.
    private static let barsPerPage = 300
    /// After this many pages the emulated source is exhausted (`hasMoreHistory = false`).
    private static let maxHistoryPages = 5
    private static let historyDelay: Duration = .milliseconds(600)
    private static let intervalLoadDelay: Duration = .milliseconds(400)

    let model: TradingChartModel
    /// Frame statistics of the `-perf` runs; its summary feeds the HUD.
    let recorder = FrameRecorder()
    /// What the consistency checks of the last stress run found; see `ChartDiagnostics.violations`.
    @ObservationIgnored private var violations = ChartDiagnostics.Violations()

    /// The value of the `-perf` launch argument (a scenario name such as `s3`, or any tag for an ad-hoc `stress`).
    let perfTag: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-perf"), flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }()

    /// `-diag` on the launch arguments: watch the chart while it is used by hand (frame times, and on every frame whether the
    /// panes cover the window and the domains hold the data; see `ChartDiagnostics.violations`), show it on the HUD and
    /// write it to `Documents/diag.json` every second.
    let isDiagnosing = ProcessInfo.processInfo.arguments.contains("-diag")

    /// The interval chosen in the picker. It changes instantly; the chart switches when the "load" finishes.
    var selectedInterval: ChartInterval = .minutes(1) {
        didSet {
            guard oldValue != selectedInterval else { return }
            loadSeries(for: selectedInterval)
        }
    }

    private(set) var isLoading = false

    /// Bumped when a drawing was added, changed or removed (not on every step of a drag): `ContentView` saves the drawings then.
    private(set) var drawingsRevision = 0

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var historyPages = 0
    @ObservationIgnored private var tickGenerator = SeededGenerator(seed: 2026)

    init() {
        var configuration = TradingChartConfiguration()
        configuration.maxLiveBarCount = 2_000
        // `-render-buffer <windows>` overrides `renderBufferWindows`, `-max-live <bars>` overrides `maxLiveBarCount`,
        // `-reserve <bars>` overrides `historyReserveBars`,
        // `-no-markers` leaves out the buy / sell markers (their capsules would be taken for candles by `scripts/frame-check.py`).
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-max-live"), flag + 1 < arguments.count, let bars = Int(arguments[flag + 1]) {
            configuration.maxLiveBarCount = bars
        }
        if let flag = arguments.firstIndex(of: "-reserve"), flag + 1 < arguments.count, let bars = Int(arguments[flag + 1]) {
            configuration.historyReserveBars = bars
        }
        // The style is chosen on the chart: the small icon at the top right of the main pane.
        configuration.stylePicker = StylePickerOptions()
        if arguments.contains("-no-badge") { configuration.showsPriceBadge = false }
        if arguments.contains("-no-priceline") { configuration.showsCurrentPriceLine = false }
        if let flag = arguments.firstIndex(of: "-render-buffer"), flag + 1 < arguments.count,
           let windows = Double(arguments[flag + 1]) {
            configuration.renderBufferWindows = windows
        }
        let series = Self.makeSeries(interval: .minutes(1), lastClose: RandomWalk.basePrice)
        model = TradingChartModel(series: series, style: .candles, configuration: configuration)
        model.currentPrice = series.lastValue
        model.markers = Self.markers(for: series)
        model.onEvent = { [weak self] event in
            self?.handle(event)
        }
        model.indicators = [Indicator.sma20, .volume].map(\.chartIndicator)
    }

    /// Starts the live feed (one tick per second) and then whatever the launch arguments ask for:
    /// a `-perf` scenario, or a `-script`.
    func start() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let tag = perfTag, let scenario = PerfScenario(rawValue: tag) {
            await runPerfScenario(scenario)
            return
        }
        if !arguments.contains("-no-ticks") { startTicks(hz: 1) }
        if isDiagnosing { Task { await runDiagnostics() } }
        await runLaunchScript()
    }

    /// Feeds `hz` price ticks per second into the chart; `0` stops the feed.
    private func startTicks(hz: Double) {
        tickTask?.cancel()
        tickTask = nil
        guard hz > 0 else { return }
        let period = Duration.seconds(1 / hz)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: period)
                guard let self, !Task.isCancelled else { return }
                tick()
            }
        }
    }

    /// Drives the chart from a launch argument, for unattended screenshots and smoke runs:
    /// `-script "2:back=120;5:live;7:interval=5m;9:style=line"` (seconds after launch, then an action).
    /// Actions: `back=N` scrolls N bars into the past, `live` returns to the live edge, `interval=<1m|5m|15m|1h|4h|1D>`,
    /// `style=<line|area|candles>`, `indicators=<sma20,ema50,bb,volume,rsi,macd>` (empty = none),
    /// `crosshair=<N>` puts the crosshair N bars before the newest bar (fractions allowed, `off` removes it),
    /// `zoom=<scale>` zooms the window (greater than 1 zooms in), `series=<N>` replaces the series by N bars of the current
    /// interval, `hasmore=<on|off>` sets `hasMoreHistory`, `ticks=<Hz>` sets the live feed rate (`0` stops it), and
    /// `draw=<horizontal|trend|ray>:<barsBack>,<price>[,<barsBack>,<price>]` adds a drawing (a price is a number, or `c`, `c+150`,
    /// `c-80`: relative to the last close), `select=<index|none>` selects a drawing, `move=<drawing>,<anchor>,<barsBack>,<price>`
    /// moves an anchor, `tool=<horizontal|trend|ray|off>` starts a tool, `scatter=<N>` adds N drawings spread over the series
    /// (for the performance runs), `cleardrawings` removes them all, `a11y=<scroll-left|scroll-right|scroll-next|scroll-previous|actions>` drives the
    /// chart through its accessibility tree like VoiceOver (see `AccessibilityProbe`), `extreme=<high|low>` puts the highest (lowest) bar at the right edge with the price at its tip (the case of a label under the price badge), and
    /// `fling=<barsPerSecond>[,<seconds>]` scrolls into the past like a fling (the speed decays with a time constant of 0.5 s
    /// and the window stops at the first bar; the speed is a bar count so that the same value is the same fling at any zoom), and
    /// `prepend=<N>` prepends N older bars at once, `append=<N>` appends N new bars, `stress=<seconds>[,<bars>][,bg]` sweeps the window from the live edge `bars` (default 560) bars into the past and back
    /// while recording frame times into `Documents/perf-<tag>.json` (`-perf <tag>` names the tag).
    func runLaunchScript() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-script"), flag + 1 < arguments.count else { return }
        let clock = ContinuousClock()
        let start = clock.now
        for step in arguments[flag + 1].split(separator: ";") {
            let parts = step.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let seconds = Double(parts[0]) else { continue }
            try? await clock.sleep(until: start + .seconds(seconds))
            let action = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
            switch (action[0], action.count > 1 ? action[1] : nil) {
            case ("back", let bars?):
                model.scrollPosition = model.scrollPosition.addingTimeInterval(-(Double(bars) ?? 0) * model.series.interval.seconds)
            case ("live", _):
                model.scrollToLiveEdge()
            case ("interval", let title?):
                if let option = Self.intervalOptions.first(where: { $0.title == title }) {
                    selectedInterval = option.interval
                }
            case ("style", let name?):
                if let style = SeriesStyle(rawValue: name) { model.style = style }
            case ("indicators", let names):
                let tokens = Set((names ?? "").split(separator: ",").map(String.init))
                model.indicators = Indicator.allCases.filter { tokens.contains($0.scriptName) }.map(\.chartIndicator)
            case ("crosshair", let bars?):
                if bars == "off" {
                    model.crosshairTime = nil
                } else if let count = Double(bars), let last = model.series.lastTime {
                    model.crosshairTime = last.addingTimeInterval(-count * model.series.interval.seconds)
                }
            case ("zoom", let scale?):
                if let scale = Double(scale) {
                    model.zoom(by: scale, anchor: model.isAtLiveEdge ? .liveEdge : .center)
                }
            case ("series", let count?):
                if let count = Int(count) { replaceSeries(barCount: count) }
            case ("prepend", let count?):
                if let count = Int(count), let first = model.series.firstTime,
                   let page = historyPage(before: first, count: count, interval: model.series.interval) {
                    historyPages += 1
                    model.prependHistory(page)
                }
            case ("fling", let parameters?):
                let values = parameters.split(separator: ",").compactMap { Double($0) }
                guard let speed = values.first else { break }
                await fling(barsPerSecond: speed, seconds: values.count > 1 ? values[1] : 1.8)
            case ("append", let count?):
                // New bars right after the newest one, as a live feed does at every bucket change.
                for _ in 0..<(Int(count) ?? 0) {
                    guard let last = model.series.candles?.last else { break }
                    let time = last.time.addingTimeInterval(model.series.interval.seconds)
                    model.update(price: last.close * 1.0005, at: time, volume: 100)
                }
            case ("hasmore", let flag?):
                model.hasMoreHistory = flag != "off"
            case ("ticks", let hz?):
                startTicks(hz: Double(hz) ?? 0)
            case ("draw", let description?):
                addDrawing(description)
            case ("select", let index?):
                selectDrawing(index)
            case ("tool", let name?):
                model.activeDrawingTool = Self.drawingKind(named: name)
            case ("move", let description?):
                moveAnchor(description)
            case ("scatter", let count?):
                scatterDrawings(count: Int(count) ?? 0)
            case ("cleardrawings", _):
                model.drawings = []
            case ("extreme", let kind?):
                alignExtreme(kind)
            case ("a11y", let what?):
                AccessibilityProbe.run(what, model: model)
            case ("stress", let parameters?):
                let values = parameters.split(separator: ",").compactMap { Double($0) }
                guard let seconds = values.first else { break }
                let sweep = values.count > 1 ? Int(values[1]) : PerfScenario.sweepBars
                let run = { [self] in
                    let stats = await recordStress(label: perfTag ?? "adhoc", duration: seconds, sweepBars: sweep)
                    writeReport(name: perfTag ?? "adhoc", title: "ad hoc", stats: stats, sweepBars: sweep, tickHz: nil)
                }
                // `bg` lets the next steps of the script run while the window sweeps (a prepend during a scroll).
                if parameters.hasSuffix("bg") {
                    Task { await run() }
                } else {
                    await run()
                }
            default:
                break
            }
        }
    }

    /// `extreme=high|low`: scrolls so that the highest (lowest) of the last 120 bars sits near the right edge of the window and puts the
    /// current price at its tip, so that the price badge is right where the label of that extreme goes.
    private func alignExtreme(_ kind: String) {
        guard let candles = model.series.candles, candles.count > 130 else { return }
        let pool = candles[(candles.count - 120)..<(candles.count - 8)]
        guard let bar = kind == "low" ? pool.min(by: { $0.low < $1.low }) : pool.max(by: { $0.high < $1.high }) else { return }
        model.scrollPosition = bar.time.addingTimeInterval(-(model.visibleBars - 1.5) * model.series.interval.seconds)
        model.currentPrice = kind == "low" ? bar.low : bar.high
    }

    // MARK: - Performance runs

    /// Records frame times and consistency findings for an hour, for use by hand; see `isDiagnosing`.
    private func runDiagnostics() async {
        let tracker = ViolationTracker()
        let model = model
        let recorder = recorder
        var lastWrite = 0.0
        _ = await recorder.record(label: "diag", duration: 3_600) { elapsed in
            tracker.add(ChartDiagnostics.violations(of: model))
            let v = tracker.total
            recorder.note = "viol \(v.total)  window \(v.windowCoverage)  stale \(v.staleBase)  data \(v.dataOutsideDomain)  base \(v.targetOutsideBase)"
            if elapsed - lastWrite >= 1 {
                lastWrite = elapsed
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("diag.json")
                let json = "{\"elapsed\": \(elapsed), \"violations\": \(v.total), \"windowCoverage\": \(v.windowCoverage), \"staleBase\": \(v.staleBase), \"dataOutsideDomain\": \(v.dataOutsideDomain), \"targetOutsideBase\": \(v.targetOutsideBase)}"
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// One scenario of `Docs/Performance.md`: set the chart up, let it settle, sweep the window for five seconds.
    private func runPerfScenario(_ scenario: PerfScenario) async {
        model.configuration.maxLiveBarCount = nil
        model.hasMoreHistory = false
        replaceSeries(barCount: scenario.barCount)
        model.indicators = scenario.indicators.map(\.chartIndicator)
        try? await Task.sleep(for: .seconds(PerfScenario.warmUp))
        startTicks(hz: scenario.tickHz)
        let stats = await recordStress(
            label: scenario.rawValue,
            duration: PerfScenario.duration,
            sweepBars: PerfScenario.sweepBars
        )
        startTicks(hz: 0)
        writeReport(
            name: scenario.rawValue,
            title: scenario.title,
            stats: stats,
            sweepBars: PerfScenario.sweepBars,
            tickHz: scenario.tickHz
        )
    }

    /// Sweeps the window from the live edge into the past and back (a triangle wave over `duration`) at the pace of the
    /// display, recording the frame times.
    private func recordStress(label: String, duration: TimeInterval, sweepBars: Int) async -> FrameStats {
        model.scrollToLiveEdge()
        let live = model.scrollPosition
        let barSeconds = model.series.interval.seconds
        let model = model
        ChartDiagnostics.reset(model)
        violations = ChartDiagnostics.Violations()
        let tracker = ViolationTracker()
        // `-wiggle` moves an anchor of the first drawing on every frame, as a drag does.
        let wiggles = ProcessInfo.processInfo.arguments.contains("-wiggle")
        let stats = await recorder.record(label: label, duration: duration) { elapsed in
            // The state the last step left, after the charts caught up with it, then the next step.
            tracker.add(ChartDiagnostics.violations(of: model))
            let progress = elapsed / duration
            let depth = progress < 0.5 ? 2 * progress : 2 - 2 * progress
            model.scrollPosition = live.addingTimeInterval(-depth * Double(sweepBars) * barSeconds)
            if wiggles { self.wiggleDrawing(at: elapsed) }
            // The model alone, right after the step: its domains must hold the data of the new window.
            tracker.addModel(ChartDiagnostics.violations(of: model))
        }
        violations = tracker.total
        recorder.annotate("viol \(tracker.total.total)")
        return stats
    }

    /// Scrolls into the past with a speed that decays exponentially (time constant 0.5 s), one step per display frame, and
    /// stops at the first bar of the series (where a scroll view stops: the offset is clamped to the content).
    private func fling(barsPerSecond: Double, seconds: TimeInterval) async {
        let start = model.scrollPosition
        let barSeconds = model.series.interval.seconds
        let tau = 0.5
        let model = model
        _ = await recorder.record(label: "fling", duration: seconds) { elapsed in
            let travelled = barsPerSecond * tau * (1 - exp(-elapsed / tau)) * barSeconds
            var position = start.addingTimeInterval(-travelled)
            if let first = model.series.firstTime, position < first { position = first }
            // Prepended history moves the first bar: a fling that began before it goes on from where the window is.
            if position < model.scrollPosition || elapsed == 0 { model.scrollPosition = position }
        }
    }

    private func writeReport(name: String, title: String, stats: FrameStats, sweepBars: Int, tickHz: Double?) {
        let report = PerfReport(
            scenario: name,
            title: title,
            build: PerfReport.buildConfiguration,
            device: PerfReport.deviceName,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            bars: model.series.count,
            indicators: model.indicators.map(\.id),
            tickHz: tickHz ?? 0,
            sweepBars: sweepBars,
            visibleBars: model.visibleBars,
            loadAverage: PerfReport.currentLoadAverage,
            stats: stats,
            bodies: {
                let counts = ChartDiagnostics.counts(of: model)
                return ["main": counts.main, "panes": counts.panes, "axes": counts.axes, "charts": counts.charts, "commits": counts.commits, "windowMoves": counts.windowMoves, "rebases": counts.rebases]
            }(),
            violations: [
                "windowCoverage": violations.windowCoverage,
                "staleBase": violations.staleBase,
                "dataOutsideDomain": violations.dataOutsideDomain,
                "targetOutsideBase": violations.targetOutsideBase,
            ]
        )
        do {
            let url = try report.write(named: name)
            NSLog("perf-report %@", url.path)
        } catch {
            NSLog("perf-report failed: %@", String(describing: error))
        }
    }

    /// Replaces the series by `barCount` candles of the current interval, ending now, and shows the live edge.
    private func replaceSeries(barCount: Int) {
        let series = Self.makeSeries(
            interval: model.series.interval,
            lastClose: RandomWalk.basePrice,
            count: barCount
        )
        model.setSeries(series, scroll: .liveEdge)
        model.markers = Self.markers(for: series)
        model.currentPrice = series.lastValue
    }

    private func tick() {
        guard let last = model.currentPrice ?? model.series.lastValue else { return }
        let price = last * (1 + tickGenerator.gaussian() * 0.0004)
        model.update(price: price, at: Date(), volume: abs(tickGenerator.gaussian()) * 40)
        if !ProcessInfo.processInfo.arguments.contains("-tick-no-price") { model.currentPrice = price }
    }

    private func loadSeries(for interval: ChartInterval) {
        loadTask?.cancel()
        historyTask?.cancel()
        historyTask = nil
        model.isLoadingHistory = false
        isLoading = true
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.intervalLoadDelay)
            guard let self, !Task.isCancelled else { return }
            let series = Self.makeSeries(interval: interval, lastClose: model.currentPrice ?? RandomWalk.basePrice)
            historyTask?.cancel()
            historyTask = nil
            historyPages = 0
            model.setSeries(series)
            model.hasMoreHistory = true
            model.markers = Self.markers(for: series)
            model.currentPrice = series.lastValue
            isLoading = false
        }
    }

    private func handle(_ event: TradingChartEvent) {
        switch event {
        case .approachedHistoryStart:
            loadHistory()
        case .drawing(.added), .drawing(.changed), .drawing(.removed):
            drawingsRevision += 1
        default:
            break
        }
    }

    /// Emulates a paged history source: every request takes 0.6 s and returns 300 bars; after five pages
    /// the source is exhausted.
    private func loadHistory() {
        guard historyTask == nil, model.hasMoreHistory else { return }
        model.isLoadingHistory = true
        let interval = model.series.interval
        historyTask = Task { [weak self] in
            try? await Task.sleep(for: Self.historyDelay)
            guard let self, !Task.isCancelled else { return }
            defer { historyTask = nil }
            guard model.series.interval == interval, let first = model.series.candles?.first else {
                model.isLoadingHistory = false
                return
            }
            guard let older = historyPage(before: first.time, count: Self.barsPerPage, interval: interval) else { return }
            historyPages += 1
            model.prependHistory(older)
            if historyPages >= Self.maxHistoryPages { model.hasMoreHistory = false }
        }
    }

    /// `count` bars that end right before `time`, continuing the walk from the open of the first loaded bar.
    private func historyPage(before time: Date, count: Int, interval: ChartInterval) -> ChartSeries? {
        guard let first = model.series.candles?.first else { return nil }
        return ChartSeries(
            candles: RandomWalk.candles(
                count: count,
                interval: interval,
                lastBucketStart: time.addingTimeInterval(-interval.seconds),
                lastClose: first.open,
                seed: UInt64(interval.seconds) &+ UInt64(historyPages + 1) &* 7_919
            ),
            interval: interval
        )
    }

    private static func makeSeries(
        interval: ChartInterval,
        lastClose: Double,
        count: Int = barsPerPage
    ) -> ChartSeries {
        ChartSeries(
            candles: RandomWalk.candles(
                count: count,
                interval: interval,
                lastBucketStart: interval.bucketStart(for: Date()),
                lastClose: lastClose,
                seed: UInt64(interval.seconds)
            ),
            interval: interval
        )
    }

    private static func markers(for series: ChartSeries) -> [ChartMarker] {
        guard series.count > 60, !ProcessInfo.processInfo.arguments.contains("-no-markers") else { return [] }
        return [
            ChartMarker(id: "buy", time: series.points[series.count - 60].time, kind: .buy),
            ChartMarker(id: "sell", time: series.points[series.count - 25].time, kind: .sell),
        ]
    }
}

/// Drives the chart the way VoiceOver does, through the accessibility tree and not through the model, and writes what it found
/// to `Documents/a11y.json`: `a11y=scroll-left|scroll-right|actions`. The tree exists while an accessibility client is attached
/// (an XCUITest, or VoiceOver). `scroll-left` is the three-finger swipe to the left (the content moves left: later data).
@MainActor
enum AccessibilityProbe {
    static func run(_ what: String, model: TradingChartModel) {
        var report: [String: Any] = ["what": what]
        if what == "uikit" {
            // What the directions mean: a real scroll view in the middle of its content, scrolled by the accessibility call.
            let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
            let scroll = UIScrollView(frame: CGRect(x: 0, y: 300, width: 100, height: 100))
            scroll.contentSize = CGSize(width: 1000, height: 100)
            scroll.isPagingEnabled = true
            window?.addSubview(scroll)
            scroll.setContentOffset(CGPoint(x: 300, y: 0), animated: false)
            let start = scroll.contentOffset.x
            report["leftHandled"] = scroll.accessibilityScroll(.left)
            report["afterLeft"] = scroll.contentOffset.x - start
            scroll.setContentOffset(CGPoint(x: 300, y: 0), animated: false)
            report["rightHandled"] = scroll.accessibilityScroll(.right)
            report["afterRight"] = scroll.contentOffset.x - 300
            scroll.setContentOffset(CGPoint(x: 300, y: 0), animated: false)
            report["nextHandled"] = scroll.accessibilityScroll(.next)
            report["afterNext"] = scroll.contentOffset.x - 300
            scroll.removeFromSuperview()
            write(report)
            return
        }
        let before = model.scrollPosition
        guard let element = find(prefix: "Candlestick chart") else {
            report["error"] = "no element with the label of the chart"
            write(report)
            return
        }
        report["label"] = element.accessibilityLabel ?? ""
        report["value"] = element.accessibilityValue ?? ""
        report["class"] = String(describing: type(of: element))
        report["actions"] = element.accessibilityCustomActions?.map(\.name) ?? []
        switch what {
        case "scroll-left": report["handled"] = element.accessibilityScroll(.left)
        case "scroll-right": report["handled"] = element.accessibilityScroll(.right)
        case "scroll-next": report["handled"] = element.accessibilityScroll(.next)
        case "scroll-previous": report["handled"] = element.accessibilityScroll(.previous)
        default: break
        }
        report["movedSeconds"] = model.scrollPosition.timeIntervalSince(before)
        report["windowSeconds"] = model.visibleDuration
        write(report)
    }

    /// The first element of the accessibility tree whose label starts with `prefix`.
    private static func find(prefix: String) -> NSObject? {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }
        for window in windows {
            if let found = find(prefix: prefix, in: window, depth: 0) { return found }
        }
        return nil
    }

    private static func find(prefix: String, in object: NSObject, depth: Int) -> NSObject? {
        guard depth < 40 else { return nil }
        if let label = object.accessibilityLabel, label.hasPrefix(prefix) { return object }
        var children: [NSObject] = []
        if let view = object as? UIView {
            children += (view.accessibilityElements ?? []).compactMap { $0 as? NSObject }
            children += view.subviews
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) }
            }
        }
        for child in children {
            if let found = find(prefix: prefix, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func write(_ report: [String: Any]) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("a11y.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}

/// Adds up the findings of `ChartDiagnostics.violations` over the frames of a stress run.
@MainActor
private final class ViolationTracker {
    private(set) var total = ChartDiagnostics.Violations()
    private var previousStale = 0

    /// The charts' view of the state: whether they caught up with the model (windows, bases) and hold the data.
    /// A pane that is behind the model at one check is usually just waiting for the update the same run loop turn
    /// brings (a tick and the check can fall into one turn); only one that is still behind at the next check counts.
    func add(_ found: ChartDiagnostics.Violations) {
        var counted = found
        counted.staleBase = min(found.staleBase, previousStale)
        previousStale = found.staleBase
        total += counted
    }

    /// Right after a step only the model is up to date; the charts follow in the same frame. Only the part that must
    /// hold at once counts: the domain shown must hold the data.
    func addModel(_ found: ChartDiagnostics.Violations) {
        total.dataOutsideDomain += found.dataOutsideDomain
        total.targetOutsideBase += found.targetOutsideBase
    }
}
