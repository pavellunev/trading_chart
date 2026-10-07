import CoreGraphics

/// Everything the editor needs to interpret a gesture: tools, current geometry and snapping.
public struct DrawingContext: Sendable {
    /// The tools available for creation and hit testing.
    public var registry: DrawingToolRegistry
    /// The data-space extent passed to tools (to extend rays and the like).
    public var domain: ChartDomain
    /// The current mapping between screen and data.
    public var transform: ChartTransform
    /// Hit-test radius in points.
    public var tolerance: CGFloat
    /// The series interval. Anchor times are snapped to the nearest bucket start while creating and dragging; prices stay free.
    public var interval: ChartInterval

    /// Creates a context.
    public init(
        registry: DrawingToolRegistry = .standard,
        domain: ChartDomain,
        transform: ChartTransform,
        tolerance: CGFloat = 12,
        interval: ChartInterval
    ) {
        self.registry = registry
        self.domain = domain
        self.transform = transform
        self.tolerance = tolerance
        self.interval = interval
    }
}
