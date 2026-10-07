import Testing
import TradingChart

@Suite("TradingChart module")
struct ModuleTests {
    @Test("umbrella module re-exports Core")
    func reExportsCore() {
        #expect(ChartInterval.hours(1).seconds == 3_600)
    }
}
