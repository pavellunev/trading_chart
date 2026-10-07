import SwiftUI

/// Where the price badge is. Shared by the badge and by what has to keep clear of it (the labels of the highest and the
/// lowest price).
@available(iOS 17.0, *)
enum PriceBadgeLayout {
    /// Vertical distance kept between the badge centre and the plot edges.
    static let edgeInset: CGFloat = 12

    /// The height of the centre of the badge for a price at `priceY` (from the top of the plot), pressed into the plot.
    static func centerY(priceY: CGFloat, plotHeight: CGFloat) -> CGFloat {
        Swift.min(Swift.max(priceY, edgeInset), Swift.max(plotHeight - edgeInset, edgeInset))
    }

    /// The rectangle of the badge of `size` pressed to the right edge of a pane `chartWidth` wide, in the coordinates of the
    /// plot (whose top is the top of the pane).
    static func rect(size: CGSize, priceY: CGFloat, plotHeight: CGFloat, chartWidth: CGFloat) -> CGRect {
        let centerY = centerY(priceY: priceY, plotHeight: plotHeight)
        return CGRect(x: chartWidth - size.width, y: centerY - size.height / 2, width: size.width, height: size.height)
    }
}

/// The current price badge on the price scale: pressed to the right edge of the chart, over the column of price labels,
/// at the height of the price. It is at least as wide as that column's labels and reaches into the plot only when the
/// price is wider than the column.
///
/// At the live edge it is a plain label. When the window is scrolled into the past it becomes a button
/// (with a chevron) that returns to the live edge.
@available(iOS 17.0, *)
struct PriceBadgeOverlay: View {
    let model: TradingChartModel
    let price: Double
    /// The plot area of the pane; bounds the badge vertically.
    let plot: CGRect
    /// The width of the whole chart (plot and price axis column).
    let chartWidth: CGFloat

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter
    @Environment(\.tradingChartStrings) private var strings

    /// Horizontal padding inside the badge, shared with ``PriceBadgeWidthProbe``.
    static let horizontalPadding: CGFloat = 6

    var body: some View {
        // The Y follows the autoscaled domain on every scroll step; this small view is all that is evaluated for it.
        let yPosition = YMapping(domain: model.mainYTarget, height: plot.height).y(of: price)
        if plot.height > 0 {
            let atLiveEdge = model.isAtLiveEdge
            let clampedY = plot.minY + PriceBadgeLayout.centerY(priceY: yPosition, plotHeight: plot.height)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if atLiveEdge {
                    badge(showsJumpArrow: false)
                } else {
                    Button {
                        model.scrollToLiveEdge()
                    } label: {
                        badge(showsJumpArrow: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: strings.scrollToLatest))
                }
            }
            .frame(width: chartWidth)
            .position(x: chartWidth / 2, y: clampedY)
            // The only animation of the badge, keyed by the price: position, background and text move in one
            // transaction (nested springs with different periods pull the background and the label apart),
            // and while scrolling (the price does not change) the badge follows the domain instantly.
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: price)
            .allowsHitTesting(!atLiveEdge)
        }
    }

    private func badge(showsJumpArrow: Bool) -> some View {
        HStack(spacing: 3) {
            Text(priceFormatter.format(price, context: .badge))
                .font(theme.priceBadgeFont)
                .contentTransition(.numericText())
            if showsJumpArrow {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(theme.priceBadgeText)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 2)
        .frame(minWidth: theme.yAxisLabelWidth)
        .background(
            (theme.priceBadgeBackground ?? theme.line)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        )
        // What keeps clear of the badge (the high/low labels) needs its measured size, with the chevron when it has one.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            model.updateBadgeSize(size)
        }
    }
}

/// An invisible copy of the badge label that reports the badge width (without the return chevron) to the model.
/// The model compares it with the width of the price axis column to see how far the badge reaches into the plot.
@available(iOS 17.0, *)
struct PriceBadgeWidthProbe: View {
    let model: TradingChartModel
    let price: Double

    @Environment(\.tradingChartTheme) private var theme
    @Environment(\.tradingChartPriceFormatter) private var priceFormatter

    var body: some View {
        Text(priceFormatter.format(price, context: .badge))
            .font(theme.priceBadgeFont)
            .fixedSize()
            .padding(.horizontal, PriceBadgeOverlay.horizontalPadding)
            .frame(minWidth: theme.yAxisLabelWidth)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                model.updateLayoutMetrics(badgeWidth: width)
            }
            .hidden()
    }
}
