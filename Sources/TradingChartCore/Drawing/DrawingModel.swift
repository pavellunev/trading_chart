import Foundation

/// A point in chart data space: a moment in time and a price.
public struct ChartAnchor: Hashable, Sendable, Codable {
    /// The time coordinate.
    public var time: Date
    /// The price coordinate.
    public var price: Double

    /// Creates an anchor.
    public init(time: Date, price: Double) {
        self.time = time
        self.price = price
    }
}

/// Identifies a type of drawing. An open set: hosts can declare their own kinds, like `Notification.Name`.
public struct DrawingKind: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    /// The unique name of the kind.
    public let rawValue: String

    /// A horizontal price line (one anchor).
    public static let horizontalLine = DrawingKind(rawValue: "horizontalLine")
    /// A segment between two anchors.
    public static let trendLine = DrawingKind(rawValue: "trendLine")
    /// A line from the first anchor through the second one to the edge of the chart.
    public static let ray = DrawingKind(rawValue: "ray")

    /// Creates a kind from its name.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a kind from a string literal.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// Decodes a kind from a single string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    /// Encodes the kind as a single string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Stroke style of a drawing.
public struct DrawingStyle: Hashable, Sendable, Codable {
    /// Explicit color. `nil` uses the theme default drawing color.
    public var color: ChartColor?
    /// Stroke width in points.
    public var lineWidth: Double
    /// Dash pattern in points; empty for a solid line.
    public var dash: [Double]

    /// Creates a style.
    public init(color: ChartColor? = nil, lineWidth: Double = 1.5, dash: [Double] = []) {
        self.color = color
        self.lineWidth = lineWidth
        self.dash = dash
    }
}

/// A user-drawn object on the chart. `Codable`, so hosts can persist drawings themselves.
public struct ChartDrawing: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier.
    public var id: UUID
    /// The kind, which selects the tool that renders it.
    public var kind: DrawingKind
    /// Control points in data space.
    public var anchors: [ChartAnchor]
    /// Stroke style.
    public var style: DrawingStyle
    /// A locked drawing can be selected but not moved.
    public var isLocked: Bool

    /// Creates a drawing.
    public init(
        id: UUID = UUID(),
        kind: DrawingKind,
        anchors: [ChartAnchor],
        style: DrawingStyle = DrawingStyle(),
        isLocked: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.anchors = anchors
        self.style = style
        self.isLocked = isLocked
    }
}

/// The visible data-space extent of the chart, used to extend open-ended drawings such as rays.
public struct ChartDomain: Sendable, Hashable {
    /// The time extent.
    public var x: ClosedRange<Date>
    /// The price extent.
    public var y: ClosedRange<Double>

    /// Creates a domain.
    public init(x: ClosedRange<Date>, y: ClosedRange<Double>) {
        self.x = x
        self.y = y
    }
}

/// A shape in data coordinates. The UI maps these through the current screen transform on every frame, so drawings follow
/// the chart while it scrolls and autoscales; see ``DrawingPrimitive/clipped(to:)`` for cutting them to the visible part.
public enum DrawingPrimitive: Hashable, Sendable {
    /// A segment between two anchors.
    case segment(ChartAnchor, ChartAnchor)
    /// A horizontal line across the whole chart at `price`.
    case horizontalLine(price: Double)
    /// A vertical line across the whole chart at `time`.
    case verticalLine(time: Date)
}

/// What a hit test found.
public enum DrawingHit: Hashable, Sendable {
    /// A control point, by index into the drawing's anchors.
    case anchor(Int)
    /// The stroke of the drawing, away from its control points.
    case body
}
