import Foundation

/// A single OHLC bar.
public struct Candle: Hashable, Sendable, Codable, Identifiable {
    /// Start of the bucket this candle covers.
    public var time: Date
    /// Opening price.
    public var open: Double
    /// Highest price of the bucket.
    public var high: Double
    /// Lowest price of the bucket.
    public var low: Double
    /// Closing price (the last known price for a live bucket).
    public var close: Double
    /// Traded volume, if known.
    public var volume: Double?

    /// Identity of a candle is its bucket start.
    public var id: Date { time }

    /// `true` when the candle closed at or above its open.
    public var isBullish: Bool { close >= open }

    /// Creates a candle from `Double` prices.
    public init(
        time: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double? = nil
    ) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    /// Creates a candle from `Decimal` prices (converted to `Double`).
    public init(
        time: Date,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        volume: Decimal? = nil
    ) {
        self.init(
            time: time,
            open: open.doubleValue,
            high: high.doubleValue,
            low: low.doubleValue,
            close: close.doubleValue,
            volume: volume?.doubleValue
        )
    }
}

/// A single price sample of a line or area series.
public struct PricePoint: Hashable, Sendable, Codable, Identifiable {
    /// Time of the sample.
    public var time: Date
    /// Price at `time`.
    public var value: Double

    /// Identity of a point is its time.
    public var id: Date { time }

    /// Creates a point from a `Double` price.
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }

    /// Creates a point from a `Decimal` price (converted to `Double`).
    public init(time: Date, value: Decimal) {
        self.init(time: time, value: value.doubleValue)
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
