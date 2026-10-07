import CoreGraphics
import Foundation
import Testing
import TradingChartCore
@testable import TradingChart

/// A store in memory that records every write, so that tests can count them.
final class MemoryStore: ChartPreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var written: [String] = []

    func load(forKey key: String) -> Data? {
        lock.withLock { values[key] }
    }

    func save(_ data: Data, forKey key: String) {
        lock.withLock {
            values[key] = data
            written.append(key)
        }
    }

    /// Puts data in without counting it as a write of the chart.
    func plant(_ data: Data, forKey key: String) {
        lock.withLock { values[key] = data }
    }

    func plant(_ json: String, forKey key: String) {
        plant(Data(json.utf8), forKey: key)
    }

    /// The keys written by `save`, in order.
    var writes: [String] { lock.withLock { written } }

    func writeCount(for key: String) -> Int { writes.filter { $0 == key }.count }

    /// The JSON object saved under `key`.
    func object(forKey key: String) -> [String: Any]? {
        load(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

private let catalog: [any ChartIndicator] = [
    SMA(period: 20), EMA(period: 50), BollingerBands(), Volume(movingAveragePeriod: 20), RSI(), MACD(),
]
private let smaID = "sma(20,close)"
private let emaID = "ema(50,close)"
private let rsiID = RSI().id
private let macdID = MACD().id

private let plot = CGRect(x: 0, y: 0, width: 300, height: 240)

private func persistence(
    _ store: MemoryStore,
    key: String = "chart",
    drawingsKey: String? = "BTC",
    persistsStyle: Bool = true,
    persistsIndicators: Bool = true
) -> ChartPersistence {
    ChartPersistence(
        key: key,
        indicatorCatalog: catalog,
        drawingsKey: drawingsKey,
        persistsStyle: persistsStyle,
        persistsIndicators: persistsIndicators,
        store: store
    )
}

@MainActor
private func makeModel(
    _ persistence: ChartPersistence?,
    style: SeriesStyle = .candles,
    picker: StylePickerOptions? = nil
) -> TradingChartModel {
    let configuration = TradingChartConfiguration(stylePicker: picker, persistence: persistence)
    let model = TradingChartModel(series: makeSeries(count: 200), style: style, configuration: configuration)
    model.currentPrice = model.series.lastValue
    return model
}

@MainActor
private func trendLine(_ model: TradingChartModel, from first: Double = 30, to second: Double = 10, price: Double = 270) -> ChartDrawing {
    let last = model.series.lastTime!
    return ChartDrawing(kind: .trendLine, anchors: [
        ChartAnchor(time: last.addingTimeInterval(-first * 60), price: price),
        ChartAnchor(time: last.addingTimeInterval(-second * 60), price: price + 15),
    ], style: DrawingStyle(color: ChartColor(red: 1, green: 0.5, blue: 0), lineWidth: 3, dash: [4, 2]), isLocked: true)
}

@MainActor
private func screenPoint(_ model: TradingChartModel, barsFromEnd: Double, price: Double) -> CGPoint {
    let time = model.series.lastTime!.addingTimeInterval(-barsFromEnd * model.series.interval.seconds)
    return model.drawingTransform(plot: plot).point(for: ChartAnchor(time: time, price: price))
}

@MainActor
@Suite("Persistence")
struct PersistenceTests {

    // MARK: - The API

    @Test("a persistence saves everything by default except the drawings, and the configuration has none")
    func defaults() {
        let value = ChartPersistence(key: "k", indicatorCatalog: [])
        #expect(value.key == "k")
        #expect(value.drawingsKey == nil)
        #expect(value.persistsStyle)
        #expect(value.persistsIndicators)
        #expect(TradingChartConfiguration().persistence == nil)
        #expect(TradingChartConfiguration(persistence: value).persistence?.key == "k")
    }

    @Test("the records are versioned JSON under keys of the namespace")
    func recordFormat() throws {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        model.style = .area
        model.indicators = [catalog[0], catalog[4]]
        model.drawings = [trendLine(model)]

        let style = try #require(store.object(forKey: "chart.style"))
        #expect(style["version"] as? Int == 1)
        #expect(style["style"] as? String == "area")
        let indicators = try #require(store.object(forKey: "chart.indicators"))
        #expect(indicators["version"] as? Int == 1)
        #expect(indicators["indicators"] as? [String] == [smaID, rsiID])
        let drawings = try #require(store.object(forKey: "chart.drawings.BTC"))
        #expect(drawings["version"] as? Int == 1)
        #expect((drawings["drawings"] as? [Any])?.count == 1)
        #expect(Set(store.writes) == ["chart.style", "chart.indicators", "chart.drawings.BTC"])
    }

    // MARK: - Style

    @Test("the style survives a restart, and it is the saved one and not the default that the window is built for")
    func styleRoundTrip() {
        let store = MemoryStore()
        let first = makeModel(persistence(store), style: .candles)
        first.style = .line

        let second = makeModel(persistence(store), style: .candles)
        #expect(second.style == .line)

        // The same window as a model that was made with that style, from the first frame.
        let reference = makeModel(nil, style: .line)
        #expect(second.visibleBars == reference.visibleBars)
        #expect(second.scrollPosition == reference.scrollPosition)
        #expect(second.renderWindow == reference.renderWindow)
        #expect(second.mainYBase == reference.mainYBase)
        #expect(second.mainYTarget == reference.mainYTarget)
        #expect(second.xTicks == reference.xTicks)
        #expect(second.isAtLiveEdge)
    }

    @Test("with nothing saved the style is the one given to the model, and nothing is written until it changes")
    func firstLaunch() {
        let store = MemoryStore()
        let model = makeModel(persistence(store), style: .area)
        #expect(model.style == .area)
        #expect(model.indicators.isEmpty)
        #expect(model.drawings.isEmpty)
        #expect(store.writes.isEmpty)
    }

    @Test("a saved style that the style picker does not offer is not restored")
    func styleOutsideThePicker() {
        let store = MemoryStore()
        makeModel(persistence(store)).style = .area

        let narrow = StylePickerOptions(availableStyles: [.line, .candles])
        #expect(makeModel(persistence(store), style: .candles, picker: narrow).style == .candles)
        let wide = StylePickerOptions(availableStyles: [.area, .candles])
        #expect(makeModel(persistence(store), style: .candles, picker: wide).style == .area)
        #expect(makeModel(persistence(store), style: .candles, picker: nil).style == .area)
        // A picker with no styles shows nothing, so it restricts nothing.
        #expect(makeModel(persistence(store), style: .candles, picker: StylePickerOptions(availableStyles: [])).style == .area)
        #expect(store.writeCount(for: "chart.style") == 1)  // refusing to restore did not touch the record
    }

    @Test("persistsStyle off saves nothing and restores nothing")
    func styleSwitchedOff() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, persistsStyle: false))
        model.style = .line
        #expect(store.writeCount(for: "chart.style") == 0)

        store.plant(#"{"version":1,"style":"area"}"#, forKey: "chart.style")
        #expect(makeModel(persistence(store, persistsStyle: false), style: .candles).style == .candles)
    }

    // MARK: - Indicators

    @Test("the indicators come back from the catalog, in the order of the catalog, and are calculated before the first frame")
    func indicatorsRoundTrip() {
        let store = MemoryStore()
        let first = makeModel(persistence(store))
        first.indicators = [catalog[4], catalog[0], catalog[5]]  // RSI, SMA, MACD: not the order of the catalog

        let second = makeModel(persistence(store))
        #expect(second.indicators.map(\.id) == [smaID, rsiID, macdID])
        #expect(second.output(for: smaID) != nil)
        #expect(second.output(for: rsiID) != nil)
        #expect(second.renderData.outputs.keys.contains(macdID))

        // As a model that had them from the start.
        let reference = makeModel(nil)
        reference.indicators = [catalog[0], catalog[4], catalog[5]]
        #expect(second.renderData.paletteBases == reference.renderData.paletteBases)
        #expect(second.mainYTarget == reference.mainYTarget)
        #expect(second.renderWindow == reference.renderWindow)
        #expect(Set(second.paneStates.keys) == Set(reference.paneStates.keys))
    }

    @Test("the restored indicators are the instances of the catalog, with the parameters the host gave them")
    func indicatorsAreTheCatalogsOwn() throws {
        let store = MemoryStore()
        let tuned = SMA(period: 20, style: IndicatorLineStyle(color: ChartColor(red: 1, green: 0, blue: 0)))
        let value = ChartPersistence(key: "chart", indicatorCatalog: [tuned], store: store)
        store.plant(#"{"version":1,"indicators":["sma(20,close)"]}"#, forKey: "chart.indicators")
        let model = makeModel(value)
        let restored = try #require(model.indicators.first as? SMA)
        #expect(restored.style.color == tuned.style.color)
    }

    @Test("an id that the catalog does not know is ignored, and a repeated one is taken once")
    func unknownIDs() {
        let store = MemoryStore()
        store.plant(#"{"version":1,"indicators":["nope(1)", "\#(rsiID)", "\#(smaID)", "\#(rsiID)"]}"#, forKey: "chart.indicators")
        #expect(makeModel(persistence(store)).indicators.map(\.id) == [smaID, rsiID])

        // A catalog that repeats an id restores the first one.
        let twice = ChartPersistence(key: "chart", indicatorCatalog: [SMA(period: 20), SMA(period: 20)], store: store)
        #expect(makeModel(twice).indicators.count == 1)
    }

    @Test("a list that repeats an id is cut and written once, and not at all when the ids stay as they were")
    func repeatedIDs() {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        model.indicators = [catalog[0]]
        #expect(store.writeCount(for: "chart.indicators") == 1)

        model.indicators = [catalog[0], catalog[0]]
        #expect(model.indicators.map(\.id) == [smaID])
        #expect(store.writeCount(for: "chart.indicators") == 1)

        model.indicators = [catalog[0], catalog[0], catalog[4]]
        #expect(model.indicators.map(\.id) == [smaID, rsiID])
        #expect(store.writeCount(for: "chart.indicators") == 2)
        #expect(store.object(forKey: "chart.indicators")?["indicators"] as? [String] == [smaID, rsiID])
    }

    @Test("an empty selection is saved as such, and restored over the defaults of a model that was set up before")
    func emptySelection() {
        let store = MemoryStore()
        let first = makeModel(persistence(store))
        first.indicators = [catalog[0]]
        first.indicators = []
        #expect(store.object(forKey: "chart.indicators")?["indicators"] as? [String] == [])

        let second = makeModel(nil)
        second.indicators = [catalog[0], catalog[1]]
        second.configuration.persistence = persistence(store)
        #expect(second.indicators.isEmpty)
    }

    @Test("persistsIndicators off saves nothing and restores nothing")
    func indicatorsSwitchedOff() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, persistsIndicators: false))
        model.indicators = [catalog[0]]
        #expect(store.writeCount(for: "chart.indicators") == 0)

        store.plant(#"{"version":1,"indicators":["\#(smaID)"]}"#, forKey: "chart.indicators")
        #expect(makeModel(persistence(store, persistsIndicators: false)).indicators.isEmpty)
    }

    // MARK: - Drawings

    @Test("drawings, with their style and lock, survive a restart")
    func drawingsRoundTrip() {
        let store = MemoryStore()
        let first = makeModel(persistence(store))
        let line = trendLine(first)
        let horizontal = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: first.series.lastTime!, price: 280)])
        first.drawings = [line, horizontal]

        let second = makeModel(persistence(store))
        #expect(second.drawings == [line, horizontal])
        #expect(second.selectedDrawingID == nil)
    }

    @Test("drawings made by touch are saved when they are added")
    func drawingByTouch() throws {
        let store = MemoryStore()
        let first = makeModel(persistence(store))
        first.activeDrawingTool = .trendLine
        first.drawingTap(at: screenPoint(first, barsFromEnd: 20, price: 280), plot: plot)
        #expect(store.writeCount(for: "chart.drawings.BTC") == 0)  // one anchor is not a drawing yet
        first.drawingTap(at: screenPoint(first, barsFromEnd: 5, price: 285), plot: plot)
        #expect(store.writeCount(for: "chart.drawings.BTC") == 1)

        let second = makeModel(persistence(store))
        #expect(second.drawings == first.drawings)
        #expect(second.drawings.count == 1)
    }

    @Test("drawings are written when one is added, changed at the end of a drag or removed, and on no other step")
    func drawingWrites() throws {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        let line = ChartDrawing(kind: .trendLine, anchors: [
            ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-30 * 60), price: 270),
            ChartAnchor(time: model.series.lastTime!.addingTimeInterval(-10 * 60), price: 285),
        ])
        model.drawings = [line]
        model.selectedDrawingID = line.id
        #expect(store.writeCount(for: "chart.drawings.BTC") == 1)  // the host's assignment

        // A drag is saved once, when the finger lifts.
        let start = model.drawingTransform(plot: plot).point(for: line.anchors[1])
        #expect(model.drawingBeginDrag(at: start, plot: plot))
        for step in 1...20 {
            model.drawingContinueDrag(to: screenPoint(model, barsFromEnd: 10 - Double(step) / 4, price: 285 + Double(step)), plot: plot)
        }
        #expect(store.writeCount(for: "chart.drawings.BTC") == 1)
        model.drawingEndDrag()
        #expect(store.writeCount(for: "chart.drawings.BTC") == 2)
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == model.drawings)

        // A drag that moved nothing is not a change.
        #expect(model.drawingBeginDrag(at: model.drawingTransform(plot: plot).point(for: model.drawings[0].anchors[0]), plot: plot))
        model.drawingEndDrag()
        #expect(store.writeCount(for: "chart.drawings.BTC") == 2)

        // A selection is not saved.
        model.selectedDrawingID = nil
        model.selectedDrawingID = line.id
        #expect(store.writeCount(for: "chart.drawings.BTC") == 2)

        model.removeDrawing(id: line.id)
        #expect(store.writeCount(for: "chart.drawings.BTC") == 3)
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [])
        model.removeDrawing(id: line.id)  // already gone
        #expect(store.writeCount(for: "chart.drawings.BTC") == 3)
    }

    @Test("deleting every drawing is one write, and so is deleting the selected one")
    func removalWrites() {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        let drawings = (0..<3).map { index in
            ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 270 + Double(index))])
        }
        model.drawings = drawings
        let before = store.writeCount(for: "chart.drawings.BTC")

        model.removeAllDrawings()
        #expect(store.writeCount(for: "chart.drawings.BTC") == before + 1)
        #expect(makeModel(persistence(store)).drawings.isEmpty)

        model.drawings = drawings
        model.selectedDrawingID = drawings[1].id
        model.deleteSelectedDrawing()
        #expect(makeModel(persistence(store)).drawings == [drawings[0], drawings[2]])
    }

    @Test("a record is not rewritten for a value that is already there")
    func noRedundantWrites() {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        model.style = .line
        model.indicators = [SMA(period: 20)]
        model.drawings = [trendLine(model)]
        let writes = store.writes

        model.style = .line
        model.indicators = [SMA(period: 20)]
        model.drawings = model.drawings
        model.removeAllDrawings()
        model.removeAllDrawings()  // nothing to remove
        #expect(store.writes == writes + ["chart.drawings.BTC"])
    }

    @Test("without a drawings key the drawings are neither saved nor restored")
    func noDrawingsKey() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: nil))
        model.drawings = [trendLine(model)]
        model.activeDrawingTool = .horizontalLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 3, price: 280), plot: plot)
        #expect(model.drawings.count == 2)
        #expect(store.writes.isEmpty)
        #expect(makeModel(persistence(store, drawingsKey: nil)).drawings.isEmpty)
    }

    @Test("changing the drawings key saves the drawings on the chart under the old key and shows the ones of the new key")
    func switchingTheDrawingsKey() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: "BTC"))
        let btc = trendLine(model)
        model.drawings = [btc]
        model.selectedDrawingID = btc.id

        // Nothing is saved for ETH: the chart shows none of BTC's.
        model.configuration.persistence?.drawingsKey = "ETH"
        #expect(model.drawings.isEmpty)
        #expect(model.selectedDrawingID == nil)
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [btc])

        let eth = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 281)])
        model.drawings = [eth]
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.ETH")!) == [eth])
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [btc])  // untouched

        model.configuration.persistence?.drawingsKey = "BTC"
        #expect(model.drawings == [btc])
        model.configuration.persistence?.drawingsKey = "ETH"
        #expect(model.drawings == [eth])

        // Switching writes nothing but the flush of what was on the chart under the key it leaves: BTC's drawings were written
        // by the assignment, and by the flushes when leaving it (twice).
        #expect(store.writeCount(for: "chart.drawings.BTC") == 3)
    }

    @Test("a drawings key set later restores the drawings saved under it, and adopts the ones on the chart when none are saved")
    func drawingsKeySetLater() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: nil))
        let own = trendLine(model)
        model.drawings = [own]

        model.configuration.persistence?.drawingsKey = "BTC"
        #expect(model.drawings == [own])  // adopted: they belonged to no key
        #expect(store.writes.isEmpty)  // and saved with the next change

        let saved = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 275)])
        store.plant(ChartPersistenceRecords.encode(drawings: [saved])!, forKey: "chart.drawings.ETH")
        model.configuration.persistence?.drawingsKey = "ETH"
        #expect(model.drawings == [saved])
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [own])  // saved when it left

        // Back to no key: the drawings stay on the chart and nothing more is written.
        let writes = store.writes
        model.configuration.persistence?.drawingsKey = nil
        #expect(model.drawings == [saved])
        model.drawings = []
        #expect(store.writes == writes + ["chart.drawings.ETH"])  // the flush of leaving ETH, and no write for the assignment
    }

    @Test("the drawings of one symbol are not adopted by another through a key that was nil in between")
    func noLeakThroughNilKey() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: "BTC"))
        let btc = trendLine(model)
        model.drawings = [btc]

        model.configuration.persistence?.drawingsKey = nil
        #expect(model.drawings == [btc])  // they stay on the chart
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [btc])

        model.configuration.persistence?.drawingsKey = "ETH"
        #expect(model.drawings.isEmpty)
        #expect(store.load(forKey: "chart.drawings.ETH") == nil)  // ETH got nothing of BTC's
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [btc])

        model.configuration.persistence?.drawingsKey = "BTC"
        #expect(model.drawings == [btc])
    }

    @Test("the same when the persistence is taken away and a persistence of another symbol comes")
    func noLeakThroughNoPersistence() {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: "BTC"))
        let btc = trendLine(model)
        model.drawings = [btc]

        model.configuration.persistence = nil
        #expect(model.drawings == [btc])
        model.configuration.persistence = persistence(store, drawingsKey: "ETH")
        #expect(model.drawings.isEmpty)
        #expect(store.load(forKey: "chart.drawings.ETH") == nil)
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [btc])

        // The key that was shown before is not another one: what is on the chart stays when nothing is saved for it.
        model.configuration.persistence = nil
        let eth = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 281)])
        model.drawings = [eth]
        model.configuration.persistence = persistence(store, drawingsKey: "ETH")
        #expect(model.drawings == [eth])
    }

    @Test("drawings that belong to no key are adopted by the first key, and belong to it from then on")
    func adoption() {
        let store = MemoryStore()
        let model = makeModel(nil)
        let own = trendLine(model)
        model.drawings = [own]

        model.configuration.persistence = persistence(store, drawingsKey: "BTC")
        #expect(model.drawings == [own])
        #expect(store.writes.isEmpty)

        let more = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 281)])
        model.drawings = [own, more]
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [own, more])

        model.configuration.persistence?.drawingsKey = "ETH"  // they are BTC's now
        #expect(model.drawings.isEmpty)
    }

    @Test("a drawing that is half placed does not survive a change of the drawings key, and the tool stays")
    func halfPlacedDrawing() throws {
        let store = MemoryStore()
        let model = makeModel(persistence(store, drawingsKey: "BTC"))
        model.activeDrawingTool = .trendLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 20, price: 280), plot: plot)
        let btcAnchor = try #require(model.drawingEditor.pendingAnchors.first)

        model.configuration.persistence?.drawingsKey = "ETH"
        #expect(model.drawingEditor.pendingAnchors.isEmpty)
        #expect(model.activeDrawingTool == .trendLine)

        // The next tap is the first anchor of a new drawing, not the second one of the old.
        model.drawingTap(at: screenPoint(model, barsFromEnd: 5, price: 285), plot: plot)
        #expect(model.drawings.isEmpty)
        #expect(store.writeCount(for: "chart.drawings.ETH") == 0)
        model.drawingTap(at: screenPoint(model, barsFromEnd: 2, price: 290), plot: plot)
        let added = try #require(model.drawings.first)
        #expect(model.drawings.count == 1)
        #expect(!added.anchors.contains(btcAnchor))
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.ETH")!) == [added])
        #expect(ChartPersistenceRecords.decodeDrawings(store.load(forKey: "chart.drawings.BTC")!) == [])
    }

    @Test("a change of the configuration that leaves the drawings key alone keeps a half placed drawing")
    func halfPlacedDrawingKept() {
        let model = makeModel(persistence(MemoryStore(), drawingsKey: "BTC"))
        model.activeDrawingTool = .trendLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 20, price: 280), plot: plot)
        model.configuration.paneHeight = 130
        #expect(model.drawingEditor.pendingAnchors.count == 1)
    }

    // MARK: - Reading what is not ours

    @Test("damaged, foreign or newer records are ignored, and the next change overwrites them", arguments: [
        "",
        "not json",
        "[1, 2, 3]",
        "{}",
        #"{"version":1}"#,
        #"{"version":2,"style":"line","indicators":["sma(20,close)"],"drawings":[]}"#,
        #"{"version":"1","style":"line","indicators":["sma(20,close)"],"drawings":[]}"#,
        #"{"version":1,"style":"zigzag","indicators":[1,2],"drawings":[{"id":"x"}]}"#,
        #"{"style":"line","indicators":["sma(20,close)"],"drawings":[]}"#,
    ])
    func brokenData(json: String) {
        let store = MemoryStore()
        for key in ["chart.style", "chart.indicators", "chart.drawings.BTC"] { store.plant(json, forKey: key) }
        let model = makeModel(persistence(store), style: .area)
        #expect(model.style == .area)
        #expect(model.indicators.isEmpty)
        #expect(model.drawings.isEmpty)
        #expect(store.writes.isEmpty)

        model.style = .line
        model.indicators = [catalog[0]]
        model.drawings = [trendLine(model)]
        let again = makeModel(persistence(store))
        #expect(again.style == .line)
        #expect(again.indicators.map(\.id) == [smaID])
        #expect(again.drawings.count == 1)
    }

    @Test("data that is not data at all, in a store that holds other things, is ignored")
    func foreignValues() {
        let suite = "TradingChartPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("a string", forKey: "chart.style")
        defaults.set(42, forKey: "chart.indicators")
        let value = ChartPersistence(key: "chart", indicatorCatalog: catalog, store: UserDefaultsChartPreferencesStore(defaults))
        let model = makeModel(value, style: .area)
        #expect(model.style == .area)
        #expect(model.indicators.isEmpty)
    }

    @Test("a drawing that cannot be encoded is not saved, and does not stop the chart")
    func unencodableDrawing() {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        model.drawings = [ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: .nan)])]
        #expect(model.drawings.count == 1)
        #expect(store.writes.isEmpty)
    }

    // MARK: - The format

    // The exact text of what is saved. These tests pin the JSON that the `Codable` conformances of the model types produce: if
    // one fails, data that users have already saved may be unreadable or different. Change the format only with a new version
    // of the record (`ChartPersistenceRecords`), and keep reading the old one.

    @Test("the style record is pinned")
    func styleRecordIsPinned() {
        let golden = #"{"style":"candles","version":1}"#
        #expect(ChartPersistenceRecords.styleVersion == 1)
        #expect(String(decoding: ChartPersistenceRecords.encode(style: .candles)!, as: UTF8.self) == golden)
        #expect(ChartPersistenceRecords.decodeStyle(Data(golden.utf8)) == .candles)
        for style in SeriesStyle.allCases {
            #expect(ChartPersistenceRecords.decodeStyle(Data(#"{"style":"\#(style.rawValue)","version":1}"#.utf8)) == style)
        }
    }

    @Test("the indicators record is pinned")
    func indicatorsRecordIsPinned() {
        let golden = #"{"indicators":["sma(20,close)","ema(50,close)"],"version":1}"#
        #expect(ChartPersistenceRecords.indicatorsVersion == 1)
        #expect(String(decoding: ChartPersistenceRecords.encode(indicatorIDs: [smaID, emaID])!, as: UTF8.self) == golden)
        #expect(ChartPersistenceRecords.decodeIndicatorIDs(Data(golden.utf8)) == [smaID, emaID])
    }

    @Test("the drawings record is pinned: keys, the UUID, the colour, the dash and the date (seconds since 2001-01-01)")
    func drawingsRecordIsPinned() {
        let trend = ChartDrawing(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            kind: .trendLine,
            anchors: [
                ChartAnchor(time: Date(timeIntervalSince1970: 1_700_000_000), price: 270),
                ChartAnchor(time: Date(timeIntervalSince1970: 1_700_000_600), price: 285.5),
            ],
            style: DrawingStyle(color: ChartColor(red: 1, green: 0.5, blue: 0, opacity: 0.25), lineWidth: 3, dash: [4, 2]),
            isLocked: true
        )
        let horizontal = ChartDrawing(
            id: UUID(uuidString: "0A5B1C2D-3E4F-4A6B-8C7D-9E0F1A2B3C4D")!,
            kind: .horizontalLine,
            anchors: [ChartAnchor(time: Date(timeIntervalSince1970: 1_700_000_000), price: 281.25)]
        )
        let golden = #"{"drawings":["#
            + #"{"anchors":[{"price":270,"time":721692800},{"price":285.5,"time":721693400}],"#
            + #""id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","isLocked":true,"kind":"trendLine","#
            + #""style":{"color":{"blue":0,"green":0.5,"opacity":0.25,"red":1},"dash":[4,2],"lineWidth":3}},"#
            + #"{"anchors":[{"price":281.25,"time":721692800}],"#
            + #""id":"0A5B1C2D-3E4F-4A6B-8C7D-9E0F1A2B3C4D","isLocked":false,"kind":"horizontalLine","#
            + #""style":{"dash":[],"lineWidth":1.5}}],"version":1}"#
        #expect(ChartPersistenceRecords.drawingsVersion == 1)
        #expect(String(decoding: ChartPersistenceRecords.encode(drawings: [trend, horizontal])!, as: UTF8.self) == golden)
        #expect(ChartPersistenceRecords.decodeDrawings(Data(golden.utf8)) == [trend, horizontal])
    }

    @Test("a record is read only on the version of its own kind")
    func versionsAreOfTheirOwnKind() {
        let store = MemoryStore()
        store.plant(#"{"style":"area","version":1}"#, forKey: "chart.style")
        store.plant(#"{"indicators":["\#(smaID)"],"version":2}"#, forKey: "chart.indicators")
        store.plant(#"{"drawings":[],"version":2}"#, forKey: "chart.drawings.BTC")
        let model = makeModel(persistence(store), style: .candles)
        #expect(model.style == .area)
        #expect(model.indicators.isEmpty)
        #expect(model.drawings.isEmpty)
    }

    // MARK: - The standard store

    @Test("UserDefaults keep the records, and the standard store is the default")
    func userDefaultsStore() {
        let suite = "TradingChartPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsChartPreferencesStore(defaults)
        #expect(store.load(forKey: "a") == nil)
        store.save(Data("x".utf8), forKey: "a")
        #expect(store.load(forKey: "a") == Data("x".utf8))
        #expect(defaults.data(forKey: "a") == Data("x".utf8))

        let value = ChartPersistence(key: "chart", indicatorCatalog: catalog, store: store)
        makeModel(value).style = .line
        #expect(makeModel(value, style: .candles).style == .line)
        #expect(ChartPersistence(key: "k", indicatorCatalog: []).store is UserDefaultsChartPreferencesStore)
    }

    // MARK: - Setting it later, and taking it away

    @Test("set later, it restores what is saved and keeps what is not, and writes nothing")
    func setLater() {
        let store = MemoryStore()
        store.plant(#"{"version":1,"style":"area"}"#, forKey: "chart.style")
        let model = makeModel(nil, style: .line)
        model.indicators = [catalog[0]]  // the host's own defaults

        model.configuration.persistence = persistence(store)
        #expect(model.style == .area)
        #expect(model.indicators.map(\.id) == [smaID])  // nothing saved for them: the defaults stay
        #expect(store.writes.isEmpty)

        // From now on a change is saved.
        model.indicators = []
        #expect(store.writes == ["chart.indicators"])
    }

    @Test("a style and indicators restored together are one update of the render state, not two")
    func restoreIsOneBatch() {
        let store = MemoryStore()
        store.plant(#"{"version":1,"style":"area"}"#, forKey: "chart.style")
        store.plant(#"{"version":1,"indicators":["\#(emaID)","\#(rsiID)"]}"#, forKey: "chart.indicators")
        let model = makeModel(nil, style: .line)

        // What any change of the configuration costs: the viewport inputs are looked at in one batch.
        var plain = model.configuration
        plain.paneHeight += 1
        let revision = model.renderRevision
        model.configuration = plain
        let baseline = model.renderRevision - revision

        let before = model.renderRevision
        var restoring = model.configuration
        restoring.persistence = persistence(store)
        model.configuration = restoring
        #expect(model.style == .area)
        #expect(model.indicators.map(\.id) == [emaID, rsiID])
        #expect(model.renderRevision - before == baseline + 1)
    }

    @Test("set later, saved indicators and drawings replace the ones on the chart")
    func setLaterReplaces() {
        let store = MemoryStore()
        store.plant(#"{"version":1,"indicators":["\#(emaID)"]}"#, forKey: "chart.indicators")
        let model = makeModel(nil)
        model.indicators = [catalog[0]]
        model.drawings = [trendLine(model)]
        let saved = ChartDrawing(kind: .horizontalLine, anchors: [ChartAnchor(time: model.series.lastTime!, price: 272)])
        store.plant(ChartPersistenceRecords.encode(drawings: [saved])!, forKey: "chart.drawings.BTC")

        model.configuration.persistence = persistence(store)
        #expect(model.indicators.map(\.id) == [emaID])
        #expect(model.drawings == [saved])
        #expect(store.writes.isEmpty)
    }

    @Test("a persistence that is taken away stops saving, and a configuration change that leaves it alone restores nothing")
    func takenAwayAndLeftAlone() {
        let store = MemoryStore()
        let model = makeModel(persistence(store))
        model.style = .line

        model.configuration.paneHeight = 120  // unrelated: the user's style must not be put back
        model.style = .area
        model.configuration.showsLegend = false
        #expect(model.style == .area)
        #expect(store.writeCount(for: "chart.style") == 2)

        model.configuration.persistence = nil
        model.style = .candles
        model.indicators = [catalog[0]]
        model.drawings = [trendLine(model)]
        model.activeDrawingTool = .horizontalLine
        model.drawingTap(at: screenPoint(model, barsFromEnd: 3, price: 280), plot: plot)
        #expect(store.writes == ["chart.style", "chart.style"])
        #expect(makeModel(persistence(store)).style == .area)
    }

    @Test("another key is another namespace: the chart restores from it")
    func anotherNamespace() {
        let store = MemoryStore()
        let trade = makeModel(persistence(store, key: "trade"))
        trade.style = .line
        trade.indicators = [catalog[0]]
        let detail = makeModel(persistence(store, key: "detail"), style: .area)
        #expect(detail.style == .area)
        #expect(detail.indicators.isEmpty)
        detail.style = .candles

        #expect(makeModel(persistence(store, key: "trade")).style == .line)
        #expect(makeModel(persistence(store, key: "detail")).style == .candles)

        // Moving a chart to the other namespace shows what is saved there.
        trade.configuration.persistence = persistence(store, key: "detail")
        #expect(trade.style == .candles)
        #expect(trade.indicators.map(\.id) == [smaID])  // nothing saved in "detail": kept
        #expect(store.object(forKey: "trade.style")?["style"] as? String == "line")
    }

    @Test("a catalog that gains an indicator restores it from the saved ids")
    func catalogChange() {
        let store = MemoryStore()
        store.plant(#"{"version":1,"indicators":["\#(smaID)","\#(rsiID)"]}"#, forKey: "chart.indicators")
        let small = ChartPersistence(key: "chart", indicatorCatalog: [SMA(period: 20)], store: store)
        let model = makeModel(small)
        #expect(model.indicators.map(\.id) == [smaID])
        #expect(store.writes.isEmpty)

        model.configuration.persistence = persistence(store)
        #expect(model.indicators.map(\.id) == [smaID, rsiID])
    }
}
