import Foundation

// Sum only detector-confirmed sensor-time action windows. Idle gaps are not
// included, and overlapping revised windows are never counted twice.
struct ActionTiming {
    struct Interval {
        let start: TimeInterval
        let end: TimeInterval
    }

    static func estimated(exercise: String, samples: [BenchMotionSample], expectedCount: Int,
                          events: [Double]? = nil) -> TimeInterval? {
        guard expectedCount > 0, samples.count >= 2,
              samples.enumerated().allSatisfy({ index, s in
                  [s.t, s.gravity.x, s.gravity.y, s.gravity.z, s.user_acceleration.x,
                   s.user_acceleration.y, s.user_acceleration.z, s.rotation_rate.x,
                   s.rotation_rate.y, s.rotation_rate.z].allSatisfy(\.isFinite)
                  && (index == 0 || (s.t > samples[index - 1].t && s.t - samples[index - 1].t <= 0.25))
              }) else { return nil }
        let intervals: [Interval]
        switch exercise {
        case "bench_press":
            let result = BenchPressAnalysis.analyze(samples)
            guard result.status == "estimated" else { return nil }
            intervals = result.cycles.map { Interval(start: $0.start, end: $0.end) }
        case "squat":
            let stream = SquatStream()
            intervals = samples.compactMap { stream.append($0) }.map { Interval(start: $0.start, end: $0.end) }
        default: return nil
        }
        guard intervals.count == expectedCount else { return nil }
        if let events {
            guard events.count == intervals.count,
                  zip(events, intervals).allSatisfy({ abs($0 - $1.end) <= 0.25 }) else { return nil }
        }
        return total(intervals)
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
