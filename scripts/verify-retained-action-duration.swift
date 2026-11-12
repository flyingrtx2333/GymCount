import Foundation

// Read-only replay of retained real timelines. No motion or completion events
// are generated, and unavailable duration is never replaced by elapsed time.
@main
enum VerifyRetainedActionDuration {
    @MainActor static func main() throws {
        func check(_ value: Bool) { precondition(value) }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "PowerReps.Duration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func store(_ name: String) -> PhoneWorkoutStore {
            PhoneWorkoutStore(defaults: defaults, reminderID: suite,
                watchArchiveURL: root.appendingPathComponent(name + "/history.json"),
                snapshotURL: root.appendingPathComponent(name + "/records-v3.json"))
        }
        var report: [[String: Any]] = []
        var measuredCount = 0
        var replayedCycles = 0
        for file in files {
            let bytes = try Data(contentsOf: file)
            let trace = try JSONDecoder().decode(WorkoutTimeline.self, from: bytes)
            let source = trace.source
            let measured = trace.estimatedActiveDuration
            let samples = trace.motion.map { s in
                BenchMotionSample(t: s.t, gravity: BenchVector(x: s.gravity.x, y: s.gravity.y, z: s.gravity.z),
                    user_acceleration: BenchVector(x: s.userAcceleration.x, y: s.userAcceleration.y, z: s.userAcceleration.z),
                    rotation_rate: BenchVector(x: s.rotationRate.x, y: s.rotationRate.y, z: s.rotationRate.z))
            }
            let intervals: [ActionTiming.Interval]
            if source.exercise == "squat" {
                let detector = SquatStream()
                intervals = samples.compactMap { detector.append($0) }.map { .init(start: $0.start, end: $0.end) }
            } else {
                intervals = BenchPressAnalysis.analyze(samples).cycles.map { .init(start: $0.start, end: $0.end) }
            }
            replayedCycles += intervals.count
            let replayed = ActionTiming.total(intervals)!
            precondition(replayed >= 0 && replayed <= source.duration)
            if !intervals.isEmpty {
                // This is the current detector's real replay output, distinct
                // from the old summary. Verify the same measured metadata path
                // used by live Watch saves, without altering the source file.
                let current = WorkoutSync.Record(id: source.id, date: source.date, exercise: source.exercise,
                    totalReps: intervals.count, maxWeight: source.maxWeight,
                    duration: source.duration, activeDuration: replayed)
                check(try WorkoutSync.decode(WorkoutSync.message([current])) == [current])
                let live = store(nameForReplay(source.id))
                try live.acceptWatchHistory([current])
                var mixedVersion = current; mixedVersion.activeDuration = nil
                try live.acceptWatchHistory([mixedVersion])
                precondition(store(nameForReplay(source.id)).history[0].activeDuration == replayed)
            }
            if let measured { precondition(measured >= 0 && measured <= source.duration); measuredCount += 1 }
            let name = source.id.uuidString
            let phone = store(name)
            check(try phone.acceptWatchTimeline(trace))
            precondition(phone.history.isEmpty)
            try phone.acceptWatchHistory([source])
            precondition(phone.history[0].displayDuration == measured)
            precondition(phone.history[0].duration == source.duration)
            precondition(phone.history[0].activeDuration == measured)
            let reopened = store(name)
            precondition(reopened.history[0].activeDuration == measured)
            try reopened.acceptWatchHistory([source])
            precondition(reopened.history[0].activeDuration == measured)
            let backup = try reopened.backupData()
            let restored = store(name + "-restore")
            try restored.restore(restored.previewRestore(backup))
            precondition(restored.history[0].activeDuration == measured)
            precondition(restored.updateRecord(id: source.id, date: source.date, sets: [], duration: nil,
                summaryReps: source.totalReps + 1, summaryWeight: source.maxWeight))
            try restored.acceptWatchHistory([source])
            precondition(restored.history[0].activeDuration == nil)
            precondition(restored.history[0].displayDuration == nil)
            precondition(restored.history[0].duration == source.duration)
            precondition(restored.deleteRecords(ids: [source.id]))
            try restored.acceptWatchHistory([source])
            check(try !restored.acceptWatchTimeline(trace))
            precondition(restored.history.isEmpty)
            check(try Data(contentsOf: file) == bytes)
            report.append(["id": name, "exercise": source.exercise, "reps": source.totalReps,
                "elapsed": source.duration, "active": measured.map { $0 as Any } ?? NSNull(),
                "currentDetectorCycles": intervals.count, "replayedActionSeconds": replayed])
        }
        precondition(!files.isEmpty && replayedCycles > 0)
        let result: [String: Any] = ["records": report, "measured": measuredCount,
            "replayedCycles": replayedCycles, "fileFirstRestartReplayCorrectionBackupDeletionPassed": true,
            "mismatchedOldEventsNeverInventDuration": true, "originalsUnchanged": true]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
    private static func nameForReplay(_ id: UUID) -> String { id.uuidString + "-current-detector" }
}
