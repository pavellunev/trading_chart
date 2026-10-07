import Foundation
import TradingChartCore

/// Where a chart keeps what the user chose: the style, the indicators and the drawings (see ``ChartPersistence``).
///
/// A store holds opaque data under string keys. The chart writes small JSON records and never reads a key it did not write;
/// it ignores data it cannot read. Implement it to keep the records somewhere other than `UserDefaults` (a file, the keychain,
/// a database, an in-memory dictionary in a test). Both methods are called on the main actor, synchronously, and must not block
/// for long: the chart saves when the user changes something, never on every frame.
@available(iOS 17.0, *)
public protocol ChartPreferencesStore: Sendable {
    /// The data saved under `key`, or `nil` when there is none.
    func load(forKey key: String) -> Data?

    /// Saves `data` under `key`, replacing what was there.
    func save(_ data: Data, forKey key: String)
}

/// A ``ChartPreferencesStore`` backed by a `UserDefaults` suite.
@available(iOS 17.0, *)
public struct UserDefaultsChartPreferencesStore: ChartPreferencesStore, @unchecked Sendable {
    // `UserDefaults` is safe to use from any thread, but the SDK does not declare it `Sendable`.
    private let defaults: UserDefaults

    /// Creates a store.
    ///
    /// - Parameter defaults: The suite to keep the records in; `UserDefaults.standard` by default.
    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The data saved under `key`.
    public func load(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    /// Saves `data` under `key`.
    public func save(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// What a chart remembers between launches, and where.
///
/// Set it as ``TradingChartConfiguration/persistence`` and the model restores the style, the indicators and the drawings the
/// user left, and saves them again whenever they change. The host writes no code besides this one setting.
///
/// ```swift
/// var configuration = TradingChartConfiguration()
/// configuration.stylePicker = StylePickerOptions()
/// configuration.persistence = ChartPersistence(
///     key: "chart",
///     indicatorCatalog: catalog,                  // the catalog of the IndicatorBar
///     drawingsKey: symbol                         // nil: the drawings are not saved
/// )
/// let model = TradingChartModel(style: .candles, configuration: configuration)
/// ```
///
/// - **The key** is the namespace. Everything the chart saves is stored under keys that start with it, so one app can keep
///   several charts apart (`"trade.chart"`, `"detail.chart"`).
/// - **The catalog** brings the indicators back. Indicators are code, not data: what is saved is their ``ChartIndicator/id``s,
///   and the indicators are taken from ``indicatorCatalog`` (the one handed to ``IndicatorBar``), in the order of the catalog.
///   An id the catalog does not know is ignored.
/// - **The drawings** are saved under ``drawingsKey`` inside the namespace. Change ``drawingsKey`` when the chart shows another
///   instrument: the drawings on the chart are saved under the old key and the ones saved under the new key are loaded.
///
/// What is saved is a small versioned JSON record per kind of data. A record that is damaged, was written by a newer version of
/// the package or is not a record at all is ignored, and the next change overwrites it.
///
/// ## When it is read and written
///
/// The model reads the records when it is created with a persistence, and when ``TradingChartConfiguration/persistence`` is set
/// later (or its ``key``, flags or catalog change): what is saved replaces what the model holds, and what is not saved is left
/// as it is, so defaults that the host set before are kept. Creating the model and putting the saved values back write
/// nothing, with one exception: when ``drawingsKey`` changes, and when a persistence with another ``key``, flags or catalog
/// replaces this one, the drawings on the chart are first saved under the old ``drawingsKey``, so that they are not lost.
/// After that the model writes the style when ``TradingChartModel/style`` changes, the indicators when
/// ``TradingChartModel/indicators`` change, and the drawings when one is added, changed (at the end of a drag, not on every
/// step of it) or removed, or when ``TradingChartModel/drawings`` is assigned; nothing is written when a value is set to what
/// it already is.
@available(iOS 17.0, *)
public struct ChartPersistence: Sendable {
    /// The namespace of everything the chart saves. The style and the indicators are saved directly under it.
    public var key: String
    /// The indicators the saved ids are brought back from; the catalog of the ``IndicatorBar``. Where an id repeats, the first
    /// indicator is the one restored.
    public var indicatorCatalog: [any ChartIndicator]
    /// The key of the drawings inside the namespace of ``key``, for example the symbol on the chart; `nil` saves and restores no
    /// drawings.
    ///
    /// Changing it (``TradingChartModel/configuration`` is the place) saves the drawings that are on the chart under the old
    /// key, then shows the ones saved under the new key. When nothing is saved under the new key, the chart is emptied if its
    /// drawings belong to another key; drawings that belong to no key (the chart had none, and none was ever set) are kept and
    /// adopted by the first key. A drawing that is half placed is dropped, and the tool stays selected.
    ///
    /// Do not assign ``TradingChartModel/drawings`` (clearing them included) to prepare for the change: any assignment is saved
    /// under the old key and replaces what was saved there. Change the key instead.
    ///
    /// Setting it to `nil` stops saving and leaves the drawings on the chart as they are. They stay the old key's: another key
    /// set afterwards shows its own drawings, or an empty chart, and does not adopt them.
    public var drawingsKey: String?
    /// Whether ``TradingChartModel/style`` is saved and restored.
    public var persistsStyle: Bool
    /// Whether ``TradingChartModel/indicators`` are saved and restored.
    public var persistsIndicators: Bool
    /// Where the records are kept; the standard `UserDefaults` by default.
    ///
    /// The chart does not notice a different store on its own: it keeps writing to the new one but restores from it only when
    /// something else of the persistence changes.
    public var store: any ChartPreferencesStore

    /// Creates a persistence.
    ///
    /// - Parameters:
    ///   - key: The namespace of everything saved.
    ///   - indicatorCatalog: The indicators on offer, as given to ``IndicatorBar``.
    ///   - drawingsKey: The key of the drawings, such as the symbol; `nil` for none.
    ///   - persistsStyle: Whether the style is saved and restored.
    ///   - persistsIndicators: Whether the indicators are saved and restored.
    ///   - store: Where the records are kept.
    public init(
        key: String,
        indicatorCatalog: [any ChartIndicator],
        drawingsKey: String? = nil,
        persistsStyle: Bool = true,
        persistsIndicators: Bool = true,
        store: any ChartPreferencesStore = UserDefaultsChartPreferencesStore(.standard)
    ) {
        self.key = key
        self.indicatorCatalog = indicatorCatalog
        self.drawingsKey = drawingsKey
        self.persistsStyle = persistsStyle
        self.persistsIndicators = persistsIndicators
        self.store = store
    }
}
