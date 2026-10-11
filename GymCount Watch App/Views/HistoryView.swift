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

    var body: some View {
        ScrollView {
            VStack(spacing: GymStyle.spacing) {
                GymHeader(title: "历史", back: { showingHistory = false })

                // MARK: 运动类型选择器
                ExerciseTypePicker(selected: $selectedExercise)

                // MARK: 周导航 + 标题
                WeekNavigatorRow(
                    title: getWeekTitle(),
                    onPrev: switchToPreviousWeek,
                    onNext: { if !isCurrentWeek { switchToNextWeek() } },
                    isCurrentWeek: isCurrentWeek
                )

                // MARK: 核心数据卡片
                StatsRow(
                    reps: getCurrentWeekTotal(),
                    repChange: getRepChangeFromLastWeek(),
                    weight: Int(getCurrentWeekTotalWeight()),
                    weightChange: Int(getWeightChangeFromLastWeek())
                )

                // MARK: 简洁柱状图
                SimpleBarChart(
                    exerciseType: selectedExercise,
                    weekDate: currentWeekDate,
                    dataManager: dataManager
                )
                .frame(height: 72)
                .padding(.horizontal, 2)

                Spacer(minLength: 4)
            }
            .gymPageContent()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .tint(GymStyle.mint)
        .gymPage()

    }

    // MARK: - Helpers

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(currentWeekDate, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private func getWeekTitle() -> String {
        dataManager.getWeekInfo(for: currentWeekDate).title
    }

    private func getCurrentWeekTotal() -> Int {
        dataManager.getWeeklyTotalForExercise(selectedExercise, for: currentWeekDate)
    }

    private func getCurrentWeekTotalWeight() -> Double {
        dataManager.getWeeklyTotalWeightForExercise(selectedExercise, for: currentWeekDate)
    }

    private func getRepChangeFromLastWeek() -> Int {
        let prev = dataManager.getPreviousWeekDataForExercise(selectedExercise, for: currentWeekDate)
        return getCurrentWeekTotal() - prev.totalReps
    }

    private func getWeightChangeFromLastWeek() -> Double {
        let prev = dataManager.getPreviousWeekDataForExercise(selectedExercise, for: currentWeekDate)
        return getCurrentWeekTotalWeight() - prev.totalWeight
    }

    private func switchToNextWeek() {
        if let next = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) {
            withAnimation(.easeInOut(duration: 0.25)) { currentWeekDate = next }
        }
    }

    private func switchToPreviousWeek() {
        if let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate) {
            withAnimation(.easeInOut(duration: 0.25)) { currentWeekDate = prev }
        }
    }
}

// MARK: - 运动类型选择器

struct ExerciseTypePicker: View {
    @Binding var selected: ExerciseType

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ExerciseType.allCases, id: \.self) { exercise in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = exercise }
                }) {
                    VStack(spacing: 3) {
                        Image(exercise.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .opacity(selected == exercise ? 1.0 : 0.4)

                        Circle()
                            .fill(selected == exercise ? GymStyle.mint : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected == exercise
                                  ? GymStyle.mint.opacity(0.15)
                                  : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 周导航行

struct WeekNavigatorRow: View {
    let title: String
    let onPrev: () -> Void
    let onNext: () -> Void
    let isCurrentWeek: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(title)
                .font(GymStyle.detail)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCurrentWeek ? Color.white.opacity(0.2) : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentWeek)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 数据统计行

struct StatsRow: View {
    let reps: Int
    let repChange: Int
    let weight: Int
    let weightChange: Int

    var body: some View {
        HStack(spacing: 8) {
            StatCard(
                value: "\(reps)",
                unit: NSLocalizedString("times", comment: "次"),
                change: repChange,
                accentColor: GymStyle.mint
            )
            StatCard(
                value: "\(weight)",
                unit: NSLocalizedString("kg", comment: "kg"),
                change: weightChange,
                accentColor: GymStyle.mint
            )
        }
    }
}

struct StatCard: View {
    let value: String
    let unit: String
    let change: Int
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(GymStyle.detail)
                    .foregroundColor(.secondary)
            }

            Text("上周 \(change >= 0 ? "+" : "−")\(abs(change))")
                .font(GymStyle.detail)
                .foregroundStyle(GymStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.clear, lineWidth: 0)
        )
    }
}

// MARK: - 简洁柱状图（仅次数，清晰易读）

struct SimpleBarChart: View {
    let exerciseType: ExerciseType
    let weekDate: Date
    let dataManager: DataManager

    @State private var chartData: [WeeklyChartData] = []

    var body: some View {
        Group {
            if chartData.allSatisfy({ $0.count == 0 }) {
                // 无数据空状态
                VStack(spacing: GymStyle.spacing) {
                    Image(systemName: "chart.bar")
                        .font(.title3)
                        .foregroundColor(Color.white.opacity(0.2))
                    Text(NSLocalizedString("noData", comment: "暂无数据"))
                        .font(GymStyle.detail)
                        .foregroundColor(Color.white.opacity(0.3))
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
                                    colors: [GymStyle.mint, GymStyle.mint],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
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
        .onAppear { updateChartData() }
        .onChange(of: exerciseType) { _, _ in updateChartData() }
        .onChange(of: weekDate) { _, _ in updateChartData() }
    }

    private func updateChartData() {
        let weekDaysString = NSLocalizedString("week_days", comment: "一,二,三,四,五,六,日")
        let weekDays = weekDaysString.components(separatedBy: ",")
        let weeklyCounts = dataManager.getWeeklyDataForExercise(exerciseType, for: weekDate)
        let weeklyWeights = dataManager.getWeeklyWeightDataForExercise(exerciseType, for: weekDate)

        chartData = (0..<7).map { i in
            WeeklyChartData(
                day: i,
                dayLabel: weekDays[i],
                count: weeklyCounts[i],
                weight: weeklyWeights[i],
                weightScaled: weeklyWeights[i]
            )
        }
    }
}

// MARK: - 数据模型

struct WeeklyChartData: Identifiable {
    let id = UUID()
    let day: Int
    let dayLabel: String
    let count: Int
    let weight: Double
    let weightScaled: Double
}

// MARK: - Preview

#Preview {
    HistoryView(showingHistory: .constant(true))
        .environmentObject(DataManager.shared)
}
