//
//  CounterView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import WatchKit

struct CounterView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingWeightInput = false
    @State private var tempWeight: Double = 0.0
    
    private var currentSession: WorkoutSession? {
        dataManager.currentSession
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 锻炼类型和重量显示
            HStack {
                VStack(alignment: .leading) {
                    Text(currentSession?.exerciseType.displayName ?? "")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(NSLocalizedString("weight", comment: "重量"))
                        Text("\(Int(currentSession?.weight ?? 0))")
                        Text(NSLocalizedString("kg", comment: "公斤"))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingWeightInput = true }) {
                    Image(systemName: "pencil")
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // 次数显示
            VStack {
                Text("\(currentSession?.totalReps ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                // Text(NSLocalizedString("reps", comment: "次数"))
                //     .font(.caption)
                //     .foregroundColor(.secondary)
            }
            
            // 计时器和自动检测状态
            // VStack(spacing: 4) {
            //     if let session = currentSession {
            //         Text(formatDuration(session.startTime.timeIntervalSinceNow))
            //             .font(.caption)
            //             .foregroundColor(.secondary)
            //     }
                
            //     // 自动检测状态指示器
            //     if dataManager.settings.autoDetectionEnabled {
            //         HStack {
            //             Circle()
            //                 .fill(dataManager.motionDetector.isDetecting ? Color.green : Color.gray)
            //                 .frame(width: 8, height: 8)
            //             Text("自动检测")
            //                 .font(.caption2)
            //                 .foregroundColor(.secondary)
            //         }
            //     }
            // }
            
            // 主要操作按钮
            HStack(spacing: 20) {
                // 计数按钮
                Button(action: {
                    dataManager.addRep()
                    // 触觉反馈
                    WKInterfaceDevice.current().play(.click)
                }) {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                        Text(NSLocalizedString("reps", comment: "次数"))
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: currentSession?.totalReps)
                
                // 停止按钮
                Button(action: {
                    dataManager.endWorkout()
                    WKInterfaceDevice.current().play(.success)
                }) {
                    VStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.title)
                        Text(NSLocalizedString("stop", comment: "停止"))
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red)
            }
            
            // 重置按钮
            Button(action: {
                dataManager.resetCurrentWorkout()
            }) {
                Text(NSLocalizedString("reset", comment: "重置"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .sheet(isPresented: $showingWeightInput) {
            WeightInputView(weight: $tempWeight) { newWeight in
                if var session = dataManager.currentSession {
                    session.weight = newWeight
                    dataManager.currentSession = session
                }
            }
        }
        .onAppear {
            tempWeight = currentSession?.weight ?? 0.0
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let absDuration = abs(duration)
        let minutes = Int(absDuration) / 60
        let seconds = Int(absDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WeightInputView: View {
    @Binding var weight: Double
    let onSave: (Double) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 16) {
            Text(NSLocalizedString("weight", comment: "重量"))
                .font(.headline)
            
            Text("\(Int(weight)) \(NSLocalizedString("kg", comment: "公斤"))")
                .font(.title)
                .foregroundColor(.primary)
            
            // 重量调节按钮
            HStack(spacing: 20) {
                Button(action: {
                    if weight > 0 {
                        weight -= 2.5
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red)
                
                Button(action: {
                    weight += 2.5
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.green)
            }
            
            // 保存按钮
            Button(action: {
                onSave(weight)
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(NSLocalizedString("save", comment: "保存"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
}

#Preview {
    CounterView()
        .environmentObject(DataManager.shared)
}
