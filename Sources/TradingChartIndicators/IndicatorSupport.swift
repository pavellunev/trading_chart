import Foundation
import TradingChartCore

/// Pairs the defined entries of an index-aligned series with the bar times, dropping the warm-up `nil`s.
func definedValues(_ aligned: [Double?], times: [Date]) -> [IndicatorValue] {
    var result: [IndicatorValue] = []
    result.reserveCapacity(aligned.count)
    for (time, value) in zip(times, aligned) {
        if let value { result.append(IndicatorValue(time: time, value: value)) }
    }
    return result
}

/// Renders a parameter for ids and names: whole numbers without a fractional part (`2`, not `2.0`).
func parameterText(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
    return "\(value)"
}

/// The suffix appended to display names when the price source is not the default close, e.g. `" hl2"`.
func sourceSuffix(_ source: PriceSource) -> String {
    source == .close ? "" : " \(source.rawValue)"
}

/// The output shared by the single-line moving averages.
func movingAverageOutput(
    id: String,
    name: String,
    style: IndicatorLineStyle,
    aligned: [Double?],
    times: [Date]
) -> IndicatorOutput {
    IndicatorOutput(lines: [
        IndicatorLine(id: id, name: name, values: definedValues(aligned, times: times), style: style)
    ])
}
