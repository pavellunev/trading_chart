import Foundation
import Testing
import TradingChartCore

@Suite("Candle, PricePoint, ChartColor")
struct DataTypesTests {
    @Test("Candle.isBullish is true when close >= open")
    func candleDirection() {
        #expect(candle(0, o: 10, h: 12, l: 9, c: 11).isBullish)
        #expect(candle(0, o: 10, h: 12, l: 9, c: 10).isBullish)
        #expect(!candle(0, o: 10, h: 12, l: 9, c: 9.5).isBullish)
    }

    @Test("Candle id is its time")
    func candleIdentity() {
        #expect(candle(120, o: 1, h: 1, l: 1, c: 1).id == date(120))
        #expect(point(60, 1).id == date(60))
    }

    @Test("Decimal initializers convert to Double")
    func decimalInit() {
        let converted = Candle(
            time: date(0),
            open: Decimal(string: "1.25")!,
            high: Decimal(string: "2.5")!,
            low: Decimal(string: "0.5")!,
            close: Decimal(string: "2")!,
            volume: Decimal(string: "100")!
        )
        #expect(converted == candle(0, o: 1.25, h: 2.5, l: 0.5, c: 2, v: 100))
        #expect(PricePoint(time: date(0), value: Decimal(string: "3.75")!) == point(0, 3.75))
        #expect(Candle(time: date(0), open: 1 as Decimal, high: 1, low: 1, close: 1).volume == nil)
    }

    @Test("Candle and PricePoint survive a Codable round trip")
    func codableRoundTrip() throws {
        let original = candle(1_700_000_040, o: 1.5, h: 2, l: 1, c: 1.75, v: 12)
        let decoded = try JSONDecoder().decode(Candle.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)

        let samplePoint = point(1_700_000_040, 42.5)
        #expect(try JSONDecoder().decode(PricePoint.self, from: JSONEncoder().encode(samplePoint)) == samplePoint)
    }

    @Test("ChartColor parses 6-digit hex with and without #")
    func hexSixDigits() throws {
        let orange = try #require(ChartColor(hex: "#FF8000"))
        #expect(orange.red == 1)
        #expect(approximatelyEqual(orange.green, 128.0 / 255.0))
        #expect(orange.blue == 0)
        #expect(orange.opacity == 1)
        #expect(ChartColor(hex: "ff8000") == orange)
    }

    @Test("ChartColor parses 3-digit and 8-digit hex")
    func hexShortAndAlpha() throws {
        let short = try #require(ChartColor(hex: "#f80"))
        #expect(short == ChartColor(hex: "#ff8800"))

        let translucent = try #require(ChartColor(hex: "#11223380"))
        #expect(approximatelyEqual(translucent.red, 17.0 / 255.0))
        #expect(approximatelyEqual(translucent.green, 34.0 / 255.0))
        #expect(approximatelyEqual(translucent.blue, 51.0 / 255.0))
        #expect(approximatelyEqual(translucent.opacity, 128.0 / 255.0))
    }

    @Test("ChartColor rejects malformed hex", arguments: ["", "#", "12345", "GGGGGG", "#1234567", "red"])
    func hexInvalid(_ text: String) {
        #expect(ChartColor(hex: text) == nil)
    }
}
