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
    @State private var showingHelp = false
    
    var body: some View {
        NavigationView {
            if dataManager.currentSession != nil {
                CounterDebugView()
            } else {
                MainMenuView(
                    selectedExercise: $selectedExercise,
                    showingHistory: $showingHistory,
                    showingSettings: $showingSettings,
                    showingHelp: $showingHelp
                )
            }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(showingHistory: $showingHistory)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
    }
}

struct MainMenuView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedExercise: ExerciseType
    @Binding var showingHistory: Bool
    @Binding var showingSettings: Bool
    @Binding var showingHelp: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // 应用标题
            // Text(NSLocalizedString("app_name", comment: "健身计数器"))
            //     .font(.headline)
            //     .foregroundColor(.primary)
            
            // 锻炼类型选择
            Picker("", selection: $selectedExercise) {
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    HStack {
                        Text(exercise.displayName)
                        Spacer()
                        Image(systemName: exercise.icon)
                        
                    }
                    .tag(exercise)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 60)
            
            // 开始按钮
            Button(action: {
                dataManager.startWorkout(exerciseType: selectedExercise, weight: dataManager.settings.defaultWeight)
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(NSLocalizedString("start", comment: "开始"))
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .cornerRadius(18)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 底部按钮
            HStack(spacing: 12) {
                Button(action: { showingHistory = true }) {
                    VStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                        Text(NSLocalizedString("history", comment: "历史记录"))
                            .font(.caption2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { showingSettings = true }) {
                    VStack {
                        Image(systemName: "gearshape")
                            .font(.title3)
                        Text(NSLocalizedString("settings", comment: "设置"))
                            .font(.caption2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { showingHelp = true }) {
                    VStack {
                        Image(systemName: "questionmark.circle")
                            .font(.title3)
                        Text("帮助")
                            .font(.caption2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager.shared)
}
