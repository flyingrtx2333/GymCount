//
//  CounterView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import WatchKit
import HealthKit

struct CounterView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingWeightInput = false
    @State private var tempWeight: Double = 0.0
    @State private var isDetecting = false

    private var currentSession: WorkoutSession? {
        dataManager.currentSession
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: 重量标签（可点击修改）
            Button(action: {
                tempWeight = currentSession?.weight ?? dataManager.settings.defaultWeight
                showingWeightInput = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                        .font(GymStyle.detail)
                        .foregroundColor(.secondary)
                    Text("\(Int(currentSession?.weight ?? dataManager.settings.defaultWeight)) kg")
                        .font(GymStyle.body)
                        .foregroundColor(.secondary)
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.25))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()

            // MARK: 计数主显示
            VStack(spacing: 6) {
                Text("\(currentSession?.totalReps ?? 0)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.25), value: currentSession?.totalReps)

                // 检测状态指示
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isDetecting ? 1.4 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                            value: isDetecting
                        )
                    Text(NSLocalizedString("detecting", comment: "检测中"))
                        .font(GymStyle.detail)
                        .foregroundColor(.secondary)
                }
                .onAppear { isDetecting = true }
                .onDisappear { isDetecting = false }
            }

            Spacer()

            // MARK: 操作按钮区
            HStack(spacing: 14) {
                // 减号
                CircleButton(
                    icon: "minus",
                    color: .orange,
                    size: 40,
                    disabled: currentSession?.totalReps == 0
                ) {
                    dataManager.removeRep()
                    WKInterfaceDevice.current().play(.click)
                }

                // 停止按钮（居中、较大）
                CircleButton(
                    icon: "stop.fill",
                    color: .red,
                    size: 50
                ) {
                    dataManager.endWorkout()
                    WKInterfaceDevice.current().play(.success)
                }

                // 加号
                CircleButton(
                    icon: "plus",
                    color: .blue,
                    size: 40
                ) {
                    dataManager.addRep()
                    WKInterfaceDevice.current().play(.click)
                }
            }
            .padding(.bottom, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(currentSession?.exerciseType.displayName ?? "")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    dataManager.endWorkout()
                    WKInterfaceDevice.current().play(.success)
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
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
            tempWeight = currentSession?.weight ?? dataManager.settings.defaultWeight
        }
    }
}

// MARK: - 圆形按钮

struct CircleButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(disabled ? 0.15 : 0.22))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(disabled ? 0.1 : 0.35), lineWidth: 0.5)
                    )
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundColor(disabled ? color.opacity(0.3) : color)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 重量输入视图

struct WeightInputView: View {
    @Binding var weight: Double
    let onSave: (Double) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 12) {

            Text(NSLocalizedString("equipment weight", comment: "器械重量"))
                .font(GymStyle.button)
                .foregroundColor(.secondary)

            // 大号重量显示
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(formatWeight(weight))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: weight)
                Text(NSLocalizedString("kg", comment: "kg"))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            // 调节按钮
            HStack(spacing: 6) {
                // -5kg
                WeightStepButton(label: "-5", color: .orange) {
                    weight = max(0, weight - 5)
                }
                // -2.5kg
                WeightStepButton(label: "-2.5", color: .orange.opacity(0.7)) {
                    weight = max(0, weight - 2.5)
                }
                // +2.5kg
                WeightStepButton(label: "+2.5", color: .blue.opacity(0.7)) {
                    weight += 2.5
                }
                // +5kg
                WeightStepButton(label: "+5", color: .blue) {
                    weight += 5
                }
            }

            // 保存
            Button(action: {
                onSave(weight)
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(NSLocalizedString("save", comment: "保存"))
                    .font(GymStyle.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(w))
            : String(format: "%.1f", w)
    }
}

struct WeightStepButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(GymStyle.detail)
                .foregroundColor(color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CounterView()
        .environmentObject(DataManager.shared)
}
