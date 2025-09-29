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
                VStack(spacing: 8) {
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
                        .frame(maxHeight: 60)
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
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                
                Spacer()
                
                // 底部统计信息
                HStack {
                    HStack(spacing: 2) {
                        Text("\(getCurrentWeekTotal())")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("次")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("历史记录")
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
                Image(systemName: selectedExercise.icon)
                    .font(.title3)
                    .foregroundColor(.primary)
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
    
    private func switchToNextWeek() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        print("📅 切换前当前周日期: \(formatter.string(from: currentWeekDate))")
        
        if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) {
            print("📅 切换到下一周: \(formatter.string(from: nextWeek))")
            withAnimation(.easeInOut(duration: 0.3)) {
                currentWeekDate = nextWeek
            }
            print("📅 切换后当前周日期: \(formatter.string(from: currentWeekDate))")
        }
    }
    
    private func switchToPreviousWeek() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        print("📅 切换前当前周日期: \(formatter.string(from: currentWeekDate))")
        
        if let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekDate) {
            print("📅 切换到上一周: \(formatter.string(from: previousWeek))")
            withAnimation(.easeInOut(duration: 0.3)) {
                currentWeekDate = previousWeek
            }
            print("📅 切换后当前周日期: \(formatter.string(from: currentWeekDate))")
        }
    }
    
}

struct WeeklyChartView: View {
    let exerciseType: ExerciseType
    let weekDate: Date
    let dataManager: DataManager
    
    @State private var chartData: [ChartDataPoint] = []
    
    var body: some View {
        VStack(spacing: 4) {
            // 图表
            if chartData.isEmpty {
                // 空状态
                VStack {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无数据")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 柱状图
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(chartData, id: \.day) { dataPoint in
                        VStack(spacing: 2) {
                            // 柱子
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: 12, height: max(2, min(40, CGFloat(dataPoint.value) * 1.5)))
                            
                            // 日期标签
                            Text(dataPoint.dayLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 50)
            }
        }
        .onAppear {
            updateChartData()
        }
        .onChange(of: exerciseType) { _, newType in
            print("📊 exerciseType 变化: \(newType.displayName)")
            updateChartData(exerciseType: newType, weekDate: weekDate)
        }
        .onChange(of: weekDate) { _, newDate in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            print("📊 weekDate 变化: \(formatter.string(from: newDate))")
            updateChartData(exerciseType: exerciseType, weekDate: newDate)
        }
    }
    
    private func updateChartData() {
        updateChartData(exerciseType: exerciseType, weekDate: weekDate)
    }
    
    private func updateChartData(exerciseType: ExerciseType, weekDate: Date) {
        let weekDays = ["一", "二", "三", "四", "五", "六", "日"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        print("📊 WeeklyChartView.updateChartData() 被调用")
        print("   传入 weekDate: \(formatter.string(from: weekDate))")
        print("   传入 exerciseType: \(exerciseType.displayName)")
        
        let weeklyData = dataManager.getWeeklyDataForExercise(exerciseType, for: weekDate)
        print("📊 更新图表，获取数据：\(weeklyData), \(exerciseType.displayName)")
        var data: [ChartDataPoint] = []
        
        for i in 0..<7 {
            data.append(ChartDataPoint(
                day: i,
                value: weeklyData[i],
                dayLabel: weekDays[i]
            ))
        }
        
        chartData = data
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