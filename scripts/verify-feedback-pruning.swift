import Foundation

// Retain real summaries around an actual pending capture. No samples or UUIDs
// are fabricated; only isolated copies are rewritten into the legacy format.
@main enum VerifyFeedbackPruning {
    static func main() throws {
        let legacyURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let historyURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let original = try Data(contentsOf: legacyURL)
        var legacy = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        legacy.removeValue(forKey: "recordingBytes")
        let entry = try JSONDecoder().decode(WorkoutFeedbackArchive.Entry.self, from: original)
        precondition(entry.pending && entry.recording != nil)
        let history = try JSONDecoder().decode([WorkoutHistory].self, from: Data(contentsOf: historyURL))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PowerReps.Pruning." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent(entry.id.uuidString + ".json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: path)
        let archive = WorkoutFeedbackArchive(folder: root)
        for item in history.filter({ $0.id != entry.id }).prefix(16) { try archive.retain(item, recording: nil) }
        let saved = try archive.load(entry.id)
        precondition(saved.pending && saved.recording == entry.recording && saved.actualCount == entry.actualCount)
        precondition(saved.recordingBytes == entry.recording!.count)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        precondition(files.count <= 11)
        let retried = try archive.prepare(entry.id, actual: entry.actualCount!)
        precondition(retried.recording == entry.recording)
        let after = try Data(contentsOf: legacyURL)
        precondition(after == original)
        print("Legacy real feedback metadata migrated; pending bytes/count preserved; pruning and retry passed")
    }
}
