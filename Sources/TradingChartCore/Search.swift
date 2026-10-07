extension RandomAccessCollection where Index == Int {
    /// The first index whose element satisfies `isPastBoundary`.
    ///
    /// The collection must be partitioned: every element for which the predicate is `false`
    /// comes before every element for which it is `true`. Returns `endIndex` if none match.
    func partitionPoint(where isPastBoundary: (Element) -> Bool) -> Int {
        var low = startIndex
        var high = endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if isPastBoundary(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
