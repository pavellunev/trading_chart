import Foundation
import TradingChartCore

/// Traded volume in its own pane, with an optional moving average.
///
/// One histogram bar per bar that has a volume, growing from zero. The tone follows the candle direction:
/// `.positive` when `close >= open`, `.negative` otherwise. With `movingAveragePeriod` set, a line (`<id>.ma`) shows
/// the SMA of the volume; a bar without volume counts as `0` there. If no bar carries a volume (for example a point
/// series) the output is `IndicatorOutput.empty`.
public struct Volume: ChartIndicator {
    /// Period of the volume moving average, or `nil` for no average line. At least 1 when set.
    public let movingAveragePeriod: Int?
    /// Style of the moving average line. A `nil` color takes the next color from the theme palette.
    public let movingAverageStyle: IndicatorLineStyle

    /// Creates a volume indicator. Traps if `movingAveragePeriod` is less than 1.
    public init(movingAveragePeriod: Int? = nil, movingAverageStyle: IndicatorLineStyle = IndicatorLineStyle()) {
        if let movingAveragePeriod {
            precondition(movingAveragePeriod >= 1, "Volume moving average period must be at least 1")
        }
        self.movingAveragePeriod = movingAveragePeriod
        self.movingAverageStyle = movingAverageStyle
    }

    /// `"volume"`, or `"volume(<period>)"` with a moving average, e.g. `"volume(20)"`.
    public var id: String {
        movingAveragePeriod.map { "volume(\($0))" } ?? "volume"
    }
    /// Always `"Volume"`.
    public var displayName: String { "Volume" }
    /// `"VOL"`.
    public var shortName: String { "VOL" }
    /// Always `IndicatorPlacement.pane`.
    public var placement: IndicatorPlacement { .pane }

    /// Builds the histogram (and the average line) from the candle volumes.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let candles = input.candles
        guard candles.contains(where: { $0.volume != nil }) else { return .empty }

        let bars = candles.compactMap { candle -> HistogramBar? in
            guard let volume = candle.volume else { return nil }
            return HistogramBar(time: candle.time, value: volume, tone: candle.isBullish ? .positive : .negative)
        }
        var output = IndicatorOutput(histograms: [
            IndicatorHistogram(id: "\(id).volume", name: "Volume", bars: bars)
        ])
        if let period = movingAveragePeriod {
            let average = IndicatorMath.sma(candles.map { $0.volume ?? 0 }, period: period)
            output.lines = [
                IndicatorLine(
                    id: "\(id).ma",
                    name: "Volume MA \(period)",
                    values: definedValues(average, times: candles.map(\.time)),
                    style: movingAverageStyle
                )
            ]
        }
        return output
    }
}
