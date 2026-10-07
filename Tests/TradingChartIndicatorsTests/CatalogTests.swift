import Foundation
import Testing
import TradingChartCore
import TradingChartIndicators

@Suite("Built-in indicator catalog")
struct CatalogTests {
    private let defaults: [any ChartIndicator] = [
        SMA(), EMA(), WMA(), BollingerBands(), Volume(), RSI(), MACD(),
    ]

    @Test("Default ids are unique and placements as documented")
    func idsAndPlacement() {
        #expect(Set(defaults.map(\.id)).count == defaults.count)
        #expect(defaults.map(\.placement) == [.overlay, .overlay, .overlay, .overlay, .pane, .pane, .pane])
    }

    @Test("Short names are the labels of a switch bar and do not depend on parameters")
    func shortNames() {
        #expect(defaults.map(\.shortName) == ["MA", "EMA", "WMA", "BOLL", "VOL", "RSI", "MACD"])
        #expect(SMA(period: 50, source: .hl2).shortName == "MA")
        #expect(BollingerBands(period: 10, multiplier: 1.5).shortName == "BOLL")
    }

    @Test("Ids differ when calculation parameters differ and ignore style")
    func idStability() {
        #expect(SMA(period: 20).id != SMA(period: 21).id)
        #expect(SMA(period: 20).id != EMA(period: 20).id)
        #expect(SMA(period: 20, source: .close).id != SMA(period: 20, source: .open).id)
        let styled = SMA(style: IndicatorLineStyle(color: ChartColor(red: 1, green: 0, blue: 0)))
        #expect(styled.id == SMA().id)
    }

    @Test("Only the MACD signal line leaves palette slot 0")
    func paletteSlots() {
        let input = IndicatorInput(series: referenceSeries())
        for indicator in defaults {
            let output = indicator.calculate(input)
            let slots = output.lines.map(\.paletteSlot) + output.bands.map(\.paletteSlot)
            if indicator is MACD {
                #expect(slots == [0, 1], "\(indicator.id)")
            } else {
                #expect(slots.allSatisfy { $0 == 0 }, "\(indicator.id)")
            }
        }
    }

    @Test("Every indicator tolerates an empty series and fills output times only from bars")
    func emptyInput() {
        let input = IndicatorInput(series: .empty(interval: .minutes(1)))
        for indicator in defaults {
            #expect(indicator.calculate(input).isEmpty, "\(indicator.id)")
        }
    }

    @Test("Every indicator output times are a subset of the input times")
    func timesComeFromInput() {
        let input = IndicatorInput(series: referenceSeries())
        let known = Set(input.candles.map(\.time))
        for indicator in defaults {
            let output = indicator.calculate(input)
            var times: [Date] = output.lines.flatMap { $0.values.map(\.time) }
            times += output.bands.flatMap { $0.upper.map(\.time) + $0.lower.map(\.time) }
            times += output.histograms.flatMap { $0.bars.map(\.time) }
            #expect(times.allSatisfy(known.contains), "\(indicator.id)")
        }
    }
}
