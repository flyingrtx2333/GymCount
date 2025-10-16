//
//  SiriKitManager.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/10/16.
//

import Foundation
import Intents
import Combine

class SiriKitManager: ObservableObject {
    static let shared = SiriKitManager()
    
    @Published var isAuthorized = false
    @Published var authorizationStatus: INSiriAuthorizationStatus = .notDetermined
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - 权限检查
    func checkAuthorizationStatus() {
        authorizationStatus = INPreferences.siriAuthorizationStatus()
        isAuthorized = (authorizationStatus == .authorized)
        
        print("Siri 授权状态: \(statusDescription(authorizationStatus))")
    }
    
    // MARK: - 强制刷新授权状态
    func refreshAuthorizationStatus() {
        checkAuthorizationStatus()
    }
    
    // MARK: - 调试方法
    func debugAuthorizationStatus() {
        print(" === Siri 授权状态调试信息 ===")
        print("当前授权状态: \(authorizationStatus.rawValue)")
        print("状态描述: \(statusDescription(authorizationStatus))")
        print("isAuthorized 属性: \(isAuthorized)")
        print("=====================================")
    }
    
    private func statusDescription(_ status: INSiriAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未确定"
        case .restricted:
            return "受限"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已授权"
        @unknown default:
            return "未知状态"
        }
    }
    
    // MARK: - 请求权限
    func requestAuthorization() async {
        return await withCheckedContinuation { continuation in
            INPreferences.requestSiriAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    self.isAuthorized = (status == .authorized)
                    print("✅ Siri 权限请求完成: \(self.statusDescription(status))")
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - 捐赠快捷指令（用于 Siri 建议）
    func donateStartWorkoutIntent(exerciseType: ExerciseType) {
        guard isAuthorized else {
            print("⚠️ Siri 未授权，无法捐赠意图")
            return
        }
        
        let intent = StartWorkoutIntent()
        intent.exerciseType = String(exerciseTypeToInt(exerciseType))
        
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("❌ 捐赠意图失败: \(error)")
            } else {
                print("✅ 已捐赠开始锻炼意图: \(exerciseType.displayName)")
            }
        }
    }
    
    func donateStopWorkoutIntent() {
        guard isAuthorized else {
            print("⚠️ Siri 未授权，无法捐赠意图")
            return
        }
        
        let intent = StopWorkoutIntent()
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("❌ 捐赠停止锻炼意图失败: \(error)")
            } else {
                print("✅ 已捐赠停止锻炼意图")
            }
        }
    }
    
    func donateAddRepIntent() {
        guard isAuthorized else {
            print("⚠️ Siri 未授权，无法捐赠意图")
            return
        }
        
        let intent = AddRepIntent()
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.donate { error in
            if let error = error {
                print("❌ 捐赠添加次数意图失败: \(error)")
            } else {
                print("✅ 已捐赠添加次数意图")
            }
        }
    }
    
    // MARK: - 辅助方法
    private func exerciseTypeToInt(_ exerciseType: ExerciseType) -> Int {
        switch exerciseType {
        case .benchPress:
            return 1
        case .squat:
            return 2
        case .deadlift:
            return 3
        }
    }
}

