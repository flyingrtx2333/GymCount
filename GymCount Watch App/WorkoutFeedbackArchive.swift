import Foundation

// Local diagnostics are never sent until the user confirms a reference count.
final class WorkoutFeedbackArchive {
    struct Entry: Codable, Identifiable {
        let workout: WorkoutHistory
        var recording: Data?
        var recordingBytes: Int? = nil
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

    private struct Header: Decodable {
        let workout: WorkoutHistory
        let recordingBytes: Int?
        let actualCount: Int?
        let serverID: Int?
    }

    private func prune() throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        // Header decoding skips the base64 sample body; retain only small metadata.
        let headers = try files.map { url -> (URL, Header, Int) in
            try autoreleasepool {
            let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: url))
            let bytes: Int
            if let known = header.recordingBytes, (0...(16 * 1024 * 1024)).contains(known) { bytes = known }
            else {
                let legacy = try load(header.workout.id)
                bytes = legacy.recording?.count ?? 0
                try write(legacy)
            }
            return (url, header, bytes)
            }
        }.sorted { $0.1.workout.date > $1.1.workout.date }
        var bytes = 0
        for (index, item) in headers.enumerated() {
            bytes += item.2
            let pending = item.1.actualCount != nil && item.1.serverID == nil
            if !pending && (index >= 10 || bytes > 48 * 1024 * 1024) {
                try FileManager.default.removeItem(at: item.0)
            }
        }
    }

    func retain(_ workout: WorkoutHistory, recording: Data?, prune: Bool = true) throws {
        // Retrying a local workout save must not overwrite an existing submission.
        if FileManager.default.fileExists(atPath: url(workout.id).path) { return }
        try write(Entry(workout: workout, recording: recording))
        guard prune else { return }
        try self.prune()
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
        var entry = entry
        entry.recordingBytes = entry.recording?.count ?? 0
        try JSONEncoder().encode(entry).write(to: url(entry.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
