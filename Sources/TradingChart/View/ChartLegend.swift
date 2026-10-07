import SwiftUI
import TradingChartCore

/// Builds the legend text of the panes and the rows of the crosshair tooltip.
@available(iOS 17.0, *)
struct LegendFormatter {
    var theme: TradingChartTheme
    var priceFormatter: PriceFormatter
    /// The words of the tooltip. `nil` means ``TradingChartStrings/standard``, which is looked up only when the tooltip rows are
    /// built: the legend rows have no words of this kind.
    var strings: TradingChartStrings?

    /// What the change of a bar is measured against.
    enum ChangeReference {
        /// The open of the bar itself (as Binance does); a point series, which has no open, falls back to the previous value.
        case open
        /// The close of the previous bar; the first bar falls back to its own open.
        case previousClose
    }

    /// What the change in the tooltip is measured against.
    var changeReference: ChangeReference = .open

    private static func referencePrice(of state: CrosshairState, _ reference: ChangeReference) -> Double? {
        switch reference {
        case .open: state.candle?.open ?? state.previousClose
        case .previousClose: state.previousClose ?? state.candle?.open
        }
    }

    /// The change of a bar in price units against `reference`; `nil` when there is nothing to compare with.
    static func change(of state: CrosshairState, against reference: ChangeReference = .open) -> Double? {
        guard let price = referencePrice(of: state, reference) else { return nil }
        return state.value - price
    }

    /// The change of a bar in percent against `reference`; `nil` when there is nothing to compare with or it is zero.
    static func changePercent(of state: CrosshairState, against reference: ChangeReference = .open) -> Double? {
        guard let price = referencePrice(of: state, reference), price != 0 else { return nil }
        return (state.value - price) / abs(price) * 100
    }

    /// The legend row of one indicator: `SMA(20): 120,641.21`, or `BB(20,2) UP: … MB: … DN: …` with a title when it has
    /// several values. Labels and values wear the colour of their line; histogram values wear the colour of their tone
    /// and their labels the label colour. An indicator without values (warm-up) shows its title only.
    ///
    /// - Parameter context: How the values are formatted; panes use ``PriceFormatter/Context/compact``.
    func indicatorRow(
        name: String,
        values: [CrosshairIndicatorValue],
        context: PriceFormatter.Context
    ) -> AttributedString {
        var row = AttributedString()
        if values.isEmpty {
            append(&row, LegendNaming.title(for: name), color: theme.legendLabel)
        } else if values.count == 1, values[0].name == name {
            appendItem(&row, label: LegendNaming.title(for: name), value: values[0], context: context)
        } else {
            if LegendNaming.hasParameters(name) {
                append(&row, LegendNaming.title(for: name), color: theme.legendLabel)
            }
            // The main series of an indicator named after it (the bars of a volume) comes first, before its averages.
            let word = name.split(separator: " ").first.map(String.init) ?? name
            let ordered = values.filter { $0.tone != nil && $0.name == word } + values.filter { !($0.tone != nil && $0.name == word) }
            for value in ordered {
                appendItem(
                    &row,
                    label: LegendNaming.elementLabel(valueName: value.name, indicatorName: name),
                    value: value,
                    context: context
                )
            }
        }
        return row
    }

    /// The rows joined into the header line; indicators are set apart by three spaces.
    func header(_ rows: [AttributedString]) -> AttributedString {
        var line = AttributedString()
        for row in rows where !row.characters.isEmpty {
            if !line.characters.isEmpty { line += AttributedString("   ") }
            line += row
        }
        return line
    }

    /// The rows of the crosshair tooltip: time, the prices of the bar, its change and range, its volume.
    ///
    /// - Parameter time: The time of the bar, already formatted.
    func tooltipRows(for state: CrosshairState, drawnStyle: SeriesStyle, time: String) -> [TooltipRow] {
        let strings = strings ?? .standard
        var rows = [TooltipRow(label: strings.time, value: time)]
        let candle = drawnStyle == .candles ? state.candle : nil
        if let candle {
            rows.append(TooltipRow(label: strings.open, value: price(candle.open)))
            rows.append(TooltipRow(label: strings.high, value: price(candle.high)))
            rows.append(TooltipRow(label: strings.low, value: price(candle.low)))
            rows.append(TooltipRow(label: strings.close, value: price(candle.close)))
        } else {
            rows.append(TooltipRow(label: strings.price, value: price(state.value)))
        }
        if let change = Self.change(of: state, against: changeReference) {
            let tint: TooltipRow.Tint = change >= 0 ? .rising : .falling
            rows.append(TooltipRow(label: strings.change, value: (change >= 0 ? "+" : "") + price(change), tint: tint))
            if let percent = Self.changePercent(of: state, against: changeReference) {
                rows.append(TooltipRow(label: strings.changePercent, value: percentText(percent), tint: tint))
            }
        }
        if let candle {
            rows.append(TooltipRow(label: strings.range, value: price(candle.high - candle.low)))
        }
        if let volume = state.candle?.volume {
            rows.append(TooltipRow(label: strings.volume, value: priceFormatter.format(volume, context: .compact)))
        }
        return rows
    }

    private func price(_ value: Double) -> String {
        priceFormatter.format(value, context: .legend)
    }

    private func percentText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + "%"
    }

    private func appendItem(
        _ row: inout AttributedString,
        label: String,
        value: CrosshairIndicatorValue,
        context: PriceFormatter.Context
    ) {
        let valueColor = theme.legendColor(for: value)
        let labelColor = value.tone == nil ? valueColor : theme.legendLabel
        append(&row, label + ":", color: labelColor)
        append(&row, priceFormatter.format(value.value, context: context), color: valueColor)
    }

    private func append(_ row: inout AttributedString, _ text: String, color: Color) {
        if !row.characters.isEmpty { row += AttributedString(" ") }
        var part = AttributedString(text)
        part.foregroundColor = color
        row += part
    }
}

/// One row of the crosshair tooltip.
@available(iOS 17.0, *)
struct TooltipRow: Equatable {
    /// How the value is tinted.
    enum Tint: Equatable {
        case none, rising, falling
    }

    var label: String
    var value: String
    var tint: Tint = .none
}

/// The legend of a pane: a single line above the plot with the values of the selected (or the newest) bar.
/// Without room it scrolls sideways instead of wrapping; it takes no part in the plot, so it covers no data.
@available(iOS 17.0, *)
struct LegendHeader: View {
    let text: AttributedString

    @Environment(\.tradingChartTheme) private var theme

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(theme.legendFont)
                .foregroundStyle(theme.legendText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// The floating card with the values of the crosshair bar.
@available(iOS 17.0, *)
struct CrosshairTooltip: View {
    let rows: [TooltipRow]

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartHostLayoutDirection) private var hostLayoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.label)
                        .foregroundStyle(theme.tooltipText.opacity(0.6))
                    Spacer(minLength: 0)
                    Text(row.value)
                        .foregroundStyle(color(of: row.tint))
                }
            }
        }
        // The card is a piece of text: in a right-to-left host the labels are at the right, as the language reads. Where the
        // card sits on the plot does not depend on this; the chart around it is laid out left to right.
        .environment(\.layoutDirection, hostLayoutDirection)
        .font(theme.legendFont)
        .lineLimit(1)
        .padding(8)
        .background(theme.tooltipBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.grid, lineWidth: 1))
        .fixedSize()
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }

    private func color(of tint: TooltipRow.Tint) -> Color {
        switch tint {
        case .none: theme.tooltipText
        case .rising: theme.bullish
        case .falling: theme.bearish
        }
    }
}

/// Which side of the plot the tooltip sits on: opposite to the crosshair, so it does not hide the selected bar.
@available(iOS 17.0, *)
enum TooltipPlacement {
    enum Side: Equatable {
        case leading, trailing
    }

    /// The width the return chevron adds to the badge when the window is not at the live edge: its spacing and its glyph.
    static let badgeChevronWidth: CGFloat = 12

    /// How far the price badge reaches into the plot from the right edge of the plot, in points: it sits on the price
    /// column and only the part wider than the column sticks out. The tooltip on the trailing side keeps clear of it, so it
    /// never covers the badge, wherever the price puts the badge on the Y axis.
    ///
    /// - Parameters:
    ///   - badgeWidth: The width of the badge label (without the chevron); `0` before it is measured.
    ///   - columnWidth: The width of the price column to the right of the plot.
    ///   - showsChevron: Whether the badge is the button that returns to the live edge, which has a chevron.
    static func badgeReach(badgeWidth: CGFloat, columnWidth: CGFloat, showsChevron: Bool) -> CGFloat {
        guard badgeWidth > 0 else { return 0 }
        return Swift.max(0, badgeWidth + (showsChevron ? badgeChevronWidth : 0) - columnWidth)
    }

    /// The side for a crosshair at `crosshairX` in a plot `plotWidth` wide. A dead band around the middle keeps
    /// the current side, so the card does not flip back and forth while the finger hovers over the centre.
    static func side(crosshairX: CGFloat?, plotWidth: CGFloat, current: Side) -> Side {
        guard let crosshairX, plotWidth > 0 else { return current }
        let fraction = crosshairX / plotWidth
        if fraction < 0.45 { return .trailing }
        if fraction > 0.55 { return .leading }
        return current
    }
}

/// A label with the crosshair background, for the price at the right edge and the time at the bottom.
@available(iOS 17.0, *)
struct CrosshairBubble: View {
    let text: String
    var width: CGFloat?

    @Environment(\.tradingChartTheme) private var theme

    var body: some View {
        Text(text)
            .font(theme.axisFont)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(theme.crosshairLabelText)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: width)
            .background(theme.crosshairLabelBackground, in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// Positions of crosshair labels, from the window of the model.
@available(iOS 17.0, *)
enum CrosshairLayout {
    /// The width reserved for the time label.
    static let timeLabelWidth: CGFloat = 92

    /// The X of `time` inside a plot of `plotWidth` points that shows `visibleRange`; `nil` when it is outside the window.
    static func x(of time: Date, visibleRange: ClosedRange<Date>, plotWidth: CGFloat) -> CGFloat? {
        let duration = visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound)
        guard duration > 0, plotWidth > 0 else { return nil }
        let fraction = time.timeIntervalSince(visibleRange.lowerBound) / duration
        guard fraction >= -0.01, fraction <= 1.01 else { return nil }
        return CGFloat(fraction) * plotWidth
    }

    /// `x` kept inside the plot so that a label of `width` is not cut off.
    static func clamped(_ x: CGFloat, width: CGFloat, plotWidth: CGFloat) -> CGFloat {
        guard plotWidth > width else { return plotWidth / 2 }
        return Swift.min(Swift.max(x, width / 2), plotWidth - width / 2)
    }
}
