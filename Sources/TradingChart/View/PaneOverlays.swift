import SwiftUI
import TradingChartCore

/// The marks of the main pane that are drawn by hand over the chart: the labels of the highest and the lowest price of the
/// window, and the trade markers.
///
/// Both depend on the window, which changes on every scroll step, and the chart is not rebuilt by one (see
/// ``YTransform``): drawn here they are always right, at any scroll position and any autoscaled domain, in the same frame
/// as the bars they belong to. A `Canvas` draws them in a fraction of a millisecond.
@available(iOS 17.0, *)
struct MainMarksOverlay: View {
    let model: TradingChartModel
    /// The plot area.
    let plot: CGRect
    let drawnStyle: SeriesStyle

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter

    var body: some View {
        let visible = model.visibleTimeRange
        let domain = model.mainYTarget
        let series = model.series
        let extremes = model.configuration.showsHighLowMarkers
            ? HighLowMarks.extremes(in: series, style: drawnStyle, range: visible)
            : nil
        let markers = model.markers.filter { visible.lowerBound.addingTimeInterval(-model.visibleDuration * 0.1) <= $0.time
            && $0.time <= visible.upperBound.addingTimeInterval(model.visibleDuration * 0.1) }
        let price = model.configuration.showsCurrentPriceLine ? model.currentPrice : nil
        let lastTime = series.lastTime
        let plot = plot
        let theme = theme
        let priceFormatter = priceFormatter
        // Where the price badge is on screen (it sits at the height of the price, over the price column and a little into the
        // plot), so that the labels of the highest and the lowest price keep clear of it.
        let badge: CGRect? = model.configuration.showsPriceBadge && model.badgeSize.width > 0
            ? model.currentPrice.map { current in
                PriceBadgeLayout.rect(
                    size: model.badgeSize,
                    priceY: YMapping(domain: domain, height: plot.height).y(of: current),
                    plotHeight: plot.height,
                    chartWidth: plot.width + model.yAxisColumnWidth
                )
            }
            : nil
        Canvas { context, _ in
            guard plot.width > 0, plot.height > 0 else { return }
            let duration = visible.upperBound.timeIntervalSince(visible.lowerBound)
            guard duration > 0 else { return }
            let mapping = YMapping(domain: domain, height: plot.height)
            func x(_ time: Date) -> CGFloat {
                CGFloat(time.timeIntervalSince(visible.lowerBound) / duration) * plot.width
            }
            // The dashed current price line: from the newest bar to the right edge of the plot, or across the whole
            // window when the newest bar is to the right of it. Drawn here (not as a mark), so a tick moves it without
            // rebuilding the chart.
            if let price {
                let y = mapping.y(of: price)
                var start: CGFloat = 0
                if case .fromLastBar(let last) = PriceLine.span(
                    lastTime: lastTime,
                    visibleRange: visible,
                    price: price,
                    yDomain: -Double.infinity...Double.infinity
                ) {
                    start = Swift.max(x(last), 0)
                }
                var line = Path()
                line.move(to: CGPoint(x: start, y: y))
                line.addLine(to: CGPoint(x: plot.width, y: y))
                context.stroke(
                    line,
                    with: .color(theme.currentPriceLine ?? theme.line.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1, dash: theme.currentPriceLineDash)
                )
            }
            if let extremes {
                let plotRect = CGRect(origin: .zero, size: plot.size)
                for extreme in [extremes.high, extremes.low] {
                    Self.drawExtreme(
                        extreme,
                        at: CGPoint(x: x(extreme.time), y: mapping.y(of: extreme.value)),
                        prefersLeft: HighLowMarks.labelGoesLeft(of: extreme.time, in: visible),
                        text: priceFormatter.format(extreme.value, context: .legend),
                        plot: plotRect,
                        avoiding: badge.map { [$0] } ?? [],
                        theme: theme,
                        in: &context
                    )
                }
            }
            for marker in markers {
                guard let price = marker.price ?? series.interpolatedValue(at: marker.time) else { continue }
                Self.drawMarker(
                    marker,
                    at: CGPoint(x: x(marker.time), y: mapping.y(of: price)),
                    theme: theme,
                    in: &context
                )
            }
        }
        .frame(width: plot.width, height: plot.height)
        .allowsHitTesting(false)
    }

    /// A short line from the tip of the bar and the price beyond it, towards the side with more room; to the other side or not
    /// at all when the price badge is in the way (see ``ExtremeLabelLayout``).
    private static func drawExtreme(
        _ extreme: WindowExtreme,
        at point: CGPoint,
        prefersLeft: Bool,
        text: String,
        plot: CGRect,
        avoiding obstacles: [CGRect],
        theme: TradingChartTheme,
        in context: inout GraphicsContext
    ) {
        let label = context.resolve(Text(text).font(theme.extremeLabelFont).foregroundStyle(theme.extremeLabel))
        let size = label.measure(in: CGSize(width: 1_000, height: 100))
        guard let placement = ExtremeLabelLayout.place(
            at: point,
            labelSize: size,
            prefersLeft: prefersLeft,
            plot: plot,
            avoiding: obstacles
        ) else { return }
        var line = Path()
        line.move(to: point)
        line.addLine(to: placement.lineEnd)
        context.stroke(line, with: .color(theme.extremeLabel), style: StrokeStyle(lineWidth: 1))
        context.draw(
            label,
            at: CGPoint(x: placement.goesLeft ? placement.labelRect.maxX : placement.labelRect.minX, y: point.y),
            anchor: placement.goesLeft ? .trailing : .leading
        )
    }

    /// The dot with its label above (buy, neutral) or below (sell).
    private static func drawMarker(
        _ marker: ChartMarker,
        at point: CGPoint,
        theme: TradingChartTheme,
        in context: inout GraphicsContext
    ) {
        let color = markerColor(marker, theme: theme)
        let size = theme.markerSize
        let dot = Path(ellipseIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        context.fill(dot, with: .color(color))
        context.stroke(dot, with: .color(theme.markerBorder), style: StrokeStyle(lineWidth: 1.5))
        guard let text = markerText(marker) else { return }
        let resolved = context.resolve(
            Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(theme.markerText)
        )
        let textWidth = resolved.measure(in: CGSize(width: 200, height: 40)).width
        let height: CGFloat = 14
        let distance = size / 2 + 3 + height / 2
        let center = CGPoint(x: point.x, y: point.y + (marker.kind == .sell ? distance : -distance))
        let capsule = Path(
            roundedRect: CGRect(x: center.x - (textWidth + 8) / 2, y: center.y - height / 2, width: textWidth + 8, height: height),
            cornerRadius: height / 2
        )
        context.fill(capsule, with: .color(color))
        context.draw(resolved, at: center, anchor: .center)
    }

    private static func markerColor(_ marker: ChartMarker, theme: TradingChartTheme) -> Color {
        if let color = marker.color { return Color(color) }
        switch marker.kind {
        case .buy: return theme.bullish
        case .sell: return theme.bearish
        case .neutral: return theme.line
        }
    }

    private static func markerText(_ marker: ChartMarker) -> String? {
        if let label = marker.label { return label }
        switch marker.kind {
        case .buy: return "B"
        case .sell: return "S"
        case .neutral: return nil
        }
    }
}

/// What the tooltip of the main pane needs besides the crosshair.
@available(iOS 17.0, *)
struct TooltipContent {
    var drawnStyle: SeriesStyle
}

/// Hosts the crosshair of a pane. A leaf view of its own: it is the only thing of the pane that reads the crosshair, which
/// moves with the finger, so that a crosshair that moves from bar to bar does not rebuild the chart (the lines, the labels and
/// the tooltip are drawn over it). The main pane and every indicator pane has one; the haptic tick is not theirs, see
/// ``CrosshairHaptic``.
@available(iOS 17.0, *)
struct CrosshairLayer: View {
    let model: TradingChartModel
    let geometry: PaneGeometry
    let isBottomPane: Bool
    /// The Y domain that is shown, for the position of the price line and label.
    let valueDomain: () -> ClosedRange<Double>
    let showsPriceLabel: Bool
    let tooltip: TooltipContent?

    var body: some View {
        let _ = model.renderCounters.crosshairBodies += 1
        let crosshair = model.crosshair
        ZStack(alignment: .topLeading) {
            if let crosshair {
                CrosshairOverlay(
                    model: model,
                    crosshair: crosshair,
                    geometry: geometry,
                    isBottomPane: isBottomPane,
                    valueDomain: valueDomain,
                    showsPriceLabel: showsPriceLabel,
                    tooltip: tooltip
                )
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The haptic tick of the crosshair moving to another bar. Hosted once by the chart (in the main pane), not by every pane's
/// ``CrosshairLayer``: the panes all show the same crosshair, and a tick per pane would be several for one bar. A leaf view
/// of its own for the same reason as the layer: it reads the crosshair, which moves with the finger.
@available(iOS 17.0, *)
struct CrosshairHaptic: View {
    let model: TradingChartModel

    var body: some View {
        let _ = model.renderCounters.crosshairHapticBodies += 1
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .sensoryFeedback(.selection, trigger: model.crosshair?.time) { _, new in
                new != nil && model.configuration.isHapticsEnabled
            }
    }
}

/// The crosshair of a pane: its lines (a vertical one at the bar, and at the price on the main pane a horizontal one), the labels
/// (the price in the price column, the time under the lowest pane) and the tooltip card. A view of its own: it reads the window,
/// which only exists while a crosshair is shown.
@available(iOS 17.0, *)
struct CrosshairOverlay: View {
    let model: TradingChartModel
    let crosshair: CrosshairState
    let geometry: PaneGeometry
    let isBottomPane: Bool
    /// The Y domain that is shown, for the position of the price label.
    let valueDomain: () -> ClosedRange<Double>
    let showsPriceLabel: Bool
    let tooltip: TooltipContent?

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter
    @Environment(\.tradingChartTimeFormatter) private var timeFormatter
    @Environment(\.tradingChartStrings) private var strings

    /// Which side of the plot the tooltip is on; see ``TooltipPlacement``.
    @State private var tooltipSide: TooltipPlacement.Side = .trailing

    var body: some View {
        let plot = geometry.plot
        let visible = model.visibleTimeRange
        let lineX = CrosshairLayout.x(of: crosshair.time, visibleRange: visible, plotWidth: plot.width)
        let lineY = showsPriceLabel
            ? YMapping(domain: valueDomain(), height: plot.height).y(of: crosshair.value)
            : nil
        ZStack(alignment: .topLeading) {
            lines(x: lineX, y: lineY, plot: plot)
            if let lineY {
                CrosshairBubble(
                    text: priceFormatter.format(crosshair.value, context: .crosshair),
                    width: theme.yAxisLabelWidth
                )
                .position(
                    x: geometry.size.width - theme.yAxisLabelWidth / 2,
                    y: plot.minY + Swift.min(Swift.max(lineY, 8), Swift.max(plot.height - 8, 8))
                )
            }
            if isBottomPane, let lineX {
                CrosshairBubble(
                    text: timeFormatter.format(crosshair.time, interval: model.series.interval, context: .crosshair),
                    width: CrosshairLayout.timeLabelWidth
                )
                .position(
                    x: CrosshairLayout.clamped(lineX, width: CrosshairLayout.timeLabelWidth, plotWidth: plot.width),
                    y: geometry.size.height - 9
                )
            }
            if let tooltip {
                tooltipCard(tooltip, plot: plot, visible: visible)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// The dashed lines over the plot: down from the bar, and across at the price. Drawn by hand, not as marks of the chart,
    /// so that the chart is not laid out again whenever the crosshair moves to another bar.
    private func lines(x: CGFloat?, y: CGFloat?, plot: CGRect) -> some View {
        let color = theme.crosshair
        return Canvas { context, _ in
            let style = StrokeStyle(lineWidth: 1, dash: [4, 3])
            if let x {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: plot.height))
                context.stroke(line, with: .color(color), style: style)
            }
            if let y, y >= 0, y <= plot.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: plot.width, y: y))
                context.stroke(line, with: .color(color), style: style)
            }
        }
        .frame(width: plot.width, height: plot.height)
    }

    /// The card with the values of the crosshair bar, at the top of the plot on the side away from the crosshair.
    private func tooltipCard(_ tooltip: TooltipContent, plot: CGRect, visible: ClosedRange<Date>) -> some View {
        let formatter = LegendFormatter(theme: theme, priceFormatter: priceFormatter, strings: strings)
        let rows = formatter.tooltipRows(
            for: crosshair,
            drawnStyle: tooltip.drawnStyle,
            time: timeFormatter.format(crosshair.time, interval: model.series.interval, context: .crosshair)
        )
        let side = TooltipPlacement.side(
            crosshairX: CrosshairLayout.x(of: crosshair.time, visibleRange: visible, plotWidth: plot.width),
            plotWidth: plot.width,
            current: tooltipSide
        )
        // The badge sits at the height of the price, and sticks into the plot with its long labels: the card, which is far
        // taller than the badge, leaves room for it instead of covering it.
        let badgeReach = model.configuration.showsPriceBadge && model.currentPrice != nil
            ? TooltipPlacement.badgeReach(
                badgeWidth: model.badgeWidth,
                columnWidth: model.yAxisColumnWidth,
                showsChevron: !model.isAtLiveEdge
            )
            : 0
        return CrosshairTooltip(rows: rows)
            .padding(.leading, 6)
            .padding(.trailing, 6 + badgeReach)
            .padding(.top, plot.minY + 6)
            .frame(width: plot.width, alignment: side == .leading ? .topLeading : .topTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: side) { _, new in tooltipSide = new }
    }
}

// MARK: - Leaf views
//
// Things on a pane that follow the newest bar, the price or the crosshair: small views of their own, so that a live tick
// re-evaluates them and not the pane (whose body builds all the marks).

/// The legend row above the main pane: the overlay indicators with their values at the crosshair bar (or the newest bar).
/// Empty when the legend is off or there is no overlay indicator.
@available(iOS 17.0, *)
struct MainLegend: View {
    let model: TradingChartModel

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter

    var body: some View {
        if model.configuration.showsLegend {
            let overlays = model.indicators.filter { $0.placement == .overlay && model.output(for: $0.id) != nil }
            if !overlays.isEmpty {
                let formatter = LegendFormatter(theme: theme, priceFormatter: priceFormatter)
                let state = model.crosshair ?? model.latestBarState
                let rows = overlays.map { indicator in
                    formatter.indicatorRow(
                        name: indicator.displayName,
                        values: state?.indicatorValues.filter { $0.indicatorID == indicator.id } ?? [],
                        context: .legend
                    )
                }
                LegendHeader(text: formatter.header(rows))
            }
        }
    }
}

/// The row above the main pane: the legend of the overlay indicators, and at the right (over the price column) the style
/// picker when ``TradingChartConfiguration/stylePicker`` is set. The picker is outside the plot, so it covers no data. A view
/// of its own: it reads the configuration and the style (``SeriesStylePicker``), and nothing that changes while scrolling.
@available(iOS 17.0, *)
struct MainLegendRow: View {
    let model: TradingChartModel

    var body: some View {
        HStack(spacing: 0) {
            MainLegend(model: model)
            if let options = model.configuration.stylePicker {
                SeriesStylePicker(model: model, options: options)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The legend row above an indicator pane: the indicator with its values at the crosshair bar (or the newest bar).
@available(iOS 17.0, *)
struct PaneLegend: View {
    let model: TradingChartModel
    let indicator: any ChartIndicator

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter

    var body: some View {
        if model.configuration.showsLegend {
            let formatter = LegendFormatter(theme: theme, priceFormatter: priceFormatter)
            let state = model.crosshair ?? model.latestBarState
            LegendHeader(text: formatter.header([
                formatter.indicatorRow(
                    name: indicator.displayName,
                    values: state?.indicatorValues.filter { $0.indicatorID == indicator.id } ?? [],
                    context: .compact
                )
            ]))
        }
    }
}

/// Hosts the price badge (or, for `isProbe`, the invisible copy that measures it).
@available(iOS 17.0, *)
struct PriceBadgeHost: View {
    let model: TradingChartModel
    let plot: CGRect
    let chartWidth: CGFloat
    let isProbe: Bool

    var body: some View {
        if model.configuration.showsPriceBadge, let price = model.currentPrice {
            if isProbe {
                PriceBadgeWidthProbe(model: model, price: price)
            } else {
                PriceBadgeOverlay(model: model, price: price, plot: plot, chartWidth: chartWidth)
            }
        }
    }
}

/// What VoiceOver gets from the main chart: its kind as the label, the last price and the visible range as the value, and
/// the ways to scroll the window: the scroll gesture (three fingers) and the actions of the rotor. Each moves the window by one
/// window width (see ``TradingChartModel/accessibilityScroll(_:)``) and announces the new range.
///
/// The value follows the window as it was when scrolling last came to rest, so a scroll step does not evaluate this body.
@available(iOS 17.0, *)
struct ChartAccessibility: ViewModifier {
    let model: TradingChartModel

    @Environment(\.tradingChartPriceFormatter) private var priceFormatter
    @Environment(\.tradingChartTimeFormatter) private var timeFormatter
    @Environment(\.tradingChartStrings) private var strings

    func body(content: Content) -> some View {
        let interval = model.series.interval
        let formatTime = { (date: Date) in timeFormatter.format(date, interval: interval, context: .crosshair) }
        let price = (model.currentPrice ?? model.series.lastValue).map { priceFormatter.format($0, context: .legend) }
        return content
            .accessibilityLabel(Text(verbatim: ChartAccessibilityText.label(for: model.style, strings: strings)))
            .accessibilityValue(Text(verbatim: ChartAccessibilityText.value(
                lastPrice: price,
                window: model.settledWindow,
                atLiveEdge: model.isAtLiveEdge,
                format: formatTime,
                strings: strings
            )))
            .accessibilityScrollAction { edge in
                // The edge is the side the content moves towards: a three-finger swipe to the left (`.leading`) moves the
                // content left, which brings later bars in from the right; a swipe to the right brings earlier bars.
                switch edge {
                case .leading: scroll(.later)
                case .trailing: scroll(.earlier)
                default: break
                }
            }
            .accessibilityAction(named: Text(verbatim: strings.showEarlierBars)) { scroll(.earlier) }
            .accessibilityAction(named: Text(verbatim: strings.showLaterBars)) { scroll(.later) }
            .accessibilityAction(named: Text(verbatim: strings.showLatestBar)) { scroll(.latest) }
    }

    /// Moves the window and says where it is now (or that it cannot go further).
    private func scroll(_ action: TradingChartModel.AccessibilityScroll) {
        let moved = model.accessibilityScroll(action)
        let interval = model.series.interval
        let announcement = ChartAccessibilityText.announcement(
            after: action,
            moved: moved,
            window: model.visibleTimeRange,
            format: { timeFormatter.format($0, interval: interval, context: .crosshair) },
            strings: strings
        )
        AccessibilityNotification.PageScrolled(announcement).post()
    }
}
