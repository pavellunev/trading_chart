import Testing
import TradingChartCore
import UIKit
import UIKit.UIGestureRecognizerSubclass
@testable import TradingChart

@Suite("Direction of a pan inside a scroll view")
struct PanDirectionTests {
    private func vector(degrees: Double, length: Double = 20) -> CGPoint {
        CGPoint(x: length * cos(degrees * .pi / 180), y: length * sin(degrees * .pi / 180))
    }

    @Test("a pan that is mostly horizontal is the chart's, whichever way it goes")
    func horizontalIsTheCharts() {
        for degrees in [0.0, 10, 30, 44, 150, 180, 210, -30, -150] {
            #expect(PanDirection.isHorizontal(translation: vector(degrees: degrees), velocity: .zero), "\(degrees) degrees")
        }
    }

    @Test("a pan that is mostly vertical is left to the scroll view")
    func verticalIsThePages() {
        for degrees in [46.0, 60, 90, 120, 134, 270, -60, -90, -120] {
            #expect(!PanDirection.isHorizontal(translation: vector(degrees: degrees), velocity: .zero), "\(degrees) degrees")
        }
    }

    @Test("the diagonal stays with the chart, and so does a pan that has not moved")
    func ties() {
        #expect(PanDirection.isHorizontal(translation: CGPoint(x: 10, y: 10), velocity: .zero))
        #expect(PanDirection.isHorizontal(translation: CGPoint(x: -10, y: 10), velocity: .zero))
        #expect(PanDirection.isHorizontal(translation: .zero, velocity: .zero))
    }

    @Test("the velocity decides only when there is no translation yet")
    func velocityIsTheFallback() {
        #expect(!PanDirection.isHorizontal(translation: .zero, velocity: CGPoint(x: 50, y: 400)))
        #expect(PanDirection.isHorizontal(translation: .zero, velocity: CGPoint(x: 400, y: 50)))
        // A translation that has a direction is not overruled by the velocity of the last moment.
        #expect(PanDirection.isHorizontal(translation: CGPoint(x: 12, y: 3), velocity: CGPoint(x: 0, y: 900)))
        #expect(!PanDirection.isHorizontal(translation: CGPoint(x: 3, y: 12), velocity: CGPoint(x: 900, y: 0)))
    }
}

@MainActor
@Suite("The pans of the scroll views above a chart")
struct ScrollAncestorPansTests {
    private func fakes(_ count: Int = 2) -> [UIPanGestureRecognizer] {
        (0..<count).map { _ in UIPanGestureRecognizer() }
    }

    /// A scroll view 320 by 480 points whose content is `content` big: a page by default, a pager when it is wide and not tall.
    private func scrollView(content: CGSize = CGSize(width: 320, height: 1_600)) -> UIScrollView {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scroll.contentSize = content
        return scroll
    }

    /// The pans found above a view inside `scroll`.
    private func pansInside(_ scroll: UIScrollView) -> ScrollAncestorPans {
        let leaf = UIView()
        scroll.addSubview(leaf)
        let lock = ScrollAncestorPans()
        lock.refresh(from: leaf)
        return lock
    }

    @Test("holding switches the pans off and releasing the last reason switches them on")
    func holdAndRelease() {
        let pans = fakes()
        let lock = ScrollAncestorPans()
        lock.track(pans)

        lock.hold(.crosshair)
        #expect(pans.allSatisfy { !$0.isEnabled })
        lock.release(.crosshair)
        #expect(pans.allSatisfy { $0.isEnabled })
    }

    @Test("a pan stays off while any reason holds it")
    func severalReasons() {
        let pans = fakes()
        let lock = ScrollAncestorPans()
        lock.track(pans)

        lock.hold(.crosshair)
        lock.hold(.pinch)
        lock.release(.crosshair)
        #expect(pans.allSatisfy { !$0.isEnabled })
        lock.release(.pinch)
        #expect(pans.allSatisfy { $0.isEnabled })

        lock.hold(.drawingDrag)
        lock.hold(.drawingDrag)  // the same reason twice is one reason
        lock.release(.drawingDrag)
        #expect(pans.allSatisfy { $0.isEnabled })
    }

    @Test("a pan that the host switched off is left as it was")
    func hostDisabledPan() {
        let pans = fakes()
        pans[0].isEnabled = false
        let lock = ScrollAncestorPans()
        lock.track(pans)

        lock.hold(.crosshair)
        #expect(!pans[0].isEnabled && !pans[1].isEnabled)
        lock.release(.crosshair)
        #expect(!pans[0].isEnabled)  // not switched on by a lock that did not switch it off
        #expect(pans[1].isEnabled)
    }

    @Test("releasing what is not held does nothing, and releasing everything switches the pans on")
    func releaseWithoutHold() {
        let pans = fakes()
        let lock = ScrollAncestorPans()
        lock.track(pans)
        pans[0].isEnabled = false

        lock.release(.pinch)
        #expect(!pans[0].isEnabled && pans[1].isEnabled)  // someone else's switch is not touched

        lock.hold(.crosshair)
        lock.hold(.pinch)
        lock.releaseAll()
        #expect(!pans[0].isEnabled && pans[1].isEnabled)
        lock.release(.crosshair)  // already let go
        #expect(pans[1].isEnabled)
    }

    @Test("two locks on one pan: the one that found it on puts it back, the other leaves it alone")
    func twoLocksOnOnePan() {
        let pan = UIPanGestureRecognizer()
        let first = ScrollAncestorPans(), second = ScrollAncestorPans()
        first.track([pan])
        second.track([pan])

        first.hold(.crosshair)
        second.hold(.pinch)  // finds the pan off already
        second.release(.pinch)
        #expect(!pan.isEnabled)  // the first still holds it
        first.release(.crosshair)
        #expect(pan.isEnabled)  // and never ends up off for good
    }

    @Test("the pans are held weakly: a scroll view that is gone is not kept alive, and is no longer an ancestor")
    func weakReferences() {
        let lock = ScrollAncestorPans()
        weak var weakScroll: UIScrollView?
        autoreleasepool {
            let scroll = scrollView()
            let child = UIView()
            scroll.addSubview(child)
            lock.refresh(from: child)
            #expect(lock.isInsideVerticalScrollView)
            #expect(lock.isScrollPan(scroll.panGestureRecognizer))
            weakScroll = scroll
            lock.hold(.crosshair)
        }
        #expect(weakScroll == nil)
        lock.release(.crosshair)  // nothing to switch on, and nothing to trap on
    }

    @Test("every scroll view above the view is found, nearest first, and nothing that is not above it")
    func findsAncestors() {
        let outer = scrollView(), inner = scrollView(), sibling = scrollView()
        let leaf = UIView()
        let host = UIView()
        host.addSubview(outer)
        outer.addSubview(inner)
        inner.addSubview(leaf)
        host.addSubview(sibling)
        sibling.addSubview(UIView())

        let lock = ScrollAncestorPans()
        lock.refresh(from: leaf)
        #expect(lock.isScrollPan(inner.panGestureRecognizer))
        #expect(lock.isScrollPan(outer.panGestureRecognizer))
        #expect(!lock.isScrollPan(sibling.panGestureRecognizer))
        #expect(!lock.isScrollPan(UIPanGestureRecognizer()))

        let alone = UIView()
        lock.refresh(from: alone)
        #expect(!lock.isInsideVerticalScrollView)
    }

    @Test("looking again lets go of what was held for the old hierarchy")
    func refreshReleases() {
        let scroll = scrollView()
        let leaf = UIView()
        scroll.addSubview(leaf)
        let lock = ScrollAncestorPans()
        lock.refresh(from: leaf)
        lock.hold(.crosshair)
        #expect(!scroll.panGestureRecognizer.isEnabled)

        leaf.removeFromSuperview()
        lock.refresh(from: leaf)
        #expect(scroll.panGestureRecognizer.isEnabled)
        #expect(!lock.isInsideVerticalScrollView)
    }

    // MARK: - Which scroll views count as vertical

    @Test("a scroll view with taller content than itself is a vertical one, a pager that is wide and not tall is not")
    func verticalCapacity() {
        // The pans are held weakly: the scroll views stay in variables for as long as they are asked about.
        let page = scrollView()
        let pager = scrollView(content: CGSize(width: 1_600, height: 480))
        let empty = scrollView(content: .zero)
        #expect(pansInside(page).isInsideVerticalScrollView)
        #expect(!pansInside(pager).isInsideVerticalScrollView)
        #expect(!pansInside(empty).isInsideVerticalScrollView)
    }

    @Test("content that is no more than a point taller than the scroll view does not make it vertical")
    func verticalCapacityThreshold() {
        let barely = scrollView(content: CGSize(width: 320, height: 481))
        let taller = scrollView(content: CGSize(width: 320, height: 481.5))
        #expect(!pansInside(barely).isInsideVerticalScrollView)
        #expect(pansInside(taller).isInsideVerticalScrollView)
    }

    @Test("a scroll view that always bounces vertically counts, whatever its content")
    func alwaysBounceVertical() {
        let page = scrollView(content: CGSize(width: 320, height: 100))
        #expect(!pansInside(page).isInsideVerticalScrollView)
        page.alwaysBounceVertical = true
        #expect(pansInside(page).isInsideVerticalScrollView)

        let pager = scrollView(content: CGSize(width: 1_600, height: 480))
        pager.alwaysBounceHorizontal = true
        #expect(!pansInside(pager).isInsideVerticalScrollView)
    }

    @Test("a scroll view with scrolling switched off, or its pan switched off, does not count")
    func disabledScrollView() {
        let page = scrollView()
        let pans = pansInside(page)
        #expect(pans.isInsideVerticalScrollView)

        page.isScrollEnabled = false
        #expect(!pans.isInsideVerticalScrollView)
        page.isScrollEnabled = true
        #expect(pans.isInsideVerticalScrollView)

        page.panGestureRecognizer.isEnabled = false
        #expect(!pans.isInsideVerticalScrollView)
        page.panGestureRecognizer.isEnabled = true
        #expect(pans.isInsideVerticalScrollView)
    }

    @Test("the answer follows the scroll view as it changes, and is not fixed when the scroll views were found")
    func answerIsCurrent() {
        let page = scrollView(content: CGSize(width: 320, height: 300))
        let pans = pansInside(page)
        #expect(!pans.isInsideVerticalScrollView)
        page.contentSize.height = 2_000
        #expect(pans.isInsideVerticalScrollView)
        page.frame.size.height = 3_000
        #expect(!pans.isInsideVerticalScrollView)
    }

    @Test("a pan that this object switched off still counts as the pan of a vertical scroll view")
    func switchedOffByUsStillCounts() {
        let page = scrollView()
        let pans = pansInside(page)
        pans.hold(.crosshair)
        #expect(!page.panGestureRecognizer.isEnabled)
        #expect(pans.isInsideVerticalScrollView)
        pans.release(.crosshair)
        #expect(pans.isInsideVerticalScrollView)
    }

    @Test("a scroll view that the host has switched off when the hold begins does not count, before, during or after it")
    func switchedOffByTheHostDoesNotCount() {
        let page = scrollView()
        let pans = pansInside(page)
        page.isScrollEnabled = false
        pans.hold(.crosshair)
        #expect(!pans.isInsideVerticalScrollView)
        pans.release(.crosshair)
        #expect(!pans.isInsideVerticalScrollView)
    }

    @Test("one vertical scroll view among several is enough, and a pager above or under it does not matter")
    func oneVerticalOfSeveral() {
        let page = scrollView()
        let pager = scrollView(content: CGSize(width: 1_600, height: 480))
        let leaf = UIView()
        page.addSubview(pager)
        pager.addSubview(leaf)

        let pans = ScrollAncestorPans()
        pans.refresh(from: leaf)
        #expect(pans.isInsideVerticalScrollView)
        #expect(pans.isScrollPan(pager.panGestureRecognizer))
        #expect(pans.isScrollPan(page.panGestureRecognizer))

        page.isScrollEnabled = false
        #expect(!pans.isInsideVerticalScrollView)  // the pager alone
        #expect(pans.isScrollPan(pager.panGestureRecognizer))  // and it still waits for the chart
        #expect(pans.isScrollPan(page.panGestureRecognizer))
    }

    @Test("a pan that is not a scroll view's has no vertical capacity")
    func fakePansDoNotCount() {
        let pans = ScrollAncestorPans()
        pans.track(fakes())
        #expect(!pans.isInsideVerticalScrollView)
    }

    // MARK: - Switching back on

    @Test("a scroll view that the host switched off during the hold stays off when the hold ends")
    func hostDisablesDuringTheHold() {
        let page = scrollView()
        let pans = pansInside(page)
        pans.hold(.crosshair)
        #expect(!page.panGestureRecognizer.isEnabled)

        page.isScrollEnabled = false
        pans.release(.crosshair)
        #expect(!page.isScrollEnabled)
        #expect(!page.panGestureRecognizer.isEnabled)  // not switched on under a scroll view that is off

        page.isScrollEnabled = true
        #expect(page.panGestureRecognizer.isEnabled)  // the host's own switch brings it back
    }

    @Test("releaseAll leaves a scroll view that the host switched off during the hold off as well")
    func releaseAllAfterTheHostDisables() {
        let page = scrollView()
        let pans = pansInside(page)
        pans.hold(.pinch)
        page.isScrollEnabled = false
        pans.releaseAll()
        #expect(!page.panGestureRecognizer.isEnabled)
    }

    @Test("of two scroll views the one that was switched off is left off, the other comes back")
    func onlyTheDisabledOneStaysOff() {
        let page = scrollView()
        let pager = scrollView(content: CGSize(width: 1_600, height: 480))
        let leaf = UIView()
        page.addSubview(pager)
        pager.addSubview(leaf)
        let pans = ScrollAncestorPans()
        pans.refresh(from: leaf)

        pans.hold(.drawingDrag)
        pager.isScrollEnabled = false
        pans.release(.drawingDrag)
        #expect(!pager.panGestureRecognizer.isEnabled)
        #expect(page.panGestureRecognizer.isEnabled)
    }
}

@MainActor
@Suite("A chart's input layer inside a scroll view")
struct NestedScrollArbitrationTests {
    private struct Setup {
        let model: TradingChartModel
        let window: UIWindow
        let scroll: UIScrollView
        let layer: ChartInputView
    }

    private func makeSetup(
        takesDrawingTouches: Bool = true,
        inScrollView: Bool = true,
        contentSize: CGSize = CGSize(width: 320, height: 1_600)
    ) -> Setup {
        let model = TradingChartModel(
            series: makeSeries(count: 100, lastStart: baseTime + 99 * 60),
            style: .candles
        )
        model.updateLayoutMetrics(plotWidth: 300, yAxisColumnWidth: 60)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = contentSize
        let content = UIView(frame: CGRect(origin: .zero, size: contentSize))
        let layer = ChartInputView(model: model, takesDrawingTouches: takesDrawingTouches)
        layer.frame = CGRect(x: 10, y: 100, width: 300, height: 300)
        content.addSubview(layer)
        if inScrollView {
            scroll.addSubview(content)
            window.addSubview(scroll)
        } else {
            window.addSubview(content)
        }
        window.makeKeyAndVisible()
        return Setup(model: model, window: window, scroll: scroll, layer: layer)
    }

    // MARK: - Finding the scroll view

    @Test("the layer finds the scroll view above it when it joins a window, and not when there is none")
    func findsTheScrollView() {
        let nested = makeSetup()
        #expect(nested.layer.scrollPans.isScrollPan(nested.scroll.panGestureRecognizer))
        nested.window.isHidden = true

        let alone = makeSetup(inScrollView: false)
        #expect(!alone.layer.scrollPans.isInsideVerticalScrollView)
        alone.window.isHidden = true
    }

    @Test("a layer that moves to another place in the hierarchy looks again")
    func findsAgainAfterAMove() {
        let setup = makeSetup(inScrollView: false)
        #expect(!setup.layer.scrollPans.isInsideVerticalScrollView)

        let otherScroll = UIScrollView(frame: setup.window.bounds)
        setup.window.addSubview(otherScroll)
        otherScroll.addSubview(setup.layer)
        #expect(setup.layer.scrollPans.isScrollPan(otherScroll.panGestureRecognizer))

        setup.window.addSubview(setup.layer)
        #expect(!setup.layer.scrollPans.isInsideVerticalScrollView)
        setup.window.isHidden = true
    }

    // MARK: - Who recognises when

    @Test("the scroll view's pan waits for the chart's pan and for the drawing pan, and for nothing else of the layer")
    func scrollPanWaitsForThePans() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        let layer = setup.layer
        #expect(layer.gestureRecognizer(layer.pan, shouldBeRequiredToFailBy: scrollPan))
        #expect(layer.gestureRecognizer(layer.drawingPan, shouldBeRequiredToFailBy: scrollPan))
        #expect(!layer.gestureRecognizer(layer.press, shouldBeRequiredToFailBy: scrollPan))
        #expect(!layer.gestureRecognizer(layer.tap, shouldBeRequiredToFailBy: scrollPan))
        // The pans of anything that is not a scroll view above the chart are not made to wait.
        let stranger = UIPanGestureRecognizer()
        #expect(!layer.gestureRecognizer(layer.pan, shouldBeRequiredToFailBy: stranger))
        #expect(!layer.gestureRecognizer(layer.drawingPan, shouldBeRequiredToFailBy: stranger))
        setup.window.isHidden = true
    }

    @Test("the layer's pans and long press never recognise together with the scroll view's pan; the tap and the pinch watch may")
    func noSimultaneousRecognitionWithTheScrollView() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        let layer = setup.layer
        for mine in [layer.pan, layer.press, layer.drawingPan] {
            #expect(!layer.gestureRecognizer(mine, shouldRecognizeSimultaneouslyWith: scrollPan))
        }
        #expect(layer.gestureRecognizer(layer.tap, shouldRecognizeSimultaneouslyWith: scrollPan))
        #expect(layer.gestureRecognizer(layer.pinchWatch, shouldRecognizeSimultaneouslyWith: scrollPan))
        // The rules among the layer's own recognisers and towards the pinch are as before.
        let pinch = UIPinchGestureRecognizer()
        for mine in [layer.pan, layer.press, layer.drawingPan, layer.tap, layer.pinchWatch] {
            #expect(layer.gestureRecognizer(mine, shouldRecognizeSimultaneouslyWith: pinch))
        }
        #expect(!layer.gestureRecognizer(layer.pan, shouldRecognizeSimultaneouslyWith: layer.press))
        setup.window.isHidden = true
    }

    @Test("inside a scroll view the chart takes a horizontal drag and leaves a vertical one to the scroll view")
    func panBeginsOnlyHorizontally() {
        let setup = makeSetup(takesDrawingTouches: false)
        let layer = setup.layer

        #expect(layer.chartTakesPan(translation: CGPoint(x: 30, y: 5), velocity: .zero))
        #expect(layer.chartTakesPan(translation: CGPoint(x: 20, y: 11.5), velocity: .zero))  // 30 degrees
        #expect(layer.chartTakesPan(translation: CGPoint(x: -20, y: -11.5), velocity: .zero))
        #expect(!layer.chartTakesPan(translation: CGPoint(x: 5, y: 30), velocity: .zero))
        #expect(!layer.chartTakesPan(translation: CGPoint(x: 8, y: -30), velocity: .zero))
        #expect(!layer.chartTakesPan(translation: .zero, velocity: CGPoint(x: 10, y: 300)))
        setup.window.isHidden = true
    }

    @Test("with no scroll view above, the chart takes the drag whatever the direction, as it always did")
    func panBeginsEveryWhereWithoutAScrollView() {
        let setup = makeSetup(takesDrawingTouches: false, inScrollView: false)
        let layer = setup.layer
        #expect(layer.chartTakesPan(translation: CGPoint(x: 5, y: 30), velocity: .zero))
        #expect(layer.chartTakesPan(translation: .zero, velocity: CGPoint(x: 10, y: 300)))
        #expect(layer.gestureRecognizerShouldBegin(layer.pan))
        setup.window.isHidden = true
    }

    // MARK: - A scroll view that does not scroll vertically

    private let pagerContent = CGSize(width: 1_600, height: 480)

    @Test("inside a pager that does not scroll vertically the chart takes a drag in any direction, as it did before")
    func pagerLeavesTheDirectionAlone() {
        let setup = makeSetup(takesDrawingTouches: false, contentSize: pagerContent)
        let layer = setup.layer
        #expect(layer.chartTakesPan(translation: CGPoint(x: 5, y: 30), velocity: .zero))
        #expect(layer.chartTakesPan(translation: CGPoint(x: 8, y: -30), velocity: .zero))
        #expect(layer.chartTakesPan(translation: .zero, velocity: CGPoint(x: 10, y: 300)))
        #expect(layer.gestureRecognizerShouldBegin(layer.pan))
        setup.window.isHidden = true
    }

    @Test("the pager's pan still waits for the chart's pans and never recognises together with them")
    func pagerStillWaits() {
        let setup = makeSetup(contentSize: pagerContent)
        let layer = setup.layer
        let pagerPan = setup.scroll.panGestureRecognizer
        #expect(layer.scrollPans.isScrollPan(pagerPan))
        #expect(layer.gestureRecognizer(layer.pan, shouldBeRequiredToFailBy: pagerPan))
        #expect(layer.gestureRecognizer(layer.drawingPan, shouldBeRequiredToFailBy: pagerPan))
        for mine in [layer.pan, layer.press, layer.drawingPan] {
            #expect(!layer.gestureRecognizer(mine, shouldRecognizeSimultaneouslyWith: pagerPan))
        }
        setup.window.isHidden = true
    }

    @Test("the pager does not flip under the crosshair, and comes back with it")
    func crosshairHoldsThePager() {
        let setup = makeSetup(contentSize: pagerContent)
        let pagerPan = setup.scroll.panGestureRecognizer
        press(setup.layer, .began)
        #expect(!pagerPan.isEnabled)
        press(setup.layer, .ended)
        #expect(pagerPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("a page with scrolling switched off leaves the drag to the chart, and takes the vertical one again when switched on")
    func scrollDisabledPage() {
        let setup = makeSetup(takesDrawingTouches: false)
        let layer = setup.layer
        let vertical = CGPoint(x: 5, y: 30)
        #expect(!layer.chartTakesPan(translation: vertical, velocity: .zero))

        setup.scroll.isScrollEnabled = false
        #expect(layer.chartTakesPan(translation: vertical, velocity: .zero))
        #expect(layer.gestureRecognizer(layer.pan, shouldBeRequiredToFailBy: setup.scroll.panGestureRecognizer))

        setup.scroll.isScrollEnabled = true
        #expect(!layer.chartTakesPan(translation: vertical, velocity: .zero))
        setup.window.isHidden = true
    }

    @Test("a page whose content grows from nothing to taller than itself takes the vertical drag from then on")
    func contentGrows() {
        let setup = makeSetup(takesDrawingTouches: false, contentSize: CGSize(width: 320, height: 480))
        let layer = setup.layer
        let vertical = CGPoint(x: 5, y: 30)
        #expect(layer.chartTakesPan(translation: vertical, velocity: .zero))
        setup.scroll.contentSize.height = 1_600
        #expect(!layer.chartTakesPan(translation: vertical, velocity: .zero))
        setup.scroll.alwaysBounceVertical = true
        setup.scroll.contentSize.height = 100
        #expect(!layer.chartTakesPan(translation: vertical, velocity: .zero))
        setup.window.isHidden = true
    }

    @Test("a page keeps the vertical drag while the crosshair has switched its pan off")
    func pageHeldByTheCrosshairStaysVertical() {
        let setup = makeSetup(takesDrawingTouches: false)
        let layer = setup.layer
        press(layer, .began)
        #expect(!setup.scroll.panGestureRecognizer.isEnabled)
        #expect(!layer.chartTakesPan(translation: CGPoint(x: 5, y: 30), velocity: .zero))
        press(layer, .ended)
        setup.window.isHidden = true
    }

    @Test("a page that the host switches off during the crosshair is not switched on when the finger lifts")
    func hostDisablesPageDuringTheCrosshair() {
        let setup = makeSetup()
        press(setup.layer, .began)
        setup.scroll.isScrollEnabled = false
        press(setup.layer, .ended)
        #expect(!setup.scroll.panGestureRecognizer.isEnabled)
        setup.window.isHidden = true
    }

    @Test("the drawing pan and the long press are not subject to the direction rule")
    func drawingPanAndPressAreNotFiltered() {
        let setup = makeSetup()
        let layer = setup.layer
        // The drawing pan's own rule (the finger went down on the selected drawing) is unchanged: nothing is selected here.
        #expect(!layer.gestureRecognizerShouldBegin(layer.drawingPan))
        #expect(layer.gestureRecognizerShouldBegin(layer.press))
        setup.window.isHidden = true
    }

    @Test("the pinch watch begins only while zoom is enabled")
    func pinchWatchNeedsZoom() {
        let setup = makeSetup()
        #expect(setup.layer.gestureRecognizerShouldBegin(setup.layer.pinchWatch))
        setup.model.configuration.isZoomEnabled = false
        #expect(!setup.layer.gestureRecognizerShouldBegin(setup.layer.pinchWatch))
        setup.window.isHidden = true
    }

    // MARK: - Keeping the page still

    /// A recogniser whose state the test sets, to drive the actions of a layer as UIKit would.
    private final class FakePress: UILongPressGestureRecognizer {
        var current: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { current }
            set { current = newValue }
        }
    }

    private final class FakePinch: UIPinchGestureRecognizer {
        var current: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { current }
            set { current = newValue }
        }
    }

    private final class FakePan: UIPanGestureRecognizer {
        var current: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { current }
            set { current = newValue }
        }
    }

    private func press(_ layer: ChartInputView, _ state: UIGestureRecognizer.State) {
        let fake = FakePress()
        fake.current = state
        layer.handlePress(fake)
    }

    private func pinch(_ layer: ChartInputView, _ state: UIGestureRecognizer.State) {
        let fake = FakePinch()
        fake.current = state
        layer.handlePinchWatch(fake)
    }

    private func drawingPan(_ layer: ChartInputView, _ state: UIGestureRecognizer.State) {
        let fake = FakePan()
        fake.current = state
        layer.handleDrawingPan(fake)
    }

    @Test("the page's pan is off for as long as the long press holds the crosshair")
    func crosshairHoldsThePage() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        #expect(scrollPan.isEnabled)

        press(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        press(setup.layer, .changed)
        #expect(!scrollPan.isEnabled)
        press(setup.layer, .ended)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("a long press that is cancelled lets the page go too")
    func cancelledPressLetsTheScrollViewGo() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        press(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        press(setup.layer, .cancelled)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("with the crosshair off the long press does not hold the page")
    func noCrosshairNoHold() {
        let setup = makeSetup()
        setup.model.configuration.isCrosshairEnabled = false
        let scrollPan = setup.scroll.panGestureRecognizer
        press(setup.layer, .began)
        #expect(scrollPan.isEnabled)
        press(setup.layer, .ended)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("the page's pan is off while two fingers are on the chart, and back when they go")
    func pinchHoldsThePage() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        pinch(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        pinch(setup.layer, .changed)
        #expect(!scrollPan.isEnabled)
        pinch(setup.layer, .ended)
        #expect(scrollPan.isEnabled)

        pinch(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        pinch(setup.layer, .cancelled)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("a pinch during a long press: the page is let go only when both are over")
    func pressAndPinchTogether() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        press(setup.layer, .began)
        pinch(setup.layer, .began)
        pinch(setup.layer, .ended)
        #expect(!scrollPan.isEnabled)
        press(setup.layer, .ended)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("a drag of a drawing holds the page, and the end of the drag lets it go")
    func drawingDragHoldsThePage() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        let layer = setup.layer
        let model = setup.model
        let plot = layer.bounds
        let last = model.series.lastTime!
        let drawing = ChartDrawing(kind: .trendLine, anchors: [
            ChartAnchor(time: last.addingTimeInterval(-30 * 60), price: 130),
            ChartAnchor(time: last.addingTimeInterval(-10 * 60), price: 150),
        ])
        model.drawings = [drawing]
        model.selectedDrawingID = drawing.id

        // A finger that went down away from the drawing does not hold the page: the drag is not the drawing's.
        layer.firstTouch = CGPoint(x: 1, y: 1)
        drawingPan(layer, .began)
        #expect(scrollPan.isEnabled)
        drawingPan(layer, .ended)

        layer.firstTouch = model.drawingTransform(plot: plot).point(for: drawing.anchors[1])
        drawingPan(layer, .began)
        #expect(!scrollPan.isEnabled)
        drawingPan(layer, .changed)
        #expect(!scrollPan.isEnabled)
        drawingPan(layer, .ended)
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("leaving the window lets the page go, whatever was holding it")
    func leavingTheWindowLetsGo() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        press(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        setup.layer.removeFromSuperview()
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("taking the representable down lets the page go")
    func dismantlingLetsGo() {
        let setup = makeSetup()
        let scrollPan = setup.scroll.panGestureRecognizer
        pinch(setup.layer, .began)
        #expect(!scrollPan.isEnabled)
        ChartInputLayer.dismantleUIView(setup.layer, coordinator: ())
        #expect(scrollPan.isEnabled)
        setup.window.isHidden = true
    }

    @Test("a layer with no scroll view above holds nothing, and a long press there is as it was")
    func noScrollViewNoHold() {
        let setup = makeSetup(inScrollView: false)
        press(setup.layer, .began)
        #expect(setup.scroll.panGestureRecognizer.isEnabled)  // not above the layer: not touched
        press(setup.layer, .ended)
        setup.window.isHidden = true
    }
}
