import Foundation

// Run the shipping persistence code against an actual Watch workout_history
// export. The private source file is read-only; all writes use isolated storage.
@main
enum VerifyWorkoutHistoryImport {
    @MainActor
    static func main() throws {
        let source = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let histories = try JSONDecoder().decode([WorkoutHistory].self, from: source)
        guard histories.count > 1 else { throw WorkoutSync.Failure.invalidPayload }
        let suite = "GymCountRealHistoryVerification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let url = root.appendingPathComponent("watch-history.json")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        // A source-faithful existing summary must survive the import unchanged.
        let existing = histories.last!
        var existingPhone = PhoneTrainingSession(id: existing.id, startTime: existing.date,
            exercise: existing.exerciseType, weight: existing.maxWeight)
        existingPhone.endTime = existing.date.addingTimeInterval(existing.duration)
        existingPhone.legacySummary = existing
        struct State: Encodable {
            let session: PhoneTrainingSession? = nil
            let history: [PhoneTrainingSession]
            let restSeconds = 90
            let remindersEnabled = false
        }
        defaults.set(try JSONEncoder().encode(State(history: [existingPhone])), forKey: "phone.training.v2")
        let incoming = histories.dropLast().map {
            WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
                totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration)
        }
        let store = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        func replay() throws {
            for offset in stride(from: 0, to: incoming.count, by: WorkoutSync.maximumBatchSize) {
                let chunk = Array(incoming[offset..<min(offset + WorkoutSync.maximumBatchSize, incoming.count)])
                let records = try WorkoutSync.decode(WorkoutSync.message(chunk))
                try store.acceptWatchHistory(records)
            }
        }
        try replay()
        precondition(store.storageError == nil && store.history.count == histories.count)
        try replay()
        precondition(store.history.count == histories.count, "Duplicate import created extra rows")
        for original in histories {
            let imported = store.history.first { $0.id == original.id }!
            precondition(imported.totalReps == original.totalReps && imported.startTime == original.date)
            precondition(imported.duration == original.duration && imported.exercises == [original.exerciseType])
            precondition(imported.volume == nil && imported.sets.isEmpty, "Invented missing set detail")
            let summary = imported.watchSummary ?? imported.legacySummary!
            precondition(summary.maxWeight == original.maxWeight)
        }
        let restored = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(restored.history.count == histories.count, "Relaunch lost rows")
        // Reproduce a process exit after the journal write but before the next
        // UserDefaults flush by restoring the original, source-faithful state.
        defaults.set(try JSONEncoder().encode(State(history: [existingPhone])), forKey: "phone.training.v2")
        let recovered = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(recovered.history.count == histories.count, "Journal did not recover committed rows")
        let removedID = histories[0].id
        let index = store.history.firstIndex { $0.id == removedID }!
        store.deleteHistory(at: IndexSet(integer: index))
        try replay()
        precondition(store.history.count == histories.count - 1 && !store.history.contains { $0.id == removedID })
        let afterDelete = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(afterDelete.history.count == histories.count - 1 && !afterDelete.history.contains { $0.id == removedID })
        let result: [String: Any] = ["sourceRecords": histories.count, "importedWatchRecords": incoming.count,
            "existingSummaryPreserved": true, "duplicatesSuppressed": true, "fieldsPreserved": true,
            "relaunchPreserved": true, "journalRecoveryPassed": true, "deletedRowNotResurrected": true,
            "transportValidated": false]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
    }
}
