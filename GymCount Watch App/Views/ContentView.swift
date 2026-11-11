//
//  ContentView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import WatchKit

// One type scale for labels, controls and supporting text across watch screens.
enum GymStyle {
    static let title = Font.system(size: 19, weight: .semibold)
    static let section = Font.system(size: 17, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let inset: CGFloat = 10
    static let spacing: CGFloat = 6
    static let buttonHeight: CGFloat = 44
    static let body = Font.system(size: 14)
    static let button = Font.system(size: 14, weight: .semibold)
    static let detail = Font.system(size: 11)
    static let trainingCounter = Font.system(size: 40, weight: .semibold, design: .rounded)
    static let counter = Font.system(size: 38, design: .rounded).weight(.semibold)
    static let accent = Color("AccentColor")
    static let ink = Color(red: 244 / 255, green: 241 / 255, blue: 232 / 255)
    static let surface = Color(red: 35 / 255, green: 35 / 255, blue: 32 / 255)
    static let muted = Color(red: 171 / 255, green: 169 / 255, blue: 159 / 255)
    static let line = Color(red: 59 / 255, green: 59 / 255, blue: 53 / 255)
    static let onAccent = Color(red: 34 / 255, green: 32 / 255, blue: 25 / 255)
}

// One compact title row reserves the system clock and keeps content stable across states.
extension View {
    func gymPageContent() -> some View {
        padding(.horizontal, GymStyle.inset)
            .padding(.bottom, 6)
    }

    func gymNavigationTitle(_ title: String, back: (() -> Void)? = nil,
                            backIdentifier: String = "watch.back") -> some View {
        frame(maxWidth: .infinity)
            .padding(.top, back == nil ? 32 : GymStyle.buttonHeight)
            .overlay(alignment: .topLeading) {
                Group {
                    if let back {
                        Button(action: back) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                                Text(title).font(.body).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            .frame(width: max(60, WKInterfaceDevice.current().screenBounds.width - 76),
                                   height: GymStyle.buttonHeight, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "返回"))
                        .accessibilityValue(title)
                        .accessibilityIdentifier(backIdentifier)
                    } else {
                        Text(title).font(.body).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(width: max(60, WKInterfaceDevice.current().screenBounds.width - 76),
                                   height: GymStyle.buttonHeight, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("watch.title")
                            .allowsHitTesting(false)
                    }
                }
                .foregroundStyle(GymStyle.ink)
                .padding(.leading, 12)
            }
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden)
    }

    func gymPage() -> some View {
        font(GymStyle.body)
            .foregroundStyle(GymStyle.ink)
            .background(Color.black)
            .tint(GymStyle.accent)
    }
}

// Shared native controls; exercise illustrations remain vector assets.
struct GymActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GymStyle.button)
            .foregroundStyle(configuration.role == .destructive ? Color.red : primary ? GymStyle.onAccent : GymStyle.ink)
            .frame(maxWidth: .infinity, minHeight: GymStyle.buttonHeight)
            .background(primary ? GymStyle.accent : GymStyle.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Color.clear : GymStyle.accent.opacity(0.25), lineWidth: 0.5))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var selectedExercise: ExerciseType = .benchPress
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var feedbackWorkout: WorkoutHistory?

    var body: some View {
        NavigationStack {
            if dataManager.requiresDraftRecovery {
                WorkoutDraftRecoveryView()
            } else if let report = dataManager.completedWholeWorkout {
                WholeWorkoutSummaryView(report: report, close: {
                    dataManager.completedWholeWorkout = nil
                    dataManager.wholeWorkoutError = nil
                }, warning: dataManager.saveError ?? dataManager.wholeWorkoutError,
                   isAutomaticallySaved: dataManager.wholeWorkoutEndedAfterIdle)
            } else if dataManager.currentSession != nil {
                if dataManager.requiresWorkoutRecovery {
                    WorkoutRecoveryView()
                } else if dataManager.isWholeWorkout {
                    WholeWorkoutView()
                } else {
                    CounterView()
                }
            } else {
                MainMenuView(
                    selectedExercise: $selectedExercise,
                    showingHistory: $showingHistory,
                    showingSettings: $showingSettings
                )
            }
        }
        .sheet(isPresented: $showingHistory) {
            NavigationStack { HistoryView(showingHistory: $showingHistory) }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $feedbackWorkout) { workout in NavigationStack { WorkoutFeedbackView(workout: workout) } }
        .overlay(alignment: .center) {
            ZStack {
                if dataManager.currentSession == nil, dataManager.completedWholeWorkout == nil, let workout = dataManager.completedWorkout {
                    WorkoutSavedBanner(workout: workout, feedback: {
                        dataManager.completedWorkout = nil
                        feedbackWorkout = workout
                    }, close: { dataManager.completedWorkout = nil })
                    .id(workout.id)
                    .transition(WorkoutSavedMotion.transition(reduced: reduceMotion))
                    .task(id: voiceOver) {
                        guard !voiceOver else { return }
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        if dataManager.completedWorkout?.id == workout.id {
                            dataManager.completedWorkout = nil
                        }
                    }
                }
            }
            .animation(WorkoutSavedMotion.animation(isPresented: dataManager.completedWorkout != nil, reduced: reduceMotion),
                       value: dataManager.completedWorkout?.id)
        }
        .alert(String(localized: "保存提示"), isPresented: Binding(
            get: { dataManager.saveError != nil || dataManager.wholeWorkoutError != nil }, set: { presented in
                guard !presented else { return }
                let dismissedError = dataManager.saveError
                let dismissedWholeError = dataManager.wholeWorkoutError
                DispatchQueue.main.async {
                    if dataManager.saveError == dismissedError { dataManager.saveError = nil }
                    if dataManager.wholeWorkoutError == dismissedWholeError { dataManager.wholeWorkoutError = nil }
                }
            })) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: { Text(dataManager.saveError ?? dataManager.wholeWorkoutError ?? "") }
        .tint(GymStyle.accent)
    }
}

struct WorkoutDraftRecoveryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var confirmingReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                Text(String(localized: "未完成训练读取失败"))
                    .font(GymStyle.title)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "重新读取")) { dataManager.retryWorkoutDraft() }
                    .buttonStyle(GymActionStyle(primary: true))
                    .accessibilityIdentifier("workout.draft.retry")
                Button(String(localized: "保留并重置")) { confirmingReset = true }
                    .buttonStyle(GymActionStyle())
                    .accessibilityIdentifier("workout.draft.reset")
            }.gymPageContent()
        }
        .gymPage().gymNavigationTitle(String(localized: "未完成训练"))
        .alert(String(localized: "重置未完成训练？"), isPresented: $confirmingReset) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "保留并重置")) { dataManager.resetUnreadableWorkoutDraft() }
        } message: {
            Text(String(localized: "原文件将保留，已保存的训练不受影响"))
        }
    }
}

struct WorkoutRecoveryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var confirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                if let session = dataManager.currentSession {
                    HStack(spacing: 6) {
                        Image(session.exerciseType.icon).resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 22, height: 22).foregroundStyle(GymStyle.accent).accessibilityHidden(true)
                        Text(session.exerciseType.displayName).font(GymStyle.body)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text((dataManager.isWholeWorkout ? dataManager.wholeTotalReps : session.totalReps).formatted())
                                .font(GymStyle.counter).monospacedDigit()
                            Text(String(localized: "次")).font(GymStyle.caption).foregroundStyle(GymStyle.muted)
                        }
                    }
                    Text(String(localized: "自动计数已暂停"))
                        .font(GymStyle.caption).foregroundStyle(GymStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if dataManager.canResumeRecoveredWorkout {
                        Button(String(localized: "继续训练")) { dataManager.resumeRecoveredWorkout() }
                            .buttonStyle(GymActionStyle(primary: true))
                            .accessibilityIdentifier("workout.recovery.resume")
                    }
                    HStack(spacing: GymStyle.spacing) {
                        Button(String(localized: "保存")) { Task { await dataManager.endWorkout() } }
                            .buttonStyle(GymActionStyle())
                            .accessibilityLabel(String(localized: "保存训练"))
                            .accessibilityIdentifier("workout.recovery.save")
                        Button(String(localized: "放弃"), role: .destructive) { confirmingDiscard = true }
                            .buttonStyle(GymActionStyle())
                            .accessibilityLabel(String(localized: "放弃训练"))
                            .accessibilityIdentifier("workout.recovery.discard")
                    }
                }
            }.gymPageContent()
        }
        .gymPage().gymNavigationTitle(String(localized: "未完成训练"))
        .alert(String(localized: "放弃这次训练？"), isPresented: $confirmingDiscard) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "放弃训练"), role: .destructive) { dataManager.discardRecoveredWorkout() }
        } message: {
            Text(String(localized: "已恢复的次数将被删除"))
        }
    }
}

// MARK: - 主菜单

struct MainMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedExercise: ExerciseType
    @Binding var showingHistory: Bool
    @Binding var showingSettings: Bool
    @State private var startingWorkout = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            let streak = TrainingStreak(dates: dataManager.trainingDates, now: context.date)
                            Label(String(localized: "\(streak.current) 天"), systemImage: "flame")
                                .font(GymStyle.detail).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(streak.current > 0 ? GymStyle.accent : GymStyle.muted)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(localized: "连续 \(streak.current) 天"))
                                .accessibilityIdentifier("workout.streak")
                        }
                    }
                    Spacer(minLength: 0)
                    Button { showingHistory = true } label: {
                        Image(systemName: "chart.bar.fill")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(String(localized: "历史"))
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel(String(localized: "设置"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(GymStyle.ink)
                .frame(height: 44)
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isSelected: selectedExercise == exercise
                    ) {
                        selectedExercise = exercise
                        guard !startingWorkout else { return }
                        startingWorkout = true
                        Task { @MainActor in
                            _ = await dataManager.startWholeWorkout(
                                exerciseType: exercise,
                                weight: dataManager.settings.defaultWeight
                            )
                            startingWorkout = false
                        }
                    }.disabled(startingWorkout)
                    .accessibilityIdentifier("workout.start." + exercise.rawValue)
                }
            }
            .gymPageContent()
        }
        .navigationBarBackButtonHidden(true)
        .gymPage()
        .gymNavigationTitle(String(localized: "训练"))
    }
}

// MARK: - 运动卡片

struct ExerciseCard: View {
    let exercise: ExerciseType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // 图标
                Image(exercise.icon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(GymStyle.accent)
                    .accessibilityHidden(true)

                // 名称
                Text(exercise.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(GymStyle.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer()

                // 开始指示
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GymStyle.accent)
                    .frame(width: 28, height: 28)
                    .background(GymStyle.accent.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? GymStyle.accent.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager.shared)
}
