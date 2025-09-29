//
//  CounterDebugView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import Charts

struct CounterDebugView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var motionDetector = MotionDetector()
    @State private var accelerationData: [AccelerationPoint] = []
    @State private var maxDataPoints = 50 // 减少数据点数量以提高性能
    @State private var updateTimer: Timer?
    @State private var pendingData: [AccelerationPoint] = [] // 待更新的数据缓冲区
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题和计数
            HStack {
                Text("调试模式")
                    .font(.headline)
                Spacer()
                Text("计数: \(motionDetector.repCount)")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal)
            
            // 三轴加速度图表
            VStack(spacing: 4) {
                // X轴加速度
                HStack {
                    Text("X轴")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(width: 20)
                    
                    Chart(accelerationData) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("加速度", point.x)
                        )
                        .foregroundStyle(.red)
                    }
                    .frame(height: 40)
                    .chartYScale(domain: -2...2)
                }
                
                // Y轴加速度
                HStack {
                    Text("Y轴")
                        .font(.caption)
                        .foregroundColor(.green)
                        .frame(width: 20)
                    
                    Chart(accelerationData) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("加速度", point.y)
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 40)
                    .chartYScale(domain: -2...2)
                }
                
                // Z轴加速度
                HStack {
                    Text("Z轴")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    
                    Chart(accelerationData) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("加速度", point.z)
                        )
                        .foregroundStyle(.blue)
                    }
                    .frame(height: 40)
                    .chartYScale(domain: -2...2)
                }
                
                // 总幅度
                // HStack {
                //     Text("幅度")
                //         .font(.caption)
                //         .foregroundColor(.purple)
                //         .frame(width: 20)
                    
                //     Chart(accelerationData) { point in
                //         LineMark(
                //             x: .value("时间", point.timestamp),
                //             y: .value("幅度", point.magnitude)
                //         )
                //         .foregroundStyle(.purple)
                //     }
                //     .frame(height: 40)
                //     .chartYScale(domain: 0...3)
                // }
            }
            .padding(.horizontal)
            
            // 控制按钮
            HStack(spacing: 12) {
                Button(action: {
                    if motionDetector.isDetecting {
                        motionDetector.stopDetection()
                    } else {
                        motionDetector.startDetection()
                    }
                }) {
                    HStack {
                        Image(systemName: motionDetector.isDetecting ? "stop.fill" : "play.fill")
                        Text(motionDetector.isDetecting ? "停止" : "开始")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(motionDetector.isDetecting ? Color.red : Color.green)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    motionDetector.resetCount()
                    accelerationData.removeAll()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重置")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    dataManager.endWorkout()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("退出")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            
            // 当前数值显示
            VStack(spacing: 2) {
                if let lastData = accelerationData.last {
                    HStack {
                        Text("X: \(String(format: "%.3f", lastData.x))")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("Y: \(String(format: "%.3f", lastData.y))")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Z: \(String(format: "%.3f", lastData.z))")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("幅度: \(String(format: "%.3f", lastData.magnitude))")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            setupMotionDetector()
            startUpdateTimer()
        }
        .onDisappear {
            motionDetector.stopDetection()
            stopUpdateTimer()
        }
    }
    
    private func setupMotionDetector() {
        // 设置回调来接收加速度数据
        motionDetector.onAccelerationDataReceived = { [self] x, y, z, magnitude in
            let newPoint = AccelerationPoint(
                timestamp: Date(),
                x: x,
                y: y,
                z: z,
                magnitude: magnitude
            )
            
            // 将数据添加到缓冲区，而不是立即更新UI
            DispatchQueue.main.async {
                pendingData.append(newPoint)
                
                // 限制缓冲区大小，避免内存过度使用
                if pendingData.count > 20 {
                    pendingData.removeFirst()
                }
            }
        }
    }
    
    private func startUpdateTimer() {
        // 每100ms更新一次UI，而不是每次数据更新都刷新
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateChartData()
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateChartData() {
        guard !pendingData.isEmpty else { return }
        
        // 批量更新数据
        accelerationData.append(contentsOf: pendingData)
        pendingData.removeAll()
        
        // 保持数据点数量限制
        while accelerationData.count > maxDataPoints {
            accelerationData.removeFirst()
        }
    }
}

// 加速度数据点结构
struct AccelerationPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
    let magnitude: Double
}

#Preview {
    CounterDebugView()
        .environmentObject(DataManager.shared)
}
