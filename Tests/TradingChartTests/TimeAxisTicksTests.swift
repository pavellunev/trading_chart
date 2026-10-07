import Foundation
import Testing
@testable import TradingChart

@Suite("Time axis ticks")
struct TimeAxisTicksTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let minute = ChartInterval.minutes(1)

    private func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func range(from start: TimeInterval, length: TimeInterval) -> ClosedRange<Date> {
        date(start)...date(start + length)
    }

    // MARK: - Step

    @Test("the step puts about the desired number of ticks into the window")
    func stepFollowsWindow() {
        // 40 one-minute bars: a tick every 10 minutes.
        #expect(TimeAxisTicks.step(visibleDuration: 2_400, interval: minute, desiredCount: 4) == .seconds(600))
        // zoomed in to 10 bars: 150 seconds would do, the next round step is 5 minutes
        #expect(TimeAxisTicks.step(visibleDuration: 600, interval: minute, desiredCount: 4) == .seconds(300))
        // 400 bars
        #expect(TimeAxisTicks.step(visibleDuration: 24_000, interval: minute, desiredCount: 4) == .seconds(7_200))
        // seconds bars
        #expect(TimeAxisTicks.step(visibleDuration: 40, interval: ChartInterval(seconds: 1), desiredCount: 4) == .seconds(10))
    }

    @Test("bars of an hour or more get day labels, so a tick is at least a day apart")
    func stepFloorForDayLabels() {
        let hour = ChartInterval.hours(1)
        // 40 hourly bars: 10 hours would do
        #expect(TimeAxisTicks.step(visibleDuration: 40 * 3_600, interval: hour, desiredCount: 4) == .days(1))
        // 40 four-hour bars: 160 hours, a tick every two days
        #expect(TimeAxisTicks.step(visibleDuration: 40 * 14_400, interval: .hours(4), desiredCount: 4) == .days(2))
        // 40 daily bars
        #expect(TimeAxisTicks.step(visibleDuration: 40 * 86_400, interval: .days(1), desiredCount: 5) == .days(14))
    }

    @Test("bars of a week or more get month labels, so a tick is at least a month apart")
    func stepFloorForMonthLabels() {
        let week = ChartInterval.weeks(1)
        #expect(TimeAxisTicks.step(visibleDuration: 10 * 604_800, interval: week, desiredCount: 4) == .months(1))
        #expect(TimeAxisTicks.step(visibleDuration: 40 * 604_800, interval: week, desiredCount: 4) == .months(3))
    }

    @Test("a very wide window takes the largest step")
    func stepUpperBound() {
        #expect(TimeAxisTicks.step(visibleDuration: 1e12, interval: minute, desiredCount: 4) == .months(60))
    }

    // MARK: - Values

    @Test("ticks are round times of the local clock, ascending, inside the range")
    func alignment() {
        let ticks = TimeAxisTicks.values(
            in: range(from: baseTime, length: 7_200),
            visibleDuration: 2_400,
            interval: minute,
            desiredCount: 4,
            timeZone: utc
        )

        #expect(!ticks.isEmpty)
        #expect(ticks.allSatisfy { $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 600) == 0 })
        #expect(ticks == ticks.sorted())
        #expect(ticks.first! >= date(baseTime) && ticks.last! <= date(baseTime + 7_200))
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 600 })
    }

    @Test("the grid does not move while the window scrolls")
    func gridIsStable() {
        let first = TimeAxisTicks.values(
            in: range(from: baseTime, length: 7_200),
            visibleDuration: 2_400,
            interval: minute,
            desiredCount: 4,
            timeZone: utc
        )
        let second = TimeAxisTicks.values(
            in: range(from: baseTime + 1_337, length: 7_200),
            visibleDuration: 2_400,
            interval: minute,
            desiredCount: 4,
            timeZone: utc
        )

        let common = Set(first).intersection(second)
        #expect(common.count > 5)
        #expect(Set(second.filter { $0 <= first.last! && $0 >= first.first! }) == common)
    }

    @Test("the number of ticks follows the window, not the series")
    func countIsBounded() {
        // three windows of 40 bars: the render window of the chart
        let ticks = TimeAxisTicks.values(
            in: range(from: baseTime, length: 3 * 2_400),
            visibleDuration: 2_400,
            interval: minute,
            desiredCount: 4,
            timeZone: utc
        )
        #expect(ticks.count >= 10 && ticks.count <= 14)
    }

    @Test("the bounds of the range are included when they are on the grid")
    func boundsIncluded() {
        let start = 1_700_000_400.0  // a multiple of 600
        let ticks = TimeAxisTicks.values(
            in: range(from: start, length: 1_200),
            visibleDuration: 2_400,
            interval: minute,
            desiredCount: 4,
            timeZone: utc
        )
        #expect(ticks == [date(start), date(start + 600), date(start + 1_200)])
    }

    @Test("hours are aligned to the local clock, also in a time zone with a half hour offset")
    func localHours() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let ticks = TimeAxisTicks.values(
            in: range(from: baseTime, length: 4 * 86_400 / 4),
            visibleDuration: 86_400 / 3,
            interval: minute,
            desiredCount: 4,
            timeZone: kolkata
        )
        let local = calendar(kolkata)

        #expect(ticks.count >= 4)
        #expect(ticks.allSatisfy { local.component(.minute, from: $0) == 0 && local.component(.second, from: $0) == 0 })
    }

    @Test("day ticks are local midnights, a fixed number of days apart")
    func localDays() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let ticks = TimeAxisTicks.values(
            in: range(from: 1_700_000_000, length: 30 * 86_400),
            visibleDuration: 40 * 14_400,
            interval: .hours(4),
            desiredCount: 4,
            timeZone: newYork
        )
        let local = calendar(newYork)

        #expect(ticks.count >= 14)
        #expect(ticks.allSatisfy { local.component(.hour, from: $0) == 0 && local.component(.minute, from: $0) == 0 })
        let days = zip(ticks, ticks.dropFirst()).map { local.dateComponents([.day], from: $0, to: $1).day }
        #expect(days.allSatisfy { $0 == 2 })
    }

    @Test("month ticks are the first days of months on a fixed grid of months")
    func monthStarts() {
        let ticks = TimeAxisTicks.values(
            in: range(from: 1_700_000_000, length: 3 * 365 * 86_400),
            visibleDuration: 40 * 604_800,
            interval: .weeks(1),
            desiredCount: 4,
            timeZone: utc
        )
        let local = calendar(utc)

        #expect(ticks.count >= 10)
        #expect(ticks.allSatisfy { local.component(.day, from: $0) == 1 && local.component(.hour, from: $0) == 0 })
        #expect(ticks.allSatisfy { (local.component(.month, from: $0) - 1) % 3 == 0 })
    }

    @Test("degenerate windows give no ticks, and the count is capped")
    func degenerate() {
        #expect(TimeAxisTicks.values(in: range(from: baseTime, length: 100), visibleDuration: 0, interval: minute, desiredCount: 4).isEmpty)
        #expect(TimeAxisTicks.values(in: range(from: baseTime, length: 100), visibleDuration: .nan, interval: minute, desiredCount: 4).isEmpty)

        let crowded = TimeAxisTicks.values(
            in: range(from: baseTime, length: 86_400),
            visibleDuration: 4,
            interval: ChartInterval(seconds: 1),
            desiredCount: 4,
            timeZone: utc
        )
        #expect(crowded.count == 256)
    }
}
