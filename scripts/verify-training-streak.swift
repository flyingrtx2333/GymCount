import Foundation

// Uses unchanged saved training dates, with controlled clocks and calendars.
@main
enum VerifyTrainingStreak {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Provide the real Watch history export") }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let bytes = try Data(contentsOf: input)
        let records = try JSONDecoder().decode([WorkoutHistory].self, from: bytes)
        let dates = records.filter { $0.totalReps > 0 }.map(\.date)
        precondition(!dates.isEmpty)
        var checks = 0
        for zone in ["Asia/Shanghai", "America/Los_Angeles", "Europe/London"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            for anchor in dates + dates.compactMap({ calendar.date(byAdding: .day, value: 1, to: $0) }) {
                let today = calendar.startOfDay(for: anchor)
                let known = Set(dates.filter { $0 <= anchor }.map { calendar.startOfDay(for: $0) })
                var expected = 0
                var cursor = known.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
                while known.contains(cursor) { expected += 1; cursor = calendar.date(byAdding: .day, value: -1, to: cursor)! }
                let result = TrainingStreak(dates: dates, now: anchor, calendar: calendar)
                precondition(result.current == expected && result.trainedToday == known.contains(today))
                let duplicated = TrainingStreak(dates: dates + dates, now: anchor, calendar: calendar)
                precondition(duplicated.current == result.current && duplicated.longest == result.longest)
                let plan = TrainingReminderPlan(dates: dates, now: anchor, calendar: calendar, prefix: "verify")
                precondition(plan.entries.count <= 60 && Set(plan.entries.map(\.id)).count == plan.entries.count)
                precondition(plan.entries.allSatisfy { $0.date > anchor && !known.contains(calendar.startOfDay(for: $0.date)) })
                for item in plan.entries {
                    let parts = calendar.dateComponents([.hour, .minute], from: item.date)
                    precondition(parts.hour == 20 && parts.minute == 0)
                    let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: item.date)).day!
                    let risk = offset == 0 ? expected : offset == 1 && known.contains(today) ? expected : 0
                    precondition(item.streakAtRisk == risk)
                    precondition(!item.body.isEmpty)
                }
                checks += 1
            }
            // No invented workouts: these clocks check calendar rollovers using
            // the same original export, including DST and a year boundary.
            for parts in [DateComponents(year: 2026, month: 3, day: 7, hour: 19),
                          DateComponents(year: 2026, month: 10, day: 31, hour: 19),
                          DateComponents(year: 2026, month: 12, day: 31, hour: 19)] {
                let clock = calendar.date(from: parts)!
                let plan = TrainingReminderPlan(dates: dates, now: clock, calendar: calendar, prefix: "verify")
                for item in plan.entries {
                    precondition(calendar.component(.hour, from: item.date) == 20)
                    precondition(calendar.component(.minute, from: item.date) == 0)
                }
                checks += 1
            }
        }
        let empty = TrainingStreak(dates: [])
        precondition(empty.current == 0 && empty.longest == 0 && !empty.trainedToday)
        let suite = "TrainingStreakRealHistory." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.set(bytes, forKey: "phone.workoutHistory")
        let snapshot = folder.appendingPathComponent("records-v3.json")
        let store = PhoneWorkoutStore(defaults: defaults, reminderID: suite,
            watchArchiveURL: folder.appendingPathComponent("history.json"), snapshotURL: snapshot)
        precondition(!store.requiresRecovery && store.history.count == records.count)
        var callbacks = 0
        store.onTrainingDatesChanged = { dates in
            let saved = try! JSONDecoder().decode(RecordSnapshot.self, from: Data(contentsOf: snapshot))
            precondition(dates == saved.history.filter { $0.totalReps > 0 }.map(\.startTime))
            callbacks += 1
        }
        let target = store.history.first { $0.totalReps > 0 }!
        precondition(store.deleteRecords(ids: [target.id]) && callbacks == 1)
        let duplicate = store.history.map { row in
            WorkoutSync.Record(id: row.id, date: row.startTime, exercise: row.exercise.rawValue,
                totalReps: row.totalReps, maxWeight: row.maxWeight, duration: row.duration,
                activeDuration: row.activeDuration, totalWeight: row.volume)
        }
        try store.acceptWatchHistory(duplicate)
        precondition(callbacks == 1, "Duplicate sync must not reschedule notifications")
        // A failed write must never cancel a reminder as if the edit succeeded.
        try FileManager.default.removeItem(at: snapshot)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: false)
        precondition(!store.deleteRecords(ids: [store.history.first { $0.totalReps > 0 }!.id]))
        precondition(callbacks == 1)
        let after = try Data(contentsOf: input)
        precondition(after == bytes)
        print("{\"realRecords\":\(records.count),\"positiveRepRecords\":\(dates.count),\"calendarAndPlanChecks\":\(checks),\"timeZones\":3,\"postPersistenceCallbackChecks\":3,\"sourceUnchanged\":true}")
    }
}
