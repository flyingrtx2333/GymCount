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
            // // 重量显示
            // HStack {
            //     Text(NSLocalizedString("weight", comment: "重量"))
            //     Text("\(Int(currentSession?.weight ?? 0))")
            //     Text(NSLocalizedString("kg", comment: "公斤"))
            // }
            // .font(.caption)
            // .foregroundColor(.secondary)
            
            // 次数显示
            VStack {
                Text("\(currentSession?.totalReps ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            // 主要操作按钮
            HStack(spacing: 20) {
                // 减号按钮
                Button(action: {
                    if let session = dataManager.currentSession, session.totalReps > 0 {
                        dataManager.removeRep()
                        WKInterfaceDevice.current().play(.click)
                    }
                }) {
                    VStack {
                        Image(systemName: "minus.circle.fill")
                            .font(.title)
                        Text(NSLocalizedString("minus", comment: "减"))
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.orange)
                .disabled(currentSession?.totalReps == 0)
                
                // 开始/停止按钮
                Button(action: {
                    if dataManager.currentSession != nil {
                        dataManager.endWorkout()
                        WKInterfaceDevice.current().play(.success)
                    } else {
                        dataManager.startWorkout(exerciseType: .benchPress, weight: dataManager.settings.defaultWeight)
                        WKInterfaceDevice.current().play(.click)
                    }
                }) {
                    VStack {
                        Image(systemName: dataManager.currentSession != nil ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                        Text(dataManager.currentSession != nil ? NSLocalizedString("stop", comment: "停止") : NSLocalizedString("start", comment: "开始"))
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(dataManager.currentSession != nil ? .red : .green)
                
                // 加号按钮
                Button(action: {
                    dataManager.addRep()
                    WKInterfaceDevice.current().play(.click)
                }) {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                        Text(NSLocalizedString("plus", comment: "加"))
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(currentSession?.exerciseType.displayName ?? "")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    if dataManager.currentSession != nil {
                        // 如果已经开始锻炼，则停止并返回主页
                        dataManager.endWorkout()
                        WKInterfaceDevice.current().play(.success)
                    }
                    // 如果未开始锻炼，直接返回主页（通过endWorkout()清空会话）
                }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { 
                    showingWeightInput = true 
                }) {
                    Image(systemName: "pencil")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
        }
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
