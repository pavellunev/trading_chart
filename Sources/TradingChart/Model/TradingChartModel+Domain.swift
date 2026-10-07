import Foundation
import TradingChartCore

/// The time domain the charts are laid out for.
///
/// Swift Charts keeps the scroll offset in points, measured from the left end of its time domain. When the left end moves
/// (older bars prepended, the head of the series trimmed by a live update) the same offset points at another time, and the
/// charts are blank or show the wrong window until they are made to look at the scroll position again (see ``scrollNudge``),
/// which takes a frame or two. So the left end is held back: with more history to load it sits a reserve of bars before the
/// first bar (``TradingChartConfiguration/historyReserveBars``), and it moves only when the series is replaced, or when
/// history is prepended beyond the reserve (and then in big steps, one reserve at a time, and only while the window is still:
/// until it stops, the bars beyond the old left end cannot be scrolled to). A prepend inside the reserve and a trim change
/// nothing the charts lay out.
///
/// The reserve is empty space the user cannot scroll to: touch scrolling stops at the first bar (``touchScrollRange``).
@available(iOS 17.0, *)
extension TradingChartModel {

    /// The domain of the series as ``ViewportMath/xDomain(series:style:configuration:now:)`` has it, without the held-back left
    /// end. A series without bars is laid out around the window.
    var naturalXDomain: ClosedRange<Date> {
        naturalXDomain(for: series)
    }

    private func naturalXDomain(for series: ChartSeries) -> ClosedRange<Date> {
        // Only a series without bars needs a time to be laid out around. The position of the window is read for that one alone:
        // a pane that asks for the domain of a series with bars must not depend on it (it changes on every scroll step).
        let now = series.isEmpty ? scrollPosition : Date(timeIntervalSince1970: 0)
        return ViewportMath.xDomain(series: series, style: style, configuration: viewport, now: now)
    }

    /// The domain of a series with the held-back left end.
    func chartXDomain(for series: ChartSeries) -> ClosedRange<Date> {
        let natural = naturalXDomain(for: series)
        guard let start = chartDomainStart else { return natural }
        // Bars older than the held-back left end, prepended while the window moves, are left out until it stops.
        return (domainExpansionPending ? start : Swift.min(start, natural.lowerBound))...natural.upperBound
    }

    /// The domain of the series that is shown.
    var chartXDomain: ClosedRange<Date> {
        chartXDomain(for: series)
    }

    /// Chooses the held-back left end after a change of the data, and flips ``scrollNudge`` if the left end of the domain
    /// moved.
    func refreshChartDomain() {
        if series.firstTime != nil {
            let natural = naturalXDomain
            let reserve = hasMoreHistory ? Double(Swift.max(configuration.historyReserveBars, 0)) * series.interval.seconds : 0
            if domainStartNeedsReset || chartDomainStart == nil {
                chartDomainStart = natural.lowerBound.addingTimeInterval(-reserve)
                domainExpansionPending = false
            } else if let start = chartDomainStart, natural.lowerBound < start {
                if isScrolling {
                    domainExpansionPending = true
                } else {
                    chartDomainStart = natural.lowerBound.addingTimeInterval(-reserve)
                    domainExpansionPending = false
                }
            }
        } else {
            chartDomainStart = nil
            domainExpansionPending = false
        }
        domainStartNeedsReset = false
        let lower = chartXDomain.lowerBound
        if let last = lastChartDomainLower, last != lower {
            scrollNudge = scrollNudge == 0 ? series.interval.seconds * Self.scrollNudgeBars : 0
        }
        lastChartDomainLower = lower
    }

    /// Whether the window is being moved: by a finger, by a fling, or by scroll steps that came in the last moments.
    private var isScrolling: Bool {
        isScrollActive || scrollMomentum != nil || touchScrollStart != nil
    }

    /// The window stopped: extends the domain if history was prepended beyond the reserve while it moved.
    func applyPendingDomainExpansion() {
        guard domainExpansionPending, !isScrolling else { return }
        batch {}
    }
}
