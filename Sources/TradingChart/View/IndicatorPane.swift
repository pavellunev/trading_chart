import SwiftUI
import Charts
import TradingChartCore

/// One indicator pane below the main chart. It shares the X domain, the visible length and the scroll position
/// with every other pane, so scrolling any of them scrolls them all.
@available(iOS 17.0, *)
struct IndicatorPane: View {
    @Bindable var model: TradingChartModel
    let indicator: any ChartIndicator
    let output: IndicatorOutput
    /// The Y domain of the pane; the pane is rebuilt when it changes.
    let state: PaneRenderState
    /// Whether this pane is the lowest one and therefore carries the time labels.
    let isBottomPane: Bool

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter
    @Environment(\.tradingChartTimeFormatter) private var timeFormatter

    private struct Layout {
        var xDomain: ClosedRange<Date>
        /// The Y domain the chart is laid out for; the autoscaled one is shown by a transform (see ``YTransform``).
        var yDomain: ClosedRange<Double>
        var barWidth: CGFloat
        var histograms: [IndicatorHistogramItem]
        var lines: [IndicatorLineItem]
    }

    var body: some View {
        let _ = model.renderCounters.paneBodies += 1
        let layout = makeLayout()
        let _ = model.renderCounters.builtWindows[indicator.id] = model.renderWindow
        let _ = model.renderCounters.builtBases[indicator.id] = state.yBase
        VStack(spacing: 0) {
            PaneLegend(model: model, indicator: indicator)
            GeometryReader { proxy in
                paneBody(
                    layout: layout,
                    geometry: PaneGeometry(size: proxy.size, theme: theme, isBottomPane: isBottomPane)
                )
            }
        }
        .frame(height: model.configuration.paneHeight)
    }

    private func makeLayout() -> Layout {
        let renderRange = model.renderWindow
        let series = model.renderInput.series
        let base = model.renderInput.paletteBase(for: indicator.id)
        return Layout(
            xDomain: model.chartXDomain(for: series),
            yDomain: state.yBase,
            barWidth: ViewportMath.candleBodyWidth(
                plotWidth: model.plotWidth,
                visibleBars: model.visibleBars,
                factor: theme.candleBodyWidthFactor,
                min: theme.minCandleBodyWidth,
                max: theme.maxCandleBodyWidth
            ),
            histograms: output.histograms.map { histogram in
                IndicatorHistogramItem(
                    id: histogram.id,
                    baseline: histogram.baseline,
                    bars: IndicatorRendering.slice(histogram.bars, in: renderRange)
                )
            },
            lines: output.lines.map { line in
                IndicatorLineItem(
                    id: line.id,
                    color: line.style.color.map(Color.init)
                        ?? theme.paletteColor(at: base + Swift.max(line.paletteSlot, 0)),
                    width: CGFloat(line.style.width),
                    dash: line.style.dash.map { CGFloat($0) },
                    values: IndicatorRendering.slice(line.values, in: renderRange)
                )
            }
        )
    }

    /// The pane below the legend: the axes behind, the chart (moved by the transform to the autoscaled domain and
    /// clipped to the plot) and the crosshair.
    private func paneBody(layout: Layout, geometry: PaneGeometry) -> some View {
        let plot = geometry.plot
        let fixed = output.fixedRange != nil
        return ZStack(alignment: .topLeading) {
            PaneAxes(
                model: model,
                geometry: geometry,
                yTarget: { state.yTarget },
                yDesiredCount: 3,
                yLabel: { IndicatorRendering.paneAxisLabel($0, hasFixedRange: fixed, formatter: priceFormatter) },
                showsTimeLabels: isBottomPane
            )
            chart(layout)
                .allowsHitTesting(false)
                .frame(width: plot.width, height: plot.height * YTransformMath.frameRatio)
                .modifier(YTransform(model: model, state: state, plotHeight: plot.height))
                .frame(width: plot.width, height: plot.height, alignment: .top)
                .clipped()
            ChartInputLayer(model: model)
                .frame(width: plot.width, height: plot.height)
            CrosshairLayer(
                model: model,
                geometry: geometry,
                isBottomPane: isBottomPane,
                valueDomain: { state.yTarget },
                showsPriceLabel: false,
                tooltip: nil
            )
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    }

    private func chart(_ layout: Layout) -> some View {
        let _ = model.renderCounters.chartBuilds += 1
        return Chart {
            levelMarks
            histogramMarks(layout)
            lineMarks(layout.lines)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: layout.xDomain)
        .chartYScale(domain: layout.yDomain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: model.chartVisibleDuration)
        .modifier(ChartScrollBridge(model: model))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(indicator.displayName)
    }

    // MARK: - Marks

    @ChartContentBuilder
    private var levelMarks: some ChartContent {
        ForEach(output.levels) { level in
            RuleMark(y: .value("Level", level.value))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: level.dash.map { CGFloat($0) }))
                .foregroundStyle(level.color.map(Color.init) ?? theme.grid)
        }
    }

    @ChartContentBuilder
    private func histogramMarks(_ layout: Layout) -> some ChartContent {
        ForEach(layout.histograms) { histogram in
            ForEach(histogram.bars, id: \.time) { bar in
                BarMark(
                    x: .value("Time", bar.time),
                    yStart: .value("Baseline", histogram.baseline),
                    yEnd: .value("Value", bar.value),
                    width: .fixed(layout.barWidth)
                )
                .foregroundStyle(theme.histogramColor(tone: bar.tone, explicit: bar.color))
            }
        }
    }

    @ChartContentBuilder
    private func lineMarks(_ lines: [IndicatorLineItem]) -> some ChartContent {
        ForEach(lines) { line in
            ForEach(line.values, id: \.time) { value in
                LineMark(
                    x: .value("Time", value.time),
                    y: .value("Value", value.value),
                    series: .value("Indicator", line.id)
                )
                .foregroundStyle(line.color)
                .lineStyle(StrokeStyle(lineWidth: line.width, lineCap: .round, lineJoin: .round, dash: line.dash))
                .interpolationMethod(.linear)
            }
        }
    }
}
