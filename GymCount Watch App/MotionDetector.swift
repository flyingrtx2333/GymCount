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

// Detection owns the movement decision; consumers own records and presentation.
enum DetectedRepetition {
    case benchPress(BenchCycle)
    case squat(SquatCycle)
    case deadlift

    var exercise: ExerciseType {
        switch self {
        case .benchPress: return .benchPress
        case .squat: return .squat
        case .deadlift: return .deadlift
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
    private var currentExerciseType: ExerciseType = .benchPress
    private var countsRepetitions = true
    private var isStopping = false
    private var generation = UUID()
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
            guard let self = self, let data = data else { 
                if error != nil {
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
                guard let self else { return }
                guard let data else {
                    if error != nil {
                        if self.currentExerciseType == .benchPress { self.benchPressDetector?.markInterrupted() }
                        else { self.squatDetector?.markInterrupted() }
                        let token = self.generation
                        DispatchQueue.main.async {
                            guard self.generation == token, self.isDetecting else { return }
                            self.onCountingError?(String(localized: "运动采样中断，请手动核对"))
                        }
                    }
                    return
                }
                self.onRawDeviceMotion?(data)
                if self.currentExerciseType == .benchPress { self.benchPressDetector?.processMotion(data) }
                else { self.squatDetector?.processMotion(data) }
            }
        }
        print("🏃‍♂️ 运动检测已启动（后台模式）")
    }
    
    func stopDetection() {
        isStopping = true
        print("🛑 停止运动检测")
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        if OperationQueue.current !== motionQueue {
            motionQueue.waitUntilAllOperationsAreFinished()
        }
        applyStop(finalAnalysis())
    }

    @MainActor
    func stopDetectionAsync() async {
        isStopping = true
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        do {
            let final = try await WorkoutFileIO.shared.perform {
                self.motionQueue.waitUntilAllOperationsAreFinished()
                return self.finalAnalysis()
            }
            applyStop(final)
        } catch { onCountingError?(String(localized: "运动采样中断，请手动核对")) }
    }

    private func finalAnalysis() -> (bench: BenchAnalysis?, squatCount: Int, deadliftCount: Int, cycles: [SquatCycle]) {
        (currentExerciseType == .benchPress && isDetecting && countsRepetitions ? benchPressDetector?.finish() : nil,
         squatDetector?.repCount ?? 0, deadliftDetector?.repCount ?? 0, squatDetector?.cycles ?? [])
    }

    private func applyStop(_ final: (bench: BenchAnalysis?, squatCount: Int, deadliftCount: Int, cycles: [SquatCycle])) {
        let wasDetecting = isDetecting
        generation = UUID() // Discard queued UI updates from the previous run.
        if wasDetecting && countsRepetitions && currentExerciseType == .benchPress,
           let result = final.bench {
            onRawBenchAnalysis?(result)
            applyBenchAnalysis(result)
        } else if wasDetecting && countsRepetitions {
            let finalCount = currentExerciseType == .squat ? final.squatCount : final.deadliftCount
            let pending = max(0, finalCount - repCount)
            repCount = finalCount
            if currentExerciseType == .squat {
                for cycle in final.cycles.suffix(pending) {
                    onRepDetected?(.squat(cycle), false)
                }
            } else {
                for _ in 0..<pending { onRepDetected?(.deadlift, false) }
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
        case .deadlift:
            deadliftDetector?.processAccelerometerData(data)
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
        print("🔄 切换到 \(exerciseType.displayName) 检测模式")
    }
}
