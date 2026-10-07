import Foundation
import Testing
import TradingChartCore

@Suite("ChartInterval")
struct ChartIntervalTests {
    @Test("Factory methods produce the right number of seconds")
    func factories() {
        #expect(ChartInterval.minutes(1).seconds == 60)
        #expect(ChartInterval.minutes(15).seconds == 900)
        #expect(ChartInterval.hours(4).seconds == 14_400)
        #expect(ChartInterval.days(1).seconds == 86_400)
        #expect(ChartInterval.weeks(1).seconds == 604_800)
        #expect(ChartInterval(seconds: 90).seconds == 90)
    }

    @Test("Intervals compare by length")
    func comparable() {
        #expect(ChartInterval.minutes(5) < .hours(1))
        #expect(ChartInterval.days(1) > .hours(23))
        #expect(ChartInterval.minutes(60) == .hours(1))
        #expect([ChartInterval.days(1), .minutes(1), .hours(1)].sorted() == [.minutes(1), .hours(1), .days(1)])
    }

    @Test("bucketStart floors to the interval since the epoch")
    func bucketStartFloors() {
        // 1_700_000_123 = 2023-11-14 22:15:23 UTC
        let t = date(1_700_000_123)
        #expect(ChartInterval.minutes(1).bucketStart(for: t) == date(1_700_000_100))
        #expect(ChartInterval.minutes(5).bucketStart(for: t) == date(1_700_000_100))
        #expect(ChartInterval.hours(1).bucketStart(for: t) == date(1_699_999_200))
        #expect(ChartInterval.days(1).bucketStart(for: t) == date(1_699_920_000))
    }

    @Test("bucketStart is idempotent and keeps exact bucket starts")
    func bucketStartIdempotent() {
        let interval = ChartInterval.minutes(5)
        let start = date(1_700_000_100)
        #expect(interval.bucketStart(for: start) == start)
        #expect(interval.bucketStart(for: interval.bucketStart(for: date(1_700_000_399))) == start)
        #expect(interval.bucketStart(for: date(1_700_000_399.9)) == start)
        #expect(interval.bucketStart(for: date(1_700_000_400)) == date(1_700_000_400))
    }

    @Test("bucketStart floors dates before the epoch")
    func bucketStartBeforeEpoch() {
        #expect(ChartInterval.minutes(1).bucketStart(for: date(-30)) == date(-60))
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("Weekly buckets start on Monday at midnight UTC unless another day is asked for")
    func weeklyBucketsStartOnMonday() {
        let wednesday = date(1_700_000_123)  // 2023-11-14 22:15:23 UTC, a Tuesday
        let start = ChartInterval.weeks(1).bucketStart(for: wednesday)
        #expect(start == date(1_699_833_600))  // Monday 2023-11-13 00:00 UTC
        #expect(Self.utc.component(.weekday, from: start) == 2)
        #expect(Self.utc.component(.hour, from: start) == 0)

        // Monday to Sunday belong to one bucket; the next Monday opens the next one.
        let monday = date(1_699_833_600)
        for offset in stride(from: 0.0, to: 7 * 86_400, by: 43_200) {
            #expect(ChartInterval.weeks(1).bucketStart(for: monday.addingTimeInterval(offset)) == monday)
        }
        #expect(ChartInterval.weeks(1).bucketStart(for: monday.addingTimeInterval(7 * 86_400)) == monday.addingTimeInterval(604_800))
        #expect(ChartInterval.weeks(1).bucketStart(for: monday.addingTimeInterval(-1)) == monday.addingTimeInterval(-604_800))
    }

    @Test("Any weekday can start the week")
    func weekdayOrigins() {
        let reference = date(1_700_000_123)
        var calendar = Self.utc
        calendar.firstWeekday = 1
        let expected: [ChartInterval.Weekday: Int] = [
            .sunday: 1, .monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6, .saturday: 7,
        ]
        for weekday in ChartInterval.Weekday.allCases {
            let start = ChartInterval.weeks(1, startingOn: weekday).bucketStart(for: reference)
            #expect(calendar.component(.weekday, from: start) == expected[weekday])
            #expect(calendar.component(.hour, from: start) == 0)
            #expect(start <= reference && reference.timeIntervalSince(start) < 604_800)
        }
    }

    @Test("Without an origin a week starts on the epoch's day, a Thursday; days start at midnight UTC")
    func epochGrid() {
        let thursday = ChartInterval(seconds: 604_800).bucketStart(for: date(1_700_000_123))
        #expect(thursday == date(1_699_488_000))
        #expect(Self.utc.component(.weekday, from: thursday) == 5)
        #expect(ChartInterval.weeks(1, startingOn: .thursday) == ChartInterval(seconds: 604_800))

        let day = ChartInterval.days(1).bucketStart(for: date(1_700_000_123))
        #expect(Self.utc.component(.hour, from: day) == 0)
        #expect(Self.utc.component(.minute, from: day) == 0)
    }

    @Test("The origin is a point of the grid: any start of it makes the same interval, and it is part of what the interval is")
    func originIdentity() {
        let monday = ChartInterval.weeks(1)
        #expect(ChartInterval(seconds: 604_800, origin: 345_600) == monday)
        #expect(ChartInterval(seconds: 604_800, origin: 345_600 + 604_800) == monday)
        #expect(ChartInterval(seconds: 604_800, origin: 345_600 - 604_800) == monday)
        #expect(monday != ChartInterval(seconds: 604_800))
        #expect(ChartInterval(seconds: 60, origin: .nan) == .minutes(1))
        // Of one length, the earlier grid comes first.
        #expect(ChartInterval(seconds: 604_800) < monday)
    }

    @Test("A grid with an origin buckets by it")
    func originBuckets() {
        let interval = ChartInterval(seconds: 3_600, origin: 1_800)  // hours that start at :30
        #expect(interval.bucketStart(for: date(7_199)) == date(5_400))
        #expect(interval.bucketStart(for: date(5_400)) == date(5_400))
        #expect(interval.bucketStart(for: date(1_799)) == date(-1_800))
        #expect(interval.bucketStart(for: interval.bucketStart(for: date(1_700_000_123))) == interval.bucketStart(for: date(1_700_000_123)))
    }

    @Test("Codable round trip and validation")
    func codable() throws {
        let original = ChartInterval.minutes(15)
        let decoded = try JSONDecoder().decode(ChartInterval.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartInterval.self, from: Data(#"{"seconds":0}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartInterval.self, from: Data(#"{"seconds":-60}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChartInterval.self, from: Data(#"{"seconds":60,"origin":1e999}"#.utf8))
        }
    }

    @Test("An interval with an origin survives a round trip; one without writes what an earlier version wrote")
    func codableOrigin() throws {
        let monday = ChartInterval.weeks(1)
        let data = try JSONEncoder().encode(monday)
        #expect(try JSONDecoder().decode(ChartInterval.self, from: data) == monday)
        #expect(String(decoding: data, as: UTF8.self).contains("origin"))

        let plain = try JSONEncoder().encode(ChartInterval.minutes(5))
        #expect(!String(decoding: plain, as: UTF8.self).contains("origin"))

        // Data written before the origin existed decodes to the grid it had: the epoch's.
        let old = try JSONDecoder().decode(ChartInterval.self, from: Data(#"{"seconds":300}"#.utf8))
        #expect(old == .minutes(5))
        let oldWeek = try JSONDecoder().decode(ChartInterval.self, from: Data(#"{"seconds":604800}"#.utf8))
        #expect(oldWeek == ChartInterval(seconds: 604_800))
        #expect(oldWeek.origin == 0)
    }
}
