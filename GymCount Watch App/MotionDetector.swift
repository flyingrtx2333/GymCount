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

class MotionDetector: ObservableObject {
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    #if DEBUG || GYMCOUNT_CAPTURE
    var onRawAcceleration: ((CMAccelerometerData) -> Void)?
    var onRawRepDetected: ((Double?) -> Void)?
    var onRawDeviceMotion: ((CMDeviceMotion) -> Void)?
    var onRawBenchAnalysis: ((BenchAnalysis) -> Void)?
    #endif
    private var accelerometerData: [CMAccelerometerData] = []
    private var dataUpdateTimer: Timer?
    private var lastDataUpdateTime: Date = Date()
    
    // 运动检测器
    private var benchPressDetector: BenchPressDetector?
    private var squatDetector: SquatDetector?
    private var deadliftDetector: DeadliftDetector?
    private var currentExerciseType: ExerciseType = .benchPress
    private var countsRepetitions = true
    private var generation = UUID()
    
    @Published var isDetecting = false
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let sampleRate = 40.0 // 采样率
    private let dataUpdateInterval = 0.05 // 数据更新间隔（50ms）
    
    var onBenchCompletion: (() -> Void)?
    var onSquatCompletion: (() -> Void)?
    var onBenchAnalysis: ((BenchAnalysis) -> Void)?
    var onCountingError: ((String) -> Void)?
    var onRepDetected: (() -> Void)?
    var onAccelerationDataReceived: ((Double, Double, Double, Double) -> Void)?
    
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
        
        benchPressDetector?.onCompletion = { [weak self] time in
            self?.publishCompletion(time, exercise: .benchPress)
        }

        // 初始化深蹲检测器
        squatDetector = SquatDetector()
        squatDetector?.onRepDetected = { [weak self] time in
            self?.handleRepDetected(sensorTime: time)
            self?.publishCompletion(time, exercise: .squat)
        }
        
        // 初始化硬拉检测器
        deadliftDetector = DeadliftDetector()
        deadliftDetector?.onRepDetected = { [weak self] in
            self?.handleRepDetected()
        }
    }
    
    func startDetection(countRepetitions: Bool = true) {
        guard !isDetecting else { return }
        guard motionManager.isAccelerometerAvailable else {
            print("❌ 加速计不可用")
            return
        }
        
        guard !countRepetitions || currentExerciseType == .deadlift || motionManager.isDeviceMotionAvailable else {
            onCountingError?("融合运动不可用，请手动计数")
            return
        }
        generation = UUID()
        isDetecting = true
        countsRepetitions = countRepetitions
        accelerometerData.removeAll()
        repCount = 0
        lastRepTime = nil
        lastDataUpdateTime = Date()
        
        // 重置当前检测器
        resetCurrentDetector()
        
        // 启动数据更新定时器
        startDataUpdateTimer()
        
        // 使用后台队列来处理加速计数据，确保在屏幕变暗时仍能正常工作
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let data = data else { 
                if let error = error {
                    print("❌ 加速计更新错误: \(error)")
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
                            self.onCountingError?("运动采样中断，请手动核对")
                        }
                    }
                    return
                }
                #if DEBUG || GYMCOUNT_CAPTURE
                self.onRawDeviceMotion?(data)
                #endif
                if self.currentExerciseType == .benchPress { self.benchPressDetector?.processMotion(data) }
                else { self.squatDetector?.processMotion(data) }
            }
        }
        print("🏃‍♂️ 运动检测已启动（后台模式）")
    }
    
    func stopDetection() {
        print("🛑 停止运动检测")
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        if OperationQueue.current !== motionQueue {
            motionQueue.waitUntilAllOperationsAreFinished()
        }
        let wasDetecting = isDetecting
        generation = UUID() // Discard queued UI updates from the previous run.
        if wasDetecting && countsRepetitions && currentExerciseType == .benchPress,
           let result = benchPressDetector?.finish() {
            #if DEBUG || GYMCOUNT_CAPTURE
            onRawBenchAnalysis?(result)
            #endif
            applyBenchAnalysis(result)
        } else if wasDetecting && countsRepetitions {
            let finalCount = currentExerciseType == .squat ? (squatDetector?.repCount ?? 0) : (deadliftDetector?.repCount ?? 0)
            let pending = max(0, finalCount - repCount)
            repCount = finalCount
            for _ in 0..<pending { onRepDetected?() }
        }
        isDetecting = false
        stopDataUpdateTimer()
    }
    
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        #if DEBUG || GYMCOUNT_CAPTURE
        onRawAcceleration?(data)
        #endif
        guard countsRepetitions else { return }
        // 添加新数据
        accelerometerData = [data]
        
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
    
    private func startDataUpdateTimer() {
        dataUpdateTimer = Timer.scheduledTimer(withTimeInterval: dataUpdateInterval, repeats: true) { [weak self] _ in
            self?.sendDataToView()
        }
    }
    
    private func stopDataUpdateTimer() {
        dataUpdateTimer?.invalidate()
        dataUpdateTimer = nil
    }
    
    private func sendDataToView() {
        motionQueue.addOperation { [weak self] in
            guard let self, let lastData = self.accelerometerData.last else { return }
            let x = lastData.acceleration.x, y = lastData.acceleration.y, z = lastData.acceleration.z
            let magnitude = sqrt(x*x + y*y + z*z)
            let token = self.generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.onAccelerationDataReceived?(x, y, z, magnitude)
            }
        }
    }

    private func publishBenchAnalysis(_ result: BenchAnalysis) {
        #if DEBUG || GYMCOUNT_CAPTURE
        onRawBenchAnalysis?(result)
        #endif
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isDetecting else { return }
            self.applyBenchAnalysis(result)
        }
    }

    private func applyBenchAnalysis(_ result: BenchAnalysis) {
        repCount = result.cycles.count
        let anchor = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        lastRepTime = result.cycles.last.map { Date(timeIntervalSince1970: anchor + $0.end) }
        onBenchAnalysis?(result)
    }

    private func publishCompletion(_ time: Double, exercise: ExerciseType) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isDetecting,
                  self.currentExerciseType == exercise,
                  (0...0.25).contains(ProcessInfo.processInfo.systemUptime - time) else { return }
            if exercise == .benchPress { self.onBenchCompletion?() }
            else { self.onSquatCompletion?() }
        }
    }

    private func handleRepDetected(sensorTime: Double? = nil) {
        #if DEBUG || GYMCOUNT_CAPTURE
        onRawRepDetected?(sensorTime)
        #endif
        let count: Int
        let time: Date?
        switch currentExerciseType {
        case .benchPress: return
        case .squat: count = squatDetector?.repCount ?? 0; time = squatDetector?.lastRepTime
        case .deadlift: count = deadliftDetector?.repCount ?? 0; time = deadliftDetector?.lastRepTime
        }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isDetecting else { return }
            self.repCount = count; self.lastRepTime = time; self.onRepDetected?()
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
