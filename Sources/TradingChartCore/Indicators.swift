import Foundation

/// Where an indicator is drawn.
public enum IndicatorPlacement: Sendable, Hashable {
    /// On top of the price chart, sharing its Y axis.
    case overlay
    /// In its own pane below the price chart.
    case pane
}

/// Which price of a bar an indicator is computed from.
public enum PriceSource: String, Sendable, Codable, CaseIterable {
    /// The open price.
    case open
    /// The high price.
    case high
    /// The low price.
    case low
    /// The close price.
    case close
    /// `(high + low) / 2`.
    case hl2
    /// `(high + low + close) / 3`.
    case hlc3
    /// `(open + high + low + close) / 4`.
    case ohlc4
}

/// A technical indicator: a pure function from bars to drawable output.
public protocol ChartIndicator: Sendable {
    /// Stable identity made of the type and its parameters, e.g. `"sma(20,close)"`. Used as the cache key.
    var id: String { get }
    /// A short human-readable name, e.g. `"SMA 20"`.
    var displayName: String { get }
    /// The shortest label, for a switch bar: `"MA"`, `"BOLL"`, `"VOL"`. Defaults to ``displayName``.
    var shortName: String { get }
    /// Whether the indicator is an overlay or has its own pane.
    var placement: IndicatorPlacement { get }
    /// Computes the indicator for the given bars.
    func calculate(_ input: IndicatorInput) -> IndicatorOutput
}

extension ChartIndicator {
    /// The same as ``displayName``.
    public var shortName: String { displayName }
}

/// The bars an indicator is computed from.
public struct IndicatorInput: Sendable {
    /// The bars, oldest first. A point series is expanded into candles with `open == high == low == close == value`
    /// and no volume.
    public let candles: [Candle]
    /// Bucket length of the source series.
    public let interval: ChartInterval

    /// Creates an input from a series.
    public init(series: ChartSeries) {
        self.interval = series.interval
        if let candles = series.candles {
            self.candles = candles
        } else {
            self.candles = series.points.map {
                Candle(time: $0.time, open: $0.value, high: $0.value, low: $0.value, close: $0.value)
            }
        }
    }

    /// One price per bar, picked according to `source`.
    public func values(_ source: PriceSource) -> [Double] {
        switch source {
        case .open: candles.map(\.open)
        case .high: candles.map(\.high)
        case .low: candles.map(\.low)
        case .close: candles.map(\.close)
        case .hl2: candles.map { ($0.high + $0.low) / 2 }
        case .hlc3: candles.map { ($0.high + $0.low + $0.close) / 3 }
        case .ohlc4: candles.map { ($0.open + $0.high + $0.low + $0.close) / 4 }
        }
    }
}

/// A defined indicator value at a bar. Bars inside the warm-up period are simply not included in outputs.
public struct IndicatorValue: Hashable, Sendable {
    /// Bar time.
    public var time: Date
    /// Indicator value at `time`.
    public var value: Double

    /// Creates a value.
    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// Stroke style of an indicator line.
public struct IndicatorLineStyle: Hashable, Sendable {
    /// Explicit color. `nil` takes the next color from the theme palette.
    public var color: ChartColor?
    /// Stroke width in points.
    public var width: Double
    /// Dash pattern in points; empty for a solid line.
    public var dash: [Double]

    /// Creates a line style.
    public init(color: ChartColor? = nil, width: Double = 1.5, dash: [Double] = []) {
        self.color = color
        self.width = width
        self.dash = dash
    }
}

/// A line of an indicator, e.g. the moving average of an SMA.
public struct IndicatorLine: Identifiable, Hashable, Sendable {
    /// Identifier unique within the output.
    public var id: String
    /// Name shown in legends.
    public var name: String
    /// Defined values, oldest first.
    public var values: [IndicatorValue]
    /// Stroke style.
    public var style: IndicatorLineStyle
    /// Offset into the theme palette for a line without an explicit color. The palette is dealt out per indicator,
    /// not per line: an indicator starts at the next free palette index and its lines pick `index + paletteSlot`,
    /// so lines that share a slot share a color. Defaults to `0`.
    public var paletteSlot: Int

    /// Creates a line.
    public init(
        id: String,
        name: String,
        values: [IndicatorValue],
        style: IndicatorLineStyle = IndicatorLineStyle(),
        paletteSlot: Int = 0
    ) {
        self.id = id
        self.name = name
        self.values = values
        self.style = style
        self.paletteSlot = paletteSlot
    }
}

/// A filled band between two series of values, e.g. Bollinger Bands.
public struct IndicatorBand: Identifiable, Hashable, Sendable {
    /// Identifier unique within the output.
    public var id: String
    /// Upper edge, oldest first.
    public var upper: [IndicatorValue]
    /// Lower edge, oldest first.
    public var lower: [IndicatorValue]
    /// Explicit fill color. `nil` takes the next color from the theme palette.
    public var fill: ChartColor?
    /// Opacity of the fill.
    public var fillOpacity: Double
    /// Offset into the theme palette for a band without an explicit fill; see ``IndicatorLine/paletteSlot``.
    /// Defaults to `0`.
    public var paletteSlot: Int

    /// Creates a band.
    public init(
        id: String,
        upper: [IndicatorValue],
        lower: [IndicatorValue],
        fill: ChartColor? = nil,
        fillOpacity: Double = 0.12,
        paletteSlot: Int = 0
    ) {
        self.id = id
        self.upper = upper
        self.lower = lower
        self.fill = fill
        self.fillOpacity = fillOpacity
        self.paletteSlot = paletteSlot
    }
}

/// The sign of a histogram bar, which the theme maps to a color.
public enum HistogramTone: Sendable, Hashable {
    /// Drawn with the bullish color.
    case positive
    /// Drawn with the bearish color.
    case negative
    /// Drawn with the neutral color.
    case neutral
}

/// A single bar of an indicator histogram.
public struct HistogramBar: Hashable, Sendable {
    /// Bar time.
    public var time: Date
    /// Bar value, measured from the histogram baseline.
    public var value: Double
    /// Tone used to pick the color from the theme.
    public var tone: HistogramTone
    /// Explicit color overriding `tone`.
    public var color: ChartColor?

    /// Creates a histogram bar.
    public init(time: Date, value: Double, tone: HistogramTone = .neutral, color: ChartColor? = nil) {
        self.time = time
        self.value = value
        self.tone = tone
        self.color = color
    }
}

/// A histogram of an indicator, e.g. volume or the MACD histogram.
public struct IndicatorHistogram: Identifiable, Hashable, Sendable {
    /// Identifier unique within the output.
    public var id: String
    /// Name shown in legends.
    public var name: String
    /// Bars, oldest first.
    public var bars: [HistogramBar]
    /// The value bars grow from.
    public var baseline: Double

    /// Creates a histogram.
    public init(id: String, name: String, bars: [HistogramBar], baseline: Double = 0) {
        self.id = id
        self.name = name
        self.bars = bars
        self.baseline = baseline
    }
}

/// A horizontal reference level of an indicator, e.g. RSI 70 / 30.
public struct IndicatorLevel: Identifiable, Hashable, Sendable {
    /// Identifier unique within the output.
    public var id: String
    /// Level value on the indicator scale.
    public var value: Double
    /// Explicit color. `nil` uses the theme grid color.
    public var color: ChartColor?
    /// Dash pattern in points.
    public var dash: [Double]

    /// Creates a level.
    public init(id: String, value: Double, color: ChartColor? = nil, dash: [Double] = [4, 3]) {
        self.id = id
        self.value = value
        self.color = color
        self.dash = dash
    }
}

/// Everything an indicator wants drawn.
public struct IndicatorOutput: Sendable, Equatable {
    /// Lines.
    public var lines: [IndicatorLine]
    /// Filled bands.
    public var bands: [IndicatorBand]
    /// Histograms.
    public var histograms: [IndicatorHistogram]
    /// Horizontal reference levels.
    public var levels: [IndicatorLevel]
    /// A fixed Y range for a pane (e.g. `0...100` for RSI). `nil` autoscales to the visible values.
    public var fixedRange: ClosedRange<Double>?

    /// Creates an output.
    public init(
        lines: [IndicatorLine] = [],
        bands: [IndicatorBand] = [],
        histograms: [IndicatorHistogram] = [],
        levels: [IndicatorLevel] = [],
        fixedRange: ClosedRange<Double>? = nil
    ) {
        self.lines = lines
        self.bands = bands
        self.histograms = histograms
        self.levels = levels
        self.fixedRange = fixedRange
    }

    /// An output with nothing to draw.
    public static let empty = IndicatorOutput()

    /// `true` when there is nothing plottable: no line values, band values or histogram bars.
    /// Reference levels alone do not count.
    public var isEmpty: Bool {
        lines.allSatisfy { $0.values.isEmpty }
            && bands.allSatisfy { $0.upper.isEmpty && $0.lower.isEmpty }
            && histograms.allSatisfy { $0.bars.isEmpty }
    }

    /// The lowest and highest plotted value whose time falls in `range` (bounds inclusive), for autoscaling.
    ///
    /// Covers line values, both band edges and histogram bars (a histogram with bars in the window also contributes
    /// its baseline so the zero line stays visible). Levels and `fixedRange` are not included.
    /// Values that are not finite (`nan`, `inf`) are left out. Returns `nil` when nothing is plotted in `range`.
    public func valueRange(in range: ClosedRange<Date>) -> ClosedRange<Double>? {
        var low = Double.infinity
        var high = -Double.infinity

        func include(_ number: Double) {
            guard number.isFinite else { return }
            low = Swift.min(low, number)
            high = Swift.max(high, number)
        }

        func include(_ values: [IndicatorValue]) {
            let lower = values.partitionPoint { $0.time >= range.lowerBound }
            let upper = values.partitionPoint { $0.time > range.upperBound }
            guard lower < upper else { return }
            for value in values[lower..<upper] {
                include(value.value)
            }
        }

        for line in lines { include(line.values) }
        for band in bands {
            include(band.upper)
            include(band.lower)
        }
        for histogram in histograms {
            let lower = histogram.bars.partitionPoint { $0.time >= range.lowerBound }
            let upper = histogram.bars.partitionPoint { $0.time > range.upperBound }
            guard lower < upper else { continue }
            include(histogram.baseline)
            for bar in histogram.bars[lower..<upper] {
                include(bar.value)
            }
        }
        return low <= high ? low...high : nil
    }

    /// The values of the lines and histograms at exactly `time`, for crosshair legends.
    ///
    /// Series with no defined value at `time` (e.g. inside the warm-up period) are skipped.
    /// Band edges are not reported. Lines come first, then histograms, in output order.
    public func values(at time: Date) -> [(name: String, value: Double, color: ChartColor?)] {
        var result: [(name: String, value: Double, color: ChartColor?)] = []
        for line in lines {
            let index = line.values.partitionPoint { $0.time >= time }
            if index < line.values.count, line.values[index].time == time {
                result.append((line.name, line.values[index].value, line.style.color))
            }
        }
        for histogram in histograms {
            let index = histogram.bars.partitionPoint { $0.time >= time }
            if index < histogram.bars.count, histogram.bars[index].time == time {
                let bar = histogram.bars[index]
                result.append((histogram.name, bar.value, bar.color))
            }
        }
        return result
    }
}
