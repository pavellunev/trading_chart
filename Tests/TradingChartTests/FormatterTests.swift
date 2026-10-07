import Foundation
import Testing
@testable import TradingChart

@Suite("PriceFormatter")
struct PriceFormatterTests {
    private let locale = Locale(identifier: "en_US")

    private func automatic(_ value: Double, _ context: PriceFormatter.Context = .badge) -> String {
        PriceFormatter.automaticString(value, context: context, locale: locale)
    }

    @Test("100 and above get two decimals")
    func largePrices() {
        #expect(automatic(67_123.456) == "67,123.46")
        #expect(automatic(1_000) == "1,000.00")
        #expect(automatic(123.4) == "123.40")
        #expect(automatic(-2_500.5) == "-2,500.50")
    }

    @Test("prices between 1 and 100 get 3 or 4 decimals by magnitude")
    func mediumPrices() {
        #expect(automatic(12.345_67) == "12.346")
        #expect(automatic(99.9) == "99.900")
        #expect(automatic(1.234_56) == "1.2346")
        #expect(automatic(1) == "1.0000")
    }

    @Test("prices below 1 get four significant digits")
    func smallPrices() {
        #expect(automatic(0.123_456) == "0.1235")
        #expect(automatic(0.012_345_6) == "0.01235")
        #expect(automatic(0.000_123_456) == "0.0001235")
        #expect(automatic(-0.5) == "-0.5000")
    }

    @Test("zero and non-finite values do not crash")
    func degenerateValues() {
        #expect(automatic(0) == "0")
        #expect(!automatic(.nan).isEmpty)
        #expect(!automatic(.infinity).isEmpty)
    }

    @Test("axis labels drop trailing zeros, other contexts keep the precision")
    func axisTrimsTrailingZeros() {
        #expect(automatic(123.4, .axis) == "123.4")
        #expect(automatic(1_000, .axis) == "1,000")
        #expect(automatic(0.5, .axis) == "0.5")
        #expect(automatic(123.4, .crosshair) == "123.40")
        #expect(automatic(123.4, .legend) == "123.40")
        #expect(automatic(123.4, .badge) == "123.40")
    }

    @Test("the compact context abbreviates thousands, millions, billions and trillions")
    func compactAbbreviations() {
        #expect(automatic(1_150, .compact) == "1.15K")
        #expect(automatic(99_200_000, .compact) == "99.2M")
        #expect(automatic(3_740, .compact) == "3.74K")
        #expect(automatic(2_500_000_000, .compact) == "2.5B")
        #expect(automatic(1_234_000_000_000, .compact) == "1.23T")
        #expect(automatic(-1_150, .compact) == "-1.15K")
    }

    @Test("the compact context keeps up to two decimals below one thousand, without trailing zeros")
    func compactSmallValues() {
        #expect(automatic(45.5, .compact) == "45.5")
        #expect(automatic(63.515_2, .compact) == "63.52")
        #expect(automatic(432.95, .compact) == "432.95")
        #expect(automatic(-6.482_8, .compact) == "-6.48")
        #expect(automatic(213, .compact) == "213")
        #expect(automatic(999.994, .compact) == "999.99")
    }

    @Test("the compact context keeps four significant digits below one")
    func compactFractions() {
        #expect(automatic(0.123_456, .compact) == "0.1235")
        #expect(automatic(0.000_123_456, .compact) == "0.0001235")
        #expect(automatic(0, .compact) == "0")
    }

    @Test("a value that rounds up to a thousand moves to the next suffix")
    func compactRounding() {
        #expect(automatic(999_999, .compact) == "1M")
        #expect(automatic(999_994, .compact) == "999.99K")
    }

    @Test("fractionDigits uses the same number of decimals everywhere")
    func fixedDigits() {
        let formatter = PriceFormatter.fractionDigits(3)
        let axis = formatter.format(12, context: .axis)
        let badge = formatter.format(12, context: .badge)

        #expect(axis == badge)
        #expect(axis.hasSuffix("12.000") || axis.hasSuffix("12,000"))
        #expect(PriceFormatter.fixedString(1.5, fractionDigits: 0, trimsTrailingZeros: false, locale: locale) == "2")
    }

    @Test("custom formatters receive the context")
    func customFormatter() {
        let contextual = PriceFormatter { value, context in
            context == .axis ? "a\(Int(value))" : "b\(Int(value))"
        }
        let plain = PriceFormatter { value in "p\(Int(value))" }

        #expect(contextual.format(5, context: .axis) == "a5")
        #expect(contextual.format(5, context: .badge) == "b5")
        #expect(plain.format(5, context: .axis) == "p5")
        #expect(plain.format(5, context: .legend) == "p5")
    }
}

@Suite("TimeFormatter")
struct TimeFormatterTests {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!
    // 2023-11-14 22:14:00 UTC
    private let time = Date(timeIntervalSince1970: 1_700_000_040)

    private func automatic(_ interval: ChartInterval, _ context: TimeFormatter.Context) -> String {
        TimeFormatter.automaticString(time, interval: interval, context: context, locale: locale, timeZone: utc)
    }

    @Test("intervals below one hour show hours and minutes")
    func minuteIntervals() {
        #expect(automatic(.minutes(1), .axis) == "22:14")
        #expect(automatic(.minutes(30), .axis) == "22:14")
    }

    @Test("intervals from one hour up to a week show day and month")
    func hourAndDayIntervals() {
        #expect(automatic(.hours(1), .axis) == "Nov 14")
        #expect(automatic(.hours(4), .axis) == "Nov 14")
        #expect(automatic(.days(1), .axis) == "Nov 14")
    }

    @Test("weekly intervals show month and year")
    func weeklyIntervals() {
        #expect(automatic(.weeks(1), .axis) == "Nov 23")
    }

    @Test("the crosshair shows day, month and time for every interval")
    func crosshair() {
        #expect(automatic(.minutes(5), .crosshair) == "Nov 14 22:14")
        #expect(automatic(.days(1), .crosshair) == "Nov 14 22:14")
    }

    @Test("a custom formatter receives time, interval and context")
    func customFormatter() {
        let formatter = TimeFormatter { date, interval, context in
            "\(Int(date.timeIntervalSince1970)) \(Int(interval.seconds)) \(context == .axis ? "axis" : "crosshair")"
        }

        #expect(formatter.format(time, interval: .minutes(1), context: .axis) == "1700000040 60 axis")
        #expect(formatter.format(time, interval: .hours(1), context: .crosshair) == "1700000040 3600 crosshair")
    }
}
