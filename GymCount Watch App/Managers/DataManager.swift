//
//  DataManager.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import Combine
import HealthKit
import WatchKit

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var currentSession: WorkoutSession?
    @Published var workoutHistory: [WorkoutHistory] = []
    @Published var settings = AppSettings.shared
    @Published var isFirstLaunch = true
    
    let motionDetector = MotionDetector()
    let healthKitManager = HealthKitManager.shared
    
    // HealthKit 运动会话
    private var hkWorkoutSession: HKWorkoutSession?
    private var hkSessionDelegate: WorkoutSessionDelegate?
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "workout_history"
    private let settingsKey = "app_settings"
    private let firstLaunchKey = "is_first_launch"
    
    private init() {
        checkFirstLaunch()
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
    
    // MARK: - 首次启动检测
    private func checkFirstLaunch() {
        isFirstLaunch = userDefaults.object(forKey: firstLaunchKey) == nil
        if isFirstLaunch {
            userDefaults.set(false, forKey: firstLaunchKey)
        }
    }
    
    func completeFirstLaunch() {
        isFirstLaunch = false
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
        WKInterfaceDevice.current().play(.click)
        currentSession = WorkoutSession(
            exerciseType: exerciseType,
            startTime: Date(),
            weight: weight
        )
        
        // 创建 HealthKit 运动会话
        startHKWorkoutSession(exerciseType: exerciseType)
        
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
        
        // 结束 HealthKit 运动会话
        endHKWorkoutSession()
        
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
    
    // MARK: - 调试数据生成
    func generateRandomBenchPressData() {
        let calendar = Calendar.current
        let today = Date()
        
        // 生成当前周的数据（周一到周日）
        let currentWeekStart = getWeekInfo(for: today).startDate
        for dayOffset in 0..<7 {
            if let workoutDate = calendar.date(byAdding: .day, value: dayOffset, to: currentWeekStart) {
                let randomReps = Int.random(in: 0...50) // 0-50次随机
                let randomWeight = Double.random(in: 20...100) // 20-100kg随机重量
                
                if randomReps > 0 {
                    // 创建模拟的WorkoutSession
                    var session = WorkoutSession(
                        exerciseType: .benchPress,
                        startTime: workoutDate,
                        weight: randomWeight
                    )
                    
                    // 添加随机次数
                    for _ in 0..<randomReps {
                        session.addRep(weight: randomWeight)
                    }
                    
                    // 设置结束时间
                    let duration = TimeInterval.random(in: 300...1800) // 5-30分钟
                    let endTime = workoutDate.addingTimeInterval(duration)
                    session.endTime = endTime
                    
                    // 从session创建WorkoutHistory
                    let workout = WorkoutHistory(from: session)
                    workoutHistory.append(workout)
                }
            }
        }
        
        // 生成上周的数据（周一到周日）
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? currentWeekStart
        for dayOffset in 0..<7 {
            if let workoutDate = calendar.date(byAdding: .day, value: dayOffset, to: lastWeekStart) {
                let randomReps = Int.random(in: 0...45) // 0-45次随机（比当前周略少）
                let randomWeight = Double.random(in: 15...95) // 15-95kg随机重量
                
                if randomReps > 0 {
                    // 创建模拟的WorkoutSession
                    var session = WorkoutSession(
                        exerciseType: .benchPress,
                        startTime: workoutDate,
                        weight: randomWeight
                    )
                    
                    // 添加随机次数
                    for _ in 0..<randomReps {
                        session.addRep(weight: randomWeight)
                    }
                    
                    // 设置结束时间
                    let duration = TimeInterval.random(in: 300...1800) // 5-30分钟
                    let endTime = workoutDate.addingTimeInterval(duration)
                    session.endTime = endTime
                    
                    // 从session创建WorkoutHistory
                    let workout = WorkoutHistory(from: session)
                    workoutHistory.append(workout)
                }
            }
        }
        
        // 按日期排序（最新的在前面）
        workoutHistory.sort { $0.date > $1.date }
        
        // 保存数据
        saveData()
        
        print("🎲 已生成随机卧推数据:")
        print("   当前周: 7天随机数据")
        print("   上周: 7天随机数据")
        print("   总记录数: \(workoutHistory.count)")
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
    
    // MARK: - 获取上周数据对比
    func getPreviousWeekDataForExercise(_ exerciseType: ExerciseType, for currentWeekDate: Date) -> (totalReps: Int, totalWeight: Double) {
        let calendar = Calendar.current
        let previousWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate) ?? currentWeekDate
        
        let totalReps = getWeeklyTotalForExercise(exerciseType, for: previousWeekDate)
        let totalWeight = getWeeklyTotalWeightForExercise(exerciseType, for: previousWeekDate)
        
        return (totalReps: totalReps, totalWeight: totalWeight)
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
        // 根据系统语言设置日期格式
        if Locale.current.language.languageCode?.identifier == "zh" {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "M/d"
        }
        
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
    
    // MARK: - 每日鼓励消息生成
    func generateDailyEncouragementMessage() -> (title: String, message: String) {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        
        // 获取今日和昨日的运动数据
        let todayWorkouts = getWorkoutsForDate(today)
        let yesterdayWorkouts = getWorkoutsForDate(yesterday)
        
        let todayTotalReps = todayWorkouts.reduce(0) { $0 + $1.totalReps }
        let yesterdayTotalReps = yesterdayWorkouts.reduce(0) { $0 + $1.totalReps }
        
        if todayTotalReps > 0 {
            // 今天有运动
            let exerciseTypes = Set(todayWorkouts.map { $0.exerciseType.displayName })
            let exerciseTypeString = Array(exerciseTypes).joined(separator: "、")
            
            let difference = todayTotalReps - yesterdayTotalReps
            
            if difference > 0 {
                // 比昨天进步
                let title = NSLocalizedString("great_progress", comment: "很棒！")
                let message = String(format: NSLocalizedString("progress_message", comment: "今天完成了%d次%@，比昨天进步了%d个，继续努力！"), 
                                   todayTotalReps, exerciseTypeString, difference)
                return (title, message)
            } else if difference < 0 {
                // 比昨天略低
                let title = NSLocalizedString("keep_going", comment: "继续加油！")
                let message = String(format: NSLocalizedString("slight_decrease_message", comment: "今天完成了%d次%@，比昨天略低%d个，继续加油！"), 
                                   todayTotalReps, exerciseTypeString, abs(difference))
                return (title, message)
            } else {
                // 和昨天一样
                let title = NSLocalizedString("consistent_effort", comment: "坚持得很好！")
                let message = String(format: NSLocalizedString("consistent_message", comment: "今天完成了%d次%@，和昨天一样，坚持得很好！"), 
                                   todayTotalReps, exerciseTypeString)
                return (title, message)
            }
        } else {
            // 今天没有运动
            let title = NSLocalizedString("time_to_move", comment: "该运动了！")
            let message = NSLocalizedString("no_workout_today", comment: "今天还没运动，快来开始你的锻炼吧！")
            return (title, message)
        }
    }
    
    // MARK: - 获取指定日期的运动数据
    private func getWorkoutsForDate(_ date: Date) -> [WorkoutHistory] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        return workoutHistory.filter { workout in
            workout.date >= startOfDay && workout.date < endOfDay
        }
    }
    
    // MARK: - 调试方法
    func debugHealthKitStatus() {
        healthKitManager.debugAuthorizationStatus()
    }
    
    // MARK: - Siri Intent 支持
    func canStartWorkout() -> Bool {
        return currentSession == nil
    }
    
    func getCurrentWorkoutStatus() -> String {
        guard let session = currentSession else {
            return NSLocalizedString("no_active_workout", comment: "没有活跃的锻炼")
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: session.startTime)
        
        return String(format: NSLocalizedString("active_workout_status", comment: "正在记录 %@，已做 %d 次，开始时间 %@"), 
                     session.exerciseType.displayName, 
                     session.totalReps, 
                     timeString)
    }
    
    // MARK: - HealthKit 运动会话管理
    private func startHKWorkoutSession(exerciseType: ExerciseType) {
        guard settings.healthKitSyncEnabled else { return }
        
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = exerciseType.hkWorkoutType
            configuration.locationType = .indoor
            
            hkSessionDelegate = WorkoutSessionDelegate(dataManager: self)
            hkWorkoutSession = try HKWorkoutSession(healthStore: healthKitManager.healthStore, configuration: configuration)
            hkWorkoutSession?.delegate = hkSessionDelegate
            
            hkWorkoutSession?.startActivity(with: Date())
            print("🏃‍♂️ 开始 HealthKit 运动会话")
        } catch {
            print("❌ 创建 HealthKit 运动会话失败: \(error)")
        }
    }
    
    private func endHKWorkoutSession() {
        guard let session = hkWorkoutSession else { return }
        
        session.end()
        hkWorkoutSession = nil
        hkSessionDelegate = nil
        print("🏁 结束 HealthKit 运动会话")
    }
}

// MARK: - HKWorkoutSessionDelegate
class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate {
    private weak var dataManager: DataManager?
    
    init(dataManager: DataManager) {
        self.dataManager = dataManager
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("🔄 运动会话状态变化: \(fromState) -> \(toState)")
        
        switch toState {
        case .notStarted:
            print("📋 运动会话未开始")
        case .running:
            print("🏃‍♂️ 运动会话开始运行")
        case .ended:
            print("🏁 运动会话结束")
        case .paused:
            print("⏸️ 运动会话暂停")
        case .prepared:
            print("📋 运动会话准备就绪")
        case .stopped:
            print("🛑 运动会话停止")
        @unknown default:
            print("❓ 未知的运动会话状态: \(toState)")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("❌ 运动会话失败: \(error)")
    }
}
