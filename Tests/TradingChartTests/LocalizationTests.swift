import SwiftUI
import Testing
import UIKit
@testable import TradingChart

private let languages = ["en", "de", "es", "fr", "hi", "id", "it", "nl", "pt-BR", "ru", "tr", "vi", "zh-Hans", "ar"]
private let foreignLanguages = languages.filter { $0 != "en" }

/// The compiled strings of one language, as the bundle of the package has them.
private func table(_ language: String) throws -> [String: String] {
    let url = try #require(
        StringCatalog.bundle.url(forResource: StringCatalog.tableName, withExtension: "strings", subdirectory: nil, localization: language),
        "no strings for \(language)"
    )
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
}

/// The placeholders of a format string, in order: `%@`, `%1$@`, `%2$@`, `%d`.
private func placeholders(of text: String) -> [String] {
    let pattern = #"%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|j|t)?[@dDiouUxXeEfFgGaAcCsSp]"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
}

private func fields(of strings: TradingChartStrings) -> [String] {
    Mirror(reflecting: strings).children.compactMap { $0.value as? String }
}

private let cyrillic: ClosedRange<UInt32> = 0x0400...0x04FF
private let arabic: ClosedRange<UInt32> = 0x0600...0x06FF
private let devanagari: ClosedRange<UInt32> = 0x0900...0x097F
private let han: ClosedRange<UInt32> = 0x4E00...0x9FFF

private func contains(_ text: String, _ range: ClosedRange<UInt32>) -> Bool {
    text.unicodeScalars.contains { range.contains($0.value) }
}

@Suite("Localization of the chart")
struct LocalizationTests {
    @Test("the package has strings for the fourteen languages, and no others")
    func languageList() {
        #expect(Set(StringCatalog.languages) == Set(languages))
        #expect(StringCatalog.languages.count == languages.count)
    }

    @Test("every key of the catalog is in every language, filled, with the placeholders of the English one", arguments: foreignLanguages)
    func catalogIsComplete(language: String) throws {
        let base = try table("en")
        let translated = try table(language)
        #expect(Set(translated.keys) == Set(base.keys), "\(language) differs in keys")
        #expect(!base.isEmpty)
        for (key, english) in base {
            let value = try #require(translated[key])
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language): \(key) is empty")
            #expect(
                placeholders(of: value) == placeholders(of: english),
                "\(language): \(key) has the placeholders \(placeholders(of: value)), English has \(placeholders(of: english))"
            )
        }
    }

    @Test("the strings with two arguments take them by position, in every language")
    func positionalPlaceholders() throws {
        let base = try table("en")
        #expect(placeholders(of: try #require(base["chart.showingRange"])) == ["%1$@", "%2$@"])
        #expect(placeholders(of: try #require(base["chart.lastPrice"])) == ["%@"])
    }

    @Test("every string of the chart is a word of the catalog: no field is left on its key, no key is unused", arguments: languages)
    func everyFieldIsLoaded(language: String) throws {
        let words = try table(language)
        let values = fields(of: TradingChartStrings(language: language))
        #expect(values.count == words.count, "\(values.count) fields, \(words.count) keys")
        #expect(Set(values) == Set(words.values))
    }

    @Test("the range is a difference of prices, not a percentage; the actions speak of bars or points, not of candles")
    func neutralWords() {
        let chinese = TradingChartStrings(language: "zh-Hans")
        #expect(chinese.range == "高低差")
        let arabic = TradingChartStrings(language: "ar")
        // The actions and the value of the chart are about the bars of any style, a line included.
        for strings in [chinese, arabic] {
            let spoken = [strings.showEarlierBars, strings.showLaterBars, strings.showLatestBar, strings.atLatestBar]
            #expect(!spoken.contains { $0.contains("K线") || $0.contains("شمع") }, "\(spoken)")
        }
        #expect(chinese.showLatestBar == "显示最新数据点")
        #expect(arabic.showLatestBar == "عرض أحدث نقطة بيانات")
        // The candlestick chart and the candles style stay candles.
        #expect(chinese.candlesStyle == "K线")
        #expect(arabic.candlesStyle == "شموع")
    }

    @Test("a language is not English with another name: the long phrases are translated", arguments: foreignLanguages)
    func translated(language: String) {
        let strings = TradingChartStrings(language: language)
        #expect(strings.lineChart != english.lineChart)
        #expect(strings.candlestickChart != english.candlestickChart)
        #expect(strings.atStartOfHistory != english.atStartOfHistory)
        #expect(strings.loadingHistory != english.loadingHistory)
        #expect(strings.chartStyle != english.chartStyle)
        #expect(strings.showingRange != english.showingRange)
    }

    @Test("every word is in the script of its language")
    func scripts() throws {
        let latin = [cyrillic, arabic, devanagari, han]
        for language in languages {
            let values = fields(of: TradingChartStrings(language: language))
            switch language {
            case "ru": #expect(values.allSatisfy { contains($0, cyrillic) }, "ru")
            case "ar": #expect(values.allSatisfy { contains($0, arabic) }, "ar")
            case "hi": #expect(values.allSatisfy { contains($0, devanagari) }, "hi")
            case "zh-Hans": #expect(values.allSatisfy { contains($0, han) }, "zh-Hans")
            default:
                for value in values {
                    #expect(!latin.contains { contains(value, $0) }, "\(language): \(value)")
                }
            }
        }
    }

    @Test("the strings of a locale are in its language")
    func localizedForLocale() {
        let chinese = TradingChartStrings.localized(for: Locale(identifier: "zh-Hans"))
        #expect([chinese.open, chinese.high, chinese.low, chinese.close] == ["开盘", "最高", "最低", "收盘"])
        #expect(chinese.lineStyle == "折线")

        let arabic = TradingChartStrings.localized(for: Locale(identifier: "ar"))
        #expect([arabic.open, arabic.high, arabic.low, arabic.close] == ["الافتتاح", "الأعلى", "الأدنى", "الإغلاق"])
        #expect(arabic.volume == "الحجم")

        let russian = TradingChartStrings.localized(for: Locale(identifier: "ru"))
        #expect(russian.time == "\u{0412}\u{0440}\u{0435}\u{043C}\u{044F}")  // the Russian "time"
        #expect(russian.volume == "\u{041E}\u{0431}\u{044A}\u{0451}\u{043C}")  // the Russian "volume"
        #expect(russian != english)

        let german = TradingChartStrings.localized(for: Locale(identifier: "de"))
        #expect(german.volume == "Volumen")
        #expect(german.lineChart == "Liniendiagramm")
        #expect(TradingChartStrings.localized(for: Locale(identifier: "en")) == english)
    }

    @Test("a region, a script or an underscore does not hide the language")
    func regionsAndScripts() {
        func strings(_ identifier: String) -> TradingChartStrings { .localized(for: Locale(identifier: identifier)) }
        #expect(strings("ru_RU") == strings("ru"))
        #expect(strings("ar_SA") == strings("ar"))
        #expect(strings("ar_AE@numbers=latn") == strings("ar"))
        #expect(strings("zh_CN") == strings("zh-Hans"))
        #expect(strings("zh-Hans-CN") == strings("zh-Hans"))
        #expect(strings("pt_BR") == strings("pt-BR"))
        #expect(strings("pt_PT") == strings("pt-BR"))
        #expect(strings("de_AT") == strings("de"))
        #expect(strings("hi_IN") == strings("hi"))
        #expect(strings("id_ID") == strings("id"))
        #expect(strings("en_GB") == english)
        #expect(strings("ru") != strings("de"))
    }

    @Test("a language that the package does not have gets English")
    func unsupportedLocale() {
        for identifier in ["sw", "uk", "zh-Hant", "he", "tlh", "", "en_US_POSIX"] {
            #expect(TradingChartStrings.localized(for: Locale(identifier: identifier)) == english, "\(identifier)")
        }
    }

    @Test("the preferences are tried in order")
    func preferences() {
        #expect(StringCatalog.language(forPreferences: ["sw", "ru-RU", "de"]) == "ru")
        #expect(StringCatalog.language(forPreferences: ["sw"]) == "en")
        #expect(StringCatalog.language(forPreferences: []) == "en")
    }

    @Test("the standard language is the language of the app, not the languages of the device")
    func standardFollowsTheApp() {
        func language(app: [String], device: [String]) -> String {
            StringCatalog.standardLanguage(appLocalizations: app, devicePreferences: device)
        }
        // An app that is only in English shows English on a device set to Arabic, and so does its chart.
        #expect(language(app: ["en"], device: ["ar", "en"]) == "en")
        #expect(language(app: ["en"], device: ["ru-RU"]) == "en")
        // An app in a language of the package gets it, with a region or a script.
        #expect(language(app: ["ru"], device: ["en"]) == "ru")
        #expect(language(app: ["pt-BR"], device: ["ar"]) == "pt-BR")
        #expect(language(app: ["zh-Hans"], device: ["en"]) == "zh-Hans")
        #expect(language(app: ["de_AT"], device: ["en"]) == "de")
        // A language that the package does not have is English, not the next language of the device.
        #expect(language(app: ["ja"], device: ["ru", "de"]) == "en")
        // An app that declares no language is left to the preferences of the device.
        #expect(language(app: [], device: ["ar-AE", "en"]) == "ar")
        #expect(language(app: ["Base"], device: ["de-DE"]) == "de")
        #expect(language(app: [], device: ["sw"]) == "en")
        #expect(language(app: [], device: []) == "en")
    }

    @Test("the languages of the running process give a language the package has")
    func standardLanguageOfTheProcess() {
        #expect(StringCatalog.languages.contains(StringCatalog.standardLanguage()))
    }

    @Test("formats keep their arguments in every language", arguments: languages)
    func formats(language: String) {
        let strings = TradingChartStrings(language: language)
        let price = strings.format(strings.lastPrice, "120.50")
        #expect(price.contains("120.50") && !price.contains("%"))
        let range = strings.format(strings.showingRange, "START", "END")
        #expect(range.contains("START") && range.contains("END") && !range.contains("%"))
    }

    @Test("a host that changes single words keeps the rest in the language")
    func overridesKeepTheRest() {
        var strings = TradingChartStrings.localized(for: Locale(identifier: "ar"))
        let arabic = strings
        strings.volume = "Vol"
        strings.showingRange = "%2$@ <- %1$@"
        #expect(strings.volume == "Vol")
        #expect(strings.format(strings.showingRange, "a", "b") == "b <- a")
        #expect(strings.open == arabic.open)
        #expect(strings != arabic)
    }

    @Test("the style picker names its entries and itself in the language of the strings")
    func stylePicker() {
        let options = StylePickerOptions(titles: [.area: "Own"])
        for language in languages {
            let strings = TradingChartStrings(language: language)
            #expect(options.title(for: .line, strings: strings) == strings.lineStyle)
            #expect(options.title(for: .candles, strings: strings) == strings.candlesStyle)
            #expect(options.title(for: .area, strings: strings) == "Own")
        }
    }
}

/// The chart is not mirrored in a right-to-left language: the picture is the same whatever the layout direction of the host,
/// but for the words of the tooltip, which are laid out as the host reads.
///
/// `ImageRenderer` draws everything but the marks of Swift Charts (candles and lines come out as a placeholder, in the same
/// place every time): the axes, the legends, the badge, the crosshair and the tooltip are what is compared. The marks are
/// checked on the simulator.
@MainActor
@Suite("Chart in a right-to-left host", .serialized)
struct RightToLeftTests {
    private func makeModel(crosshair: Bool) -> TradingChartModel {
        let candles = (0..<200).map { index -> Candle in
            let phase = Double(index)
            let mid = 100 + 10 * sin(phase / 9)
            return Candle(
                time: date(baseTime + phase * 60), open: mid - 1, high: mid + 2, low: mid - 2, close: mid + 1,
                volume: 50 + 30 * abs(sin(phase / 5))
            )
        }
        let model = TradingChartModel(series: ChartSeries(candles: candles, interval: .minutes(1)), style: .candles)
        model.indicators = [SMA(period: 20), Volume()]
        model.currentPrice = candles.last?.close
        model.configuration.stylePicker = StylePickerOptions()
        if crosshair { model.crosshairTime = date(baseTime + 150 * 60) }
        return model
    }

    /// The chart as pixels, in a host with `direction`, the Arabic strings and a fixed locale.
    private func render(_ model: TradingChartModel, direction: LayoutDirection) throws -> Data {
        let view = TradingChartView(model: model)
            .tradingChartStrings(.localized(for: Locale(identifier: "ar")))
            .environment(\.layoutDirection, direction)
            .environment(\.colorScheme, .light)
            .padding(8)
            .background(Color.white)
            .frame(width: 393, height: 560)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.uiImage?.pngData())
    }

    // The pictures are compared as booleans: an expectation on two PNGs would print them, and a failure would take minutes.
    @Test("a right-to-left host gets the very picture a left-to-right one does: axes, scale, badge, legend")
    func notMirrored() throws {
        let model = makeModel(crosshair: false)
        let leftToRight = try render(model, direction: .leftToRight)
        let stable = try render(model, direction: .leftToRight) == leftToRight
        let same = try render(model, direction: .rightToLeft) == leftToRight
        #expect(stable, "the picture is not stable, so it cannot be compared")
        #expect(same, "a right-to-left host sees another picture")
    }

    @Test("with the crosshair the words of the tooltip follow the host")
    func tooltipFollowsTheHost() throws {
        let model = makeModel(crosshair: true)
        let leftToRight = try render(model, direction: .leftToRight)
        let rightToLeft = try render(model, direction: .rightToLeft)
        let differ = leftToRight != rightToLeft
        let stable = try render(model, direction: .leftToRight) == leftToRight
            && (try render(model, direction: .rightToLeft)) == rightToLeft
        #expect(differ, "the tooltip does not follow the host")
        #expect(stable, "the picture is not stable, so it cannot be compared")
    }
}
