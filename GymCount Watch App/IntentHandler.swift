//
//  IntentHandler.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/10/16.
//

import Foundation
import Intents

// MARK: - Intent 处理器主类
class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any? {
        if intent is StartWorkoutIntent {
            return StartWorkoutIntentHandler()
        } else if intent is StopWorkoutIntent {
            return StopWorkoutIntentHandler()
        } else if intent is AddRepIntent {
            return AddRepIntentHandler()
        }
        return nil
    }
}

// MARK: - 辅助方法：Int -> ExerciseType 转换
extension IntentHandler {
    static func convertExerciseType(from rawValue: Int) -> ExerciseType? {
        switch rawValue {
        case 1: // benchPress
            return .benchPress
        case 2: // squat
            return .squat
        case 3: // deadlift
            return .deadlift
        default:
            return nil
        }
    }
}

// MARK: - StartWorkout Intent 处理器
class StartWorkoutIntentHandler: NSObject, StartWorkoutIntentHandling {
    
    func handle(intent: StartWorkoutIntent, completion: @escaping (StartWorkoutIntentResponse) -> Void) {
        print("🎤 Siri: 处理开始锻炼请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否已有活跃的锻炼
        guard dataManager.canStartWorkout() else {
            print("⚠️ Siri: 已有活跃的锻炼，无法开始新的锻炼")
            let response = StartWorkoutIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // 获取运动类型
        guard let exerciseTypeString = intent.exerciseType,
              let exerciseTypeValue = Int(exerciseTypeString),
              let exerciseType = IntentHandler.convertExerciseType(from: exerciseTypeValue) else {
            print("❌ Siri: 无效的运动类型")
            let response = StartWorkoutIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // 开始锻炼
        dataManager.startWorkout(exerciseType: exerciseType)
        
        print("✅ Siri: 成功开始 \(exerciseType.displayName) 锻炼")
        
        // 返回 continueInApp 响应以打开应用
        let response = StartWorkoutIntentResponse(code: .continueInApp, userActivity: nil)
        completion(response)
    }
    
    func resolveExerciseType(for intent: StartWorkoutIntent, with completion: @escaping (INIntegerResolutionResult) -> Void) {
        if let exerciseTypeString = intent.exerciseType,
           let exerciseTypeValue = Int(exerciseTypeString) {
            completion(INIntegerResolutionResult.success(with: exerciseTypeValue))
        } else {
            // 请求用户提供运动类型
            completion(INIntegerResolutionResult.needsValue())
        }
    }
    
    func confirm(intent: StartWorkoutIntent, completion: @escaping (StartWorkoutIntentResponse) -> Void) {
        // 确认阶段：检查是否可以开始锻炼
        let dataManager = DataManager.shared
        
        if dataManager.canStartWorkout() {
            completion(StartWorkoutIntentResponse(code: .success, userActivity: nil))
        } else {
            let response = StartWorkoutIntentResponse(code: .failure, userActivity: nil)
            completion(response)
        }
    }
}

// MARK: - StopWorkout Intent 处理器
class StopWorkoutIntentHandler: NSObject, StopWorkoutIntentHandling {
    
    func handle(intent: StopWorkoutIntent, completion: @escaping (StopWorkoutIntentResponse) -> Void) {
        print("🎤 Siri: 处理停止锻炼请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否有活跃的锻炼
        guard dataManager.currentSession != nil else {
            print("⚠️ Siri: 没有活跃的锻炼")
            let response = StopWorkoutIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        let session = dataManager.currentSession!
        let exerciseType = session.exerciseType
        let totalReps = session.totalReps
        
        // 结束锻炼
        dataManager.endWorkout()
        
        print("✅ Siri: 成功停止锻炼 \(exerciseType.displayName)，共完成 \(totalReps) 次")
        
        // 返回 continueInApp 响应以打开应用
        let response = StopWorkoutIntentResponse(code: .continueInApp, userActivity: nil)
        completion(response)
    }
    
    func confirm(intent: StopWorkoutIntent, completion: @escaping (StopWorkoutIntentResponse) -> Void) {
        // 确认阶段：检查是否有活跃的锻炼
        let dataManager = DataManager.shared
        
        if dataManager.currentSession != nil {
            completion(StopWorkoutIntentResponse(code: .success, userActivity: nil))
        } else {
            let response = StopWorkoutIntentResponse(code: .failure, userActivity: nil)
            completion(response)
        }
    }
}

// MARK: - AddRep Intent 处理器
class AddRepIntentHandler: NSObject, AddRepIntentHandling {
    
    func handle(intent: AddRepIntent, completion: @escaping (AddRepIntentResponse) -> Void) {
        print("🎤 Siri: 处理添加次数请求")
        
        let dataManager = DataManager.shared
        
        // 检查是否有活跃的锻炼
        guard let session = dataManager.currentSession else {
            print("⚠️ Siri: 没有活跃的锻炼")
            let response = AddRepIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // 添加一次
        dataManager.addRep()
        
        let newTotal = session.totalReps + 1
        print("✅ Siri: 成功添加一次 \(session.exerciseType.displayName)，当前总数: \(newTotal)")
        
        // 返回 continueInApp 响应以打开应用
        let response = AddRepIntentResponse(code: .continueInApp, userActivity: nil)
        completion(response)
    }
    
    func confirm(intent: AddRepIntent, completion: @escaping (AddRepIntentResponse) -> Void) {
        // 确认阶段：检查是否有活跃的锻炼
        let dataManager = DataManager.shared
        
        if dataManager.currentSession != nil {
            completion(AddRepIntentResponse(code: .success, userActivity: nil))
        } else {
            let response = AddRepIntentResponse(code: .failure, userActivity: nil)
            completion(response)
        }
    }
}

