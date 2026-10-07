import Foundation

/// The translations of the package: `Resources/TradingChart.xcstrings`, which the build turns into one `TradingChart.strings` per
/// language in the resource bundle of the module. Looked up by language here, not by the preferences of the process, so that
/// an app with a language of its own can ask for it.
///
/// The table has a name of its own and is not `Localizable`: that is the table the compiler fills with the labels of Swift Charts
/// marks (`PlottableValue.value("Time", ...)`), and it would add them to a catalog called `Localizable` on every build.
@available(iOS 17.0, *)
enum StringCatalog {
    /// The resource bundle of the module.
    static let bundle = Bundle.module

    /// The name of the table (the file `TradingChart.xcstrings`).
    static let tableName = "TradingChart"

    /// The language that fills what another language lacks.
    static let baseLanguage = "en"

    /// The languages the bundle has strings for.
    static var languages: [String] {
        bundle.localizations.filter { $0 != "Base" }
    }

    /// The language to use for `preferences` (identifiers such as `ru`, `pt_BR`, `zh-Hans-CN`, best first): the first of them
    /// that the bundle has, English when none.
    static func language(forPreferences preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first ?? baseLanguage
    }

    /// The language the chart speaks when nobody asks for one: the language of the app, not of the device.
    ///
    /// The languages of the app are the ones its main bundle was localized to that best match the preferences of the user
    /// (`Bundle.main.preferredLocalizations`), so an app that is only in English gets English on a device set to Arabic, as the
    /// rest of its screens do. Only an app that declares no language at all (nothing but `Base`) is left to the preferences
    /// of the device. An app in a language the package does not have gets English, not the next language of the device.
    ///
    /// - Parameters:
    ///   - appLocalizations: The languages of the main bundle, best first.
    ///   - devicePreferences: The preferred languages of the device, best first.
    static func standardLanguage(
        appLocalizations: [String] = Bundle.main.preferredLocalizations,
        devicePreferences: [String] = Locale.preferredLanguages
    ) -> String {
        let declared = appLocalizations.filter { !$0.isEmpty && $0 != "Base" }
        return language(forPreferences: declared.isEmpty ? devicePreferences : declared)
    }

    #if DEBUG
    /// How many sets of strings were built on the current thread: what the tests count to see that nothing is rebuilt.
    static var buildsOnThisThread: Int {
        Thread.current.threadDictionary[buildsKey] as? Int ?? 0
    }

    static func noteBuild() {
        Thread.current.threadDictionary[buildsKey] = buildsOnThisThread + 1
    }

    private static let buildsKey = "TradingChart.StringCatalog.builds"
    #endif

    /// The strings of `language`, by key.
    static func table(for language: String) -> Table {
        Table(strings: strings(of: language), base: strings(of: baseLanguage))
    }

    /// The strings of one language, by key; a key that the language lacks falls back to English, and one that English lacks
    /// to the key itself.
    struct Table {
        let strings: [String: String]
        let base: [String: String]

        subscript(key: String) -> String {
            strings[key] ?? base[key] ?? key
        }
    }

    private static let cache = Cache()

    private static func strings(of language: String) -> [String: String] {
        cache.strings(of: language) {
            guard let url = bundle.url(forResource: tableName, withExtension: "strings", subdirectory: nil, localization: language),
                  let table = NSDictionary(contentsOf: url) as? [String: String]
            else { return [:] }
            return table
        }
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: [String: String]] = [:]

        func strings(of language: String, load: () -> [String: String]) -> [String: String] {
            lock.lock()
            defer { lock.unlock() }
            if let table = tables[language] { return table }
            let table = load()
            tables[language] = table
            return table
        }
    }
}
