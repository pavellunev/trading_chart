import UIKit

/// Which of two directions a pan that has just begun to move belongs to, when the chart sits in a scroll view: a pan that is
/// mostly horizontal is the chart's, anything else is left to the scroll view. A pan exactly on the diagonal stays with the chart.
///
/// `translation` is the distance the finger has gone since it went down; `velocity` is used only when there is no distance yet.
@available(iOS 17.0, *)
enum PanDirection {
    static func isHorizontal(translation: CGPoint, velocity: CGPoint) -> Bool {
        let vector = translation == .zero ? velocity : translation
        return abs(vector.x) >= abs(vector.y)
    }
}

/// The pan recognisers of the scroll views that hold a chart, and the switch that keeps them still while the chart has the finger.
///
/// A scroll view above the chart (a SwiftUI `ScrollView`, a `List`) takes a vertical drag that starts on the chart as well as the
/// chart's own recognisers do. The chart's input layer therefore does three things with what this finds:
///
/// - it never recognises together with a scroll view's pan, which waits for the chart's pan to fail (a vertical drag fails the
///   chart's pan at once, so the page scrolls with no delay); a scroll view that cannot scroll vertically (a horizontal pager, a
///   page with scrolling switched off) does not change what the chart takes, but its pan waits and never moves along with the chart;
/// - it switches those pans off while a long press (the crosshair), a pinch or a drag of a drawing is in progress, so that the page
///   does not scroll under a finger that is doing something else;
/// - it switches them back on when that ends, or when the layer leaves the window.
///
/// The recognisers are held weakly: a chart that outlives its scroll view, or the other way round, keeps nothing alive.
@available(iOS 17.0, *)
@MainActor
final class ScrollAncestorPans {
    /// What keeps the pans of the scroll views off.
    struct Reason: OptionSet {
        let rawValue: Int
        /// A long press is in progress: the crosshair follows the finger.
        static let crosshair = Reason(rawValue: 1 << 0)
        /// A drawing is being dragged.
        static let drawingDrag = Reason(rawValue: 1 << 1)
        /// Two fingers are on the chart: a pinch.
        static let pinch = Reason(rawValue: 1 << 2)
    }

    private struct Weak {
        weak var pan: UIPanGestureRecognizer?
    }

    /// The pans of the scroll views above the chart, nearest first.
    private var tracked: [Weak] = []
    /// The pans this object switched off, and nobody else: they are switched on again by `release`.
    private var switchedOff: [Weak] = []
    private var reasons: Reason = []

    /// Whether a scroll view above the chart can scroll vertically right now: scrolling is on (the pan is not switched off by the
    /// host; one switched off by this object counts), and the content is taller than the scroll view or the scroll view bounces
    /// always. Asked when a pan is about to begin, as the answer changes with the host's state.
    var isInsideVerticalScrollView: Bool {
        tracked.contains { entry in entry.pan.map(canScrollVertically) ?? false }
    }

    /// Whether `recognizer` is the pan of a scroll view above the chart.
    func isScrollPan(_ recognizer: UIGestureRecognizer) -> Bool {
        tracked.contains { $0.pan === recognizer }
    }

    /// Looks for the scroll views above `view`. Called when the view's place in the hierarchy changes; what was held for the old
    /// ones is let go first.
    func refresh(from view: UIView) {
        releaseAll()
        var pans: [UIPanGestureRecognizer] = []
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView { pans.append(scrollView.panGestureRecognizer) }
            ancestor = current.superview
        }
        track(pans)
    }

    /// Takes `pans` as the pans of the scroll views above the chart.
    func track(_ pans: [UIPanGestureRecognizer]) {
        tracked = pans.map { Weak(pan: $0) }
    }

    /// Switches the pans of the scroll views off for `reason`. A pan that is already off (the host disabled scrolling) is left alone.
    func hold(_ reason: Reason) {
        let wasFree = reasons.isEmpty
        reasons.insert(reason)
        guard wasFree else { return }
        switchedOff = []
        for entry in tracked {
            guard let pan = entry.pan, pan.isEnabled else { continue }
            pan.isEnabled = false
            switchedOff.append(entry)
        }
    }

    /// Lets go of `reason`; the pans come back on when nothing else holds them.
    func release(_ reason: Reason) {
        guard !reasons.isEmpty else { return }
        reasons.remove(reason)
        if reasons.isEmpty { switchBackOn() }
    }

    /// Lets go of every reason.
    func releaseAll() {
        reasons = []
        switchBackOn()
    }

    private func canScrollVertically(_ pan: UIPanGestureRecognizer) -> Bool {
        guard let scrollView = pan.view as? UIScrollView, scrollView.isScrollEnabled else { return false }
        guard pan.isEnabled || switchedOff.contains(where: { $0.pan === pan }) else { return false }
        return scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height + 1
    }

    /// Switches on what was switched off; a pan whose scroll view the host has switched off meanwhile stays off.
    private func switchBackOn() {
        for entry in switchedOff {
            guard let pan = entry.pan else { continue }
            if (pan.view as? UIScrollView)?.isScrollEnabled == false { continue }
            pan.isEnabled = true
        }
        switchedOff = []
    }
}
