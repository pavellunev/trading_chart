import SwiftUI
import TradingChartCore

/// A scrollable trading chart driven by a ``TradingChartModel``.
///
/// The main panel shows the series and the overlay indicators; every indicator that has its own pane
/// (``IndicatorPlacement/pane``) and something to draw gets a panel below, scrolling in sync with the main one.
///
/// ```swift
/// let model = TradingChartModel(series: series, style: .candles)
/// model.indicators = [SMA(period: 20), Volume(), RSI()]
///
/// TradingChartView(model: model)
///     .tradingChartTheme(.standard)
/// ```
@available(iOS 17.0, *)
public struct TradingChartView: View {
    private let model: TradingChartModel

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.layoutDirection) private var hostLayoutDirection

    /// The pinch in progress: the window at its start, and the part of the window that stays in place.
    @State private var pinch = PinchTracker()
    /// `true` while a pinch is in progress. SwiftUI puts it back when the pinch ends *or is cancelled* (a phone call, a system
    /// gesture), and `onEnded` is not called for a cancelled one: this is how a cancelled pinch lets go of its baseline.
    @GestureState private var isPinching = false

    /// Creates a chart for `model`.
    public init(model: TradingChartModel) {
        self.model = model
    }

    private struct PaneItem: Identifiable {
        var indicator: any ChartIndicator
        var output: IndicatorOutput
        var state: PaneRenderState
        var id: String { indicator.id }
    }

    /// The indicators that get a pane: placed in a pane and with something to draw.
    private var panes: [PaneItem] {
        let input = model.renderInput
        return model.indicators.compactMap { indicator in
            guard indicator.placement == .pane,
                  let output = input.outputs[indicator.id],
                  !output.isEmpty
            else { return nil }
            return PaneItem(indicator: indicator, output: output, state: model.paneState(for: indicator.id))
        }
    }

    /// The chart.
    public var body: some View {
        let panes = panes
        VStack(spacing: 0) {
            MainChartPane(model: model, isBottomPane: panes.isEmpty)
            ForEach(Array(panes.enumerated()), id: \.element.id) { offset, pane in
                Rectangle()
                    .fill(theme.paneSeparator)
                    .frame(height: 1)
                IndicatorPane(
                    model: model,
                    indicator: pane.indicator,
                    output: pane.output,
                    state: pane.state,
                    isBottomPane: offset == panes.count - 1
                )
            }
        }
        // Time runs from left to right and the price scale is at the right in every language, as in every exchange app: the
        // chart is not mirrored in a right-to-left host. Only the words of the tooltip follow the host (see `CrosshairTooltip`).
        .environment(\.tradingChartHostLayoutDirection, hostLayoutDirection)
        .environment(\.layoutDirection, .leftToRight)
        .simultaneousGesture(magnifyGesture, including: model.configuration.isZoomEnabled ? .all : .subviews)
        .onChange(of: isPinching) { _, active in
            if !active { pinch.end() }
        }
        // What the autoscale at the edges of the window assumes about the width of a candle is the theme's.
        .onChange(of: CandleMetrics(theme: theme), initial: true) { _, metrics in
            model.updateCandleMetrics(metrics)
        }
    }

    /// Pinch to zoom. The magnification is the total since the gesture began, applied to the window as it was
    /// then; the window stays glued to the live edge when it started there, and zooms around its centre otherwise.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($isPinching) { _, isPinching, _ in
                isPinching = true
            }
            .onChanged { value in
                pinch.magnified(by: Double(value.magnification), in: model)
            }
            .onEnded { _ in
                pinch.end()
            }
    }
}

/// The pinch in progress: the window as it was at the first change of the gesture, and the part of it that stays in place.
///
/// The total magnification of a pinch is applied to that window, not to the current one, so repeated changes neither add up nor
/// drift once the width is clamped. The baseline is dropped by ``end()``, which the view calls when the pinch ends and when it is
/// cancelled: a baseline that survived a cancelled pinch would make the next one start from an old window.
@available(iOS 17.0, *)
@MainActor
final class PinchTracker {
    private var session: (baseline: TradingChartModel.ZoomBaseline, anchor: ZoomAnchor)?

    /// Whether a pinch holds a baseline.
    var isActive: Bool { session != nil }

    /// Zooms `model` by the total `magnification` of the pinch. The first call of a pinch takes its baseline: the window now,
    /// glued to the live edge when it sits there and zooming around its centre otherwise.
    func magnified(by magnification: Double, in model: TradingChartModel) {
        let current = session ?? (
            baseline: model.zoomBaseline(),
            anchor: model.isAtLiveEdge ? ZoomAnchor.liveEdge : ZoomAnchor.center
        )
        session = current
        model.zoom(from: current.baseline, by: magnification, anchor: current.anchor)
    }

    /// The pinch is over, ended or cancelled.
    func end() {
        session = nil
    }
}
