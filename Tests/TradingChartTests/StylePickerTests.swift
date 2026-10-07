import SwiftUI
import Testing
import UIKit
import TradingChartCore
@testable import TradingChart

@Suite("Style picker")
struct StylePickerTests {
    @Test("the options offer all three styles by default, with the titles of the strings of the chart")
    func defaults() {
        let options = StylePickerOptions()
        #expect(options.availableStyles == [.line, .area, .candles])
        #expect(options.title(for: .line, strings: english) == "Line")
        #expect(options.title(for: .area, strings: english) == "Area")
        #expect(options.title(for: .candles, strings: english) == "Candles")
        #expect(options.accessibilityLabel == nil)
        let russian = TradingChartStrings.localized(for: Locale(identifier: "ru"))
        #expect(options.title(for: .candles, strings: russian) == "\u{0421}\u{0432}\u{0435}\u{0447}\u{0438}")  // the Russian "candles"
        #expect(options.title(for: .line) == TradingChartStrings.standard.lineStyle)
    }

    @Test("titles are replaced style by style, the others keep the default")
    func localisedTitles() {
        let options = StylePickerOptions(titles: [.candles: "Kerzen", .line: "Linie"], accessibilityLabel: "Diagrammstil")
        #expect(options.title(for: .candles, strings: english) == "Kerzen")
        #expect(options.title(for: .line, strings: english) == "Linie")
        #expect(options.title(for: .area, strings: english) == "Area")
        #expect(options.accessibilityLabel == "Diagrammstil")
    }

    @Test("a style that is listed twice is offered once, in the order of the first mention")
    func listedOnce() {
        let options = StylePickerOptions(availableStyles: [.candles, .line, .candles, .line])
        #expect(options.listedStyles == [.candles, .line])
        #expect(StylePickerOptions(availableStyles: []).listedStyles.isEmpty)
    }

    @Test("the options are Equatable and part of the configuration, which has none by default")
    func configuration() {
        #expect(TradingChartConfiguration().stylePicker == nil)
        var configuration = TradingChartConfiguration()
        configuration.stylePicker = StylePickerOptions(availableStyles: [.line, .candles])
        #expect(configuration.stylePicker == StylePickerOptions(availableStyles: [.line, .candles]))
        #expect(configuration.stylePicker != StylePickerOptions())
        #expect(TradingChartConfiguration(stylePicker: StylePickerOptions()).stylePicker != nil)
    }

    @MainActor
    @Test("every style has its own SF Symbol, and the symbols exist")
    func symbols() {
        let names = SeriesStyle.allCases.map(SeriesStylePicker.systemImage(for:))
        #expect(Set(names).count == SeriesStyle.allCases.count)
        for name in names {
            #expect(UIImage(systemName: name) != nil, "\(name) is not an SF Symbol")
        }
        #expect(SeriesStylePicker.systemImage(for: .line) == "chart.xyaxis.line")
        #expect(SeriesStylePicker.systemImage(for: .area) == "chart.line.uptrend.xyaxis")
        #expect(SeriesStylePicker.systemImage(for: .candles) == "chart.bar.xaxis")
    }

    @MainActor
    @Test("the picker is a tap target of 44 by 24 points, like the row it sits in")
    func size() throws {
        let model = TradingChartModel(series: makeSeries(count: 50), style: .line)
        let controller = UIHostingController(rootView: SeriesStylePicker(model: model))
        let size = controller.sizeThatFits(in: CGSize(width: 400, height: 400))
        #expect(size.width == SeriesStylePicker.size.width)
        #expect(size.height == SeriesStylePicker.size.height)

        let empty = UIHostingController(rootView: SeriesStylePicker(model: model, options: StylePickerOptions(availableStyles: [])))
        #expect(empty.sizeThatFits(in: CGSize(width: 400, height: 400)) == .zero)
    }

    @MainActor
    @Test("the legend row takes the whole width with or without overlay indicators, so the picker is at its right end")
    func rowFillsTheWidth() {
        let model = TradingChartModel(series: makeSeries(count: 50), style: .line)
        model.configuration.stylePicker = StylePickerOptions()
        let proposal = CGSize(width: 320, height: 400)

        let alone = UIHostingController(rootView: MainLegendRow(model: model))
        #expect(alone.sizeThatFits(in: proposal).width == proposal.width)

        model.indicators = [EchoIndicator()]
        let withLegend = UIHostingController(rootView: MainLegendRow(model: model))
        #expect(withLegend.sizeThatFits(in: proposal).width == proposal.width)
    }
}
