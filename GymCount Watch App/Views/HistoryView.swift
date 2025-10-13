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
    @State private var currentWeekDate: Date = Date() // 当前显示的周日期
    @State private var crownRotation: Double = 0.0
    
    init(showingHistory: Binding<Bool>) {
        self._showingHistory = showingHistory
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // 中间主区域：周数据图表
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 周标题
                    Text(getWeekTitle())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 图表和圆点指示器区域
                    HStack(alignment: .center, spacing: 0) {
                        // 图表区域
                        WeeklyChartView(
                            exerciseType: selectedExercise,
                            weekDate: currentWeekDate,
                            dataManager: dataManager
                        )
                        .frame(maxHeight: 100)
                        .layoutPriority(1)  // 更愿意让图表占据空间
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    // 左右滑动切换周
                                    if value.translation.width > 30 {
                                        // 向右滑动，显示上一周
                                        switchToPreviousWeek()
                                    } else if value.translation.width < -30 {
                                        // 向左滑动，显示下一周
                                        switchToNextWeek()
                                    }
                                }
                        )
                        
                        Spacer()
                        
                        // 圆点指示器 - 贴右侧
                        VStack(spacing: 4) {
                            ForEach(ExerciseType.allCases, id: \.self) { exercise in
                                Circle()
                                    .fill(exercise == selectedExercise ? Color.white : Color.gray)
                                    .frame(width: 6, height: 6)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            selectedExercise = exercise
                                        }
                                    }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .padding(.horizontal, 2)

                    Spacer()
                }
                .padding(.vertical, 8)
                
                // 底部统计信息
                // HStack {
                    
                    
                    
                // }
                // .padding(.horizontal, 16)
                // .padding(.bottom, 4)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(selectedExercise.displayName)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    showingHistory = false
                }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Image(selectedExercise.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                HStack(spacing: 2) {
                    Text("\(getCurrentWeekTotal())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(NSLocalizedString("times", comment: "次"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    Text("\(Int(getCurrentWeekTotalWeight()))")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(NSLocalizedString("kg", comment: "公斤"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    // Text(NSLocalizedString("total_weight", comment: "总重量"))
                    //     .font(.caption2)
                    //     .foregroundColor(.secondary)
                }
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $crownRotation,
            from: 0,
            through: Double(ExerciseType.allCases.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false
        )
        .onChange(of: crownRotation) { _, newValue in
            let exerciseIndex = Int(newValue.rounded())
            if exerciseIndex >= 0 && exerciseIndex < ExerciseType.allCases.count {
                let newExercise = ExerciseType.allCases[exerciseIndex]
                if newExercise != selectedExercise {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedExercise = newExercise
                    }
                }
            }
        }
        .onAppear {
            // 初始化数字表冠位置
            if let currentIndex = ExerciseType.allCases.firstIndex(of: selectedExercise) {
                crownRotation = Double(currentIndex)
            }
        }
    }
    
    private func getWeekTitle() -> String {
        let weekInfo = dataManager.getWeekInfo(for: currentWeekDate)
        return weekInfo.title
    }
    
    private func getCurrentWeekTotal() -> Int {
        return dataManager.getWeeklyTotalForExercise(selectedExercise, for: currentWeekDate)
    }
    
    private func getCurrentWeekTotalWeight() -> Double {
        return dataManager.getWeeklyTotalWeightForExercise(selectedExercise, for: currentWeekDate)
    }
    
    private func switchToNextWeek() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentWeekDate = nextWeek
            }
            print("📅 \(NSLocalizedString("debug_switch_to_next_week", comment: "切换到下一周 切换后当前周日期")): \(formatter.string(from: currentWeekDate))")
        }
    }
    
    private func switchToPreviousWeek() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentWeekDate = previousWeek
            }
            print("📅 \(NSLocalizedString("debug_switch_to_previous_week", comment: "切换到上一周，切换后当前周日期")): \(formatter.string(from: currentWeekDate))")
        }
    }
    
}

struct WeeklyChartView: View {
    let exerciseType: ExerciseType
    let weekDate: Date
    let dataManager: DataManager
    
    @State private var chartData: [ChartDataPoint] = []
    @State private var weightData: [Double] = []
    
    var body: some View {
        VStack {
            // 图表
            if chartData.isEmpty {
                // 空状态
                VStack {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("noData", comment: "暂无数据"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 双柱状图
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(chartData.enumerated()), id: \.element.day) { index, dataPoint in
                        VStack(spacing: 2) {
                            HStack(alignment: .bottom, spacing: 1) {
                                // 次数柱子（蓝色）
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.blue)
                                    .frame(width: 5, height: max(2, min(40, CGFloat(dataPoint.value) * 1.5)))
                                
                                // 重量柱子（粉色）
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.pink)
                                    .frame(width: 5, height: max(2, min(40, CGFloat(weightData[index]) * 0.1)))
                            }
                            
                            // 日期标签
                            Text(dataPoint.dayLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 100)
            }
        }
        .onAppear {
            updateChartData()
        }
        .onChange(of: exerciseType) { _, newType in
            print("📊 \(NSLocalizedString("exerciseType", comment: "运动类型")) 变化: \(newType.displayName)")
            updateChartData(exerciseType: newType, weekDate: weekDate)
        }
        .onChange(of: weekDate) { _, newDate in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            print("📊 \(NSLocalizedString("debug_week_date_changed", comment: "weekDate 变化")): \(formatter.string(from: newDate))")
            updateChartData(exerciseType: exerciseType, weekDate: newDate)
        }
    }
    
    private func updateChartData() {
        updateChartData(exerciseType: exerciseType, weekDate: weekDate)
    }
    
    private func updateChartData(exerciseType: ExerciseType, weekDate: Date) {
        let weekDaysString = NSLocalizedString("week_days", comment: "一,二,三,四,五,六,日")
        let weekDays = weekDaysString.components(separatedBy: ",")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("   \(NSLocalizedString("debug_input_week_date", comment: "传入 weekDate")): \(formatter.string(from: weekDate))")
        print("   \(NSLocalizedString("debug_input_exercise_type", comment: "传入 exerciseType")): \(exerciseType.displayName)")
        
        let weeklyData = dataManager.getWeeklyDataForExercise(exerciseType, for: weekDate)
        let weeklyWeightData = dataManager.getWeeklyWeightDataForExercise(exerciseType, for: weekDate)
        print("📊 \(NSLocalizedString("debug_update_chart_data", comment: "更新图表，获取数据"))：\(weeklyData), \(exerciseType.displayName)")
        print("📊 重量数据：\(weeklyWeightData)")
        var data: [ChartDataPoint] = []
        
        for i in 0..<7 {
            data.append(ChartDataPoint(
                day: i,
                value: weeklyData[i],
                dayLabel: weekDays[i]
            ))
        }
        
        chartData = data
        weightData = weeklyWeightData
    }
}

struct ChartDataPoint {
    let day: Int
    let value: Int
    let dayLabel: String
}

#Preview {
    HistoryView(showingHistory: .constant(true))
        .environmentObject(DataManager.shared)
}