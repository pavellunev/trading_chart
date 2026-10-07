import SwiftUI

@available(iOS 17.0, *)
extension EnvironmentValues {
    @Entry var tradingChartTheme = TradingChartTheme.standard
    @Entry var tradingChartPriceFormatter = PriceFormatter.automatic
    @Entry var tradingChartTimeFormatter = TimeFormatter.automatic
    @Entry var tradingChartStrings = TradingChartStrings.standard
    /// The layout direction of the host of the chart; the chart itself is always laid out left to right.
    @Entry var tradingChartHostLayoutDirection = LayoutDirection.leftToRight
}

@available(iOS 17.0, *)
extension View {
    /// Sets the theme of the charts in this view hierarchy.
    public func tradingChartTheme(_ theme: TradingChartTheme) -> some View {
        environment(\.tradingChartTheme, theme)
    }

    /// Sets how the charts in this view hierarchy format prices.
    public func tradingChartPriceFormatter(_ formatter: PriceFormatter) -> some View {
        environment(\.tradingChartPriceFormatter, formatter)
    }

    /// Sets how the charts in this view hierarchy format times.
    public func tradingChartTimeFormatter(_ formatter: TimeFormatter) -> some View {
        environment(\.tradingChartTimeFormatter, formatter)
    }

    /// Sets the words the charts in this view hierarchy say: the VoiceOver texts, the badge and the tooltip.
    public func tradingChartStrings(_ strings: TradingChartStrings) -> some View {
        environment(\.tradingChartStrings, strings)
    }
}
