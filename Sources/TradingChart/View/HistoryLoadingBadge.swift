import SwiftUI

/// A compact spinner at the left edge of the plot, shown while the host loads older history.
@available(iOS 17.0, *)
struct HistoryLoadingBadge: View {
    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartStrings) private var strings

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .padding(6)
            .background(theme.tooltipBackground, in: Circle())
            .accessibilityLabel(Text(verbatim: strings.loadingHistory))
            .allowsHitTesting(false)
    }

    /// The distance from the left edge of the plot to the centre of the spinner.
    static let inset: CGFloat = 20
}

/// Hosts the history spinner. A leaf view of its own: whether the spinner shows depends on the scroll position, which
/// only this view reads (and only while history is loading), so the chart is not rebuilt by a scroll step.
@available(iOS 17.0, *)
struct HistoryLoadingOverlay: View {
    let model: TradingChartModel
    /// The visible part of the plot in the coordinate space of the chart overlay.
    let visiblePlot: CGRect

    var body: some View {
        if model.isLoadingHistory,
           HistoryLoadingIndicator.isVisible(
               isLoading: true,
               firstTime: model.series.firstTime,
               visibleRange: model.visibleTimeRange
           ) {
            HistoryLoadingBadge()
                .position(x: visiblePlot.minX + HistoryLoadingBadge.inset, y: visiblePlot.midY)
        }
    }
}

/// When the history spinner is on screen. Pure.
@available(iOS 17.0, *)
enum HistoryLoadingIndicator {
    /// The spinner shows while history is loading and the oldest bar is in the window or less than one window width
    /// to the left of it, i.e. while the user is close enough to the loaded edge to notice the missing data.
    static func isVisible(isLoading: Bool, firstTime: Date?, visibleRange: ClosedRange<Date>) -> Bool {
        guard isLoading, let firstTime, firstTime <= visibleRange.upperBound else { return false }
        let width = visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound)
        return visibleRange.lowerBound.timeIntervalSince(firstTime) < width
    }
}
