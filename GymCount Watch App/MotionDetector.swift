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

// 卧推周期状态
enum CycleState {
    case stable      // 稳定状态
    case unstable    // 不稳定状态
    case positivePhase // 正加速度阶段（X轴 > 0）
    case negativePhase // 负加速度阶段（X轴 < 0）
    case transition  // 过渡状态
}

class MotionDetector: ObservableObject {
    private let motionManager = CMMotionManager()
    private var accelerometerData: [CMAccelerometerData] = []
    private var timer: Timer?
    private var dataUpdateTimer: Timer?
    private var lastDataUpdateTime: Date = Date()
    
    // 卧推检测状态
    private var cycleState: CycleState = .stable
    private var cycleStartTime: Date?
    private var xAxisData: [Double] = [] // X轴数据历史
    private var stabilityStartTime: Date? // 稳定性开始时间
    private var phaseStartTime: Date? // 当前阶段开始时间
    private var hasPositivePhase = false // 是否已检测到正加速度阶段
    private var hasNegativePhase = false // 是否已检测到负加速度阶段
    
    @Published var isDetecting = false
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let sampleRate = 40.0 // 采样率
    private let windowSize = 30 // 减少窗口大小
    private let minRepInterval = 1.0 // 最小重复间隔（秒）
    private let dataUpdateInterval = 0.05 // 数据更新间隔（50ms）
    
    // 卧推检测参数
    private let stabilityThreshold = 0.05 // X轴稳定性阈值
    private let stabilityWindowSize = 10 // 稳定性检测窗口大小
    private let minCycleDuration = 0.5 // 最小周期持续时间（秒）
    private let maxCycleDuration = 3.0 // 最大周期持续时间（秒）
    private let minStabilityDuration = 0.3 // 最小稳定持续时间（秒）
    private let accelerationThreshold = 0.1 // X轴加速度阈值，用于检测明显的正负值变化
    private let minPhaseDuration = 0.2 // 最小阶段持续时间（秒）
    private let gravityThreshold = 0.2 // 允许偏离重力加速度(-1)的最大距离
    private let gravityOffset = -1.0 // 重力加速度偏移值
    
    var onRepDetected: (() -> Void)?
    var onAccelerationDataReceived: ((Double, Double, Double, Double) -> Void)?
    
    init() {
        setupMotionManager()
    }
    
    deinit {
        stopDetection()
    }
    
    private func setupMotionManager() {
        motionManager.accelerometerUpdateInterval = 1.0 / sampleRate
    }
    
    func startDetection() {
        guard motionManager.isAccelerometerAvailable else {
            print("❌ 加速计不可用")
            return
        }
        
        isDetecting = true
        accelerometerData.removeAll()
        xAxisData.removeAll()
        repCount = 0
        cycleState = .stable
        cycleStartTime = nil
        stabilityStartTime = nil
        phaseStartTime = nil
        hasPositivePhase = false
        hasNegativePhase = false
        lastDataUpdateTime = Date()
        
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
        timer?.invalidate()
        timer = nil
        stopDataUpdateTimer()
    }
    
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // 添加新数据
        accelerometerData.append(data)
        
        // 添加X轴数据到历史记录
        xAxisData.append(data.acceleration.x)
        if xAxisData.count > stabilityWindowSize {
            xAxisData.removeFirst()
        }
        
        // 保持窗口大小
        if accelerometerData.count > windowSize {
            accelerometerData.removeFirst()
        }
        
        // 需要足够的数据才能检测
        guard accelerometerData.count >= windowSize && xAxisData.count >= stabilityWindowSize else { return }
        
        // 检测卧推周期
        detectBenchPressCycle()
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
    
    // 卧推周期检测：稳定-不稳定-正加速度阶段-负加速度阶段-稳定
    private func detectBenchPressCycle() {
        let currentStability = calculateXAxisStability()
        let currentXAcceleration = xAxisData.last ?? 0.0
        let now = Date()
        
        switch cycleState {
        case .stable:
            if !currentStability {
                // 从稳定变为不稳定，开始新的周期
                cycleState = .unstable
                cycleStartTime = now
                phaseStartTime = now
                stabilityStartTime = nil
                hasPositivePhase = false
                hasNegativePhase = false
                print("🔄 开始卧推周期 - 进入不稳定状态")
            }
            
        case .unstable:
            // 检测明显的X轴加速度变化
            if abs(currentXAcceleration+1) > accelerationThreshold {
                if currentXAcceleration > -1 {
                    // 进入正加速度阶段
                    cycleState = .positivePhase
                    phaseStartTime = now
                    hasPositivePhase = true
                    print("📈 进入正加速度阶段 - X轴: \(String(format: "%.3f", currentXAcceleration))")
                } else {
                    // 进入负加速度阶段
                    cycleState = .negativePhase
                    phaseStartTime = now
                    hasNegativePhase = true
                    print("📉 进入负加速度阶段 - X轴: \(String(format: "%.3f", currentXAcceleration))")
                }
            } else if currentStability {
                // 如果直接回到稳定状态，重置周期
                cycleState = .stable
                cycleStartTime = nil
                phaseStartTime = nil
                hasPositivePhase = false
                hasNegativePhase = false
                print("🔄 重置周期 - 未检测到明显的加速度变化")
            }
            
        case .positivePhase:
            if abs(currentXAcceleration) > accelerationThreshold && currentXAcceleration < 0 {
                // 从正加速度阶段进入负加速度阶段
                cycleState = .negativePhase
                phaseStartTime = now
                hasNegativePhase = true
                print("📉 从正加速度阶段进入负加速度阶段 - X轴: \(String(format: "%.3f", currentXAcceleration))")
            } else if currentStability {
                // 如果直接回到稳定状态，检查是否完成了完整的周期
                if hasPositivePhase && hasNegativePhase {
                    // 完成了正负两个阶段，进入过渡状态
                    cycleState = .transition
                    stabilityStartTime = now
                    print("🔄 完成正负加速度阶段，进入稳定过渡状态")
                } else {
                    // 未完成完整周期，重置
                    cycleState = .stable
                    cycleStartTime = nil
                    phaseStartTime = nil
                    hasPositivePhase = false
                    hasNegativePhase = false
                    print("🔄 重置周期 - 未完成完整的正负加速度阶段")
                }
            }
            
        case .negativePhase:
            if currentStability {
                // 从负加速度阶段进入稳定状态
                if hasPositivePhase && hasNegativePhase {
                    // 完成了正负两个阶段，进入过渡状态
                    cycleState = .transition
                    stabilityStartTime = now
                    print("🔄 完成正负加速度阶段，进入稳定过渡状态")
                } else {
                    // 未完成完整周期，重置
                    cycleState = .stable
                    cycleStartTime = nil
                    phaseStartTime = nil
                    hasPositivePhase = false
                    hasNegativePhase = false
                    print("🔄 重置周期 - 未完成完整的正负加速度阶段")
                }
            } else if abs(currentXAcceleration) > accelerationThreshold && currentXAcceleration > 0 {
                // 又回到正加速度阶段，可能是新的周期开始
                cycleState = .positivePhase
                phaseStartTime = now
                hasPositivePhase = true
                print("📈 重新进入正加速度阶段 - X轴: \(String(format: "%.3f", currentXAcceleration))")
            }
            
        case .transition:
            if currentStability {
                // 保持稳定状态，检查稳定性持续时间
                if let stabilityStart = stabilityStartTime {
                    let stabilityDuration = now.timeIntervalSince(stabilityStart)
                    
                    if stabilityDuration >= minStabilityDuration {
                        // 稳定性持续时间足够，确认周期完成
                        if let startTime = cycleStartTime {
                            let cycleDuration = now.timeIntervalSince(startTime)
                            
                            // 检查周期时长是否合理
                            if cycleDuration >= minCycleDuration && cycleDuration <= maxCycleDuration {
                                // 检查时间间隔
                                if let lastTime = lastRepTime {
                                    let timeSinceLastRep = now.timeIntervalSince(lastTime)
                                    if timeSinceLastRep >= minRepInterval {
                                        recordRep(at: now)
                                        print("✅ 检测到卧推动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 稳定时长: \(String(format: "%.2f", stabilityDuration))秒, 正负阶段: \(hasPositivePhase ? "✓" : "✗")/\(hasNegativePhase ? "✓" : "✗")")
                                    }
                                } else {
                                    recordRep(at: now)
                                    print("✅ 检测到卧推动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 稳定时长: \(String(format: "%.2f", stabilityDuration))秒, 正负阶段: \(hasPositivePhase ? "✓" : "✗")/\(hasNegativePhase ? "✓" : "✗")")
                                }
                            } else {
                                print("❌ 周期时长不合理: \(String(format: "%.2f", cycleDuration))秒")
                            }
                        }
                        
                        // 重置状态
                        cycleState = .stable
                        cycleStartTime = nil
                        stabilityStartTime = nil
                        phaseStartTime = nil
                        hasPositivePhase = false
                        hasNegativePhase = false
                    } else {
                        // 稳定性持续时间还不够，继续等待
                        print("⏳ 稳定性持续中: \(String(format: "%.2f", stabilityDuration))秒")
                    }
                }
            } else {
                // 又变回不稳定，重置周期
                cycleState = .unstable
                cycleStartTime = now
                phaseStartTime = now
                stabilityStartTime = nil
                hasPositivePhase = false
                hasNegativePhase = false
                print("🔄 重新开始卧推周期 - 稳定性被打破")
            }
        }
    }
    
    // 计算X轴稳定性
    private func calculateXAxisStability() -> Bool {
        guard xAxisData.count >= stabilityWindowSize else { return true }
        
        // 计算最近窗口内X轴数据的标准差
        let recentData = Array(xAxisData.suffix(stabilityWindowSize))
        let mean = recentData.reduce(0, +) / Double(recentData.count)
        let variance = recentData.map { pow($0 - mean, 2) }.reduce(0, +) / Double(recentData.count)
        let standardDeviation = sqrt(variance)
        
        // 检查是否稳定在-1附近（重力加速度）
        let distanceFromGravity = abs(mean - gravityOffset)
        
        // 同时满足两个条件：标准差小且稳定在-1附近
        let isStableByDeviation = standardDeviation < stabilityThreshold
        let isStableByGravity = distanceFromGravity < gravityThreshold
        
        return isStableByDeviation && isStableByGravity
    }
    
    private func recordRep(at time: Date) {
        repCount += 1
        lastRepTime = time
        
        // 触觉反馈 - 使用向上方向的震动，表示计数增加
        WKInterfaceDevice.current().play(.directionUp)
        
        // 回调
        onRepDetected?()
    }
    
    func resetCount() {
        repCount = 0
        lastRepTime = nil
        cycleState = .stable
        cycleStartTime = nil
        stabilityStartTime = nil
        phaseStartTime = nil
        hasPositivePhase = false
        hasNegativePhase = false
        xAxisData.removeAll()
        print("🔄 重置卧推检测状态")
    }
}

// MARK: - 运动检测扩展
extension MotionDetector {
    // 针对不同锻炼类型的检测参数
    func configureForExercise(_ exerciseType: ExerciseType) {
        switch exerciseType {
        case .benchPress:
            // 卧推：较大的加速度变化
            break
        case .squat:
            // 深蹲：垂直方向的加速度变化
            break
        }
    }
}
