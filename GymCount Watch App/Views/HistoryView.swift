//
//  HistoryView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI
import Charts
import WatchKit

struct HistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var showingHistory: Bool
    @State private var selectedExercise: ExerciseType = .benchPress
    @State private var currentWeekDate: Date = Date()
    @State private var feedbackWorkout: WorkoutHistory?
    @State private var showingTrend = false
    @State private var weeklyWorkouts: [WorkoutHistory] = []
    @State private var weekCounts = Array(repeating: 0, count: 7)
    @State private var weekWeight: Double?
    @State private var previousReps = 0
    @State private var previousWeight: Double?
    @State private var showingExercisePicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                historyHeader

                WeekNavigatorRow(
                    title: getWeekTitle(),
                    accessibilityTitle: dataManager.getWeekInfo(for: currentWeekDate).title,
                    onPrev: switchToPreviousWeek,
                    onNext: { if !isCurrentWeek { switchToNextWeek() } },
                    isCurrentWeek: isCurrentWeek
                )

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        showingTrend.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        StatsRow(
                            reps: getCurrentWeekTotal(),
                            weight: getCurrentWeekTotalWeight(),
                            repChange: showingTrend ? getRepChangeFromLastWeek() : nil,
                            weightChange: showingTrend ? getWeightChangeFromLastWeek() : nil
                        )
                        VStack(spacing: 3) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: showingTrend ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(GymStyle.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: showingTrend ? "收起趋势" : "展开趋势"))
                .accessibilityIdentifier("history.trend-toggle")

                if showingTrend {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "趋势")).font(GymStyle.caption)
                        SimpleBarChart(
                            counts: weekCounts
                        )
                        .frame(height: 72)
                    }
                    .padding(.vertical, 6)
                    .transition(.opacity)
                }

                if weeklyWorkouts.isEmpty {
                    Text(NSLocalizedString("noData", comment: "暂无数据"))
                        .font(GymStyle.caption)
                        .foregroundStyle(GymStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ForEach(weeklyWorkouts) { workout in
                        Button { feedbackWorkout = workout } label: {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.date, format: .dateTime.month().day().hour().minute())
                                        .font(GymStyle.detail)
                                        .foregroundStyle(GymStyle.muted)
                                    Text(workout.workoutReport == nil ? String(localized: "计数反馈") : String(localized: "训练报告"))
                                        .font(GymStyle.detail)
                                        .foregroundStyle(GymStyle.accent)
                                }
                                Spacer(minLength: 0)
                                Text(String(localized: "\(repetitions(in: workout)) 次"))
                                    .font(GymStyle.section)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(GymStyle.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("feedback.history." + workout.id.uuidString)
                        Divider().overlay(GymStyle.ink.opacity(0.08))
                    }
                }
            }
            .gymPageContent()
        }
        .navigationBarBackButtonHidden(true)
        .tint(GymStyle.accent)
        .gymPage()
        .gymNavigationTitle(String(localized: "历史"), back: { showingHistory = false })
        .onChange(of: selectedExercise) { _, _ in refreshWeek(dataManager.workoutHistory) }
        .onChange(of: currentWeekDate) { _, _ in refreshWeek(dataManager.workoutHistory) }
        .onReceive(dataManager.$workoutHistory) { refreshWeek($0) }
        .sheet(item: $feedbackWorkout) { workout in
            if let report = workout.workoutReport {
                NavigationStack { WholeWorkoutSummaryView(report: report, close: { feedbackWorkout = nil }) }
            } else {
                NavigationStack { WorkoutFeedbackView(workout: workout) }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                List {
                    ForEach(ExerciseType.allCases, id: \.self) { exercise in
                        Button {
                            selectedExercise = exercise
                            showingExercisePicker = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(exercise.icon)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(GymStyle.ink)
                                    .accessibilityHidden(true)
                                Text(exercise.displayName)
                                Spacer(minLength: 0)
                                if selectedExercise == exercise {
                                    Image(systemName: "checkmark").foregroundStyle(GymStyle.accent)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("history.exercise." + exercise.rawValue)
                    }
                }
                .gymPage()
                .gymNavigationTitle(String(localized: "选择动作"), back: { showingExercisePicker = false })
            }
        }
    }

    private var historyHeader: some View {
        HStack(spacing: 0) {
            Button { showingExercisePicker = true } label: {
                HStack(spacing: 3) {
                    Image(selectedExercise.icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(selectedExercise.displayName).font(GymStyle.body)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(GymStyle.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(selectedExercise.displayName)
            .accessibilityIdentifier("history.exercise-filter")
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private func refreshWeek(_ history: [WorkoutHistory]) {
        let week = WatchWorkoutWeek.interval(containing: currentWeekDate)
        let previous = WatchWorkoutWeek.interval(containing: week.start.addingTimeInterval(-1))
        var rows: [WorkoutHistory] = [], counts = Array(repeating: 0, count: 7)
        var currentVolume: Double? = 0, priorVolume: Double? = 0, priorCount = 0
        let calendar = Calendar.current
        for item in history {
            let matching = item.workoutReport.map { report in report.sets.contains { $0.exercise == selectedExercise } }
                ?? (item.exerciseType == selectedExercise)
            guard matching else { continue }
            let reps = repetitions(in: item), volume = trainingWeight(in: item)
            if WatchWorkoutWeek.contains(item.date, in: week) {
                rows.append(item)
                counts[(calendar.component(.weekday, from: item.date) + 5) % 7] += reps
                currentVolume = currentVolume.flatMap { sum in volume.map { sum + $0 } }
            } else if WatchWorkoutWeek.contains(item.date, in: previous) {
                priorCount += reps
                priorVolume = priorVolume.flatMap { sum in volume.map { sum + $0 } }
            }
        }
        weeklyWorkouts = rows.sorted { $0.date > $1.date }
        weekCounts = counts; weekWeight = currentVolume
        previousReps = priorCount; previousWeight = priorVolume
    }

    private func repetitions(in workout: WorkoutHistory) -> Int {
        guard let report = workout.workoutReport else { return workout.totalReps }
        return report.sets.filter { $0.exercise == selectedExercise }.reduce(0) { $0 + $1.totalReps }
    }

    private func trainingWeight(in workout: WorkoutHistory) -> Double? {
        guard let report = workout.workoutReport else { return workout.totalWeight }
        return report.sets.filter { $0.exercise == selectedExercise }.reduce(0) { $0 + $1.totalWeight }
    }

    // MARK: - Helpers

    private var isCurrentWeek: Bool {
        WatchWorkoutWeek.interval(containing: currentWeekDate).start == WatchWorkoutWeek.interval(containing: Date()).start
    }

    private func getWeekTitle() -> String {
        let week = WatchWorkoutWeek.interval(containing: currentWeekDate)
        let lastDay = week.end.addingTimeInterval(-1)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDate(week.start, equalTo: Date(), toGranularity: .year),
           calendar.isDate(lastDay, equalTo: Date(), toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("Md")
            return formatter.string(from: week.start) + "–" + formatter.string(from: lastDay)
        }
        formatter.setLocalizedDateFormatFromTemplate("yyMd")
        return formatter.string(from: week.start) + "\n" + formatter.string(from: lastDay)
    }

    private func getCurrentWeekTotal() -> Int { weekCounts.reduce(0, +) }
    private func getCurrentWeekTotalWeight() -> Double? { weekWeight }
    private func getRepChangeFromLastWeek() -> Int { getCurrentWeekTotal() - previousReps }
    private func getWeightChangeFromLastWeek() -> Double? {
        guard let current = weekWeight, let previous = previousWeight else { return nil }
        return current - previous
    }

    private func switchToNextWeek() {
        if let next = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { currentWeekDate = next }
        }
    }

    private func switchToPreviousWeek() {
        if let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { currentWeekDate = prev }
        }
    }
}

// MARK: - 周导航行

struct WeekNavigatorRow: View {
    let title: String
    let accessibilityTitle: String
    let onPrev: () -> Void
    let onNext: () -> Void
    let isCurrentWeek: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GymStyle.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "上一周"))

            Text(title)
                .font(GymStyle.detail)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .accessibilityLabel(accessibilityTitle)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCurrentWeek ? GymStyle.ink.opacity(0.2) : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentWeek)
            .accessibilityLabel(String(localized: "下一周"))
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 数据统计行

struct StatsRow: View {
    let reps: Int
    let weight: Double?
    let repChange: Int?
    let weightChange: Double?

    var body: some View {
        HStack(spacing: 6) {
            StatCard(
                title: String(localized: "累计次数"),
                value: "\(reps)",
                unit: NSLocalizedString("times", comment: "次"),
                change: repChange.map(Double.init)
            )
            StatCard(
                title: String(localized: "训练量"),
                value: weight.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—",
                unit: NSLocalizedString("kg", comment: "kg"),
                change: weightChange
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let change: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(GymStyle.muted)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(GymStyle.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let change {
                Text(String(localized: "上周 \(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(0...1))))"))
                    .font(GymStyle.detail)
                    .foregroundStyle(GymStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 简洁柱状图（仅次数，清晰易读）

struct SimpleBarChart: View {
    let counts: [Int]
    private var chartData: [WeeklyChartData] {
        let labels = NSLocalizedString("week_days", comment: "一,二,三,四,五,六,日").components(separatedBy: ",")
        return counts.enumerated().map { WeeklyChartData(day: $0.offset, dayLabel: labels.indices.contains($0.offset) ? labels[$0.offset] : String($0.offset + 1), count: $0.element) }
    }

    var body: some View {
        Group {
            if chartData.allSatisfy({ $0.count == 0 }) {
                // 无数据空状态
                VStack(spacing: GymStyle.spacing) {
                    Image(systemName: "chart.bar")
                        .font(.title3)
                        .foregroundColor(GymStyle.ink.opacity(0.2))
                    Text(NSLocalizedString("noData", comment: "暂无数据"))
                        .font(GymStyle.detail)
                        .foregroundColor(GymStyle.ink.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                )
            } else {
                Chart {
                    ForEach(chartData) { d in
                        BarMark(
                            x: .value("Day", d.dayLabel),
                            y: .value("Count", d.count)
                        )
                        .foregroundStyle(
                            d.count > 0
                                ? LinearGradient(
                                    colors: [GymStyle.accent, GymStyle.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [GymStyle.ink.opacity(0.08), GymStyle.ink.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .cornerRadius(3)
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(GymStyle.detail)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                )
            }
        }
    }
}

// MARK: - 数据模型

struct WeeklyChartData: Identifiable {
    var id: Int { day }
    let day: Int
    let dayLabel: String
    let count: Int
}

// MARK: - Preview

#Preview {
    HistoryView(showingHistory: .constant(true))
        .environmentObject(DataManager.shared)
}
