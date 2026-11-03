import Foundation

// Inputs are the unchanged raw segment and report replay of a real capture.
// All writes are isolated; no new movement or health measurements are invented.
@main enum VerifyReportSensorStorage {
    @MainActor static func main() async throws {
        func check(_ value: Bool, _ reason: String = "Check failed") { precondition(value, reason) }
        guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileNoSuchFile) }
        let reportURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let timelineURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let reportBytes = try Data(contentsOf: reportURL), timelineBytes = try Data(contentsOf: timelineURL)
        let records = try JSONDecoder().decode([WorkoutSync.Record].self, from: reportBytes)
        guard let source = records.first, let report = source.workoutReport else { throw CocoaError(.fileReadCorruptFile) }
        let timeline = try JSONDecoder().decode(WorkoutTimeline.self, from: timelineBytes)
        try WorkoutReportSensorArchive.validate(timeline, for: source)
        let suite = "PowerReps.ReportSensorStorage." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func store(_ name: String) -> PhoneWorkoutStore {
            PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: root.appendingPathComponent(name + "/watch.json"),
                              snapshotURL: root.appendingPathComponent(name + "/records-v3.json"))
        }
        func sensorURL(_ store: PhoneWorkoutStore) -> URL {
            store.snapshotURL.deletingLastPathComponent().appendingPathComponent("ReportSensors/" + source.id.uuidString + "/" + timeline.id.uuidString + ".json")
        }
        let phone = store("phone")
        do {
            try await phone.receiveWatchReportSensorFile(timelineURL, workoutID: source.id, segmentID: timeline.id)
            preconditionFailure("Sensor must wait for its durable parent report")
        } catch { }
        check(!FileManager.default.fileExists(atPath: sensorURL(phone).path))
        try await phone.receiveWatchHistory(records)
        try await phone.receiveWatchReportSensorFile(timelineURL, workoutID: source.id, segmentID: timeline.id)
        check(try await phone.loadReportSensor(source.id, segmentID: timeline.id) == timeline)
        let index = try await phone.loadReportSensorIndex(source.id)
        check(index.count == 1 && index[0].id == timeline.id && index[0].origin == timeline.origin)
        let persisted = try Data(contentsOf: sensorURL(phone))
        // Repeated concurrent files remain one segment and preserve raw precision.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 { group.addTask { try await phone.receiveWatchReportSensorFile(timelineURL, workoutID: source.id, segmentID: timeline.id) } }
            try await group.waitForAll()
        }
        check(try Data(contentsOf: sensorURL(phone)) == persisted)
        let repetitions = report.sets.flatMap(\.repetitions).map(\.id)
        if report.sets.count == 1 && repetitions.count > 1 {
            check(phone.updateReportGrouping(id: source.id, groups: [Array(repetitions.prefix(1)), Array(repetitions.dropFirst())]))
        }
        check(phone.updateRecord(id: source.id, date: source.date, sets: [], duration: nil,
                                 summaryReps: source.totalReps + 1, summaryWeight: source.maxWeight))
        try await phone.receiveWatchHistory(records)
        try await phone.receiveWatchReportSensorFile(timelineURL, workoutID: source.id, segmentID: timeline.id)
        check(phone.history[0].sourceWorkoutReport == report)
        check(phone.history[0].totalReps == source.totalReps + 1)
        check(try await phone.loadReportSensor(source.id, segmentID: timeline.id) == timeline)
        let reopened = store("phone")
        check(reopened.history == phone.history)
        check(try await reopened.loadReportSensor(source.id, segmentID: timeline.id) == timeline)
        let exported = try await phone.exportBackup()
        defer { try? FileManager.default.removeItem(at: exported) }
        let backupBytes = try Data(contentsOf: exported)
        let backup = try JSONDecoder().decode(RecordBackup.self, from: backupBytes)
        check(backup.version == 4 && backup.reportSensors?.count == 1)
        check(backup.reportSensors?[0].timeline == timeline)
        let restored = store("restored")
        let preview = try await restored.readBackup(exported)
        try await restored.mergeBackup(preview)
        check(restored.history == phone.history)
        check(try await restored.loadReportSensor(source.id, segmentID: timeline.id) == timeline)
        check(restored.updateRecord(id: source.id, date: source.date, sets: [], duration: nil,
                                    summaryReps: source.totalReps + 2, summaryWeight: source.maxWeight))
        let currentRecords = restored.history, currentSensorBytes = try Data(contentsOf: sensorURL(restored))
        try await restored.mergeBackup(preview)
        check(restored.history == currentRecords)
        check(try Data(contentsOf: sensorURL(restored)) == currentSensorBytes)
        var corrupt = backup
        corrupt.reportSensors = (backup.reportSensors ?? []) + (backup.reportSensors ?? [])
        do { _ = try restored.previewRestore(JSONEncoder().encode(corrupt)); preconditionFailure("Duplicate segment accepted") } catch { }
        corrupt = backup
        corrupt.reportSensors = [.init(workoutID: UUID(), timeline: timeline)]
        do { _ = try restored.previewRestore(JSONEncoder().encode(corrupt)); preconditionFailure("Unmatched parent accepted") } catch { }
        corrupt = backup; corrupt.version = 3
        do { _ = try restored.previewRestore(JSONEncoder().encode(corrupt)); preconditionFailure("Version 3 accepted new sensors") } catch { }
        corrupt = backup; corrupt.version = 5
        do { _ = try restored.previewRestore(JSONEncoder().encode(corrupt)); preconditionFailure("Future version accepted") } catch { }
        do { _ = try restored.previewRestore(backupBytes.prefix(100)); preconditionFailure("Truncated backup accepted") } catch { }
        for version in 1...3 {
            var legacy = RecordBackup(snapshot: RecordSnapshot())
            legacy.version = version; legacy.snapshot.version = version < 3 ? 3 : 4
            _ = try restored.previewRestore(JSONEncoder().encode(legacy))
        }
        var priorReportBackup = backup
        priorReportBackup.version = 3; priorReportBackup.reportSensors = nil
        _ = try restored.previewRestore(JSONEncoder().encode(priorReportBackup))
        let failed = store("failed")
        let failedPreview = try await failed.readBackup(exported)
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try FileManager.default.createDirectory(at: failed.snapshotURL, withIntermediateDirectories: true)
        try reportBytes.write(to: failed.snapshotURL.appendingPathComponent("preserve"))
        do { try await failed.mergeBackup(failedPreview); preconditionFailure("Failed record commit accepted") } catch { }
        check(failed.history.isEmpty && !FileManager.default.fileExists(atPath: sensorURL(failed).path))
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try await failed.mergeBackup(failedPreview)
        check(try await failed.loadReportSensor(source.id, segmentID: timeline.id) == timeline)
        // A pre-existing local segment survives rollback, rather than being removed.
        let retained = store("retained")
        let retainedArchive = WorkoutReportSensorArchive(folder: retained.snapshotURL.deletingLastPathComponent().appendingPathComponent("ReportSensors"))
        try retainedArchive.retain(timeline, for: source)
        let retainedBytes = try Data(contentsOf: sensorURL(retained))
        try FileManager.default.removeItem(at: retained.snapshotURL)
        try FileManager.default.createDirectory(at: retained.snapshotURL, withIntermediateDirectories: true)
        try reportBytes.write(to: retained.snapshotURL.appendingPathComponent("preserve"))
        do { try await retained.mergeBackup(preview); preconditionFailure("Failed commit accepted") } catch { }
        check(try Data(contentsOf: sensorURL(retained)) == retainedBytes)
        check(restored.deleteRecords(ids: [source.id]))
        check(!FileManager.default.fileExists(atPath: sensorURL(restored).path))
        // Deleted parents acknowledge even a missing delayed file without reopening it.
        try await restored.receiveWatchReportSensorFile(root.appendingPathComponent("missing.json"), workoutID: source.id, segmentID: timeline.id)
        try await restored.receiveWatchHistory(records)
        try await restored.mergeBackup(preview)
        check(restored.history.isEmpty)
        check(try await restored.loadReportSensorIndex(source.id).isEmpty)
        check(try await restored.loadReportSensor(source.id, segmentID: timeline.id) == nil)
        check(try Data(contentsOf: reportURL) == reportBytes)
        check(try Data(contentsOf: timelineURL) == timelineBytes)
        let proof: [String: Any] = ["sourceReportRepetitions": report.totalReps,
            "realAccelerationSamples": timeline.acceleration.count, "realMotionSamples": timeline.motion.count,
            "sensorBeforeParentRetryable": true, "rawPrecisionPreserved": true, "concurrentDuplicateReceiptPassed": true,
            "correctionGroupingSourcePreserved": true, "backupVersion": 4, "legacyVersionsAccepted": [1, 2, 3],
            "sensorBackupRestoreRestartPassed": true, "currentContentWinsMerge": true,
            "duplicateMalformedUnsupportedRejected": true, "failedRestoreRollsBackNewOnly": true,
            "deletionWinsLateFilesAndRestore": true, "sourceFilesUnchanged": true,
            "physicalTransportTested": false]
        print(String(decoding: try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
