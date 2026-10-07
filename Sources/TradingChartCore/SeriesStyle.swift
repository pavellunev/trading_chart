/// How a series is drawn.
///
/// `.area` is a line with a gradient fill underneath. `.candles` falls back to a plain line
/// when the series carries no OHLC data.
public enum SeriesStyle: String, Sendable, Codable, CaseIterable {
    /// A plain line through the close prices.
    case line
    /// A line with a gradient fill underneath.
    case area
    /// OHLC candlesticks.
    case candles
}
