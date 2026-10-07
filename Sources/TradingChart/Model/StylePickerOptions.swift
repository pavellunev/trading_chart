import TradingChartCore

/// What the style picker on the chart (``SeriesStylePicker``) offers and how it is worded.
///
/// Set it as ``TradingChartConfiguration/stylePicker`` to show the picker on the chart; `nil` there hides it. The titles and the
/// label are the words of ``TradingChartStrings`` (in the language of the chart, see ``TradingChartStrings/localized(for:)``);
/// give ``titles`` (and ``accessibilityLabel``) the host's own strings to replace them.
///
/// ```swift
/// var configuration = TradingChartConfiguration()
/// configuration.stylePicker = StylePickerOptions(
///     availableStyles: [.line, .candles],
///     titles: [.line: String(localized: "Line"), .candles: String(localized: "Candles")]
/// )
/// ```
@available(iOS 17.0, *)
public struct StylePickerOptions: Sendable, Equatable {
    /// The styles on offer, in the order they are listed. Repeated styles are listed once; none at all hides the picker.
    public var availableStyles: [SeriesStyle]
    /// Titles that replace the default ones (``TradingChartStrings/lineStyle`` and its siblings), by style.
    public var titles: [SeriesStyle: String]
    /// What VoiceOver calls the picker, replacing ``TradingChartStrings/chartStyle``; its value is the title of the current style.
    public var accessibilityLabel: String?

    /// Creates options.
    ///
    /// - Parameters:
    ///   - availableStyles: The styles on offer; all three by default.
    ///   - titles: Titles that replace the default ones.
    ///   - accessibilityLabel: What VoiceOver calls the picker; `nil` for the words of the chart.
    public init(
        availableStyles: [SeriesStyle] = SeriesStyle.allCases,
        titles: [SeriesStyle: String] = [:],
        accessibilityLabel: String? = nil
    ) {
        self.availableStyles = availableStyles
        self.titles = titles
        self.accessibilityLabel = accessibilityLabel
    }

    /// The title of `style`: the one in ``titles``, else the word of `strings`.
    ///
    /// - Parameters:
    ///   - style: The style.
    ///   - strings: The words of the chart; the ones of the device by default.
    public func title(for style: SeriesStyle, strings: TradingChartStrings = .standard) -> String {
        if let title = titles[style] { return title }
        switch style {
        case .line: return strings.lineStyle
        case .area: return strings.areaStyle
        case .candles: return strings.candlesStyle
        }
    }

    /// ``availableStyles`` without repeats.
    var listedStyles: [SeriesStyle] {
        var seen = Set<SeriesStyle>()
        return availableStyles.filter { seen.insert($0).inserted }
    }
}
