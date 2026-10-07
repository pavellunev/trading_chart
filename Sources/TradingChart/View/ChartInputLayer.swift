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
    }
}

@available(iOS 17.0, *)
final class ChartInputView: UIView, UIGestureRecognizerDelegate {
    var model: TradingChartModel

    let pan = UIPanGestureRecognizer()
    let press = UILongPressGestureRecognizer()
    let tap = UITapGestureRecognizer()
    let drawingPan = UIPanGestureRecognizer()
    private let takesDrawingTouches: Bool
    /// Whether a long press is in progress: the crosshair follows the finger, the window stays.
    private var isSelecting = false
    /// Where the finger went down, in the coordinates of the view: a pan is recognised only after the finger has moved, and
    /// whose it is depends on where it started.
    private var firstTouch = CGPoint.zero
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
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopFling() }
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

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard model.configuration.isCrosshairEnabled else { return }
            isSelecting = true
            model.cancelTouchScroll()
            model.touchCrosshair(atX: gesture.location(in: self).x, plotWidth: bounds.width)
        case .changed:
            if isSelecting { model.touchCrosshair(atX: gesture.location(in: self).x, plotWidth: bounds.width) }
        default:
            if isSelecting {
                isSelecting = false
                model.clearTouchCrosshair()
            }
        }
    }

    // MARK: - The drawings

    /// A tap places an anchor while a tool is active, and otherwise selects the drawing under it or clears the selection.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        model.drawingTap(at: gesture.location(in: self), plot: bounds)
    }

    /// A drag that started on the selected drawing: the anchor or the whole drawing follows the finger.
    @objc private func handleDrawingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDraggingDrawing = model.drawingBeginDrag(at: firstTouch, plot: bounds)
            if isDraggingDrawing { model.drawingContinueDrag(to: gesture.location(in: self), plot: bounds) }
        case .changed:
            if isDraggingDrawing { model.drawingContinueDrag(to: gesture.location(in: self), plot: bounds) }
        default:
            if isDraggingDrawing {
                isDraggingDrawing = false
                model.drawingEndDrag()
            }
        }
    }

    /// Whose a pan is: the drawing's when the finger went down on the selected drawing, the chart's otherwise.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // With the crosshair switched off a long press must not start at all: it would hold the finger for the press, and the
        // pan that follows would never begin.
        if gestureRecognizer === press { return model.configuration.isCrosshairEnabled }
        guard takesDrawingTouches else { return true }
        let grabsDrawing = model.drawingGrabsSelected(at: firstTouch, plot: bounds)
        if gestureRecognizer === pan { return !grabsDrawing }
        if gestureRecognizer === drawingPan { return grabsDrawing }
        return true
    }

    /// The pans and the long press exclude each other, and so do the recognisers of two panes (a finger on each of two panes
    /// would scroll the chart twice and start two flings); everything else (the pinch and the tap) goes on.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        if let otherLayer = other.view as? ChartInputView, otherLayer !== self { return false }
        let own: [UIGestureRecognizer] = [pan, press, drawingPan]
        return !(own.contains(gestureRecognizer) && own.contains(other))
    }
}
