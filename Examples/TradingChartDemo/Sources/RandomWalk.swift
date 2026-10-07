import Foundation
import TradingChart

/// A small deterministic generator (SplitMix64), so every launch draws the same history.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A standard normal sample (Box-Muller).
    mutating func gaussian() -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &self)
        let u2 = Double.random(in: 0..<1, using: &self)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Generates candles by walking backwards from the newest close, so older pages continue exactly where
/// the loaded history starts.
enum RandomWalk {
    /// A BTC-scale price: six digits, so the badge and the axis labels are as wide as they get.
    static let basePrice = 121_345.67

    /// `count` candles ending at `lastBucketStart` whose last close is `lastClose`.
    static func candles(
        count: Int,
        interval: ChartInterval,
        lastBucketStart: Date,
        lastClose: Double,
        seed: UInt64
    ) -> [Candle] {
        var generator = SeededGenerator(seed: seed)
        // Per-bar volatility grows with the square root of the bar length.
        let volatility = 0.0012 * (interval.seconds / 60).squareRoot()
        var close = lastClose
        var candles: [Candle] = []
        candles.reserveCapacity(count)

        for index in 0..<count {
            let time = lastBucketStart.addingTimeInterval(-Double(index) * interval.seconds)
            // Every 30th-ish candle is a doji.
            let step = Double.random(in: 0..<1, using: &generator) < 0.03 ? 0 : generator.gaussian() * volatility
            let open = close / (1 + step)
            let top = max(open, close)
            let bottom = min(open, close)
            let high = top * (1 + abs(generator.gaussian()) * volatility * 0.5)
            let low = bottom * (1 - abs(generator.gaussian()) * volatility * 0.5)
            // Thousands of units per bar, so the compact legend shows K.
            let volume = (20 + abs(generator.gaussian()) * 15 * (1 + abs(step) / volatility)) * 40
            candles.append(Candle(time: time, open: open, high: high, low: low, close: close, volume: volume))
            close = open
        }
        return candles.reversed()
    }
}
