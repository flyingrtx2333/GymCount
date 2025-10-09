//
//  Models.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import HealthKit

// MARK: - 锻炼类型枚举
enum ExerciseType: String, CaseIterable, Codable {
    case benchPress = "bench_press"
    case squat = "squat"
    
    var displayName: String {
        switch self {
        case .benchPress:
            return NSLocalizedString("bench_press", comment: "卧推")
        case .squat:
            return NSLocalizedString("squat", comment: "深蹲")
        }
    }
    
    var icon: String {
        switch self {
        case .benchPress:
            return "figure.strengthtraining.traditional"
        case .squat:
            return "figure.strengthtraining.functional"
        }
    }
    
    // MARK: - HealthKit 映射
    var hkWorkoutType: HKWorkoutActivityType {
        switch self {
        case .benchPress, .squat:
            return .traditionalStrengthTraining
        }
    }
    
    var hkWorkoutTypeName: String {
        switch self {
        case .benchPress:
            return "传统力量训练 - 卧推"
        case .squat:
            return "传统力量训练 - 深蹲"
        }
    }
}

// MARK: - 单次锻炼记录
struct RepRecord: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let weight: Double // 重量（公斤）
    
    init(weight: Double = 0.0) {
        self.timestamp = Date()
        self.weight = weight
    }
}

// MARK: - 锻炼会话
struct WorkoutSession: Codable, Identifiable {
    let id = UUID()
    let exerciseType: ExerciseType
    let startTime: Date
    var endTime: Date?
    var repRecords: [RepRecord] = []
    var weight: Double = 0.0 // 当前重量设置
    
    var isActive: Bool {
        return endTime == nil
    }
    
    var totalReps: Int {
        return repRecords.count
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
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
struct WorkoutHistory: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let exerciseType: ExerciseType
    let totalReps: Int
    let maxWeight: Double
    let duration: TimeInterval
    
    init(from session: WorkoutSession) {
        self.date = session.startTime
        self.exerciseType = session.exerciseType
        self.totalReps = session.totalReps
        self.maxWeight = session.repRecords.map { $0.weight }.max() ?? 0.0
        self.duration = session.duration ?? 0.0
    }
}

// MARK: - 应用设置
struct AppSettings: Codable {
    var autoDetectionEnabled: Bool = true
    var defaultWeight: Double = 50.0
    var healthKitSyncEnabled: Bool = true
    var autoSyncToHealthKit: Bool = true
    
    static let shared = AppSettings()
}
