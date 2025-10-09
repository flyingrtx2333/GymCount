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
    private var accelerometerData: [CMAccelerometerData] = []
    private var dataUpdateTimer: Timer?
    private var lastDataUpdateTime: Date = Date()
    
    // 运动检测器
    private var benchPressDetector: BenchPressDetector?
    private var squatDetector: SquatDetector?
    private var currentExerciseType: ExerciseType = .benchPress
    
    @Published var isDetecting = false
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let sampleRate = 40.0 // 采样率
    private let dataUpdateInterval = 0.05 // 数据更新间隔（50ms）
    
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
    }
    
    private func setupDetectors() {
        // 初始化卧推检测器
        benchPressDetector = BenchPressDetector()
        benchPressDetector?.onRepDetected = { [weak self] in
            self?.handleRepDetected()
        }
        
        // 初始化深蹲检测器
        squatDetector = SquatDetector()
        squatDetector?.onRepDetected = { [weak self] in
            self?.handleRepDetected()
        }
    }
    
    func startDetection() {
        guard motionManager.isAccelerometerAvailable else {
            print("❌ 加速计不可用")
            return
        }
        
        isDetecting = true
        accelerometerData.removeAll()
        repCount = 0
        lastDataUpdateTime = Date()
        
        // 重置当前检测器
        resetCurrentDetector()
        
        // 启动数据更新定时器
        startDataUpdateTimer()
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { 
                if let error = error {
                    print("❌ 加速计更新错误: \(error)")
                }
                return 
            }
            
            self.processAccelerometerData(data)
        }
    }
    
    func stopDetection() {
        print("🛑 停止运动检测")
        motionManager.stopAccelerometerUpdates()
        isDetecting = false
        stopDataUpdateTimer()
    }
    
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // 添加新数据
        accelerometerData.append(data)
        
        // 保持窗口大小
        if accelerometerData.count > 30 {
            accelerometerData.removeFirst()
        }
        
        // 将数据传递给当前活动的检测器
        switch currentExerciseType {
        case .benchPress:
            benchPressDetector?.processAccelerometerData(data)
        case .squat:
            squatDetector?.processAccelerometerData(data)
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
        guard let lastData = accelerometerData.last else { return }
        
        let x = lastData.acceleration.x
        let y = lastData.acceleration.y
        let z = lastData.acceleration.z
        let magnitude = sqrt(pow(x, 2) + pow(y, 2) + pow(z, 2))
        
        // 发送数据给调试视图
        onAccelerationDataReceived?(x, y, z, magnitude)
    }
    
    private func handleRepDetected() {
        // 从当前活动的检测器获取计数信息
        switch currentExerciseType {
        case .benchPress:
            if let detector = benchPressDetector {
                repCount = detector.repCount
                lastRepTime = detector.lastRepTime
            }
        case .squat:
            if let detector = squatDetector {
                repCount = detector.repCount
                lastRepTime = detector.lastRepTime
            }
        }
        
        // 触发回调
        onRepDetected?()
    }
    
    private func resetCurrentDetector() {
        switch currentExerciseType {
        case .benchPress:
            benchPressDetector?.resetCount()
        case .squat:
            squatDetector?.resetCount()
        }
    }
    
    func resetCount() {
        repCount = 0
        lastRepTime = nil
        resetCurrentDetector()
        print("🔄 重置运动检测状态")
    }
    
    func configureForExercise(_ exerciseType: ExerciseType) {
        currentExerciseType = exerciseType
        print("🔄 切换到 \(exerciseType.displayName) 检测模式")
    }
}

