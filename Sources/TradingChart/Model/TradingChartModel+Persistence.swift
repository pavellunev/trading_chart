import Foundation
import TradingChartCore

// What the chart remembers between launches: reads ``ChartPersistence`` when it is set and writes when the user changes
// something. The records and their keys are in `ChartPersistenceRecords`; the model only decides when to read and to write.
// Nothing is written while the saved values are put back, and nothing on a change that changes nothing.

@available(iOS 17.0, *)
extension TradingChartModel {

    /// ``configuration`` was assigned: restores from a persistence that is new, or that reads another place than the one it
    /// replaced, and switches the drawings when only their key changed. Changes that leave the persistence as it was do
    /// nothing.
    func persistenceDidChange(from old: ChartPersistence?) {
        guard let new = configuration.persistence else { return }
        if let old, old.hasSameNamespace(as: new) {
            if old.drawingsKey != new.drawingsKey { switchDrawings(from: old, to: new) }
            return
        }
        isRestoringPersistence = true
        defer { isRestoringPersistence = false }
        // One batch, so that a restored style and restored indicators are one update of the render state.
        batch {
            if let style = new.restoredStyle(offeredBy: configuration.stylePicker) { self.style = style }
            if let indicators = new.restoredIndicators() { self.indicators = indicators }
        }
        switchDrawings(from: old, to: new)
    }

    /// The drawings follow the key: the ones on the chart are saved under the old key, then the ones saved under the new key
    /// are shown. When nothing is saved under the new key the chart is emptied if it shows the drawings of another key (see
    /// ``shownDrawingsKey``, which a `nil` key in between does not forget), and keeps what it shows otherwise: drawings that
    /// belong to no key are adopted by the first one. A `nil` key keeps the drawings and stops saving them. A drawing that is
    /// half placed is dropped when the key changes, and the tool stays.
    private func switchDrawings(from old: ChartPersistence?, to new: ChartPersistence) {
        if old?.drawingsKey != nil { old?.save(drawings: drawingEditor.drawings) }
        let newKey = new.drawingsStoreKey
        if newKey != old?.drawingsStoreKey { drawingEditor.beginCreating(drawingEditor.activeTool) }
        guard let newKey else { return }
        let wasRestoring = isRestoringPersistence
        isRestoringPersistence = true
        defer { isRestoringPersistence = wasRestoring }
        if let restored = new.restoredDrawings() {
            drawings = restored
        } else if let shown = shownDrawingsKey, shown != newKey {
            drawings = []
        }
        shownDrawingsKey = newKey
    }

    func persistStyle() {
        guard !isRestoringPersistence else { return }
        configuration.persistence?.save(style: style)
    }

    func persistIndicators() {
        guard !isRestoringPersistence else { return }
        configuration.persistence?.save(indicators: indicators)
    }

    func persistDrawings() {
        guard !isRestoringPersistence else { return }
        configuration.persistence?.save(drawings: drawingEditor.drawings)
    }
}
