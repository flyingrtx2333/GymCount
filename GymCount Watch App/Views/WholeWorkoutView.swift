import SwiftUI
import WatchKit

struct WholeWorkoutView: View {
    @EnvironmentObject private var dataManager: DataManager
    @State private var showingWeight = false
    @State private var showingExercise = false
    @State private var changingSet = false
    @State private var showingActions = false
    @State private var showingDiscard = false

    private var session: WorkoutSession? { dataManager.currentSession }
    private var locked: Bool { dataManager.isSavingWorkout || changingSet }
    private var canEditRepetitions: Bool { session?.isActive == true && !dataManager.isWholeWorkoutPaused }

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                HStack(spacing: 2) {
                    Button { showingExercise = true } label: {
                        HStack(spacing: 3) {
                            Text(session?.exerciseType.displayName ?? "")
                                .font(GymStyle.body).lineLimit(1).minimumScaleFactor(0.75)
                            Image(systemName: "chevron.down").font(GymStyle.detail)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "切换动作"))
                    .accessibilityValue(session?.exerciseType.displayName ?? "")
                    .accessibilityIdentifier("whole.exercise")
                    .disabled(session?.isActive != true)
                    Spacer(minLength: 0)
                    Button { showingWeight = true } label: {
                        Text(weightText).font(GymStyle.caption)
                            .foregroundStyle(GymStyle.accent)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "修改器械重量"))
                    .accessibilityValue(weightText)
                    .accessibilityIdentifier("whole.weight")
                    .disabled(session?.isActive != true)
                }
                HStack {
                    Text(String(localized: "第 \(dataManager.currentGroupNumber) 组"))
                        .accessibilityIdentifier("whole.group")
                    Spacer(minLength: 0)
                    Text(String(localized: "合计 \(dataManager.wholeTotalReps) 次"))
                    Button { showingActions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(GymStyle.button)
                            .foregroundStyle(GymStyle.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "更多操作"))
                    .accessibilityIdentifier("whole.actions")
                    .confirmationDialog(String(localized: "更多操作"), isPresented: $showingActions, titleVisibility: .hidden) {
                        Button(String(localized: "手动分组")) {
                            perform { await dataManager.nextWholeWorkoutSet() }
                        }
                        .disabled(locked || !canEditRepetitions || dataManager.currentGroupReps == 0)
                        .accessibilityIdentifier("whole.next-set")
                        Button(String(localized: "放弃训练"), role: .destructive) { showingDiscard = true }
                            .accessibilityIdentifier("whole.discard")
                        Button(String(localized: "取消"), role: .cancel) {}
                    }
                    .alert(String(localized: "放弃这次训练？"), isPresented: $showingDiscard) {
                        Button(String(localized: "取消"), role: .cancel) {}
                        Button(String(localized: "放弃训练"), role: .destructive) { dataManager.resetCurrentWorkout() }
                            .accessibilityIdentifier("whole.discard.confirm")
                    } message: {
                        Text(String(localized: "未保存的训练将被删除"))
                    }
                }
                .font(GymStyle.detail).foregroundStyle(GymStyle.muted)

                HStack(spacing: 2) {
                    CircleButton(icon: "minus", disabled: locked || !canEditRepetitions || dataManager.currentGroupReps == 0) {
                        dataManager.removeRep()
                        WKInterfaceDevice.current().play(.click)
                    }.accessibilityLabel(String(localized: "减少次数"))
                    Text("\(dataManager.currentGroupReps)")
                        .font(GymStyle.trainingCounter).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("whole.count")
                    CircleButton(icon: "plus", disabled: locked || !canEditRepetitions) {
                        dataManager.addRep()
                        WKInterfaceDevice.current().play(.click)
                    }.accessibilityLabel(String(localized: "增加次数"))
                }

                liveStatus
                    .frame(maxWidth: .infinity, minHeight: 20)
                if let error = liveError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(GymStyle.detail).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(error)
                        .accessibilityIdentifier("whole.error")
                }

                HStack(spacing: GymStyle.spacing) {
                    Button(dataManager.isWholeWorkoutPaused ? String(localized: "继续") : String(localized: "暂停")) {
                        changingSet = true
                        Task { @MainActor in
                            if dataManager.isWholeWorkoutPaused { await dataManager.resumeWholeWorkout() }
                            else { await dataManager.pauseWholeWorkout() }
                            changingSet = false
                        }
                    }
                    .buttonStyle(GymActionStyle())
                    .accessibilityIdentifier("whole.pause")
                    .disabled(session?.isActive != true)
                    Button(session?.endTime == nil ? String(localized: "结束") : String(localized: "重试保存")) {
                        perform { await dataManager.finishWholeWorkout() }
                    }
                    .buttonStyle(GymActionStyle(primary: true))
                    .accessibilityIdentifier("workout.end")
                }
            }
            .gymPageContent()
            .disabled(locked)
        }
        .gymPage().navigationBarBackButtonHidden(true)
        .gymNavigationTitle(String(localized: "训练"))
        .overlay { if locked { ProgressView() } }
        .sheet(isPresented: $showingWeight) {
            WeightInputView(value: session?.weight ?? dataManager.settings.defaultWeight, maximum: 500) { value in
                guard let exercise = session?.exerciseType else { return }
                perform { await dataManager.switchWholeWorkoutExercise(exerciseType: exercise, weight: value) }
            }
        }
        .sheet(isPresented: $showingExercise) {
            WholeWorkoutExercisePicker(selected: session?.exerciseType) { exercise in
                let weight = session?.weight ?? dataManager.settings.defaultWeight
                perform { await dataManager.switchWholeWorkoutExercise(exerciseType: exercise, weight: weight) }
            }
        }
        .alert(String(localized: "还在训练吗？"), isPresented: $dataManager.wholeWorkoutIdlePrompt) {
            Button(String(localized: "继续训练"), role: .cancel) { dataManager.continueWholeWorkoutAfterIdle() }
            Button(String(localized: "结束训练")) { perform { await dataManager.finishWholeWorkout() } }
        }
    }

    private var liveError: String? {
        let message = dataManager.saveError ?? dataManager.wholeWorkoutError
        guard message != (dataManager.countingFailed ? dataManager.countingMessage : nil) else { return nil }
        return message
    }

    private var weightText: String {
        (session?.weight ?? dataManager.settings.defaultWeight)
            .formatted(.number.grouping(.never).precision(.significantDigits(1...15))) + String(localized: " 公斤")
    }

    private var liveStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            status(at: context.date)
        }
    }

    @ViewBuilder private func status(at date: Date) -> some View {
        if dataManager.isWholeWorkoutPaused {
            Text(String(localized: "已暂停")).font(GymStyle.caption).foregroundStyle(GymStyle.accent)
        } else if dataManager.countingFailed {
            Label(dataManager.countingMessage, systemImage: "exclamationmark.circle.fill")
                .font(GymStyle.detail).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if let start = dataManager.restStartedAt {
            HStack(spacing: 4) {
                Text(String(localized: "间隔"))
                Text(Duration.seconds(max(0, date.timeIntervalSince(start))).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
            }
            .font(GymStyle.caption).foregroundStyle(GymStyle.accent)
            .accessibilityIdentifier("whole.interval")
        } else {
            Text(dataManager.countingMessage)
                .font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func perform(_ action: @escaping @MainActor () async -> Bool) {
        guard !locked else { return }
        changingSet = true
        Task { @MainActor in
            _ = await action()
            changingSet = false
        }
    }
}

private struct WholeWorkoutExercisePicker: View {
    let selected: ExerciseType?
    let choose: (ExerciseType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    ExerciseCard(exercise: exercise, isSelected: exercise == selected) {
                        dismiss()
                        choose(exercise)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("whole.switch." + exercise.rawValue)
                }
            }.gymPageContent()
        }.gymPage().gymNavigationTitle(String(localized: "切换动作"), back: { dismiss() })
        }
    }
}

struct WholeWorkoutSummaryView: View {
    let report: WorkoutReport
    let close: () -> Void
    var warning: String? = nil
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(report.totalReps)").font(GymStyle.counter).monospacedDigit()
                    Text(String(localized: "次")).font(GymStyle.caption).foregroundStyle(GymStyle.muted)
                    Spacer(minLength: 0)
                    Text(String(localized: "\(report.sets.count) 组")).font(GymStyle.caption)
                }.accessibilityIdentifier("whole.summary.reps")
                metric(String(localized: "总用时"), value: time(report.duration))
                if let active = report.activeDuration { metric(String(localized: "动作时长"), value: time(active)) }
                if let interval = report.intervalDuration { metric(String(localized: "组间间隔"), value: time(interval)) }
                if report.pauseDuration > 0 { metric(String(localized: "暂停"), value: time(report.pauseDuration)) }
                if let energy = report.activeEnergyKcal {
                    metric(report.metricsComplete ? String(localized: "活动热量（估计）") : String(localized: "已记录热量（估计）"), value: energy.formatted(.number.precision(.fractionLength(0))) + " kcal")
                }
                Divider().overlay(GymStyle.line).padding(.vertical, 4)
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    let sets = report.sets.filter { $0.exercise == exercise }
                    if !sets.isEmpty {
                        HStack(spacing: 6) {
                            Image(exercise.icon).resizable().renderingMode(.template)
                                .scaledToFit().frame(width: 28, height: 28)
                                .foregroundStyle(GymStyle.accent).accessibilityHidden(true)
                            Text(exercise.displayName).font(GymStyle.body).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Text(String(localized: "\(sets.reduce(0) { $0 + $1.totalReps }) 次"))
                                .font(GymStyle.caption).monospacedDigit()
                        }.frame(minHeight: 34).accessibilityElement(children: .combine)
                    }
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(GymStyle.detail).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("whole.summary.warning")
                    Button(String(localized: "设置")) { showingSettings = true }
                        .buttonStyle(GymActionStyle())
                }
                Button(String(localized: "完成"), action: close)
                    .buttonStyle(GymActionStyle(primary: true))
                    .accessibilityIdentifier("whole.summary.done")
            }.gymPageContent()
        }
        .gymPage().navigationBarBackButtonHidden(true)
        .gymNavigationTitle(String(localized: "训练已保存"))
        .accessibilityIdentifier("whole.summary")
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(GymStyle.detail).foregroundStyle(GymStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(value).font(GymStyle.caption).monospacedDigit()
        }.frame(minHeight: 24).accessibilityElement(children: .combine)
    }

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}
