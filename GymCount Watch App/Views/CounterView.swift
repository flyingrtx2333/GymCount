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
        CounterPanel(
            exercise: currentSession?.exerciseType.displayName ?? "",
            count: currentSession?.totalReps ?? 0,
            weight: currentSession?.weight ?? dataManager.settings.defaultWeight,
            onWeight: {
                tempWeight = currentSession?.weight ?? dataManager.settings.defaultWeight
                showingWeightInput = true
            },
            onMinus: { dataManager.removeRep(); WKInterfaceDevice.current().play(.click) },
            onPlus: { dataManager.addRep(); WKInterfaceDevice.current().play(.click) },
            onEnd: { dataManager.endWorkout(); WKInterfaceDevice.current().play(.success) }
        )
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .sheet(isPresented: $showingWeightInput) {
            WeightInputView(weight: $tempWeight) { newWeight in
                if var session = dataManager.currentSession {
                    session.weight = newWeight
                    dataManager.currentSession = session
                }
            }
        }
    }

}

struct CounterPanel: View {
    let exercise: String
    let count: Int
    let weight: Double
    let onWeight: () -> Void
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                HStack(spacing: 4) {
                    Text(exercise).font(GymStyle.section)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Button(action: onWeight) {
                        Text(weight.formatted(.number.precision(.fractionLength(0...1))) + " 公斤")
                            .font(GymStyle.caption)
                            .foregroundStyle(GymStyle.muted)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("修改器械重量")
                }

                .frame(height: 28)

                HStack(spacing: 2) {
                    CircleButton(icon: "minus", color: GymStyle.mint, size: 44, disabled: count == 0, action: onMinus)
                        .accessibilityLabel("减少次数")
                    Text("\(count)")
                        .font(GymStyle.trainingCounter)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    CircleButton(icon: "plus", color: GymStyle.mint, size: 44, action: onPlus)
                        .accessibilityLabel("增加次数")
                }
                HStack(spacing: 5) {
                    Circle().fill(GymStyle.mint).frame(width: 5, height: 5)
                    Text(NSLocalizedString("detecting", comment: "检测中"))
                        .font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                }
                Button("结束", action: onEnd).buttonStyle(GymActionStyle())
            }
            .gymPageContent(fullWidthHeader: true)
        }
        .gymPage()
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
                    .fill(GymStyle.surface)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(disabled ? GymStyle.muted.opacity(0.3) : Color.white)
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
        ScrollView {
        VStack(spacing: GymStyle.spacing) {

            GymHeader(title: "器械重量", back: { presentationMode.wrappedValue.dismiss() })

            // 大号重量显示
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("\(formatWeight(weight))")
                    .font(GymStyle.counter)
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: weight)
                Text("公斤")
                    .font(GymStyle.body)
                    .foregroundColor(.secondary)
            }

            // 调节按钮
            HStack(spacing: 6) {
                // -5kg
                WeightStepButton(label: "-5", color: GymStyle.mint) {
                    weight = max(0, weight - 5)
                }
                // -2.5kg
                WeightStepButton(label: "-2.5", color: GymStyle.mint.opacity(0.7)) {
                    weight = max(0, weight - 2.5)
                }
                // +2.5kg
                WeightStepButton(label: "+2.5", color: GymStyle.mint.opacity(0.7)) {
                    weight += 2.5
                }
                // +5kg
                WeightStepButton(label: "+5", color: GymStyle.mint) {
                    weight += 5
                }
            }

            Button("保存") {
                onSave(weight)
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(GymActionStyle(primary: true))
        }
        .gymPageContent(fullWidthHeader: true)
        }
        .gymPage()
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
                        .fill(GymStyle.surface)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CounterView()
        .environmentObject(DataManager.shared)
}
