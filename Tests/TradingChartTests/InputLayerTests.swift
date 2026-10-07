import SwiftUI
import Testing
import TradingChartCore
import UIKit
@testable import TradingChart

/// Counts what a closure is told, so a test can see a display link run or stop.
@MainActor
private final class Count {
    var value = 0
}

@MainActor
@Suite("Fling lifecycle", .serialized)
struct FlingLifecycleTests {
    private let plotWidth: CGFloat = 300

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeModel(configuration: TradingChartConfiguration = TradingChartConfiguration()) -> (TradingChartModel, ManualTicker) {
        let series = makeSeries(count: 600, lastStart: baseTime + 599 * 60)
        let model = TradingChartModel(series: series, style: .candles, configuration: configuration)
        model.updateLayoutMetrics(plotWidth: plotWidth, yAxisColumnWidth: 60)
        let ticker = ManualTicker()
        model.frameTicker = ticker.ticker
        return (model, ticker)
    }

    // MARK: - The display link

    @Test("a display link goes on while its tick says so and stops itself when it does not")
    func displayLinkStopsItself() {
        let ticks = Count()
        let stop = FrameTicker.display.start { _ in
            ticks.value += 1
            return ticks.value < 3
        }
        spin(0.5)
        #expect(ticks.value == 3)  // not 3 and then a link that ticks on for ever
        stop()  // harmless once it has stopped by itself
    }

    @Test("the function that stops a display link works, and twice is harmless")
    func displayLinkStopFunction() {
        let ticks = Count()
        let stop = FrameTicker.display.start { _ in
            ticks.value += 1
            return true
        }
        spin(0.2)
        #expect(ticks.value > 0)
        stop()
        let atStop = ticks.value
        spin(0.2)
        #expect(ticks.value == atStop)
        stop()
    }

    @Test("the display link of a fling does not outlive the model: the first tick after it is gone ends the link")
    func displayLinkDoesNotOutliveTheModel() {
        let ticks = Count()
        let real = FrameTicker.display
        var model: TradingChartModel? = TradingChartModel(
            series: makeSeries(count: 600, lastStart: baseTime + 599 * 60),
            style: .candles
        )
        weak var weakModel = model
        model?.updateLayoutMetrics(plotWidth: plotWidth, yAxisColumnWidth: 60)
        model?.frameTicker = FrameTicker { tick in
            real.start { delta in
                ticks.value += 1
                return tick(delta)
            }
        }
        model?.beginTouchScroll()
        model?.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        spin(0.15)
        #expect(ticks.value > 0)  // the link is running, with the model alive

        model = nil
        #expect(weakModel == nil)  // nothing but the link could keep it
        spin(0.2)
        let atEnd = ticks.value
        spin(0.4)
        #expect(ticks.value == atEnd)  // no tick for ever after the model has gone
    }

    // MARK: - Leaving the screen

    @Test("a fling stops when its input layer leaves the window, and when the representable is taken down")
    func flingStopsWhenTheViewGoesAway() {
        let (model, ticker) = makeModel()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.makeKeyAndVisible()
        let layer = ChartInputView(model: model, takesDrawingTouches: false)
        layer.frame = CGRect(x: 0, y: 0, width: plotWidth, height: 200)
        window.addSubview(layer)

        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        ticker.advance()
        #expect(ticker.activeCount == 1)

        layer.removeFromSuperview()
        #expect(ticker.activeCount == 0)
        #expect(model.scrollMomentum == nil)

        // The same for a representable that SwiftUI takes down while the view is not in a window.
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        #expect(ticker.activeCount == 1)
        ChartInputLayer.dismantleUIView(ChartInputView(model: model, takesDrawingTouches: false), coordinator: ())
        #expect(ticker.activeCount == 0)
        window.isHidden = true
    }

    // MARK: - One fling at a time

    @Test("a second fling ends the first one: one ticker runs, and the window moves as for one fling")
    func twoFlingsAreOne() {
        let (model, ticker) = makeModel()
        let (single, singleTicker) = makeModel()

        // Two panes were touched by two fingers: both drags began, then both lifted at speed.
        model.beginTouchScroll()
        model.beginTouchScroll()
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        #expect(ticker.starts == 2)
        #expect(ticker.activeCount == 1)  // the first one is stopped, not left ticking behind the second

        single.beginTouchScroll()
        single.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        for _ in 0..<20 {
            ticker.advance()
            singleTicker.advance()
        }
        #expect(model.scrollPosition == single.scrollPosition)

        ticker.run(seconds: 10)
        #expect(ticker.activeCount == 0)
    }

    // MARK: - History that arrives while a finger is down

    private func historyReadyModel() -> (TradingChartModel, ManualTicker) {
        var configuration = TradingChartConfiguration()
        configuration.historyReserveBars = 10
        return makeModel(configuration: configuration)
    }

    private func page(_ model: TradingChartModel) -> ChartSeries {
        makeSeries(count: 300, lastStart: model.series.firstTime!.timeIntervalSince1970 - 60)
    }

    @Test("history that arrives under a finger extends the domain when the finger lifts without a fling")
    func expansionAppliedWhenTheFingerLifts() {
        let (model, ticker) = historyReadyModel()
        model.beginTouchScroll()
        model.prependHistory(page(model))
        #expect(model.domainExpansionPending)
        #expect(model.touchScrollRange.lowerBound > model.naturalXDomain.lowerBound)  // the new bars cannot be reached yet

        model.endTouchScroll(velocity: 0, plotWidth: plotWidth)

        #expect(!model.domainExpansionPending)
        #expect(model.touchScrollRange.lowerBound == model.naturalXDomain.lowerBound)
        #expect(!ticker.isRunning)
    }

    @Test("history that arrives under a finger extends the domain when the finger is taken away")
    func expansionAppliedWhenTheTouchIsCancelled() {
        let (model, _) = historyReadyModel()
        model.beginTouchScroll()
        model.prependHistory(page(model))
        #expect(model.domainExpansionPending)

        model.cancelTouchScroll()

        #expect(!model.domainExpansionPending)
        #expect(model.touchScrollRange.lowerBound == model.naturalXDomain.lowerBound)
    }

    @Test("while a fling runs the domain waits for it to stop")
    func expansionWaitsForTheFling() {
        let (model, ticker) = historyReadyModel()
        model.beginTouchScroll()
        model.prependHistory(page(model))
        model.endTouchScroll(velocity: 900, plotWidth: plotWidth)
        #expect(ticker.isRunning)
        #expect(model.domainExpansionPending)
    }
}

@MainActor
@Suite("Arbitration of the input layers")
struct InputArbitrationTests {
    private func makeLayers(configuration: TradingChartConfiguration = TradingChartConfiguration())
        -> (model: TradingChartModel, first: ChartInputView, second: ChartInputView)
    {
        let model = TradingChartModel(
            series: makeSeries(count: 100, lastStart: baseTime + 99 * 60),
            style: .candles,
            configuration: configuration
        )
        return (
            model,
            ChartInputView(model: model, takesDrawingTouches: true),
            ChartInputView(model: model, takesDrawingTouches: true)
        )
    }

    private func recognisers(of layer: ChartInputView) -> [UIGestureRecognizer] {
        [layer.pan, layer.press, layer.tap, layer.drawingPan]
    }

    @Test("a layer never recognises together with another one: two fingers on two panes scroll one pane")
    func panesAreExclusive() {
        let (_, first, second) = makeLayers()
        for mine in recognisers(of: first) {
            for theirs in recognisers(of: second) {
                #expect(first.gestureRecognizer(mine, shouldRecognizeSimultaneouslyWith: theirs) == false)
                #expect(second.gestureRecognizer(theirs, shouldRecognizeSimultaneouslyWith: mine) == false)
            }
        }
    }

    @Test("what is not another layer, the pinch of the chart, goes along with a layer's recognisers")
    func pinchGoesAlong() {
        let (_, layer, _) = makeLayers()
        let host = UIView()
        let pinch = UIPinchGestureRecognizer()
        host.addGestureRecognizer(pinch)
        for mine in [layer.pan, layer.tap, layer.drawingPan, layer.press] {
            #expect(layer.gestureRecognizer(mine, shouldRecognizeSimultaneouslyWith: pinch))
        }
        // A recogniser that is on no view at all is not a layer's either.
        #expect(layer.gestureRecognizer(layer.pan, shouldRecognizeSimultaneouslyWith: UIPinchGestureRecognizer()))
    }

    @Test("within one layer the pans and the long press exclude each other, and the tap goes along")
    func oneLayerKeepsItsRules() {
        let (_, layer, _) = makeLayers()
        #expect(!layer.gestureRecognizer(layer.pan, shouldRecognizeSimultaneouslyWith: layer.press))
        #expect(!layer.gestureRecognizer(layer.press, shouldRecognizeSimultaneouslyWith: layer.drawingPan))
        #expect(!layer.gestureRecognizer(layer.pan, shouldRecognizeSimultaneouslyWith: layer.drawingPan))
        #expect(layer.gestureRecognizer(layer.tap, shouldRecognizeSimultaneouslyWith: layer.pan))
    }

    @Test("with the crosshair switched off the long press does not begin, so it cannot hold up the pan")
    func pressNeedsTheCrosshair() {
        var configuration = TradingChartConfiguration()
        configuration.isCrosshairEnabled = false
        let (model, drawing, _) = makeLayers(configuration: configuration)
        let plain = ChartInputView(model: model, takesDrawingTouches: false)
        for layer in [drawing, plain] {
            #expect(layer.gestureRecognizerShouldBegin(layer.press) == false)
            #expect(layer.gestureRecognizerShouldBegin(layer.pan))
        }
        #expect(drawing.gestureRecognizerShouldBegin(drawing.tap))

        model.configuration.isCrosshairEnabled = true
        for layer in [drawing, plain] {
            #expect(layer.gestureRecognizerShouldBegin(layer.press))
            #expect(layer.gestureRecognizerShouldBegin(layer.pan))
        }
    }
}
