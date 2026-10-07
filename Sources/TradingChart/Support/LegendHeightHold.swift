import CoreGraphics
import Foundation
import SwiftUI
import TradingChartCore

/// The least height a legend takes, and the width it was measured at: it holds only at that width.
@available(iOS 17.0, *)
struct LegendHeightFloor: Equatable {
    var width: CGFloat
    var height: CGFloat

    /// Widths closer than this are the same width (sub-point layout noise).
    static let widthTolerance: CGFloat = 0.5

    /// `size` as tall as the floor, when it is as wide as the floor was measured at; any other width is laid out as it is.
    func applied(to size: CGSize) -> CGSize {
        guard abs(size.width - width) < Self.widthTolerance else { return size }
        return CGSize(width: size.width, height: Swift.max(size.height, height))
    }
}

/// What keeps the number of lines of a legend from jumping, which would move the plot below it up and down. The crosshair moves
/// over bars whose values have fewer or more digits, and a live tick changes the digits of the newest bar, so the text of the
/// legend wraps differently from one moment to the next.
///
/// The height of the legend only grows while the legend stays what it was measured as: the same ``Key`` (what it lists, and
/// whatever changes how its text is made and laid out), the same width. It is measured again (and may shrink) when any of them
/// changes, and when the crosshair ends (``crosshairEnded()``). Pure: the view measures the legend, feeds ``observe(_:key:)`` and
/// lays the legend out with ``floor(for:)`` as its least height.
@available(iOS 17.0, *)
struct LegendHeightHold: Equatable {
    /// What the legend is: when any part of it changes the legend is another one, and what was held of the old one is dropped.
    ///
    /// Everything that changes the number of lines without the crosshair or a tick is in it: what the legend lists, whether it
    /// is shown, whether the style picker shortens its first line, the font and the price formatter. Closures cannot be
    /// compared, so the formatter is its ``PriceFormatter/identity``: the key changes when the host replaces the formatter,
    /// whatever the new one formats.
    struct Key: Hashable {
        var indicatorIDs: [String]
        var style: SeriesStyle
        var showsLegend = true
        var hasStylePicker = false
        var font = TradingChartTheme.standard.legendFont
        var formatter = PriceFormatter.automatic.identity
    }

    /// What a measurement is of: a view keyed by it is made anew, and reports its size anew, whenever it changes.
    struct Token: Hashable {
        var key: Key
        var generation: Int
    }

    private(set) var key: Key?
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    private var generation = 0

    func token(for key: Key) -> Token {
        Token(key: key, generation: generation)
    }

    /// The least height of the legend of `key`: what it measured as before, or `nil` when it is not the legend that was measured.
    func floor(for key: Key) -> LegendHeightFloor? {
        key == self.key ? LegendHeightFloor(width: width, height: height) : nil
    }

    /// The measured size of the legend of `key`: it adds to what is held at the same width, and starts a new measurement for
    /// another legend or another width.
    mutating func observe(_ size: CGSize, key: Key) {
        if key == self.key, abs(size.width - width) < LegendHeightFloor.widthTolerance {
            height = Swift.max(height, size.height)
        } else {
            self.key = key
            width = size.width
            height = size.height
        }
    }

    /// The crosshair ended: what is held is dropped, and the next measurement (which the new ``token(for:)`` brings) is of the
    /// legend as it is, however much shorter that is.
    mutating func crosshairEnded() {
        key = nil
        width = 0
        height = 0
        generation += 1
    }
}
