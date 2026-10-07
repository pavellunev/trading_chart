import TradingChartCore

/// Turns indicator and line names into the short upper-case labels of the legend. Pure.
@available(iOS 17.0, *)
enum LegendNaming {
    private static let abbreviations: [String: String] = [
        "volume": "VOL",
        "upper": "UP",
        "middle": "MB",
        "lower": "DN",
        "histogram": "HIST",
    ]

    /// `SMA 20` becomes `SMA(20)`, `BB 20 2` becomes `BB(20,2)`, `SMA 20 hl2` becomes `SMA(20,hl2)`; a name without
    /// parameters is shortened (`Volume` is `VOL`) or upper-cased. A name whose tail is not made of numbers and
    /// price sources (`My Indicator`) is returned as it is.
    static func title(for name: String) -> String {
        let tokens = name.split(separator: " ").map(String.init)
        guard let word = tokens.first else { return name }
        if tokens.count == 1 { return abbreviation(of: word) }
        let parameters = tokens.dropFirst()
        guard parameters.allSatisfy(isParameter) else { return name }
        return abbreviation(of: word) + "(" + parameters.joined(separator: ",") + ")"
    }

    /// Whether `name` is a word followed by parameters, like `SMA 20`.
    static func hasParameters(_ name: String) -> Bool {
        let tokens = name.split(separator: " ")
        return tokens.count > 1 && tokens.dropFirst().allSatisfy { isParameter(String($0)) }
    }

    /// The label of a line or histogram of an indicator: its name without the name of the indicator
    /// (`BB Upper` of `BB 20 2` is `UP`, `Volume MA 20` of `Volume` is `MA(20)`); when nothing remains,
    /// the label of the indicator itself (`Volume` is `VOL`, `MACD` is `MACD`).
    static func elementLabel(valueName: String, indicatorName: String) -> String {
        let word = indicatorName.split(separator: " ").first.map(String.init) ?? indicatorName
        var rest = valueName
        if valueName == word {
            rest = ""
        } else if valueName.hasPrefix(word + " ") {
            rest = String(valueName.dropFirst(word.count + 1))
        }
        return title(for: rest.isEmpty ? word : rest)
    }

    private static func abbreviation(of word: String) -> String {
        abbreviations[word.lowercased()] ?? word.uppercased()
    }

    private static func isParameter(_ token: String) -> Bool {
        Double(token) != nil || PriceSource(rawValue: token) != nil
    }
}
