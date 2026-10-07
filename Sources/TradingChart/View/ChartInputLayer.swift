import SwiftUI
import UIKit

/// The transparent layer over the plot of a pane that takes the finger: a drag scrolls the chart (and a fling goes on after
/// the finger lifts), a long press shows the crosshair and a drag after it moves the crosshair. On the main pane
/// (`takesDrawingTouches`) it also takes the touches of the drawing tools: a tap places an anchor or selects a drawing, and a drag
/// that starts on the selected drawing moves it.
///
/// The charts under it do not take touches (`allowsHitTesting(false)`), they only follow ``TradingChartModel/scrollPosition``;
/// see `TradingChartModel+Scrolling.swift` for why. A view of its own that reads nothing from the model while SwiftUI
/// evaluates it, so a scroll step does not evaluate it.
///
/// One view takes every one-finger touch, so that the gestures need no layer of their own on top of each other: a pan that
/// starts on the selected drawing is the drawing's, any other pan is the chart's, and the long press (crosshair) and the pinch
/// (the chart view's, with two fingers) work in every mode of the drawing tools. Only one pane at a time takes a finger: the
/// recognisers of one input layer never run at the same time as those of another.
///
/// Inside a scroll view that scrolls vertically (a page with the chart in the middle of it) the finger is shared with the page: a
/// mostly horizontal drag is the chart's, a vertical one is the page's, and while the crosshair, a pinch or a drawing drag is in
/// progress the page stays still (see ``ScrollAncestorPans``). A scroll view above the chart that does not scroll vertically (a
/// horizontal pager, scrolling switched off) leaves the drag to the chart in any direction, and its own pan waits for the chart's.
@available(iOS 17.0, *)
struct ChartInputLayer: UIViewRepresentable {
    let model: TradingChartModel
    var takesDrawingTouches = false

    func makeUIView(context: Context) -> ChartInputView {
        ChartInputView(model: model, takesDrawingTouches: takesDrawingTouches)
    }

    func updateUIView(_ view: ChartInputView, context: Context) {
        view.model = model
    }

    static func dismantleUIView(_ view: ChartInputView, coordinator: ()) {
        view.stopFling()
        view.scrollPans.releaseAll()
    }
}

@available(iOS 17.0, *)
final class ChartInputView: UIView, UIGestureRecognizerDelegate {
    var model: TradingChartModel

    let pan = UIPanGestureRecognizer()
    let press = UILongPressGestureRecognizer()
    let tap = UITapGestureRecognizer()
    let drawingPan = UIPanGestureRecognizer()
    /// Watches for two fingers on the layer, only to keep the page still: the pinch itself is the chart view's.
    let pinchWatch = UIPinchGestureRecognizer()
    /// The scroll views above this layer.
    let scrollPans = ScrollAncestorPans()
    private let takesDrawingTouches: Bool
    /// Whether a long press is in progress: the crosshair follows the finger, the window stays.
    private var isSelecting = false
    /// Where the finger went down, in the coordinates of the view: a pan is recognised only after the finger has moved, and
    /// whose it is depends on where it started.
    var firstTouch = CGPoint.zero
    /// Whether the drawing pan in progress grabbed the drawing.
    private var isDraggingDrawing = false

    init(model: TradingChartModel, takesDrawingTouches: Bool) {
        self.model = model
        self.takesDrawingTouches = takesDrawingTouches
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false

        pan.maximumNumberOfTouches = 1
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        press.minimumPressDuration = 0.3
        press.addTarget(self, action: #selector(handlePress(_:)))
        press.delegate = self
        addGestureRecognizer(press)

        pinchWatch.cancelsTouchesInView = false
        pinchWatch.addTarget(self, action: #selector(handlePinchWatch(_:)))
        pinchWatch.delegate = self
        addGestureRecognizer(pinchWatch)

        if takesDrawingTouches {
            drawingPan.maximumNumberOfTouches = 1
            drawingPan.addTarget(self, action: #selector(handleDrawingPan(_:)))
            drawingPan.delegate = self
            addGestureRecognizer(drawingPan)

            // A tap is a touch that did not become a drag or a long press: a tap recogniser alone would still count a touch that
            // moved a few dozen points, or was held.
            tap.addTarget(self, action: #selector(handleTap(_:)))
            tap.delegate = self
            tap.require(toFail: pan)
            tap.require(toFail: drawingPan)
            tap.require(toFail: press)
            addGestureRecognizer(tap)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A fling that outlives the screen it was on would tick a display link for nothing (and the host's model, which outlives
    /// the view, would go on moving a window nobody sees): leaving the window stops it.
    ///
    /// The scroll views above the layer are looked for whenever its place in the hierarchy changes.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopFling() }
        scrollPans.refresh(from: self)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        scrollPans.refresh(from: self)
    }

    /// Stops the fling in progress, if any.
    func stopFling() {
        model.stopScrollMomentum()
    }

    /// A finger that goes down stops a fling, as it does on a scroll view.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        model.stopScrollMomentum()
        if let touch = touches.first { firstTouch = touch.location(in: self) }
        super.touchesBegan(touches, with: event)
    }

    // MARK: - The chart: scroll and crosshair

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isSelecting else { return }
        switch gesture.state {
        case .began:
            model.beginTouchScroll()
        case .changed:
            model.touchScroll(translation: gesture.translation(in: self).x, plotWidth: bounds.width)
        case .ended:
            model.endTouchScroll(velocity: gesture.velocity(in: self).x, plotWidth: bounds.width)
        default:
            model.cancelTouchScroll()
        }
    }

    @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard model.configuration.isCrosshairEnabled else { return }
            isSelecting = true
            scrollPans.hold(.crosshair)
            model.cancelTouchScroll()
            model.touchCrosshair(atX: gesture.location(in: self).x, plotWidth: bounds.width)
        case .changed:
            if isSelecting { model.touchCrosshair(atX: gesture.location(in: self).x, plotWidth: bounds.width) }
        default:
            if isSelecting {
                isSelecting = false
                scrollPans.release(.crosshair)
                model.clearTouchCrosshair()
            }
        }
    }

    /// Two fingers on the layer: the page stays still for as long as they are down.
    @objc func handlePinchWatch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: scrollPans.hold(.pinch)
        case .changed: break
        default: scrollPans.release(.pinch)
        }
    }

    // MARK: - The drawings

    /// A tap places an anchor while a tool is active, and otherwise selects the drawing under it or clears the selection.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        model.drawingTap(at: gesture.location(in: self), plot: bounds)
    }

    /// A drag that started on the selected drawing: the anchor or the whole drawing follows the finger.
    @objc func handleDrawingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDraggingDrawing = model.drawingBeginDrag(at: firstTouch, plot: bounds)
            if isDraggingDrawing {
                scrollPans.hold(.drawingDrag)
                model.drawingContinueDrag(to: gesture.location(in: self), plot: bounds)
            }
        case .changed:
            if isDraggingDrawing { model.drawingContinueDrag(to: gesture.location(in: self), plot: bounds) }
        default:
            if isDraggingDrawing {
                isDraggingDrawing = false
                scrollPans.release(.drawingDrag)
                model.drawingEndDrag()
            }
        }
    }

    /// Whose a pan is: the drawing's when the finger went down on the selected drawing, the chart's otherwise; and, inside a
    /// scroll view, the chart's only when it is mostly horizontal.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // With the crosshair switched off a long press must not start at all: it would hold the finger for the press, and the
        // pan that follows would never begin.
        if gestureRecognizer === press { return model.configuration.isCrosshairEnabled }
        if gestureRecognizer === pinchWatch { return model.configuration.isZoomEnabled }
        // A vertical drag fails the chart's pan at once, and the scroll view above (which waits for it) takes the drag.
        if gestureRecognizer === pan,
           !chartTakesPan(translation: pan.translation(in: self), velocity: pan.velocity(in: self)) {
            return false
        }
        guard takesDrawingTouches else { return true }
        let grabsDrawing = model.drawingGrabsSelected(at: firstTouch, plot: bounds)
        if gestureRecognizer === pan { return !grabsDrawing }
        if gestureRecognizer === drawingPan { return grabsDrawing }
        return true
    }

    /// Whether a pan that has begun to move, going as `translation` and `velocity` say, is the chart's: always, unless a scroll view
    /// above the chart can scroll vertically just now, which takes the drags that are not mostly horizontal.
    func chartTakesPan(translation: CGPoint, velocity: CGPoint) -> Bool {
        !scrollPans.isInsideVerticalScrollView || PanDirection.isHorizontal(translation: translation, velocity: velocity)
    }

    /// The pans and the long press exclude each other, and so do the recognisers of two panes (a finger on each of two panes
    /// would scroll the chart twice and start two flings) and the pan of a scroll view above the chart (the page would scroll
    /// with the chart); everything else (the pinch and the tap) goes on.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        if let otherLayer = other.view as? ChartInputView, otherLayer !== self { return false }
        let own: [UIGestureRecognizer] = [pan, press, drawingPan]
        if own.contains(gestureRecognizer), scrollPans.isScrollPan(other) { return false }
        return !(own.contains(gestureRecognizer) && own.contains(other))
    }

    /// The pan of a scroll view above the chart waits for the chart's pans: it starts only when neither of them takes the drag.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pan || gestureRecognizer === drawingPan) && scrollPans.isScrollPan(other)
    }
}
