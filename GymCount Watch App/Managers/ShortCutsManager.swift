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
        nil
    }
}

// MARK: - 开始锻炼 Intent
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "开始健身计数"
    static var description = IntentDescription("开始记录指定的锻炼动作")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "运动类型", requestValueDialog: "要计数哪个动作？")
    var exerciseType: ExerciseTypeEntity
    
    @Parameter(title: "重量(kg)")
    var weight: Double?
    
    static var parameterSummary: some ParameterSummary {
        Summary("开始记录\(\.$exerciseType)") {
            \.$weight
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dataManager = DataManager.shared
        guard !dataManager.isSavingWorkout else { throw StartWorkoutError.saving }
        guard !dataManager.requiresDraftRecovery, !dataManager.requiresWorkoutRecovery else {
            throw StartWorkoutError.recoveryRequired
        }
        guard dataManager.currentSession == nil else { throw StartWorkoutError.alreadyActive }
        #if DEBUG
        guard !CollectionStore.shared.recording, CollectionStore.shared.draft == nil else {
            throw StartWorkoutError.captureActive
        }
        #endif
        guard let exercise = exerciseType.toExerciseType() else {
            throw StartWorkoutError.invalidExercise
        }
        let weightValue = weight ?? dataManager.settings.defaultWeight
        guard weightValue.isFinite, (0...500).contains(weightValue) else { throw StartWorkoutError.invalidWeight }
        let started = await dataManager.startWholeWorkout(exerciseType: exercise, weight: weightValue)
        guard started, let session = dataManager.currentSession, session.exerciseType == exercise, session.isActive else {
            throw NSError(domain: "PowerReps.Siri", code: 1,
                userInfo: [NSLocalizedDescriptionKey: dataManager.saveError ?? dataManager.wholeWorkoutError ?? String(localized: "计数未能开始，请在手表重试")])
        }
        #if DEBUG
        WatchCaptureLink.shared.showingCapture = false
        #endif
        return .result(dialog: "已开始\(exercise.displayName)计数")
    }
}

// MARK: - 停止锻炼 Intent
struct StopWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "结束训练"
    static var description = IntentDescription("结束当前训练并保存报告")
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("结束当前训练")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dataManager = DataManager.shared
        guard let session = dataManager.currentSession else {
            throw StopWorkoutError.noActiveWorkout
        }
        let isWholeWorkout = dataManager.isWholeWorkout
        let count = isWholeWorkout ? dataManager.wholeTotalReps : session.totalReps
        let saved = isWholeWorkout
            ? await dataManager.finishWholeWorkout()
            : await dataManager.endWorkout()
        guard saved else {
            throw NSError(domain: "PowerReps.Siri", code: 2, userInfo: [
                NSLocalizedDescriptionKey: dataManager.saveError ?? dataManager.wholeWorkoutError ?? String(localized: "保存失败，请重试")
            ])
        }
        // Final motion analysis can revise a provisional count while saving.
        let total = isWholeWorkout
            ? (dataManager.completedWholeWorkout?.totalReps ?? count)
            : (dataManager.completedWorkout?.totalReps ?? count)
        return .result(dialog: "训练已保存，共\(total)次")
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
            let message = String(localized: "当前没有活跃的锻炼")
            print("ℹ️ 快捷指令: \(message)")
            return .result(value: message)
        }
        
        let exerciseName = session.exerciseType.displayName
        let totalReps = dataManager.isWholeWorkout ? dataManager.wholeTotalReps : session.totalReps
        if dataManager.isWholeWorkout {
            return .result(value: String(localized: "训练进行中，共\(totalReps)次"))
        }
        let duration = Int(Date().timeIntervalSince(session.startTime) / 60)
        
        let message = String(localized: "正在记录\(exerciseName)，已完成\(totalReps)次，已进行\(duration)分钟")
        print("ℹ️ 快捷指令: \(message)")
        
        return .result(value: message)
    }
}

// MARK: - 错误定义
enum StartWorkoutError: Error, CustomLocalizedStringResourceConvertible {
    case alreadyActive
    case invalidExercise
    case invalidWeight
    case recoveryRequired
    case captureActive
    case saving
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .alreadyActive:
            return "已有正在进行的锻炼，请先停止当前锻炼"
        case .invalidExercise:
            return "无效的运动类型"
        case .invalidWeight:
            return "重量须在 0–500 公斤之间"
        case .recoveryRequired:
            return "请先在手表处理未完成训练"
        case .captureActive:
            return "请先完成当前采集"
        case .saving:
            return "训练正在保存，请稍后再试"
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
                "Start \(.applicationName)",
                "Start counting with \(.applicationName)",
                "Start \(\.$exerciseType) with \(.applicationName)",
                "Start recording workout with \(.applicationName)",
                "Begin workout using \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("shortcut_title_start_workout"),
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StopWorkoutIntent(),
            phrases: [
                "Finish \(.applicationName)",
                "End workout with \(.applicationName)",
                "Stop counting with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("shortcut_title_end_workout"),
            systemImageName: "stop.circle"
        )
    }
}
