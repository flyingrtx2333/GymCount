//
//  DataManager.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import Combine
import HealthKit

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var currentSession: WorkoutSession?
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var settings = AppSettings.shared
    
    let motionDetector = MotionDetector()
    let healthKitManager = HealthKitManager.shared
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "workout_history"
    private let settingsKey = "app_settings"
    
    private init() {
        loadData()
        setupMotionDetector()
        setupHealthKit()
    }
    
    private func setupMotionDetector() {
        motionDetector.onRepDetected = { [weak self] in
            self?.addRep()
        }
    }
    
    private func setupHealthKit() {
        // 如果启用了 HealthKit 同步，请求权限
        if settings.healthKitSyncEnabled {
            Task {
                await healthKitManager.requestAuthorization()
            }
        }
    }
    
    // MARK: - 数据持久化
    private func loadData() {
        // 加载历史记录
        if let historyData = userDefaults.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([WorkoutHistory].self, from: historyData) {
            workoutHistory = history
        }
        
        // 加载设置
        if let settingsData = userDefaults.data(forKey: settingsKey),
           let loadedSettings = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
            settings = loadedSettings
        }
    }
    
    private func saveData() {
        // 保存历史记录
        if let historyData = try? JSONEncoder().encode(workoutHistory) {
            userDefaults.set(historyData, forKey: historyKey)
        }
        
        // 保存设置
        if let settingsData = try? JSONEncoder().encode(settings) {
            userDefaults.set(settingsData, forKey: settingsKey)
        }
    }
    
    // MARK: - 锻炼会话管理
    func startWorkout(exerciseType: ExerciseType, weight: Double = 0.0) {
        currentSession = WorkoutSession(
            exerciseType: exerciseType,
            startTime: Date(),
            weight: weight
        )
        
        // 自动开始运动检测
        motionDetector.configureForExercise(exerciseType)
        motionDetector.startDetection()
    }
    
    func addRep() {
        guard var session = currentSession else { return }
        session.addRep()
        currentSession = session
    }
    
    func removeRep() {
        guard var session = currentSession else { return }
        session.removeRep()
        currentSession = session
    }
    
    func endWorkout() {
        guard var session = currentSession else { return }
        session.endSession()
        
        // 停止运动检测
        motionDetector.stopDetection()
        
        // 添加到历史记录
        let history = WorkoutHistory(from: session)
        workoutHistory.insert(history, at: 0) // 最新的在前面
        
        // 保存数据
        saveData()
        
        // 同步到 HealthKit
        if settings.healthKitSyncEnabled && settings.autoSyncToHealthKit {
            Task {
                await syncWorkoutToHealthKit(history)
            }
        }
        
        // 清除当前会话
        currentSession = nil
    }
    
    func resetCurrentWorkout() {
        motionDetector.stopDetection()
        currentSession = nil
    }
    
    // MARK: - 历史记录管理
    func deleteHistoryItem(_ item: WorkoutHistory) {
        workoutHistory.removeAll { $0.id == item.id }
        saveData()
    }
    
    func clearAllHistory() {
        workoutHistory.removeAll()
        saveData()
    }
    
    // MARK: - 调试方法
    func printAllHistory() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        print("📊 所有历史记录:")
        for (index, workout) in workoutHistory.enumerated() {
            print("  \(index + 1). \(workout.exerciseType.displayName) - \(formatter.string(from: workout.date)) - \(workout.totalReps)次")
        }
        print("总计: \(workoutHistory.count) 条记录")
        print("---")
    }
    
    // MARK: - 设置管理
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        saveData()
        
        // 如果启用了 HealthKit 同步，请求权限
        if settings.healthKitSyncEnabled {
            Task {
                await healthKitManager.requestAuthorization()
            }
        }
    }
    
    // MARK: - 统计数据
    func getTotalWorkouts() -> Int {
        return workoutHistory.count
    }
    
    func getTotalReps() -> Int {
        return workoutHistory.reduce(0) { $0 + $1.totalReps }
    }
    
    func getMaxWeight(for exerciseType: ExerciseType) -> Double {
        return workoutHistory
            .filter { $0.exerciseType == exerciseType }
            .map { $0.maxWeight }
            .max() ?? 0.0
    }
    
    func getRecentWorkouts(limit: Int = 10) -> [WorkoutHistory] {
        return Array(workoutHistory.prefix(limit))
    }
    
    // MARK: - 周数据统计
    func getWeeklyData(for exerciseType: ExerciseType) -> [Int] {
        let calendar = Calendar.current
        let today = Date()
        
        // 获取本周的开始日期（周一）
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        guard let weekStart = weekInterval?.start else { return Array(repeating: 0, count: 7) }
        
        var weeklyData = Array(repeating: 0, count: 7)
        
        // 筛选本周的锻炼记录
        let thisWeekWorkouts = workoutHistory.filter { workout in
            workout.exerciseType == exerciseType &&
            workout.date >= weekStart &&
            workout.date <= today
        }
        
        // 按日期分组统计次数
        for workout in thisWeekWorkouts {
            let dayOfWeek = calendar.component(.weekday, from: workout.date)
            let index = (dayOfWeek + 5) % 7 // 转换为周一到周日的索引 (0-6)
            if index >= 0 && index < 7 {
                weeklyData[index] += workout.totalReps
            }
        }
        
        return weeklyData
    }
    
    func getWeeklyTotal(for exerciseType: ExerciseType) -> Int {
        return getWeeklyData(for: exerciseType).reduce(0, +)
    }
    
    func getWeekDays() -> [String] {
        return ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    }
    
    // MARK: - 按具体日期获取周数据
    func getWeeklyDataForExercise(_ exerciseType: ExerciseType, for weekStartDate: Date) -> [Int] {
        let calendar = Calendar.current
        
        // 使用 getWeekInfo 来确保一致性
        let weekInfo = getWeekInfo(for: weekStartDate)
        let weekStart = weekInfo.startDate
        let weekEnd = weekInfo.endDate
        let weekEndOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: weekEnd)) ?? weekEnd
        
        // 调试信息
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("🔍 调试信息 - 获取周数据:")
        print("   运动类型: \(exerciseType.displayName)")
        print("   输入日期: \(formatter.string(from: weekStartDate))")
        print("   周一开始: \(formatter.string(from: weekStart))")
        print("   周日结束: \(formatter.string(from: weekEnd))")
        print("   总历史记录数: \(workoutHistory.count)")
        
        var weeklyData = Array(repeating: 0, count: 7)
        
        // 筛选该周的锻炼记录
        let weekWorkouts = workoutHistory.filter { workout in
            workout.exerciseType == exerciseType &&
            workout.date >= weekStart &&
            workout.date < weekEndOfDay
        }
        
        print("   匹配的锻炼记录数: \(weekWorkouts.count)")
        
        // 按日期分组统计次数
        for workout in weekWorkouts {
            let dayOfWeek = calendar.component(.weekday, from: workout.date)
            let index = (dayOfWeek + 5) % 7 // 转换为周一到周日的索引 (0-6)
            if index >= 0 && index < 7 {
                weeklyData[index] += workout.totalReps
                print("   记录: \(formatter.string(from: workout.date)) - 周\(index + 1) - \(workout.totalReps)次")
            }
        }
        
        print("   最终周数据: \(weeklyData)")
        print("   周总计: \(weeklyData.reduce(0, +))")
        print("---")
        
        return weeklyData
    }
    
    // MARK: - 按具体日期获取周重量数据
    func getWeeklyWeightDataForExercise(_ exerciseType: ExerciseType, for weekStartDate: Date) -> [Double] {
        let calendar = Calendar.current
        
        // 使用 getWeekInfo 来确保一致性
        let weekInfo = getWeekInfo(for: weekStartDate)
        let weekStart = weekInfo.startDate
        let weekEnd = weekInfo.endDate
        let weekEndOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: weekEnd)) ?? weekEnd
        
        var weeklyWeightData = Array(repeating: 0.0, count: 7)
        
        // 筛选该周的锻炼记录
        let weekWorkouts = workoutHistory.filter { workout in
            workout.exerciseType == exerciseType &&
            workout.date >= weekStart &&
            workout.date < weekEndOfDay
        }
        
        // 按日期分组统计重量
        for workout in weekWorkouts {
            let dayOfWeek = calendar.component(.weekday, from: workout.date)
            let index = (dayOfWeek + 5) % 7 // 转换为周一到周日的索引 (0-6)
            if index >= 0 && index < 7 {
                weeklyWeightData[index] += workout.maxWeight * Double(workout.totalReps)
            }
        }
        
        return weeklyWeightData
    }
    
    func getWeeklyTotalForExercise(_ exerciseType: ExerciseType, for weekStartDate: Date) -> Int {
        return getWeeklyDataForExercise(exerciseType, for: weekStartDate).reduce(0, +)
    }
    
    func getWeeklyTotalWeightForExercise(_ exerciseType: ExerciseType, for weekStartDate: Date) -> Double {
        return getWeeklyWeightDataForExercise(exerciseType, for: weekStartDate).reduce(0, +)
    }
    
    // MARK: - 获取指定周的日期信息
    func getWeekInfo(for weekStartDate: Date) -> (startDate: Date, endDate: Date, title: String) {
        let calendar = Calendar.current
        
        // 确保是周一的开始
        let weekday = calendar.component(.weekday, from: weekStartDate)
        let daysFromMonday = (weekday + 5) % 7
        let mondayStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: weekStartDate) ?? weekStartDate
        
        let weekStart = calendar.startOfDay(for: mondayStart)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        
        let title = "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
        
        return (startDate: weekStart, endDate: weekEnd, title: title)
    }
    
    // MARK: - HealthKit 集成方法
    func syncWorkoutToHealthKit(_ workoutHistory: WorkoutHistory) async {
        guard settings.healthKitSyncEnabled else {
            print("❌ HealthKit 同步已禁用")
            return
        }
        
        // 刷新授权状态
        healthKitManager.refreshAuthorizationStatus()
        
        // 检查是否已存在相同的锻炼记录
        let exists = await healthKitManager.checkWorkoutExists(workoutHistory)
        if exists {
            print("⚠️ 锻炼记录已存在于 HealthKit 中，跳过同步")
            return
        }
        
        await healthKitManager.saveWorkoutToHealthKit(workoutHistory)
    }
    
    func syncAllWorkoutsToHealthKit() async {
        guard settings.healthKitSyncEnabled else {
            print("❌ HealthKit 同步已禁用")
            return
        }
        
        // 刷新授权状态
        healthKitManager.refreshAuthorizationStatus()
        
        print("🔄 开始同步所有锻炼记录到 HealthKit...")
        await healthKitManager.syncWorkoutHistory(workoutHistory)
    }
    
    func requestHealthKitPermission() async {
        await healthKitManager.requestAuthorization()
    }
    
    func getHealthKitAuthorizationStatus() -> HKAuthorizationStatus {
        return healthKitManager.authorizationStatus
    }
    
    func isHealthKitAuthorized() -> Bool {
        return healthKitManager.isAuthorized
    }
    
    // MARK: - 调试方法
    func debugHealthKitStatus() {
        healthKitManager.debugAuthorizationStatus()
    }
}
