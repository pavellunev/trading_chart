import Foundation
import TradingChartCore

/// What assistive technologies do to the chart: VoiceOver scrolls the window by a whole window width (the scroll gesture and
/// the actions of the chart) and reads the last price and the visible range.
@available(iOS 17.0, *)
extension TradingChartModel {

    /// A move of the window made by an assistive technology.
    enum AccessibilityScroll: Equatable {
        /// One window width towards the past (the first bar is the limit).
        case earlier
        /// One window width towards the live edge (which is the limit).
        case later
        /// Straight to the live edge.
        case latest
    }

    /// Moves the window as `action` says. Ends a fling in progress, like any other write of ``scrollPosition``.
    ///
    /// - Returns: Whether the window moved (it does not when it is at the limit already, nor when the chart has no bars).
    @discardableResult
    func accessibilityScroll(_ action: AccessibilityScroll) -> Bool {
        guard !series.isEmpty else { return false }
        let before = scrollPosition
        switch action {
        case .latest:
            scrollToLiveEdge()
        case .earlier, .later:
            let range = touchScrollRange
            let step = (action == .earlier ? -1 : 1) * visibleDuration
            let target = Swift.min(Swift.max(before.addingTimeInterval(step), range.lowerBound), range.upperBound)
            if target != before { scrollPosition = target }
        }
        return scrollPosition != before
    }
}

/// The words VoiceOver hears. Pure.
@available(iOS 17.0, *)
enum ChartAccessibilityText {
    /// What the chart is.
    static func label(for style: SeriesStyle, strings: TradingChartStrings = .standard) -> String {
        switch style {
        case .line: strings.lineChart
        case .area: strings.areaChart
        case .candles: strings.candlestickChart
        }
    }

    /// The range of time on the screen: `Showing 04 Oct 12:00 to 04 Oct 13:30`.
    static func range(
        _ window: ClosedRange<Date>,
        format: (Date) -> String,
        strings: TradingChartStrings = .standard
    ) -> String {
        strings.format(strings.showingRange, format(window.lowerBound), format(window.upperBound))
    }

    /// The last price, the range of time on the screen, and whether that is the newest data: for example
    /// `Last price 120.50. Showing 04 Oct 12:00 to 04 Oct 13:30. At the latest bar.`
    ///
    /// - Parameters:
    ///   - lastPrice: The formatted last price, if there is one.
    ///   - window: The visible range of time.
    ///   - atLiveEdge: Whether the newest bar is at the right edge.
    ///   - format: Formats a time of the window.
    ///   - strings: The words.
    static func value(
        lastPrice: String?,
        window: ClosedRange<Date>,
        atLiveEdge: Bool,
        format: (Date) -> String,
        strings: TradingChartStrings = .standard
    ) -> String {
        var parts: [String] = []
        if let lastPrice { parts.append(strings.format(strings.lastPrice, lastPrice)) }
        parts.append(range(window, format: format, strings: strings))
        parts.append(atLiveEdge ? strings.atLatestBar : strings.scrolledIntoThePast)
        return parts.joined(separator: ". ") + "."
    }

    /// What is said after a scroll action: the new range, or that the window is at its limit already.
    static func announcement(
        after action: TradingChartModel.AccessibilityScroll,
        moved: Bool,
        window: ClosedRange<Date>,
        format: (Date) -> String,
        strings: TradingChartStrings = .standard
    ) -> String {
        guard !moved else { return range(window, format: format, strings: strings) }
        return action == .earlier ? strings.atStartOfHistory : strings.atLatestBar
    }
}
