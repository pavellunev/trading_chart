import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import TradingChart

/// Where the items of a legend go: decided on sizes, with no view.
@Suite("Legend flow")
struct LegendFlowTests {
    /// An item of `width` points, one line of text tall; `gap` separates it from the item before it.
    private func item(_ width: CGFloat, gap: CGFloat = LegendFlow.itemGap, joins: Bool = false) -> LegendFlowItem {
        LegendFlowItem(size: CGSize(width: width, height: 13), gapBefore: gap, joinsPrevious: joins)
    }

    private let picker = CGSize(width: 44, height: 24)

    @Test("items that fit go on one line, left to right, with the gap of each before it")
    func oneLine() {
        let placement = LegendFlow.place([item(50), item(40), item(30, gap: 10)], width: 300)

        #expect(placement.frames == [
            CGRect(x: 4, y: 2, width: 50, height: 13),
            CGRect(x: 58, y: 2, width: 40, height: 13),
            CGRect(x: 108, y: 2, width: 30, height: 13),
        ])
        #expect(placement.lineCount == 1)
        #expect(placement.size == CGSize(width: 300, height: 17))
        #expect(placement.accessory == nil)
    }

    @Test("an item that does not fit after the ones on the line goes to the next line, whole")
    func wraps() {
        // 4 + 50 + 4 + 40 = 98 fits in 120 - 4, the 30 behind a gap of 10 would end at 138.
        let placement = LegendFlow.place([item(50), item(40), item(30, gap: 10)], width: 120)

        #expect(placement.frames[0] == CGRect(x: 4, y: 2, width: 50, height: 13))
        #expect(placement.frames[1] == CGRect(x: 58, y: 2, width: 40, height: 13))
        // The gap is for the neighbour on the same line: at the start of a line the item is at the inset.
        #expect(placement.frames[2] == CGRect(x: 4, y: 19, width: 30, height: 13))
        #expect(placement.lineCount == 2)
        #expect(placement.size == CGSize(width: 120, height: 34))
    }

    @Test("an item is never split: it stays on its line when it just fits and leaves for the next when it is a point too wide")
    func exactFit() {
        // The room of a line is 100 - 2 * 4 = 92: 40 + 4 + 48 = 92 fits, 40 + 4 + 49 does not.
        #expect(LegendFlow.place([item(40), item(48)], width: 100).lineCount == 1)
        let wider = LegendFlow.place([item(40), item(49)], width: 100)
        #expect(wider.lineCount == 2)
        #expect(wider.frames[1].width == 49)
    }

    @Test("an item wider than a line keeps a line of its own and is narrowed to it")
    func tooWideAlone() {
        let placement = LegendFlow.place([item(30), item(200), item(20)], width: 100)

        #expect(placement.frames[0] == CGRect(x: 4, y: 2, width: 30, height: 13))
        #expect(placement.frames[1] == CGRect(x: 4, y: 19, width: 92, height: 13))
        #expect(placement.frames[2] == CGRect(x: 4, y: 36, width: 20, height: 13))
        #expect(placement.lineCount == 3)
    }

    @Test("the height of the legend is 17, 34 and 51 points for one, two and three lines of 13 point text")
    func heights() {
        let items = [item(60), item(60), item(60)]
        #expect(LegendFlow.place(items, width: 400).size.height == 17)
        #expect(LegendFlow.place(items, width: 140).size.height == 34)
        #expect(LegendFlow.place(items, width: 80).size.height == 51)
        #expect(LegendFlow.place(items, width: 80).lineCount == 3)
    }

    @Test("no items take no height, with or without room")
    func empty() {
        let placement = LegendFlow.place([], width: 320)
        #expect(placement.size == CGSize(width: 320, height: 0))
        #expect(placement.lineCount == 0)
        #expect(LegendFlow.place([], width: nil).size == .zero)
    }

    @Test("without a width everything is one line, as wide as it is")
    func naturalWidth() {
        let items = [item(50), item(40), item(30, gap: 10)]
        let natural = LegendFlow.place(items, width: nil)

        #expect(natural.lineCount == 1)
        #expect(natural.size == CGSize(width: 4 + 50 + 4 + 40 + 10 + 30 + 4, height: 17))
        // Laid out at that width again, nothing wraps.
        let again = LegendFlow.place(items, width: natural.size.width)
        #expect(again.lineCount == 1)
        #expect(again.frames == natural.frames)
    }

    @Test("the picker is at the trailing edge of the first line, which is as tall as it is, with the text centred in it")
    func pickerPosition() {
        let placement = LegendFlow.place([item(50), item(40)], accessory: picker, width: 300)

        #expect(placement.accessory == CGRect(x: 256, y: 0, width: 44, height: 24))
        // One line with the picker is as tall as the picker (the row the legend always had).
        #expect(placement.size == CGSize(width: 300, height: 24))
        #expect(placement.frames[0] == CGRect(x: 4, y: 5.5, width: 50, height: 13))
        #expect(placement.lineCount == 1)
    }

    @Test("the picker takes its width from the first line only, and the lines below clear it")
    func pickerAndWrapping() {
        // The first line has 200 - 8 - 44 = 148: the two items take 60 + 4 + 60 = 124, the third (4 + 60) does not fit.
        let placement = LegendFlow.place([item(60), item(60), item(60)], accessory: picker, width: 200)

        #expect(placement.accessory == CGRect(x: 156, y: 0, width: 44, height: 24))
        #expect(placement.frames[1] == CGRect(x: 68, y: 5.5, width: 60, height: 13))
        // The second line has the whole width and starts under the picker, not beside its lower part.
        #expect(placement.frames[2] == CGRect(x: 4, y: 26, width: 60, height: 13))
        #expect(placement.size == CGSize(width: 200, height: 24 + 17))
        #expect(placement.lineCount == 2)
    }

    @Test("a second line is not narrowed by the picker: what fits in the whole width stays on it")
    func secondLineIsFull() {
        // 60 + 4 + 60 + 4 + 60 = 188 fits in 200 - 8 on a line of its own, but not on the first (148).
        let placement = LegendFlow.place(
            [item(100), item(60), item(60), item(60)],
            accessory: picker,
            width: 200
        )
        #expect(placement.frames[0].minY == 5.5)
        #expect(placement.frames[1].minY == 26)
        #expect(placement.frames[2].minY == 26)
        #expect(placement.frames[3].minY == 26)
        #expect(placement.lineCount == 2)
    }

    @Test("a title that would end a line goes to the next with the value after it, instead of being left behind")
    func titleStaysWithItsValue() {
        // A line has 200 - 8 = 192. `first` and the title end at 100 + 10 + 50 = 160, the title and its value would end at
        // 160 + 4 + 60 = 224.
        let items = [item(100), item(50, gap: 10), item(60, joins: true), item(60)]
        let placement = LegendFlow.place(items, width: 200)

        #expect(placement.frames[0] == CGRect(x: 4, y: 2, width: 100, height: 13))
        #expect(placement.frames[1] == CGRect(x: 4, y: 19, width: 50, height: 13))
        #expect(placement.frames[2] == CGRect(x: 58, y: 19, width: 60, height: 13))
        // Only the first value is held to the title: the next goes where it fits (here the second line has 4 + 50 + 4 + 60 + 4 + 60).
        #expect(placement.frames[3] == CGRect(x: 122, y: 19, width: 60, height: 13))
        #expect(placement.lineCount == 2)

        // Without the join the title stays at the end of the first line and the value starts the next, as before.
        let apart = LegendFlow.place([item(100), item(50, gap: 10), item(60), item(60)], width: 200)
        #expect(apart.frames[1].minY == 2)
        #expect(apart.frames[2] == CGRect(x: 4, y: 19, width: 60, height: 13))
    }

    @Test("a title and its value that fit after what is on the line stay on it")
    func unitThatFitsStays() {
        let placement = LegendFlow.place([item(60), item(40, gap: 10), item(60, joins: true)], width: 200)
        // 4 + 60 + 10 + 40 + 4 + 60 = 178 <= 192.
        #expect(placement.lineCount == 1)
        #expect(placement.frames[1].minX == 74)
        #expect(placement.frames[2].minX == 118)
    }

    @Test("the unit is measured against the first line, which the picker shortens, and the next line, which it does not")
    func unitAndPicker() {
        // The first line has 200 - 8 - 44 = 148: 60 + 10 + 40 = 110 fits, with the value (+ 4 + 60) it is 174. The unit is
        // 40 + 4 + 60 = 104 on a line of its own, which has 192.
        let placement = LegendFlow.place(
            [item(60), item(40, gap: 10), item(60, joins: true)],
            accessory: picker,
            width: 200
        )
        #expect(placement.frames[0].minY == 5.5)
        #expect(placement.frames[1] == CGRect(x: 4, y: 26, width: 40, height: 13))
        #expect(placement.frames[2] == CGRect(x: 48, y: 26, width: 60, height: 13))
        #expect(placement.lineCount == 2)
    }

    @Test("a title and a value that are wider than a line together fall apart and flow one by one, as separate items do")
    func unitWiderThanALine() {
        // A line has 92. The unit is 50 + 4 + 60 = 114, wider than any line: the title stays after the 30 (30 + 10 + 50 = 90) and
        // the value goes to the next line.
        let placement = LegendFlow.place([item(30), item(50, gap: 10), item(60, joins: true)], width: 100)
        #expect(placement.frames[1] == CGRect(x: 44, y: 2, width: 50, height: 13))
        #expect(placement.frames[2] == CGRect(x: 4, y: 19, width: 60, height: 13))
        #expect(placement.lineCount == 2)

        // The same at the start of the legend: nothing to move the unit after.
        let first = LegendFlow.place([item(50), item(60, joins: true)], width: 100)
        #expect(first.frames[0].minY == 2)
        #expect(first.frames[1].minY == 19)
    }

    @Test("without a width a title and its value are on one line like everything else")
    func unitWithoutWidth() {
        let placement = LegendFlow.place([item(50), item(60, joins: true)], width: nil)
        #expect(placement.lineCount == 1)
        #expect(placement.size == CGSize(width: 4 + 50 + 4 + 60 + 4, height: 17))
    }

    @Test("the picker with no legend is a row of its own, the height of the picker, at the right")
    func pickerAlone() {
        let placement = LegendFlow.place([], accessory: picker, width: 320)

        #expect(placement.accessory == CGRect(x: 276, y: 0, width: 44, height: 24))
        #expect(placement.size == CGSize(width: 320, height: 24))
        #expect(placement.lineCount == 0)
    }

    @Test("a first item that does not fit beside the picker stays on the first line, narrowed")
    func firstItemBesideThePicker() {
        let placement = LegendFlow.place([item(120), item(30)], accessory: picker, width: 150)

        // 150 - 8 - 44 = 98 of room on the first line.
        #expect(placement.frames[0] == CGRect(x: 4, y: 5.5, width: 98, height: 13))
        #expect(placement.frames[1].minY == 26)
    }

    @Test("the picker is centred in the first line when the text makes it taller than the picker")
    func pickerCentredInATallLine() {
        // A big font: text 40 tall makes the first line 40 + 4 = 44, the picker (24) is 10 below its top.
        let tall = LegendFlowItem(size: CGSize(width: 60, height: 40), gapBefore: LegendFlow.itemGap)
        let placement = LegendFlow.place([tall, tall, tall], accessory: picker, width: 200)

        #expect(placement.accessory == CGRect(x: 156, y: 10, width: 44, height: 24))
        #expect(placement.frames[0] == CGRect(x: 4, y: 2, width: 60, height: 40))
        // The second line starts under the first, which is as tall as the text.
        #expect(placement.frames[2] == CGRect(x: 4, y: 46, width: 60, height: 40))
        #expect(placement.size == CGSize(width: 200, height: 88))

        // As tall as the picker the line is no taller than the picker, which fills it.
        #expect(LegendFlow.place([item(50)], accessory: picker, width: 200).accessory?.minY == 0)
        // A line of text that is as tall as the picker (20 + 4) leaves it at the top as well.
        let almost = LegendFlowItem(size: CGSize(width: 60, height: 20), gapBefore: LegendFlow.itemGap)
        #expect(LegendFlow.place([almost], accessory: picker, width: 200).accessory?.minY == 0)
    }

    @Test("the first unit of a title and its value that does not fit beside the picker, but fits a line, goes to the second line whole")
    func firstUnitBesidePicker() {
        // The first line has 200 - 8 - 44 = 148, a line below it 192. The unit is 60 + 4 + 100 = 164: too wide for the first line,
        // not for the second.
        let placement = LegendFlow.place([item(60), item(100, joins: true), item(30)], accessory: picker, width: 200)

        // The first line is the picker's alone.
        #expect(placement.accessory == CGRect(x: 156, y: 0, width: 44, height: 24))
        #expect(placement.frames[0] == CGRect(x: 4, y: 26, width: 60, height: 13))
        #expect(placement.frames[1] == CGRect(x: 68, y: 26, width: 100, height: 13))
        // What follows goes where it fits: 4 + 60 + 4 + 100 + 4 + 30 = 202 does not, so the next line.
        #expect(placement.frames[2] == CGRect(x: 4, y: 43, width: 30, height: 13))
        #expect(placement.lineCount == 2)
        #expect(placement.size == CGSize(width: 200, height: 24 + 17 + 17))
    }

    @Test("the first unit stays on the first line beside the picker when it fits there")
    func firstUnitThatFitsStays() {
        // 60 + 4 + 60 = 124 <= 148.
        let placement = LegendFlow.place([item(60), item(60, joins: true)], accessory: picker, width: 200)
        #expect(placement.frames[0] == CGRect(x: 4, y: 5.5, width: 60, height: 13))
        #expect(placement.frames[1] == CGRect(x: 68, y: 5.5, width: 60, height: 13))
        #expect(placement.lineCount == 1)
    }

    @Test("the first unit that is wider than a whole line falls apart beside the picker, as it does anywhere")
    func firstUnitWiderThanALineBesidePicker() {
        // 100 + 4 + 100 = 204 > 192: no line holds it. The title takes the first line (4 + 100 <= 148), the value the next.
        let placement = LegendFlow.place([item(100), item(100, joins: true)], accessory: picker, width: 200)
        #expect(placement.frames[0].minY == 5.5)
        #expect(placement.frames[1] == CGRect(x: 4, y: 26, width: 100, height: 13))
        #expect(placement.lineCount == 2)
    }

    @Test("without a picker the first unit is never moved: every line is as wide as the first")
    func firstUnitWithoutPicker() {
        let placement = LegendFlow.place([item(60), item(100, joins: true)], width: 160)
        // 60 + 4 + 100 = 164 > 152: it falls apart, the value takes the next line.
        #expect(placement.frames[0].minY == 2)
        #expect(placement.frames[1].minY == 19)
        #expect(placement.lineCount == 2)
    }
}

/// The floor under the height of a legend, and what holds it.
@Suite("Legend height hold")
struct LegendHeightHoldTests {
    private typealias Key = LegendHeightHold.Key
    private let bands = Key(indicatorIDs: ["sma", "bb"], style: .candles)

    @Test("the floor takes the legend up to the height it had, at the width it had, and never lowers it")
    func floorApplies() {
        let floor = LegendHeightFloor(width: 300, height: 51)
        #expect(floor.applied(to: CGSize(width: 300, height: 17)) == CGSize(width: 300, height: 51))
        #expect(floor.applied(to: CGSize(width: 300.3, height: 17)) == CGSize(width: 300.3, height: 51))
        #expect(floor.applied(to: CGSize(width: 300, height: 68)) == CGSize(width: 300, height: 68))
        // Another width is another layout: the legend is as tall as its text.
        #expect(floor.applied(to: CGSize(width: 320, height: 17)) == CGSize(width: 320, height: 17))
        #expect(floor.applied(to: CGSize(width: 280, height: 17)) == CGSize(width: 280, height: 17))
    }

    @Test("nothing is held before the legend is measured")
    func fresh() {
        let hold = LegendHeightHold()
        #expect(hold.floor(for: bands) == nil)
    }

    @Test("the height only grows while the indicators, the style and the width stay the same")
    func onlyGrows() {
        var hold = LegendHeightHold()
        hold.observe(CGSize(width: 300, height: 34), key: bands)
        #expect(hold.floor(for: bands) == LegendHeightFloor(width: 300, height: 34))

        hold.observe(CGSize(width: 300, height: 51), key: bands)
        #expect(hold.floor(for: bands)?.height == 51)
        // A shorter legend (fewer digits, fewer lines) reports a floor-sized one, and what is held does not move.
        hold.observe(CGSize(width: 300, height: 34), key: bands)
        hold.observe(CGSize(width: 300, height: 17), key: bands)
        #expect(hold.floor(for: bands)?.height == 51)
    }

    @Test("other indicators, another style or another width measure again, and the legend may shrink")
    func resets() {
        var hold = LegendHeightHold()
        hold.observe(CGSize(width: 300, height: 51), key: bands)

        // The floor is not for a legend that lists something else, even before it is measured.
        let fewer = Key(indicatorIDs: ["sma"], style: .candles)
        let line = Key(indicatorIDs: ["sma", "bb"], style: .line)
        #expect(hold.floor(for: fewer) == nil)
        #expect(hold.floor(for: line) == nil)

        var shrunk = hold
        shrunk.observe(CGSize(width: 300, height: 17), key: fewer)
        #expect(shrunk.floor(for: fewer)?.height == 17)
        #expect(shrunk.floor(for: bands) == nil)

        var styled = hold
        styled.observe(CGSize(width: 300, height: 34), key: line)
        #expect(styled.floor(for: line)?.height == 34)

        var wider = hold
        wider.observe(CGSize(width: 393, height: 17), key: bands)
        #expect(wider.floor(for: bands) == LegendHeightFloor(width: 393, height: 17))

        // A width a fraction of a point off is the same width.
        var same = hold
        same.observe(CGSize(width: 300.2, height: 34), key: bands)
        #expect(same.floor(for: bands)?.height == 51)
    }

    @Test("the legend being off, the style picker, the font and the formatter are part of what is held")
    func environmentIsPartOfTheKey() {
        var hold = LegendHeightHold()
        hold.observe(CGSize(width: 300, height: 51), key: bands)

        var off = bands
        off.showsLegend = false
        var picker = bands
        picker.hasStylePicker = true
        var font = bands
        font.font = .system(size: 20)
        var formatter = bands
        formatter.formatter = PriceFormatter.fractionDigits(2).identity
        for other in [off, picker, font, formatter] {
            #expect(hold.floor(for: other) == nil)
            var again = hold
            again.observe(CGSize(width: 300, height: 17), key: other)
            #expect(again.floor(for: other)?.height == 17)
            #expect(again.floor(for: bands) == nil)
        }
        // The same things as they were are the same legend.
        var same = bands
        same.font = TradingChartTheme.standard.legendFont
        same.formatter = PriceFormatter.automatic.identity
        #expect(hold.floor(for: same)?.height == 51)
    }

    @Test("a formatter is told from another by its identity: a copy is the same, one built anew is not, even when it formats alike")
    func formatterIdentity() {
        let formatter = PriceFormatter.fractionDigits(2)
        let copy = formatter
        #expect(copy.identity == formatter.identity)
        #expect(PriceFormatter.fractionDigits(2).identity != formatter.identity)
        #expect(PriceFormatter { String($0) }.identity != PriceFormatter { String($0) }.identity)
        #expect(PriceFormatter.automatic.identity == PriceFormatter.automatic.identity)
    }

    @Test("the end of the crosshair drops what is held, and asks for a new measurement")
    func crosshairEnds() {
        var hold = LegendHeightHold()
        hold.observe(CGSize(width: 300, height: 51), key: bands)
        let before = hold.token(for: bands)

        hold.crosshairEnded()
        #expect(hold.floor(for: bands) == nil)
        // What measures is made anew, so that it reports its size even when that is the size it had.
        #expect(hold.token(for: bands) != before)

        hold.observe(CGSize(width: 300, height: 17), key: bands)
        #expect(hold.floor(for: bands) == LegendHeightFloor(width: 300, height: 17))
        // The measurement is also made anew for another legend.
        #expect(hold.token(for: Key(indicatorIDs: ["sma"], style: .candles)) != hold.token(for: bands))
    }
}

/// The layout of the legend in a view: the pure placement above, applied to real subviews.
@MainActor
@Suite("Legend flow layout", .serialized)
struct LegendFlowLayoutTests {
    /// Where the probe's views ended up, by name.
    @MainActor
    final class Frames {
        var byName: [String: CGRect] = [:]
    }

    private struct Probe: View {
        let frames: Frames
        let widths: [CGFloat]
        var picker = false
        var floor: LegendHeightFloor?

        var body: some View {
            LegendFlowLayout(floor: floor) {
                ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                    Color.red.frame(width: width, height: 13).tracked("item\(index)", in: frames)
                }
                if picker {
                    Color.blue.frame(width: 44, height: 24).tracked("picker", in: frames).legendAccessory()
                }
            }
            .coordinateSpace(name: "legend")
        }
    }

    private func spin(_ seconds: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func host<Content: View>(_ view: Content, width: CGFloat) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        spin()
        return window
    }

    @Test("the legend is as tall as its lines: 17, 34 and 51 points for one, two and three of them, and fills the width")
    func height() {
        func size(width: CGFloat) -> CGSize {
            let controller = UIHostingController(rootView: Probe(frames: Frames(), widths: [60, 60, 60]))
            return controller.sizeThatFits(in: CGSize(width: width, height: 1_000))
        }
        #expect(size(width: 400) == CGSize(width: 400, height: 17))
        #expect(size(width: 140) == CGSize(width: 140, height: 34))
        #expect(size(width: 80) == CGSize(width: 80, height: 51))
    }

    @Test("a floor lifts the legend to the height it was measured at, at that width only")
    func floorLiftsTheHeight() {
        func size(width: CGFloat, floor: LegendHeightFloor?) -> CGSize {
            UIHostingController(rootView: Probe(frames: Frames(), widths: [60, 60, 60], floor: floor))
                .sizeThatFits(in: CGSize(width: width, height: 1_000))
        }
        let floor = LegendHeightFloor(width: 400, height: 51)
        #expect(size(width: 400, floor: floor) == CGSize(width: 400, height: 51))
        #expect(size(width: 400, floor: nil) == CGSize(width: 400, height: 17))
        // A legend that needs more than the floor takes it.
        #expect(size(width: 80, floor: floor) == CGSize(width: 80, height: 51))
        #expect(size(width: 80, floor: LegendHeightFloor(width: 80, height: 17)) == CGSize(width: 80, height: 51))
        // At another width the floor does not apply.
        #expect(size(width: 140, floor: floor) == CGSize(width: 140, height: 34))
    }

    @Test("the views are placed where the pure placement says, and the picker is at the end of the first line")
    func placement() {
        let frames = Frames()
        let window = host(Probe(frames: frames, widths: [60, 60, 60], picker: true), width: 200)
        defer { window.isHidden = true }

        #expect(frames.byName["item0"] == CGRect(x: 4, y: 5.5, width: 60, height: 13))
        #expect(frames.byName["item1"] == CGRect(x: 68, y: 5.5, width: 60, height: 13))
        #expect(frames.byName["item2"] == CGRect(x: 4, y: 26, width: 60, height: 13))
        #expect(frames.byName["picker"] == CGRect(x: 156, y: 0, width: 44, height: 24))
    }

    @Test("the legend of the main pane wraps: an overlay legend that does not fit takes more lines, the picker stays on the first")
    func mainLegendRowWraps() throws {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .line)
        model.configuration.stylePicker = StylePickerOptions()
        model.indicators = [SMA(), EMA(period: 50), BollingerBands()]
        func height(width: CGFloat) -> CGFloat {
            UIHostingController(rootView: MainLegendRow(model: model))
                .sizeThatFits(in: CGSize(width: width, height: 1_000)).height
        }

        let wide = height(width: 1_200)
        #expect(wide == SeriesStylePicker.size.height)
        let narrow = height(width: 150)
        #expect(narrow > wide)
        // Each further line is the height of a line of the legend font plus its insets.
        let extra = narrow - wide
        #expect(extra >= 2 * (LegendFlow.verticalInset * 2 + 10), "\(extra)")
        #expect(height(width: 110) >= narrow)
    }

    /// The legend of the main pane over a mark, which sits where the legend ends: its top is the height of the legend.
    private struct LegendOverMark: View {
        let model: TradingChartModel
        let frames: Frames

        var body: some View {
            VStack(spacing: 0) {
                MainLegendRow(model: model)
                Color.clear.frame(height: 1).tracked("below", in: frames)
            }
            .coordinateSpace(name: "legend")
        }
    }

    /// Prices around `price`, one bar a minute, the last one at `baseTime`.
    private func series(around price: Double, count: Int = 120) -> ChartSeries {
        ChartSeries(
            candles: (0..<count).map { index in
                let close = price + Double(index % 7)
                return Candle(
                    time: date(baseTime - Double(count - 1 - index) * 60),
                    open: close - 1,
                    high: close + 1,
                    low: close - 2,
                    close: close,
                    volume: 10
                )
            },
            interval: .minutes(1)
        )
    }

    @Test("a live tick that adds digits grows the legend and one that takes them away does not shrink it; another style or other indicators measure it again")
    func liveTicksHoldTheHeight() throws {
        let model = TradingChartModel(series: series(around: 95), style: .candles)
        model.indicators = [SMA(), EMA(period: 50), BollingerBands()]
        let frames = Frames()
        let window = host(LegendOverMark(model: model, frames: frames), width: 320)
        defer { window.isHidden = true }
        func height() throws -> CGFloat { try #require(frames.byName["below"]).minY }
        let last = try #require(model.series.lastTime)

        let low = try height()
        model.update(price: 5_000_000, at: last)
        spin()
        let high = try height()
        #expect(high >= low + 17, "low \(low), high \(high)")

        // Back to a price of two digits: the digits of every value are fewer again, the legend keeps its lines.
        for price in [95.0, 5_000_000, 96, 97, 95] {
            model.update(price: price, at: last)
            spin()
            #expect(try height() == high, "price \(price)")
        }

        // Measured again for another style: as tall as its text.
        model.style = .line
        spin()
        #expect(try height() == low)

        // And for other indicators.
        model.update(price: 5_000_000, at: last)
        spin()
        #expect(try height() == high)
        model.indicators = [SMA()]
        spin()
        #expect(try height() < low)
    }

    @Test("the end of the crosshair measures the legend again, and holds it from there, also when it is as tall as the held one was")
    func crosshairEndHoldsFromThere() throws {
        let model = TradingChartModel(series: series(around: 95), style: .candles)
        model.indicators = [SMA(), EMA(period: 50), BollingerBands()]
        let frames = Frames()
        let window = host(LegendOverMark(model: model, frames: frames), width: 320)
        defer { window.isHidden = true }
        func height() throws -> CGFloat { try #require(frames.byName["below"]).minY }
        let last = try #require(model.series.lastTime)

        let low = try height()
        model.update(price: 5_000_000, at: last)
        spin()
        let high = try height()
        #expect(high >= low + 17, "low \(low), high \(high)")

        // The crosshair on a bar with short numbers: the legend keeps the lines of the newest bar.
        model.crosshairTime = model.series.points[10].time
        spin()
        #expect(try height() == high)

        // At its end the legend is measured again, and it is as tall as it was: nothing changes size, and what is held from here
        // on is this height all the same.
        model.crosshairTime = nil
        spin()
        #expect(try height() == high)
        model.update(price: 95, at: last)
        spin()
        #expect(try height() == high)
    }

    /// The legend of the main pane over a mark, with the theme and the price formatter of a host that can replace them.
    @MainActor
    @Observable
    final class Appearance {
        var theme = TradingChartTheme.standard
        var formatter = PriceFormatter.automatic
    }

    private struct LegendWithAppearance: View {
        let model: TradingChartModel
        let frames: Frames
        let appearance: Appearance

        var body: some View {
            LegendOverMark(model: model, frames: frames)
                .tradingChartTheme(appearance.theme)
                .tradingChartPriceFormatter(appearance.formatter)
        }
    }

    @Test("turning the legend off takes the band away at once, even when it was held at more lines; turning it on measures it again")
    func legendOffRemovesTheBand() throws {
        let model = TradingChartModel(series: series(around: 95), style: .candles)
        model.configuration.stylePicker = StylePickerOptions()
        model.indicators = [SMA(), EMA(period: 50), BollingerBands()]
        let frames = Frames()
        let window = host(LegendOverMark(model: model, frames: frames), width: 320)
        defer { window.isHidden = true }
        func height() throws -> CGFloat { try #require(frames.byName["below"]).minY }
        let last = try #require(model.series.lastTime)

        let low = try height()
        model.update(price: 5_000_000, at: last)
        spin()
        let high = try height()
        #expect(high >= low + 17, "low \(low), high \(high)")

        // Nothing but the picker is left of the legend: its row, with no band of the lines that were.
        model.configuration.showsLegend = false
        spin()
        #expect(try height() == SeriesStylePicker.size.height)

        // The legend is another one when it comes back: as tall as its text now, not as tall as it was held before.
        model.update(price: 95, at: last)
        spin()
        model.configuration.showsLegend = true
        spin()
        #expect(try height() == low)

        // Without the picker either there is nothing at all.
        model.configuration.showsLegend = false
        model.configuration.stylePicker = nil
        spin()
        #expect(try height() == 0)
    }

    @Test("a formatter that shows fewer digits shrinks the legend without a crosshair; so does a smaller font")
    func appearanceMeasuresAgain() throws {
        let model = TradingChartModel(series: series(around: 95), style: .candles)
        model.indicators = [SMA(), EMA(period: 50), BollingerBands()]
        let appearance = Appearance()
        appearance.formatter = .fractionDigits(8)
        let frames = Frames()
        let window = host(LegendWithAppearance(model: model, frames: frames, appearance: appearance), width: 320)
        defer { window.isHidden = true }
        func height() throws -> CGFloat { try #require(frames.byName["below"]).minY }

        /// The height of a legend that starts out with this appearance.
        func fresh(_ configure: (Appearance) -> Void) throws -> CGFloat {
            let other = Appearance()
            configure(other)
            let otherFrames = Frames()
            let otherWindow = host(LegendWithAppearance(model: model, frames: otherFrames, appearance: other), width: 320)
            defer { otherWindow.isHidden = true }
            return try #require(otherFrames.byName["below"]).minY
        }

        let long = try height()
        #expect(long == (try fresh { $0.formatter = .fractionDigits(8) }))

        // The host learns the tick size of the instrument: a formatter that shows fewer digits replaces the first.
        appearance.formatter = .fractionDigits(0)
        spin()
        let short = try height()
        #expect(short < long, "long \(long), short \(short)")
        #expect(short == (try fresh { $0.formatter = .fractionDigits(0) }))

        // A smaller font.
        appearance.theme.legendFont = .system(size: 7).monospacedDigit()
        spin()
        let small = try height()
        #expect(small < short, "short \(short), small \(small)")
        #expect(small == (try fresh {
            $0.formatter = .fractionDigits(0)
            $0.theme.legendFont = .system(size: 7).monospacedDigit()
        }))
    }

    /// A legend of one big item with a picker, over a mark at the bottom of the legend.
    private struct BigFontLegend: View {
        let frames: Frames

        var body: some View {
            var theme = TradingChartTheme.standard
            theme.legendFont = .system(size: 40)
            return VStack(spacing: 0) {
                LegendFlowLayout {
                    LegendItems(items: [LegendItem(text: AttributedString("SMA"), startsGroup: true)])
                    Color.blue.frame(width: 44, height: 24).tracked("picker", in: frames).legendAccessory()
                }
                Color.clear.frame(height: 1).tracked("below", in: frames)
            }
            .tradingChartTheme(theme)
            .coordinateSpace(name: "legend")
        }
    }

    @Test("with a big legend font the picker is centred in the first line, which is as tall as the text")
    func pickerCentredWithABigFont() throws {
        let frames = Frames()
        let window = host(BigFontLegend(frames: frames), width: 320)
        defer { window.isHidden = true }

        let picker = try #require(frames.byName["picker"])
        let height = try #require(frames.byName["below"]).minY
        #expect(height > 40, "height \(height)")
        #expect(picker.minY > 0)
        #expect(picker.midY == height / 2, "picker \(picker), height \(height)")
    }

    @Test("the legend of an indicator pane wraps as well")
    func paneLegendWraps() {
        let model = TradingChartModel(series: makeSeries(count: 200), style: .line)
        let macd = MACD()
        model.indicators = [macd]
        let legend = PaneLegend(model: model, indicator: macd)
        func height(width: CGFloat) -> CGFloat {
            UIHostingController(rootView: legend).sizeThatFits(in: CGSize(width: width, height: 1_000)).height
        }

        let wide = height(width: 1_200)
        #expect(wide > 0)
        #expect(height(width: 80) > wide)
    }
}

private extension View {
    /// Records the frame of the view in the coordinate space `legend`.
    @MainActor
    func tracked(_ name: String, in frames: LegendFlowLayoutTests.Frames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("legend")) } action: { frames.byName[name] = $0 }
    }
}
