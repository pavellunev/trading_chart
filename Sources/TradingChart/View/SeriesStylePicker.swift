import SwiftUI
import TradingChartCore

/// A small icon that shows the style of a chart and opens a menu to change it (line, area, candles).
///
/// ``TradingChartView`` shows one in the legend row of the main pane, at the right over the price column, when
/// ``TradingChartConfiguration/stylePicker`` is set. It is public so that a host can put the same control somewhere else
/// (a toolbar, say). Choosing an entry sets ``TradingChartModel/style``, with everything that does: the window goes back to
/// the default width of the style and to the live edge.
///
/// ```swift
/// SeriesStylePicker(model: model, options: StylePickerOptions(availableStyles: [.line, .candles]))
/// ```
@available(iOS 17.0, *)
public struct SeriesStylePicker: View {
    private let model: TradingChartModel
    private let options: StylePickerOptions

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartStrings) private var strings

    /// The width and the height of the tap target, in points.
    static let size = CGSize(width: 44, height: 24)

    /// Creates a picker for `model`.
    ///
    /// - Parameters:
    ///   - model: The chart whose ``TradingChartModel/style`` the picker shows and sets.
    ///   - options: The styles on offer and their titles.
    public init(model: TradingChartModel, options: StylePickerOptions = StylePickerOptions()) {
        self.model = model
        self.options = options
    }

    /// The picker; empty when ``StylePickerOptions/availableStyles`` is empty.
    public var body: some View {
        let styles = options.listedStyles
        if !styles.isEmpty {
            let style = model.style
            let label = options.accessibilityLabel ?? strings.chartStyle
            Menu {
                Picker(label, selection: selection) {
                    ForEach(styles, id: \.self) { style in
                        Label(options.title(for: style, strings: strings), systemImage: Self.systemImage(for: style))
                            .tag(style)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: Self.systemImage(for: style))
                    .font(.system(size: 14))
                    .foregroundStyle(theme.axisLabel)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(options.title(for: style, strings: strings))
        }
    }

    private var selection: Binding<SeriesStyle> {
        Binding(get: { model.style }, set: { model.style = $0 })
    }

    /// The SF Symbol of a style: a line, a line with a trend, bars (there is no candlestick symbol).
    static func systemImage(for style: SeriesStyle) -> String {
        switch style {
        case .line: "chart.xyaxis.line"
        case .area: "chart.line.uptrend.xyaxis"
        case .candles: "chart.bar.xaxis"
        }
    }
}
