import SwiftUI
import TradingChartCore

/// The sizes of a pane below its legend row: the plot, the column of price labels to the right of it, and the strip of
/// time labels under it (on the lowest pane only).
@available(iOS 17.0, *)
struct PaneGeometry: Equatable {
    /// The whole pane body.
    var size: CGSize
    /// Width of the column of price labels, including the gap between it and the plot.
    var columnWidth: CGFloat
    /// Height of the strip of time labels under the plot.
    var timeStripHeight: CGFloat

    /// The gap between the plot and the price labels.
    static let labelGap: CGFloat = 4
    /// The height reserved for the time labels.
    static let timeStrip: CGFloat = 16

    init(size: CGSize, theme: TradingChartTheme, isBottomPane: Bool) {
        self.size = size
        columnWidth = theme.yAxisLabelWidth + Self.labelGap
        timeStripHeight = isBottomPane ? Self.timeStrip : 0
    }

    /// The plot area: where the marks are visible.
    var plot: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: Swift.max(size.width - columnWidth, 0),
            height: Swift.max(size.height - timeStripHeight, 0)
        )
    }
}

/// The axes of a pane, drawn behind the chart: grid lines and price labels of the Y axis, vertical grid lines and (on
/// the lowest pane) time labels of the X axis.
///
/// They are drawn here and not by Swift Charts because the chart is laid out for a base domain and moved to the
/// autoscaled one by a transform (see ``YTransform``): the axes must follow the autoscaled domain and the scroll
/// position on every frame without laying the chart out. A `Canvas` redraws them in a fraction of a millisecond.
@available(iOS 17.0, *)
struct PaneAxes: View {
    let model: TradingChartModel
    let geometry: PaneGeometry
    /// The Y domain that is shown; read in the body, so that this view (and nothing else) follows it.
    let yTarget: () -> ClosedRange<Double>
    let yDesiredCount: Int
    let yLabel: (Double) -> String
    let showsTimeLabels: Bool

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartTimeFormatter) private var timeFormatter

    var body: some View {
        let _ = model.renderCounters.axisBodies += 1
        let domain = yTarget()
        let scroll = model.scrollPosition
        let duration = model.visibleDuration
        let ticks = model.xTicks
        let interval = model.series.interval
        let geometry = geometry
        let theme = theme
        let timeFormatter = timeFormatter
        let yLabel = yLabel
        let yDesiredCount = yDesiredCount
        let showsTimeLabels = showsTimeLabels
        Canvas { context, _ in
            // The canvas reaches `overhang` beyond the pane at the top and the bottom, so that a price label at the edge
            // of the plot is not cut in half.
            context.translateBy(x: 0, y: Self.overhang)
            let plot = geometry.plot
            guard plot.width > 0, plot.height > 0, duration > 0 else { return }
            let grid = GraphicsContext.Shading.color(theme.grid)
            let dash = StrokeStyle(lineWidth: 1, dash: theme.gridDash)

            // Y axis: dashed lines across the plot, labels right-aligned in the column.
            let mapping = YMapping(domain: domain, height: plot.height)
            for value in YAxisTicks.values(in: domain, desiredCount: yDesiredCount) {
                let y = mapping.y(of: value)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: plot.width, y: y))
                context.stroke(line, with: grid, style: dash)
                Self.drawLabel(
                    Text(yLabel(value)).font(theme.axisFont).foregroundStyle(theme.axisLabel),
                    in: &context,
                    at: CGPoint(x: geometry.size.width, y: y),
                    anchor: .trailing,
                    maxWidth: theme.yAxisLabelWidth
                )
            }

            // X axis: vertical lines at the ticks, labels right of them that fit into the plot.
            let start = scroll.timeIntervalSince1970
            for tick in ticks {
                let x = CGFloat((tick.timeIntervalSince1970 - start) / duration) * plot.width
                guard x >= -1, x <= plot.width + 1 else { continue }
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: plot.height))
                context.stroke(line, with: grid, style: dash)
                guard showsTimeLabels else { continue }
                let label = context.resolve(
                    Text(timeFormatter.format(tick, interval: interval, context: .axis))
                        .font(theme.axisFont)
                        .foregroundStyle(theme.axisLabel)
                )
                let width = label.measure(in: CGSize(width: 1_000, height: 100)).width
                guard TimeAxisLabelFit.fits(
                    tick: tick,
                    visibleRange: scroll...scroll.addingTimeInterval(duration),
                    plotWidth: plot.width,
                    labelWidth: width
                ) else { continue }
                context.draw(label, at: CGPoint(x: x + 4, y: plot.height + geometry.timeStripHeight / 2), anchor: .leading)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height + 2 * Self.overhang)
        .offset(y: -Self.overhang)
        .allowsHitTesting(false)
    }

    /// How far the canvas reaches beyond the pane, top and bottom, in points.
    private static let overhang: CGFloat = 8

    /// Draws `text` at `point`, shrunk to fit `maxWidth` when it is wider (as `minimumScaleFactor` would).
    private static func drawLabel(
        _ text: Text,
        in context: inout GraphicsContext,
        at point: CGPoint,
        anchor: UnitPoint,
        maxWidth: CGFloat
    ) {
        let resolved = context.resolve(text)
        let width = resolved.measure(in: CGSize(width: 1_000, height: 100)).width
        if width > maxWidth, width > 0 {
            let factor = Swift.max(maxWidth / width, 0.8)
            context.drawLayer { layer in
                layer.translateBy(x: point.x, y: point.y)
                layer.scaleBy(x: factor, y: factor)
                layer.draw(resolved, at: .zero, anchor: anchor)
            }
        } else {
            context.draw(resolved, at: point, anchor: anchor)
        }
    }
}

/// Shows the autoscaled Y domain on a chart that is laid out for another one: scales the chart in Y about its top
/// and moves it (see ``YTransformMath``). The chart is `frameRatio` plot heights tall. Reads the base and the target here,
/// so that a scroll step re-evaluates this small body instead of the pane.
@available(iOS 17.0, *)
struct YTransform: ViewModifier {
    let model: TradingChartModel
    /// The pane state, or `nil` for the main pane.
    let state: PaneRenderState?
    let plotHeight: CGFloat

    func body(content: Content) -> some View {
        let parameters = YTransformMath.parameters(
            base: state?.yBase ?? model.mainYBase,
            target: state?.yTarget ?? model.mainYTarget
        )
        content
            .scaleEffect(x: 1, y: CGFloat(parameters.scale), anchor: .top)
            .offset(y: plotHeight * CGFloat(parameters.offset))
    }
}
