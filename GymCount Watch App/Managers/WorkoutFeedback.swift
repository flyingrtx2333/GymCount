import Foundation
import SwiftUI
import WatchKit

final class WorkoutDiagnostics {
    let raw = RawCapture()

    private let encodedPoints = SampleBlocks()
    private let encodedMotion = SampleBlocks()

    init(prepareTimeline: Bool = false) {
        if prepareTimeline {
            raw.completedAccelerationBlock = { [encodedPoints] block in
                encodedPoints.prepare(block, convert: WorkoutDiagnostics.point)
            }
            raw.completedMotionBlock = { [encodedMotion] block in
                encodedMotion.prepare(block, convert: WorkoutDiagnostics.motion)
            }
        }
    }

    private static func point(_ sample: CaptureSample) -> WorkoutTimeline.VectorSample {
        .init(t: sample.t, x: sample.x, y: sample.y, z: sample.z)
    }

    private static func motion(_ sample: CaptureMotion) -> WorkoutTimeline.MotionSample {
        func vector(_ value: CaptureVector) -> WorkoutTimeline.Vector {
            .init(x: value.x, y: value.y, z: value.z)
        }
        return .init(t: sample.t, gravity: vector(sample.gravity),
            userAcceleration: vector(sample.user_acceleration), rotationRate: vector(sample.rotation_rate),
            attitude: vector(sample.attitude), magneticField: sample.magnetic_field_accuracy >= 0 ? vector(sample.magnetic_field) : nil)
    }

    func encodedTimeline(_ timeline: WorkoutTimeline) throws -> Data {
        // The metadata still uses the shipping Codable schema. Splice the two
        // numeric arrays as their original JSON bytes (no NSNumber conversion).
        var header = timeline
        header.motion = []
        header.acceleration = []
        let json = try JSONEncoder().encode(header)
        guard var fields = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw WorkoutTimeline.Failure.invalid
        }
        fields.removeValue(forKey: "motion")
        fields.removeValue(forKey: "acceleration")
        var output = try JSONSerialization.data(withJSONObject: fields)
        output.removeLast() // closing brace of the compact metadata object
        output.append(contentsOf: #","motion":["#.utf8)
        try encodedMotion.appendElements(timeline.motion, to: &output)
        output.append(contentsOf: #"],"acceleration":["#.utf8)
        try encodedPoints.appendElements(timeline.acceleration, to: &output)
        output.append(contentsOf: "]}".utf8)
        return output
    }

    func recording(for workout: WorkoutHistory) throws -> Data? {
        guard let record = record(for: workout) else { return nil }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        return data.count <= 16 * 1024 * 1024 ? data : nil
    }

    func timeline(for workout: WorkoutHistory, trimToDuration: Bool = false) throws -> WorkoutTimeline? {
        let snapshot = raw.snapshot()
        let origin = raw.originWallTime.map { Date(timeIntervalSince1970: $0) }
        let offset = origin?.timeIntervalSince(workout.date) ?? 0
        let cutoff = trimToDuration ? workout.duration - max(0, offset) : .infinity
        let points = snapshot.points.prefix { $0.t <= cutoff }
        guard points.count >= 2 else { return nil }
        let source = WorkoutSync.Record(id: workout.id, date: workout.date, exercise: workout.exerciseType.rawValue,
            totalReps: workout.totalReps, maxWeight: workout.maxWeight, duration: workout.duration,
            activeDuration: workout.activeDuration, totalWeight: workout.totalWeight)
        return try WorkoutTimeline(source: source, origin: origin,
            acceleration: points.map(Self.point),
            motion: snapshot.motion.prefix { $0.t <= cutoff }.map(Self.motion),
            detectedEvents: snapshot.events.filter { $0 <= cutoff },
            feedbackEvents: workout.exerciseType == .deadlift ? nil : raw.recordedFeedback.filter { $0 <= cutoff },
            algorithmVersion: workout.exerciseType.countingAlgorithmVersion,
            isPartial: snapshot.eventsTruncated)
    }

    private func record(for workout: WorkoutHistory) -> CaptureRecord? {
        let snapshot = raw.snapshot()
        // The existing capture API accepts full sets up to ten minutes. Never
        // present a truncated sample window as a complete training record.
        let duration = max(workout.duration, snapshot.points.last?.t ?? 0,
                           snapshot.motion.last?.t ?? 0, snapshot.events.last ?? 0,
                           raw.recordedFeedback.last ?? 0)
        guard snapshot.points.count >= 2, snapshot.points.count < 19200,
              duration > 0, duration <= 600, snapshot.events.count <= 500 else { return nil }
        let defaults = UserDefaults.standard
        let participant = defaults.string(forKey: "captureParticipantID").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(participant.uuidString, forKey: "captureParticipantID")
        let info = Bundle.main.infoDictionary ?? [:]
        let kind = workout.exerciseType
        let motion = snapshot.motion.count >= 2 ? snapshot.motion : []
        return CaptureRecord(session_id: workout.id, started_at: workout.date,
            exercise: kind.rawValue, actual_count: 0, detected_count: snapshot.events.count,
            duration_seconds: duration, wrist: WKInterfaceDevice.current().wristLocation == .left ? "left" : "right",
            watch_crown: WKInterfaceDevice.current().crownOrientation == .left ? "left" : "right", pace: "normal",
            watch_model: WKInterfaceDevice.current().model, os_version: WKInterfaceDevice.current().systemVersion,
            app_version: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            algorithm_version: kind.countingAlgorithmVersion,
            participant_id: participant,
            notes: "workout_feedback; workout_id=\(workout.id.uuidString); displayed_count=\(workout.totalReps); weight_kg=\(workout.maxWeight)",
            samples: snapshot.points, gyroscope_samples: [], motion_samples: motion, magnetometer_samples: [],
            sensor_availability: CaptureAvailability(gyroscope: false, device_motion: !motion.isEmpty, magnetometer: false),
            detected_events: snapshot.events,
            feedback_events: kind == .deadlift ? nil : raw.recordedFeedback,
            feedback_algorithm_version: kind.completionFeedbackVersion,
            reference_events_truncated: snapshot.eventsTruncated)
    }
}

// Each instance belongs to one append-only sensor stream. Only completed
// blocks are reused. A trimmed or unfinished block is encoded from the snapshot.
private final class SampleBlocks: @unchecked Sendable {
    private let worker = DispatchQueue(label: "PowerReps.sampleEncoding", qos: .utility)
    private let lock = NSLock()
    private var blocks: [Int: Data] = [:]

    func prepare<Input, Output: Encodable>(_ slice: ArraySlice<Input>, convert: @escaping (Input) -> Output) {
        let start = slice.startIndex
        let samples = Array(slice)
        worker.async { [weak self] in
            guard let self, let data = try? JSONEncoder().encode(samples.map(convert)) else { return }
            self.lock.withLock { self.blocks[start] = data }
        }
    }

    func appendElements<T: Encodable>(_ samples: [T], to output: inout Data) throws {
        let available = lock.withLock { blocks }
        for start in stride(from: 0, to: samples.count, by: 256) {
            let end = min(start + 256, samples.count)
            let cached = end - start == 256 ? available[start] : nil
            let data = try cached ?? JSONEncoder().encode(Array(samples[start..<end]))
            if start > 0 { output.append(0x2c) }
            output.append(data.dropFirst().dropLast())
        }
    }
}

@MainActor
final class WorkoutFeedbackStore: ObservableObject {
    static let shared = WorkoutFeedbackStore()
    let archive: WorkoutFeedbackArchive
    @Published private(set) var uploadingID: UUID?
    @Published private(set) var revision = 0
    @Published private(set) var errorMessage: String?
    private(set) var errorID: UUID?
    private let send: (URLRequest) async throws -> (Data, URLResponse)

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkoutFeedback"),
         send: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        archive = WorkoutFeedbackArchive(folder: folder)
        self.send = send
    }

    func upload(_ id: UUID, actual: Int) async {
        guard uploadingID == nil else { return }
        errorMessage = nil; errorID = id; uploadingID = id
        defer { uploadingID = nil; revision += 1 }
        do {
            let archive = self.archive
            let entry = try await WorkoutFileIO.shared.perform { try archive.prepare(id, actual: actual) }
            if entry.serverID != nil { return }
            var request = URLRequest(url: URL(string: "https://api.flyingrtx.com/api/v1/gymcount/sessions")!)
            request.httpMethod = "POST"; request.timeoutInterval = 45
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = entry.recording
            let (data, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else { throw WorkoutFeedbackArchive.Failure.invalidResponse }
            guard http.statusCode == 201 else {
                switch http.statusCode {
                case 409: errorMessage = String(localized: "反馈内容冲突，请保留记录并联系支持")
                case 422: errorMessage = String(localized: "采样未通过校验，反馈已保留")
                case 429: errorMessage = String(localized: "提交频繁，请稍后重试")
                default: errorMessage = String(localized: "上传失败（\(http.statusCode)），请重试")
                }
                WKInterfaceDevice.current().play(.failure)
                return
            }
            try await WorkoutFileIO.shared.perform { try archive.acknowledge(entry, response: data) }
            WKInterfaceDevice.current().play(.success)
        } catch {
            if let failure = error as? URLError {
                errorMessage = failure.code == .timedOut ? String(localized: "上传超时，请重试") : String(localized: "连接失败，请联网后重试")
            } else {
                errorMessage = String(localized: "反馈未完成，数据已保留，请重试")
            }
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func clearError() { errorMessage = nil }
}
