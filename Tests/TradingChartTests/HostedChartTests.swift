import SwiftUI
import Testing
import UIKit
@_spi(Diagnostics) @testable import TradingChart

/// Tests that put the real view into a window and let SwiftUI evaluate it, to count what a scroll rebuilds.
@MainActor
@Suite("Hosted chart", .serialized)
struct HostedChartTests {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeHost(_ model: TradingChartModel) -> (window: UIWindow, controller: UIHostingController<some View>) {
        let controller = UIHostingController(rootView: TradingChartView(model: model).padding(8))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 760))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return (window, controller)
    }

    @Test("a programmatic scroll rebuilds the panes a few times, not on every frame")
    func scrollDoesNotRebuildPerFrame() throws {
        let (model, clock) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.5)
        let barSeconds = model.series.interval.seconds
        let live = model.scrollPosition
        let before = ChartDiagnostics.counts(of: model)
        #expect(before.main > 0)  // the view was built

        ChartDiagnostics.reset(model)
        let steps = 90
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let depth = progress < 0.5 ? 2 * progress : 2 - 2 * progress
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-depth * 300 * barSeconds)
            spin(0.016)
        }
        let counts = ChartDiagnostics.counts(of: model)
        // The panes are laid out again for moves of the window and of the Y base: a handful, far fewer than the frames.
        #expect(counts.main <= steps / 3, "\(counts)")
        #expect(counts.panes <= 3 * steps / 3, "\(counts)")
        // The axes (small canvases) follow every frame.
        #expect(counts.axes >= steps)
        #expect(ChartDiagnostics.violations(of: model).total == 0)
    }

    /// Twelve drawings of every kind around the visible window, the first one selected.
    private func addDrawings(to model: TradingChartModel) {
        let last = model.series.lastTime ?? date(baseTime)
        let bar = model.series.interval.seconds
        model.drawings = (0..<12).map { index in
            let start = last.addingTimeInterval(-Double(10 + index * 20) * bar)
            let price = 95 + Double(index) * 2
            switch index % 3 {
            case 0:
                return ChartDrawing(kind: .trendLine, anchors: [
                    ChartAnchor(time: start, price: price),
                    ChartAnchor(time: start.addingTimeInterval(15 * bar), price: price + 6),
                ])
            case 1:
                return ChartDrawing(kind: .ray, anchors: [
                    ChartAnchor(time: start, price: price),
                    ChartAnchor(time: start.addingTimeInterval(8 * bar), price: price - 3),
                ])
            default:
                return ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: start, price: price)])
            }
        }
        model.selectedDrawingID = model.drawings[0].id
    }

    @Test("dragging a drawing redraws the overlay and rebuilds neither the main pane nor the indicator panes")
    func dragDoesNotRebuildTheCharts() throws {
        let (model, _) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        addDrawings(to: model)
        spin(1.5)

        ChartDiagnostics.reset(model)
        let plot = CGRect(x: 0, y: 0, width: 300, height: 300)
        let anchor = try #require(model.drawings.first?.anchors.last)
        let start = model.drawingTransform(plot: plot).point(for: anchor)
        #expect(model.drawingBeginDrag(at: start, plot: plot))
        for step in 1...60 {
            model.drawingContinueDrag(to: CGPoint(x: start.x - Double(step), y: start.y + Double(step) / 2), plot: plot)
            spin(0.016)
        }
        model.drawingEndDrag()
        spin(0.2)

        let counts = ChartDiagnostics.counts(of: model)
        #expect(counts.main == 0)
        #expect(counts.panes == 0)
        #expect(counts.commits == 0)
        #expect(model.renderCounters.drawingBodies >= 30)  // the overlay followed the finger
        #expect(model.drawings.first?.anchors.last != anchor)
    }

    @Test("a scroll with twelve drawings rebuilds the panes as rarely as without, and every frame stays consistent")
    func scrollWithDrawings() throws {
        let (model, clock) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        addDrawings(to: model)
        spin(1.5)
        let barSeconds = model.series.interval.seconds
        let live = model.scrollPosition
        model.renderCounters.builtWindows = [:]
        model.renderCounters.builtBases = [:]

        ChartDiagnostics.reset(model)
        let steps = 90
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let depth = progress < 0.5 ? 2 * progress : 2 - 2 * progress
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-depth * 300 * barSeconds)
            spin(0.016)
        }
        let counts = ChartDiagnostics.counts(of: model)
        #expect(counts.main <= steps / 3)
        #expect(counts.panes <= 3 * steps / 3)
        #expect(model.renderCounters.drawingBodies >= steps)  // the drawings follow every scroll step
        #expect(ChartDiagnostics.violations(of: model).total == 0)
    }

    /// Every view of a class below `view`.
    private func descendants<T: UIView>(of view: UIView, ofType type: T.Type) -> [T] {
        view.subviews.flatMap { subview -> [T] in
            (subview as? T).map { [$0] + descendants(of: subview, ofType: type) } ?? descendants(of: subview, ofType: type)
        }
    }

    @Test("every pane has an input layer over its plot, and the layers take the finger instead of the charts")
    func inputLayers() throws {
        let (model, _) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.0)

        let layers = descendants(of: host.controller.view, ofType: ChartInputView.self)
        // The main pane, Volume and RSI.
        #expect(layers.count == 3)
        for layer in layers {
            #expect(layer.isUserInteractionEnabled)
            #expect(layer.bounds.width > 100)
            #expect(layer.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } == true)
            #expect(layer.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } == true)
            let pan = try #require(layer.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }.first)
            #expect(pan.maximumNumberOfTouches == 1)  // two fingers are the pinch's
        }
    }

    @Test("the model learns the size of the badge as it is on the screen: with the chevron once the window leaves the live edge")
    func badgeSize() {
        let (model, _) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.0)

        let atLiveEdge = model.badgeSize
        #expect(atLiveEdge.width >= TradingChartTheme.standard.yAxisLabelWidth)
        #expect(atLiveEdge.height > 12 && atLiveEdge.height < 40)

        model.scrollPosition = model.scrollPosition.addingTimeInterval(-3_600)
        spin(1.0)
        #expect(!model.isAtLiveEdge)
        #expect(model.badgeSize.width > atLiveEdge.width)
        #expect(model.badgeSize.height == atLiveEdge.height)
    }

    @Test("a live tick on the newest bar, far from the window, rebuilds neither the panes nor the charts in them")
    func tickOutsideTheWindowRebuildsNothing() {
        let (model, clock) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.5)
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-300 * 60)
        clock.advance(by: 0.3)  // scrolling has come to rest
        spin(1.0)
        let last = try? #require(model.series.lastTime)
        #expect(last.map { !model.renderWindow.contains($0) } == true)

        ChartDiagnostics.reset(model)
        for step in 1...20 {
            model.update(price: 100 + Double(step), at: model.series.lastTime!)
            spin(0.03)
        }

        let counts = ChartDiagnostics.counts(of: model)
        #expect(counts.main == 0, "\(counts)")
        #expect(counts.panes == 0, "\(counts)")
        // The closure of the pane's GeometryReader, which builds the chart, is not evaluated either.
        #expect(counts.charts == 0, "\(counts)")
    }

    @Test("a crosshair that moves from bar to bar rebuilds neither the panes nor the charts in them, and its own layer follows it")
    func crosshairDoesNotRebuildTheCharts() {
        let (model, _) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.5)
        let visible = model.visibleTimeRange

        ChartDiagnostics.reset(model)
        for step in 0..<30 {
            model.crosshairTime = visible.lowerBound.addingTimeInterval(Double(step) * model.visibleDuration / 30)
            spin(0.02)
        }

        let counts = ChartDiagnostics.counts(of: model)
        #expect(model.crosshair != nil)
        #expect(counts.main == 0, "\(counts)")
        #expect(counts.panes == 0, "\(counts)")
        #expect(counts.charts == 0, "\(counts)")
        #expect(counts.commits == 0, "\(counts)")
        #expect(model.renderCounters.crosshairBodies >= 10)  // the leaf view that draws it did follow the finger
    }

    @Test("the haptic tick of the crosshair is hosted once, not once per pane")
    func crosshairHapticIsHostedOnce() {
        let (model, _) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.5)
        let visible = model.visibleTimeRange

        ChartDiagnostics.reset(model)
        for step in 0..<30 {
            model.crosshairTime = visible.lowerBound.addingTimeInterval(Double(step) * model.visibleDuration / 30)
            spin(0.02)
        }

        let layers = model.renderCounters.crosshairBodies
        let haptics = model.renderCounters.crosshairHapticBodies
        #expect(haptics >= 10)  // it followed the crosshair
        // The main pane and the two indicator panes (Volume, RSI) have a crosshair layer each; the tick has one host.
        #expect(haptics * 2 <= layers, "layers \(layers), haptics \(haptics)")
    }

    @Test("the counters belong to the model: a chart that scrolls does not count into another one")
    func countersArePerModel() {
        let (first, firstClock) = swingingModelForHosting()
        let (second, _) = swingingModelForHosting()
        let firstHost = makeHost(first)
        let secondHost = makeHost(second)
        defer {
            firstHost.window.isHidden = true
            secondHost.window.isHidden = true
        }
        spin(1.5)
        ChartDiagnostics.reset(first)
        ChartDiagnostics.reset(second)

        let live = first.scrollPosition
        for step in 0..<40 {
            firstClock.advance(by: 0.0167)
            first.scrollPosition = live.addingTimeInterval(-Double(step) * 60)
            spin(0.016)
        }

        #expect(ChartDiagnostics.counts(of: first).axes >= 40)
        #expect(ChartDiagnostics.counts(of: second).axes == 0)
        #expect(ChartDiagnostics.violations(of: first).total == 0)
        #expect(ChartDiagnostics.violations(of: second).total == 0)
    }

    @Test("with no drawings a scroll does not evaluate the drawing overlay")
    func noDrawingsNoWork() {
        let (model, clock) = swingingModelForHosting()
        let host = makeHost(model)
        defer { host.window.isHidden = true }
        spin(1.5)
        let live = model.scrollPosition

        ChartDiagnostics.reset(model)
        for step in 0..<40 {
            clock.advance(by: 0.0167)
            model.scrollPosition = live.addingTimeInterval(-Double(step) * 60)
            spin(0.016)
        }
        #expect(model.renderCounters.drawingBodies == 0)
    }
}

@MainActor
private func swingingModelForHosting() -> (TradingChartModel, ManualClock) {
    let candles = (0..<600).map { index -> Candle in
        let phase = Double(index)
        let mid = 100 + 12 * sin(phase / 17) + 4 * sin(phase / 3.1)
        return Candle(
            time: date(baseTime + phase * 60),
            open: mid - 1,
            high: mid + 2,
            low: mid - 2,
            close: mid + 1,
            volume: 50 + 40 * abs(sin(phase / 5))
        )
    }
    let model = TradingChartModel(series: ChartSeries(candles: candles, interval: .minutes(1)), style: .candles)
    model.indicators = [SMA(period: 20), Volume(), RSI()]
    model.currentPrice = candles.last?.close
    let clock = ManualClock()
    model.scrollClock = clock.scrollClock
    return (model, clock)
}
