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
                totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration, activeDuration: $0.activeDuration)
        }
        // Migrate a real old journal together with the existing v2 summary.
        let oldJournal = try WatchWorkoutArchive(url: url)
        try oldJournal.accept(Array(incoming.prefix(10)))
        let journalBytes = try Data(contentsOf: url)
        let store = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(store.history.count == 11)
        let journalAfterMigration = try Data(contentsOf: url)
        precondition(journalBytes == journalAfterMigration, "Migration changed the original journal")
        precondition(store.lastSyncAt == nil, "Migration invented a successful sync")
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
            precondition(imported.activeDuration == original.activeDuration, "Invented or lost action duration")
            precondition(imported.volume == nil && imported.sets.isEmpty, "Invented missing set detail")
            let summary = imported.watchSummary ?? imported.legacySummary!
            precondition(summary.maxWeight == original.maxWeight)
        }
        let restored = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(restored.history.count == histories.count, "Relaunch lost rows")
        // Daily time totals must equal the original recorded durations, without
        // turning unavailable action times into zero-valued measurements.
        for metric in RecordTimeMetric.allCases {
            let days = RecordDurationDay.summarize(restored.history, metric: metric)
            var expected: [Date: [TimeInterval]] = [:]
            for history in histories {
                if let value = metric == .elapsed ? history.duration : history.activeDuration {
                    expected[Calendar.current.startOfDay(for: history.date), default: []].append(value)
                }
            }
            precondition(days.count == expected.count)
            for day in days {
                let values = expected[day.id]!
                precondition(day.measuredRecords == values.count)
                precondition(day.recordCount == histories.filter { Calendar.current.startOfDay(for: $0.date) == day.id }.count)
                precondition(abs(day.seconds - values.reduce(0, +)) < 0.000001)
            }
        }
        // Exercise phone-only corrections against a real source summary. The
        // Watch source, group boundaries and duration must remain untouched.
        let target = incoming[0]
        let correctedReps = target.totalReps == 1_000_000 ? target.totalReps - 1 : target.totalReps + 1
        let correctedWeight = min(500, target.maxWeight + 2.5)
        precondition(store.updateRecord(id: target.id, date: target.date, sets: [], duration: nil,
            summaryReps: correctedReps, summaryWeight: correctedWeight))
        try replay()
        let corrected = store.history.first { $0.id == target.id }!
        precondition(corrected.totalReps == correctedReps && corrected.maxWeight == correctedWeight)
        precondition(corrected.watchSummary?.totalReps == target.totalReps && corrected.watchSummary?.maxWeight == target.maxWeight)
        precondition(corrected.sets.isEmpty && corrected.volume == nil && corrected.duration == target.duration)
        let afterEdit = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(afterEdit.history.first { $0.id == target.id }?.totalReps == correctedReps)
        let savedState = try Data(contentsOf: store.snapshotURL)
        precondition(!store.updateRecord(id: target.id, date: target.date, sets: [], duration: nil,
            summaryReps: correctedReps, summaryWeight: .nan))
        let afterInvalid = try Data(contentsOf: store.snapshotURL)
        precondition(afterInvalid == savedState)
        let original = histories.first { $0.totalReps > 0 && $0.totalReps <= 999 && $0.maxWeight <= 500 }!
        let sets = [PhoneTrainingSet(exercise: original.exerciseType, weight: original.maxWeight, reps: original.totalReps)]
        precondition(store.addRecord(date: original.date, sets: sets, duration: nil))
        let manual = store.history.first { $0.manualEntry == true }!
        precondition(manual.displayDuration == nil && manual.totalReps == original.totalReps)
        precondition(RecordTimeMetric.elapsed.seconds(in: manual) == nil)
        precondition(RecordDurationDay.summarize([manual], metric: .elapsed).isEmpty)
        let measuredBeforeManualDuration = RecordDurationDay.summarize(store.history, metric: .elapsed)
        precondition(measuredBeforeManualDuration.reduce(0) { $0 + $1.measuredRecords } == histories.count)
        precondition(measuredBeforeManualDuration.contains { $0.recordCount > $0.measuredRecords })
        precondition(manual.sets.first?.id == sets.first?.id)
        precondition(store.updateRecord(id: manual.id, date: original.date, sets: sets, duration: original.duration,
            summaryReps: nil, summaryWeight: nil))
        let afterManual = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(afterManual.history.first { $0.id == manual.id }?.displayDuration == original.duration)
        precondition(RecordTimeMetric.elapsed.seconds(in: afterManual.history.first { $0.id == manual.id }!) == original.duration)
        store.deleteRecord(id: manual.id)
        precondition(store.history.count == histories.count)
        // Once migrated, stale UserDefaults must not replace the atomic snapshot.
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
        // Export/restore real records in a second isolated store.
        let backup = try store.backupData()
        let restoreURL = root.appendingPathComponent("restore/watch.json")
        let emptyDefaults = UserDefaults(suiteName: suite + ".restore")!
        defer { emptyDefaults.removePersistentDomain(forName: suite + ".restore") }
        let restoredBackup = PhoneWorkoutStore(defaults: emptyDefaults, reminderID: suite, watchArchiveURL: restoreURL)
        let preview = try restoredBackup.previewRestore(backup)
        precondition(preview.added == store.history.count)
        try restoredBackup.restore(preview)
        precondition(restoredBackup.history.count == store.history.count)
        precondition(restoredBackup.history.first { $0.id == target.id }?.totalReps == store.history.first { $0.id == target.id }?.totalReps)
        let duplicatePreview = try restoredBackup.previewRestore(backup)
        precondition(duplicatePreview.added == 0 && duplicatePreview.skipped == store.history.count)
        try restoredBackup.restore(duplicatePreview)
        // Local corrections and deletes win over an older backup.
        let survivor = restoredBackup.history.first!
        precondition(restoredBackup.updateRecord(id: survivor.id, date: survivor.startTime, sets: [], duration: nil,
            summaryReps: 7, summaryWeight: 40, note: "real-history verification"))
        try restoredBackup.restore(preview)
        precondition(restoredBackup.history.first { $0.id == survivor.id }?.totalReps == 7)
        precondition(restoredBackup.deleteRecords(ids: [survivor.id]))
        try restoredBackup.restore(preview)
        precondition(!restoredBackup.history.contains { $0.id == survivor.id })
        var deletedBackup = try JSONDecoder().decode(RecordBackup.self, from: backup)
        let protectedID = store.history.first!.id
        deletedBackup.snapshot.history.removeAll { $0.id == protectedID }
        deletedBackup.snapshot.deletedIDs.insert(protectedID)
        let deletionPreview = try store.previewRestore(JSONEncoder().encode(deletedBackup))
        try store.restore(deletionPreview)
        precondition(store.history.contains { $0.id == protectedID })
        // Draft contents, including incomplete numbers, round-trip without becoming a workout.
        var draft = RecordEditorDraft(sets: [RecordSetDraft(exercise: .benchPress, weight: "42.")])
        draft.note = "unfinished"
        precondition(store.saveDraft(draft))
        let draftReload = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(draftReload.editorDrafts.first?.sets.first?.weight == "42.")
        let csv = store.csv(records: store.history, sets: false)
        let groupsCSV = store.csv(records: store.history, sets: true)
        precondition(csv.contains("duration_seconds") && groupsCSV.components(separatedBy: "\r\n").count == 2, "Summary invented set rows")
        var bad = deletedBackup; bad.version = 999
        for data in [Data("broken".utf8), try JSONEncoder().encode(bad)] {
            do { _ = try store.previewRestore(data); preconditionFailure("Invalid backup accepted") } catch {}
        }
        var invalid = deletedBackup
        invalid.snapshot.history[0].note = String(repeating: "x", count: 2001)
        do { _ = try store.previewRestore(JSONEncoder().encode(invalid)); preconditionFailure("Invalid field accepted") } catch {}
        // A failed write must not publish a record or discard the draft. Retry is possible.
        let failureURL = root.appendingPathComponent("failure/records.json")
        let failureStore = PhoneWorkoutStore(defaults: emptyDefaults, reminderID: suite, watchArchiveURL: root.appendingPathComponent("failure/watch.json"), snapshotURL: failureURL)
        precondition(failureStore.saveDraft(draft))
        let originalState = try Data(contentsOf: failureURL)
        try FileManager.default.removeItem(at: failureURL.deletingLastPathComponent())
        try Data("unwritable parent".utf8).write(to: failureURL.deletingLastPathComponent())
        precondition(!failureStore.addRecord(date: original.date, sets: sets, duration: nil, draftID: draft.id))
        precondition(failureStore.editorDrafts.first?.id == draft.id)
        precondition(failureStore.history.isEmpty && failureStore.storageError != nil)
        try FileManager.default.removeItem(at: failureURL.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: failureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalState.write(to: failureURL)
        precondition(failureStore.addRecord(date: original.date, sets: sets, duration: nil))
        precondition(failureStore.history.count == 1 && failureStore.storageError == nil)
        let corruptURL = root.appendingPathComponent("corrupt/records-v3.json")
        try FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptBytes = Data("damaged existing snapshot".utf8)
        try corruptBytes.write(to: corruptURL)
        let corruptStore = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: root.appendingPathComponent("corrupt/watch.json"), snapshotURL: corruptURL)
        precondition(corruptStore.storageError != nil)
        precondition(!corruptStore.addRecord(date: original.date, sets: sets, duration: nil))
        let afterCorruptWrite = try Data(contentsOf: corruptURL)
        precondition(afterCorruptWrite == corruptBytes, "Corrupt snapshot overwritten by fallback")
        precondition(store.lastSyncAt == nil, "Receiving batches falsely marked the sync complete")
        precondition(store.confirmSync() && store.lastSyncAt != nil)
        let result: [String: Any] = ["sourceRecords": histories.count, "importedWatchRecords": incoming.count,
            "existingSummaryPreserved": true, "duplicatesSuppressed": true, "fieldsPreserved": true,
            "dailyDurationMatchesSource": true, "missingDurationsNotZero": true, "partialDurationCoverageCorrect": true,
            "relaunchPreserved": true, "journalRecoveryPassed": true, "deletedRowNotResurrected": true,
            "phoneCorrectionsSurviveResync": true, "manualRecordEditingPreserved": true, "invalidEditsRejected": true,
            "backupRoundTripPassed": true, "restoreConflictRulesPassed": true, "invalidBackupsRejected": true,
            "draftsPreserved": true, "failedWritesKeepPublishedState": true, "csvNoInventedSets": true, "originalJournalPreserved": true, "corruptSnapshotPreserved": true, "syncTimestampRequiresConfirmation": true, "transportValidated": false]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
    }
}
