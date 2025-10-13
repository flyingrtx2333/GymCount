//
//  Squat.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import Foundation
import CoreMotion
import WatchKit

// 深蹲周期状态
enum SquatCycleState {
    case stable      // 稳定状态
    case unstable    // 不稳定状态
}

class SquatDetector: ObservableObject {
    private var xAxisData: [Double] = [] // X轴数据历史
    
    // 深蹲检测状态
    private var cycleState: SquatCycleState = .stable
    private var cycleStartTime: Date?
    private var stabilityChanges = 0 // 稳定性变化次数
    private var lastStabilityState = true // 上次的稳定性状态
    private var stateStartTime: Date? // 当前状态开始时间
    private var lastStateChangeTime: Date? // 上次状态变化时间
    private var lastRepCompletionTime: Date? // 上次动作完成时间
    
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let stabilityWindowSize = 15 // 稳定性检测窗口大小（增加以更好捕捉慢速动作）
    private let minRepInterval = 1.0 // 最小重复间隔（秒）
    private let minCycleDuration = 0.3 // 最小周期持续时间（秒）
    private let stabilityThreshold = 0.03 // X轴稳定性阈值（降低以适应慢速动作）
    private let gravityThreshold = 0.2 // 允许偏离重力加速度(-1)的最大距离（降低）
    private let minStateDuration = 0.5 // 最小状态持续时间（秒）
    private let slowSquatThreshold = 0.1 // 慢速深蹲的稳定性阈值
    private let slowSquatGravityThreshold = 0.18 // 慢速深蹲的重力阈值
    private let cooldownPeriod = 0.8 // 动作完成后的冷却时间（秒）
    
    var onRepDetected: (() -> Void)?
    
    init() {
        resetState()
    }
    
    func processAccelerometerData(_ data: CMAccelerometerData) {
        // 添加X轴数据到历史记录
        xAxisData.append(data.acceleration.x)
        if xAxisData.count > stabilityWindowSize {
            xAxisData.removeFirst()
        }
        
        // 需要足够的数据才能检测
        guard xAxisData.count >= stabilityWindowSize else { return }
        
        // 检测深蹲周期
        detectSquatCycle()
    }
    
    // 深蹲周期检测：稳定-不稳定-稳定-不稳定-稳定
    private func detectSquatCycle() {
        let currentStability = calculateXAxisStability()
        let now = Date()
        
        // 检查是否在冷却期内
        if let lastCompletion = lastRepCompletionTime {
            let timeSinceCompletion = now.timeIntervalSince(lastCompletion)
            if timeSinceCompletion < cooldownPeriod {
                // 在冷却期内，忽略状态变化
                return
            }
        }
        
        // 初始化状态开始时间
        if stateStartTime == nil {
            stateStartTime = now
        }
        
        // 检测稳定性变化
        if currentStability != lastStabilityState {
            // 检查当前状态是否持续了足够的时间
            if let stateStart = stateStartTime {
                let stateDuration = now.timeIntervalSince(stateStart)
                
                // 动态调整最小状态持续时间：对于慢速深蹲，允许更短的状态持续时间
                let xAxisAverage = calculateXAxisAverage()
                let isSlowSquat = abs(xAxisAverage - (-1.0)) < 0.2 // 判断是否为慢速深蹲
                let requiredStateDuration = isSlowSquat ? minStateDuration * 0.7 : minStateDuration
                
                if stateDuration >= requiredStateDuration {
                    // 状态持续时间足够，允许状态切换
                    stabilityChanges += 1
                    lastStabilityState = currentStability
                    stateStartTime = now
                    lastStateChangeTime = now
                    
                    // 获取当前动作阶段描述
                    let phaseDescription = getPhaseDescription(for: stabilityChanges, isStable: currentStability)
                    
                    if stabilityChanges == 1 {
                        // 第一次变化，开始新的周期
                        cycleStartTime = now
                        print("🔄 开始深蹲周期 - \(phaseDescription), 状态持续: \(String(format: "%.2f", stateDuration))秒, X轴平均值: \(String(format: "%.3f", xAxisAverage)), 慢速: \(isSlowSquat)")
                    } else if stabilityChanges >= 5 {
                        // 完成5次变化的完整周期
                        if let startTime = cycleStartTime {
                            let cycleDuration = now.timeIntervalSince(startTime)
                            
                            // 检查周期时长是否合理
                            if cycleDuration >= minCycleDuration {
                                // 检查时间间隔
                                if let lastTime = lastRepTime {
                                    let timeSinceLastRep = now.timeIntervalSince(lastTime)
                                    if timeSinceLastRep >= minRepInterval {
                                        recordRep(at: now)
                                        print("✅ 检测到深蹲动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 变化次数: \(stabilityChanges), X轴平均值: \(String(format: "%.3f", xAxisAverage)), 慢速: \(isSlowSquat)")
                                    }
                                } else {
                                    recordRep(at: now)
                                    print("✅ 检测到深蹲动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 变化次数: \(stabilityChanges), X轴平均值: \(String(format: "%.3f", xAxisAverage)), 慢速: \(isSlowSquat)")
                                }
                                
                                // 重置状态
                                resetCycleState()
                            } else {
                                print("❌ 周期时长不合理: \(String(format: "%.2f", cycleDuration))秒, X轴平均值: \(String(format: "%.3f", xAxisAverage))")
                            }
                        }
                    } else {
                        print("🔄 状态变化 \(stabilityChanges) - \(phaseDescription), 状态持续: \(String(format: "%.2f", stateDuration))秒, X轴平均值: \(String(format: "%.3f", xAxisAverage)), 慢速: \(isSlowSquat)")
                    }
                } else {
                    // 状态持续时间不够，忽略这次变化
                    // print("⏳ 状态持续时间不足，忽略变化 - 当前: \(currentStability ? "稳定" : "不稳定"), 需要: \(String(format: "%.2f", requiredStateDuration))秒, 实际: \(String(format: "%.2f", stateDuration))秒")
                }
            }
        }
    }
    
    // 获取动作阶段描述
    private func getPhaseDescription(for changeCount: Int, isStable: Bool) -> String {
        switch changeCount {
        case 1:
            return NSLocalizedString("phase_down", comment: "向下") // 从顶部开始向下
        case 2:
            return NSLocalizedString("phase_bottom", comment: "底部") // 到达底部位置
        case 3:
            return NSLocalizedString("phase_up", comment: "向上") // 从底部开始向上
        case 4:
            return NSLocalizedString("phase_top", comment: "顶部") // 接近顶部位置
        case 5:
            return NSLocalizedString("phase_down", comment: "向下") // 完成一个周期，准备下一个
        default:
            return isStable ? NSLocalizedString("phase_stable", comment: "稳定") : NSLocalizedString("phase_unstable", comment: "不稳定")
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
        let distanceFromGravity = abs(mean - (-1.0))
        
        // 动态调整阈值：如果检测到可能是慢速深蹲，使用更宽松的阈值
        let isSlowSquat = standardDeviation < slowSquatThreshold && distanceFromGravity < slowSquatGravityThreshold
        
        let currentStabilityThreshold = isSlowSquat ? slowSquatThreshold : stabilityThreshold
        let currentGravityThreshold = isSlowSquat ? slowSquatGravityThreshold : gravityThreshold
        
        // 同时满足两个条件：标准差小且稳定在-1附近
        let isStableByDeviation = standardDeviation < currentStabilityThreshold
        let isStableByGravity = distanceFromGravity < currentGravityThreshold
        
        return isStableByDeviation && isStableByGravity
    }
    
    // 计算X轴平均值
    private func calculateXAxisAverage() -> Double {
        guard xAxisData.count >= stabilityWindowSize else { return 0.0 }
        
        let recentData = Array(xAxisData.suffix(stabilityWindowSize))
        return recentData.reduce(0, +) / Double(recentData.count)
    }
    
    private func recordRep(at time: Date) {
        repCount += 1
        lastRepTime = time
        lastRepCompletionTime = time // 记录动作完成时间
        
        // 触觉反馈 - 使用向上方向的震动，表示计数增加
        WKInterfaceDevice.current().play(.directionUp)
        
        // 回调
        onRepDetected?()
    }
    
    func resetCount() {
        repCount = 0
        lastRepTime = nil
        resetState()
        print("🔄 重置深蹲检测状态")
    }
    
    private func resetState() {
        cycleState = .stable
        cycleStartTime = nil
        stabilityChanges = 0
        lastStabilityState = true
        stateStartTime = nil
        lastStateChangeTime = nil
        lastRepCompletionTime = nil
        xAxisData.removeAll()
    }
    
    private func resetCycleState() {
        stabilityChanges = 0
        cycleStartTime = nil
        // 保持当前的稳定性状态，不要重置为true
        // lastStabilityState 保持当前值
        stateStartTime = nil
        lastStateChangeTime = nil
    }
}
