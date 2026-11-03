import Foundation

// Replays real, read-only exports through the shipping migration and statistics.
// Usage: verify-training-insights WATCH_HISTORY_JSON [PHONE_RECORDS_SNAPSHOT_JSON]
@main
enum VerifyTrainingInsights {
    struct Snapshot: Decodable { let history: [PhoneTrainingSession] }

    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "TrainingInsights", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Provide an existing Watch history export."])
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let original = try Data(contentsOf: sourceURL)
        let histories = try JSONDecoder().decode([WorkoutHistory].self, from: original)
        precondition(!histories.isEmpty, "The real history export was empty")
        let suite = "GymCountRealTrainingInsights." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(original, forKey: "phone.workoutHistory")
        let store = PhoneWorkoutStore(defaults: defaults, reminderID: suite,
                                     watchArchiveURL: root.appendingPathComponent("watch-history.json"),
                                     snapshotURL: root.appendingPathComponent("records-v3.json"))
        precondition(!store.requiresRecovery && store.history.count == histories.count)
        let records = store.history
        let now = max(Date(), histories.map(\.date).max()!)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let insights = RecordTrainingInsights(records: records, filter: RecordFilter(), now: now, calendar: calendar)
        precondition(insights.sessionCount == histories.count)
        precondition(insights.totalReps == histories.reduce(0) { $0 + $1.totalReps })
        precondition(insights.measuredDurationCount == histories.filter { $0.activeDuration != nil }.count)
        equal(insights.knownDuration, sumKnown(histories.compactMap(\.activeDuration)))
        equal(insights.totalKnownVolume, sumKnown(histories.compactMap(\.totalWeight)))
        precondition(insights.workingWeightRecords == 0 && insights.weightBreakdown.isEmpty && insights.mostUsedWeight == nil,
                     "A summary maximum was invented as a working set")
        precondition(records.allSatisfy { $0.sets.isEmpty })

        for exercise in ExerciseType.allCases {
            let expected = histories.filter { $0.exerciseType == exercise }
            let row = insights.exerciseBreakdown.first { $0.exercise == exercise }
            precondition(row?.recordCount ?? 0 == expected.count)
            precondition(row?.reps ?? 0 == expected.reduce(0) { $0 + $1.totalReps })
            let filter = RecordFilter(exercise: exercise)
            let scoped = RecordTrainingInsights(records: records, filter: filter, now: now, calendar: calendar)
            precondition(scoped.sessionCount == expected.count)
            precondition(scoped.totalReps == expected.reduce(0) { $0 + $1.totalReps })
            precondition(scoped.exerciseBreakdown.allSatisfy { $0.exercise == exercise })
            verifyMaxima(scoped, weights: expected.map(\.maxWeight))
        }
        verifyMaxima(insights, weights: histories.map(\.maxWeight))
        let expectedExercise = ExerciseType.allCases.sorted { a, b in
            let ac = histories.filter { $0.exerciseType == a }.count
            let bc = histories.filter { $0.exerciseType == b }.count
            return ac == bc ? ExerciseType.allCases.firstIndex(of: a)! < ExerciseType.allCases.firstIndex(of: b)! : ac > bc
        }.first!
        precondition(insights.mostFrequentExercise?.exercise == expectedExercise)

        var calendarChecks = 0
        for zone in ["Asia/Shanghai", "America/Los_Angeles"] {
            calendar.timeZone = TimeZone(identifier: zone)!
            let all = RecordTrainingInsights(records: records, filter: RecordFilter(), now: now, calendar: calendar)
            let grouped = Dictionary(grouping: histories, by: { calendar.startOfDay(for: $0.date) })
            precondition(all.trainingDays == grouped.count && all.days.count == grouped.count)
            precondition(all.daysByDate.count == grouped.count)
            precondition(all.days.reduce(0) { $0 + $1.recordCount } == histories.count)
            for day in all.days {
                let expected = grouped[day.date]!
                precondition(day.recordCount == expected.count)
                precondition(day.reps == expected.reduce(0) { $0 + $1.totalReps })
                equal(day.knownDuration, sumKnown(expected.compactMap(\.activeDuration)))
            }
            let days = Set(histories.filter { $0.totalReps > 0 }.map { calendar.startOfDay(for: $0.date) })
            var expectedLongest = 0
            for date in days {
                var cursor = date
                var count = 0
                while days.contains(cursor) {
                    count += 1
                    cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
                }
                expectedLongest = max(expectedLongest, count)
            }
            precondition(all.longestStreak == expectedLongest)
            let latest = days.max()!
            // Re-anchor to an actual training day and the following rest day;
            // this proves today's absence does not end yesterday's streak.
            for anchor in [latest.addingTimeInterval(3600), calendar.date(byAdding: .day, value: 1, to: latest)!.addingTimeInterval(3600)] {
                let current = RecordTrainingInsights(records: records, filter: RecordFilter(), now: anchor, calendar: calendar)
                var cursor = calendar.startOfDay(for: anchor)
                if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
                var expectedCurrent = 0
                while days.contains(cursor) {
                    expectedCurrent += 1
                    cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
                }
                // The anchor can be before the day's real training start.
                let visibleDays = Set(histories.filter { $0.date <= anchor && $0.totalReps > 0 }.map { calendar.startOfDay(for: $0.date) })
                if visibleDays == days { precondition(current.currentStreak == expectedCurrent) }
            }

            for period in [RecordFilter.Period.week, .month, .quarter, .custom, .all] {
                var filter = RecordFilter()
                filter.period = period
                filter.start = histories.map(\.date).sorted()[histories.count / 3]
                filter.end = histories.map(\.date).sorted()[histories.count * 2 / 3]
                let countDays = period == .week ? 6 : period == .month ? 29 : 89
                let lower = period == .custom ? calendar.startOfDay(for: filter.start)
                    : calendar.date(byAdding: .day, value: -countDays, to: calendar.startOfDay(for: now))!
                let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: filter.end))!
                let expected = histories.filter { history in
                    history.date <= now && (period == .all || (history.date >= lower && (period != .custom || history.date < upper)))
                }
                let scoped = RecordTrainingInsights(records: records, filter: filter, now: now, calendar: calendar)
                precondition(scoped.sessionCount == expected.count)
                precondition(scoped.totalReps == expected.reduce(0) { $0 + $1.totalReps })
                equal(scoped.knownDuration, sumKnown(expected.compactMap(\.activeDuration)))
                verifyMaxima(scoped, weights: expected.map(\.maxWeight))
                calendarChecks += 1
            }
        }
        let cutoff = histories.map(\.date).sorted()[histories.count / 2]
        let bounded = RecordTrainingInsights(records: records, filter: RecordFilter(), now: cutoff, calendar: calendar)
        precondition(bounded.sessionCount == histories.filter { $0.date <= cutoff }.count)
        precondition(bounded.filteredRecords.allSatisfy { $0.startTime <= cutoff })
        let empty = RecordTrainingInsights(records: [], filter: RecordFilter(), now: now, calendar: calendar)
        precondition(empty.sessionCount == 0 && empty.days.isEmpty && empty.totalReps == 0)
        precondition(empty.knownDuration == nil && empty.totalKnownVolume == nil && empty.mostUsedWeight == nil)
        precondition(empty.currentStreak == 0 && empty.longestStreak == 0)

        var detailedSourceRecords = 0
        var modeChecks = 0
        if CommandLine.arguments.count > 2 {
            let snapshotURL = URL(fileURLWithPath: CommandLine.arguments[2])
            let snapshotBytes = try Data(contentsOf: snapshotURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: snapshotBytes)
            detailedSourceRecords = snapshot.history.filter { !$0.isSummary && !$0.sets.isEmpty }.count
            let snapshotNow = max(now, snapshot.history.map(\.startTime).max() ?? now)
            for exercise in [nil] + ExerciseType.allCases.map(Optional.some) {
                let filter = RecordFilter(exercise: exercise)
                let actual = RecordTrainingInsights(records: snapshot.history, filter: filter, now: snapshotNow, calendar: calendar)
                let expected = snapshot.history.filter { !$0.isSummary }.flatMap(\.sets).filter {
                    !$0.imported && $0.reps > 0 && $0.weight.isFinite && $0.weight >= 0 && (exercise == nil || $0.exercise == exercise)
                }
                let grouped = Dictionary(grouping: expected, by: \.weight)
                precondition(actual.weightBreakdown.count == grouped.count)
                for row in actual.weightBreakdown {
                    let sets = grouped[row.weight]!
                    precondition(row.sets == sets.count && row.reps == sets.reduce(0) { $0 + $1.reps })
                    precondition(row.exercises == ExerciseType.allCases.filter { exercise in sets.contains { $0.exercise == exercise } })
                }
                let mode = grouped.keys.sorted { a, b in
                    let ac = grouped[a]!.count, bc = grouped[b]!.count
                    return ac == bc ? a < b : ac > bc
                }.first
                precondition(actual.mostUsedWeight?.weight == mode)
                let expectedRecords = snapshot.history.filter { record in
                    !record.isSummary && record.sets.contains { set in
                        !set.imported && set.reps > 0 && set.weight.isFinite && set.weight >= 0 && (exercise == nil || set.exercise == exercise)
                    }
                }.count
                precondition(actual.workingWeightRecords == expectedRecords)
                if !expected.isEmpty { modeChecks += 1 }
            }
            let afterSnapshot = try Data(contentsOf: snapshotURL)
            precondition(afterSnapshot == snapshotBytes, "The real phone snapshot was changed")
        }
        let afterSource = try Data(contentsOf: sourceURL)
        precondition(afterSource == original, "The real Watch export was changed")
        let report: [String: Any] = [
            "sourceRecords": histories.count,
            "sourceReps": insights.totalReps,
            "sourceDuration": insights.knownDuration.map { $0 as Any } ?? NSNull(),
            "distinctTrainingDays": insights.trainingDays,
            "mostFrequentExercise": insights.mostFrequentExercise?.exercise.rawValue as Any,
            "mostFrequentMaximumWeight": insights.mostFrequentMaximumWeight?.weight as Any,
            "maximumWeightDistributionMatchesRealSource": true,
            "summaryMaximumNeverInventedAsWorkingSet": true,
            "workingWeightRecords": insights.workingWeightRecords,
            "knownSetSourceRecords": detailedSourceRecords,
            "knownSetModeExercised": modeChecks > 0,
            "knownSetModeFilterChecks": modeChecks,
            "calendarRangeChecks": calendarChecks,
            "futureRecordsExcluded": true,
            "localDayAndStreakChecksPassed": true,
            "emptyDataPreservesUnknownMeasurements": true,
            "sourceFilesUnchanged": true
        ]
        let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }

    private static func sumKnown(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) }

    private static func equal(_ actual: Double?, _ expected: Double?) {
        guard let actual, let expected else { precondition(actual == nil && expected == nil); return }
        precondition(abs(actual - expected) < 0.000001)
    }

    private static func verifyMaxima(_ insights: RecordTrainingInsights, weights: [Double]) {
        let grouped = Dictionary(grouping: weights.filter { $0.isFinite && $0 >= 0 }, by: { $0 })
        precondition(insights.maximumWeightBreakdown.count == grouped.count)
        for row in insights.maximumWeightBreakdown { precondition(row.recordCount == grouped[row.weight]!.count) }
        let mode = grouped.keys.sorted { a, b in
            let ac = grouped[a]!.count, bc = grouped[b]!.count
            return ac == bc ? a < b : ac > bc
        }.first
        precondition(insights.mostFrequentMaximumWeight?.weight == mode)
    }
}
