import Foundation

/// Measured training data. Missing cycle boundaries and HealthKit values stay nil.
struct WorkoutReport: Codable, Equatable {
    struct TimeRange: Codable, Equatable {
        var startedAt: Date
        var endedAt: Date
        var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    }
    struct Repetition: Codable, Equatable, Identifiable {
        var id: UUID
        var completedAt: Date
        var startedAt: Date?
        var weight: Double
    }
    struct SetRecord: Codable, Equatable, Identifiable {
        var id: UUID
        var exercise: ExerciseType
        var repetitions: [Repetition]
        var totalReps: Int { repetitions.count }
        var maxWeight: Double { repetitions.map(\.weight).max() ?? 0 }
        var totalWeight: Double { repetitions.reduce(0) { $0 + $1.weight } }
        var startedAt: Date { repetitions.first.map { $0.startedAt ?? $0.completedAt } ?? .distantPast }
        var endedAt: Date { repetitions.last?.completedAt ?? startedAt }
        var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
        var activeDuration: TimeInterval? {
            guard !repetitions.isEmpty, repetitions.allSatisfy({ $0.startedAt != nil }) else { return nil }
            return WorkoutReport.unionDuration(repetitions.map { TimeRange(startedAt: $0.startedAt!, endedAt: $0.completedAt) })
        }
    }
    struct HeartRatePoint: Codable, Equatable {
        var date: Date
        var bpm: Double
    }

    var version = 1
    var startedAt: Date
    var endedAt: Date
    var sets: [SetRecord]
    var pauses: [TimeRange] = []
    var activeEnergyKcal: Double?
    var heartRates: [HeartRatePoint] = []
    var healthWorkoutID: UUID?
    var weightsRecorded: Bool?
    var hasKnownWeights: Bool { weightsRecorded != false }
    var metricsComplete = false
    var measuredAverageHeartRate: Double?
    var measuredMaximumHeartRate: Double?
    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    var totalReps: Int { sets.reduce(0) { $0 + $1.totalReps } }
    var maxWeight: Double { sets.map(\.maxWeight).max() ?? 0 }
    var totalWeight: Double { sets.reduce(0) { $0 + $1.totalWeight } }
    var pauseDuration: TimeInterval { Self.unionDuration(pauses) }
    var activeDuration: TimeInterval? {
        guard !sets.isEmpty, sets.allSatisfy({ $0.activeDuration != nil }) else { return nil }
        return Self.unionDuration(sets.flatMap(\.repetitions).map { TimeRange(startedAt: $0.startedAt!, endedAt: $0.completedAt) })
    }
    /// Only measured gaps between sets, excluding explicitly paused periods.
    var intervalDuration: TimeInterval? {
        guard sets.count > 1 else { return sets.isEmpty ? nil : 0 }
        guard sets.dropFirst().allSatisfy({ $0.repetitions.first?.startedAt != nil }) else { return nil }
        return zip(sets, sets.dropFirst()).reduce(0) { value, pair in
            let start = pair.0.endedAt, end = pair.1.startedAt
            let overlap = pauses.compactMap { pause -> TimeRange? in
                let lower = max(start, pause.startedAt), upper = min(end, pause.endedAt)
                return lower < upper ? TimeRange(startedAt: lower, endedAt: upper) : nil
            }
            return value + max(0, end.timeIntervalSince(start) - Self.unionDuration(overlap))
        }
    }
    var averageHeartRate: Double? {
        measuredAverageHeartRate ?? (heartRates.isEmpty ? nil : heartRates.reduce(0) { $0 + $1.bpm } / Double(heartRates.count))
    }
    var maximumHeartRate: Double? { measuredMaximumHeartRate ?? heartRates.map(\.bpm).max() }

    static func unionDuration(_ ranges: [TimeRange]) -> TimeInterval {
        let ranges = ranges.sorted { $0.startedAt < $1.startedAt }
        guard var current = ranges.first else { return 0 }
        var total: TimeInterval = 0
        for range in ranges.dropFirst() {
            if range.startedAt <= current.endedAt { current.endedAt = max(current.endedAt, range.endedAt) }
            else { total += current.duration; current = range }
        }
        return total + current.duration
    }

    /// Split only across a long gap between complete cycles; slow repetitions
    /// raise the threshold. Manual reps without a start cannot infer a new set.
    static func group(_ reps: [RepRecord], exercise: ExerciseType) -> [SetRecord] {
        let ordered = reps.sorted { $0.timestamp < $1.timestamp }
        let durations = ordered.compactMap { rep in rep.startedAt.map { rep.timestamp.timeIntervalSince($0) } }.filter { $0 > 0 }.sorted()
        let median = durations.isEmpty ? 0 : durations[durations.count / 2]
        let gapThreshold = max(15, median * 3)
        var groups: [SetRecord] = []
        for rep in ordered {
            let newGroup = groups.last.map { last in
                rep.startedAt.map { $0.timeIntervalSince(last.endedAt) >= gapThreshold } ?? false
            } ?? true
            if newGroup { groups.append(SetRecord(id: rep.id, exercise: exercise, repetitions: [])) }
            groups[groups.count - 1].repetitions.append(Repetition(id: rep.id, completedAt: rep.timestamp, startedAt: rep.startedAt, weight: rep.weight))
        }
        return groups
    }

    func validate() throws {
        func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
        guard version == 1, valid(startedAt), valid(endedAt), endedAt >= startedAt,
              duration.isFinite, sets.count <= 1_000, totalReps <= 10_000,
              Set(sets.map(\.id)).count == sets.count,
              Set(sets.flatMap(\.repetitions).map(\.id)).count == totalReps,
              activeEnergyKcal.map({ $0.isFinite && $0 >= 0 }) ?? true,
              [measuredAverageHeartRate, measuredMaximumHeartRate].allSatisfy({ $0.map { $0.isFinite && (1...300).contains($0) } ?? true }),
              heartRates.count <= 10_000, pauses.count <= 1_000 else { throw CocoaError(.fileReadCorruptFile) }
        var previousEnd = startedAt
        for set in sets {
            guard !set.repetitions.isEmpty, set.startedAt >= previousEnd, set.endedAt <= endedAt else { throw CocoaError(.fileReadCorruptFile) }
            var completion = set.startedAt
            for rep in set.repetitions {
                guard valid(rep.completedAt), rep.completedAt >= completion, rep.completedAt <= endedAt,
                      rep.weight.isFinite, (0...500).contains(rep.weight),
                      rep.startedAt.map({ valid($0) && $0 >= startedAt && $0 <= rep.completedAt }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
                completion = rep.completedAt
            }
            previousEnd = set.endedAt
        }
        guard pauses.allSatisfy({ valid($0.startedAt) && valid($0.endedAt) && $0.startedAt >= startedAt && $0.endedAt <= endedAt && $0.endedAt >= $0.startedAt }),
              heartRates.allSatisfy({ valid($0.date) && $0.date >= startedAt && $0.date <= endedAt && $0.bpm.isFinite && (1...300).contains($0.bpm) }) else { throw CocoaError(.fileReadCorruptFile) }
    }
}

struct WholeWorkoutDraft: Codable, Equatable {
    var id: UUID
    var startedAt: Date
    var completedSets: [WorkoutReport.SetRecord] = []
    var pauses: [WorkoutReport.TimeRange] = []
    var pausedAt: Date?
    var pendingReport: WorkoutReport?
    var metricsInterrupted = false
    var healthSessionStarted: Bool?
    var segmentStartedAt: Date?
    var segmentID: UUID?

    func validate(checkpoint: Date) throws {
        var report = WorkoutReport(startedAt: startedAt, endedAt: checkpoint, sets: completedSets, pauses: pauses)
        if let pausedAt {
            guard pausedAt >= startedAt && pausedAt <= checkpoint else { throw CocoaError(.fileReadCorruptFile) }
            report.pauses.append(.init(startedAt: pausedAt, endedAt: checkpoint))
        }
        try report.validate()
        if let pendingReport {
            try pendingReport.validate()
            guard pendingReport.startedAt == startedAt, pendingReport.endedAt <= checkpoint,
                  pendingReport.sets == completedSets else { throw CocoaError(.fileReadCorruptFile) }
        }
        if let segmentStartedAt {
            guard segmentStartedAt.timeIntervalSinceReferenceDate.isFinite, segmentStartedAt >= startedAt, segmentStartedAt <= checkpoint else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}
