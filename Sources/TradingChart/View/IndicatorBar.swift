import SwiftUI
import TradingChartCore

/// A row of indicator switches in the style of exchange apps: `MA  EMA  BOLL  |  VOL  MACD  RSI`.
///
/// The row lists the indicators of a catalog by their ``ChartIndicator/shortName``: first the overlays, then a divider,
/// then the indicators that get a pane of their own. An indicator that is on is drawn in the selected colour and
/// semibold, the others in the secondary colour, with no chip or background. A tap switches an indicator in
/// ``TradingChartModel/indicators``; the indicators of the catalog always stay in the order of the catalog, which also
/// fixes their colours. The row scrolls sideways when it does not fit, and shows no scroll indicator.
///
/// ```swift
/// IndicatorBar(model: model, catalog: [SMA(), EMA(), BollingerBands(), Volume(), MACD(), RSI()])
///
/// IndicatorBar(model: model, catalog: catalog) {
///     Button("Settings", systemImage: "gearshape") { showsSettings = true }
/// }
/// ```
///
/// Fonts, colours and sizes come from the theme (``TradingChartTheme/indicatorBarFont``, ``TradingChartTheme/indicatorBarSpacing``,
/// ``TradingChartTheme/indicatorBarHeight`` and their siblings); the defaults are compact: 13 pt labels 14 pt apart in a row 30 pt high.
@available(iOS 17.0, *)
public struct IndicatorBar<Accessory: View>: View {
    private let model: TradingChartModel
    private let catalog: [any ChartIndicator]
    private let accessory: Accessory

    @Environment(\.tradingChartTheme) private var theme

    /// Creates a bar with a view after the scrolling row, for example a settings button.
    ///
    /// - Parameters:
    ///   - model: The chart whose ``TradingChartModel/indicators`` the bar switches.
    ///   - catalog: The indicators on offer, in the order they are listed and drawn. Repeated ids are listed once.
    ///   - accessory: A view pinned to the trailing edge, outside the scrolling row.
    public init(
        model: TradingChartModel,
        catalog: [any ChartIndicator],
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.model = model
        self.catalog = catalog
        self.accessory = accessory()
    }

    /// The bar.
    public var body: some View {
        let groups = IndicatorSelection.groups(of: catalog)
        let selected = Set(model.indicators.map(\.id))
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(groups.overlays, id: \.id) { item($0, isSelected: selected.contains($0.id)) }
                    if !groups.overlays.isEmpty, !groups.panes.isEmpty {
                        Rectangle()
                            .fill(theme.indicatorBarDivider)
                            .frame(width: 1, height: 14)
                            .padding(.horizontal, 2)
                            .accessibilityHidden(true)
                    }
                    ForEach(groups.panes, id: \.id) { item($0, isSelected: selected.contains($0.id)) }
                }
            }
            .scrollIndicators(.hidden)
            accessory
        }
        .frame(height: theme.indicatorBarHeight)
    }

    /// A label with half the spacing of the theme on each side, so that the gap between two labels is the spacing, and the
    /// whole height of the bar (and half the gap on each side) is the tap target.
    private func item(_ indicator: any ChartIndicator, isSelected: Bool) -> some View {
        Button {
            model.indicators = IndicatorSelection.toggled(model.indicators, toggling: indicator, catalog: catalog)
        } label: {
            Text(indicator.shortName)
                .font(theme.indicatorBarFont)
                .fontWeight(isSelected ? .semibold : nil)
                .foregroundStyle(isSelected ? theme.indicatorBarSelected : theme.indicatorBarUnselected)
                .lineLimit(1)
                .padding(.horizontal, theme.indicatorBarSpacing / 2)
                .padding(.vertical, 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(indicator.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@available(iOS 17.0, *)
extension IndicatorBar where Accessory == EmptyView {
    /// Creates a bar without an accessory.
    ///
    /// - Parameters:
    ///   - model: The chart whose ``TradingChartModel/indicators`` the bar switches.
    ///   - catalog: The indicators on offer, in the order they are listed and drawn. Repeated ids are listed once.
    public init(model: TradingChartModel, catalog: [any ChartIndicator]) {
        self.init(model: model, catalog: catalog) { EmptyView() }
    }
}
