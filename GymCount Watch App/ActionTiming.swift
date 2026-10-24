import Foundation

// Sum only detector-confirmed sensor-time action windows. Idle gaps are not
// included, and overlapping revised windows are never counted twice.
struct ActionTiming {
    struct Interval {
        let start: TimeInterval
        let end: TimeInterval
    }

    static func total(_ intervals: [Interval]) -> TimeInterval? {
        guard intervals.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start }) else { return nil }
        let sorted = intervals.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return 0 }
        var start = first.start, end = first.end, total = 0.0
        for interval in sorted.dropFirst() {
            if interval.start <= end { end = max(end, interval.end) }
            else { total += end - start; start = interval.start; end = interval.end }
        }
        return total + end - start
    }
}
