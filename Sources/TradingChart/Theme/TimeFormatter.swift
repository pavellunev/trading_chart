import Foundation
import TradingChartCore

/// Turns bar times into strings. Inject one with the `tradingChartTimeFormatter(_:)` view modifier.
@available(iOS 17.0, *)
public struct TimeFormatter: Sendable {
    /// Where a formatted time appears.
    public enum Context: Sendable {
        /// A time axis label.
        case axis
        /// A crosshair label.
        case crosshair
    }

    private let formatter: @Sendable (Date, ChartInterval, Context) -> String

    /// Creates a formatter from the time, the interval of the series and the context.
    public init(_ format: @escaping @Sendable (Date, ChartInterval, Context) -> String) {
        self.formatter = format
    }

    /// The formatted time.
    public func format(_ date: Date, interval: ChartInterval, context: Context) -> String {
        formatter(date, interval, context)
    }

    /// Chooses the format from the bar interval.
    ///
    /// Axis labels: `HH:mm` below one hour, day and month below one week, month and year from one week.
    /// Crosshair labels always show day, month and `HH:mm`.
    public static let automatic = TimeFormatter { date, interval, context in
        automaticString(date, interval: interval, context: context, locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)
    }

    static func automaticString(
        _ date: Date,
        interval: ChartInterval,
        context: Context,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        switch context {
        case .axis:
            if interval.seconds < 3_600 {
                return hoursAndMinutes(date, locale: locale, timeZone: timeZone)
            }
            var style = Date.FormatStyle.dateTime.day(.twoDigits).month(.abbreviated)
            if interval.seconds >= 604_800 {
                style = Date.FormatStyle.dateTime.month(.abbreviated).year(.twoDigits)
            }
            return styled(date, style, locale: locale, timeZone: timeZone)
        case .crosshair:
            let day = styled(
                date,
                Date.FormatStyle.dateTime.day(.twoDigits).month(.abbreviated),
                locale: locale,
                timeZone: timeZone
            )
            return day + " " + hoursAndMinutes(date, locale: locale, timeZone: timeZone)
        }
    }

    private static func styled(_ date: Date, _ style: Date.FormatStyle, locale: Locale, timeZone: TimeZone) -> String {
        var style = style
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// `HH:mm` on a 24-hour clock regardless of the locale.
    private static func hoursAndMinutes(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: locale,
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return date.formatted(style)
    }
}
