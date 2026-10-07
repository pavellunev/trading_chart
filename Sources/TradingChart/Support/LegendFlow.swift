import CoreGraphics

/// One unbreakable piece of a legend as the flow sees it: its size, and the gap that sets it apart from the item before it
/// when they share a line.
@available(iOS 17.0, *)
struct LegendFlowItem: Equatable {
    var size: CGSize
    var gapBefore: CGFloat
    /// Whether the item stays on one line with the item before it (the title of an indicator with its first value), as long as
    /// the two of them fit a line.
    var joinsPrevious = false
}

/// Where the items of a legend go: left to right, each on the line where it fits, the next line when it does not. Pure; the
/// layout of the legend (``LegendFlowLayout``) only measures its subviews and places them where this says.
///
/// - The first line is shorter by the width of the *accessory* (the style picker), which sits at the trailing edge of it, and
///   as tall as the accessory when that is taller than a line of text, so the lines below clear it. The text and the accessory
///   are centred vertically in the first line.
/// - An item that is wider than a line by itself keeps a line of its own and is narrowed to it (its text is truncated).
/// - An item that joins the one before it makes a unit with it: the unit goes to the next line when it does not fit after what
///   is on the line, and so a title is never left at the end of a line with its value at the start of the next. That holds for
///   the first line too: a unit that does not fit beside the accessory but fits a whole line leaves the first line to the
///   accessory and starts the second. A unit that is wider than a line by itself falls apart into its items, which flow one by
///   one.
/// - Every line has `verticalInset` above and below the text and the whole legend `horizontalInset` on both sides, which is
///   the padding the legend had as a single line.
@available(iOS 17.0, *)
enum LegendFlow {
    /// The space at the left and the right of the text.
    static let horizontalInset: CGFloat = 4
    /// The space above and below the text of a line.
    static let verticalInset: CGFloat = 2
    /// The gap between two items of one indicator.
    static let itemGap: CGFloat = 4
    /// The gap before the first item of an indicator that follows another one on the same line.
    static let groupGap: CGFloat = 10

    /// Where everything is, in the space of the legend (its top left corner is the origin).
    struct Placement: Equatable {
        /// The frame of every item, in the order they were given.
        var frames: [CGRect]
        /// The frame of the accessory: at the trailing edge, on the first line.
        var accessory: CGRect?
        /// The lines that hold text (a first line with only the accessory on it is not one).
        var lineCount: Int
        /// The size the legend takes.
        var size: CGSize
    }

    /// - Parameters:
    ///   - items: The items in reading order.
    ///   - accessory: The size of the control at the trailing edge of the first line, if there is one.
    ///   - width: The width to lay out in; `nil` puts everything on one line and takes the width that needs.
    static func place(_ items: [LegendFlowItem], accessory: CGSize? = nil, width: CGFloat?) -> Placement {
        let accessory = accessory.flatMap { $0.width > 0 || $0.height > 0 ? $0 : nil }
        let accessoryWidth = accessory?.width ?? 0
        let width = width.map { Swift.max($0, 0) }

        func available(onLine line: Int) -> CGFloat? {
            width.map { Swift.max($0 - 2 * horizontalInset - (line == 0 ? accessoryWidth : 0), 0) }
        }

        // Break into lines: an item that does not fit after the ones already on the line starts the next one, and so does a unit
        // of joined items that does not fit as a whole.
        var lines: [[Int]] = []
        var lineWidths: [CGFloat] = []
        var widths: [CGFloat] = []

        func append(_ index: Int) {
            let item = items[index]
            var line = Swift.max(lines.count - 1, 0)
            if lines.isEmpty {
                lines.append([])
                lineWidths.append(0)
            }
            if !lines[line].isEmpty, let limit = available(onLine: line),
               lineWidths[line] + item.gapBefore + item.size.width > limit + 0.001 {
                lines.append([])
                lineWidths.append(0)
                line += 1
            }
            let gap = lines[line].isEmpty ? 0 : item.gapBefore
            let itemWidth = available(onLine: line).map { Swift.min(item.size.width, $0) } ?? item.size.width
            lines[line].append(index)
            lineWidths[line] += gap + itemWidth
            widths.append(itemWidth)
        }

        var start = 0
        while start < items.count {
            var end = start + 1
            while end < items.count, items[end].joinsPrevious { end += 1 }
            let line = Swift.max(lines.count - 1, 0)
            if end - start > 1, let room = available(onLine: line), let nextRoom = available(onLine: line + 1) {
                // The unit as one piece: where it would end after what is on the line (nothing is, and no gap, at the very start),
                // and what it takes on a line of its own.
                let alone = items[start..<end].dropFirst().reduce(items[start].size.width) { $0 + $1.gapBefore + $1.size.width }
                let before = lines.isEmpty ? 0 : lineWidths[line] + items[start].gapBefore
                if before + alone > room + 0.001, alone <= nextRoom + 0.001 {
                    // At the start the first line stays empty, for the accessory alone.
                    if lines.isEmpty {
                        lines.append([])
                        lineWidths.append(0)
                    }
                    lines.append([])
                    lineWidths.append(0)
                }
            }
            for index in start..<end { append(index) }
            start = end
        }

        // Stack the lines: a line is as tall as its tallest item plus the insets, the first at least as tall as the accessory, which
        // is centred in it.
        var frames = [CGRect](repeating: .zero, count: items.count)
        var top: CGFloat = 0
        var firstBand = accessory?.height ?? 0
        for (line, indices) in lines.enumerated() {
            let textHeight = indices.map { items[$0].size.height }.max() ?? 0
            var band = textHeight + 2 * verticalInset
            if line == 0, let accessory { band = Swift.max(band, accessory.height) }
            if line == 0 { firstBand = band }
            var x = horizontalInset
            for (position, index) in indices.enumerated() {
                if position > 0 { x += items[index].gapBefore }
                let height = items[index].size.height
                frames[index] = CGRect(x: x, y: top + (band - height) / 2, width: widths[index], height: height)
                x += widths[index]
            }
            top += band
        }
        if lines.isEmpty, let accessory { top = accessory.height }

        let natural = lines.isEmpty && accessory == nil ? 0 : (lineWidths.first ?? 0) + 2 * horizontalInset + accessoryWidth
        let totalWidth = width ?? natural
        return Placement(
            frames: frames,
            accessory: accessory.map {
                CGRect(x: totalWidth - $0.width, y: (firstBand - $0.height) / 2, width: $0.width, height: $0.height)
            },
            lineCount: lines.filter { !$0.isEmpty }.count,
            size: CGSize(width: totalWidth, height: top)
        )
    }
}
