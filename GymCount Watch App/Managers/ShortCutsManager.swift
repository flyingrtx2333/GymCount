//
//  ShortCutsManager.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/10/16.
//

import Foundation
import AppIntents
import SwiftUI

// MARK: - 运动类型实体（用于快捷指令）
struct ExerciseTypeEntity: AppEntity {
    let id: String
    let displayName: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "运动类型")
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
    
    static var defaultQuery = ExerciseTypeQuery()
    
    // 从 ExerciseType 转换
    init(from exerciseType: ExerciseType) {
        self.id = exerciseType.rawValue
        self.displayName = exerciseType.displayName
    }
    
    // 转换为 ExerciseType
    func toExerciseType() -> ExerciseType? {
        return ExerciseType(rawValue: id)
    }
}

// MARK: - 运动类型查询
struct ExerciseTypeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ExerciseTypeEntity] {
        return ExerciseType.allCases
            .filter { identifiers.contains($0.rawValue) }
            .map { ExerciseTypeEntity(from: $0) }
    }
    
    func suggestedEntities() async throws -> [ExerciseTypeEntity] {
        return ExerciseType.allCases.map { ExerciseTypeEntity(from: $0) }
    }
    
    func defaultResult() async -> ExerciseTypeEntity? {
        return ExerciseTypeEntity(from: .squat)
    }
}

// MARK: - 开始锻炼 Intent
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "开始记录锻炼"
    static var description = IntentDescription("开始记录指定的锻炼动作")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "运动类型")
    var exerciseType: ExerciseTypeEntity
    
    @Parameter(title: "重量(kg)", default: 0.0)
    var weight: Double?
    
    static var parameterSummary: some ParameterSummary {
        Summary("开始记录\(\.$exerciseType)") {
            \.$weight
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        print("🎤 快捷指令: 处理开始锻炼请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否已有活跃的锻炼
        guard dataManager.canStartWorkout() else {
            print("⚠️ 快捷指令: 已有活跃的锻炼，无法开始新的锻炼")
            throw StartWorkoutError.alreadyActive
        }
        
        // 获取运动类型
        guard let exercise = exerciseType.toExerciseType() else {
            print("❌ 快捷指令: 无效的运动类型")
            throw StartWorkoutError.invalidExercise
        }
        
        // 开始锻炼
        let weightValue = weight ?? dataManager.settings.defaultWeight
        dataManager.startWorkout(exerciseType: exercise, weight: weightValue)
        
        print("✅ 快捷指令: 成功开始 \(exercise.displayName) 锻炼")
        
        return .result()
    }
}

// MARK: - 停止锻炼 Intent
struct StopWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "停止锻炼"
    static var description = IntentDescription("停止当前正在进行的锻炼")
    static var openAppWhenRun: Bool = true
    
    static var parameterSummary: some ParameterSummary {
        Summary("停止当前锻炼")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        print("🎤 快捷指令: 处理停止锻炼请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否有活跃的锻炼
        guard let session = dataManager.currentSession else {
            print("⚠️ 快捷指令: 没有活跃的锻炼")
            throw StopWorkoutError.noActiveWorkout
        }
        
        let exerciseName = session.exerciseType.displayName
        let totalReps = session.totalReps
        
        // 结束锻炼
        dataManager.endWorkout()
        
        print("✅ 快捷指令: 成功停止锻炼 \(exerciseName)，共完成 \(totalReps) 次")
        
        return .result()
    }
}

// MARK: - 添加次数 Intent
struct AddRepIntent: AppIntent {
    static var title: LocalizedStringResource = "添加一次"
    static var description = IntentDescription("为当前锻炼添加一次计数")
    static var openAppWhenRun: Bool = false
    
    static var parameterSummary: some ParameterSummary {
        Summary("添加一次")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎤 快捷指令: 处理添加次数请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否有活跃的锻炼
        guard let session = dataManager.currentSession else {
            print("⚠️ 快捷指令: 没有活跃的锻炼")
            throw AddRepError.noActiveWorkout
        }
        
        // 添加一次
        dataManager.addRep()
        
        let exerciseName = session.exerciseType.displayName
        let newTotal = session.totalReps + 1
        print("✅ 快捷指令: 成功添加一次 \(exerciseName)，当前总数: \(newTotal)")
        
        return .result()
    }
}

// MARK: - 查询当前锻炼状态 Intent
struct GetWorkoutStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "查询锻炼状态"
    static var description = IntentDescription("查询当前锻炼的状态信息")
    static var openAppWhenRun: Bool = false
    
    static var parameterSummary: some ParameterSummary {
        Summary("查询当前锻炼状态")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        print("🎤 快捷指令: 查询锻炼状态")
        
        let dataManager = DataManager.shared
        
        guard let session = dataManager.currentSession else {
            let message = "当前没有活跃的锻炼"
            print("ℹ️ 快捷指令: \(message)")
            return .result(value: message)
        }
        
        let exerciseName = session.exerciseType.displayName
        let totalReps = session.totalReps
        let duration = Int(Date().timeIntervalSince(session.startTime) / 60)
        
        let message = "正在记录\(exerciseName)，已完成\(totalReps)次，已进行\(duration)分钟"
        print("ℹ️ 快捷指令: \(message)")
        
        return .result(value: message)
    }
}

// MARK: - 错误定义
enum StartWorkoutError: Error, CustomLocalizedStringResourceConvertible {
    case alreadyActive
    case invalidExercise
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .alreadyActive:
            return "已有正在进行的锻炼，请先停止当前锻炼"
        case .invalidExercise:
            return "无效的运动类型"
        }
    }
}

enum StopWorkoutError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveWorkout
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveWorkout:
            return "当前没有正在进行的锻炼"
        }
    }
}

enum AddRepError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveWorkout
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveWorkout:
            return "当前没有正在进行的锻炼"
        }
    }
}

// MARK: - 快捷指令提供者
struct GymCountShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "开始记录\(.applicationName)锻炼",
                "用\(.applicationName)开始锻炼"
            ],
            shortTitle: "开始锻炼",
            systemImageName: "figure.strengthtraining.traditional"
        )
    }
}