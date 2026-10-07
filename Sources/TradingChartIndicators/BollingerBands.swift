import Foundation
import TradingChartCore

/// Bollinger Bands, drawn over the price chart.
///
/// `middle = SMA(period)`, `upper = middle + multiplier * sigma`, `lower = middle - multiplier * sigma`, where sigma is
/// the **population** standard deviation (divisor `period`) of the same window. The output has three lines
/// (`<id>.middle`, `<id>.upper`, `<id>.lower`) and one filled band between upper and lower (`<id>.band`).
/// The first `period - 1` bars have no value and are not part of the output.
public struct BollingerBands: ChartIndicator {
    /// Window length. At least 1.
    public let period: Int
    /// Number of standard deviations between the middle line and each edge. Not negative.
    public let multiplier: Double
    /// The price the bands are computed from.
    public let source: PriceSource
    /// Color of the lines and the band fill. `nil` takes one color from the theme palette for the whole indicator.
    public let color: ChartColor?

    /// Creates Bollinger Bands. Traps if `period < 1` or `multiplier < 0`.
    public init(period: Int = 20, multiplier: Double = 2, source: PriceSource = .close, color: ChartColor? = nil) {
        precondition(period >= 1, "BollingerBands period must be at least 1")
        precondition(multiplier >= 0, "BollingerBands multiplier must not be negative")
        self.period = period
        self.multiplier = multiplier
        self.source = source
        self.color = color
    }

    /// `"bb(<period>,<multiplier>,<source>)"`, e.g. `"bb(20,2,close)"`.
    public var id: String { "bb(\(period),\(parameterText(multiplier)),\(source.rawValue))" }
    /// `"BB <period> <multiplier>"`, e.g. `"BB 20 2"`; a non-close source is appended.
    public var displayName: String { "BB \(period) \(parameterText(multiplier))\(sourceSuffix(source))" }
    /// `"BOLL"`.
    public var shortName: String { "BOLL" }
    /// Always `IndicatorPlacement.overlay`.
    public var placement: IndicatorPlacement { .overlay }

    /// Computes the bands over `input.values(source)`; see ``IndicatorMath/sma(_:period:)`` and
    /// ``IndicatorMath/populationStdDev(_:period:)``.
    public func calculate(_ input: IndicatorInput) -> IndicatorOutput {
        let values = input.values(source)
        let times = input.candles.map(\.time)
        let middle = IndicatorMath.sma(values, period: period)
        let deviation = IndicatorMath.populationStdDev(values, period: period)

        var upper = [Double?](repeating: nil, count: values.count)
        var lower = [Double?](repeating: nil, count: values.count)
        for index in values.indices {
            guard let center = middle[index], let sigma = deviation[index] else { continue }
            upper[index] = center + multiplier * sigma
            lower[index] = center - multiplier * sigma
        }

        let upperValues = definedValues(upper, times: times)
        let lowerValues = definedValues(lower, times: times)
        return IndicatorOutput(
            lines: [
                IndicatorLine(
                    id: "\(id).middle",
                    name: "BB Middle",
                    values: definedValues(middle, times: times),
                    style: IndicatorLineStyle(color: color, width: 1, dash: [4, 3])
                ),
                IndicatorLine(
                    id: "\(id).upper",
                    name: "BB Upper",
                    values: upperValues,
                    style: IndicatorLineStyle(color: color, width: 1)
                ),
                IndicatorLine(
                    id: "\(id).lower",
                    name: "BB Lower",
                    values: lowerValues,
                    style: IndicatorLineStyle(color: color, width: 1)
                ),
            ],
            bands: [IndicatorBand(id: "\(id).band", upper: upperValues, lower: lowerValues, fill: color)]
        )
    }
}
