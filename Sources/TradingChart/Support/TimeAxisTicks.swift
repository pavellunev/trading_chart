import Foundation
import TradingChartCore

/// The tick dates of the time axis, generated for a window of the series instead of for the whole scrollable domain.
///
/// With `AxisMarks(values: .automatic(...))` Swift Charts creates marks for the whole scrollable domain on every frame:
/// the number of ticks (and of grid lines and labels) grows with the length of the series, so a chart with 5 000 bars
/// scrolled much slower than one with 600. Ticks on a fixed grid of round times, generated only for the render window,
/// cost the same for any series length. A tick never moves while the window scrolls: the grid depends on the step
/// alone, and the step on the width of the window.
/// Pure.
@available(iOS 17.0, *)
enum TimeAxisTicks {

    /// The distance between ticks.
    enum Step: Equatable {
        /// A step that divides the day (seconds, minutes, hours); the ticks are its multiples on the local clock.
        case seconds(TimeInterval)
        /// Whole local days, counted from 1 January 1970.
        case days(Int)
        /// Whole calendar months, aligned to the start of the month of year zero.
        case months(Int)

        /// The step as a time span; a month counts as 30.4 days.
        var approximateSeconds: TimeInterval {
            switch self {
            case .seconds(let seconds): seconds
            case .days(let days): Double(days) * 86_400
            case .months(let months): Double(months) * 2_629_800
            }
        }
    }

    /// The steps to choose from, ascending.
    static let ladder: [Step] = [
        .seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(15), .seconds(30),
        .seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900), .seconds(1_800),
        .seconds(3_600), .seconds(7_200), .seconds(10_800), .seconds(14_400), .seconds(21_600), .seconds(43_200),
        .days(1), .days(2), .days(7), .days(14),
        .months(1), .months(3), .months(6), .months(12), .months(24), .months(60),
    ]

    /// The smallest step that puts at most about `desiredCount` ticks into a window `visibleDuration` seconds wide.
    ///
    /// Labels of a series with bars of an hour or more show a day, those of a series with bars of a week or more a
    /// month, so the step is not allowed to be smaller than that: a day label would repeat.
    static func step(visibleDuration: TimeInterval, interval: ChartInterval, desiredCount: Int) -> Step {
        let target = visibleDuration / Double(Swift.max(desiredCount, 1))
        let minimum: TimeInterval
        if interval.seconds >= 604_800 {
            minimum = Step.months(1).approximateSeconds
        } else if interval.seconds >= 3_600 {
            minimum = 86_400
        } else {
            minimum = 0
        }
        return ladder.first { $0.approximateSeconds >= target && $0.approximateSeconds >= minimum }
            ?? ladder[ladder.count - 1]
    }

    /// The ticks inside `range`, ascending, on the grid of the step that suits a window `visibleDuration` seconds wide.
    /// At most 256 values.
    static func values(
        in range: ClosedRange<Date>,
        visibleDuration: TimeInterval,
        interval: ChartInterval,
        desiredCount: Int,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [Date] {
        guard visibleDuration > 0, visibleDuration.isFinite else { return [] }
        let step = step(visibleDuration: visibleDuration, interval: interval, desiredCount: desiredCount)
        switch step {
        case .seconds(let seconds):
            return localMultiples(in: range, step: seconds, timeZone: timeZone)
        case .days(let days):
            return localDays(in: range, step: days, timeZone: timeZone)
        case .months(let months):
            return monthStarts(in: range, step: months, timeZone: timeZone)
        }
    }

    private static let limit = 256

    /// Times that are multiples of `step` on the local clock.
    private static func localMultiples(in range: ClosedRange<Date>, step: TimeInterval, timeZone: TimeZone) -> [Date] {
        let offset = Double(timeZone.secondsFromGMT(for: range.lowerBound))
        var tick = ((range.lowerBound.timeIntervalSince1970 + offset) / step).rounded(.up) * step - offset
        var result: [Date] = []
        while tick <= range.upperBound.timeIntervalSince1970, result.count < limit {
            result.append(Date(timeIntervalSince1970: tick))
            tick += step
        }
        return result
    }

    /// Local midnights of the days whose number (days since 1 January 1970) is a multiple of `step`.
    private static func localDays(in range: ClosedRange<Date>, step: Int, timeZone: TimeZone) -> [Date] {
        let offset = Double(timeZone.secondsFromGMT(for: range.lowerBound))
        let first = ((range.lowerBound.timeIntervalSince1970 + offset) / 86_400).rounded(.down)
        var day = (first / Double(step)).rounded(.down) * Double(step)
        var result: [Date] = []
        while result.count < limit {
            let local = day * 86_400
            // The offset of the day itself, in case the clock changed between the start of the range and that day.
            let dayOffset = Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: local - offset)))
            let tick = Date(timeIntervalSince1970: local - dayOffset)
            if tick > range.upperBound { break }
            if tick >= range.lowerBound { result.append(tick) }
            day += Double(step)
        }
        return result
    }

    /// The starts of the months whose index (`year * 12 + month - 1`) is a multiple of `step`.
    private static func monthStarts(in range: ClosedRange<Date>, step: Int, timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.dateComponents([.year, .month], from: range.lowerBound)
        guard let year = start.year, let month = start.month else { return [] }
        var index = ((year * 12 + month - 1) / step) * step
        var result: [Date] = []
        while result.count < limit {
            guard let tick = calendar.date(from: DateComponents(year: index / 12, month: index % 12 + 1, day: 1)) else { break }
            if tick > range.upperBound { break }
            if tick >= range.lowerBound { result.append(tick) }
            index += step
        }
        return result
    }
}
