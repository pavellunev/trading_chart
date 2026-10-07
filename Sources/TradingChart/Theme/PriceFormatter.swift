import Foundation

/// Turns prices into strings. Inject one with the `tradingChartPriceFormatter(_:)` view modifier.
@available(iOS 17.0, *)
public struct PriceFormatter: Sendable {
    /// Where a formatted price appears; lets a formatter vary the precision.
    public enum Context: Sendable {
        /// A price axis label.
        case axis
        /// The current price badge.
        case badge
        /// A crosshair label.
        case crosshair
        /// The legend of a price pane and the crosshair tooltip.
        case legend
        /// A volume or a value of an indicator pane in the legend and the tooltip: large numbers are abbreviated.
        case compact
    }

    private let formatter: @Sendable (Double, Context) -> String

    /// Creates a formatter that depends on the context.
    public init(_ format: @escaping @Sendable (Double, Context) -> String) {
        self.formatter = format
    }

    /// Creates a formatter that uses one format everywhere.
    public init(_ format: @escaping @Sendable (Double) -> String) {
        self.formatter = { value, _ in format(value) }
    }

    /// The formatted price.
    public func format(_ value: Double, context: Context) -> String {
        formatter(value, context)
    }

    /// Chooses the number of decimals from the magnitude of the price.
    ///
    /// - `100` and above: 2 decimals; `10..<100`: 3; `1..<10`: 4; below `1`: 4 significant digits.
    /// - Axis labels drop trailing zeros; every other context keeps the full precision.
    /// - ``Context/compact`` abbreviates thousands, millions, billions and trillions (`1.15K`, `99.2M`) and keeps
    ///   up to two decimals (four significant digits below `1`), without trailing zeros.
    public static let automatic = PriceFormatter { value, context in
        automaticString(value, context: context, locale: .autoupdatingCurrent)
    }

    /// Always shows exactly `count` decimals.
    public static func fractionDigits(_ count: Int) -> PriceFormatter {
        let digits = max(count, 0)
        return PriceFormatter { value in
            fixedString(value, fractionDigits: digits, trimsTrailingZeros: false, locale: .autoupdatingCurrent)
        }
    }

    static func automaticString(_ value: Double, context: Context, locale: Locale) -> String {
        guard value.isFinite else { return "\(value)" }
        let magnitude = abs(value)
        guard magnitude > 0 else { return "0" }
        if context == .compact { return compactString(value, locale: locale) }
        let digits: Int
        switch magnitude {
        case 100...: digits = 2
        case 10...: digits = 3
        case 1...: digits = 4
        default:
            let exponent = Int(log10(magnitude).rounded(.down))
            digits = min(3 - exponent, 12)
        }
        return fixedString(value, fractionDigits: digits, trimsTrailingZeros: context == .axis, locale: locale)
    }

    /// `1_150` is `1.15K`, `99_200_000` is `99.2M`; below 1000 up to two decimals, below 1 four significant digits.
    static func compactString(_ value: Double, locale: Locale) -> String {
        let suffixes = ["", "K", "M", "B", "T"]
        var scaled = value
        var level = 0
        while abs(scaled) >= 1_000, level < suffixes.count - 1 {
            scaled /= 1_000
            level += 1
        }
        // 999_999 is 999.999K, which rounds to 1,000.00K: move it up one level instead.
        if abs((scaled * 100).rounded() / 100) >= 1_000, level < suffixes.count - 1 {
            scaled /= 1_000
            level += 1
        }
        let magnitude = abs(scaled)
        let digits: Int
        if magnitude >= 1 || magnitude == 0 {
            digits = 2
        } else {
            digits = min(3 - Int(log10(magnitude).rounded(.down)), 12)
        }
        let text = scaled.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(0...digits))
        )
        return text + suffixes[level]
    }

    static func fixedString(_ value: Double, fractionDigits: Int, trimsTrailingZeros: Bool, locale: Locale) -> String {
        let lowest = trimsTrailingZeros ? 0 : fractionDigits
        return value.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(lowest...fractionDigits))
        )
    }
}
