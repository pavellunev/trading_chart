import Foundation

/// An immutable-by-default time series of prices: either a line of points or OHLC candles.
///
/// The series owns its ``interval``. Everything that depends on bucket size (the visible window,
/// axes, candle width, live ticks) must be derived from `series.interval` rather than from
/// whatever interval the user has selected in a picker. Items are always sorted by time with
/// unique timestamps.
///
/// ## Bad data
///
/// A series never holds a bar the chart cannot draw. Every way in (the initialisers, `upsert` and `apply`) drops a bar or a
/// point with a time or a price that is not finite (`nan`, `inf`; a `Decimal.nan` converts to `nan`), and repairs a candle whose
/// `high` is below, or whose `low` is above, one of its other prices: `high` becomes the highest and `low` the lowest of the
/// four. A volume that is not finite is dropped from the candle. The updating calls report a dropped input as
/// ``UpdateResult/ignored``.
public struct ChartSeries: Sendable, Equatable {
    /// The payload of a series.
    public enum Content: Sendable, Equatable {
        /// A line series.
        case points([PricePoint])
        /// An OHLC series.
        case candles([Candle])
    }

    /// The outcome of a mutation that inserts or updates a bar.
    public enum UpdateResult: Sendable, Equatable {
        /// The last bar was replaced or merged with the incoming data.
        case updatedLast
        /// A new bar was added at the end.
        case appended
        /// The input was older than the last bar, or not finite, and was dropped.
        case ignored
    }

    /// What a live tick turns an empty series into.
    ///
    /// Once a series has bars its kind stays: live updates and ``ChartSeries/prepend(_:)`` convert what they bring to it. Only an
    /// empty series can change kind, by taking a page of history or a candle.
    public enum Kind: Sendable, Equatable {
        /// OHLC bars: a candle series.
        case candles
        /// Single values: a line series.
        case points
    }

    /// Bucket length of the series.
    public let interval: ChartInterval
    /// The underlying points or candles.
    public private(set) var content: Content
    /// One point per bar, in sync with ``content``. For candle series each point carries the close price.
    public private(set) var points: [PricePoint]

    /// The candles, or `nil` for a point series.
    public var candles: [Candle]? {
        if case .candles(let candles) = content { return candles }
        return nil
    }

    /// `true` when the series carries OHLC data.
    public var hasCandles: Bool {
        if case .candles = content { return true }
        return false
    }

    /// `true` when the series has no bars.
    public var isEmpty: Bool { points.isEmpty }

    /// The number of bars.
    public var count: Int { points.count }

    /// Time of the first (oldest) bar.
    public var firstTime: Date? { points.first?.time }

    /// Time of the last (newest) bar.
    public var lastTime: Date? { points.last?.time }

    /// The last price: the close of the last candle or the value of the last point.
    public var lastValue: Double? { points.last?.value }

    /// Creates a line series.
    ///
    /// Points are sorted by time; when several points share a timestamp the last one in `points` wins. A point with a time or a
    /// value that is not finite is dropped.
    public init(points: [PricePoint], interval: ChartInterval) {
        let normalized = Self.normalized(points.compactMap(Self.sanitized), time: \.time)
        self.interval = interval
        self.content = .points(normalized)
        self.points = normalized
    }

    /// Creates an OHLC series.
    ///
    /// Candles are sorted by time; when several candles share a timestamp the last one in `candles` wins. A candle with a
    /// time or a price that is not finite is dropped, and one whose `high` and `low` do not enclose its other prices is
    /// repaired (see the documentation of ``ChartSeries``).
    public init(candles: [Candle], interval: ChartInterval) {
        let normalized = Self.normalized(candles.compactMap(Self.sanitized), time: \.time)
        self.interval = interval
        self.content = .candles(normalized)
        self.points = normalized.map(Self.point(from:))
    }

    /// An empty series with the given interval.
    ///
    /// The `kind` says what a first live tick (``apply(price:at:volume:maxCount:keepingFrom:)``, or an upserted
    /// ``PricePoint``, which is applied as a tick) turns it into. The default is a candle series: the tick opens a candle.
    /// Upserting a ``Candle`` into an empty series of points makes it a candle series, whichever `kind` it was created with.
    ///
    /// A series that has bars keeps its kind, whatever it is given afterwards: a page of history of the other kind that is
    /// prepended (``prepend(_:)``) is converted to it. A line chart that starts from the default empty series and is fed ticks
    /// is a series of candles, and takes a page of points as candles; ask for ``Kind/points`` to keep it a line.
    ///
    /// - Parameters:
    ///   - interval: The bucket length.
    ///   - kind: ``Kind/candles`` (the default) or ``Kind/points``.
    public static func empty(interval: ChartInterval, kind: Kind = .candles) -> ChartSeries {
        switch kind {
        case .candles: ChartSeries(candles: [], interval: interval)
        case .points: ChartSeries(points: [], interval: interval)
        }
    }

    // MARK: - Mutation

    /// Inserts or updates a candle.
    ///
    /// - Candle series: the same `time` as the last candle replaces it, a newer one is appended
    ///   (the head is trimmed to `maxCount`), an older one is ignored.
    /// - Point series: the candle is reduced to a point at its close. An empty point series
    ///   adopts the candle content instead: the first candle makes it a candle series.
    /// - A candle with a time or a price that is not finite is ignored; see the documentation of ``ChartSeries``.
    ///
    /// - Parameters:
    ///   - candle: The candle to insert or merge into the last bar.
    ///   - maxCount: Upper bound for the number of bars kept (at least 1); `nil` keeps everything.
    ///   - keepingFrom: Bars at or after this time are never trimmed, even when that keeps more than `maxCount` bars
    ///     (the head is cut only as far as bars older than this time allow). `nil` trims freely.
    @discardableResult
    public mutating func upsert(_ candle: Candle, maxCount: Int?, keepingFrom: Date? = nil) -> UpdateResult {
        guard let candle = Self.sanitized(candle) else { return .ignored }
        switch content {
        case .candles:
            return upsertCandle(candle, maxCount: maxCount, keepingFrom: keepingFrom)
        case .points:
            if points.isEmpty {
                content = .candles([])
                return upsertCandle(candle, maxCount: maxCount, keepingFrom: keepingFrom)
            }
            return upsertPoint(Self.point(from: candle), maxCount: maxCount, keepingFrom: keepingFrom)
        }
    }

    /// Inserts or updates a point.
    ///
    /// - Point series: the same `time` as the last point replaces it, a newer one is appended
    ///   (the head is trimmed to `maxCount`), an older one is ignored.
    /// - Candle series: the point is applied as a tick via ``apply(price:at:volume:maxCount:keepingFrom:)``: it is moved to the
    ///   start of its bucket, and merges into the candle of that bucket. On an empty candle series it opens a candle.
    /// - A point with a time or a value that is not finite is ignored; see the documentation of ``ChartSeries``.
    ///
    /// - Parameters:
    ///   - point: The point to insert or replace the last point with.
    ///   - maxCount: Upper bound for the number of bars kept (at least 1); `nil` keeps everything.
    ///   - keepingFrom: Bars at or after this time are never trimmed (as for a candle).
    @discardableResult
    public mutating func upsert(_ point: PricePoint, maxCount: Int?, keepingFrom: Date? = nil) -> UpdateResult {
        guard let point = Self.sanitized(point) else { return .ignored }
        switch content {
        case .points:
            return upsertPoint(point, maxCount: maxCount, keepingFrom: keepingFrom)
        case .candles:
            return apply(price: point.value, at: point.time, volume: nil, maxCount: maxCount, keepingFrom: keepingFrom)
        }
    }

    /// Applies a live price tick.
    ///
    /// The tick is assigned to the bucket `interval.bucketStart(for: time)`.
    /// - Candle series: a tick in the last bucket updates its high, low and close (and adds `volume`
    ///   to the candle volume); a tick in a newer bucket appends a candle with `open == high == low == close == price`;
    ///   a tick in an older bucket is ignored.
    /// - A tick with a time or a price that is not finite is ignored (a volume that is not finite is left out); see the documentation of ``ChartSeries``.
    /// - Point series: the tick becomes a point stamped at the bucket start and is upserted like any other point.
    ///   `volume` is ignored.
    ///
    /// - Parameters:
    ///   - price: The traded price.
    ///   - time: When it was traded; it selects the bucket.
    ///   - volume: The traded volume to add to the candle (candle series only).
    ///   - maxCount: Upper bound for the number of bars kept (at least 1); `nil` keeps everything.
    ///   - keepingFrom: Bars at or after this time are never trimmed (as for a candle).
    @discardableResult
    public mutating func apply(
        price: Double,
        at time: Date,
        volume: Double? = nil,
        maxCount: Int?,
        keepingFrom: Date? = nil
    ) -> UpdateResult {
        guard price.isFinite, time.timeIntervalSince1970.isFinite else { return .ignored }
        let volume = volume.flatMap { $0.isFinite ? $0 : nil }
        let bucket = interval.bucketStart(for: time)
        switch content {
        case .points:
            return upsertPoint(PricePoint(time: bucket, value: price), maxCount: maxCount, keepingFrom: keepingFrom)
        case .candles:
            let candle: Candle
            if let last = lastCandle, last.time == bucket {
                candle = Candle(
                    time: bucket,
                    open: last.open,
                    high: Swift.max(last.high, price),
                    low: Swift.min(last.low, price),
                    close: price,
                    volume: Self.merged(volume: last.volume, adding: volume)
                )
            } else {
                candle = Candle(time: bucket, open: price, high: price, low: price, close: price, volume: volume)
            }
            return upsertCandle(candle, maxCount: maxCount, keepingFrom: keepingFrom)
        }
    }

    /// Prepends older history.
    ///
    /// Only bars strictly older than ``firstTime`` are taken, so overlapping pages are safe.
    /// The call is a no-op when the intervals differ, and when the page has no bar older than the first one (an empty page
    /// included). An empty series simply adopts `older`, and with it its kind.
    ///
    /// A series that has bars keeps its kind, and a page of the other kind is converted to it, so it is not dropped. A page of
    /// candles prepended to points becomes points at the close of each candle. A page of points prepended to candles becomes
    /// flat candles (`open == high == low == close == value`, no volume): each point is moved to the start of its bucket, and the
    /// points of one bucket make one candle (the first value is its open, the last its close, the extremes its high and low).
    public mutating func prepend(_ older: ChartSeries) {
        guard older.interval == interval, !older.isEmpty else { return }
        if isEmpty {
            content = older.content
            points = older.points
            return
        }
        guard let firstTime else { return }
        switch content {
        case .points:
            // `points` of a page holds the close of each candle, so the same array serves either kind of page.
            let head = older.points.prefix { $0.time < firstTime }
            guard !head.isEmpty else { return }
            var current = points
            content = .points([])
            points = []
            current.insert(contentsOf: head, at: 0)
            points = current
            content = .points(current)
        case .candles(var current):
            let page = older.candles ?? Self.candles(from: older.points, interval: interval)
            let head = page.prefix { $0.time < firstTime }
            guard !head.isEmpty else { return }
            content = .candles([])
            current.insert(contentsOf: head, at: 0)
            points.insert(contentsOf: head.map(Self.point(from:)), at: 0)
            content = .candles(current)
        }
    }

    // MARK: - Queries

    /// The index of the bar closest in time to `time`, or `nil` for an empty series.
    ///
    /// Times outside the series resolve to the first or last bar; an exact tie between two bars
    /// resolves to the earlier one. Uses binary search.
    public func index(nearestTo time: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        let upper = points.partitionPoint { $0.time > time }
        if upper == 0 { return 0 }
        if upper == points.count { return points.count - 1 }
        let before = upper - 1
        let gapBefore = time.timeIntervalSince(points[before].time)
        let gapAfter = points[upper].time.timeIntervalSince(time)
        return gapAfter < gapBefore ? upper : before
    }

    /// The price at `time`, linearly interpolated between neighbouring bars (using close prices).
    ///
    /// Times before the first bar or after the last bar clamp to the edge value. Returns `nil` for an empty series.
    public func interpolatedValue(at time: Date) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        let upper = points.partitionPoint { $0.time > time }
        let left = points[upper - 1]
        let right = points[upper]
        let span = right.time.timeIntervalSince(left.time)
        guard span > 0 else { return left.value }
        let fraction = time.timeIntervalSince(left.time) / span
        return left.value + (right.value - left.value) * fraction
    }

    /// The lowest and highest price among bars whose time falls in `range` (bounds inclusive).
    ///
    /// For ``SeriesStyle/candles`` on a candle series the extremes are over `low` and `high`;
    /// otherwise over the point values. The bounds of the window are found by binary search.
    /// Returns `nil` when no bar falls in `range`.
    public func valueRange(in range: ClosedRange<Date>, style: SeriesStyle) -> ClosedRange<Double>? {
        let lower = points.partitionPoint { $0.time >= range.lowerBound }
        let upper = points.partitionPoint { $0.time > range.upperBound }
        guard lower < upper else { return nil }
        var low = Double.infinity
        var high = -Double.infinity
        if style == .candles, case .candles(let candles) = content {
            for candle in candles[lower..<upper] {
                low = Swift.min(low, candle.low)
                high = Swift.max(high, candle.high)
            }
        } else {
            for point in points[lower..<upper] {
                low = Swift.min(low, point.value)
                high = Swift.max(high, point.value)
            }
        }
        return low <= high ? low...high : nil
    }

    // MARK: - Internals

    private var lastCandle: Candle? {
        if case .candles(let candles) = content { return candles.last }
        return nil
    }

    /// The candle as the series keeps it: `high` and `low` enclosing all four prices, a volume that is finite; `nil` for a candle
    /// whose time or price is not finite.
    private static func sanitized(_ candle: Candle) -> Candle? {
        guard candle.time.timeIntervalSince1970.isFinite,
              candle.open.isFinite, candle.high.isFinite, candle.low.isFinite, candle.close.isFinite
        else { return nil }
        var result = candle
        result.high = Swift.max(candle.high, candle.open, candle.close, candle.low)
        result.low = Swift.min(candle.low, candle.open, candle.close, candle.high)
        if let volume = candle.volume, !volume.isFinite { result.volume = nil }
        return result
    }

    private static func sanitized(_ point: PricePoint) -> PricePoint? {
        point.time.timeIntervalSince1970.isFinite && point.value.isFinite ? point : nil
    }

    private static func point(from candle: Candle) -> PricePoint {
        PricePoint(time: candle.time, value: candle.close)
    }

    /// Candles for points that are sorted by time: one per bucket, stamped at its start, without volume.
    private static func candles(from points: [PricePoint], interval: ChartInterval) -> [Candle] {
        var result: [Candle] = []
        result.reserveCapacity(points.count)
        for point in points {
            let bucket = interval.bucketStart(for: point.time)
            let value = point.value
            if var last = result.last, last.time == bucket {
                last.high = Swift.max(last.high, value)
                last.low = Swift.min(last.low, value)
                last.close = value
                result[result.count - 1] = last
            } else {
                result.append(Candle(time: bucket, open: value, high: value, low: value, close: value, volume: nil))
            }
        }
        return result
    }

    private static func merged(volume: Double?, adding added: Double?) -> Double? {
        guard let added else { return volume }
        return (volume ?? 0) + added
    }

    private mutating func upsertCandle(_ candle: Candle, maxCount: Int?, keepingFrom: Date?) -> UpdateResult {
        guard case .candles(var candles) = content else { return .ignored }
        content = .candles([])
        let result = Self.upsertLast(&candles, candle, time: \.time, maxCount: maxCount, keepingFrom: keepingFrom)
        content = .candles(candles)
        if result != .ignored {
            _ = Self.upsertLast(
                &points,
                Self.point(from: candle),
                time: \.time,
                maxCount: maxCount,
                keepingFrom: keepingFrom
            )
        }
        return result
    }

    private mutating func upsertPoint(_ point: PricePoint, maxCount: Int?, keepingFrom: Date?) -> UpdateResult {
        guard case .points(var items) = content else { return .ignored }
        content = .points([])
        let result = Self.upsertLast(&items, point, time: \.time, maxCount: maxCount, keepingFrom: keepingFrom)
        points = items
        content = .points(items)
        return result
    }

    /// Replaces the last element when the times match, appends a newer one (trimming the head), drops an older one.
    private static func upsertLast<Element>(
        _ items: inout [Element],
        _ item: Element,
        time: KeyPath<Element, Date>,
        maxCount: Int?,
        keepingFrom: Date?
    ) -> UpdateResult {
        guard let last = items.last else {
            items.append(item)
            trim(&items, time: time, maxCount: maxCount, keepingFrom: keepingFrom)
            return .appended
        }
        let newTime = item[keyPath: time]
        let lastTime = last[keyPath: time]
        if newTime == lastTime {
            items[items.count - 1] = item
            return .updatedLast
        }
        if newTime > lastTime {
            items.append(item)
            trim(&items, time: time, maxCount: maxCount, keepingFrom: keepingFrom)
            return .appended
        }
        return .ignored
    }

    /// Cuts the head down to `maxCount` items, but never an item at or after `keepingFrom`.
    private static func trim<Element>(
        _ items: inout [Element],
        time: KeyPath<Element, Date>,
        maxCount: Int?,
        keepingFrom: Date?
    ) {
        guard let maxCount else { return }
        var excess = items.count - Swift.max(maxCount, 1)
        guard excess > 0 else { return }
        if let keepingFrom {
            excess = Swift.min(excess, items.partitionPoint { $0[keyPath: time] >= keepingFrom })
        }
        if excess > 0 {
            items.removeFirst(excess)
        }
    }

    /// Sorts by time and collapses duplicate timestamps, keeping the element that appears last in the input.
    private static func normalized<Element>(_ items: [Element], time: KeyPath<Element, Date>) -> [Element] {
        var isStrictlyIncreasing = true
        var previous: Date?
        for item in items {
            let current = item[keyPath: time]
            if let previous, current <= previous {
                isStrictlyIncreasing = false
                break
            }
            previous = current
        }
        if isStrictlyIncreasing { return items }

        let ordered = items.enumerated().sorted { lhs, rhs in
            let lhsTime = lhs.element[keyPath: time]
            let rhsTime = rhs.element[keyPath: time]
            return lhsTime == rhsTime ? lhs.offset < rhs.offset : lhsTime < rhsTime
        }
        var result: [Element] = []
        result.reserveCapacity(ordered.count)
        for (_, item) in ordered {
            if let last = result.last, last[keyPath: time] == item[keyPath: time] {
                result[result.count - 1] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}
