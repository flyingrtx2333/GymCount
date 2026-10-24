import Foundation
import SwiftUI
import WatchKit

final class WorkoutDiagnostics {
    let raw = RawCapture()

    func recording(for workout: WorkoutHistory) throws -> Data? {
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
        let record = CaptureRecord(session_id: workout.id, started_at: workout.date,
            exercise: kind.rawValue, actual_count: 0, detected_count: snapshot.events.count,
            duration_seconds: duration, wrist: WKInterfaceDevice.current().wristLocation == .left ? "left" : "right",
            watch_crown: WKInterfaceDevice.current().crownOrientation == .left ? "left" : "right", pace: "normal",
            watch_model: WKInterfaceDevice.current().model, os_version: WKInterfaceDevice.current().systemVersion,
            app_version: "\(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            algorithm_version: kind == .benchPress ? BenchAnalysis.version : kind == .squat ? SquatStream.version : "rules-20261007",
            participant_id: participant,
            notes: "workout_feedback; workout_id=\(workout.id.uuidString); displayed_count=\(workout.totalReps); weight_kg=\(workout.maxWeight)",
            samples: snapshot.points, gyroscope_samples: [], motion_samples: motion, magnetometer_samples: [],
            sensor_availability: CaptureAvailability(gyroscope: false, device_motion: !motion.isEmpty, magnetometer: false),
            detected_events: snapshot.events,
            feedback_events: kind == .deadlift ? nil : raw.recordedFeedback,
            feedback_algorithm_version: kind == .benchPress ? BenchPressFeedback.version : kind == .squat ? SquatStream.version : nil,
            reference_events_truncated: snapshot.eventsTruncated)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        return data.count <= 16 * 1024 * 1024 ? data : nil
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
            let entry = try archive.prepare(id, actual: actual)
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
            try archive.acknowledge(entry, response: data)
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
