import Foundation
import TradingChartCore

/// The records a chart saves: what they look like, under which keys, and how they are read back. Pure apart from the store.
///
/// Every record is a JSON object with a `version` and one field of its own. A record is read only when its version is the one
/// this code writes for its kind; anything else (damaged JSON, another shape, a newer version) reads as "nothing saved".
///
/// Each kind has a version of its own, so that a change of one format does not discard the other records. The records are
/// encoded with the `Codable` conformances of the model types (``SeriesStyle``, ``ChartDrawing``, ``DrawingStyle``,
/// ``ChartAnchor``, ``ChartColor``): a change to those that alters the JSON, or makes saved JSON unreadable, needs a new version
/// here, and the golden records in the tests fail until it is made.
@available(iOS 17.0, *)
enum ChartPersistenceRecords {

    /// The version of the style record that is written, and the only one that is read.
    static let styleVersion = 1
    /// The version of the indicators record that is written, and the only one that is read.
    static let indicatorsVersion = 1
    /// The version of a drawings record that is written, and the only one that is read.
    static let drawingsVersion = 1

    private struct Header: Decodable {
        var version: Int
    }

    private struct StyleRecord: Codable {
        var version: Int
        var style: SeriesStyle
    }

    private struct IndicatorsRecord: Codable {
        var version: Int
        var indicators: [String]
    }

    private struct DrawingsRecord: Codable {
        var version: Int
        var drawings: [ChartDrawing]
    }

    // MARK: - Coding

    static func encode(style: SeriesStyle) -> Data? {
        encode(StyleRecord(version: styleVersion, style: style))
    }

    static func decodeStyle(_ data: Data) -> SeriesStyle? {
        decode(StyleRecord.self, version: styleVersion, from: data)?.style
    }

    static func encode(indicatorIDs: [String]) -> Data? {
        encode(IndicatorsRecord(version: indicatorsVersion, indicators: indicatorIDs))
    }

    static func decodeIndicatorIDs(_ data: Data) -> [String]? {
        decode(IndicatorsRecord.self, version: indicatorsVersion, from: data)?.indicators
    }

    static func encode(drawings: [ChartDrawing]) -> Data? {
        encode(DrawingsRecord(version: drawingsVersion, drawings: drawings))
    }

    static func decodeDrawings(_ data: Data) -> [ChartDrawing]? {
        decode(DrawingsRecord.self, version: drawingsVersion, from: data)?.drawings
    }

    /// `nil` when the value cannot be encoded (a drawing with a price that is not a number, say): nothing is written then.
    private static func encode<Record: Encodable>(_ record: Record) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(record)
    }

    private static func decode<Record: Decodable>(_ type: Record.Type, version: Int, from data: Data) -> Record? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.version == version else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

@available(iOS 17.0, *)
extension ChartPersistence {

    // MARK: - Keys

    var styleStoreKey: String { "\(key).style" }
    var indicatorsStoreKey: String { "\(key).indicators" }

    /// Where the drawings of ``drawingsKey`` are kept; `nil` without a drawings key. Names the drawings as well as it names
    /// the place: the same ``drawingsKey`` in another namespace is other drawings.
    var drawingsStoreKey: String? { drawingsKey.map { "\(key).drawings.\($0)" } }

    // MARK: - Reading

    /// The saved style, when it is saved, readable and offered: the style picker, when there is one with styles, must list it.
    func restoredStyle(offeredBy picker: StylePickerOptions?) -> SeriesStyle? {
        guard persistsStyle,
              let data = store.load(forKey: styleStoreKey),
              let style = ChartPersistenceRecords.decodeStyle(data)
        else { return nil }
        if let picker, !picker.listedStyles.isEmpty, !picker.listedStyles.contains(style) { return nil }
        return style
    }

    /// The indicators of the catalog whose ids are saved, in the order of the catalog; `nil` when nothing readable is saved.
    func restoredIndicators() -> [any ChartIndicator]? {
        guard persistsIndicators,
              let data = store.load(forKey: indicatorsStoreKey),
              let ids = ChartPersistenceRecords.decodeIndicatorIDs(data)
        else { return nil }
        let wanted = Set(ids)
        var seen = Set<String>()
        return indicatorCatalog.filter { wanted.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// The drawings saved under ``drawingsKey``; `nil` without a key and when nothing readable is saved.
    func restoredDrawings() -> [ChartDrawing]? {
        guard let drawingsStoreKey, let data = store.load(forKey: drawingsStoreKey) else { return nil }
        return ChartPersistenceRecords.decodeDrawings(data)
    }

    // MARK: - Writing

    func save(style: SeriesStyle) {
        guard persistsStyle, let data = ChartPersistenceRecords.encode(style: style) else { return }
        store.save(data, forKey: styleStoreKey)
    }

    func save(indicators: [any ChartIndicator]) {
        guard persistsIndicators, let data = ChartPersistenceRecords.encode(indicatorIDs: indicators.map(\.id)) else { return }
        store.save(data, forKey: indicatorsStoreKey)
    }

    func save(drawings: [ChartDrawing]) {
        guard let drawingsStoreKey, let data = ChartPersistenceRecords.encode(drawings: drawings) else { return }
        store.save(data, forKey: drawingsStoreKey)
    }

    // MARK: - Comparing

    /// Whether `other` reads the style and the indicators from the same place the same way. The store is not compared (it cannot
    /// be), and neither is ``drawingsKey``, which the model handles on its own.
    func hasSameNamespace(as other: ChartPersistence) -> Bool {
        key == other.key
            && persistsStyle == other.persistsStyle
            && persistsIndicators == other.persistsIndicators
            && indicatorCatalog.map(\.id) == other.indicatorCatalog.map(\.id)
    }
}
