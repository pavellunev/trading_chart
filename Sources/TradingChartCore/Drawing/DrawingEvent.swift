import Foundation

/// A change to the set of drawings or to the selection, reported to the host.
public enum DrawingEvent: Sendable, Equatable {
    /// A drawing was created. It is also selected.
    case added(ChartDrawing)
    /// A drawing was moved or reshaped.
    case changed(ChartDrawing)
    /// A drawing was deleted.
    case removed(UUID)
    /// The selection changed; `nil` means nothing is selected.
    case selectionChanged(UUID?)
}
