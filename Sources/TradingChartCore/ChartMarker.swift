import Foundation

/// An annotation pinned to a moment on the chart, typically a trade.
///
/// A `.buy` marker is drawn above its price level and a `.sell` marker below it.
public struct ChartMarker: Identifiable, Hashable, Sendable {
    /// The meaning of a marker, which drives its default color and label.
    public enum Kind: Sendable, Hashable {
        /// A buy: bullish color, label "B", drawn above the price.
        case buy
        /// A sell: bearish color, label "S", drawn below the price.
        case sell
        /// A neutral note: line color, no default label.
        case neutral
    }

    /// Stable identifier chosen by the host.
    public var id: String
    /// Moment the marker refers to.
    public var time: Date
    /// Price level of the marker. `nil` snaps the marker to the series at `time` (via `interpolatedValue`).
    public var price: Double?
    /// The marker kind.
    public var kind: Kind
    /// Text inside the marker. `nil` means "B" / "S" for buy / sell and no text for neutral.
    public var label: String?
    /// Explicit color. `nil` uses the theme color for the kind.
    public var color: ChartColor?

    /// Creates a marker.
    public init(
        id: String,
        time: Date,
        price: Double? = nil,
        kind: Kind,
        label: String? = nil,
        color: ChartColor? = nil
    ) {
        self.id = id
        self.time = time
        self.price = price
        self.kind = kind
        self.label = label
        self.color = color
    }
}
