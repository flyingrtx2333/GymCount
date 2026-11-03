import Foundation

// Only real private history/timelines are accepted. Writes use a disposable
// directory; this exercises the asynchronous entry points used by the app.
@main enum VerifyPerformanceStorage {
    @MainActor static func main() async throws {
        func check(_ value: Bool) { precondition(value) }
        let historyURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let tracesURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let historyBytes = try Data(contentsOf: historyURL)
        let history = try JSONDecoder().decode([WorkoutHistory].self, from: historyBytes)
        let paths = try FileManager.default.contentsOfDirectory(at: tracesURL, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let input = try paths.map { try Data(contentsOf: $0) }
        let traces = try input.map { try JSONDecoder().decode(WorkoutTimeline.self, from: $0) }
        precondition(!history.isEmpty && !traces.isEmpty)
        let suite = "PowerReps.AsyncStorage." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func store(_ name: String) -> PhoneWorkoutStore {
            PhoneWorkoutStore(defaults: defaults, reminderID: suite, snapshotURL: root.appendingPathComponent(name + "/records-v3.json"))
        }
        let phone = store("phone")
        // Repeated concurrent deliveries are serialized, never based on a stale snapshot.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in traces.indices {
                let trace = traces[index], bytes = input[index]
                group.addTask { try await phone.receiveWatchHistory([trace.source]) }
                group.addTask { try await phone.receiveWatchTimeline(bytes, id: trace.id) }
            }
            try await group.waitForAll()
        }
        precondition(phone.history.count == traces.count)
        for (trace, path) in zip(traces, paths) {
            try await phone.receiveWatchTimelineFile(path, id: trace.id)
            check(try await phone.loadTimeline(trace.id) == trace)
        }
        let revision = phone.historyRevision
        var draft = RecordEditorDraft(sets: []); draft.date = history[0].date
        precondition(phone.saveDraft(draft))
        precondition(phone.historyRevision == revision, "Drafts must not invalidate trend statistics")
        let first = traces[0]
        precondition(phone.updateRecord(id: first.id, date: first.source.date, sets: [], duration: nil,
            summaryReps: first.source.totalReps + 1, summaryWeight: first.source.maxWeight))
        try await phone.receiveWatchHistory([first.source])
        precondition(phone.history.first { $0.id == first.id }!.totalReps == first.source.totalReps + 1)
        let export = try await phone.exportBackup()
        defer { try? FileManager.default.removeItem(at: export) }
        let backupSize = try export.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let restored = store("restored")
        let preview = try await restored.readBackup(export)
        precondition(preview.added == traces.count)
        try await restored.mergeBackup(preview)
        precondition(restored.history == phone.history)
        for trace in traces { check(try await restored.loadTimeline(trace.id) == trace) }
        let duplicate = try await restored.readBackup(export)
        precondition(duplicate.added == 0)
        try await restored.mergeBackup(duplicate)
        precondition(restored.history == phone.history)
        // A deleted row cannot reappear from a late file, summary, or backup.
        precondition(restored.deleteRecords(ids: [first.id]))
        try await restored.receiveWatchHistory([first.source])
        try await restored.receiveWatchTimeline(input[0], id: first.id)
        try await restored.mergeBackup(preview)
        precondition(!restored.history.contains { $0.id == first.id })
        check(try await restored.loadTimeline(first.id) == nil)
        let reopened = store("restored")
        precondition(reopened.history == restored.history)
        let damaged = root.appendingPathComponent("damaged.json")
        try Data(contentsOf: export).prefix(100).write(to: damaged)
        do { _ = try await restored.readBackup(damaged); preconditionFailure("Damaged backup accepted") } catch {}
        let failed = store("failed")
        let failedPreview = try await failed.readBackup(export)
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try FileManager.default.createDirectory(at: failed.snapshotURL, withIntermediateDirectories: true)
        try historyBytes.write(to: failed.snapshotURL.appendingPathComponent("preserve"))
        do { try await failed.mergeBackup(failedPreview); preconditionFailure("Failed commit accepted") } catch {}
        precondition(failed.history.isEmpty)
        let staging = failed.snapshotURL.deletingLastPathComponent().appendingPathComponent("Timelines")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        precondition(leftovers.isEmpty, "Failed restore left traces behind")
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try await failed.mergeBackup(failedPreview)
        precondition(failed.history.count == traces.count)
        // Startup returns summaries immediately; enrichment is explicit and cached.
        let cold = store("cold")
        try cold.acceptWatchHistory(traces.map(\.source))
        let archive = WorkoutTimelineArchive(folder: cold.snapshotURL.deletingLastPathComponent().appendingPathComponent("Timelines"))
        for trace in traces { try archive.retain(trace) }
        let launched = store("cold")
        await launched.enrichRetainedDurations()
        let afterEnrichment = launched.history
        let cache = launched.snapshotURL.deletingLastPathComponent().appendingPathComponent("duration-attempts-v1.json")
        let beforeCache = try Data(contentsOf: cache)
        await launched.enrichRetainedDurations()
        precondition(launched.history == afterEnrichment)
        check(try Data(contentsOf: cache) == beforeCache)
        let real82 = store("history82")
        let records = history.map { WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
            totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration,
            activeDuration: $0.activeDuration, totalWeight: $0.totalWeight) }
        try await real82.receiveWatchHistory(records)
        precondition(real82.history.count == history.count)
        let historyRevision = real82.historyRevision
        let confirmed = await real82.confirmReceivedSync()
        precondition(confirmed)
        precondition(real82.historyRevision == historyRevision && real82.lastSyncAt != nil)
        check(try Data(contentsOf: historyURL) == historyBytes)
        for (path, bytes) in zip(paths, input) { check(try Data(contentsOf: path) == bytes) }
        let proof: [String: Any] = ["realHistoryRecords": history.count, "realTimelines": traces.count,
            "backupBytes": backupSize, "concurrentReceiptMergePassed": true, "rawSamplesUnchanged": true,
            "correctionDeletionRestartPassed": true, "asyncBackupRestorePassed": true,
            "failedRestoreRollbackPassed": true, "durationAttemptCachePassed": true,
            "unrelatedUpdatesKeepHistoryRevision": true, "networkOrPhysicalWatchTested": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
