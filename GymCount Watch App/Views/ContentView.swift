//
//  ContentView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

// One type scale for labels, controls and supporting text across watch screens.
enum GymStyle {
    static let body = Font.system(size: 13)
    static let button = Font.system(size: 13).weight(.semibold)
    static let detail = Font.system(size: 11)
    static let counter = Font.system(size: 22, design: .rounded).weight(.bold)
    static let surface = Color.white.opacity(0.08)
}

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedExercise: ExerciseType = .benchPress
    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            if dataManager.currentSession != nil {
                CounterView()
            } else {
                MainMenuView(
                    selectedExercise: $selectedExercise,
                    showingHistory: $showingHistory,
                    showingSettings: $showingSettings
                )
            }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(showingHistory: $showingHistory)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// MARK: - 主菜单

struct MainMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedExercise: ExerciseType
    @Binding var showingHistory: Bool
    @Binding var showingSettings: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isSelected: selectedExercise == exercise
                    ) {
                        selectedExercise = exercise
                        dataManager.startWorkout(
                            exerciseType: exercise,
                            weight: dataManager.settings.defaultWeight
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("app_name", comment: "健身计数"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { showingHistory = true }) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.secondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 运动卡片

struct ExerciseCard: View {
    let exercise: ExerciseType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // 图标
                Image(exercise.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)

                // 名称
                Text(exercise.displayName)
                    .font(GymStyle.button)
                    .foregroundColor(.white)

                Spacer()

                // 开始指示
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager.shared)
}
