import Foundation

// Use an existing private capture export. No sensor data is synthesized or sent.
@main struct VerifyWorkoutFeedback {
    static func check(_ value: Bool) { precondition(value) }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Pass a real capture JSON and output folder") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        var body = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
        for key in ["original_actual_count", "label_history", "server_id", "input_sha256", "cloud_analysis", "video"] { body.removeValue(forKey: key) }
        let id = UUID(uuidString: body["session_id"] as! String)!
        let originalActual = body["actual_count"] as! Int
        let workout = WorkoutHistory(id: id, date: ISO8601DateFormatter().date(from: body["started_at"] as! String)!,
            exerciseType: ExerciseType(rawValue: body["exercise"] as! String)!, totalReps: body["detected_count"] as! Int,
            maxWeight: 0, duration: body["duration_seconds"] as! Double)
        let store = WorkoutFeedbackArchive(folder: folder.appendingPathComponent("outbox"))
        try store.retain(workout, recording: JSONSerialization.data(withJSONObject: body))
        check(try store.load(id).actualCount == nil)
        let entry = try store.prepare(id, actual: originalActual)
        precondition(entry.pending)
        let reopened = WorkoutFeedbackArchive(folder: store.folder)
        let retry = try reopened.prepare(id, actual: originalActual)
        precondition(entry.recording == retry.recording)
        do { _ = try reopened.prepare(id, actual: originalActual == 500 ? 499 : originalActual + 1); fatalError("Changed retry body accepted") }
        catch WorkoutFeedbackArchive.Failure.alreadyQueued {}
        try store.retain(workout, recording: nil)
        check(try store.load(id).recording == entry.recording)
        do { _ = try store.prepare(id, actual: -1); fatalError("Invalid actual count accepted") }
        catch WorkoutFeedbackArchive.Failure.invalidCount {}
        do { try store.acknowledge(entry, response: Data("{}".utf8)); fatalError("Bad receipt accepted") }
        catch { check(try store.load(id).pending) }
        // A real filesystem failure must leave the previous on-disk outbox intact.
        let blocked = folder.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        do { try WorkoutFeedbackArchive(folder: blocked).retain(workout, recording: entry.recording); fatalError("Failed write accepted") }
        catch { check(try store.load(id).recording == entry.recording) }
        try entry.recording!.write(to: folder.appendingPathComponent("feedback-payload.json"))
        let proof: [String: Any] = ["source": source.lastPathComponent, "sampleCount": (body["samples"] as! [Any]).count,
            "explicitConfirmationRequired": true, "queueSurvivesRestart": true, "retryBodyUnchanged": true,
            "invalidCountRejected": true, "invalidReceiptRejected": true, "failedWritePreserved": true,
            "networkUploadTested": false]
        try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("verification.json"))
        print("Real capture outbox verification passed")
    }
}
