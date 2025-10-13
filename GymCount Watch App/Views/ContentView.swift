//
//  ContentView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

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

struct MainMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedExercise: ExerciseType
    @Binding var showingHistory: Bool
    @Binding var showingSettings: Bool
    
    var body: some View {
        ZStack {
            // 柔和渐变背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.8),
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.1),
                    Color.black.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                
                // 运动类型选择器
                Picker("",selection: $selectedExercise) {
                    ForEach(ExerciseType.allCases, id: \.self) { exercise in
                        HStack(spacing: 15) {
                            Image(systemName: exercise.icon)
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                            Spacer()
                            Text(exercise.displayName)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .tag(exercise)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .background(Color.clear)
                .clipped()
                .compositingGroup()
                .accentColor(.clear)
                .scrollContentBackground(.hidden)
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            //左上角
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { showingHistory = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            //右上角
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            // 下方
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: {
                        dataManager.startWorkout(exerciseType: selectedExercise, weight: dataManager.settings.defaultWeight)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 40, height: 40)
                                .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 2)
                            
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager.shared)
}

