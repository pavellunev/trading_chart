import SwiftUI
import TradingChartCore

@available(iOS 17.0, *)
extension Color {
    /// A SwiftUI color for a platform-neutral ``ChartColor``.
    init(_ color: ChartColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}
