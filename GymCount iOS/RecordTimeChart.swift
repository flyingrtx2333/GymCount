import SwiftUI

func recordChartRangeTitle(_ range: DateInterval, granularity: RecordChartGranularity) -> String {
    if granularity == .day { return recordDate(range.start) }
    if granularity == .month { return range.start.formatted(.dateTime.year().month()) }
    let end = range.end.addingTimeInterval(-1)
    let calendar = Calendar.current
    let showYear = calendar.component(.year, from: range.start) != calendar.component(.year, from: end)
        || calendar.component(.year, from: range.start) != calendar.component(.year, from: Date())
    let format: Date.FormatStyle = showYear ? .dateTime.year().month().day() : .dateTime.month().day()
    return range.start.formatted(format) + " – " + end.formatted(format)
}

func recordChartAxisFormat(_ granularity: RecordChartGranularity, first: Date?, last: Date?) -> Date.FormatStyle {
    guard granularity == .month else { return recordChartDateFormat(first: first, last: last) }
    let year = first.map { Calendar.current.component(.year, from: $0) }
    let showYear = year != last.map { Calendar.current.component(.year, from: $0) } || year != Calendar.current.component(.year, from: Date())
    return showYear ? .dateTime.year(.twoDigits).month(.twoDigits) : .dateTime.month(.twoDigits)
}

// One metric model for the trends screen; workout storage remains unchanged.
enum RecordTrendMetric: String, CaseIterable {
    case active, reps, weight

    var title: String {
        switch self {
        case .reps: String(localized: "次数")
        case .weight: String(localized: "最高重量")
        case .active: RecordTimeMetric.active.title
        }
    }
    var compactTitle: String {
        title
    }
    var timeMetric: RecordTimeMetric? {
        switch self {
        case .active: .active
        default: nil
        }
    }
    func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        if timeMetric != nil {
            return Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        }
        return self == .reps ? String(localized: "\(Int(value)) 次") : String(localized: "\(value.formatted()) 公斤")
    }
    func compactFormatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        guard timeMetric != nil else { return formatted(value) }
        return Self.clock(value)
    }
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

struct RecordTrendPoint: Identifiable, Equatable {
    let id: Date
    let range: DateInterval
    let value: Double?
    let measuredRecords: Int
    let recordCount: Int

    static func summarize(_ records: [PhoneTrainingSession], metric: RecordTrendMetric,
                          granularity: RecordChartGranularity, filter: RecordFilter) -> [Self] {
        let buckets = RecordTrendBucket.summarize(records, granularity: granularity, reps: filter.reps, weight: filter.weight)
        let durations = metric.timeMetric.map { RecordDurationDay.summarize(records, metric: $0, granularity: granularity, exercise: filter.exercise) } ?? []
        let byDate = Dictionary(uniqueKeysWithValues: durations.map { ($0.id, $0) })
        let grouping = granularity.resolved(for: records.map(\.startTime))
        let knownWeights = Dictionary(grouping: records.filter(\.hasKnownWeight), by: { grouping.interval(containing: $0.startTime).start })
        return buckets.map { bucket in
            let duration = byDate[bucket.id]
            let value: Double? = switch metric {
            case .reps: Double(bucket.reps)
            case .weight: knownWeights[bucket.id]?.map(filter.weight).max()
            case .active: duration?.seconds
            }
            return Self(id: bucket.id, range: bucket.range, value: value,
                        measuredRecords: metric == .weight ? knownWeights[bucket.id]?.count ?? 0 : metric.timeMetric == nil ? bucket.sessions : duration?.measuredRecords ?? 0,
                        recordCount: bucket.sessions)
        }
    }
}
