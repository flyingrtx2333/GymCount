import Foundation

enum WorkoutSync {
    static let batchKind = "gymcount.workouts.v1"
    static let requestKind = "gymcount.workouts.request.v1"
    static let receiptKind = "gymcount.workouts.receipt.v1"
    static let maximumBatchSize = 40
    static let maximumPayloadBytes = 48 * 1024

    struct Record: Codable, Equatable, Identifiable {
        let id: UUID
        let date: Date
        let exercise: String
        let totalReps: Int
        let maxWeight: Double
        let duration: TimeInterval

        var valid: Bool {
            ["bench_press", "squat", "deadlift"].contains(exercise) &&
            date.timeIntervalSinceReferenceDate.isFinite && duration.isFinite && duration >= 0 &&
            maxWeight.isFinite && maxWeight >= 0 && (0...1_000_000).contains(totalReps)
        }
    }

    static func decode(_ message: [String: Any]) throws -> [Record] {
        guard message["kind"] as? String == batchKind,
              let data = message["payload"] as? Data, data.count <= maximumPayloadBytes else {
            throw Failure.invalidPayload
        }
        let records = try JSONDecoder().decode([Record].self, from: data)
        guard !records.isEmpty, records.count <= maximumBatchSize,
              records.allSatisfy(\.valid), Set(records.map(\.id)).count == records.count else {
            throw Failure.invalidPayload
        }
        return records
    }

    static func message(_ records: [Record]) throws -> [String: Any] {
        let data = try JSONEncoder().encode(records)
        let message: [String: Any] = ["kind": batchKind, "payload": data,
                                      "ids": records.map { $0.id.uuidString }]
        _ = try decode(message)
        return message
    }

    static func ids(_ message: [String: Any]) -> Set<UUID> {
        Set((message["ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
    }

    enum Failure: Error { case invalidPayload, conflictingRecord }
}

// A separate atomic journal is saved before acknowledging the Watch. If the
// process exits before UserDefaults is flushed, the next launch restores these
// records. Phone deletions are durable tombstones, so retries cannot resurrect them.
final class WatchWorkoutArchive {
    private struct State: Codable {
        var records: [WorkoutSync.Record] = []
        var deletedIDs: Set<UUID> = []
    }
    private let url: URL
    private var state: State
    var records: [WorkoutSync.Record] { state.records.filter { !state.deletedIDs.contains($0.id) } }
    var deletedIDs: Set<UUID> { state.deletedIDs }

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard state.records.allSatisfy(\.valid), Set(state.records.map(\.id)).count == state.records.count else {
                throw WorkoutSync.Failure.invalidPayload
            }
        } else { state = State() }
    }

    func accept(_ records: [WorkoutSync.Record]) throws {
        guard records.allSatisfy(\.valid) else { throw WorkoutSync.Failure.invalidPayload }
        var next = state
        for record in records {
            if next.deletedIDs.contains(record.id) { continue }
            if let existing = next.records.first(where: { $0.id == record.id }) {
                guard existing == record else { throw WorkoutSync.Failure.conflictingRecord }
            } else { next.records.append(record) }
        }
        try persist(next)
    }

    func remove(_ ids: Set<UUID>) throws {
        var next = state
        next.deletedIDs.formUnion(ids)
        next.records.removeAll { ids.contains($0.id) }
        try persist(next)
    }

    private func persist(_ next: State) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next
    }
}
