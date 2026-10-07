import Foundation
import TradingChartCore

/// Relative Strength Index with Wilder smoothing, in its own pane.
///
/// Computed from close prices by ``IndicatorMath/rsi(_:period:)``: `RSI = 100 * avgGain / (avgGain + avgLoss)`.
/// Convention for flat markets: `avgLoss == 0` gives `100`, no movement at all (both averages `0`) gives `50`.
/// The output has one line, a fixed `0...100` range and two dashed reference levels (`<id>.overbought`,
/// `<id>.oversold`). The first `period` bars have no value and are not part of the output.
public struct RSI: ChartIndicator {
    /// Smoothing period. At least 1.
    public let period: Int
    /// Upper reference level.
    public let overbought: Double
    /// Lower reference level.
    public let oversold: Double
    /// Line style. A `nil` color takes the next color from the theme palette.
    public let style: IndicatorLineStyle

    /// Creates an RSI. Traps if `period < 1`.
    public init(
        period: Int = 14,
        overbought: Double = 70,
        oversold: Double = 30,
        style: IndicatorLineStyle = IndicatorLineStyle()
    ) {
        precondition(period >= 1, "RSI period must be at least 1")
        self.period = period
        self.overbought = overbought
        self.oversold = oversold
        self.style = style
    }

    /// `"rsi(<period>,<overbought>,<oversold>)"`, e.g. `"rsi(14,70,30)"`.
    public var id: String { "rsi(\(period),\(parameterText(overbought)),\(parameterText(oversold)))" }
    /// `"RSI <period>"`, e.g. `"RSI 14"`.
    public var displayName: String { "RSI \(period)" }
    /// `"RSI"`.
    public var shortName: String { "RSI" }
    /// Always `IndicatorPlacement.pane`.
    public var placement: IndicatorPlacement { .pane }

    /// Computes the index over the close prices.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let aligned = IndicatorMath.rsi(input.values(.close), period: period)
        return IndicatorOutput(
            lines: [
                IndicatorLine(
                    id: id,
                    name: displayName,
                    values: definedValues(aligned, times: input.candles.map(\.time)),
                    style: style
                )
            ],
            levels: [
                IndicatorLevel(id: "\(id).overbought", value: overbought),
                IndicatorLevel(id: "\(id).oversold", value: oversold),
            ],
            fixedRange: 0...100
        )
    }
}
