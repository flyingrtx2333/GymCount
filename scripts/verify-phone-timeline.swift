import Foundation

// Use a private, real capture export. Waveforms and completion events are never
// generated here. The capture's summary header uses its recorded count/date/
// duration; captures do not contain load, so no load-dependent claim is made.
@main
enum VerifyPhoneTimeline {
    @MainActor
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let rows = try JSONSerialization.jsonObject(with: input) as! [[String: Any]]
        let selectedID = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 24
        let row = rows.first { ($0["id"] as? Int) == selectedID }!
        let capture = row["recording"] as! [String: Any]
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let started = capture["started_at"] as! String
        let date = iso.date(from: started) ?? ISO8601DateFormatter().date(from: started)!
        let source = WorkoutSync.Record(id: UUID(uuidString: capture["session_id"] as! String)!, date: date,
            exercise: capture["exercise"] as! String, totalReps: capture["detected_count"] as! Int,
            maxWeight: 0, duration: capture["duration_seconds"] as! Double)
        let timeline = try WorkoutTimeline(captureData: JSONSerialization.data(withJSONObject: capture), source: source)
        let suite = "PowerRepsRealTimeline." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func store(_ name: String) -> PhoneWorkoutStore {
            PhoneWorkoutStore(defaults: defaults, reminderID: suite,
                watchArchiveURL: root.appendingPathComponent(name + "/history.json"),
                snapshotURL: root.appendingPathComponent(name + "/records-v3.json"))
        }
        let phone = store("phone")
        // Files may arrive first and must survive relaunch without creating a row.
        check(try phone.acceptWatchTimeline(timeline))
        precondition(phone.history.isEmpty)
        let launched = store("phone")
        let conflictSource = WorkoutSync.Record(id: source.id, date: source.date, exercise: source.exercise,
            totalReps: source.totalReps + 1, maxWeight: source.maxWeight, duration: source.duration)
        do { try launched.acceptWatchHistory([conflictSource]); preconditionFailure("Conflicting late summary accepted") }
        catch WorkoutSync.Failure.conflictingRecord {}
        precondition(launched.history.isEmpty)
        try launched.acceptWatchHistory([source])
        check(try launched.timeline(for: source.id) == timeline)
        check(try launched.acceptWatchTimeline(timeline))
        // Phone corrections never rewrite raw automatic completion events.
        let correctedReps = source.totalReps + 1
        precondition(launched.updateRecord(id: source.id, date: date, sets: [], duration: nil,
            summaryReps: correctedReps, summaryWeight: 42.5))
        try launched.acceptWatchHistory([source])
        precondition(launched.history[0].totalReps == correctedReps)
        check(try launched.timeline(for: source.id) == timeline)
        var conflicting = timeline
        conflicting.source = WorkoutSync.Record(id: source.id, date: source.date, exercise: source.exercise,
            totalReps: correctedReps, maxWeight: source.maxWeight, duration: source.duration)
        do { _ = try launched.acceptWatchTimeline(conflicting); preconditionFailure("Conflicting source accepted") }
        catch WorkoutSync.Failure.conflictingRecord {}
        var truncated = timeline; truncated.acceleration.removeLast()
        do { _ = try launched.acceptWatchTimeline(truncated); preconditionFailure("Changed waveform accepted") }
        catch WorkoutTimeline.Failure.conflicting {}
        check(try launched.timeline(for: source.id) == timeline)
        let backup = try launched.backupData()
        let decoded = try JSONDecoder().decode(RecordBackup.self, from: backup)
        precondition(decoded.version == 4 && decoded.timelines == [timeline])
        let restored = store("restored")
        let preview = try restored.previewRestore(backup)
        precondition(preview.added == 1)
        try restored.restore(preview)
        check(try restored.timeline(for: source.id) == timeline)
        precondition(restored.history[0].totalReps == correctedReps)
        let reopened = store("restored")
        check(try reopened.timeline(for: source.id) == timeline)
        // An existing UUID and its current edits always win during merge restore.
        precondition(reopened.updateRecord(id: source.id, date: date, sets: [], duration: nil,
            summaryReps: correctedReps + 1, summaryWeight: 45))
        let duplicate = try reopened.previewRestore(backup)
        precondition(duplicate.added == 0 && duplicate.skipped == 1)
        try reopened.restore(duplicate)
        precondition(reopened.history[0].totalReps == correctedReps + 1)
        check(try reopened.timeline(for: source.id) == timeline)
        var backupDeletion = decoded
        backupDeletion.snapshot.history = []
        backupDeletion.snapshot.deletedIDs.insert(source.id)
        backupDeletion.timelines = nil
        try reopened.restore(reopened.previewRestore(JSONEncoder().encode(backupDeletion)))
        precondition(reopened.history.count == 1)
        check(try reopened.timeline(for: source.id) == timeline)
        // Version 1 remains importable, but cannot smuggle new waveform content.
        var legacy = decoded; legacy.version = 1; legacy.snapshot.version = 3; legacy.timelines = nil
        let old = store("legacy")
        try old.restore(old.previewRestore(JSONEncoder().encode(legacy)))
        check(try old.history.count == 1 && old.timeline(for: source.id) == nil)
        var malformed = decoded; malformed.timelines = [timeline, timeline]
        do { _ = try reopened.previewRestore(JSONEncoder().encode(malformed)); preconditionFailure("Duplicate timeline accepted") }
        catch {}
        do { _ = try reopened.previewRestore(Data("broken".utf8)); preconditionFailure("Broken backup accepted") }
        catch {}
        // Persist tombstones before cleanup; delayed files and backups stay gone.
        precondition(reopened.deleteRecords(ids: [source.id]))
        check(!(try reopened.acceptWatchTimeline(timeline)))
        try reopened.acceptWatchHistory([source])
        check(try reopened.history.isEmpty && reopened.timeline(for: source.id) == nil)
        try reopened.restore(reopened.previewRestore(backup))
        precondition(reopened.history.isEmpty)
        let afterDelete = store("restored")
        check(try afterDelete.history.isEmpty && !afterDelete.acceptWatchTimeline(timeline))
        // A real raw file written before a failed metadata commit is rolled back.
        let failed = store("failed")
        let failurePreview = try failed.previewRestore(backup)
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try FileManager.default.createDirectory(at: failed.snapshotURL, withIntermediateDirectories: true)
        let blocker = failed.snapshotURL.appendingPathComponent("keep")
        try Data("preserve".utf8).write(to: blocker)
        do { try failed.restore(failurePreview); preconditionFailure("Blocked snapshot accepted") }
        catch {}
        let staged = failed.snapshotURL.deletingLastPathComponent().appendingPathComponent("Timelines/" + source.id.uuidString + ".json")
        precondition(!FileManager.default.fileExists(atPath: staged.path) && failed.history.isEmpty)
        try FileManager.default.removeItem(at: failed.snapshotURL)
        try failed.restore(failurePreview)
        check(try failed.timeline(for: source.id) == timeline)
        print("Real capture \(selectedID): \(timeline.acceleration.count) acceleration / \(timeline.motion.count) motion samples; import, late summary, relaunch, correction, backup v1/v2, restore conflict, delete, late file and failed-commit rollback passed.")
    }
}
