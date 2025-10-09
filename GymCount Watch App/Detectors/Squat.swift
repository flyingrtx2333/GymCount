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
    case standing     // 站立状态
    case descending   // 下降阶段
    case bottom       // 底部状态
    case ascending    // 上升阶段
    case transition   // 过渡状态
}

class SquatDetector: ObservableObject {
    private var accelerometerData: [CMAccelerometerData] = []
    private var yAxisData: [Double] = [] // Y轴数据历史（垂直方向）
    private var zAxisData: [Double] = [] // Z轴数据历史（前后方向）
    
    // 深蹲检测状态
    private var cycleState: SquatCycleState = .standing
    private var cycleStartTime: Date?
    private var phaseStartTime: Date? // 当前阶段开始时间
    private var hasDescending = false // 是否已检测到下降阶段
    private var hasAscending = false // 是否已检测到上升阶段
    private var bottomStartTime: Date? // 底部状态开始时间
    
    @Published var repCount = 0
    @Published var lastRepTime: Date?
    
    // 检测参数
    private let windowSize = 30
    private let minRepInterval = 1.0 // 最小重复间隔（秒）
    
    // 深蹲检测参数
    private let stabilityThreshold = 0.05 // 稳定性阈值
    private let stabilityWindowSize = 10 // 稳定性检测窗口大小
    private let minCycleDuration = 1.0 // 最小周期持续时间（秒）
    private let maxCycleDuration = 5.0 // 最大周期持续时间（秒）
    private let minBottomDuration = 0.2 // 最小底部停留时间（秒）
    private let maxBottomDuration = 2.0 // 最大底部停留时间（秒）
    private let verticalAccelerationThreshold = 0.15 // 垂直加速度阈值
    private let gravityThreshold = 0.2 // 允许偏离重力加速度的最大距离
    private let gravityOffset = -1.0 // 重力加速度偏移值（Y轴）
    
    var onRepDetected: (() -> Void)?
    
    init() {
        resetState()
    }
    
    func processAccelerometerData(_ data: CMAccelerometerData) {
        // 添加新数据
        accelerometerData.append(data)
        
        // 添加Y轴和Z轴数据到历史记录
        yAxisData.append(data.acceleration.y)
        zAxisData.append(data.acceleration.z)
        
        if yAxisData.count > stabilityWindowSize {
            yAxisData.removeFirst()
        }
        if zAxisData.count > stabilityWindowSize {
            zAxisData.removeFirst()
        }
        
        // 保持窗口大小
        if accelerometerData.count > windowSize {
            accelerometerData.removeFirst()
        }
        
        // 需要足够的数据才能检测
        guard accelerometerData.count >= windowSize && 
              yAxisData.count >= stabilityWindowSize && 
              zAxisData.count >= stabilityWindowSize else { return }
        
        // 检测深蹲周期
        detectSquatCycle()
    }
    
    // 深蹲周期检测：站立-下降-底部-上升-站立
    private func detectSquatCycle() {
        let currentYAcceleration = yAxisData.last ?? 0.0
        let currentZAcceleration = zAxisData.last ?? 0.0
        let now = Date()
        
        // 计算垂直方向的加速度变化
        let verticalAcceleration = calculateVerticalAcceleration()
        let isStable = calculateStability()
        
        switch cycleState {
        case .standing:
            if !isStable && verticalAcceleration < -verticalAccelerationThreshold {
                // 从站立状态开始下降
                cycleState = .descending
                cycleStartTime = now
                phaseStartTime = now
                hasDescending = true
                hasAscending = false
                bottomStartTime = nil
                print("📉 开始深蹲下降阶段 - Y轴: \(String(format: "%.3f", currentYAcceleration))")
            }
            
        case .descending:
            if isStable && verticalAcceleration > -verticalAccelerationThreshold {
                // 下降结束，进入底部状态
                cycleState = .bottom
                phaseStartTime = now
                bottomStartTime = now
                print("⏸️ 进入深蹲底部状态 - Y轴: \(String(format: "%.3f", currentYAcceleration))")
            } else if verticalAcceleration > verticalAccelerationThreshold {
                // 直接开始上升（没有明显的底部停留）
                cycleState = .ascending
                phaseStartTime = now
                hasAscending = true
                print("📈 从下降直接进入上升阶段 - Y轴: \(String(format: "%.3f", currentYAcceleration))")
            }
            
        case .bottom:
            if let bottomStart = bottomStartTime {
                let bottomDuration = now.timeIntervalSince(bottomStart)
                
                if bottomDuration >= minBottomDuration {
                    if verticalAcceleration > verticalAccelerationThreshold {
                        // 从底部开始上升
                        cycleState = .ascending
                        phaseStartTime = now
                        hasAscending = true
                        print("📈 从底部开始上升阶段 - Y轴: \(String(format: "%.3f", currentYAcceleration))")
                    } else if bottomDuration > maxBottomDuration {
                        // 底部停留时间过长，重置
                        cycleState = .standing
                        cycleStartTime = nil
                        phaseStartTime = nil
                        hasDescending = false
                        hasAscending = false
                        bottomStartTime = nil
                        print("🔄 重置周期 - 底部停留时间过长")
                    }
                }
            }
            
        case .ascending:
            if isStable && verticalAcceleration < verticalAccelerationThreshold {
                // 上升结束，检查是否完成完整周期
                if hasDescending && hasAscending {
                    // 完成了下降和上升两个阶段，进入过渡状态
                    cycleState = .transition
                    phaseStartTime = now
                    print("🔄 完成下降和上升阶段，进入稳定过渡状态")
                } else {
                    // 未完成完整周期，重置
                    cycleState = .standing
                    cycleStartTime = nil
                    phaseStartTime = nil
                    hasDescending = false
                    hasAscending = false
                    bottomStartTime = nil
                    print("🔄 重置周期 - 未完成完整的下降上升阶段")
                }
            }
            
        case .transition:
            if isStable {
                // 保持稳定状态，确认周期完成
                if let startTime = cycleStartTime {
                    let cycleDuration = now.timeIntervalSince(startTime)
                    
                    // 检查周期时长是否合理
                    if cycleDuration >= minCycleDuration && cycleDuration <= maxCycleDuration {
                        // 检查时间间隔
                        if let lastTime = lastRepTime {
                            let timeSinceLastRep = now.timeIntervalSince(lastTime)
                            if timeSinceLastRep >= minRepInterval {
                                recordRep(at: now)
                                print("✅ 检测到深蹲动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 下降上升阶段: \(hasDescending ? "✓" : "✗")/\(hasAscending ? "✓" : "✗")")
                            }
                        } else {
                            recordRep(at: now)
                            print("✅ 检测到深蹲动作 - 周期时长: \(String(format: "%.2f", cycleDuration))秒, 下降上升阶段: \(hasDescending ? "✓" : "✗")/\(hasAscending ? "✓" : "✗")")
                        }
                    } else {
                        print("❌ 周期时长不合理: \(String(format: "%.2f", cycleDuration))秒")
                    }
                }
                
                // 重置状态
                cycleState = .standing
                cycleStartTime = nil
                phaseStartTime = nil
                hasDescending = false
                hasAscending = false
                bottomStartTime = nil
            } else {
                // 又变回不稳定，可能是新的周期开始
                if verticalAcceleration < -verticalAccelerationThreshold {
                    cycleState = .descending
                    cycleStartTime = now
                    phaseStartTime = now
                    hasDescending = true
                    hasAscending = false
                    bottomStartTime = nil
                    print("🔄 重新开始深蹲周期 - 检测到下降动作")
                }
            }
        }
    }
    
    // 计算垂直方向的加速度变化
    private func calculateVerticalAcceleration() -> Double {
        guard yAxisData.count >= 2 else { return 0.0 }
        
        // 计算Y轴加速度的变化率
        let recentData = Array(yAxisData.suffix(5))
        if recentData.count < 2 { return 0.0 }
        
        let first = recentData.first!
        let last = recentData.last!
        return last - first
    }
    
    // 计算稳定性
    private func calculateStability() -> Bool {
        guard yAxisData.count >= stabilityWindowSize else { return true }
        
        // 计算最近窗口内Y轴数据的标准差
        let recentData = Array(yAxisData.suffix(stabilityWindowSize))
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
        resetState()
        print("🔄 重置深蹲检测状态")
    }
    
    private func resetState() {
        cycleState = .standing
        cycleStartTime = nil
        phaseStartTime = nil
        hasDescending = false
        hasAscending = false
        bottomStartTime = nil
        yAxisData.removeAll()
        zAxisData.removeAll()
        accelerometerData.removeAll()
    }
}
