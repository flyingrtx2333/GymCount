import Foundation

// Read an actual Watch history export. All persistence uses a temporary folder;
// no summary is expanded into invented repetitions or training volume.
@main
enum VerifyWatchHistoryCompatibility {
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceBytes = try Data(contentsOf: source)
        let histories = try JSONDecoder().decode([WorkoutHistory].self, from: sourceBytes)
        precondition(!histories.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WatchHistoryCompatibility." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let records = histories.map {
            WorkoutSync.Record(id: $0.id, date: $0.date, exercise: $0.exerciseType.rawValue,
                totalReps: $0.totalReps, maxWeight: $0.maxWeight, duration: $0.duration,
                activeDuration: $0.activeDuration, totalWeight: $0.totalWeight)
        }
        let url = root.appendingPathComponent("history.json")
        let archive = try WatchWorkoutArchive(url: url)
        for _ in 0..<2 {
            for offset in stride(from: 0, to: records.count, by: WorkoutSync.maximumBatchSize) {
                let chunk = Array(records[offset..<min(offset + WorkoutSync.maximumBatchSize, records.count)])
                try archive.accept(WorkoutSync.decode(WorkoutSync.message(chunk)))
            }
        }
        let reopened = try WatchWorkoutArchive(url: url)
        precondition(reopened.records == records, "Replay or relaunch changed the source summaries")
        let roundTrip = try JSONDecoder().decode([WorkoutHistory].self, from: JSONEncoder().encode(histories))
        for (original, restored) in zip(histories, roundTrip) {
            precondition(original.id == restored.id && original.date == restored.date && original.exerciseType == restored.exerciseType)
            precondition(original.totalReps == restored.totalReps && original.maxWeight == restored.maxWeight && original.duration == restored.duration)
            precondition(original.activeDuration == restored.activeDuration && original.totalWeight == restored.totalWeight)
        }
        for identifier in ["America/Los_Angeles", "Asia/Shanghai"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            for firstWeekday in [1, 2] {
                calendar.firstWeekday = firstWeekday
                for history in histories {
                    let week = WatchWorkoutWeek.interval(containing: history.date, calendar: calendar)
                    precondition(calendar.component(.weekday, from: week.start) == 2)
                    precondition(WatchWorkoutWeek.contains(history.date, in: week))
                    precondition(WatchWorkoutWeek.contains(week.start, in: week))
                    precondition(!WatchWorkoutWeek.contains(week.end, in: week))
                    precondition(calendar.date(byAdding: .day, value: 7, to: week.start) == week.end)
                }
            }
        }
        let draftURL = root.appendingPathComponent("draft/current-workout-v1.json")
        let drafts = WatchWorkoutDraftStore(url: draftURL)
        try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Damage an isolated copy of the actual export bytes. No invented
        // workout is loaded, recovered, or accepted as training evidence.
        let damagedBytes = Data(sourceBytes.prefix(max(1, sourceBytes.count / 2)))
        try damagedBytes.write(to: draftURL, options: .atomic)
        do {
            _ = try drafts.load()
            preconditionFailure("Damaged source bytes were accepted as a workout draft")
        } catch {}
        let blockedRecovery = draftURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        try sourceBytes.write(to: blockedRecovery, options: .atomic)
        do {
            _ = try drafts.preserveForRecovery()
            preconditionFailure("An obstructed recovery destination was accepted")
        } catch {}
        let afterFailedPreservation = try Data(contentsOf: draftURL)
        precondition(afterFailedPreservation == damagedBytes, "Failed preservation changed the original file")
        try FileManager.default.removeItem(at: blockedRecovery)
        let firstPreserved = try drafts.preserveForRecovery()!
        let firstPreservedBytes = try Data(contentsOf: firstPreserved)
        precondition(firstPreservedBytes == damagedBytes, "Recovery changed the source bytes")
        precondition(!FileManager.default.fileExists(atPath: draftURL.path))
        if let _ = try drafts.load() { preconditionFailure("Preserved draft was still offered for recovery") }
        try damagedBytes.write(to: draftURL, options: .atomic)
        let secondPreserved = try drafts.preserveForRecovery()!
        let firstAfterSecondPreservation = try Data(contentsOf: firstPreserved)
        let secondPreservedBytes = try Data(contentsOf: secondPreserved)
        precondition(firstPreserved != secondPreserved && firstAfterSecondPreservation == damagedBytes)
        precondition(secondPreservedBytes == damagedBytes)
        let proof: [String: Any] = ["sourceRecords": histories.count,
            "unknownVolumeRecordsPreserved": histories.filter { $0.totalWeight == nil }.count,
            "replayAndRelaunchPreserved": true, "sourceFieldsPreserved": true,
            "mondayWeekBoundsPassed": true, "unreadableDraftPreservedExactly": true,
            "draftPreservationFailureKeptOriginal": true, "draftRecoveryPathsUnique": true,
            "deviceOrHealthStoreAccessed": false]
        let sourceAfter = try Data(contentsOf: source)
        precondition(sourceAfter == sourceBytes, "Original export changed")
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]))
    }
}
