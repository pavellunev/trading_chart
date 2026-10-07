import Foundation

/// The words the chart says: what VoiceOver reads and offers, the label of the "back to the latest bar" badge, the
/// "loading history" spinner, the rows of the crosshair tooltip and the names in the style picker.
///
/// The package carries the translations (see ``localized(for:)`` for the languages). ``standard`` is in the language of the
/// app (the one its main bundle is localized to), which is what the chart says when nobody sets anything; a host whose app has
/// a language of its own passes it with the `tradingChartStrings(_:)` view modifier, and a host that wants other words changes single fields (a string that has the
/// `%@` placeholders is a format: keep them, in the order your language needs with `%1$@` and `%2$@`):
///
/// ```swift
/// var strings = TradingChartStrings.localized(for: appLocale)
/// strings.scrollToLatest = String(localized: "chart.scrollToLatest")
/// strings.volume = String(localized: "chart.volume")
///
/// TradingChartView(model: model)
///     .tradingChartStrings(strings)
/// ```
///
/// The names of indicators come from the indicators themselves (`ChartIndicator.displayName`) and are not translated.
@available(iOS 17.0, *)
public struct TradingChartStrings: Sendable, Equatable {

    // MARK: VoiceOver

    /// What VoiceOver calls a chart drawn as a line.
    public var lineChart: String
    /// What VoiceOver calls a chart drawn as an area.
    public var areaChart: String
    /// What VoiceOver calls a chart drawn as candles.
    public var candlestickChart: String
    /// The last price in the value of the chart; `%@` is the formatted price.
    public var lastPrice: String
    /// The range of time on the screen, in the value of the chart and in the announcement after a scroll; the two `%@` are the
    /// formatted start and end.
    public var showingRange: String
    /// The value of the chart when the newest bar is on the screen, and what is announced after a scroll to it.
    public var atLatestBar: String
    /// The value of the chart when the window is in the past.
    public var scrolledIntoThePast: String
    /// What is announced when a scroll towards the past cannot go further.
    public var atStartOfHistory: String
    /// The action that scrolls the window one width towards the past.
    public var showEarlierBars: String
    /// The action that scrolls the window one width towards the live edge.
    public var showLaterBars: String
    /// The action that scrolls to the newest bar.
    public var showLatestBar: String
    /// What VoiceOver calls the price badge when it is the button that scrolls back to the newest bar.
    public var scrollToLatest: String
    /// What VoiceOver calls the spinner shown while history loads.
    public var loadingHistory: String

    // MARK: Crosshair tooltip

    /// The tooltip row with the time of the bar.
    public var time: String
    /// The tooltip row with the opening price.
    public var open: String
    /// The tooltip row with the highest price.
    public var high: String
    /// The tooltip row with the lowest price.
    public var low: String
    /// The tooltip row with the closing price.
    public var close: String
    /// The tooltip row with the price of a bar of a line or an area.
    public var price: String
    /// The tooltip row with the change of the bar in price units.
    public var change: String
    /// The tooltip row with the change of the bar in percent.
    public var changePercent: String
    /// The tooltip row with the range (high minus low) of the bar.
    public var range: String
    /// The tooltip row with the traded volume.
    public var volume: String

    // MARK: Style picker

    /// The entry of the style picker that shows a line.
    public var lineStyle: String
    /// The entry of the style picker that shows an area.
    public var areaStyle: String
    /// The entry of the style picker that shows candles.
    public var candlesStyle: String
    /// What VoiceOver calls the style picker; its value is the name of the current style.
    public var chartStyle: String

    /// The strings in the language of the app: the language its main bundle is localized to that best matches the user's
    /// preferences (an app that is only in English gets English on a device set to Arabic, like the rest of its screens),
    /// else English if the package has no strings in that language. An app that declares no language at all follows the
    /// preferred languages of the device.
    ///
    /// It is worked out once per process; a chart that follows a language setting of its own passes ``localized(for:)``.
    public static let standard = TradingChartStrings(language: StringCatalog.standardLanguage())

    /// The strings in the language of `locale`, for an app that has a language of its own (an in-app setting), which may not be
    /// the language of the device.
    ///
    /// The package has strings in English, German, Spanish, French, Hindi, Indonesian, Italian, Dutch, Brazilian Portuguese,
    /// Russian, Turkish, Vietnamese, Simplified Chinese and Arabic (`en`, `de`, `es`, `fr`, `hi`, `id`, `it`, `nl`, `pt-BR`,
    /// `ru`, `tr`, `vi`, `zh-Hans`, `ar`). A locale that matches none of them (a region of one of them does) gets English.
    ///
    /// - Parameter locale: The locale whose language the strings are in; only its language and script are used.
    public static func localized(for locale: Locale) -> TradingChartStrings {
        TradingChartStrings(language: StringCatalog.language(forPreferences: [locale.identifier]))
    }

    /// Creates the strings in the language of the app, like ``standard``; change what you need.
    public init() {
        self = .standard
    }

    init(language: String) {
        #if DEBUG
        StringCatalog.noteBuild()
        #endif
        let table = StringCatalog.table(for: language)
        lineChart = table["chart.line"]
        areaChart = table["chart.area"]
        candlestickChart = table["chart.candlestick"]
        lastPrice = table["chart.lastPrice"]
        showingRange = table["chart.showingRange"]
        atLatestBar = table["chart.atLatestBar"]
        scrolledIntoThePast = table["chart.scrolledIntoThePast"]
        atStartOfHistory = table["chart.atStartOfHistory"]
        showEarlierBars = table["chart.action.showEarlierBars"]
        showLaterBars = table["chart.action.showLaterBars"]
        showLatestBar = table["chart.action.showLatestBar"]
        scrollToLatest = table["badge.scrollToLatest"]
        loadingHistory = table["history.loading"]
        time = table["tooltip.time"]
        open = table["tooltip.open"]
        high = table["tooltip.high"]
        low = table["tooltip.low"]
        close = table["tooltip.close"]
        price = table["tooltip.price"]
        change = table["tooltip.change"]
        changePercent = table["tooltip.changePercent"]
        range = table["tooltip.range"]
        volume = table["tooltip.volume"]
        lineStyle = table["style.line"]
        areaStyle = table["style.area"]
        candlesStyle = table["style.candles"]
        chartStyle = table["style.picker"]
    }

    /// `template` with each `%@` replaced, in order, by one of `arguments` (`%1$@`, `%2$@` pick by position).
    func format(_ template: String, _ arguments: String...) -> String {
        String(format: template, arguments: arguments.map { $0 as CVarArg })
    }
}
