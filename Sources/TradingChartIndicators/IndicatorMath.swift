import Foundation

/// The three aligned series produced by ``IndicatorMath/macd(_:fast:slow:signal:)``.
public struct MACDResult: Sendable, Equatable {
    /// `EMA(fast) - EMA(slow)`. Defined from index `max(fast, slow) - 1`.
    public var macd: [Double?]
    /// `EMA(signal)` of the defined MACD values. Defined from index `max(fast, slow) + signal - 2`.
    public var signal: [Double?]
    /// `macd - signal`. Defined wherever `signal` is.
    public var histogram: [Double?]

    /// Creates a result from three aligned series.
    public init(macd: [Double?], signal: [Double?], histogram: [Double?]) {
        self.macd = macd
        self.signal = signal
        self.histogram = histogram
    }
}

/// Pure math behind the built-in indicators, over plain `[Double]` series.
///
/// Every function returns an array of the same length as its input, aligned by index. Entries inside the warm-up
/// period are `nil`, so a series shorter than the period yields only `nil`s (and an empty input an empty array).
/// Inputs are expected to be finite; `NaN` and infinities propagate into the output.
/// Every `period` must be at least 1 (a `precondition`).
public enum IndicatorMath {
    /// Simple moving average: the arithmetic mean of the last `period` values.
    ///
    /// Defined from index `period - 1`. Computed with a running sum, so it is O(n).
    public static func sma(_ values: [Double], period: Int) -> [Double?] {
        precondition(period >= 1, "period must be at least 1")
        var result = [Double?](repeating: nil, count: values.count)
        guard values.count >= period else { return result }

        var sum = 0.0
        for index in values.indices {
            sum += values[index]
            if index >= period { sum -= values[index - period] }
            if index >= period - 1 { result[index] = sum / Double(period) }
        }
        return result
    }

    /// Exponential moving average with the TA-Lib convention: the first value is the SMA of the first `period`
    /// values (at index `period - 1`), then `ema = k * value + (1 - k) * previous` with `k = 2 / (period + 1)`.
    ///
    /// Defined from index `period - 1`. With `period == 1` it reproduces the input.
    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        precondition(period >= 1, "period must be at least 1")
        var result = [Double?](repeating: nil, count: values.count)
        guard values.count >= period else { return result }

        let k = 2 / Double(period + 1)
        var previous = values[..<period].reduce(0, +) / Double(period)
        result[period - 1] = previous
        for index in period..<values.count {
            previous = k * values[index] + (1 - k) * previous
            result[index] = previous
        }
        return result
    }

    /// Linearly weighted moving average: weights `1...period`, the newest value weighing `period`, divided by
    /// `period * (period + 1) / 2`.
    ///
    /// Defined from index `period - 1`. O(n * period).
    public static func wma(_ values: [Double], period: Int) -> [Double?] {
        precondition(period >= 1, "period must be at least 1")
        var result = [Double?](repeating: nil, count: values.count)
        guard values.count >= period else { return result }

        let divisor = Double(period * (period + 1)) / 2
        for index in (period - 1)..<values.count {
            let start = index - period + 1
            var weighted = 0.0
            for offset in 0..<period {
                weighted += Double(offset + 1) * values[start + offset]
            }
            result[index] = weighted / divisor
        }
        return result
    }

    /// Rolling population standard deviation (divisor `period`, not `period - 1`) of the last `period` values.
    ///
    /// Computed in two passes per window (mean, then squared deviations), which stays accurate for large prices.
    /// Defined from index `period - 1`; with `period == 1` it is `0`. O(n * period).
    public static func populationStdDev(_ values: [Double], period: Int) -> [Double?] {
        precondition(period >= 1, "period must be at least 1")
        var result = [Double?](repeating: nil, count: values.count)
        guard values.count >= period else { return result }

        let count = Double(period)
        for index in (period - 1)..<values.count {
            let window = values[(index - period + 1)...index]
            let mean = window.reduce(0, +) / count
            let squares = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            result[index] = (squares / count).squareRoot()
        }
        return result
    }

    /// Relative Strength Index with Wilder smoothing.
    ///
    /// The first average gain and loss are the plain means of the first `period` bar-to-bar changes; afterwards
    /// `avg = (previousAvg * (period - 1) + current) / period`. The index is `100 * avgGain / (avgGain + avgLoss)`,
    /// i.e. `100 - 100 / (1 + avgGain / avgLoss)`.
    ///
    /// Defined from index `period` (it needs `period + 1` values). Flat-market convention: when `avgLoss == 0` the
    /// RSI is `100`; when both averages are `0` (no movement at all) it is `50`.
    public static func rsi(_ values: [Double], period: Int) -> [Double?] {
        precondition(period >= 1, "period must be at least 1")
        var result = [Double?](repeating: nil, count: values.count)
        guard values.count > period else { return result }

        let count = Double(period)
        var averageGain = 0.0
        var averageLoss = 0.0
        for index in 1...period {
            let change = values[index] - values[index - 1]
            averageGain += max(change, 0)
            averageLoss += max(-change, 0)
        }
        averageGain /= count
        averageLoss /= count
        result[period] = relativeStrengthIndex(gain: averageGain, loss: averageLoss)

        for index in (period + 1)..<values.count {
            let change = values[index] - values[index - 1]
            averageGain = (averageGain * (count - 1) + max(change, 0)) / count
            averageLoss = (averageLoss * (count - 1) + max(-change, 0)) / count
            result[index] = relativeStrengthIndex(gain: averageGain, loss: averageLoss)
        }
        return result
    }

    /// Moving Average Convergence Divergence.
    ///
    /// `macd = EMA(fast) - EMA(slow)`, where each EMA is seeded independently by ``ema(_:period:)`` (as charting
    /// platforms such as TradingView do; TA-Lib's own `MACD` seeds the fast EMA later, so its first values differ and
    /// converge after warm-up). `signal = EMA(signal period)` of the defined MACD values, `histogram = macd - signal`.
    /// `fast` is not required to be smaller than `slow`.
    public static func macd(_ values: [Double], fast: Int, slow: Int, signal: Int) -> MACDResult {
        precondition(fast >= 1 && slow >= 1 && signal >= 1, "periods must be at least 1")
        let count = values.count
        var macdLine = [Double?](repeating: nil, count: count)
        var signalLine = [Double?](repeating: nil, count: count)
        var histogram = [Double?](repeating: nil, count: count)

        let fastEMA = ema(values, period: fast)
        let slowEMA = ema(values, period: slow)
        for index in values.indices {
            if let fastValue = fastEMA[index], let slowValue = slowEMA[index] {
                macdLine[index] = fastValue - slowValue
            }
        }

        // The MACD line is defined from one index onwards, so the signal EMA runs over that dense tail.
        guard let firstDefined = macdLine.firstIndex(where: { $0 != nil }) else {
            return MACDResult(macd: macdLine, signal: signalLine, histogram: histogram)
        }
        let dense = macdLine[firstDefined...].compactMap { $0 }
        let denseSignal = ema(dense, period: signal)
        for (offset, value) in denseSignal.enumerated() {
            guard let value, let macdValue = macdLine[firstDefined + offset] else { continue }
            signalLine[firstDefined + offset] = value
            histogram[firstDefined + offset] = macdValue - value
        }
        return MACDResult(macd: macdLine, signal: signalLine, histogram: histogram)
    }

    private static func relativeStrengthIndex(gain: Double, loss: Double) -> Double {
        let total = gain + loss
        return total == 0 ? 50 : 100 * gain / total
    }
}
