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
    
    @Published private(set) var currentSession: WorkoutSession?
    @Published private(set) var requiresWorkoutRecovery = false
    @Published private(set) var canResumeRecoveredWorkout = false
    @Published private(set) var requiresDraftRecovery = false
    @Published var workoutHistory: [WorkoutHistory] = [] {
        didSet { NotificationManager.shared.scheduleDailyReminder() }
    }
    var trainingDates: [Date] { workoutHistory.filter { $0.totalReps > 0 }.map(\.date) }
    @Published var settings = AppSettings.shared
    @Published var isFirstLaunch = true
    @Published var countingMessage = String(localized: "检测中")
    @Published var completedWorkout: WorkoutHistory?
    @Published var completedWholeWorkout: WorkoutReport?
    @Published var wholeWorkoutIdlePrompt = false
    @Published var wholeWorkoutError: String?
    private var wholeIdleTask: Task<Void, Never>?
    private var idleAcknowledgedAt = Date.distantPast
    private var liveHealthObservation: AnyCancellable?
    @Published var saveError: String?
    @Published private(set) var isSavingWorkout = false
    @Published var countingFailed = false
    private var sensorWallAnchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    private var diagnostics: WorkoutDiagnostics?
    private let historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchHistory/history-v1.json")
    private var historyReadFailed = false
    private let draftStore = WatchWorkoutDraftStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchHistory/current-workout-v1.json"))
    private var draftWriteFailed = false
    private var checkpointedSession: WorkoutSession?
    private let feedbackArchive = WorkoutFeedbackArchive(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkoutFeedback"))
    let timelineArchive = WorkoutTimelineArchive(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkoutTimelines"))
    let reportSensorArchive = WorkoutReportSensorArchive(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WatchHistory/WholeWorkoutSamples"))
    private var automaticBenchCycles: [UUID: BenchCycle] = [:]
    private var automaticSquatCycles: [UUID: SquatCycle] = [:]
    private var removedBenchIDs: Set<UUID> = []
    
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
        loadCurrentWorkout()
        setupMotionDetector()
        setupHealthKit()
    }
    
    private func setupMotionDetector() {
        motionDetector.onRepDetected = { [weak self] repetition, isLive in
            guard let self, !self.requiresWorkoutRecovery, !self.isWholeWorkoutPaused,
                  var session = self.currentSession, session.isActive,
                  session.exerciseType == repetition.exercise else { return }
            let id = UUID()
            let cycle: (start: Double, end: Double)?
            switch repetition {
            case .benchPress(let value):
                self.automaticBenchCycles[id] = value
                cycle = (value.start, value.end)
            case .squat(let value):
                self.automaticSquatCycles[id] = value
                cycle = (value.start, value.end)
            case .deadlift:
                cycle = nil
            }
            var rep = RepRecord(id: id, timestamp: cycle.map { Date(timeIntervalSince1970: self.sensorWallAnchor + $0.end) } ?? Date(), weight: session.weight)
            rep.startedAt = cycle.map { Date(timeIntervalSince1970: self.sensorWallAnchor + $0.start) }
            session.repRecords.append(rep)
            switch repetition {
            case .benchPress:
                let cycles = session.repRecords.compactMap { self.automaticBenchCycles[$0.id] }
                session.activeDuration = cycles.count == session.totalReps ? ActionTiming.total(cycles.map {
                    ActionTiming.Interval(start: $0.start, end: $0.end)
                }) : nil
            case .squat: session.activeDuration = self.squatDuration(for: session)
            case .deadlift: session.activeDuration = nil
            }
            // Publish and give feedback before potentially slow checkpoint I/O.
            self.currentSession = session
            RepCompletionFeedback.play(isLive: isLive) { self.diagnostics?.raw.markFeedback(at: $0) }
            self.checkpoint(session)
        }
        motionDetector.onBenchAnalysis = { [weak self] in self?.applyBenchAnalysis($0) }
        motionDetector.onCountingError = { [weak self] in self?.reportCountingFailure($0) }
        motionDetector.onActiveDuration = { [weak self] duration in
            guard let self, !self.requiresWorkoutRecovery, var session = self.currentSession, session.isActive else { return }
            let cycles = session.repRecords.compactMap { self.automaticBenchCycles[$0.id] }
            // A manually added rep has no measured start. Removed false positives
            // must not keep contributing time after the next analysis update.
            session.activeDuration = duration != nil && cycles.count == session.totalReps ? ActionTiming.total(cycles.map {
                ActionTiming.Interval(start: $0.start, end: $0.end)
            }) : nil
            self.updateCurrentSession(session)
        }
    }

    private func applyBenchAnalysis(_ result: BenchAnalysis) {
        guard !requiresWorkoutRecovery, var session = currentSession, session.isActive, session.exerciseType == .benchPress else { return }
        if result.status == "insufficient_data" {
            countingFailed = true
            countingMessage = String(localized: "采样中断，请手动核对")
            return
        }
        // A one-rep set may have a valid live completion while V8 still needs a
        // second cycle to qualify a bout. Unknown is not a zero-count correction.
        guard result.count != nil else { return }
        let message = String(localized: "估计中 · 结束时核准")
        if !countingFailed, countingMessage != message { countingMessage = message }
        var activeIDs: Set<UUID> = []
        let anchor = sensorWallAnchor
        for cycle in result.cycles {
            let match = automaticBenchCycles.lazy.filter {
                !activeIDs.contains($0.key) && abs($0.value.turn - cycle.turn) < 0.75
            }.min { abs($0.value.turn - cycle.turn) < abs($1.value.turn - cycle.turn) }
            let id = match?.key ?? UUID()
            automaticBenchCycles[id] = cycle
            activeIDs.insert(id)
            // Keep manual additions, manual removals, and each existing rep's weight.
            if !removedBenchIDs.contains(id) {
                let date = Date(timeIntervalSince1970: anchor + cycle.end)
                if let index = session.repRecords.firstIndex(where: { $0.id == id }) {
                    session.repRecords[index] = RepRecord(id: id, timestamp: date, weight: session.repRecords[index].weight)
                    session.repRecords[index].startedAt = Date(timeIntervalSince1970: anchor + cycle.start)
                } else {
                    var rep = RepRecord(id: id, timestamp: date, weight: session.weight)
                    rep.startedAt = Date(timeIntervalSince1970: anchor + cycle.start)
                    session.repRecords.append(rep)
                }
            }
        }
        session.repRecords.removeAll { automaticBenchCycles[$0.id] != nil && !activeIDs.contains($0.id) }
        session.repRecords.sort { $0.timestamp < $1.timestamp }
        updateCurrentSession(session)
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
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do { workoutHistory = try JSONDecoder().decode([WorkoutHistory].self, from: Data(contentsOf: historyURL)) }
            catch { historyReadFailed = true; saveError = String(localized: "训练记录读取失败，请重新打开 App") }
        } else if let historyData = userDefaults.data(forKey: historyKey) {
            do { workoutHistory = try JSONDecoder().decode([WorkoutHistory].self, from: historyData) }
            catch { historyReadFailed = true; saveError = String(localized: "训练记录读取失败，请重新打开 App") }
        }

        // 加载设置
        if let settingsData = userDefaults.data(forKey: settingsKey),
           let loadedSettings = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
            settings = loadedSettings
        }
    }
    
    @discardableResult
    private func persistHistory(_ history: [WorkoutHistory]) -> Bool {
        guard !historyReadFailed else {
            saveError = String(localized: "训练记录读取失败，请重新打开 App")
            return false
        }
        do {
            let data = try JSONEncoder().encode(history)
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: historyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Keep the original defaults snapshot as a migration fallback.
            return true
        } catch {
            saveError = String(localized: "保存失败，训练仍在本页，请重试")
            WKInterfaceDevice.current().play(.failure)
            return false
        }
    }

    private func saveSettings() {
        if let settingsData = try? JSONEncoder().encode(settings) {
            userDefaults.set(settingsData, forKey: settingsKey)
        }
    }

    private func loadCurrentWorkout() {
        do {
            guard let draft = try draftStore.load() else { return }
            // History commits first. A stale checkpoint after a cleanup failure
            // must never restore a second copy of an already-saved workout.
            if workoutHistory.contains(where: { $0.id == draft.session.id }) {
                try draftStore.clear()
                return
            }
            var session = draft.session
            canResumeRecoveredWorkout = session.endTime == nil
            session.pauseForRecovery(at: draft.checkpoint)
            currentSession = session
            requiresWorkoutRecovery = true
        } catch {
            requiresDraftRecovery = true
            saveError = String(localized: "未完成训练读取失败")
        }
    }

    func retryWorkoutDraft() {
        guard requiresDraftRecovery else { return }
        requiresDraftRecovery = false
        saveError = nil
        loadCurrentWorkout()
    }

    func resetUnreadableWorkoutDraft() {
        guard requiresDraftRecovery else { return }
        do {
            try draftStore.preserveForRecovery()
            checkpointedSession = nil
            draftWriteFailed = false
            requiresDraftRecovery = false
            saveError = nil
        } catch {
            saveError = String(localized: "原文件保留失败，请重试")
        }
    }

    private func matchesCheckpoint(_ session: WorkoutSession) -> Bool {
        guard !draftWriteFailed, let saved = checkpointedSession,
           saved.id == session.id, saved.exerciseType == session.exerciseType,
           saved.startTime == session.startTime, saved.endTime == session.endTime,
           saved.weight == session.weight, saved.activeDuration == session.activeDuration,
           saved.durationBeforeResume == session.durationBeforeResume, saved.resumedAt == session.resumedAt,
           saved.wholeDraft == session.wholeDraft,
           saved.repRecords.count == session.repRecords.count,
           zip(saved.repRecords, session.repRecords).allSatisfy({ pair in
               pair.0.id == pair.1.id && pair.0.timestamp == pair.1.timestamp && pair.0.weight == pair.1.weight && pair.0.startedAt == pair.1.startedAt
           }) else { return false }
        return true

    }

    @discardableResult
    private func checkpoint(_ session: WorkoutSession) -> Bool {
        if matchesCheckpoint(session) { return true }
        do {
            try draftStore.save(session)
            checkpointedSession = session
            draftWriteFailed = false
            return true
        } catch {
            if !draftWriteFailed {
                saveError = String(localized: "训练备份失败，请保持 App 打开并重试保存")
                WKInterfaceDevice.current().play(.failure)
            }
            draftWriteFailed = true
            return false
        }
    }

    private func updateCurrentSession(_ session: WorkoutSession) {
        // Prefix replays frequently repeat the same stable result.
        guard !matchesCheckpoint(session) else { return }
        // Keep the newest repetitions in memory even when storage is full.
        currentSession = session
        checkpoint(session)
    }

    func updateCurrentWeight(_ weight: Double) {
        guard !isSavingWorkout, !requiresWorkoutRecovery, weight.isFinite, weight >= 0, var session = currentSession, session.isActive else { return }
        session.weight = weight
        updateCurrentSession(session)
    }

    func resumeRecoveredWorkout() {
        guard !isSavingWorkout else { return }
        guard requiresWorkoutRecovery, canResumeRecoveredWorkout, var session = currentSession else { return }
        if var draft = session.wholeDraft {
            draft.completedSets += WorkoutReport.group(session.repRecords, exercise: session.exerciseType)
            draft.pauses.append(.init(startedAt: draft.pausedAt ?? session.endTime ?? Date(), endedAt: Date()))
            draft.pausedAt = nil; draft.metricsInterrupted = true
            draft.segmentStartedAt = Date(); draft.segmentID = UUID()
            session.wholeDraft = draft; session.repRecords = []
        }
        session.resume()
        guard checkpoint(session) else { return }
        currentSession = session
        requiresWorkoutRecovery = false
        canResumeRecoveredWorkout = false
        countingFailed = false
        countingMessage = session.exerciseType == .benchPress ? String(localized: "估计中 · 结束时核准") : String(localized: "检测中")
        automaticBenchCycles = [:]; automaticSquatCycles = [:]; removedBenchIDs = []
        // Previous raw samples are unavailable after a restart. A resumed set
        // must not offer a partial recording as feedback for the full workout.
        diagnostics = nil
        if session.wholeDraft == nil { startHKWorkoutSession(exerciseType: session.exerciseType) }
        else {
            startWholeIdleMonitor()
            wholeWorkoutError = String(localized: "训练已恢复，健康数据从现在继续")
            isSavingWorkout = true
            Task { @MainActor in
                defer { isSavingWorkout = false }
                observeLiveHealth()
                if settings.healthKitSyncEnabled {
                    do {
                        try await healthKitManager.liveWorkout.begin(id: session.id, startDate: Date())
                        if var active = currentSession, active.id == session.id {
                            active.wholeDraft?.healthSessionStarted = true; updateCurrentSession(active)
                        }
                    } catch { wholeWorkoutError = error.localizedDescription }
                }
            }
        }
        sensorWallAnchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        motionDetector.configureForExercise(session.exerciseType)
        motionDetector.startDetection()
    }

    func discardRecoveredWorkout() {
        guard requiresWorkoutRecovery else { return }
        resetCurrentWorkout()
    }

    func reportCountingFailure(_ message: String) {
        guard currentSession != nil else { return }
        countingMessage = message
        if !countingFailed { WKInterfaceDevice.current().play(.failure) }
        countingFailed = true
    }

    // MARK: - 锻炼会话管理
    func startWorkout(exerciseType: ExerciseType, weight: Double = 0.0, whole: Bool = false) {
        guard currentSession == nil else { return }
        guard !requiresDraftRecovery else {
            saveError = String(localized: "未完成训练读取失败")
            return
        }
        guard weight.isFinite, weight >= 0 else { return }
        completedWorkout = nil; saveError = nil; countingFailed = false
        automaticBenchCycles = [:]; automaticSquatCycles = [:]; removedBenchIDs = []
        countingMessage = exerciseType == .benchPress ? String(localized: "估计中 · 结束时核准") : String(localized: "检测中")
        if exerciseType == .deadlift { WKInterfaceDevice.current().play(.click) }
        var session = WorkoutSession(
            exerciseType: exerciseType,
            startTime: Date(),
            weight: weight
        )
        if whole { session.wholeDraft = WholeWorkoutDraft(id: session.id, startedAt: session.startTime, segmentID: UUID()) }
        guard checkpoint(session) else { return }
        currentSession = session
        
        let diagnostics = WorkoutDiagnostics()
        self.diagnostics = diagnostics
        motionDetector.onRawAcceleration = { diagnostics.raw.append($0) }
        motionDetector.onRawDeviceMotion = { diagnostics.raw.appendMotion($0) }
        motionDetector.onRawBenchAnalysis = { diagnostics.raw.setBenchAnalysis($0) }
        motionDetector.onRawRepDetected = { diagnostics.raw.markRep(at: $0) }

        // 创建 HealthKit 运动会话
        if !whole { startHKWorkoutSession(exerciseType: exerciseType) }
        
        // 自动开始运动检测
        sensorWallAnchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        motionDetector.configureForExercise(exerciseType)
        motionDetector.startDetection()
    }
    
    func addRep() {
        guard !isSavingWorkout, !isWholeWorkoutPaused else { return }
        recordDetectedRep()
    }

    private func recordDetectedRep() {
        guard !requiresWorkoutRecovery, var session = currentSession, session.isActive else { return }
        session.addRep()
        session.activeDuration = nil
        updateCurrentSession(session)
    }
    
    func removeRep() {
        guard !isSavingWorkout, !isWholeWorkoutPaused, !requiresWorkoutRecovery, var session = currentSession, session.isActive else { return }
        if let id = session.repRecords.last?.id, automaticBenchCycles[id] != nil { removedBenchIDs.insert(id) }
        session.removeRep()
        session.activeDuration = nil
        if session.exerciseType == .squat { session.activeDuration = squatDuration(for: session) }
        updateCurrentSession(session)
    }

    private func squatDuration(for session: WorkoutSession) -> TimeInterval? {
        let cycles = session.repRecords.compactMap { automaticSquatCycles[$0.id] }
        guard !cycles.isEmpty, cycles.count == session.totalReps else { return nil }
        return ActionTiming.total(cycles.map { ActionTiming.Interval(start: $0.start, end: $0.end) })
    }
    
    @discardableResult
    @MainActor
    func endWorkout() async -> Bool {
        if isWholeWorkout { return await finishWholeWorkout() }
        guard !isSavingWorkout, !historyReadFailed else { return false }
        isSavingWorkout = true
        defer { isSavingWorkout = false }
        saveError = nil
        // Stop first so the finalized count and diagnostic events describe the same set.
        await motionDetector.stopDetectionAsync()
        guard var session = currentSession else { return false }
        if session.endTime == nil { session.endSession() }
        updateCurrentSession(session)
        endHKWorkoutSession()
        let history = WorkoutHistory(id: session.id, date: session.startTime,
            exerciseType: session.exerciseType, totalReps: session.totalReps,
            maxWeight: session.repRecords.map(\.weight).max() ?? session.weight,
            duration: session.duration ?? 0, activeDuration: session.activeDuration,
            totalWeight: session.repRecords.reduce(0) { $0 + $1.weight })
        let next = [history] + workoutHistory.filter { $0.id != history.id }
        let diagnostics = self.diagnostics, timelineArchive = self.timelineArchive
        let feedbackArchive = self.feedbackArchive, historyURL = self.historyURL
        let oldHistory = workoutHistory
        do {
            let warning = try await WorkoutFileIO.shared.perform { () -> String? in
                if let timeline = try diagnostics?.timeline(for: history) { try timelineArchive.retain(timeline) }
                let data = try JSONEncoder().encode(next)
                try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: historyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var canPrune = true
                do { try Self.prepareWorkoutTimelines(oldHistory, timelineArchive: timelineArchive, feedbackArchive: feedbackArchive) }
                catch { canPrune = false }
                do { try feedbackArchive.retain(history, recording: diagnostics?.recording(for: history), prune: canPrune) }
                catch { return String(localized: "训练已保存，但反馈采样保存失败") }
                return canPrune ? nil : String(localized: "部分时间轴读取失败，请重试同步")
            }
            workoutHistory = next
            saveError = warning
        } catch {
            saveError = String(localized: "保存失败，训练仍在本页，请重试")
            WKInterfaceDevice.current().play(.failure)
            return false
        }
        self.diagnostics = nil
        motionDetector.onRawAcceleration = nil; motionDetector.onRawDeviceMotion = nil
        motionDetector.onRawBenchAnalysis = nil; motionDetector.onRawRepDetected = nil
        currentSession = nil
        checkpointedSession = nil
        requiresWorkoutRecovery = false
        canResumeRecoveredWorkout = false
        try? draftStore.clear()
        completedWorkout = history
        WKInterfaceDevice.current().play(.success)
        #if DEBUG || GYMCOUNT_CAPTURE
        Task { @MainActor in WatchCaptureLink.shared.syncWorkouts() }
        #endif
        if settings.healthKitSyncEnabled && settings.autoSyncToHealthKit {
            Task { await syncWorkoutToHealthKit(history) }
        }
        return true
    }

    func resetCurrentWorkout() {
        guard !isSavingWorkout else { return }
        motionDetector.stopDetection()
        do { try draftStore.clear() }
        catch {
            saveError = String(localized: "未能放弃训练，请重试")
            return
        }
        endHKWorkoutSession()
        wholeIdleTask?.cancel(); wholeIdleTask = nil
        let discardedID = currentSession?.id
        if isWholeWorkout, let discardedID {
            removeWholeWorkoutSamples([discardedID], failure: String(localized: "训练已放弃，采样清理失败"))
        }
        Task { @MainActor in if let discardedID { healthKitManager.liveWorkout.discard(id: discardedID) } }
        diagnostics = nil
        motionDetector.onRawAcceleration = nil; motionDetector.onRawDeviceMotion = nil
        motionDetector.onRawBenchAnalysis = nil; motionDetector.onRawRepDetected = nil
        currentSession = nil
        checkpointedSession = nil
        requiresWorkoutRecovery = false
        canResumeRecoveredWorkout = false
    }
    
    // MARK: - 历史记录管理
    func prepareWorkoutTimelines() async throws {
        let history = workoutHistory, archive = timelineArchive, feedback = feedbackArchive
        try await WorkoutFileIO.shared.perform {
            try Self.prepareWorkoutTimelines(history, timelineArchive: archive, feedbackArchive: feedback)
        }
    }

    private static func prepareWorkoutTimelines(_ history: [WorkoutHistory], timelineArchive: WorkoutTimelineArchive, feedbackArchive: WorkoutFeedbackArchive) throws {
        // Older versions kept real samples only in the bounded feedback outbox.
        // Preserve those that still exist, without inventing a missing time anchor.
        var failure: Error?
        for history in history {
            if FileManager.default.fileExists(atPath: timelineArchive.fileURL(history.id).path) { continue }
            let url = feedbackArchive.folder.appendingPathComponent(history.id.uuidString + ".json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let entry = try feedbackArchive.load(history.id)
                guard let recording = entry.recording else { continue }
                let source = WorkoutSync.Record(id: history.id, date: history.date, exercise: history.exerciseType.rawValue,
                    totalReps: history.totalReps, maxWeight: history.maxWeight, duration: history.duration,
                    activeDuration: history.activeDuration, totalWeight: history.totalWeight)
                try timelineArchive.retain(WorkoutTimeline(captureData: recording, source: source))
            } catch { failure = error }
        }
        if let failure { throw failure }
    }

    func deleteHistoryItem(_ item: WorkoutHistory) {
        guard !isSavingWorkout else { return }
        let next = workoutHistory.filter { $0.id != item.id }
        guard persistHistory(next) else { return }
        workoutHistory = next
        try? feedbackArchive.remove(item.id)
        removeWholeWorkoutSamples([item.id], failure: String(localized: "记录已删除，时间轴清理失败"))
        do { try timelineArchive.remove(item.id) }
        catch { saveError = String(localized: "记录已删除，时间轴清理失败") }
    }
    
    func clearAllHistory() {
        guard !isSavingWorkout else { return }
        guard persistHistory([]) else { return }
        let ids = workoutHistory.map(\.id)
        workoutHistory = []
        for id in ids { try? feedbackArchive.remove(id) }
        removeWholeWorkoutSamples(ids, failure: String(localized: "记录已删除，时间轴清理失败"))
        do { for id in ids { try timelineArchive.remove(id) } }
        catch { saveError = String(localized: "记录已删除，时间轴清理失败") }
    }
    
    private func removeWholeWorkoutSamples(_ ids: [UUID], failure: String) {
        let root = historyURL.deletingLastPathComponent().appendingPathComponent("WholeWorkoutSamples")
        Task { @MainActor in
            #if DEBUG || GYMCOUNT_CAPTURE
            WatchCaptureLink.shared.cancelReportSensors(workoutIDs: Set(ids))
            #endif
            do {
                try await WorkoutFileIO.shared.perform {
                    for id in ids {
                        let url = root.appendingPathComponent(id.uuidString)
                        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    }
                }
            } catch { saveError = failure }
        }
    }

    // MARK: - 设置管理
    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        saveSettings()
        
        // 如果启用了 HealthKit 同步，请求权限
        if settings.healthKitSyncEnabled {
            Task {
                await healthKitManager.requestAuthorization()
            }
        }
    }
    
    // MARK: - 获取指定周的日期信息
    func getWeekInfo(for weekStartDate: Date) -> (startDate: Date, endDate: Date, title: String) {
        let calendar = Calendar.current
        
        let interval = WatchWorkoutWeek.interval(containing: weekStartDate, calendar: calendar)
        let weekStart = interval.start
        let weekEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        
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
    @MainActor
    func syncWorkoutToHealthKit(_ workoutHistory: WorkoutHistory) async {
        guard settings.healthKitSyncEnabled else {
            print("❌ HealthKit 同步已禁用")
            return
        }
        
        // 刷新授权状态
        healthKitManager.refreshAuthorizationStatus()
        
        await healthKitManager.saveWorkoutToHealthKit(workoutHistory)
    }
    
    @MainActor
    func syncAllWorkoutsToHealthKit(enabled: Bool? = nil) async {
        guard enabled ?? settings.healthKitSyncEnabled else {
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
        return currentSession == nil && !requiresDraftRecovery
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
            reportCountingFailure(String(localized: "训练会话启动失败，请保持 App 打开"))
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

// MARK: - Whole training lifecycle
extension DataManager {
    var isWholeWorkout: Bool { currentSession?.wholeDraft != nil }
    var isWholeWorkoutPaused: Bool { currentSession?.wholeDraft?.pausedAt != nil }
    private var currentWholeSets: [WorkoutReport.SetRecord] {
        guard let session = currentSession else { return [] }
        return WorkoutReport.group(session.repRecords, exercise: session.exerciseType)
    }
    var currentGroupNumber: Int { (currentSession?.wholeDraft?.completedSets.count ?? 0) + max(1, currentWholeSets.count) }
    var currentGroupReps: Int { currentWholeSets.last?.totalReps ?? 0 }
    var wholeTotalReps: Int { (currentSession?.wholeDraft?.completedSets.reduce(0) { $0 + $1.totalReps } ?? 0) + (currentSession?.totalReps ?? 0) }
    var restStartedAt: Date? {
        guard !isWholeWorkoutPaused else { return nil }
        let last = currentSession?.repRecords.last?.timestamp ?? currentSession?.wholeDraft?.completedSets.last?.endedAt
        if currentSession?.repRecords.isEmpty == true { return last }
        return last.flatMap { Date().timeIntervalSince($0) >= 15 ? $0 : nil }
    }

    @MainActor @discardableResult
    func startWholeWorkout(exerciseType: ExerciseType, weight: Double) async -> Bool {
        guard !isSavingWorkout, currentSession == nil else { return false }
        guard weight.isFinite, (0...500).contains(weight) else {
            wholeWorkoutError = String(localized: "重量须在 0–500 公斤之间")
            return false
        }
        isSavingWorkout = true; defer { isSavingWorkout = false }
        completedWholeWorkout = nil; wholeWorkoutError = nil
        startWorkout(exerciseType: exerciseType, weight: weight, whole: true)
        guard let session = currentSession, session.wholeDraft != nil else { return false }
        startWholeIdleMonitor()
        observeLiveHealth()
        if settings.healthKitSyncEnabled {
            do {
                try await healthKitManager.liveWorkout.begin(id: session.id, startDate: session.startTime)
                if var active = currentSession, active.id == session.id {
                    active.wholeDraft?.healthSessionStarted = true; updateCurrentSession(active)
                }
            }
            catch { wholeWorkoutError = error.localizedDescription }
        }
        return true
    }

    @MainActor
    private func observeLiveHealth() {
        liveHealthObservation = healthKitManager.liveWorkout.$errorMessage.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] error in
                guard let self, self.isWholeWorkout, let error,
                      self.healthKitManager.liveWorkout.workoutID == self.currentSession?.id else { return }
                self.wholeWorkoutError = error
            }
    }

    private var canChangeWholeWorkout: Bool {
        isWholeWorkout && currentSession?.isActive == true && currentSession?.wholeDraft?.pendingReport == nil && !requiresWorkoutRecovery
    }

    private func startWholeIdleMonitor() {
        wholeIdleTask?.cancel(); idleAcknowledgedAt = Date(); wholeWorkoutIdlePrompt = false
        wholeIdleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.isWholeWorkout else { return }
                let last = self.currentSession?.repRecords.last?.timestamp ?? self.currentSession?.wholeDraft?.completedSets.last?.endedAt ?? self.idleAcknowledgedAt
                if !self.isWholeWorkoutPaused, Date().timeIntervalSince(max(last, self.idleAcknowledgedAt)) >= 300, !self.wholeWorkoutIdlePrompt {
                    self.wholeWorkoutIdlePrompt = true
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }

    func continueWholeWorkoutAfterIdle() { idleAcknowledgedAt = Date(); wholeWorkoutIdlePrompt = false }

    /// Persist the finalized segment before resetting the detector or changing exercise.
    @MainActor
    private func closeWholeSegment() async -> Bool {
        await motionDetector.stopDetectionAsync()
        guard var session = currentSession, var draft = session.wholeDraft else { return false }
        let sets = WorkoutReport.group(session.repRecords, exercise: session.exerciseType)
        // Keep each real sensor segment even though the combined report uses a
        // different multi-exercise timeline. Never label the final block as the full session.
        if let diagnostics {
            let start = draft.segmentStartedAt ?? session.startTime
            if draft.segmentID == nil {
                draft.segmentID = UUID(); session.wholeDraft = draft
                guard checkpoint(session) else { return false }
                currentSession = session
            }
            let segment = WorkoutHistory(id: draft.segmentID!, date: start,
                exerciseType: session.exerciseType, totalReps: session.totalReps,
                maxWeight: session.repRecords.map(\.weight).max() ?? session.weight,
                duration: max(0, Date().timeIntervalSince(start)), activeDuration: session.activeDuration,
                totalWeight: session.repRecords.reduce(0) { $0 + $1.weight })
            let url = reportSensorArchive.fileURL(workoutID: draft.id, segmentID: segment.id)
            do {
                try await WorkoutFileIO.shared.perform {
                    if let timeline = try diagnostics.timeline(for: segment) {
                        let data = try JSONEncoder().encode(timeline)
                        guard data.count <= WorkoutTimeline.maximumFileBytes else { throw WorkoutTimeline.Failure.invalid }
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let count = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension == "json" }.count
                        guard count < WorkoutReportSensors.maximumSegments || FileManager.default.fileExists(atPath: url.path) else { throw WorkoutTimeline.Failure.invalid }
                        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                }
            } catch {
                reportCountingFailure(String(localized: "保存失败，计数已暂停，请重试"))
                saveError = String(localized: "采样保存失败，请重试")
                return false
            }
        }
        draft.completedSets += sets
        draft.segmentStartedAt = Date()
        draft.segmentID = UUID()
        session.wholeDraft = draft; session.repRecords = []; session.activeDuration = nil
        guard checkpoint(session) else { reportCountingFailure(String(localized: "保存失败，计数已暂停，请重试")); return false }
        currentSession = session
        automaticBenchCycles = [:]; automaticSquatCycles = [:]; removedBenchIDs = []
        diagnostics = nil
        motionDetector.onRawAcceleration = nil; motionDetector.onRawDeviceMotion = nil
        motionDetector.onRawBenchAnalysis = nil; motionDetector.onRawRepDetected = nil
        return true
    }

    private func restartWholeDetection() {
        guard let session = currentSession, !isWholeWorkoutPaused, !requiresWorkoutRecovery else { return }
        let diagnostics = WorkoutDiagnostics(); self.diagnostics = diagnostics
        motionDetector.onRawAcceleration = { diagnostics.raw.append($0) }
        motionDetector.onRawDeviceMotion = { diagnostics.raw.appendMotion($0) }
        motionDetector.onRawBenchAnalysis = { diagnostics.raw.setBenchAnalysis($0) }
        motionDetector.onRawRepDetected = { diagnostics.raw.markRep(at: $0) }
        countingFailed = false
        countingMessage = session.exerciseType == .benchPress ? String(localized: "估计中 · 结束时核准") : String(localized: "检测中")
        sensorWallAnchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        motionDetector.configureForExercise(session.exerciseType)
        motionDetector.startDetection()
        continueWholeWorkoutAfterIdle()
    }

    @MainActor @discardableResult
    func nextWholeWorkoutSet() async -> Bool {
        guard canChangeWholeWorkout, !isWholeWorkoutPaused, !isSavingWorkout else { return false }
        isSavingWorkout = true; defer { isSavingWorkout = false }
        guard await closeWholeSegment() else { return false }
        restartWholeDetection()
        return true
    }

    @MainActor @discardableResult
    func switchWholeWorkoutExercise(exerciseType: ExerciseType, weight: Double) async -> Bool {
        guard canChangeWholeWorkout, !isSavingWorkout, weight.isFinite, (0...500).contains(weight) else { return false }
        isSavingWorkout = true; defer { isSavingWorkout = false }
        guard await closeWholeSegment(), var session = currentSession else { return false }
        session.exerciseType = exerciseType; session.weight = weight
        guard checkpoint(session) else { reportCountingFailure(String(localized: "保存失败，计数已暂停，请重试")); return false }
        currentSession = session
        restartWholeDetection()
        return true
    }

    @MainActor
    func pauseWholeWorkout() async {
        guard canChangeWholeWorkout, !isWholeWorkoutPaused, !isSavingWorkout else { return }
        isSavingWorkout = true; defer { isSavingWorkout = false }
        guard await closeWholeSegment(), var session = currentSession else { return }
        session.wholeDraft?.pausedAt = Date()
        guard checkpoint(session) else { reportCountingFailure(String(localized: "保存失败，计数已暂停，请重试")); return }
        currentSession = session
        healthKitManager.liveWorkout.pause()
    }

    @MainActor
    func resumeWholeWorkout() async {
        guard isWholeWorkoutPaused, !isSavingWorkout, !requiresWorkoutRecovery,
              var session = currentSession, let pause = session.wholeDraft?.pausedAt else { return }
        session.wholeDraft?.pauses.append(.init(startedAt: pause, endedAt: Date()))
        session.wholeDraft?.pausedAt = nil
        session.wholeDraft?.segmentStartedAt = Date()
        session.wholeDraft?.segmentID = UUID()
        guard checkpoint(session) else { return }
        currentSession = session
        healthKitManager.liveWorkout.resume()
        restartWholeDetection()
    }

    @MainActor @discardableResult
    func finishWholeWorkout() async -> Bool {
        guard isWholeWorkout, !isSavingWorkout, !historyReadFailed else { return false }
        isSavingWorkout = true; defer { isSavingWorkout = false }
        saveError = nil; wholeWorkoutIdlePrompt = false
        if currentSession?.wholeDraft?.pendingReport == nil {
            guard await closeWholeSegment(), var session = currentSession, var draft = session.wholeDraft else { return false }
            let end = requiresWorkoutRecovery ? (session.endTime ?? Date()) : Date()
            if let pausedAt = draft.pausedAt { draft.pauses.append(.init(startedAt: pausedAt, endedAt: end)); draft.pausedAt = nil }
            var report = WorkoutReport(startedAt: draft.startedAt, endedAt: end, sets: draft.completedSets, pauses: draft.pauses)
            if draft.healthSessionStarted == true && !requiresWorkoutRecovery {
                do {
                    let result = try await healthKitManager.liveWorkout.finish(at: end)
                    report.activeEnergyKcal = result.activeEnergyKilocalories
                    report.measuredAverageHeartRate = result.averageHeartRate
                    report.measuredMaximumHeartRate = result.maximumHeartRate
                    report.healthWorkoutID = result.workoutUUID
                    report.heartRates = result.heartRateSamples.map { .init(date: $0.date, bpm: $0.beatsPerMinute) }
                    report.metricsComplete = !draft.metricsInterrupted
                } catch {
                    let result = healthKitManager.liveWorkout.snapshot()
                    report.activeEnergyKcal = result.activeEnergyKilocalories
                    report.measuredAverageHeartRate = result.averageHeartRate
                    report.measuredMaximumHeartRate = result.maximumHeartRate
                    report.heartRates = result.heartRateSamples.map { .init(date: $0.date, bpm: $0.beatsPerMinute) }
                }
            }
            report.heartRates = report.heartRates.filter { $0.date >= report.startedAt && $0.date <= report.endedAt }
            do { try report.validate() }
            catch { saveError = String(localized: "训练数据校验失败，请重试"); return false }
            draft.pendingReport = report; session.wholeDraft = draft; session.endTime = end
            currentSession = session
            guard checkpoint(session) else { return false }
        }
        guard let session = currentSession, let draft = session.wholeDraft, let report = draft.pendingReport else { return false }
        let history = WorkoutHistory(id: draft.id, date: report.startedAt,
            exerciseType: report.sets.first?.exercise ?? session.exerciseType, totalReps: report.totalReps,
            maxWeight: report.maxWeight, duration: report.duration, activeDuration: report.activeDuration,
            totalWeight: report.totalWeight, workoutReport: report)
        let next = [history] + workoutHistory.filter { $0.id != history.id }
        let url = historyURL
        do {
            try await WorkoutFileIO.shared.perform {
                let data = try JSONEncoder().encode(next)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { saveError = String(localized: "保存失败，训练仍在本页，请重试"); return false }
        workoutHistory = next
        currentSession = nil; checkpointedSession = nil
        requiresWorkoutRecovery = false; canResumeRecoveredWorkout = false
        wholeIdleTask?.cancel(); wholeIdleTask = nil
        try? draftStore.clear()
        completedWorkout = nil; completedWholeWorkout = report
        if draft.healthSessionStarted == true && report.healthWorkoutID == nil {
            wholeWorkoutError = String(localized: "训练已保存，健康记录未写入")
        }
        WKInterfaceDevice.current().play(.success)
        #if DEBUG || GYMCOUNT_CAPTURE
        WatchCaptureLink.shared.syncWorkouts()
        #endif
        return true
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
        DispatchQueue.main.async { [weak self] in
            self?.dataManager?.reportCountingFailure(String(localized: "训练会话中断，请核对次数"))
        }
    }
}
