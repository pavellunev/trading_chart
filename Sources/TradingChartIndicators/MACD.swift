import Foundation
import TradingChartCore

/// Moving Average Convergence Divergence, in its own pane.
///
/// Computed from close prices by ``IndicatorMath/macd(_:fast:slow:signal:)``: the MACD line is `EMA(fast) - EMA(slow)`,
/// the signal line is the EMA of the MACD line, and the histogram is their difference. Histogram bars are
/// `.positive` above zero, `.negative` below zero and `.neutral` at exactly zero.
/// The output has two lines (`<id>.macd`, `<id>.signal`) and one histogram (`<id>.histogram`) around a `0` baseline.
/// The signal line uses palette slot 1, so the two lines get different colors when neither has an explicit one.
/// Bars before each series is defined are not part of the output.
public struct MACD: ChartIndicator {
    /// Period of the fast EMA. At least 1.
    public let fast: Int
    /// Period of the slow EMA. At least 1.
    public let slow: Int
    /// Period of the signal EMA. At least 1.
    public let signal: Int
    /// Style of the MACD line. A `nil` color takes the next color from the theme palette.
    public let macdStyle: IndicatorLineStyle
    /// Style of the signal line. A `nil` color takes the next color from the theme palette.
    public let signalStyle: IndicatorLineStyle

    /// Creates a MACD. Traps if any period is less than 1.
    public init(
        fast: Int = 12,
        slow: Int = 26,
        signal: Int = 9,
        macdStyle: IndicatorLineStyle = IndicatorLineStyle(),
        signalStyle: IndicatorLineStyle = IndicatorLineStyle()
    ) {
        precondition(fast >= 1 && slow >= 1 && signal >= 1, "MACD periods must be at least 1")
        self.fast = fast
        self.slow = slow
        self.signal = signal
        self.macdStyle = macdStyle
        self.signalStyle = signalStyle
    }

    /// `"macd(<fast>,<slow>,<signal>)"`, e.g. `"macd(12,26,9)"`.
    public var id: String { "macd(\(fast),\(slow),\(signal))" }
    /// `"MACD <fast> <slow> <signal>"`, e.g. `"MACD 12 26 9"`.
    public var displayName: String { "MACD \(fast) \(slow) \(signal)" }
    /// `"MACD"`.
    public var shortName: String { "MACD" }
    /// Always `IndicatorPlacement.pane`.
    public var placement: IndicatorPlacement { .pane }

    /// Computes the lines and the histogram over the close prices.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let result = IndicatorMath.macd(input.values(.close), fast: fast, slow: slow, signal: signal)
        let times = input.candles.map(\.time)

        var bars: [HistogramBar] = []
        for (time, value) in zip(times, result.histogram) {
            guard let value else { continue }
            let tone: HistogramTone = value > 0 ? .positive : (value < 0 ? .negative : .neutral)
            bars.append(HistogramBar(time: time, value: value, tone: tone))
        }

        return IndicatorOutput(
            lines: [
                IndicatorLine(
                    id: "\(id).macd",
                    name: "MACD",
                    values: definedValues(result.macd, times: times),
                    style: macdStyle
                ),
                IndicatorLine(
                    id: "\(id).signal",
                    name: "Signal",
                    values: definedValues(result.signal, times: times),
                    style: signalStyle,
                    paletteSlot: 1
                ),
            ],
            histograms: [IndicatorHistogram(id: "\(id).histogram", name: "Histogram", bars: bars)]
        )
    }
}
