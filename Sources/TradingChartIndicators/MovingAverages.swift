import Foundation
import TradingChartCore

/// Simple moving average, drawn over the price chart.
///
/// `sma[i]` is the mean of the last `period` values of `source`; the first `period - 1` bars have no value and are not
/// part of the output. A series shorter than `period` yields a line with no values.
public struct SMA: ChartIndicator {
    /// Number of bars averaged. At least 1.
    public let period: Int
    /// The price the average is computed from.
    public let source: PriceSource
    /// Line style. A `nil` color takes the next color from the theme palette.
    public let style: IndicatorLineStyle

    /// Creates an SMA. Traps if `period < 1`.
    public init(period: Int = 20, source: PriceSource = .close, style: IndicatorLineStyle = IndicatorLineStyle()) {
        precondition(period >= 1, "SMA period must be at least 1")
        self.period = period
        self.source = source
        self.style = style
    }

    /// `"sma(<period>,<source>)"`, e.g. `"sma(20,close)"`.
    public var id: String { "sma(\(period),\(source.rawValue))" }
    /// `"SMA <period>"`, e.g. `"SMA 20"`; a non-close source is appended (`"SMA 20 hl2"`).
    public var displayName: String { "SMA \(period)\(sourceSuffix(source))" }
    /// `"MA"`.
    public var shortName: String { "MA" }
    /// Always `IndicatorPlacement.overlay`.
    public var placement: IndicatorPlacement { .overlay }

    /// Computes the average over `input.values(source)`; see ``IndicatorMath/sma(_:period:)``.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        movingAverageOutput(
            id: id,
            name: displayName,
            style: style,
            aligned: IndicatorMath.sma(input.values(source), period: period),
            times: input.candles.map(\.time)
        )
    }
}

/// Exponential moving average, drawn over the price chart.
///
/// Seeded with the SMA of the first `period` values (TA-Lib convention), then `k * value + (1 - k) * previous` with
/// `k = 2 / (period + 1)`. Bars before the seed have no value and are not part of the output.
public struct EMA: ChartIndicator {
    /// Smoothing period. At least 1.
    public let period: Int
    /// The price the average is computed from.
    public let source: PriceSource
    /// Line style. A `nil` color takes the next color from the theme palette.
    public let style: IndicatorLineStyle

    /// Creates an EMA. Traps if `period < 1`.
    public init(period: Int = 20, source: PriceSource = .close, style: IndicatorLineStyle = IndicatorLineStyle()) {
        precondition(period >= 1, "EMA period must be at least 1")
        self.period = period
        self.source = source
        self.style = style
    }

    /// `"ema(<period>,<source>)"`, e.g. `"ema(20,close)"`.
    public var id: String { "ema(\(period),\(source.rawValue))" }
    /// `"EMA <period>"`, e.g. `"EMA 20"`; a non-close source is appended (`"EMA 20 hl2"`).
    public var displayName: String { "EMA \(period)\(sourceSuffix(source))" }
    /// `"EMA"`.
    public var shortName: String { "EMA" }
    /// Always `IndicatorPlacement.overlay`.
    public var placement: IndicatorPlacement { .overlay }

    /// Computes the average over `input.values(source)`; see ``IndicatorMath/ema(_:period:)``.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        movingAverageOutput(
            id: id,
            name: displayName,
            style: style,
            aligned: IndicatorMath.ema(input.values(source), period: period),
            times: input.candles.map(\.time)
        )
    }
}

/// Linearly weighted moving average, drawn over the price chart.
///
/// Weights run `1...period` with the newest value weighing most; the sum is divided by `period * (period + 1) / 2`.
/// The first `period - 1` bars have no value and are not part of the output.
public struct WMA: ChartIndicator {
    /// Number of bars averaged. At least 1.
    public let period: Int
    /// The price the average is computed from.
    public let source: PriceSource
    /// Line style. A `nil` color takes the next color from the theme palette.
    public let style: IndicatorLineStyle

    /// Creates a WMA. Traps if `period < 1`.
    public init(period: Int = 20, source: PriceSource = .close, style: IndicatorLineStyle = IndicatorLineStyle()) {
        precondition(period >= 1, "WMA period must be at least 1")
        self.period = period
        self.source = source
        self.style = style
    }

    /// `"wma(<period>,<source>)"`, e.g. `"wma(20,close)"`.
    public var id: String { "wma(\(period),\(source.rawValue))" }
    /// `"WMA <period>"`, e.g. `"WMA 20"`; a non-close source is appended (`"WMA 20 hl2"`).
    public var displayName: String { "WMA \(period)\(sourceSuffix(source))" }
    /// `"WMA"`.
    public var shortName: String { "WMA" }
    /// Always `IndicatorPlacement.overlay`.
    public var placement: IndicatorPlacement { .overlay }

    /// Computes the average over `input.values(source)`; see ``IndicatorMath/wma(_:period:)``.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        movingAverageOutput(
            id: id,
            name: displayName,
            style: style,
            aligned: IndicatorMath.wma(input.values(source), period: period),
            times: input.candles.map(\.time)
        )
    }
}
