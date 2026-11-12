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
        let incoming = histories.map {
            WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
                totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration, activeDuration: $0.activeDuration, totalWeight: $0.totalWeight)
        }
        // Migrate a real old journal together with the existing v2 summary.
        let oldJournal = try WatchWorkoutArchive(url: url)
        try oldJournal.accept(Array(incoming.prefix(10)))
        let journalBytes = try Data(contentsOf: url)
        let store = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(store.history.count == Set(incoming.prefix(10).map(\.id) + [existing.id]).count)
        let journalAfterMigration = try Data(contentsOf: url)
        precondition(journalBytes == journalAfterMigration, "Migration changed the original journal")
        precondition(store.lastSyncAt == nil, "Migration invented a successful sync")
        let legacyCorrectedReps = existing.totalReps == 1_000_000 ? existing.totalReps - 1 : existing.totalReps + 1
        precondition(store.updateRecord(id: existing.id, date: existing.date, sets: [], duration: nil,
            summaryReps: legacyCorrectedReps, summaryWeight: existing.maxWeight, note: "legacy-source verification"))
        let beforeConflict = try Data(contentsOf: store.snapshotURL)
        let beforeConflictIDs = Set(store.history.map(\.id))
        let preceding = incoming.first { !beforeConflictIDs.contains($0.id) } ?? incoming[0]
        let conflictingLegacy = WorkoutSync.Record(id: existing.id, date: existing.date, exercise: existing.exerciseType.rawValue,
            totalReps: legacyCorrectedReps, maxWeight: existing.maxWeight, duration: existing.duration,
            activeDuration: existing.activeDuration, totalWeight: existing.totalWeight)
        do {
            try store.acceptWatchHistory([preceding, conflictingLegacy])
            preconditionFailure("Conflicting legacy source was accepted")
        } catch WorkoutSync.Failure.conflictingRecord {}
        let afterConflict = try Data(contentsOf: store.snapshotURL)
        precondition(beforeConflict == afterConflict && Set(store.history.map(\.id)) == beforeConflictIDs,
            "A conflicting source partially committed its batch")
        func replay() throws {
            for offset in stride(from: 0, to: incoming.count, by: WorkoutSync.maximumBatchSize) {
                let chunk = Array(incoming[offset..<min(offset + WorkoutSync.maximumBatchSize, incoming.count)])
                let records = try WorkoutSync.decode(WorkoutSync.message(chunk))
                try store.acceptWatchHistory(records)
            }
        }
        try replay()
        precondition(store.storageError == nil && store.history.count == histories.count)
        let enrichedLegacy = store.history.first { $0.id == existing.id }!
        precondition(enrichedLegacy.watchSummary?.id == existing.id && enrichedLegacy.legacySummary?.id == existing.id,
            "Matching legacy source was not enriched or original source was discarded")
        precondition(enrichedLegacy.legacySummary?.totalReps == existing.totalReps &&
            enrichedLegacy.watchSummary?.totalReps == existing.totalReps && enrichedLegacy.totalReps == legacyCorrectedReps &&
            enrichedLegacy.note == "legacy-source verification", "Legacy source enrichment overwrote phone edits")
        precondition(store.updateRecord(id: existing.id, date: existing.date, sets: [], duration: nil,
            summaryReps: existing.totalReps, summaryWeight: existing.maxWeight))
        try replay()
        precondition(store.history.count == histories.count, "Duplicate import created extra rows")
        for original in histories {
            let imported = store.history.first { $0.id == original.id }!
            precondition(imported.totalReps == original.totalReps && imported.startTime == original.date)
            precondition(imported.duration == original.duration && imported.exercises == [original.exerciseType])
            precondition(imported.activeDuration == original.activeDuration, "Invented or lost action duration")
            precondition(imported.displayDuration == original.activeDuration, "Displayed elapsed time as training time")
            precondition(imported.volume == original.totalWeight && imported.sets.isEmpty, "Invented or lost measured training volume")
            let summary = imported.watchSummary ?? imported.legacySummary!
            precondition(summary.maxWeight == original.maxWeight)
        }
        let restored = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(restored.history.count == histories.count, "Relaunch lost rows")
        // Daily time totals must equal the original action durations, without
        // turning unavailable action times into zero-valued measurements.
        for metric in RecordTimeMetric.allCases {
            let days = RecordDurationDay.summarize(restored.history, metric: metric)
            var expected: [Date: [TimeInterval]] = [:]
            for history in histories {
                if let value = history.activeDuration {
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
        // Reconcile each displayed period with the unmodified Watch export.
        // Calendar boundaries are computed independently of the UI helpers.
        let calendar = Calendar.current
        var periodCounts: [String: Int] = [:]
        for granularity in [RecordChartGranularity.day, .week, .month] {
            let component: Calendar.Component = granularity == .day ? .day : granularity == .week ? .weekOfYear : .month
            let expected = Dictionary(grouping: histories) { calendar.dateInterval(of: component, for: $0.date)!.start }
            let buckets = RecordTrendBucket.summarize(restored.history, granularity: granularity,
                reps: { $0.totalReps }, weight: { $0.maxWeight })
            periodCounts[granularity.rawValue] = buckets.count
            precondition(buckets.count == expected.count)
            precondition(buckets.reduce(0) { $0 + $1.sessions } == histories.count)
            precondition(buckets.reduce(0) { $0 + $1.reps } == histories.reduce(0) { $0 + $1.totalReps })
            precondition(buckets.map(\.weight).max() == histories.map(\.maxWeight).max())
            for bucket in buckets {
                let originals = expected[bucket.id]!
                let interval = calendar.dateInterval(of: component, for: originals[0].date)!
                precondition(bucket.range == interval && bucket.id == interval.start)
                precondition(originals.allSatisfy { $0.date >= interval.start && $0.date < interval.end })
                precondition(bucket.sessions == originals.count)
                precondition(bucket.reps == originals.reduce(0) { $0 + $1.totalReps })
                precondition(bucket.weight == originals.map(\.maxWeight).max())
            }
            for metric in RecordTimeMetric.allCases {
                let measured = RecordDurationDay.summarize(restored.history, metric: metric, granularity: granularity)
                let expectedMeasured = expected.compactMapValues { originals -> [TimeInterval]? in
                    let values = originals.compactMap(\.activeDuration)
                    return values.isEmpty ? nil : values
                }
                precondition(measured.count == expectedMeasured.count)
                for bucket in measured {
                    let values = expectedMeasured[bucket.id]!
                    precondition(bucket.range == calendar.dateInterval(of: component, for: bucket.id)!)
                    precondition(bucket.recordCount == expected[bucket.id]!.count)
                    precondition(bucket.measuredRecords == values.count)
                    precondition(abs(bucket.seconds - values.reduce(0, +)) < 0.000001)
                }
            }
        }
        let sourceDates = histories.map(\.date)
        // Partial calendar buckets must open exactly the records already counted.
        // Choose real dates inside each populated month, without altering the source.
        var clippedBuckets = 0
        let months = Dictionary(grouping: restored.history) { calendar.dateInterval(of: .month, for: $0.startTime)!.start }
        for rows in months.values {
            let dates = Array(Set(rows.map { calendar.startOfDay(for: $0.startTime) })).sorted()
            guard dates.count > 1 else { continue }
            var filter = RecordFilter(period: .custom, start: dates[dates.count / 2], end: dates.last!)
            let selected = restored.history.filter(filter.includes)
            for grouping in [RecordChartGranularity.week, .month] {
                for bucket in RecordTrendBucket.summarize(selected, granularity: grouping, reps: filter.reps, weight: filter.weight) {
                    let range = filter.intersection(with: bucket.range)!
                    var destination = filter; destination.select(range)
                    let before = selected.filter { $0.startTime >= bucket.range.start && $0.startTime < bucket.range.end }
                    let after = restored.history.filter(destination.includes)
                    precondition(Set(before.map(\.id)) == Set(after.map(\.id)), "Chart drilldown expanded the selected range")
                    if range != bucket.range { clippedBuckets += 1 }
                }
            }
            filter.period = .all
            let fullMonth = calendar.dateInterval(of: .month, for: dates[0])!
            precondition(filter.intersection(with: fullMonth) == fullMonth)
        }
        precondition(clippedBuckets > 0, "Real history did not exercise a partial calendar bucket")
        let sourceSpan = calendar.dateComponents([.day], from: calendar.startOfDay(for: sourceDates.min()!), to: calendar.startOfDay(for: sourceDates.max()!)).day!
        let expectedAutomatic: RecordChartGranularity = sourceSpan <= 45 ? .day : sourceSpan <= 180 ? .week : .month
        precondition(RecordChartGranularity.automatic.resolved(for: sourceDates) == expectedAutomatic)
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
        let measuredCountBeforeManual = store.history.compactMap(\.displayDuration).count
        let sets = [PhoneTrainingSet(exercise: original.exerciseType, weight: original.maxWeight, reps: original.totalReps)]
        precondition(store.addRecord(date: original.date, sets: sets, duration: nil))
        let manual = store.history.first { $0.manualEntry == true }!
        precondition(manual.displayDuration == nil && manual.totalReps == original.totalReps)
        precondition(RecordTimeMetric.active.seconds(in: manual) == nil)
        precondition(RecordDurationDay.summarize([manual], metric: .active).isEmpty)
        for granularity in [RecordChartGranularity.week, .month] {
            precondition(RecordDurationDay.summarize([manual], metric: .active, granularity: granularity).isEmpty)
            let partial = RecordDurationDay.summarize(store.history, metric: .active, granularity: granularity)
            precondition(partial.reduce(0) { $0 + $1.measuredRecords } == measuredCountBeforeManual)
        }
        let measuredBeforeManualDuration = RecordDurationDay.summarize(store.history, metric: .active)
        precondition(measuredBeforeManualDuration.reduce(0) { $0 + $1.measuredRecords } == measuredCountBeforeManual)
        precondition(manual.sets.first?.id == sets.first?.id)
        precondition(store.updateRecord(id: manual.id, date: original.date, sets: sets, duration: original.duration,
            summaryReps: nil, summaryWeight: nil))
        let afterManual = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: url)
        precondition(afterManual.history.first { $0.id == manual.id }?.displayDuration == original.duration)
        precondition(RecordTimeMetric.active.seconds(in: afterManual.history.first { $0.id == manual.id }!) == original.duration)
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
        precondition(failureStore.discardEditorDraft(UUID()), "An unsaved draft should not require a disk write to exit")
        precondition(!failureStore.discardEditorDraft(draft.id), "An existing draft deletion must not falsely report success")
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
        precondition(corruptStore.requiresRecovery)
        do { _ = try corruptStore.previewRestore(Data("broken backup".utf8)); preconditionFailure("Corrupt backup accepted for recovery") } catch {}
        let afterRejectedRecovery = try Data(contentsOf: corruptURL)
        precondition(afterRejectedRecovery == corruptBytes)
        let recovery = try corruptStore.previewRestore(backup)
        precondition(recovery.added == store.history.count)
        try corruptStore.restore(recovery)
        precondition(!corruptStore.requiresRecovery && corruptStore.history.count == store.history.count)
        let protectedFiles = try FileManager.default.contentsOfDirectory(at: corruptURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("before-recovery-") }
        precondition(protectedFiles.count == 1)
        let protectedBytes = try Data(contentsOf: protectedFiles[0])
        precondition(protectedBytes == corruptBytes, "Recovery did not preserve exact original bytes")
        let recoveredFromBackup = PhoneWorkoutStore(defaults: defaults, reminderID: suite, snapshotURL: corruptURL)
        precondition(recoveredFromBackup.history.count == store.history.count && recoveredFromBackup.storageError == nil)
        precondition(store.lastSyncAt == nil, "Receiving batches falsely marked the sync complete")
        precondition(store.confirmSync() && store.lastSyncAt != nil)
        let result: [String: Any] = ["sourceRecords": histories.count, "importedWatchRecords": incoming.count,
            "existingSummaryPreserved": true, "duplicatesSuppressed": true, "fieldsPreserved": true,
            "dailyDurationMatchesSource": true, "missingDurationsNotZero": true, "partialDurationCoverageCorrect": true,
            "periodAggregationMatchesSource": true, "periodSelectionBoundsPreserved": true, "periodCounts": periodCounts,
            "automaticGranularity": expectedAutomatic.rawValue, "sourceZeroDurationRecords": histories.filter { $0.duration == 0 }.count,
            "partialChartDrilldownBuckets": clippedBuckets, "unreadableSnapshotRecoveryPassed": true,
            "recoveryOriginalBytesPreserved": true, "unsavedEditorCanExitWithoutWrite": true,
            "relaunchPreserved": true, "journalRecoveryPassed": true, "deletedRowNotResurrected": true,
            "phoneCorrectionsSurviveResync": true, "manualRecordEditingPreserved": true, "invalidEditsRejected": true,
            "legacySameIDReplayPreservesSourceAndCorrection": true,
            "legacySourceConflictRejectsWholeBatch": true,
            "backupRoundTripPassed": true, "restoreConflictRulesPassed": true, "invalidBackupsRejected": true,
            "draftsPreserved": true, "failedWritesKeepPublishedState": true, "csvNoInventedSets": true, "originalJournalPreserved": true, "corruptSnapshotPreserved": true, "syncTimestampRequiresConfirmation": true, "transportValidated": false]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]))
    }
}
