//
//  MotionDetector.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import CoreMotion
import Combine
import WatchKit
import os

// Detection owns the movement decision; consumers own records and presentation.
enum DetectedRepetition {
    case benchPress(BenchCycle)
    case squat(SquatCycle)
    case deadlift
    case upperBody(ExerciseType, UpperBodyCycle)

    var exercise: ExerciseType {
        switch self {
        case .benchPress: return .benchPress
        case .squat: return .squat
        case .deadlift: return .deadlift
        case .upperBody(let exercise, _): return exercise
        }
    }
}

enum RepCompletionFeedback {
    static func play(isLive: Bool, record: (Double) -> Void) {
        guard isLive else { return }
        record(ProcessInfo.processInfo.systemUptime)
        WKInterfaceDevice.current().play(.directionUp)
    }
}

class MotionDetector: ObservableObject {
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    var onRawAcceleration: ((CMAccelerometerData) -> Void)?
    var onRawRepDetected: ((Double?) -> Void)?
    var onRawDeviceMotion: ((CMDeviceMotion) -> Void)?
    var onRawBenchAnalysis: ((BenchAnalysis) -> Void)?
    
    // 运动检测器
    private var benchPressDetector: BenchPressDetector?
    private var squatDetector: SquatDetector?
    private var deadliftDetector: DeadliftDetector?
    private var upperBodyDetector: UpperBodyDetector?
    private var currentExerciseType: ExerciseType = .benchPress
    private var countsRepetitions = true
    private let lifecycleLock = NSLock()
    private var stopping = false
    private var runGeneration = UUID()
    private var isStopping: Bool {
        get { lifecycleLock.withLock { stopping } }
        set { lifecycleLock.withLock { stopping = newValue } }
    }
    private var generation: UUID {
        get { lifecycleLock.withLock { runGeneration } }
        set { lifecycleLock.withLock { runGeneration = newValue } }
    }
    private let lifecycleLog = Logger(subsystem: "com.flyingrtx.GymCount.watchkitapp", category: "MotionLifecycle")
    private var lastDeliveredRepTime: Double?
    
    @Published var isDetecting = false
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let sampleRate = 40.0 // 采样率
    
    var onBenchAnalysis: ((BenchAnalysis) -> Void)?
    var onCountingError: ((String) -> Void)?
    var onActiveDuration: ((TimeInterval?) -> Void)?
    var onRepDetected: ((DetectedRepetition, Bool) -> Void)?
    
    init() {
        setupMotionManager()
        setupDetectors()
    }
    
    deinit {
        stopDetection()
    }
    
    private func setupMotionManager() {
        motionManager.accelerometerUpdateInterval = 1.0 / sampleRate
        motionManager.deviceMotionUpdateInterval = 1.0 / sampleRate
    }
    
    private func setupDetectors() {
        // 初始化卧推检测器
        benchPressDetector = BenchPressDetector()
        benchPressDetector?.onAnalysis = { [weak self] result in
            self?.publishBenchAnalysis(result)
        }
        
        benchPressDetector?.onCompletion = { [weak self] cycle in
            self?.publishRepetition(.benchPress(cycle), sensorTime: cycle.end)
        }

        // 初始化深蹲检测器
        squatDetector = SquatDetector()
        squatDetector?.onRepDetected = { [weak self] time in
            self?.handleRepDetected(sensorTime: time)
        }
        
        // 初始化硬拉检测器
        deadliftDetector = DeadliftDetector()
        deadliftDetector?.onRepDetected = { [weak self] time in
            self?.handleRepDetected(sensorTime: time)
        }
    }
    
    func startDetection(countRepetitions: Bool = true) {
        guard !isDetecting else { return }
        guard motionManager.isAccelerometerAvailable else {
            onCountingError?(String(localized: "运动传感器不可用，请手动计数"))
            return
        }
        
        guard !countRepetitions || currentExerciseType == .deadlift || motionManager.isDeviceMotionAvailable else {
            onCountingError?(String(localized: "融合运动不可用，请手动计数"))
            return
        }
        generation = UUID()
        lastDeliveredRepTime = nil
        isStopping = false
        isDetecting = true
        countsRepetitions = countRepetitions
        repCount = 0
        lastRepTime = nil
        
        // 重置当前检测器
        resetCurrentDetector()
        
        let runID = generation
        // 使用后台队列来处理加速计数据，确保在屏幕变暗时仍能正常工作
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self, self.generation == runID else { return }
            guard let data else {
                if let error, self.shouldReportMotionError(error, stream: "accelerometer", runID: runID) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == runID, self.isDetecting else { return }
                        self.onCountingError?(String(localized: "运动采样中断，请手动核对"))
                    }
                }
                return 
            }
            
            // 在后台队列处理数据
            self.processAccelerometerData(data)
        }
        
        if countRepetitions && currentExerciseType != .deadlift {
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] data, error in
                guard let self, self.generation == runID else { return }
                guard let data else {
                    if let error, self.shouldReportMotionError(error, stream: "device_motion", runID: runID) {
                        switch self.currentExerciseType {
                        case .benchPress: self.benchPressDetector?.markInterrupted()
                        case .squat: self.squatDetector?.markInterrupted()
                        case .overheadPress, .barbellRow, .bicepCurl: self.upperBodyDetector?.markInterrupted()
                        case .deadlift: break
                        }
                        DispatchQueue.main.async {
                            guard self.generation == runID, self.isDetecting else { return }
                            self.onCountingError?(String(localized: "运动采样中断，请手动核对"))
                        }
                    }
                    return
                }
                self.onRawDeviceMotion?(data)
                switch self.currentExerciseType {
                case .benchPress: self.benchPressDetector?.processMotion(data)
                case .squat: self.squatDetector?.processMotion(data)
                case .overheadPress, .barbellRow, .bicepCurl: self.processUpperBodyMotion(data)
                case .deadlift: break
                }
            }
        }
        print("🏃‍♂️ 运动检测已启动（后台模式）")
    }
    
    func stopDetection() {
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        isStopping = true
        print("🛑 停止运动检测")
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        if OperationQueue.current !== motionQueue {
            motionQueue.waitUntilAllOperationsAreFinished()
        }
        applyStop(finalAnalysis(stoppedAt: stoppedAt))
    }

    @MainActor
    func stopDetectionAsync() async {
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        isStopping = true
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        let final = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                self.motionQueue.waitUntilAllOperationsAreFinished()
                continuation.resume(returning: self.finalAnalysis(stoppedAt: stoppedAt))
            }
        }
        applyStop(final)
    }

    // File I/O and queued analysis may finish later; coverage ends when stop was requested.
    private func finalAnalysis(stoppedAt: Double) -> (bench: BenchAnalysis?, squatCount: Int, deadliftCount: Int, cycles: [SquatCycle], upperCycles: [UpperBodyCycle]) {
        (currentExerciseType == .benchPress && isDetecting && countsRepetitions ? benchPressDetector?.finish(receivedAt: stoppedAt) : nil,
         squatDetector?.repCount ?? 0, deadliftDetector?.repCount ?? 0, squatDetector?.cycles ?? [], upperBodyDetector?.cycles ?? [])
    }

    private func shouldReportMotionError(_ error: Error, stream: String, runID: UUID) -> Bool {
        guard generation == runID else { return false }
        let stopping = isStopping
        let failure = error as NSError
        lifecycleLog.notice("motion_error stream=\(stream, privacy: .public) domain=\(failure.domain, privacy: .public) code=\(failure.code) stopping=\(stopping)")
        return !stopping
    }

    private func applyStop(_ final: (bench: BenchAnalysis?, squatCount: Int, deadliftCount: Int, cycles: [SquatCycle], upperCycles: [UpperBodyCycle])) {
        let wasDetecting = isDetecting
        generation = UUID() // Discard queued UI updates from the previous run.
        if wasDetecting && countsRepetitions && currentExerciseType == .benchPress,
           let result = final.bench {
            onRawBenchAnalysis?(result)
            applyBenchAnalysis(result)
        } else if wasDetecting && countsRepetitions {
            let finalCount: Int
            switch currentExerciseType {
            case .squat: finalCount = final.squatCount
            case .deadlift: finalCount = final.deadliftCount
            case .overheadPress, .barbellRow, .bicepCurl: finalCount = final.upperCycles.count
            case .benchPress: finalCount = repCount
            }
            let pending = max(0, finalCount - repCount)
            repCount = finalCount
            if currentExerciseType == .squat {
                for cycle in final.cycles.suffix(pending) {
                    onRepDetected?(.squat(cycle), false)
                }
            } else if currentExerciseType == .deadlift {
                for _ in 0..<pending { onRepDetected?(.deadlift, false) }
            } else {
                for cycle in final.upperCycles.suffix(pending) {
                    onRepDetected?(.upperBody(currentExerciseType, cycle), false)
                }
            }
        }
        isDetecting = false
        isStopping = false
    }

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        onRawAcceleration?(data)
        guard countsRepetitions else { return }
        // 将数据传递给当前活动的检测器
        switch currentExerciseType {
        case .benchPress:
            break // Bench press uses fused motion, never raw X-axis stability.
        case .squat:
            break // Squat uses the same fused stream in training and collection.
        case .overheadPress, .barbellRow, .bicepCurl:
            break // Upper-body movements also require the fused stream.
        case .deadlift:
            deadliftDetector?.processAccelerometerData(data)
        }
    }

    private func processUpperBodyMotion(_ data: CMDeviceMotion) {
        guard let detector = upperBodyDetector else { return }
        let wasInterrupted = detector.interrupted
        let sample = BenchMotionSample(t: data.timestamp,
            gravity: .init(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            user_acceleration: .init(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotation_rate: .init(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))
        if let cycle = detector.append(sample) {
            onRawRepDetected?(cycle.end)
            publishRepetition(.upperBody(currentExerciseType, cycle), sensorTime: cycle.end, count: detector.repCount)
        }
        if !wasInterrupted && detector.interrupted {
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.isDetecting else { return }
                self.onCountingError?(String(localized: "运动采样中断，请手动核对"))
            }
        }
    }
    
    private func publishBenchAnalysis(_ result: BenchAnalysis) {
        onRawBenchAnalysis?(result)
        // Prefix V8 results use future context and can confirm several old reps
        // together. Keep them in the diagnostic stream, not in the live counter.
        // applyStop() alone reconciles the finished set without completion feedback.
        guard result.status == "insufficient_data" else { return }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isDetecting else { return }
            self.onCountingError?(String(localized: "采样中断，请手动核对"))
        }
    }

    private func publishRepetition(_ repetition: DetectedRepetition, sensorTime: Double?, count: Int? = nil, date: Date? = nil) {
        let token = generation
        let completedAt = sensorTime ?? ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isDetecting, !self.isStopping,
                  self.currentExerciseType == repetition.exercise else { return }
            let isLive = (0...0.25).contains(ProcessInfo.processInfo.systemUptime - completedAt)
            // Never turn delayed bench completions into live increments. Squat
            // and deadlift may reconcile their counts, but do so silently.
            if case .benchPress = repetition, !isLive { return }
            let next = count ?? (self.repCount + 1)
            guard next > self.repCount,
                  self.lastDeliveredRepTime.map({ completedAt > $0 }) ?? true else { return }
            self.lastDeliveredRepTime = completedAt
            self.repCount = next
            let anchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
            self.lastRepTime = date ?? Date(timeIntervalSince1970: anchor + completedAt)
            self.onRepDetected?(repetition, isLive)
        }
    }

    private func applyBenchAnalysis(_ result: BenchAnalysis) {
        if let count = result.count {
            repCount = count
            let anchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
            lastRepTime = result.cycles.last.map { Date(timeIntervalSince1970: anchor + $0.end) }
        }
        onBenchAnalysis?(result)
        onActiveDuration?(result.status == "estimated" ? ActionTiming.total(result.cycles.map {
            ActionTiming.Interval(start: $0.start, end: $0.end)
        }) : nil)
    }

    private func handleRepDetected(sensorTime: Double? = nil) {
        onRawRepDetected?(sensorTime)
        switch currentExerciseType {
        case .benchPress: return
        case .squat:
            guard let detector = squatDetector, let cycle = detector.cycles.last else { return }
            publishRepetition(.squat(cycle), sensorTime: sensorTime, count: detector.repCount, date: detector.lastRepTime)
        case .deadlift:
            guard let detector = deadliftDetector else { return }
            publishRepetition(.deadlift, sensorTime: sensorTime, count: detector.repCount, date: detector.lastRepTime)
        case .overheadPress, .barbellRow, .bicepCurl: return
        }
    }

    private func resetCurrentDetector() {
        switch currentExerciseType {
        case .benchPress:
            benchPressDetector?.resetCount()
        case .squat:
            squatDetector?.resetCount()
        case .deadlift:
            deadliftDetector?.resetCount()
        case .overheadPress, .barbellRow, .bicepCurl:
            upperBodyDetector?.resetCount()
        }
    }
    
    func resetCount() {
        let restart = isDetecting
        if restart { stopDetection() }
        repCount = 0
        lastRepTime = nil
        resetCurrentDetector()
        if restart { startDetection(countRepetitions: countsRepetitions) }
        print("🔄 重置运动检测状态")
    }
    
    func configureForExercise(_ exerciseType: ExerciseType) {
        currentExerciseType = exerciseType
        upperBodyDetector = UpperBodyDetector(exercise: exerciseType)
        print("🔄 切换到 \(exerciseType.displayName) 检测模式")
    }
}
