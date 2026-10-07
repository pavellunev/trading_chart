import Foundation
import Observation
import TradingChartCore

/// The observable state of a chart: the data series, the style, the scrolling window and the overlays.
///
/// The scroll anchor (``scrollPosition``, the left edge of the window) lives here and is changed in the same
/// synchronous mutation as the data, so the view never renders a frame with new data and a stale window.
/// Everything that depends on bar size is derived from ``series``'s own interval, never from a picker in the host UI.
///
/// ## Topics
///
/// ### Creating a model
///
/// - ``init(series:style:configuration:)``
/// - ``configuration``
///
/// ### Data
///
/// - ``series``
/// - ``setSeries(_:scroll:)``
/// - ``ScrollBehavior``
/// - ``update(price:at:volume:)``
/// - ``update(_:interval:)-(Candle,_)``
/// - ``update(_:interval:)-(PricePoint,_)``
/// - ``prependHistory(_:)``
/// - ``style``
/// - ``currentPrice``
/// - ``markers``
///
/// ### Indicators
///
/// - ``indicators``
/// - ``output(for:)``
///
/// ### The window
///
/// - ``scrollPosition``
/// - ``visibleBars``
/// - ``visibleDuration``
/// - ``visibleTimeRange``
/// - ``isAtLiveEdge``
/// - ``scrollToLiveEdge()``
/// - ``zoom(by:anchor:)``
///
/// ### The crosshair
///
/// - ``crosshair``
/// - ``crosshairTime``
///
/// ### Paging history
///
/// - ``isLoadingHistory``
/// - ``hasMoreHistory``
///
/// ### Persistence
///
/// - ``TradingChartConfiguration/persistence``
/// - ``ChartPersistence``
///
/// ### Drawings
///
/// - ``drawings``
/// - ``activeDrawingTool``
/// - ``selectedDrawingID``
/// - ``drawingTools``
/// - ``deleteSelectedDrawing()``
/// - ``removeDrawing(id:)``
/// - ``removeAllDrawings()``
///
/// ### Events
///
/// - ``onEvent``
@available(iOS 17.0, *)
@MainActor
@Observable
public final class TradingChartModel {

    /// How ``setSeries(_:scroll:)`` treats the scroll position.
    public enum ScrollBehavior: Sendable {
        /// Jump to the live edge when the interval changed or the window was already at the live edge.
        case automatic
        /// Always jump to the live edge.
        case liveEdge
        /// Keep the scroll position as it is.
        case preserve
    }

    /// Behaviour and layout options.
    public var configuration: TradingChartConfiguration {
        didSet {
            viewportInputsDidChange()
            if !configuration.isCrosshairEnabled, crosshairTime != nil { crosshairTime = nil }
            if oldValue.isDrawingEnabled, !configuration.isDrawingEnabled { cancelDrawingInteraction() }
            persistenceDidChange(from: oldValue.persistence)
        }
    }

    /// The displayed data. Change it through ``setSeries(_:scroll:)``, ``update(price:at:volume:)`` and ``prependHistory(_:)``.
    public private(set) var series: ChartSeries

    /// How the series is drawn. Changing it resets the window to the default width of the new style and scrolls to the live edge.
    public var style: SeriesStyle {
        didSet {
            guard style != oldValue else { return }
            styleDidChange()
            persistStyle()
        }
    }

    /// The latest price: draws the dashed line and the badge. `nil` hides both.
    public var currentPrice: Double? {
        didSet {
            if (oldValue == nil) != (currentPrice == nil) {
                viewportInputsDidChange()
            } else if oldValue != currentPrice, !isBatching {
                refreshRenderState(.structural, dataChanged: false)
            }
        }
    }

    /// Trade markers shown on the series.
    public var markers: [ChartMarker]

    /// Indicators calculated from the series. Entries with a duplicate ``ChartIndicator/id`` are dropped.
    public var indicators: [any ChartIndicator] {
        didSet { indicatorsDidChange(from: oldValue) }
    }

    /// The left edge of the visible window. ``TradingChartView`` moves it when the user scrolls (a drag, and a fling after it)
    /// and the charts follow it. Setting it yourself ends a fling in progress.
    public var scrollPosition: Date {
        didSet {
            // A change that is not the finger's or the fling's (the host, a zoom, a new series) ends the fling.
            if !isDrivingScroll { stopScrollMomentum() }
            guard !isBatching else { return }
            scrollDidChange()
        }
    }

    /// The number of bars across the visible window.
    public private(set) var visibleBars: Double

    /// The raw time of the crosshair selection reported by the chart. `nil` when there is no selection.
    ///
    /// The chart sets it while the user holds a finger on it; it may also be set from code. ``crosshair`` is the
    /// snapped bar this time falls on, and ``TradingChartEvent/crosshairChanged(_:)`` fires when that bar changes.
    public var crosshairTime: Date? {
        didSet { crosshairTimeDidChange() }
    }

    /// Whether the host is loading older history. Set it to `true` when you start a request (typically in response
    /// to ``TradingChartEvent/approachedHistoryStart``): no new ``TradingChartEvent/approachedHistoryStart`` is sent
    /// while it is `true`, and the chart shows a loading indicator at the left edge. ``prependHistory(_:)`` and
    /// ``setSeries(_:scroll:)`` reset it to `false`, so a request that ends with a page, with an empty page or with
    /// a page of another interval never leaves the chart waiting. Set it back to `false` yourself when a request fails;
    /// that allows ``TradingChartEvent/approachedHistoryStart`` to fire again.
    public var isLoadingHistory = false {
        didSet {
            // Only the end of a request can make the next one due.
            guard isLoadingHistory != oldValue, !isLoadingHistory else { return }
            historyRequestMayBeDue()
        }
    }

    /// Whether the source has more history than is loaded. Set it to `false` when the source is exhausted:
    /// ``TradingChartEvent/approachedHistoryStart`` is not sent while it is `false`. Setting it back to `true`
    /// (for example for a new instrument) allows the event to fire again.
    public var hasMoreHistory = true {
        didSet {
            guard hasMoreHistory != oldValue, hasMoreHistory else { return }
            historyRequestMayBeDue()
        }
    }

    /// The tools that create drawings and turn them into shapes. Starts as ``DrawingToolRegistry/standard`` (horizontal
    /// line, trend line, ray); register your own kinds with ``DrawingToolRegistry/register(_:)``.
    ///
    /// The drawings themselves (``drawings``, ``activeDrawingTool``, ``selectedDrawingID`` and the methods that remove
    /// them) are declared in `TradingChartModel+Drawing.swift`.
    public var drawingTools: DrawingToolRegistry = .standard

    /// The state machine behind the drawings: creation, selection, dragging. Read by the drawing overlay, which is the one
    /// thing a drag of a drawing invalidates.
    var drawingEditor = DrawingEditor()

    /// Where the finger was relative to the anchor it grabbed, so that the anchor does not jump under the finger.
    @ObservationIgnored var drawingGrabOffset = CGSize.zero

    /// Set while what was saved is put back (``TradingChartConfiguration/persistence``): the values that come out of the store
    /// are not written back to it.
    @ObservationIgnored var isRestoringPersistence = false

    /// The place (``ChartPersistence/drawingsStoreKey``) whose drawings are on the chart. It stays when the key is taken away
    /// (a `nil` ``ChartPersistence/drawingsKey``, no persistence at all): the drawings on the chart still are the ones of
    /// that key, and no other key may adopt them. `nil` only while the drawings belong to no key.
    @ObservationIgnored var shownDrawingsKey: String?

    /// Receives chart notifications.
    ///
    /// There is one handler: assigning it replaces the previous one. Handle every event you care about in a single closure
    /// (a `switch` over ``TradingChartEvent``), and in particular do not assign it once for history paging and again for
    /// the crosshair or the drawings: the last assignment wins and the paging stops.
    @ObservationIgnored
    public var onEvent: (@MainActor (TradingChartEvent) -> Void)?

    /// The viewport configuration every geometry calculation uses: ``configuration``'s viewport with the right padding
    /// and the live-edge tolerance adapted to the zoom level, and the padding widened so that the last bar stays clear
    /// of the price badge (see ``ViewportMath/effectiveConfiguration(_:visibleBars:plotWidth:badgeOverhang:)``).
    /// The single source for `ViewportMath` calls, in the model and in the view.
    private(set) var viewport: ViewportConfiguration

    /// Width of the visible plot area in points, reported by the view.
    private(set) var plotWidth: CGFloat = 0

    /// Width of the price badge in points, reported by the view; `0` while the badge is not shown.
    private(set) var badgeWidth: CGFloat = 0

    /// The size of the price badge as it is on the screen (with the return chevron when it has one), reported by the view;
    /// `.zero` until it is measured. The labels of the highest and the lowest price keep clear of it.
    private(set) var badgeSize = CGSize.zero

    /// Width of the price axis column to the right of the plot in points, reported by the view. The badge sits on
    /// this column and only the part wider than it reaches into the plot.
    private(set) var yAxisColumnWidth: CGFloat = 0

    /// ``visibleDuration`` as the charts are told it (`chartXVisibleDomain`). The same value, but stored and assigned only when it
    /// changes (a zoom, a style, another interval): ``visibleDuration`` reads ``series``, and a pane that read that would be
    /// rebuilt by every live tick.
    private(set) var chartVisibleDuration: TimeInterval

    /// How the theme draws candles, reported by the view; what the autoscale at the edges of the window assumes about the
    /// width of a candle.
    @ObservationIgnored var candleMetrics = CandleMetrics(theme: .standard)

    /// What the panes were last built with and how often; see ``ChartDiagnostics``.
    let renderCounters = RenderCounters()

    /// A tiny offset, alternating between `0` and a thousandth of a bar, that the chart adds to the scroll position it is
    /// given (see ``chartScrollBinding``). It flips whenever the left end of the time domain of the charts moves (the series
    /// replaced, history prepended beyond the reserve; see ``chartXDomain``): Swift Charts keeps the scroll offset in points
    /// when that end moves, so the window would shift (or show nothing) until the position it is bound to changes.
    /// ``scrollPosition`` itself never includes it.
    var scrollNudge: TimeInterval = 0

    /// The left end of the time domain the charts are laid out for, held back from the first bar (see ``chartXDomain``).
    @ObservationIgnored var chartDomainStart: Date?
    /// The left end of the chart domain as the charts last saw it; ``scrollNudge`` flips when it changes.
    @ObservationIgnored var lastChartDomainLower: Date?
    /// Set by whatever replaces the series or changes what the domain is made of: the held-back start is chosen anew.
    @ObservationIgnored var domainStartNeedsReset = true
    /// History was prepended beyond the reserve while the window was moving: the domain is extended when it stops.
    @ObservationIgnored var domainExpansionPending = false

    // MARK: Render state
    //
    // What the views build their marks from. It follows the window and the data, but changes much more rarely than
    // ``scrollPosition``, and the views read it instead of the scroll position, so that a scroll step does not rebuild
    // the charts. Maintained by `refreshRenderState` (see `TradingChartModel+RenderState.swift`).

    /// The time range marks are built for: the visible window and its buffer. Moves only when the visible window
    /// comes close to its edge (see ``RenderWindowPolicy``).
    var renderWindow: ClosedRange<Date> = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1)
    /// The ticks of the time axis inside the render window.
    var xTicks: [Date] = []
    /// The Y domain the main chart is laid out for. Moves only when the transform to ``mainYTarget`` gets too strong
    /// (see ``YTransformMath``), when the data changes, and when scrolling stops.
    var mainYBase: ClosedRange<Double> = 0...1
    /// The Y domain of the main pane that is shown: the autoscaled domain of the visible window, on every scroll step.
    var mainYTarget: ClosedRange<Double> = 0...1
    /// The visible window as it was when scrolling last came to rest (and after every change of the data or the layout). Only
    /// the accessibility value reads it, so it is not rebuilt by every scroll step.
    var settledWindow: ClosedRange<Date> = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1)
    /// What the chart bodies build their marks from; see ``renderInput``.
    @ObservationIgnored var renderData: RenderData
    /// Bumped when what the marks are built from changed in a way the charts have to show. Reading ``renderInput`` depends
    /// on it.
    var renderRevision = 0
    @ObservationIgnored var renderDirty = false
    /// The render state of the indicator panes, by indicator id.
    @ObservationIgnored var paneStates: [String: PaneRenderState] = [:]
    @ObservationIgnored var scrollClock = ScrollClock.system
    // Scrolling by touch (see `TradingChartModel+Scrolling.swift`).
    @ObservationIgnored var frameTicker = FrameTicker.display
    @ObservationIgnored var scrollMomentum: ScrollMomentum?
    @ObservationIgnored var scrollMomentumPlotWidth: Double = 0
    @ObservationIgnored var cancelMomentumTicker: (@MainActor () -> Void)?
    @ObservationIgnored var touchScrollStart: Date?
    @ObservationIgnored var isDrivingScroll = false
    @ObservationIgnored var isScrollActive = false
    @ObservationIgnored var isSettlePending = false
    @ObservationIgnored var lastScrollTime: TimeInterval = 0
    @ObservationIgnored var lastScrollPosition = Date(timeIntervalSince1970: 0)
    /// Window widths per second, positive towards the future.
    @ObservationIgnored var scrollVelocity: Double = 0

    var indicatorOutputs: [String: IndicatorOutput] = [:]
    /// First palette index of each indicator, dealt out in order (see ``IndicatorPalette``).
    private var paletteBases: [String: Int] = [:]

    /// Bumped whenever a new history request may become due: a new series, older bars prepended, a request ended,
    /// more history became available. ``TradingChartEvent/approachedHistoryStart`` is sent at most once per value.
    @ObservationIgnored private var historyEpoch = 0
    @ObservationIgnored private var historyRequestEpoch = -1
    @ObservationIgnored private var lastReportedLiveEdge = true
    @ObservationIgnored var isBatching = false
    @ObservationIgnored private var lastReportedCrosshairTime: Date?

    /// Creates a model.
    ///
    /// With ``TradingChartConfiguration/persistence`` set, the style, the indicators and the drawings that were saved are
    /// restored before the first frame: a saved style replaces `style`, which is then only the default for a first launch.
    public init(
        series: ChartSeries = .empty(interval: .minutes(1)),
        style: SeriesStyle = .candles,
        configuration: TradingChartConfiguration = TradingChartConfiguration()
    ) {
        let persistence = configuration.persistence
        let style = persistence?.restoredStyle(offeredBy: configuration.stylePicker) ?? style
        let bars = configuration.viewport.defaultVisibleBars(for: style)
        let effective = ViewportMath.effectiveConfiguration(
            configuration.viewport,
            visibleBars: bars,
            plotWidth: 0,
            badgeOverhang: nil
        )
        self.configuration = configuration
        self.series = series
        self.style = style
        self.markers = []
        self.indicators = persistence?.restoredIndicators() ?? []
        self.visibleBars = bars
        self.chartVisibleDuration = bars * series.interval.seconds
        self.viewport = effective
        self.renderData = RenderData(series: series, outputs: [:], paletteBases: [:])
        if let last = series.lastTime {
            self.scrollPosition = ViewportMath.endAnchor(
                lastTime: last,
                interval: series.interval,
                visibleBars: bars,
                configuration: effective
            )
        } else {
            self.scrollPosition = Date()
        }
        if let drawings = persistence?.restoredDrawings() { drawingEditor.setDrawings(drawings) }
        shownDrawingsKey = persistence?.drawingsStoreKey
        if !indicators.isEmpty {
            recomputeIndicators()
            renderData = RenderData(series: series, outputs: indicatorOutputs, paletteBases: paletteBases)
        }
        refreshChartDomain()
        refreshRenderState(.structural, dataChanged: true)
    }

    /// The series, the indicator outputs and the palette bases the chart bodies build marks from.
    ///
    /// Reading it makes a view depend on the render revision, not on ``series`` itself: a live update that only touches
    /// bars outside the render window (the user looks at the history while ticks arrive) does not rebuild the charts.
    var renderInput: RenderData {
        _ = renderRevision
        return renderData
    }

    // MARK: - Viewport

    /// The width of the visible window in seconds.
    public var visibleDuration: TimeInterval {
        visibleBars * series.interval.seconds
    }

    /// The visible window: from ``scrollPosition`` for ``visibleDuration``.
    public var visibleTimeRange: ClosedRange<Date> {
        scrollPosition...scrollPosition.addingTimeInterval(visibleDuration)
    }

    /// Whether the window shows the newest bar at its right edge (within a small tolerance).
    ///
    /// A stored property that is assigned only when the answer changes, so a view that reads it is not rebuilt
    /// by every scroll step.
    public internal(set) var isAtLiveEdge = true

    /// The same answer, computed from the current window.
    var liveEdgeNow: Bool {
        ViewportMath.isAtLiveEdge(
            scrollPosition: scrollPosition,
            lastTime: series.lastTime,
            interval: series.interval,
            visibleBars: visibleBars,
            configuration: viewport
        )
    }

    /// Scrolls so that the newest bar sits at the right edge.
    public func scrollToLiveEdge() {
        batch { moveToLiveEdge() }
    }

    /// Zooms the window by `scale` (greater than 1 zooms in), clamped to the configured bar counts. A chart without bars does
    /// not zoom.
    ///
    /// - Parameters:
    ///   - scale: Factor relative to the current width; the new width is `visibleBars / scale`.
    ///   - anchor: The part of the window that stays in place.
    public func zoom(by scale: Double, anchor: ZoomAnchor) {
        zoom(from: zoomBaseline(), by: scale, anchor: anchor)
    }

    /// The window as it was when a pinch gesture started.
    struct ZoomBaseline: Equatable {
        var scrollPosition: Date
        var visibleBars: Double
    }

    /// Captures the window at the start of a pinch gesture.
    func zoomBaseline() -> ZoomBaseline {
        ZoomBaseline(scrollPosition: scrollPosition, visibleBars: visibleBars)
    }

    /// Zooms relative to `baseline` instead of the current window, so a gesture reports its total magnification
    /// and repeated calls neither accumulate nor drift once the width is clamped.
    func zoom(from baseline: ZoomBaseline, by scale: Double, anchor: ZoomAnchor) {
        // The window of an empty series follows scrollPosition, which a zoom around the centre would move.
        guard !series.isEmpty else { return }
        let result = ViewportMath.zoomed(
            scrollPosition: baseline.scrollPosition,
            visibleBars: baseline.visibleBars,
            scale: scale,
            anchor: anchor,
            lastTime: series.lastTime,
            interval: series.interval,
            configuration: viewport
        )
        batch {
            visibleBars = result.visibleBars
            scrollPosition = result.scrollPosition
            // The badge padding is measured in bars, so a new width changes it; the live edge must follow.
            if refreshViewport(), anchor == .liveEdge { moveToLiveEdge() }
        }
    }

    // MARK: - Crosshair

    /// The bar under the crosshair, snapped to the nearest bar of the series, or `nil` without a selection
    /// (also when the crosshair is disabled or the series is empty).
    public var crosshair: CrosshairState? {
        guard configuration.isCrosshairEnabled,
              let crosshairTime,
              let index = series.index(nearestTo: crosshairTime)
        else { return nil }
        return crosshairState(atBar: index)
    }

    /// The state of the newest bar: what the legend shows while there is no crosshair.
    var latestBarState: CrosshairState? {
        series.isEmpty ? nil : crosshairState(atBar: series.count - 1)
    }

    private func crosshairState(atBar index: Int) -> CrosshairState {
        let point = series.points[index]
        return CrosshairState(
            time: point.time,
            candle: series.candles?[index],
            value: point.value,
            previousClose: index > 0 ? series.points[index - 1].value : nil,
            indicatorValues: indicatorValues(at: point.time)
        )
    }

    private func indicatorValues(at time: Date) -> [CrosshairIndicatorValue] {
        var result: [CrosshairIndicatorValue] = []
        for indicator in indicators {
            guard let output = indicatorOutputs[indicator.id] else { continue }
            let base = paletteBases[indicator.id] ?? 0
            for line in output.lines {
                guard let value = IndicatorRendering.value(in: line.values, at: time) else { continue }
                result.append(CrosshairIndicatorValue(
                    indicatorID: indicator.id,
                    name: line.name,
                    value: value,
                    color: line.style.color,
                    paletteIndex: line.style.color == nil ? base + Swift.max(line.paletteSlot, 0) : nil
                ))
            }
            for histogram in output.histograms {
                guard let bar = IndicatorRendering.bar(in: histogram.bars, at: time) else { continue }
                result.append(CrosshairIndicatorValue(
                    indicatorID: indicator.id,
                    name: histogram.name,
                    value: bar.value,
                    color: bar.color,
                    tone: bar.tone
                ))
            }
        }
        return result
    }

    /// The first palette index of the indicator with the given id (see ``IndicatorPalette``).
    func paletteBase(for indicatorID: String) -> Int {
        paletteBases[indicatorID] ?? 0
    }

    private func crosshairTimeDidChange() {
        let snapped = crosshair
        guard snapped?.time != lastReportedCrosshairTime else { return }
        lastReportedCrosshairTime = snapped?.time
        onEvent?(.crosshairChanged(snapped))
    }

    // MARK: - Data

    /// Replaces the series.
    ///
    /// The scroll position changes in the same mutation as the data. With ``ScrollBehavior/automatic`` the window
    /// jumps to the live edge when the interval changed or the window was at the live edge before the replacement.
    public func setSeries(_ new: ChartSeries, scroll: ScrollBehavior = .automatic) {
        let intervalChanged = new.interval != series.interval
        let wasAtLiveEdge = liveEdgeNow
        batch {
            series = new
            domainStartNeedsReset = true
            historyEpoch += 1
            // A new series ends whatever request was running for the old one.
            isLoadingHistory = false
            recomputeIndicators()
            if intervalChanged, crosshairTime != nil { crosshairTime = nil }
            switch scroll {
            case .automatic:
                if intervalChanged || wasAtLiveEdge { moveToLiveEdge() }
            case .liveEdge:
                moveToLiveEdge()
            case .preserve:
                break
            }
        }
    }

    /// Inserts or updates a candle (a live OHLC update).
    ///
    /// - Parameters:
    ///   - candle: The candle to insert, or to merge into the last bar.
    ///   - interval: The interval the candle was built for. When it differs from the series interval the update is dropped.
    /// - Returns: What happened to the series; ``ChartSeries/UpdateResult/ignored`` also covers a foreign interval.
    @discardableResult
    public func update(_ candle: Candle, interval: ChartInterval? = nil) -> ChartSeries.UpdateResult {
        guard accepts(interval) else { return .ignored }
        let maxCount = liveMaxBarCount
        let keepingFrom = trimProtectionBoundary
        return mutateSeries { $0.upsert(candle, maxCount: maxCount, keepingFrom: keepingFrom) }
    }

    /// Inserts or updates a point (a live update of a line series).
    ///
    /// - Parameters:
    ///   - point: The point to insert, or to replace the last point with.
    ///   - interval: The interval the point was built for. When it differs from the series interval the update is dropped.
    /// - Returns: What happened to the series; ``ChartSeries/UpdateResult/ignored`` also covers a foreign interval.
    @discardableResult
    public func update(_ point: PricePoint, interval: ChartInterval? = nil) -> ChartSeries.UpdateResult {
        guard accepts(interval) else { return .ignored }
        let maxCount = liveMaxBarCount
        let keepingFrom = trimProtectionBoundary
        return mutateSeries { $0.upsert(point, maxCount: maxCount, keepingFrom: keepingFrom) }
    }

    /// Applies a price tick to the bar the time falls into, creating a new bar when a new bucket starts.
    @discardableResult
    public func update(price: Double, at time: Date, volume: Double? = nil) -> ChartSeries.UpdateResult {
        let maxCount = liveMaxBarCount
        let keepingFrom = trimProtectionBoundary
        return mutateSeries { $0.apply(price: price, at: time, volume: volume, maxCount: maxCount, keepingFrom: keepingFrom) }
    }

    /// Prepends older history. The scroll position (a date) is left alone, so the visible content does not move:
    /// ``scrollPosition`` and ``visibleTimeRange`` are the same before and after, and the indicators are recalculated
    /// over the longer series (their warm-up at the former start is filled in).
    ///
    /// Only bars older than the current first bar are taken; a series with another interval is ignored. The series keeps its
    /// kind: a page of the other kind is converted to it (``ChartSeries/prepend(_:)``), candles to points by close and points to
    /// flat candles. An empty series takes the kind of the page.
    /// In every case ``isLoadingHistory`` goes back to `false`, so the request the host made is over. A call that adds
    /// no bars (an empty page, a page of another interval, a page that overlaps what is loaded) does not make the chart
    /// ask for history again by itself; set ``hasMoreHistory`` to `false` when the source has nothing more.
    public func prependHistory(_ older: ChartSeries) {
        let countBefore = series.count
        let epochBefore = historyEpoch
        batch {
            series.prepend(older)
            let added = series.count != countBefore
            if added {
                historyEpoch += 1
                recomputeIndicators()
            }
            isLoadingHistory = false
            if !added { historyEpoch = epochBefore }
        }
    }

    /// The cached output of the indicator with the given ``ChartIndicator/id``, or `nil` for an unknown id.
    public func output(for indicatorID: String) -> IndicatorOutput? {
        indicatorOutputs[indicatorID]
    }

    // MARK: - Internals

    /// The bound a live update trims the series to: none while history is being loaded. A page of history ends at the first
    /// bar the host knew when it asked; cutting bars off the head meanwhile would leave a hole between the page and the series.
    /// The next update after the request is over trims again.
    private var liveMaxBarCount: Int? {
        isLoadingHistory ? nil : configuration.maxLiveBarCount
    }

    private func accepts(_ interval: ChartInterval?) -> Bool {
        guard let interval else { return true }
        return interval == series.interval
    }

    private func mutateSeries(_ mutation: (inout ChartSeries) -> ChartSeries.UpdateResult) -> ChartSeries.UpdateResult {
        let wasAtLiveEdge = liveEdgeNow
        var result = ChartSeries.UpdateResult.ignored
        let window = renderWindow
        batch {
            result = mutation(&series)
            guard result != .ignored else {
                renderDirty = false
                return
            }
            recomputeIndicators()
            if wasAtLiveEdge { moveToLiveEdge() }
            // A tick that changes the newest bar, which the render window does not reach, changes nothing the charts draw.
            if result == .updatedLast, let last = series.lastTime, !window.contains(last), !wasAtLiveEdge {
                renderDirty = false
            }
        }
        return result
    }

    /// Runs a group of mutations and reports the viewport events once, after all of them.
    func batch(_ mutations: () -> Void) {
        let wasBatching = isBatching
        isBatching = true
        renderDirty = true
        mutations()
        isBatching = wasBatching
        if !wasBatching {
            let duration = visibleDuration
            if duration != chartVisibleDuration { chartVisibleDuration = duration }
            refreshChartDomain()
            let changed = syncRenderData()
            refreshRenderState(.structural, dataChanged: changed)
            reportViewportEvents()
        }
    }

    /// Hands the data to the chart bodies, and tells them (through the revision) when it changed for them.
    @discardableResult
    private func syncRenderData() -> Bool {
        renderData = RenderData(series: series, outputs: indicatorOutputs, paletteBases: paletteBases)
        guard renderDirty else { return false }
        renderDirty = false
        renderRevision &+= 1
        return true
    }

    private func moveToLiveEdge() {
        guard let last = series.lastTime else { return }
        let target = ViewportMath.endAnchor(
            lastTime: last,
            interval: series.interval,
            visibleBars: visibleBars,
            configuration: viewport
        )
        if scrollPosition != target { scrollPosition = target }
    }

    private func styleDidChange() {
        batch {
            domainStartNeedsReset = true
            visibleBars = configuration.viewport.defaultVisibleBars(for: style)
            refreshViewport()
            moveToLiveEdge()
        }
    }

    /// Reacts to a change of something the effective viewport depends on, keeping a window that sat at the live edge there.
    private func viewportInputsDidChange() {
        let wasAtLiveEdge = liveEdgeNow
        batch {
            if refreshViewport(), wasAtLiveEdge { moveToLiveEdge() }
        }
    }

    /// The view reports measured sizes here. Changes below one point are dropped so that sub-pixel layout noise
    /// cannot make the window jitter. A window at the live edge is re-anchored in the same mutation.
    func updateLayoutMetrics(
        plotWidth newPlotWidth: CGFloat? = nil,
        badgeWidth newBadgeWidth: CGFloat? = nil,
        yAxisColumnWidth newColumnWidth: CGFloat? = nil
    ) {
        let plotChanged = newPlotWidth.map { abs($0 - plotWidth) >= Self.metricsHysteresis } ?? false
        let badgeChanged = newBadgeWidth.map { abs($0 - badgeWidth) >= Self.metricsHysteresis } ?? false
        let columnChanged = newColumnWidth.map { abs($0 - yAxisColumnWidth) >= Self.metricsHysteresis } ?? false
        guard plotChanged || badgeChanged || columnChanged else { return }
        let wasAtLiveEdge = liveEdgeNow
        batch {
            if plotChanged, let newPlotWidth { plotWidth = newPlotWidth }
            if badgeChanged, let newBadgeWidth { badgeWidth = newBadgeWidth }
            if columnChanged, let newColumnWidth { yAxisColumnWidth = newColumnWidth }
            if refreshViewport(), wasAtLiveEdge { moveToLiveEdge() }
        }
    }

    /// The view reports the size of the badge on the screen. Changes below half a point are dropped.
    func updateBadgeSize(_ size: CGSize) {
        guard abs(size.width - badgeSize.width) >= 0.5 || abs(size.height - badgeSize.height) >= 0.5 else { return }
        badgeSize = size
    }

    /// The view reports how the theme draws candles; the autoscale at the edges of the window follows it. The standard theme is
    /// assumed until it does.
    func updateCandleMetrics(_ metrics: CandleMetrics) {
        guard metrics != candleMetrics else { return }
        candleMetrics = metrics
        batch {}
    }

    /// Recomputes ``viewport`` and returns whether it changed.
    ///
    /// The badge sits on the price axis column, so it reaches into the plot only by `badgeWidth - yAxisColumnWidth`;
    /// it counts while it is shown (`showsPriceBadge`, a price, a measured badge and column).
    @discardableResult
    private func refreshViewport() -> Bool {
        var badgeOverhang: CGFloat?
        if configuration.showsPriceBadge, currentPrice != nil, badgeWidth > 0, yAxisColumnWidth > 0 {
            badgeOverhang = Swift.max(0, badgeWidth - yAxisColumnWidth)
        }
        let next = ViewportMath.effectiveConfiguration(
            configuration.viewport,
            visibleBars: visibleBars,
            plotWidth: plotWidth,
            badgeOverhang: badgeOverhang
        )
        guard next != viewport else { return false }
        viewport = next
        return true
    }

    private static let metricsHysteresis: CGFloat = 1
    static let scrollNudgeBars: Double = 0.001

    private func indicatorsDidChange(from old: [any ChartIndicator]) {
        var seen = Set<String>()
        let unique = indicators.filter { seen.insert($0.id).inserted }
        if unique.count != indicators.count {
            // Assigning the list without the duplicates comes back here with the list that has them as `old`, which would write
            // the same ids again: the write is made here, against the list that was there before.
            let wasRestoring = isRestoringPersistence
            isRestoringPersistence = true
            indicators = unique
            isRestoringPersistence = wasRestoring
            if old.map(\.id) != unique.map(\.id) { persistIndicators() }
            return
        }
        batch { recomputeIndicators() }
        if old.map(\.id) != indicators.map(\.id) { persistIndicators() }
    }

    private func recomputeIndicators() {
        guard !indicators.isEmpty else {
            if !indicatorOutputs.isEmpty { indicatorOutputs = [:] }
            if !paletteBases.isEmpty { paletteBases = [:] }
            return
        }
        let input = IndicatorInput(series: series)
        var outputs: [String: IndicatorOutput] = [:]
        outputs.reserveCapacity(indicators.count)
        var ordered: [IndicatorOutput] = []
        ordered.reserveCapacity(indicators.count)
        for indicator in indicators {
            let output = indicator.calculate(input)
            outputs[indicator.id] = output
            ordered.append(output)
        }
        indicatorOutputs = outputs
        paletteBases = Dictionary(
            zip(indicators.map(\.id), IndicatorPalette.baseIndices(for: ordered)),
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var isApproachingHistoryStart: Bool {
        guard let first = series.firstTime else { return false }
        let threshold = configuration.historyPrefetchThreshold.duration(
            interval: series.interval,
            visibleDuration: visibleDuration
        )
        return scrollPosition.timeIntervalSince(first) < threshold
    }

    /// The oldest time a live update must not trim: the bars the user is looking at and the render buffer before them.
    private var trimProtectionBoundary: Date {
        renderTimeRange.lowerBound
    }

    /// A flag changed in a way that may make a history request due: starts a new epoch and looks at the window.
    private func historyRequestMayBeDue() {
        historyEpoch += 1
        guard !isBatching else { return }
        reportViewportEvents()
    }

    func reportViewportEvents() {
        let atLiveEdge = liveEdgeNow
        if atLiveEdge != lastReportedLiveEdge {
            lastReportedLiveEdge = atLiveEdge
            onEvent?(.liveEdgeChanged(atLiveEdge))
        }
        if historyRequestEpoch != historyEpoch, hasMoreHistory, !isLoadingHistory, isApproachingHistoryStart {
            historyRequestEpoch = historyEpoch
            onEvent?(.approachedHistoryStart)
        }
    }
}
