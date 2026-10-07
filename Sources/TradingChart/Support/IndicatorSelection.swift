import TradingChartCore

/// Which indicators of a catalog are on, and how a tap on one changes that. Pure.
@available(iOS 17.0, *)
enum IndicatorSelection {

    /// The catalog without repeated ids (the first of a kind wins), split into overlays and panes, in catalog order.
    static func groups(of catalog: [any ChartIndicator]) -> (overlays: [any ChartIndicator], panes: [any ChartIndicator]) {
        var seen = Set<String>()
        let unique = catalog.filter { seen.insert($0.id).inserted }
        return (
            unique.filter { $0.placement == .overlay },
            unique.filter { $0.placement == .pane }
        )
    }

    /// `current` after a tap on `indicator`: switched off when it is in `current` (matched by id), switched on otherwise.
    ///
    /// The indicators of `catalog` come out in the order of the catalog, whatever order they were switched on in;
    /// an indicator that is already on keeps its own instance (and so its style). Indicators of `current` that the
    /// catalog does not know stay, after the catalog ones, in their original order.
    static func toggled(
        _ current: [any ChartIndicator],
        toggling indicator: any ChartIndicator,
        catalog: [any ChartIndicator]
    ) -> [any ChartIndicator] {
        var selected: [String: any ChartIndicator] = [:]
        for item in current where selected[item.id] == nil {
            selected[item.id] = item
        }
        if selected[indicator.id] != nil {
            selected[indicator.id] = nil
        } else {
            selected[indicator.id] = indicator
        }

        var placed = Set<String>()
        var result: [any ChartIndicator] = []
        for item in catalog where placed.insert(item.id).inserted {
            if let kept = selected[item.id] { result.append(kept) }
        }
        for item in current where !placed.contains(item.id) && selected[item.id] != nil {
            placed.insert(item.id)
            result.append(item)
        }
        if let added = selected[indicator.id], !placed.contains(indicator.id) {
            result.append(added)
        }
        return result
    }
}
