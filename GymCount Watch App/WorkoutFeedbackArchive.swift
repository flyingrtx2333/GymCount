import Foundation

// Local diagnostics are never sent until the user confirms a reference count.
final class WorkoutFeedbackArchive {
    struct Entry: Codable, Identifiable {
        let workout: WorkoutHistory
        var recording: Data?
        var actualCount: Int?
        var serverID: Int?
        var id: UUID { workout.id }
        var pending: Bool { actualCount != nil && serverID == nil }
    }

    enum Failure: Error { case missingSamples, invalidCount, alreadyQueued, invalidResponse }
    let folder: URL
    init(folder: URL) { self.folder = folder }

    func load(_ id: UUID) throws -> Entry {
        try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url(id)))
    }

    func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(Entry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.workout.date > $1.workout.date }
    }

    func retain(_ workout: WorkoutHistory, recording: Data?) throws {
        // Retrying a local workout save must not overwrite an existing submission.
        if FileManager.default.fileExists(atPath: url(workout.id).path) { return }
        try write(Entry(workout: workout, recording: recording))
        // Keep diagnostics bounded; never evict an explicitly submitted pending report.
        var retainedBytes = 0
        for (index, item) in try entries().enumerated() {
            retainedBytes += item.recording?.count ?? 0
            if !item.pending && (index >= 10 || retainedBytes > 48 * 1024 * 1024) {
                try FileManager.default.removeItem(at: url(item.id))
            }
        }
    }

    func prepare(_ id: UUID, actual: Int) throws -> Entry {
        guard (0...500).contains(actual) else { throw Failure.invalidCount }
        var entry = try load(id)
        if entry.actualCount != nil {
            guard entry.actualCount == actual else { throw Failure.alreadyQueued }
            return entry
        }
        guard let data = entry.recording,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.missingSamples
        }
        body["actual_count"] = actual
        entry.recording = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        entry.actualCount = actual
        try write(entry) // Durable outbox before any network request.
        return entry
    }

    func acknowledge(_ entry: Entry, response: Data) throws {
        struct Receipt: Decodable { let id: Int; let session_id: UUID }
        let receipt = try JSONDecoder().decode(Receipt.self, from: response)
        guard receipt.id > 0, receipt.session_id == entry.id else { throw Failure.invalidResponse }
        var saved = entry
        saved.serverID = receipt.id
        try write(saved)
    }

    func remove(_ id: UUID) throws {
        let path = url(id)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    private func url(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }
    private func write(_ entry: Entry) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: url(entry.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
