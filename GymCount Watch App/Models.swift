//
//  Models.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
#if os(watchOS) || os(iOS)
import HealthKit
#endif

// MARK: - 锻炼类型枚举
enum ExerciseType: String, CaseIterable, Codable {
    case benchPress = "bench_press"
    case squat = "squat"
    case deadlift = "deadlift"
    case overheadPress = "overhead_press"
    case barbellRow = "barbell_row"
    case bicepCurl = "bicep_curl"
    
    var displayName: String {
        switch self {
        case .benchPress:
            return NSLocalizedString("bench_press", comment: "卧推")
        case .squat:
            return NSLocalizedString("squat", comment: "深蹲")
        case .deadlift:
            return NSLocalizedString("deadlift", comment: "硬拉")
        case .overheadPress:
            return NSLocalizedString("overhead_press", comment: "肩上推举")
        case .barbellRow:
            return NSLocalizedString("barbell_row", comment: "杠铃划船")
        case .bicepCurl:
            return NSLocalizedString("bicep_curl", comment: "哑铃弯举")
        }
    }
    
    var icon: String {
        switch self {
        case .benchPress:
            return "Exercise-bench_press"
        case .squat:
            return "Exercise-squat"
        case .deadlift:
            return "Exercise-deadlift"
        case .overheadPress:
            return "Exercise-overhead_press"
        case .barbellRow:
            return "Exercise-barbell_row"
        case .bicepCurl:
            return "Exercise-bicep_curl"
        }
    }
    
    // MARK: - HealthKit 映射
    #if os(watchOS) || os(iOS)
    var hkWorkoutType: HKWorkoutActivityType {
        switch self {
        case .benchPress, .squat, .deadlift, .overheadPress, .barbellRow, .bicepCurl:
            return .traditionalStrengthTraining
        }
    }
    #endif
    
    var hkWorkoutTypeName: String {
        switch self {
        case .benchPress:
            return NSLocalizedString("traditional_strength_training_bench_press", comment: "传统力量训练 - 卧推")
        case .squat:
            return NSLocalizedString("traditional_strength_training_squat", comment: "传统力量训练 - 深蹲")
        case .deadlift:
            return NSLocalizedString("traditional_strength_training_deadlift", comment: "传统力量训练 - 硬拉")
        case .overheadPress:
            return NSLocalizedString("traditional_strength_training_overhead_press", comment: "传统力量训练 - 肩上推举")
        case .barbellRow:
            return NSLocalizedString("traditional_strength_training_barbell_row", comment: "传统力量训练 - 杠铃划船")
        case .bicepCurl:
            return NSLocalizedString("traditional_strength_training_bicep_curl", comment: "传统力量训练 - 哑铃弯举")
        }
    }
}

// MARK: - 单次锻炼记录
struct RepRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var startedAt: Date? = nil
    let weight: Double // 重量（公斤）
    
    init(id: UUID = UUID(), timestamp: Date = Date(), weight: Double = 0.0) {
        self.id = id
        self.timestamp = timestamp
        self.weight = weight
    }
}

// MARK: - 锻炼会话
struct WorkoutSession: Codable, Identifiable {
    let id: UUID
    var exerciseType: ExerciseType
    let startTime: Date
    var endTime: Date?
    var repRecords: [RepRecord] = []
    var weight: Double = 0.0 // 当前重量设置
    var activeDuration: TimeInterval?
    var durationBeforeResume: TimeInterval?
    var resumedAt: Date?
    var wholeDraft: WholeWorkoutDraft?
    
    init(exerciseType: ExerciseType, startTime: Date, weight: Double = 0.0) {
        self.id = UUID()
        self.exerciseType = exerciseType
        self.startTime = startTime
        self.weight = weight
    }
    
    var isActive: Bool {
        return endTime == nil
    }
    
    var totalReps: Int {
        return repRecords.count
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return (durationBeforeResume ?? 0) + max(0, endTime.timeIntervalSince(resumedAt ?? startTime))
    }

    mutating func pauseForRecovery(at checkpoint: Date) {
        if endTime == nil { endTime = checkpoint }
    }

    mutating func resume(at date: Date = Date()) {
        durationBeforeResume = duration ?? 0
        resumedAt = date
        endTime = nil
        activeDuration = nil
    }
    
    mutating func addRep(weight: Double? = nil) {
        let repWeight = weight ?? self.weight
        repRecords.append(RepRecord(weight: repWeight))
    }
    
    mutating func removeRep() {
        if !repRecords.isEmpty {
            repRecords.removeLast()
        }
    }
    
    mutating func endSession() {
        endTime = Date()
    }
}

// MARK: - 锻炼历史记录
struct WorkoutHistory: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let exerciseType: ExerciseType
    let totalReps: Int
    let maxWeight: Double
    let duration: TimeInterval
    var activeDuration: TimeInterval?
    var totalWeight: Double?
    var workoutReport: WorkoutReport?

    init(id: UUID, date: Date, exerciseType: ExerciseType, totalReps: Int, maxWeight: Double, duration: TimeInterval, activeDuration: TimeInterval? = nil, totalWeight: Double? = nil, workoutReport: WorkoutReport? = nil) {
        self.id = id
        self.date = date
        self.exerciseType = exerciseType
        self.totalReps = totalReps
        self.maxWeight = maxWeight
        self.duration = duration
        self.activeDuration = activeDuration
        self.totalWeight = totalWeight
        self.workoutReport = workoutReport
    }
    
    init(from session: WorkoutSession) {
        self.id = UUID()
        self.date = session.startTime
        self.exerciseType = session.exerciseType
        self.totalReps = session.totalReps
        self.maxWeight = session.repRecords.map { $0.weight }.max() ?? 0.0
        let elapsed = session.duration ?? 0.0
        self.duration = elapsed
        self.activeDuration = session.activeDuration.map { min(elapsed, max(0, $0)) }
        self.totalWeight = session.repRecords.reduce(0) { $0 + $1.weight }
    }
}

// Checkpoints contain only the known repetitions. Loading never starts sensors.
struct WatchWorkoutDraft: Codable {
    let session: WorkoutSession
    let checkpoint: Date
}

struct WatchWorkoutDraftStore {
    let url: URL

    func load() throws -> WatchWorkoutDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try JSONDecoder().decode(WatchWorkoutDraft.self, from: Data(contentsOf: url))
        let session = draft.session
        guard draft.checkpoint.timeIntervalSinceReferenceDate.isFinite,
              session.startTime.timeIntervalSinceReferenceDate.isFinite,
              draft.checkpoint >= session.startTime,
              session.weight.isFinite, session.weight >= 0,
              Set(session.repRecords.map(\.id)).count == session.repRecords.count,
              session.repRecords.allSatisfy({ rep in rep.weight.isFinite && rep.weight >= 0 && rep.timestamp.timeIntervalSinceReferenceDate.isFinite && (rep.startedAt.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 >= session.startTime && $0 <= rep.timestamp } ?? true) }),
              session.endTime.map({ $0 >= session.startTime && $0 <= draft.checkpoint }) ?? true,
              session.durationBeforeResume.map({ $0.isFinite && $0 >= 0 }) ?? true,
              session.resumedAt.map({ $0 >= session.startTime && $0 <= draft.checkpoint }) ?? true,
              session.activeDuration.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try session.wholeDraft?.validate(checkpoint: draft.checkpoint)
        return draft
    }

    func save(_ session: WorkoutSession, at checkpoint: Date = Date()) throws {
        let data = try JSONEncoder().encode(WatchWorkoutDraft(session: session, checkpoint: checkpoint))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    func preserveForRecovery() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let folder = url.deletingLastPathComponent().appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let preserved = folder.appendingPathComponent("current-workout-" + UUID().uuidString + ".json")
        // The destination stays on the same volume. Moving preserves the exact
        // unreadable file (or directory) before a new draft can replace it.
        try FileManager.default.moveItem(at: url, to: preserved)
        return preserved
    }
}

enum WatchWorkoutWeek {
    static func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let daysFromMonday = (calendar.component(.weekday, from: day) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func contains(_ date: Date, in week: DateInterval) -> Bool {
        date >= week.start && date < week.end
    }
}

// MARK: - 应用设置
struct AppSettings: Codable, Equatable {
    var autoDetectionEnabled: Bool = true
    var defaultWeight: Double = 50.0  // 杠铃重量(kg)
    var userBodyWeight: Double = 70.0 // 用户体重（kg）
    var healthKitSyncEnabled: Bool = true
    var autoSyncToHealthKit: Bool = true
    
    static let shared = AppSettings()
}
