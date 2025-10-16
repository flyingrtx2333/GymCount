//
//  HealthKitManager.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    let healthStore = HKHealthStore() // 改为公共访问
    @Published var isAuthorized = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - 权限检查
    func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit 不可用")
            isAuthorized = false
            authorizationStatus = .notDetermined
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        authorizationStatus = healthStore.authorizationStatus(for: workoutType)
        
        // 检查所有可能的授权状态
        print("🔍 原始授权状态: \(authorizationStatus.rawValue)")
        print("🔍 .notDetermined: \(HKAuthorizationStatus.notDetermined.rawValue)")
        print("🔍 .sharingDenied: \(HKAuthorizationStatus.sharingDenied.rawValue)")
        print("🔍 .sharingAuthorized: \(HKAuthorizationStatus.sharingAuthorized.rawValue)")
        
        // 根据实际状态值判断是否已授权
        isAuthorized = authorizationStatus.rawValue == 2 // 根据调试输出，2 表示已授权
        
        print("🔍 HealthKit 授权状态: \(authorizationStatus.rawValue), 是否已授权: \(isAuthorized)")
    }
    
    // MARK: - 强制刷新授权状态
    func refreshAuthorizationStatus() {
        checkAuthorizationStatus()
    }
    
    // MARK: - 调试方法
    func debugAuthorizationStatus() {
        print("🔍 === HealthKit 授权状态调试信息 ===")
        print("HealthKit 是否可用: \(HKHealthStore.isHealthDataAvailable())")
        
        let workoutType = HKObjectType.workoutType()
        let currentStatus = healthStore.authorizationStatus(for: workoutType)
        
        print("当前授权状态: \(currentStatus.rawValue)")
        print("状态描述: \(statusDescription(currentStatus))")
        print("isAuthorized 属性: \(isAuthorized)")
        print("authorizationStatus 属性: \(authorizationStatus.rawValue)")
        print("=====================================")
    }
    
    private func statusDescription(_ status: HKAuthorizationStatus) -> String {
        switch status.rawValue {
        case 0:
            return "未确定"
        case 1:
            return "已拒绝"
        case 2:
            return "已授权"
        default:
            return "未知状态(\(status.rawValue))"
        }
    }
    
    // MARK: - 请求权限
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit 不可用")
            return
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]
        
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await MainActor.run {
                checkAuthorizationStatus()
            }
            print("✅ HealthKit 权限请求完成")
        } catch {
            print("❌ HealthKit 权限请求失败: \(error)")
        }
    }
    
    // MARK: - 获取用户体重
    func getUserBodyWeight() async -> Double {
        // 首先尝试从 HealthKit 获取最新体重数据
        let currentStatus = healthStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .bodyMass)!)
        if currentStatus.rawValue == 2 { // 2 表示已授权
            guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
                print("❌ 无法创建体重类型")
                return DataManager.shared.settings.userBodyWeight
            }
            
            return await withCheckedContinuation { continuation in
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
                let query = HKSampleQuery(
                    sampleType: bodyMassType,
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        print("❌ 读取体重数据失败: \(error)")
                        continuation.resume(returning: DataManager.shared.settings.userBodyWeight)
                        return
                    }
                    
                    if let sample = samples?.first as? HKQuantitySample {
                        let weight = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                        print("✅ 从 HealthKit 获取到用户体重: \(weight) kg")
                        continuation.resume(returning: weight)
                    } else {
                        print("⚠️ HealthKit 中未找到体重数据，使用设置中的体重")
                        continuation.resume(returning: DataManager.shared.settings.userBodyWeight)
                    }
                }
                
                healthStore.execute(query)
            }
        } else {
            print("⚠️ HealthKit 未授权读取体重数据，使用设置中的体重")
            return DataManager.shared.settings.userBodyWeight
        }
    }
    
    // MARK: - 保存锻炼数据到 HealthKit
    func saveWorkoutToHealthKit(_ workoutHistory: WorkoutHistory) async {
        // 实时检查授权状态
        let currentStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard currentStatus.rawValue == 2 else { // 2 表示已授权
            print("❌ HealthKit 未授权，无法保存锻炼数据。当前状态: \(currentStatus.rawValue)")
            return
        }
        
        // 将应用内的锻炼类型映射到 HealthKit 的锻炼类型
        let hkWorkoutType = mapToHKWorkoutType(workoutHistory.exerciseType)
        
        // 计算锻炼结束时间
        let endDate = workoutHistory.date.addingTimeInterval(workoutHistory.duration)
        
        // 获取用户体重
        let userBodyWeight = await getUserBodyWeight()
        
        // 先计算卡路里消耗
        let estimatedCalories = calculateEstimatedCalories(
            reps: workoutHistory.totalReps,
            weight: workoutHistory.maxWeight,
            bodyWeight: userBodyWeight,
            duration: workoutHistory.duration
        )
        
        print("🔥 卡路里计算详情:")
        print("   次数: \(workoutHistory.totalReps)")
        print("   重量: \(workoutHistory.maxWeight) kg")
        print("   用户体重: \(userBodyWeight) kg")
        print("   时长: \(workoutHistory.duration) 秒")
        print("   估算卡路里: \(String(format: "%.2f", estimatedCalories)) kcal")
        
        // 创建能量消耗数据
        let energyQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: estimatedCalories)
        
        // 创建锻炼会话，包含能量消耗数据
        let workout = HKWorkout(
            activityType: hkWorkoutType,
            start: workoutHistory.date,
            end: endDate,
            duration: workoutHistory.duration,
            totalEnergyBurned: energyQuantity,
            totalDistance: nil,
            metadata: [
                "app_name": "GymCount",
                "exercise_type": workoutHistory.exerciseType.rawValue,
                "total_reps": workoutHistory.totalReps,
                "max_weight": workoutHistory.maxWeight
            ]
        )
        
        do {
            try await healthStore.save(workout)
            print("✅ 锻炼数据已保存到 HealthKit: \(workoutHistory.exerciseType.displayName)")
            print("✅ 锻炼总能量消耗: \(estimatedCalories) 卡路里")
            
            // 保存额外的健康数据（活跃能量样本）
            await saveAdditionalHealthData(for: workout, workoutHistory: workoutHistory)
            
        } catch {
            print("❌ 保存锻炼数据到 HealthKit 失败: \(error)")
        }
    }
    
    // MARK: - 保存额外的健康数据
    private func saveAdditionalHealthData(for workout: HKWorkout, workoutHistory: WorkoutHistory) async {
        let endDate = workout.endDate
        
        // 使用与锻炼记录相同的卡路里值
        let estimatedCalories = workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
        
        // 保存活跃能量消耗样本，并关联到锻炼记录
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let energyQuantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: estimatedCalories)
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: energyQuantity,
                start: workout.startDate,
                end: endDate,
                device: nil,
                metadata: [
                    "HKWorkoutActivityID": workout.uuid.uuidString,
                    "HKWorkoutActivityType": workout.workoutActivityType.rawValue
                ]
            )
            
            do {
                try await healthStore.save(energySample)
                print("✅ 活跃能量样本已保存: \(estimatedCalories) 卡路里")
                print("✅ 能量样本已关联到锻炼记录: \(workout.uuid)")
            } catch {
                print("❌ 保存活跃能量样本失败: \(error)")
            }
        }
    }
    
    // MARK: - 锻炼类型映射
    private func mapToHKWorkoutType(_ exerciseType: ExerciseType) -> HKWorkoutActivityType {
        switch exerciseType {
        case .benchPress:
            return .traditionalStrengthTraining
        case .squat:
            return .traditionalStrengthTraining
        case .deadlift:
            return .traditionalStrengthTraining
        }
    }
    
    // MARK: - 卡路里计算
    /// 基于体重、负重、次数、时长估算卡路里消耗（更科学版本）
    /// - Parameters:
    ///   - reps: 动作次数
    ///   - weight: 杠铃重量（kg）
    ///   - bodyWeight: 用户体重（kg）
    ///   - duration: 当前组持续时间（秒）
    /// - Returns: 估算消耗的卡路里
    private func calculateEstimatedCalories(reps: Int, weight: Double, bodyWeight: Double, duration: TimeInterval) -> Double {
        // 基础 MET（中等强度力量训练约 5-6）
        var met = 5.0
        
        // 根据负重比例（相对于体重）提升 MET
        let intensityFactor = (weight / bodyWeight) * 1.5
        met += intensityFactor
        
        // 根据次数增加微调
        met += Double(reps) / 20.0
        
        // 防止异常
        met = min(max(met, 5.0), 9.0) // 限制在合理区间 [5,9]
        
        // 计算时间（小时）
        let durationHours = duration / 3600.0
        
        // 卡路里 = MET × 体重 × 小时
        let calories = met * bodyWeight * durationHours
        
        return max(calories, 0.5) // 至少消耗0.5 kcal
    }
    
    // MARK: - 读取锻炼历史
    func readWorkoutHistory(from startDate: Date, to endDate: Date) async -> [HKWorkout] {
        let currentStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard currentStatus.rawValue == 2 else { // 2 表示已授权
            print("❌ HealthKit 未授权，无法读取锻炼历史。当前状态: \(currentStatus.rawValue)")
            return []
        }
        
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("❌ 读取锻炼历史失败: \(error)")
                    continuation.resume(returning: [])
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                print("✅ 从 HealthKit 读取到 \(workouts.count) 条锻炼记录")
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - 同步数据
    func syncWorkoutHistory(_ workoutHistory: [WorkoutHistory]) async {
        let currentStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard currentStatus.rawValue == 2 else { // 2 表示已授权
            print("❌ HealthKit 未授权，无法同步数据。当前状态: \(currentStatus.rawValue)")
            return
        }
        
        print("🔄 开始同步 \(workoutHistory.count) 条锻炼记录到 HealthKit")
        
        for workout in workoutHistory {
            await saveWorkoutToHealthKit(workout)
            // 添加小延迟避免过于频繁的请求
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
        
        print("✅ 锻炼记录同步完成")
    }
    
    // MARK: - 检查特定锻炼是否已存在
    func checkWorkoutExists(_ workoutHistory: WorkoutHistory) async -> Bool {
        let currentStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard currentStatus.rawValue == 2 else { // 2 表示已授权
            print("❌ HealthKit 未授权，无法检查锻炼记录。当前状态: \(currentStatus.rawValue)")
            return false 
        }
        
        let startDate = workoutHistory.date
        let endDate = startDate.addingTimeInterval(workoutHistory.duration)
        
        let workouts = await readWorkoutHistory(from: startDate, to: endDate)
        
        // 检查是否有相同时间段的锻炼记录
        return workouts.contains { workout in
            let timeDiff = abs(workout.startDate.timeIntervalSince(startDate))
            return timeDiff < 60 // 1分钟内的差异认为是同一次锻炼
        }
    }
}
