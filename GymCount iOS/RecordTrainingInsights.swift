import Foundation

// Derives statistics from saved records. Missing measurements remain missing;
// a Watch summary's maximum weight is never treated as a completed set.
struct RecordTrainingInsights {
    struct ExerciseBreakdown: Identifiable, Equatable {
        let exercise: ExerciseType
        let recordCount: Int
        let reps: Int
        var id: String { exercise.rawValue }
    }

    struct WeightBreakdown: Identifiable, Equatable {
        let weight: Double
        let sets: Int
        let reps: Int
        let exercises: [ExerciseType]
        var id: Double { weight }
    }

    struct MaximumWeightBreakdown: Identifiable, Equatable {
        let weight: Double
        let recordCount: Int
        var id: Double { weight }
    }

    struct TrainingDay: Identifiable, Equatable {
        let date: Date
        let recordCount: Int
        let reps: Int
        let knownDuration: Double?
        var id: Date { date }
    }

    let filteredRecords: [PhoneTrainingSession]
    let sessionCount: Int
    let totalReps: Int
    let knownDuration: Double?
    let measuredDurationCount: Int
    let trainingDays: Int
    let totalKnownVolume: Double?
    let exerciseBreakdown: [ExerciseBreakdown]
    let weightBreakdown: [WeightBreakdown]
    let maximumWeightBreakdown: [MaximumWeightBreakdown]
    let workingWeightRecords: Int
    let days: [TrainingDay]
    let daysByDate: [Date: TrainingDay]
    let longestStreak: Int
    let currentStreak: Int

    var mostFrequentExercise: ExerciseBreakdown? { exerciseBreakdown.first }
    var mostUsedWeight: WeightBreakdown? { weightBreakdown.first }
    var mostFrequentMaximumWeight: MaximumWeightBreakdown? { maximumWeightBreakdown.first }

    init(records: [PhoneTrainingSession], filter: RecordFilter,
         now: Date = Date(), calendar: Calendar = .current) {
        let lower: Date?
        let upper: Date?
        switch filter.period {
        case .all:
            lower = nil
            upper = nil
        case .custom:
            lower = calendar.startOfDay(for: filter.start)
            upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: filter.end))
        case .week, .month, .quarter:
            let distance = filter.period == .week ? 6 : filter.period == .month ? 29 : 89
            lower = calendar.date(byAdding: .day, value: -distance, to: calendar.startOfDay(for: now))
            upper = nil
        }
        let selected = records.filter { record in
            record.startTime <= now && record.startTime.timeIntervalSinceReferenceDate.isFinite
                && (lower.map { record.startTime >= $0 } ?? true)
                && (upper.map { record.startTime < $0 } ?? true)
                && (filter.exercise.map { record.exercises.contains($0) && (record.workoutReport == nil || record.reportMatchesCorrection) } ?? true)
        }
        filteredRecords = selected
        sessionCount = selected.count
        totalReps = selected.reduce(0) { $0 + filter.reps($1) }

        let durations = selected.compactMap { Self.validMeasurement($0.measuredActiveDuration(for: filter.exercise)) }
        knownDuration = durations.isEmpty ? nil : durations.reduce(0, +)
        measuredDurationCount = durations.count

        let volumes = selected.compactMap { record -> Double? in
            if let report = record.workoutReport {
                guard record.reportMatchesCorrection, report.hasKnownWeights else { return nil }
                return report.sets.filter { filter.exercise == nil || $0.exercise == filter.exercise }.reduce(0) { $0 + $1.totalWeight }
            }
            if record.isSummary { return Self.validMeasurement(record.volume) }
            let sets = record.sets.filter { filter.exercise == nil || $0.exercise == filter.exercise }
            guard !sets.isEmpty else { return nil }
            // Imported individual repetitions still preserve measured load and
            // volume, but their grouping is not evidence of a completed set.
            let values = sets.compactMap { set -> Double? in
                guard set.reps >= 0, let weight = Self.validMeasurement(set.weight) else { return nil }
                return Self.validMeasurement(weight * Double(set.reps))
            }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        totalKnownVolume = volumes.isEmpty ? nil : volumes.reduce(0, +)

        exerciseBreakdown = ExerciseType.allCases.compactMap { exercise -> ExerciseBreakdown? in
            guard filter.exercise == nil || filter.exercise == exercise else { return nil }
            let rows = selected.filter { $0.exercises.contains(exercise) && ($0.workoutReport == nil || $0.reportMatchesCorrection) }
            guard !rows.isEmpty else { return nil }
            let reps = rows.reduce(0) { result, record in
                result + record.repetitions(for: exercise)
            }
            return ExerciseBreakdown(exercise: exercise, recordCount: rows.count, reps: reps)
        }.sorted {
            if $0.recordCount != $1.recordCount { return $0.recordCount > $1.recordCount }
            return Self.exerciseOrder($0.exercise) < Self.exerciseOrder($1.exercise)
        }

        var workingRecords = 0
        var setsByWeight: [Double: [PhoneTrainingSet]] = [:]
        var maxima: [Double: Int] = [:]
        for record in selected {
            let knownSets = record.measuredSets.filter {
                !$0.imported && $0.reps > 0 && Self.validMeasurement($0.weight) != nil
                    && (filter.exercise == nil || $0.exercise == filter.exercise)
            }
            if !knownSets.isEmpty { workingRecords += 1 }
            for set in knownSets { setsByWeight[set.weight, default: []].append(set) }
            if record.hasKnownWeight, let weight = Self.validMeasurement(filter.weight(record)) {
                maxima[weight, default: 0] += 1
            }
        }
        workingWeightRecords = workingRecords
        weightBreakdown = setsByWeight.map { weight, sets in
            WeightBreakdown(weight: weight, sets: sets.count, reps: sets.reduce(0) { $0 + $1.reps },
                            exercises: ExerciseType.allCases.filter { exercise in sets.contains { $0.exercise == exercise } })
        }.sorted {
            if $0.sets != $1.sets { return $0.sets > $1.sets }
            return $0.weight < $1.weight
        }
        maximumWeightBreakdown = maxima.map { MaximumWeightBreakdown(weight: $0.key, recordCount: $0.value) }.sorted {
            if $0.recordCount != $1.recordCount { return $0.recordCount > $1.recordCount }
            return $0.weight < $1.weight
        }

        days = Dictionary(grouping: selected, by: { calendar.startOfDay(for: $0.startTime) }).map { date, records in
            let values = records.compactMap { Self.validMeasurement($0.measuredActiveDuration(for: filter.exercise)) }
            return TrainingDay(date: date, recordCount: records.count, reps: records.reduce(0) { $0 + filter.reps($1) },
                               knownDuration: values.isEmpty ? nil : values.reduce(0, +))
        }.sorted { $0.date < $1.date }
        daysByDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        trainingDays = days.count

        let streak = TrainingStreak(dates: selected.filter { filter.reps($0) > 0 }.map(\.startTime), now: now, calendar: calendar)
        longestStreak = streak.longest
        currentStreak = streak.current
    }

    private static func validMeasurement(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func exerciseOrder(_ exercise: ExerciseType) -> Int {
        ExerciseType.allCases.firstIndex(of: exercise) ?? 0
    }
}
