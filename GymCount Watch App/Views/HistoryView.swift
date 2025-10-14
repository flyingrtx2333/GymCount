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
    
    init(showingHistory: Binding<Bool>) {
        self._showingHistory = showingHistory
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // 中间主区域：使用TabView显示不同运动类型
                TabView(selection: $selectedExercise) {
                    ForEach(ExerciseType.allCases, id: \.self) { exercise in
                        VStack(spacing: 0) {
                            Spacer()
                            
                            // 周标题
                            Text(getWeekTitle())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // 图表区域
                            WeeklyChartView(
                                exerciseType: exercise,
                                weekDate: currentWeekDate,
                                dataManager: dataManager
                            )
                            .frame(maxHeight: 100)
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
                        }
                        .padding(.vertical, 8)
                        .tag(exercise)
                    }
                }
                .tabViewStyle(.verticalPage)
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
                }
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

    @State private var chartData: [WeeklyChartData] = []

    var body: some View {
        VStack {
            if chartData.isEmpty {
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
                Chart {
                    ForEach(chartData) { d in
                        // 先绘制折线图（在底层）
                        LineMark(
                            x: .value("Day", d.dayLabel),
                            y: .value("WeightScaled", d.weightScaled)
                        )
                        .foregroundStyle(.pink)
                        .lineStyle(StrokeStyle(lineWidth: 3)) // 增加线宽确保可见性
                        
                        // 再绘制数据点（在折线上）
                        PointMark(
                            x: .value("Day", d.dayLabel),
                            y: .value("WeightScaled", d.weightScaled)
                        )
                        .foregroundStyle(.pink)
                        .symbolSize(40) // 增加点的大小
                        
                        // 最后绘制柱状图（在顶层，但设置透明度）
                        BarMark(
                            x: .value("Day", d.dayLabel),
                            y: .value("Count", d.count)
                        )
                        .foregroundStyle(.blue.opacity(0.7)) // 设置透明度让折线图可见
                    }
                }
                // 双Y轴设置
                .chartYAxis {
                    // 左侧Y轴（次数）
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                    // 右侧Y轴（重量）
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let scaled = value.as(Double.self) {
                                // 反算回来显示真实重量
                                let real = scaled / weightScaleFactor
                                Text(String(format: "%.0f", real))
                            }
                        }
                    }
                }
                // 自定义 Y 轴的 domain（用次数最大值 + 缩放后重量最大值做范围）
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 100)
                .chartLegend(.hidden)  // 隐藏默认图例
                // 你可以在这里自己放 legend
            }
        }
        .onAppear { updateChartData() }
        .onChange(of: exerciseType) { _, _ in updateChartData() }
        .onChange(of: weekDate) { _, _ in updateChartData() }
    }

    // 缩放因子，用于把重量映射到可与次数共用的尺度上
    var weightScaleFactor: Double {
        let maxCount = chartData.map { $0.count }.max() ?? 0
        let maxWeight = chartData.map { $0.weight }.max() ?? 1
        if maxWeight == 0 { return 1 }
        return Double(maxCount) / maxWeight
    }

    // 计算 y 轴 domain，包括次数和缩放后重量的范围
    var yDomain: ClosedRange<Double> {
        let maxCount = Double(chartData.map { $0.count }.max() ?? 0)
        let maxWeightScaled = chartData.map { $0.weightScaled }.max() ?? 0
        let maxValue = max(maxCount, maxWeightScaled)
        return 0 ... (maxValue * 1.1) // 给一点上方余量
    }

    private func updateChartData() {
        let weekDaysString = NSLocalizedString("week_days", comment: "一,二,三,四,五,六,日")
        let weekDays = weekDaysString.components(separatedBy: ",")
        let weeklyCounts = dataManager.getWeeklyDataForExercise(exerciseType, for: weekDate)
        let weeklyWeights = dataManager.getWeeklyWeightDataForExercise(exerciseType, for: weekDate)
        
        // 先计算缩放因子
        let maxCount = weeklyCounts.max() ?? 0
        let maxWeight = weeklyWeights.max() ?? 1
        let scaleFactor = maxWeight > 0 ? Double(maxCount) / maxWeight : 1.0
        
        var arr: [WeeklyChartData] = []
        for i in 0..<7 {
            let wt = weeklyWeights[i]
            let wtScaled = wt * scaleFactor
            arr.append(WeeklyChartData(
                day: i,
                dayLabel: weekDays[i],
                count: weeklyCounts[i],
                weight: wt,
                weightScaled: wtScaled
            ))
        }
        chartData = arr
    }
}

struct WeeklyChartData: Identifiable {
    let id = UUID()
    let day: Int
    let dayLabel: String
    let count: Int
    let weight: Double
    let weightScaled: Double
}



#Preview {
    HistoryView(showingHistory: .constant(true))
        .environmentObject(DataManager.shared)
}