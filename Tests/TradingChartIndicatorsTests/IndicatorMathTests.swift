import Testing
import TradingChartIndicators

@Suite("IndicatorMath against TA-Lib reference")
struct IndicatorMathReferenceTests {
    @Test("Reference series has at least 40 values")
    func referenceLength() {
        #expect(referenceCloses.count >= 40)
    }

    @Test("sma matches the reference", arguments: [(5, reference_sma5), (20, reference_sma20)])
    func sma(period: Int, expected: [Double?]) {
        expectAligned(IndicatorMath.sma(referenceCloses, period: period), expected)
    }

    @Test("ema matches the reference", arguments: [(5, reference_ema5), (12, reference_ema12)])
    func ema(period: Int, expected: [Double?]) {
        expectAligned(IndicatorMath.ema(referenceCloses, period: period), expected)
    }

    @Test("wma matches the reference", arguments: [(5, reference_wma5), (10, reference_wma10)])
    func wma(period: Int, expected: [Double?]) {
        expectAligned(IndicatorMath.wma(referenceCloses, period: period), expected)
    }

    @Test("populationStdDev matches the reference", arguments: [(5, reference_stdev5), (20, reference_stdev20)])
    func populationStdDev(period: Int, expected: [Double?]) {
        expectAligned(IndicatorMath.populationStdDev(referenceCloses, period: period), expected)
    }

    @Test("rsi matches the reference", arguments: [(5, reference_rsi5), (14, reference_rsi14)])
    func rsi(period: Int, expected: [Double?]) {
        expectAligned(IndicatorMath.rsi(referenceCloses, period: period), expected)
    }

    @Test("macd 12/26/9 matches the reference")
    func macdClassic() {
        let result = IndicatorMath.macd(referenceCloses, fast: 12, slow: 26, signal: 9)
        expectAligned(result.macd, reference_macd12_26_9)
        expectAligned(result.signal, reference_macdSignal12_26_9)
        expectAligned(result.histogram, reference_macdHistogram12_26_9)
    }

    @Test("macd 3/6/4 matches the reference")
    func macdShort() {
        let result = IndicatorMath.macd(referenceCloses, fast: 3, slow: 6, signal: 4)
        expectAligned(result.macd, reference_macd3_6_4)
        expectAligned(result.signal, reference_macdSignal3_6_4)
        expectAligned(result.histogram, reference_macdHistogram3_6_4)
    }
}

@Suite("IndicatorMath hand-computed cases")
struct IndicatorMathHandComputedTests {
    @Test("sma of 1...5 with period 3")
    func sma() {
        expectAligned(IndicatorMath.sma([1, 2, 3, 4, 5], period: 3), [nil, nil, 2, 3, 4])
    }

    @Test("ema is seeded with the SMA, then k = 2 / (period + 1)")
    func ema() {
        // Period 3: k = 0.5. Seed = (1 + 2 + 3) / 3 = 2; next = 0.5 * 4 + 0.5 * 2 = 3; next = 0.5 * 5 + 0.5 * 3 = 4.
        expectAligned(IndicatorMath.ema([1, 2, 3, 4, 5], period: 3), [nil, nil, 2, 3, 4])
        // Period 2: k = 2/3. Seed = 1.5; next = 2/3 * 6 + 1/3 * 1.5 = 4.5.
        expectAligned(IndicatorMath.ema([1, 2, 6], period: 2), [nil, 1.5, 4.5])
    }

    @Test("wma weighs the newest value most")
    func wma() {
        // (1*1 + 2*2 + 3*3) / 6 and (1*2 + 2*3 + 3*4) / 6.
        expectAligned(IndicatorMath.wma([1, 2, 3, 4], period: 3), [nil, nil, 14.0 / 6, 20.0 / 6])
    }

    @Test("populationStdDev divides by the period")
    func populationStdDev() {
        // The textbook set 2 4 4 4 5 5 7 9 has population sigma exactly 2 (sample sigma would be ~2.138).
        expectAligned(
            IndicatorMath.populationStdDev([2, 4, 4, 4, 5, 5, 7, 9], period: 8),
            [nil, nil, nil, nil, nil, nil, nil, 2]
        )
    }

    @Test("rsi uses plain means for the seed, then Wilder smoothing")
    func rsi() {
        // Period 2 on 10 11 10 12: changes +1 -1 +2.
        // Seed: avgGain = 0.5, avgLoss = 0.5 -> RSI 50.
        // Next: avgGain = (0.5 * 1 + 2) / 2 = 1.25, avgLoss = (0.5 * 1 + 0) / 2 = 0.25 -> RSI = 100 * 1.25 / 1.5.
        expectAligned(IndicatorMath.rsi([10, 11, 10, 12], period: 2), [nil, nil, 50, 100 * 1.25 / 1.5])
    }

    @Test("macd aligns its three series by index")
    func macdAlignment() {
        // fast 2, slow 3, signal 2 over 1...6: EMA2 (k = 2/3) seeds at index 1, EMA3 (k = 0.5) at index 2.
        let result = IndicatorMath.macd([1, 2, 3, 4, 5, 6], fast: 2, slow: 3, signal: 2)
        // EMA2: [-, 1.5, 2.5, 3.5, 4.5, 5.5]; EMA3: [-, -, 2, 3, 4, 5]; difference is 0.5 from index 2.
        expectAligned(result.macd, [nil, nil, 0.5, 0.5, 0.5, 0.5])
        // Signal EMA2 over the tail 0.5 0.5 ...: seeded at the second defined value, constant 0.5.
        expectAligned(result.signal, [nil, nil, nil, 0.5, 0.5, 0.5])
        expectAligned(result.histogram, [nil, nil, nil, 0, 0, 0])
    }
}

@Suite("IndicatorMath edge cases")
struct IndicatorMathEdgeCaseTests {
    private var averages: [(String, ([Double], Int) -> [Double?])] {
        [
            ("sma", { IndicatorMath.sma($0, period: $1) }),
            ("ema", { IndicatorMath.ema($0, period: $1) }),
            ("wma", { IndicatorMath.wma($0, period: $1) }),
            ("populationStdDev", { IndicatorMath.populationStdDev($0, period: $1) }),
            ("rsi", { IndicatorMath.rsi($0, period: $1) }),
        ]
    }

    @Test("Empty input gives an empty result")
    func empty() {
        for (name, function) in averages {
            #expect(function([], 3).isEmpty, "\(name)")
        }
        let macd = IndicatorMath.macd([], fast: 3, slow: 6, signal: 4)
        #expect(macd.macd.isEmpty && macd.signal.isEmpty && macd.histogram.isEmpty)
    }

    @Test("Input shorter than the period gives only nils of the same length")
    func shorterThanPeriod() {
        let values: [Double] = [1, 2, 3]
        for (name, function) in averages {
            let result = function(values, 5)
            #expect(result.count == 3, "\(name)")
            #expect(result.allSatisfy { $0 == nil }, "\(name)")
        }
        let macd = IndicatorMath.macd(values, fast: 2, slow: 5, signal: 2)
        #expect(macd.macd == [nil, nil, nil] && macd.signal == [nil, nil, nil] && macd.histogram == [nil, nil, nil])
    }

    @Test("The first defined index is period - 1 (period for rsi)")
    func firstDefinedIndex() {
        let values = (1...30).map(Double.init)
        #expect(IndicatorMath.sma(values, period: 7).firstIndex { $0 != nil } == 6)
        #expect(IndicatorMath.ema(values, period: 7).firstIndex { $0 != nil } == 6)
        #expect(IndicatorMath.wma(values, period: 7).firstIndex { $0 != nil } == 6)
        #expect(IndicatorMath.populationStdDev(values, period: 7).firstIndex { $0 != nil } == 6)
        #expect(IndicatorMath.rsi(values, period: 7).firstIndex { $0 != nil } == 7)
    }

    @Test("Input exactly one period long gives a single value; rsi needs one more")
    func exactlyOnePeriod() {
        let values: [Double] = [3, 1, 4, 1, 5]
        for function in [IndicatorMath.sma, IndicatorMath.ema, IndicatorMath.wma, IndicatorMath.populationStdDev] {
            let result = function(values, 5)
            #expect(result.compactMap { $0 }.count == 1)
            #expect(result[4] != nil)
        }
        #expect(IndicatorMath.rsi(values, period: 5).allSatisfy { $0 == nil })
        #expect(IndicatorMath.rsi(values + [9], period: 5).compactMap { $0 }.count == 1)
    }

    @Test("Period 1 reproduces the input (sigma is 0)")
    func periodOne() {
        let values = Array(referenceCloses.prefix(40))
        expectAligned(IndicatorMath.sma(values, period: 1), values.map { $0 })
        expectAligned(IndicatorMath.ema(values, period: 1), values.map { $0 })
        expectAligned(IndicatorMath.wma(values, period: 1), values.map { $0 })
        expectAligned(IndicatorMath.populationStdDev(values, period: 1), values.map { _ in 0 })
    }

    @Test("Constant series: averages equal the constant, sigma is 0")
    func constantSeries() {
        let values = [Double](repeating: 42.5, count: 50)
        let tail = { (series: [Double?]) in series.compactMap { $0 } }
        for series in [
            IndicatorMath.sma(values, period: 10),
            IndicatorMath.ema(values, period: 10),
            IndicatorMath.wma(values, period: 10),
        ] {
            #expect(tail(series).count == 41)
            #expect(tail(series).allSatisfy { abs($0 - 42.5) < 1e-12 })
        }
        #expect(tail(IndicatorMath.populationStdDev(values, period: 10)).allSatisfy { abs($0) < 1e-12 })
    }

    @Test("rsi convention: avgLoss == 0 gives 100, no movement gives 50, avgGain == 0 gives 0")
    func rsiConventions() {
        let rising = (1...30).map(Double.init)
        let falling = rising.reversed().map { $0 }
        let flat = [Double](repeating: 7, count: 30)
        #expect(IndicatorMath.rsi(rising, period: 14).compactMap { $0 }.allSatisfy { $0 == 100 })
        #expect(IndicatorMath.rsi(falling, period: 14).compactMap { $0 }.allSatisfy { $0 == 0 })
        let flatResult = IndicatorMath.rsi(flat, period: 14).compactMap { $0 }
        #expect(flatResult.count == 16)
        #expect(flatResult.allSatisfy { $0 == 50 })
    }

    @Test("rsi stays within 0...100")
    func rsiRange() {
        for value in IndicatorMath.rsi(referenceCloses, period: 14).compactMap({ $0 }) {
            #expect((0...100).contains(value))
        }
    }

    @Test("macd defined-ness: macd from slow - 1, signal and histogram from slow + signal - 2")
    func macdWarmUp() {
        let values = Array(referenceCloses.prefix(50))
        let result = IndicatorMath.macd(values, fast: 12, slow: 26, signal: 9)
        #expect(result.macd.firstIndex { $0 != nil } == 25)
        #expect(result.signal.firstIndex { $0 != nil } == 33)
        #expect(result.histogram.firstIndex { $0 != nil } == 33)
        #expect(result.macd.count == 50 && result.signal.count == 50 && result.histogram.count == 50)
    }

    @Test("macd with equal fast and slow is identically zero")
    func macdEqualPeriods() {
        let result = IndicatorMath.macd(Array(referenceCloses.prefix(40)), fast: 5, slow: 5, signal: 3)
        #expect(result.macd.compactMap { $0 }.allSatisfy { $0 == 0 })
        #expect(result.histogram.compactMap { $0 }.allSatisfy { $0 == 0 })
    }

    @Test("Running-sum sma stays accurate on a long series of large prices")
    func smaDrift() {
        // Deterministic pseudo-random walk around 100_000.
        var state: UInt64 = 12345
        var price = 100_000.0
        var values: [Double] = []
        for _ in 0..<5000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            price += Double(Int64(bitPattern: state >> 11) % 1000) / 100
            values.append(price)
        }
        let fast = IndicatorMath.sma(values, period: 20)
        for index in stride(from: 19, to: values.count, by: 97) {
            let direct = values[(index - 19)...index].reduce(0, +) / 20
            #expect(abs(fast[index]! - direct) < 1e-7)
        }
        #expect(abs(fast[4999]! - values[4980...4999].reduce(0, +) / 20) < 1e-7)
    }
}
