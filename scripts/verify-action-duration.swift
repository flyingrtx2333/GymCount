import Foundation

// Replay original recordings through shipping timing/detector code. Inputs stay
// private and unchanged. The output is a timing consistency check, not video truth.
@main
enum VerifyActionDuration {
    struct Record: Decodable { let id: Int; let recording: Recording }
    struct Recording: Decodable {
        let exercise: String
        let session_id: UUID
        let started_at: String
        let detected_count: Int
        let duration_seconds: Double
        let samples: [Sample]
        let motion_samples: [BenchMotionSample]?
    }
    struct Sample: Decodable { let t: Double; let x: Double; let y: Double; let z: Double }

    @MainActor
    static func main() throws {
        let rows = try JSONDecoder().decode([Record].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var proof: [[String: Any]] = []
        for row in rows {
            let input = row.recording
            let duration: TimeInterval?
            if input.exercise == "bench_press" {
                let analysis = BenchPressAnalysis.analyze(input.motion_samples ?? [])
                duration = analysis.status == "estimated" ? ActionTiming.total(analysis.cycles.map {
                    ActionTiming.Interval(start: $0.start, end: $0.end)
                }) : nil
            } else if input.exercise == "squat" {
                duration = nil // No validated action boundaries; never infer from counts.
            } else { continue }
            if let duration {
                precondition(duration.isFinite && duration >= 0 && duration <= input.duration_seconds)
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = iso.date(from: input.started_at) ?? ISO8601DateFormatter().date(from: input.started_at) else {
                fatalError("Invalid source date")
            }
            // Capture files have no load field. Zero is an unspecified load for
            // this isolated protocol check; no capture becomes a user workout.
            let source = WorkoutSync.Record(id: input.session_id, date: date,
                exercise: input.exercise, totalReps: input.detected_count, maxWeight: 0,
                duration: input.duration_seconds, activeDuration: duration)
            let decoded = try WorkoutSync.decode(WorkoutSync.message([source]))
            precondition(decoded == [source], "Action time was lost in transport encoding")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ActionDurationReplay." + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let journal = try WatchWorkoutArchive(url: folder.appendingPathComponent("history.json"))
            var oldReceiverRecord = source
            oldReceiverRecord.activeDuration = nil
            try journal.accept([oldReceiverRecord])
            try journal.accept([source])
            try journal.accept([oldReceiverRecord])
            precondition(journal.records == [source], "Mixed-version replay lost the enriched metric")
            let reopened = try WatchWorkoutArchive(url: folder.appendingPathComponent("history.json"))
            precondition(reopened.records == [source], "Relaunch lost the action duration")
            let suite = "ActionDurationReplay." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let phone = PhoneWorkoutStore(defaults: defaults, reminderID: suite, watchArchiveURL: folder.appendingPathComponent("phone.json"))
            try phone.acceptWatchHistory([oldReceiverRecord])
            try phone.acceptWatchHistory([source])
            try phone.acceptWatchHistory([oldReceiverRecord])
            precondition(phone.history.count == 1 && phone.history[0].activeDuration == duration)
            proof.append(["id": row.id, "exercise": input.exercise,
                "elapsedSeconds": input.duration_seconds, "actionSeconds": duration.map { $0 as Any } ?? NSNull(),
                "syncRoundTripPassed": true, "mixedVersionEnrichmentPassed": true])
        }
        let output: [String: Any] = ["records": proof, "independentVideoTimingValidated": false]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
