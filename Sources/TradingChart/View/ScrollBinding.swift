import SwiftUI
import Charts

@available(iOS 17.0, *)
extension TradingChartModel {
    /// The binding of `chartScrollPosition(x:)`: the scroll position plus ``scrollNudge``. The charts follow it; they never
    /// change it (the finger is taken by ``ChartInputLayer``), so a write through it is ignored.
    ///
    /// When the left end of the time domain moves (history prepended, the head trimmed) Swift Charts keeps its scroll
    /// offset in points and does not look at the bound position again, so the window would drift to other times, or
    /// to times that have no marks. A different value of the binding makes it re-apply the position, and the flipped
    /// nudge (a thousandth of a bar, far below a pixel) is that different value, delivered in the same update as the
    /// new domain.
    var chartScrollBinding: Binding<Date> {
        Binding(
            get: { self.scrollPosition.addingTimeInterval(self.scrollNudge) },
            set: { _ in }
        )
    }
}

/// Binds the chart to the scroll position of the model.
///
/// Swift Charts reads the binding while the modifier is applied, so whatever view applies it depends on
/// ``TradingChartModel/scrollPosition``. A modifier of its own takes that dependency: a scroll step re-evaluates
/// this tiny body, not the body of the pane (which would rebuild all the marks).
@available(iOS 17.0, *)
struct ChartScrollBridge: ViewModifier {
    let model: TradingChartModel

    func body(content: Content) -> some View {
        content.chartScrollPosition(x: model.chartScrollBinding)
    }
}
