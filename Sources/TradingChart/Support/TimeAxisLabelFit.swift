import CoreGraphics
import Foundation

/// Decides whether a time axis label fits into the visible plot. Pure.
@available(iOS 17.0, *)
enum TimeAxisLabelFit {
    /// Distance from a tick to the start of its label: labels are leading-aligned at the tick, with a small gap.
    /// Generous on purpose, so that a label is dropped rather than cut.
    static let tickGap: CGFloat = 6

    /// Whether a label of `labelWidth` points starting at the tick of `tick` lies entirely inside the visible plot
    /// of `plotWidth` points that shows `visibleRange`. Always `true` while the plot or the label is not measured.
    static func fits(
        tick: Date,
        visibleRange: ClosedRange<Date>,
        plotWidth: CGFloat,
        labelWidth: CGFloat
    ) -> Bool {
        let duration = visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound)
        guard plotWidth > 0, labelWidth > 0, duration > 0 else { return true }
        let x = CGFloat(tick.timeIntervalSince(visibleRange.lowerBound) / duration) * plotWidth
        return x >= 0 && x + tickGap + labelWidth <= plotWidth
    }
}
