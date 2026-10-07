/// The set of drawing tools available to a chart, keyed by drawing kind.
public struct DrawingToolRegistry: Sendable {
    private var tools: [DrawingKind: any DrawingTool]

    /// A registry with the built-in tools: horizontal line, trend line and ray.
    public static let standard = DrawingToolRegistry(
        tools: [HorizontalLineTool(), TrendLineTool(), RayTool()]
    )

    /// Creates a registry holding the given tools. A later tool replaces an earlier one of the same kind.
    public init(tools: [any DrawingTool] = []) {
        self.tools = [:]
        for tool in tools {
            self.tools[tool.kind] = tool
        }
    }

    /// Adds a tool, replacing any existing tool of the same kind.
    public mutating func register(_ tool: any DrawingTool) {
        tools[tool.kind] = tool
    }

    /// The tool registered for `kind`, if any.
    public func tool(for kind: DrawingKind) -> (any DrawingTool)? {
        tools[kind]
    }
}
