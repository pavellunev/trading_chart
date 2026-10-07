#if DEBUG
import SwiftUI
import TradingChartCore

/// Deterministic sample data for previews.
@available(iOS 17.0, *)
@MainActor
private func previewModel(style: SeriesStyle) -> TradingChartModel {
    let interval = ChartInterval.minutes(5)
    let end = Date(timeIntervalSince1970: 1_760_000_000)
    let candles = (0..<200).map { index -> Candle in
        let time = end.addingTimeInterval(Double(index - 199) * interval.seconds)
        let phase = Double(index)
        let open = 100 + 6 * sin(phase / 9) + 2 * sin(phase / 3.1)
        let close = 100 + 6 * sin((phase + 1) / 9) + 2 * sin((phase + 1) / 3.1)
        let wick = 0.6 + 0.4 * abs(sin(phase))
        return Candle(
            time: time,
            open: open,
            high: max(open, close) + wick,
            low: min(open, close) - wick,
            close: close,
            volume: 1_000 + 400 * abs(sin(phase / 4))
        )
    }
    let series = ChartSeries(candles: candles, interval: interval)
    let model = TradingChartModel(series: series, style: style)
    model.currentPrice = series.lastValue
    if let first = series.points.dropFirst(150).first, let second = series.points.dropFirst(175).first {
        model.markers = [
            ChartMarker(id: "buy", time: first.time, kind: .buy),
            ChartMarker(id: "sell", time: second.time, kind: .sell),
        ]
    }
    return model
}

@available(iOS 17.0, *)
#Preview("Candles") {
    TradingChartView(model: previewModel(style: .candles))
        .frame(height: 360)
        .padding()
}

@available(iOS 17.0, *)
#Preview("Area") {
    TradingChartView(model: previewModel(style: .area))
        .frame(height: 360)
        .padding()
}

@available(iOS 17.0, *)
#Preview("Line, dark") {
    TradingChartView(model: previewModel(style: .line))
        .frame(height: 360)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
