import Foundation

/// The duration of one bar (bucket) of a series, and where the grid of buckets starts.
///
/// Buckets are `seconds` long and start at `origin + k * seconds` seconds after the Unix epoch (UTC), so they are not tied to a
/// calendar or a time zone. With the default origin of `0` an interval of a day starts at midnight UTC. A week does not: the
/// epoch was a Thursday, so `ChartInterval(seconds: 604_800)` has weeks that start on Thursdays. ``weeks(_:startingOn:)`` puts
/// the grid on the day an exchange starts its week (Monday by default).
///
/// Months are not supported in this version: they are not a fixed number of seconds.
public struct ChartInterval: Hashable, Comparable, Sendable, Codable {
    /// Bucket length in seconds. Always greater than zero.
    public let seconds: TimeInterval
    /// Where the grid of buckets starts, in seconds after the Unix epoch, reduced to `0..<seconds`. Two intervals with the
    /// same `seconds` and a different `origin` are different intervals: a bar of one does not belong to the other.
    public let origin: TimeInterval

    /// A day of the week.
    public enum Weekday: Int, Sendable, Hashable, CaseIterable {
        case sunday = 0, monday, tuesday, wednesday, thursday, friday, saturday

        /// Days between the Unix epoch (a Thursday) and the first time this day began after it.
        fileprivate var daysFromEpoch: Int {
            (rawValue - Weekday.thursday.rawValue + 7) % 7
        }
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, origin
    }

    /// Creates an interval of the given length.
    ///
    /// - Parameters:
    ///   - seconds: The length of a bucket.
    ///   - origin: A moment, in seconds after the Unix epoch, at which a bucket starts. Any moment of the grid will do; the
    ///     default is the epoch itself. A value that is not finite is taken as `0`.
    /// - Precondition: `seconds > 0`.
    public init(seconds: TimeInterval, origin: TimeInterval = 0) {
        precondition(seconds > 0, "ChartInterval.seconds must be greater than zero")
        self.seconds = seconds
        self.origin = Self.reduced(origin, by: seconds)
    }

    /// Decodes an interval, rejecting non-positive or non-finite lengths. A missing `origin` is `0`, so what an earlier version
    /// wrote (`{"seconds":60}`) decodes to the same interval it was.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let seconds = try container.decode(TimeInterval.self, forKey: .seconds)
        guard seconds > 0, seconds.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .seconds,
                in: container,
                debugDescription: "ChartInterval.seconds must be a positive finite number"
            )
        }
        let origin = try container.decodeIfPresent(TimeInterval.self, forKey: .origin) ?? 0
        guard origin.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .origin,
                in: container,
                debugDescription: "ChartInterval.origin must be a finite number"
            )
        }
        self.seconds = seconds
        self.origin = Self.reduced(origin, by: seconds)
    }

    /// Encodes the length, and the origin when it is not `0`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seconds, forKey: .seconds)
        if origin != 0 { try container.encode(origin, forKey: .origin) }
    }

    /// An interval of `count` minutes. `count` must be positive.
    public static func minutes(_ count: Int) -> ChartInterval {
        ChartInterval(seconds: TimeInterval(count) * 60)
    }

    /// An interval of `count` hours. `count` must be positive.
    public static func hours(_ count: Int) -> ChartInterval {
        ChartInterval(seconds: TimeInterval(count) * 3_600)
    }

    /// An interval of `count` days (24 hours each), starting at midnight UTC. `count` must be positive.
    public static func days(_ count: Int) -> ChartInterval {
        ChartInterval(seconds: TimeInterval(count) * 86_400)
    }

    /// An interval of `count` weeks (7 days each), starting at midnight UTC on `weekday`. `count` must be positive.
    ///
    /// - Parameters:
    ///   - count: The number of weeks in a bar.
    ///   - weekday: The day a week starts on; Monday by default. Use the day the data source starts its weeks on, or live
    ///     ticks of the other days fall into buckets the source's candles do not have.
    public static func weeks(_ count: Int, startingOn weekday: Weekday = .monday) -> ChartInterval {
        ChartInterval(seconds: TimeInterval(count) * 604_800, origin: TimeInterval(weekday.daysFromEpoch) * 86_400)
    }

    /// The start of the bucket that contains `date`.
    ///
    /// Computed as `floor((t - origin) / seconds) * seconds + origin` where `t` is the number of seconds since the Unix epoch
    /// (UTC), so buckets are not tied to any calendar or time zone.
    public func bucketStart(for date: Date) -> Date {
        let t = date.timeIntervalSince1970 - origin
        return Date(timeIntervalSince1970: (t / seconds).rounded(.down) * seconds + origin)
    }

    /// Orders intervals by their length, and those of one length by where their grid starts.
    public static func < (lhs: ChartInterval, rhs: ChartInterval) -> Bool {
        lhs.seconds != rhs.seconds ? lhs.seconds < rhs.seconds : lhs.origin < rhs.origin
    }

    /// `origin` brought into `0..<seconds`, so that every start of the same grid is the same interval.
    private static func reduced(_ origin: TimeInterval, by seconds: TimeInterval) -> TimeInterval {
        guard origin.isFinite else { return 0 }
        let remainder = origin.truncatingRemainder(dividingBy: seconds)
        return remainder < 0 ? remainder + seconds : remainder
    }
}
