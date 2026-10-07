import Foundation

/// A UI-framework-independent RGBA color with components in `0...1`.
public struct ChartColor: Hashable, Sendable, Codable {
    /// Red component.
    public var red: Double
    /// Green component.
    public var green: Double
    /// Blue component.
    public var blue: Double
    /// Opacity (alpha).
    public var opacity: Double

    /// Creates a color from components in `0...1`.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Creates a color from a hex string: `RGB`, `RRGGBB` or `RRGGBBAA`, with an optional leading `#`.
    ///
    /// Returns `nil` for any other length or for non-hex characters.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        let expanded: String
        switch digits.count {
        case 3:
            expanded = digits.map { "\($0)\($0)" }.joined() + "FF"
        case 6:
            expanded = digits + "FF"
        case 8:
            expanded = digits
        default:
            return nil
        }
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}
