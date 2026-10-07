import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

/// The time domain of the charts: its left end is held back, so that history that is prepended and a head that is trimmed do
/// not move it (a domain that moves makes the charts blank for a frame; see `TradingChartModel+Domain.swift`).
@MainActor
@Suite("Chart domain")
struct ChartDomainTests {
    private static let minute: TimeInterval = 60

    private func makeModel(
        count: Int = 600,
        reserve: Int = 1_000,
        configure: (inout TradingChartConfiguration) -> Void = { _ in }
    ) -> TradingChartModel {
        var configuration = TradingChartConfiguration()
        configuration.historyReserveBars = reserve
        configure(&configuration)
        let series = makeSeries(count: count, lastStart: baseTime + Double(count - 1) * Self.minute)
        return TradingChartModel(series: series, style: .candles, configuration: configuration)
    }

    private func natural(_ model: TradingChartModel) -> ClosedRange<Date> {
        model.naturalXDomain
    }

    private func page(_ count: Int, before time: Date) -> ChartSeries {
        makeSeries(count: count, lastStart: time.timeIntervalSince1970 - Self.minute)
    }

    @Test("with more history to load the domain starts a reserve of bars before the first bar")
    func reserve() {
        let model = makeModel()
        #expect(model.chartXDomain.lowerBound == natural(model).lowerBound.addingTimeInterval(-1_000 * Self.minute))
        #expect(model.chartXDomain.upperBound == natural(model).upperBound)
        // The scroll range does not include it.
        #expect(model.touchScrollRange.lowerBound == natural(model).lowerBound)
    }

    @Test("a source with nothing more to load needs no reserve")
    func noReserve() {
        let model = makeModel(count: 10)
        model.hasMoreHistory = false
        model.setSeries(makeSeries(count: 600, lastStart: baseTime + 599 * Self.minute))
        #expect(model.chartXDomain == natural(model))
    }

    @Test("the reserve is not taken away mid-session when the source runs out")
    func reserveStaysWhenHistoryEnds() {
        let model = makeModel()
        let start = model.chartXDomain.lowerBound
        model.hasMoreHistory = false
        #expect(model.chartXDomain.lowerBound == start)
        model.prependHistory(page(300, before: model.series.firstTime!))
        #expect(model.chartXDomain.lowerBound == start)
    }

    @Test("history prepended inside the reserve does not move the domain, the scroll nudge, or the window")
    func prependInsideTheReserve() {
        let model = makeModel()
        let start = model.chartXDomain.lowerBound
        let nudge = model.scrollNudge
        let position = model.scrollPosition

        model.prependHistory(page(300, before: model.series.firstTime!))
        model.prependHistory(page(300, before: model.series.firstTime!))

        #expect(model.series.count == 1_200)
        #expect(model.chartXDomain.lowerBound == start)
        #expect(model.scrollNudge == nudge)
        #expect(model.scrollPosition == position)
        // What can be scrolled to does grow.
        #expect(model.touchScrollRange.lowerBound == natural(model).lowerBound)
    }

    @Test("history prepended beyond the reserve extends the domain by another reserve, once, and flips the nudge")
    func prependBeyondTheReserve() {
        let model = makeModel(reserve: 100)
        let start = model.chartXDomain.lowerBound
        let nudge = model.scrollNudge

        model.prependHistory(page(300, before: model.series.firstTime!))

        #expect(model.chartXDomain.lowerBound == natural(model).lowerBound.addingTimeInterval(-100 * Self.minute))
        #expect(model.chartXDomain.lowerBound < start)
        #expect(model.scrollNudge != nudge)
        // Another page that fits in the new reserve changes nothing.
        let extended = model.chartXDomain.lowerBound
        model.prependHistory(page(50, before: model.series.firstTime!))
        #expect(model.chartXDomain.lowerBound == extended)
    }

    @Test("history beyond the reserve that arrives while the window moves extends the domain when the window stops")
    func expansionWaitsForRest() {
        let model = makeModel(reserve: 100)
        let clock = ManualClock()
        model.scrollClock = clock.scrollClock
        let start = model.chartXDomain.lowerBound
        let nudge = model.scrollNudge
        model.scrollPosition = model.scrollPosition.addingTimeInterval(-300)  // a scroll step: the window is moving
        clock.advance(by: 0.02)

        model.prependHistory(page(300, before: model.series.firstTime!))

        // Not yet: the charts keep their domain, and the bars that are not in it cannot be scrolled to.
        #expect(model.chartXDomain.lowerBound == start)
        #expect(model.scrollNudge == nudge)
        #expect(model.touchScrollRange.lowerBound == start)

        clock.advance(by: 0.3)  // the window stood still for the settle delay

        #expect(model.chartXDomain.lowerBound == natural(model).lowerBound.addingTimeInterval(-100 * Self.minute))
        #expect(model.scrollNudge != nudge)
        #expect(model.touchScrollRange.lowerBound == natural(model).lowerBound)
    }

    @Test("trimming the head of the series by a live update does not move the domain")
    func trimKeepsTheDomain() {
        let model = makeModel()
        let start = model.chartXDomain.lowerBound
        let nudge = model.scrollNudge

        // 600 bars with `maxLiveBarCount` 600: a new bar drops the oldest.
        for _ in 1...5 {
            model.update(price: 500, at: model.series.lastTime!.addingTimeInterval(Self.minute))
        }

        #expect(model.series.count == 600)
        #expect(model.chartXDomain.lowerBound == start)
        #expect(model.scrollNudge == nudge)
        // The oldest bars that are gone cannot be scrolled to.
        #expect(model.touchScrollRange.lowerBound == natural(model).lowerBound)
        #expect(model.touchScrollRange.lowerBound > start)
    }

    @Test("a new series, and a new style, choose the left end anew")
    func resets() {
        let model = makeModel(reserve: 100)
        let nudge = model.scrollNudge

        let shorter = makeSeries(count: 50, lastStart: baseTime + 599 * Self.minute)
        model.setSeries(shorter)
        #expect(model.chartXDomain.lowerBound == natural(model).lowerBound.addingTimeInterval(-100 * Self.minute))
        #expect(model.scrollNudge != nudge)  // the left end moved

        let nudgeNow = model.scrollNudge
        model.style = .line
        // Candles keep a bar of room before the first bar, a line does not: the natural start moved by one bar.
        #expect(model.chartXDomain.lowerBound == natural(model).lowerBound.addingTimeInterval(-100 * Self.minute))
        #expect(model.scrollNudge != nudgeNow)
    }

    @Test("the pane charts take the same domain for the series they are built from")
    func domainForASeries() {
        let model = makeModel()
        let older = page(300, before: model.series.firstTime!)
        #expect(model.chartXDomain(for: model.series) == model.chartXDomain)
        // A series that starts earlier than the reserve reaches gets the earlier start for its own domain.
        let long = makeSeries(count: 3_000, lastStart: baseTime + 599 * Self.minute)
        #expect(model.chartXDomain(for: long).lowerBound <= model.chartXDomain.lowerBound)
        #expect(older.count == 300)
    }
}
