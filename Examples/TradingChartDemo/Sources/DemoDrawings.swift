import Foundation
import TradingChart

/// Drawings in the demo: the script actions that put drawings on the chart without touches (for screenshots and the
/// performance runs).
extension DemoViewModel {

    /// The drawing kind for a launch-script name.
    static func drawingKind(named name: String) -> DrawingKind? {
        switch name {
        case "horizontal": .horizontalLine
        case "trend": .trendLine
        case "ray": .ray
        default: nil
        }
    }

    /// `trend:20,c-100,5,c+120`: the kind, then `barsBack,price` for every anchor.
    func addDrawing(_ description: String) {
        let parts = description.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Self.drawingKind(named: parts[0]),
              let tool = model.drawingTools.tool(for: kind)
        else { return }
        let tokens = parts[1].split(separator: ",").map(String.init)
        guard tokens.count >= 2 * tool.requiredAnchorCount else { return }
        var anchors: [ChartAnchor] = []
        for index in 0..<tool.requiredAnchorCount {
            guard let anchor = anchor(barsBack: tokens[2 * index], price: tokens[2 * index + 1]) else { return }
            anchors.append(anchor)
        }
        model.drawings.append(ChartDrawing(kind: kind, anchors: anchors))
    }

    func selectDrawing(_ index: String) {
        if index == "none" {
            model.selectedDrawingID = nil
        } else if let position = Int(index), model.drawings.indices.contains(position) {
            model.selectedDrawingID = model.drawings[position].id
        }
    }

    /// `0,1,12,c+50`: the drawing, its anchor, then the new `barsBack,price`. What a drag leaves behind, without the drag.
    func moveAnchor(_ description: String) {
        let tokens = description.split(separator: ",").map(String.init)
        guard tokens.count == 4, let drawing = Int(tokens[0]), let index = Int(tokens[1]),
              model.drawings.indices.contains(drawing), model.drawings[drawing].anchors.indices.contains(index),
              let anchor = anchor(barsBack: tokens[2], price: tokens[3])
        else { return }
        model.drawings[drawing].anchors[index] = anchor
    }

    /// `count` drawings of all kinds spread over the whole series, for the performance runs: horizontal lines at evenly spaced
    /// prices between its lowest and highest, trend lines and rays between real closes (25 bars apart) at evenly spaced
    /// positions, so that some of them are in view wherever the window is.
    func scatterDrawings(count: Int) {
        guard count > 0, let candles = model.series.candles, candles.count > 30 else { return }
        let low = candles.map(\.low).min() ?? 0
        let high = candles.map(\.high).max() ?? 1
        let span = 25
        var drawings = model.drawings
        for index in 0..<count {
            let fraction = (Double(index) + 0.5) / Double(count)
            let start = Int(fraction * Double(candles.count - span - 1))
            switch index % 3 {
            case 0:
                let price = low + (high - low) * fraction
                drawings.append(ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: candles[start].time, price: price)]))
            case 1:
                drawings.append(ChartDrawing(kind: .trendLine, anchors: [
                    ChartAnchor(time: candles[start].time, price: candles[start].close),
                    ChartAnchor(time: candles[start + span].time, price: candles[start + span].close),
                ]))
            default:
                drawings.append(ChartDrawing(kind: .ray, anchors: [
                    ChartAnchor(time: candles[start].time, price: candles[start].close),
                    ChartAnchor(time: candles[start + span].time, price: candles[start + span].close),
                ]))
            }
        }
        model.drawings = drawings
    }

    /// Moves the second anchor of the first drawing a little, the way a drag does on every frame (`-wiggle`).
    func wiggleDrawing(at seconds: TimeInterval) {
        guard let first = model.drawings.first, let anchor = first.anchors.last else { return }
        let price = anchor.price + sin(seconds * 9) * anchor.price * 0.0004
        model.drawings[0].anchors[first.anchors.count - 1] = ChartAnchor(time: anchor.time, price: price)
    }

    private func anchor(barsBack: String, price: String) -> ChartAnchor? {
        guard let bars = Double(barsBack), let lastTime = model.series.lastTime,
              let value = resolvedPrice(price)
        else { return nil }
        return ChartAnchor(time: lastTime.addingTimeInterval(-bars * model.series.interval.seconds), price: value)
    }

    /// A number, or `c` for the last close with an optional offset: `c`, `c+150`, `c-80`.
    private func resolvedPrice(_ text: String) -> Double? {
        guard text.hasPrefix("c") else { return Double(text) }
        guard let close = model.series.lastValue else { return nil }
        let offset = text.dropFirst()
        return offset.isEmpty ? close : Double(offset).map { close + $0 }
    }
}
