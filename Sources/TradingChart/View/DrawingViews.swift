import SwiftUI
import TradingChartCore

/// Draws the drawings over the main pane: a `Canvas` over the plot, like ``MainMarksOverlay``.
///
/// Drawings are in data coordinates and are mapped through the window that is shown (the visible time range and the
/// autoscaled price range) on every frame, in the same frame as the bars they sit on. They are not marks of the chart:
/// a mark would rebuild the chart whenever a drawing is added or dragged, and the canvas redraws in a fraction of a
/// millisecond. A view of its own, so that what it reads (the drawings, the window) invalidates nothing else.
@available(iOS 17.0, *)
struct DrawingsOverlay: View {
    let model: TradingChartModel
    /// The plot area.
    let plot: CGRect

    @Environment(\.tradingChartTheme) private var theme

    var body: some View {
        let _ = model.renderCounters.drawingBodies += 1
        let editor = model.drawingEditor
        // Nothing to draw: read nothing else, so a scroll step does not even evaluate this body.
        if plot.width > 0, plot.height > 0, !editor.drawings.isEmpty || !editor.pendingAnchors.isEmpty {
            let frame = DrawingLayout.frame(
                drawings: editor.drawings,
                selectedID: editor.selectedID,
                pendingAnchors: editor.pendingAnchors,
                registry: model.drawingTools,
                domain: model.drawingDomain(),
                transform: model.drawingTransform(plot: plot)
            )
            let theme = theme
            Canvas { context, _ in
                for stroke in frame.strokes {
                    Self.draw(stroke, theme: theme, in: &context)
                }
                for point in frame.pending {
                    Self.drawHandle(at: point, core: theme.drawingDefault, theme: theme, in: &context)
                }
            }
            .frame(width: plot.width, height: plot.height)
            .allowsHitTesting(false)
        }
    }

    private static func color(of style: DrawingStyle, theme: TradingChartTheme) -> Color {
        style.color.map(Color.init) ?? theme.drawingDefault
    }

    private static func draw(_ stroke: DrawingStroke, theme: TradingChartTheme, in context: inout GraphicsContext) {
        let color = color(of: stroke.style, theme: theme)
        if !stroke.lines.isEmpty {
            var path = Path()
            for line in stroke.lines {
                path.move(to: line.from)
                path.addLine(to: line.to)
            }
            let width = CGFloat(stroke.style.lineWidth)
            if stroke.isSelected {
                // A soft halo, so a selected drawing stands out even where its anchors are off screen.
                context.stroke(
                    path,
                    with: .color(color.opacity(0.25)),
                    style: StrokeStyle(lineWidth: width + 6, lineCap: .round, lineJoin: .round)
                )
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: width,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: stroke.style.dash.map { CGFloat($0) }
                )
            )
        }
        for point in stroke.handles {
            drawHandle(at: point, core: color, theme: theme, in: &context)
        }
    }

    /// A ring in the handle colour around a core in the colour of the drawing.
    private static func drawHandle(at point: CGPoint, core: Color, theme: TradingChartTheme, in context: inout GraphicsContext) {
        let outer = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        let inner = Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
        context.fill(outer, with: .color(theme.drawingHandle))
        context.fill(inner, with: .color(core))
    }
}
