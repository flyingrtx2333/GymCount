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

    private var currentSession: WorkoutSession? {
        dataManager.currentSession
    }

    var body: some View {
        CounterPanel(
            exercise: currentSession?.exerciseType.displayName ?? "",
            count: currentSession?.totalReps ?? 0,
            activeDuration: currentSession?.activeDuration,
            countingMessage: dataManager.countingMessage,
            countingFailed: dataManager.countingFailed,
            finished: currentSession?.endTime != nil,
            weight: currentSession?.weight ?? dataManager.settings.defaultWeight,
            onWeight: {
                showingWeightInput = true
            },
            onMinus: { dataManager.removeRep(); WKInterfaceDevice.current().play(.click) },
            onPlus: { dataManager.addRep(); WKInterfaceDevice.current().play(.click) },
            onEnd: { Task { await dataManager.endWorkout() } }
        )
        .navigationBarBackButtonHidden(true)
        .gymNavigationTitle(currentSession?.exerciseType.displayName ?? String(localized: "训练"))
        .disabled(dataManager.isSavingWorkout)
        .overlay { if dataManager.isSavingWorkout { ProgressView() } }
        .sheet(isPresented: $showingWeightInput) {
            WeightInputView(value: currentSession?.weight ?? dataManager.settings.defaultWeight) { newWeight in
                dataManager.updateCurrentWeight(newWeight)
            }
        }
    }

}

struct CounterPanel: View {
    let exercise: String
    let count: Int
    var activeDuration: TimeInterval? = nil
    var countingMessage: String = NSLocalizedString("detecting", comment: "检测中")
    var countingFailed = false
    var finished = false
    let weight: Double
    let onWeight: () -> Void
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Button(action: onWeight) {
                        Text(weight.formatted(.number.grouping(.never).precision(.significantDigits(1...15))) + String(localized: " 公斤"))
                            .font(GymStyle.caption)
                            .foregroundStyle(GymStyle.muted)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(finished)
                    .accessibilityLabel(String(localized: "修改器械重量"))
                    .accessibilityValue(weight.formatted(.number.grouping(.never).precision(.significantDigits(1...15))) + String(localized: " 公斤"))
                }

                .frame(minHeight: 44)

                HStack(spacing: 2) {
                    CircleButton(icon: "minus", size: 44, disabled: finished || count == 0, action: onMinus)
                        .accessibilityLabel(String(localized: "减少次数"))
                    Text("\(count)")
                        .font(GymStyle.trainingCounter)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    CircleButton(icon: "plus", size: 44, disabled: finished, action: onPlus)
                        .accessibilityLabel(String(localized: "增加次数"))
                }
                if !finished {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: countingFailed ? "exclamationmark.circle.fill" : "circle.fill")
                            .font(.system(size: countingFailed ? 11 : 5, weight: .medium))
                            .accessibilityHidden(true)
                        Text(countingMessage)
                            .font(countingFailed ? GymStyle.caption : GymStyle.detail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(countingFailed ? Color.orange : GymStyle.muted)
                    .frame(maxWidth: .infinity, alignment: countingFailed ? .leading : .center)
                    .accessibilityElement(children: .combine)
                }
                if let activeDuration {
                    Text(String(localized: "动作时长（估计）：\(Duration.seconds(activeDuration).formatted(.time(pattern: .minuteSecond)))"))
                        .font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                }
                Button(finished ? String(localized: "重试保存") : String(localized: "结束"), action: onEnd).buttonStyle(GymActionStyle())
                    .accessibilityIdentifier("workout.end")
            }
            .gymPageContent()
        }
        .gymPage()
    }
}

// MARK: - 圆形按钮

struct CircleButton: View {
    let icon: String
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
                            .strokeBorder(GymStyle.ink.opacity(0.08), lineWidth: 0.5)
                    )
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(disabled ? GymStyle.muted.opacity(0.3) : GymStyle.ink)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 重量输入视图

struct WeightInputView: View {
    let title: String
    let minimum: Double
    let maximum: Double
    let step: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(title: String = String(localized: "器械重量"), value: Double,
         minimum: Double = 0, maximum: Double = .infinity, step: Double = 2.5,
         onSave: @escaping (Double) -> Void) {
        self.title = title; self.minimum = minimum; self.maximum = maximum
        self.step = step; self.onSave = onSave
        _text = State(initialValue: Self.inputText(value))
    }

    private var value: Double? {
        let scanner = Scanner(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = Locale.current
        guard let number = scanner.scanDouble(), scanner.isAtEnd, number.isFinite,
              number >= minimum, number <= maximum else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(spacing: 8) {

                HStack(spacing: 6) {
                    TextField("0", text: $text)
                        .textFieldStyle(.plain).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().submitLabel(.done)
                        .font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel(String(localized: "重量(kg)"))
                        .accessibilityIdentifier("weight-input-value")
                        .frame(minHeight: 52)
                    Text(String(localized: "公斤")).font(GymStyle.caption).foregroundStyle(GymStyle.muted)
                        .fixedSize().accessibilityHidden(true)
                }

                if value == nil {
                    Text(maximum.isFinite
                         ? String(format: String(localized: "重量范围：%@–%@ 公斤"), minimum.formatted(), maximum.formatted())
                         : String(localized: "请输入有效重量"))
                        .font(GymStyle.detail).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("weight-input-error")
                }

                HStack(spacing: 8) {
                    WeightStepButton(label: "−" + step.formatted(), color: GymStyle.accent,
                                     disabled: value.map { $0 <= minimum } ?? true) { adjust(-step) }
                        .accessibilityLabel(String(localized: "减少重量"))
                        .accessibilityValue(step.formatted() + String(localized: " 公斤"))
                        .accessibilityIdentifier("weight-step-minus")
                    WeightStepButton(label: "+" + step.formatted(), color: GymStyle.accent,
                                     disabled: value.map { $0 >= maximum } ?? true) { adjust(step) }
                        .accessibilityLabel(String(localized: "增加重量"))
                        .accessibilityValue(step.formatted() + String(localized: " 公斤"))
                        .accessibilityIdentifier("weight-step-plus")
                }
            }.gymPageContent()
        }.gymPage().gymNavigationTitle(title, back: { dismiss() }, backIdentifier: "weight-input-back")
        .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button(String(localized: "保存")) {
                        guard let value else { return }
                        onSave(value); dismiss()
                    }
                        .buttonStyle(GymActionStyle(primary: true)).disabled(value == nil)
                        .accessibilityIdentifier("weight-input-save")
                    .padding(.horizontal, GymStyle.inset)
                    .padding(.bottom, 4)
                    .background(Color.black)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private func adjust(_ amount: Double) {
        guard let value else { return }
        text = Self.inputText(min(maximum, max(minimum, value + amount)))
    }

    private static func inputText(_ value: Double) -> String {
        let raw = String(value)
        let number = raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
        return number.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

struct WeightStepButton: View {
    let label: String
    let color: Color
    var disabled = false
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
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.35 : 1)
    }
}

#Preview {
    CounterView()
        .environmentObject(DataManager.shared)
}
