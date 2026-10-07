import SwiftUI
import TradingChartCore

/// Deals out the theme palette to indicators.
///
/// The palette is dealt out per indicator, not per line: every indicator gets a base index, the next free palette
/// position, and a line or band without an explicit colour picks `base + paletteSlot` (wrapping around the palette).
@available(iOS 17.0, *)
enum IndicatorPalette {

    /// How many palette positions an indicator takes: the highest `paletteSlot` among its lines and bands
    /// that have no explicit colour, plus one. An indicator with nothing to colour takes none.
    static func slotCount(of output: IndicatorOutput) -> Int {
        var highest = -1
        for line in output.lines where line.style.color == nil {
            highest = Swift.max(highest, line.paletteSlot)
        }
        for band in output.bands where band.fill == nil {
            highest = Swift.max(highest, band.paletteSlot)
        }
        return highest + 1
    }

    /// The base index of every indicator, in order: each starts where the previous one ended.
    static func baseIndices(for outputs: [IndicatorOutput]) -> [Int] {
        var next = 0
        return outputs.map { output in
            defer { next += slotCount(of: output) }
            return next
        }
    }

    /// The position in a palette of `paletteCount` colours.
    static func position(base: Int, slot: Int, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let raw = base + Swift.max(slot, 0)
        return ((raw % paletteCount) + paletteCount) % paletteCount
    }
}

@available(iOS 17.0, *)
extension TradingChartTheme {
    /// The colour at `paletteIndex` (wrapped around the palette); ``line`` when the palette is empty.
    func paletteColor(at paletteIndex: Int) -> Color {
        guard !indicatorPalette.isEmpty else { return line }
        return indicatorPalette[IndicatorPalette.position(base: paletteIndex, slot: 0, paletteCount: indicatorPalette.count)]
    }

    /// The colour a histogram bar is drawn with: an explicit colour, else the tone's colour.
    func histogramColor(tone: HistogramTone, explicit: ChartColor?) -> Color {
        if let explicit { return Color(explicit) }
        switch tone {
        case .positive: return bullish
        case .negative: return bearish
        case .neutral: return axisLabel
        }
    }

    /// The colour of a crosshair legend value.
    func legendColor(for value: CrosshairIndicatorValue) -> Color {
        if let color = value.color { return Color(color) }
        if let tone = value.tone { return histogramColor(tone: tone, explicit: nil) }
        if let index = value.paletteIndex { return paletteColor(at: index) }
        return legendText
    }
}
