import Foundation

enum WorkoutSync {
    static let reportFileKind = "gymcount.workouts.file.v2"
    static let maximumReportFileBytes = 4 * 1024 * 1024
    static let batchKind = "gymcount.workouts.v1"
    static let requestKind = "gymcount.workouts.request.v1"
    static let receiptKind = "gymcount.workouts.receipt.v1"
    static let maximumBatchSize = 40
    static let maximumPayloadBytes = 48 * 1024
    static let exerciseCapabilityKey = "supported_exercises"
    static let legacyExercises: Set<String> = ["bench_press", "squat", "deadlift"]

    static func supportedExercises(in request: [String: Any]) -> Set<String> {
        guard let names = request[exerciseCapabilityKey] as? [String], names.count <= 100 else { return legacyExercises }
        return Set(names).intersection(ExerciseType.allCases.map(\.rawValue))
    }

    static func supports(_ workout: WorkoutHistory, exercises: Set<String>) -> Bool {
        exercises.contains(workout.exerciseType.rawValue) &&
            (workout.workoutReport?.sets.allSatisfy { exercises.contains($0.exercise.rawValue) } ?? true)
    }

    struct Record: Codable, Equatable, Identifiable {
        let id: UUID
        let date: Date
        let exercise: String
        let totalReps: Int
        let maxWeight: Double
        let duration: TimeInterval
        var activeDuration: TimeInterval? = nil
        var totalWeight: Double? = nil
        var workoutReport: WorkoutReport? = nil

        var valid: Bool {
            ExerciseType(rawValue: exercise) != nil &&
            date.timeIntervalSinceReferenceDate.isFinite && duration.isFinite && duration >= 0 &&
            maxWeight.isFinite && maxWeight >= 0 && (0...1_000_000).contains(totalReps) &&
            (activeDuration.map { $0.isFinite && $0 >= 0 && $0 <= duration } ?? true) &&
            (totalWeight.map { $0.isFinite && $0 >= 0 } ?? true) && validReport
        }

        private var validReport: Bool {
            guard let report = workoutReport else { return true }
            guard (try? report.validate()) != nil else { return false }
            return report.startedAt == date && report.duration == duration && report.totalReps == totalReps &&
                report.maxWeight == maxWeight && (report.sets.first?.exercise.rawValue ?? exercise) == exercise &&
                (activeDuration == nil || activeDuration == report.activeDuration) &&
                (totalWeight == nil || totalWeight == report.totalWeight)
        }

        func sameSource(as other: Record) -> Bool {
            id == other.id && date == other.date && exercise == other.exercise &&
            totalReps == other.totalReps && maxWeight == other.maxWeight && duration == other.duration
        }
    }

    static func decode(_ message: [String: Any]) throws -> [Record] {
        let kind = message["kind"] as? String
        guard kind == batchKind || kind == reportFileKind,
              let data = message["payload"] as? Data, data.count <= (kind == reportFileKind ? maximumReportFileBytes : maximumPayloadBytes) else {
            throw Failure.invalidPayload
        }
        let records = try JSONDecoder().decode([Record].self, from: data)
        guard !records.isEmpty, records.count <= maximumBatchSize,
              records.allSatisfy(\.valid), Set(records.map(\.id)).count == records.count else {
            throw Failure.invalidPayload
        }
        return records
    }

    static func message(_ records: [Record], asFile: Bool = false) throws -> [String: Any] {
        let data = try JSONEncoder().encode(records)
        let message: [String: Any] = ["kind": asFile ? reportFileKind : batchKind, "payload": data,
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
            if let index = next.records.firstIndex(where: { $0.id == record.id }) {
                let existing = next.records[index]
                guard existing.sameSource(as: record),
                      existing.activeDuration == nil || record.activeDuration == nil ||
                      existing.activeDuration == record.activeDuration,
                      existing.totalWeight == nil || record.totalWeight == nil ||
                      existing.totalWeight == record.totalWeight,
                      existing.workoutReport == nil || record.workoutReport == nil || existing.workoutReport == record.workoutReport else { throw WorkoutSync.Failure.conflictingRecord }
                var merged = existing
                if merged.activeDuration == nil { merged.activeDuration = record.activeDuration }
                if merged.totalWeight == nil { merged.totalWeight = record.totalWeight }
                if merged.workoutReport == nil { merged.workoutReport = record.workoutReport }
                next.records[index] = merged
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

// Sensor time is relative to the first accelerometer sample. `origin` is only
// present when that sample's wall-clock anchor was actually retained.
struct WorkoutTimeline: Codable, Equatable, Identifiable {
    static let fileKind = "gymcount.timeline.v1"
    static let receiptKind = "gymcount.timeline.receipt.v1"
    static let maximumFileBytes = 16 * 1024 * 1024
    static let maximumSamples = 19_200
    static let maximumEvents = 500

    struct Vector: Codable, Equatable {
        let x: Double
        let y: Double
        let z: Double
        fileprivate var valid: Bool { [x, y, z].allSatisfy { $0.isFinite && abs($0) <= 1_000_000_000 } }
    }
    struct VectorSample: Codable, Equatable {
        let t: Double
        let x: Double
        let y: Double
        let z: Double
        fileprivate var valid: Bool { Vector(x: x, y: y, z: z).valid }
    }
    struct MotionSample: Codable, Equatable {
        let t: Double
        let gravity: Vector
        let userAcceleration: Vector
        let rotationRate: Vector
        let attitude: Vector
        let magneticField: Vector?
        fileprivate var valid: Bool {
            gravity.valid && userAcceleration.valid && rotationRate.valid && attitude.valid &&
            (magneticField?.valid ?? true)
        }
    }

    var version = 1
    var source: WorkoutSync.Record
    var origin: Date?
    var acceleration: [VectorSample]
    var motion: [MotionSample]
    var detectedEvents: [Double]
    var feedbackEvents: [Double]?
    var referenceEvents: [Double]?
    var algorithmVersion: String?
    var isPartial: Bool
    var id: UUID { source.id }
    var duration: Double {
        [acceleration.last?.t, motion.last?.t, detectedEvents.last,
         feedbackEvents?.last, referenceEvents?.last].compactMap { $0 }.max() ?? 0
    }

    var estimatedActiveDuration: TimeInterval? {
        if let known = source.activeDuration { return known }
        let samples = motion.map { sample in
            BenchMotionSample(t: sample.t,
                gravity: BenchVector(x: sample.gravity.x, y: sample.gravity.y, z: sample.gravity.z),
                user_acceleration: BenchVector(x: sample.userAcceleration.x, y: sample.userAcceleration.y, z: sample.userAcceleration.z),
                rotation_rate: BenchVector(x: sample.rotationRate.x, y: sample.rotationRate.y, z: sample.rotationRate.z))
        }
        guard let measured = ActionTiming.estimated(exercise: source.exercise, samples: samples,
            expectedCount: source.totalReps, events: detectedEvents), measured <= source.duration else { return nil }
        return measured
    }

    enum Failure: Error { case invalid, unsupported, conflicting }

    init(captureData: Data, source: WorkoutSync.Record, origin: Date? = nil) throws {
        struct Capture: Decodable {
            struct Motion: Decodable {
                let t: Double
                let gravity: Vector
                let user_acceleration: Vector
                let rotation_rate: Vector
                let attitude: Vector
                let magnetic_field: Vector?
                let magnetic_field_accuracy: Int?
            }
            let schema_version: Int?
            let session_id: UUID
            let started_at: String
            let exercise: String
            let duration_seconds: Double
            let samples: [VectorSample]
            let motion_samples: [Motion]?
            let detected_events: [Double]
            let feedback_events: [Double]?
            let reference_events: [Double]?
            let algorithm_version: String?
            let reference_events_truncated: Bool?
            let acceleration_unit: String?
            let rotation_unit: String?
            let attitude_unit: String?
        }
        guard captureData.count <= Self.maximumFileBytes else { throw Failure.invalid }
        let raw = try JSONDecoder().decode(Capture.self, from: captureData)
        guard raw.schema_version == nil || raw.schema_version == 1 || raw.schema_version == 2 else { throw Failure.unsupported }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard raw.session_id == source.id, raw.exercise == source.exercise,
              let started = fractional.date(from: raw.started_at) ?? ISO8601DateFormatter().date(from: raw.started_at),
              abs(started.timeIntervalSince(source.date)) <= 1.01,
              raw.duration_seconds.isFinite, raw.duration_seconds >= 0,
              raw.acceleration_unit == nil || raw.acceleration_unit == "g",
              raw.rotation_unit == nil || raw.rotation_unit == "rad/s",
              raw.attitude_unit == nil || raw.attitude_unit == "rad" else { throw Failure.invalid }
        guard raw.samples.count <= Self.maximumSamples,
              (raw.motion_samples?.count ?? 0) <= Self.maximumSamples else { throw Failure.invalid }
        let motion = (raw.motion_samples ?? []).map {
            MotionSample(t: $0.t, gravity: $0.gravity, userAcceleration: $0.user_acceleration,
                         rotationRate: $0.rotation_rate, attitude: $0.attitude,
                         magneticField: ($0.magnetic_field_accuracy ?? -1) >= 0 ? $0.magnetic_field : nil)
        }
        try self.init(source: source, origin: origin, acceleration: raw.samples, motion: motion,
                      detectedEvents: raw.detected_events, feedbackEvents: raw.feedback_events,
                      referenceEvents: raw.reference_events, algorithmVersion: raw.algorithm_version,
                      isPartial: raw.reference_events_truncated == true)
        guard duration <= raw.duration_seconds + 1 else { throw Failure.invalid }
    }

    init(source: WorkoutSync.Record, origin: Date?, acceleration: [VectorSample], motion: [MotionSample],
         detectedEvents: [Double], feedbackEvents: [Double]?, referenceEvents: [Double]? = nil,
         algorithmVersion: String?, isPartial: Bool = false) throws {
        self.source = source; self.origin = origin; self.acceleration = acceleration; self.motion = motion
        self.detectedEvents = detectedEvents; self.feedbackEvents = feedbackEvents
        self.referenceEvents = referenceEvents; self.algorithmVersion = algorithmVersion
        let endOffset = origin.map { max(0, $0.timeIntervalSince(source.date)) } ?? 0
        let measuredEnd = max(acceleration.last?.t ?? 0, motion.last?.t ?? 0) + endOffset
        self.isPartial = isPartial || acceleration.count == Self.maximumSamples ||
            motion.count == Self.maximumSamples || endOffset > 1 || source.duration - measuredEnd > 1 ||
            zip(acceleration, acceleration.dropFirst()).contains { $1.t - $0.t > 0.25 } ||
            zip(motion, motion.dropFirst()).contains { $1.t - $0.t > 0.25 }
        try validate()
    }

    func validate() throws {
        guard version == 1 else { throw Failure.unsupported }
        guard source.valid, acceleration.count <= Self.maximumSamples, motion.count <= Self.maximumSamples,
              !acceleration.isEmpty || !motion.isEmpty,
              acceleration.allSatisfy(\.valid), motion.allSatisfy(\.valid),
              (algorithmVersion?.count ?? 0) <= 200,
              Self.validTimes(acceleration.map(\.t), maximum: Self.maximumSamples, end: source.duration + 1),
              Self.validTimes(motion.map(\.t), maximum: Self.maximumSamples, end: source.duration + 1),
              Self.validTimes(detectedEvents, maximum: Self.maximumEvents, end: source.duration + 1),
              feedbackEvents.map({ Self.validTimes($0, maximum: Self.maximumEvents, end: source.duration + 1) }) ?? true,
              referenceEvents.map({ Self.validTimes($0, maximum: Self.maximumEvents, end: source.duration + 1) }) ?? true,
              duration <= source.duration + 1 else { throw Failure.invalid }
        if let origin {
            let offset = origin.timeIntervalSince(source.date)
            guard origin.timeIntervalSince1970.isFinite, offset >= -1, offset <= source.duration + 1,
                  max(0, offset) + duration <= source.duration + 1 else { throw Failure.invalid }
        }
    }

    private static func validTimes(_ times: [Double], maximum: Int, end: Double) -> Bool {
        times.count <= maximum && times.enumerated().allSatisfy { index, value in
            value.isFinite && value >= 0 && value <= min(86_400, end) && (index == 0 || value > times[index - 1])
        }
    }

    func merging(_ other: Self) throws -> Self {
        try validate(); try other.validate()
        guard source.sameSource(as: other.source),
              source.activeDuration == nil || other.source.activeDuration == nil || source.activeDuration == other.source.activeDuration,
              source.totalWeight == nil || other.source.totalWeight == nil || source.totalWeight == other.source.totalWeight,
              origin == nil || other.origin == nil || origin == other.origin,
              acceleration == other.acceleration, motion == other.motion,
              detectedEvents == other.detectedEvents, feedbackEvents == other.feedbackEvents,
              referenceEvents == other.referenceEvents, algorithmVersion == other.algorithmVersion,
              isPartial == other.isPartial || origin == nil || other.origin == nil else { throw Failure.conflicting }
        var merged = self
        if merged.source.activeDuration == nil { merged.source.activeDuration = other.source.activeDuration }
        if merged.source.totalWeight == nil { merged.source.totalWeight = other.source.totalWeight }
        if merged.origin == nil, other.origin != nil { merged.origin = other.origin; merged.isPartial = other.isPartial }
        return merged
    }
}

// Independent from the bounded feedback outbox: unacknowledged workout traces
// survive feedback cleanup, process restarts and a replacement phone receiver.
final class WorkoutTimelineArchive {
    let folder: URL
    init(folder: URL) { self.folder = folder }
    func fileURL(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }

    func load(_ id: UUID) throws -> WorkoutTimeline? {
        let url = fileURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size <= WorkoutTimeline.maximumFileBytes else { throw WorkoutTimeline.Failure.invalid }
        let data = try Data(contentsOf: url)
        guard data.count <= WorkoutTimeline.maximumFileBytes else { throw WorkoutTimeline.Failure.invalid }
        let timeline = try JSONDecoder().decode(WorkoutTimeline.self, from: data)
        try timeline.validate()
        guard timeline.id == id else { throw WorkoutTimeline.Failure.invalid }
        return timeline
    }

    func entries() throws -> [WorkoutTimeline] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> WorkoutTimeline? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                return try load(id)
            }.sorted { $0.source.date > $1.source.date }
    }

    func retain(_ timeline: WorkoutTimeline) throws {
        try timeline.validate()
        let saved = try load(timeline.id)
        let next = try saved.map { try $0.merging(timeline) } ?? timeline
        guard saved != next else { return }
        let data = try JSONEncoder().encode(next)
        guard data.count <= WorkoutTimeline.maximumFileBytes else { throw WorkoutTimeline.Failure.invalid }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(timeline.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ id: UUID) throws {
        let url = fileURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

enum WorkoutReportSensors {
    static let fileKind = "gymcount.report-sensor.v1"
    static let receiptKind = "gymcount.report-sensor.receipt.v1"
    static let capabilityKey = "report_sensors_version"
    static let maximumSegments = 1_000
}

struct WorkoutReportSensorSummary: Identifiable, Equatable {
    let source: WorkoutSync.Record
    let origin: Date?
    var id: UUID { source.id }
}

// Individual sensor blocks keep their original sample clocks and precision.
// A whole workout never pretends that its last block covers the full session.
final class WorkoutReportSensorArchive {
    let folder: URL
    init(folder: URL) { self.folder = folder }
    func fileURL(workoutID: UUID, segmentID: UUID) -> URL {
        folder.appendingPathComponent(workoutID.uuidString).appendingPathComponent(segmentID.uuidString + ".json")
    }
    func load(workoutID: UUID, segmentID: UUID) throws -> WorkoutTimeline? {
        let directory = folder.appendingPathComponent(workoutID.uuidString)
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw WorkoutTimeline.Failure.invalid }
        return try WorkoutTimelineArchive(folder: directory).load(segmentID)
    }
    func index(for source: WorkoutSync.Record) throws -> [WorkoutReportSensorSummary] {
        guard source.valid, source.workoutReport != nil else { throw WorkoutTimeline.Failure.invalid }
        let directory = folder.appendingPathComponent(source.id.uuidString)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw WorkoutTimeline.Failure.invalid }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard files.count <= WorkoutReportSensors.maximumSegments else { throw WorkoutTimeline.Failure.invalid }
        var summaries: [WorkoutReportSensorSummary] = []
        for file in files {
            let summary = try autoreleasepool { () throws -> WorkoutReportSensorSummary in
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      let timeline = try load(workoutID: source.id, segmentID: id) else { throw WorkoutTimeline.Failure.invalid }
                try Self.validate(timeline, for: source)
                return .init(source: timeline.source, origin: timeline.origin)
            }
            summaries.append(summary)
        }
        let sorted = summaries.sorted { $0.source.date == $1.source.date ? $0.id.uuidString < $1.id.uuidString : $0.source.date < $1.source.date }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ left, right in
            right.source.date >= left.source.date.addingTimeInterval(left.source.duration - 0.001)
        }) else { throw WorkoutTimeline.Failure.conflicting }
        return sorted
    }
    func retain(_ timeline: WorkoutTimeline, for source: WorkoutSync.Record) throws {
        try Self.validate(timeline, for: source)
        let existing = try index(for: source)
        guard existing.contains(where: { $0.id == timeline.id }) || existing.count < WorkoutReportSensors.maximumSegments else { throw WorkoutTimeline.Failure.invalid }
        let start = timeline.source.date, end = start.addingTimeInterval(timeline.source.duration)
        guard existing.filter({ $0.id != timeline.id }).allSatisfy({ item in
            let otherEnd = item.source.date.addingTimeInterval(item.source.duration)
            return end <= item.source.date.addingTimeInterval(0.001) || otherEnd <= start.addingTimeInterval(0.001)
        }) else { throw WorkoutTimeline.Failure.conflicting }
        try WorkoutTimelineArchive(folder: folder.appendingPathComponent(source.id.uuidString)).retain(timeline)
    }
    func remove(_ workoutID: UUID) throws {
        let directory = folder.appendingPathComponent(workoutID.uuidString)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    static func validate(_ timeline: WorkoutTimeline, for source: WorkoutSync.Record) throws {
        try timeline.validate()
        guard source.valid, let report = source.workoutReport, timeline.source.workoutReport == nil,
              timeline.source.date >= report.startedAt,
              timeline.source.date.addingTimeInterval(timeline.source.duration) <= report.endedAt.addingTimeInterval(0.001)
        else { throw WorkoutTimeline.Failure.conflicting }
        let end = timeline.source.date.addingTimeInterval(timeline.source.duration)
        let repetitions = report.sets.filter { $0.exercise.rawValue == timeline.source.exercise }.flatMap(\.repetitions)
            .filter { $0.completedAt >= timeline.source.date && $0.completedAt <= end }
        guard repetitions.count == timeline.source.totalReps else { throw WorkoutTimeline.Failure.conflicting }
        if !repetitions.isEmpty {
            guard repetitions.map(\.weight).max() == timeline.source.maxWeight,
                  timeline.source.totalWeight.map({ abs($0 - repetitions.reduce(0) { $0 + $1.weight }) < 0.001 }) ?? true
            else { throw WorkoutTimeline.Failure.conflicting }
        }
    }
}

// One ordered file lane per process. Heavy JSON and atomic writes never need
// the UI executor; app receipts are sent only after this lane completes.
final class WorkoutFileIO: @unchecked Sendable {
    static let shared = WorkoutFileIO()
    private let queue = DispatchQueue(label: "PowerReps.files", qos: .utility)
    func perform<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
