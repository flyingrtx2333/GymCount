//
//  ContentView.swift
//  GymCount Watch App
//
//  Created by 向钧升 on 2025/9/26.
//

import SwiftUI

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
    static let trainingCounter = Font.system(size: 48, weight: .semibold, design: .rounded)
    static let counter = Font.system(size: 38, design: .rounded).weight(.semibold)
    static let mint = Color(red: 181 / 255, green: 244 / 255, blue: 216 / 255)
    static let surface = Color(red: 18 / 255, green: 20 / 255, blue: 20 / 255)
    static let muted = Color.white.opacity(0.55)
}

// Compact headers share a row with the clock; full-width headers sit just below it.
extension View {
    func gymPageContent(fullWidthHeader: Bool = false) -> some View {
        padding(.horizontal, GymStyle.inset)
            .padding(.top, fullWidthHeader ? 32 : 12)
            .padding(.bottom, 12)
    }

    func gymPage() -> some View {
        ignoresSafeArea(.container, edges: .top)
            .font(GymStyle.body)
            .foregroundStyle(.white)
            .background(Color.black)
            .tint(GymStyle.mint)
    }
}

// Shared native controls; exercise illustrations remain vector assets.
struct GymActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GymStyle.button)
            .foregroundStyle(primary ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: GymStyle.buttonHeight)
            .background(primary ? GymStyle.mint : GymStyle.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Color.clear : GymStyle.mint.opacity(0.25), lineWidth: 0.5))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.65 : 1)
    }
}

struct GymHeader: View {
    let title: String
    var back: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
            }
            Text(title).font(GymStyle.title)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(minHeight: back == nil ? 24 : 44)
        .frame(height: 28)
    }
}

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedExercise: ExerciseType = .benchPress
    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
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
        .tint(GymStyle.mint)
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
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("训练").font(GymStyle.title)
                    Spacer(minLength: 0)
                    Button { showingHistory = true } label: {
                        Image(systemName: "chart.bar.fill").frame(width: 32, height: 44)
                    }.accessibilityLabel("历史")
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").frame(width: 32, height: 44)
                    }.accessibilityLabel("设置")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .frame(height: 28)
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
            .gymPageContent(fullWidthHeader: true)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden)
        .gymPage()
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
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                // 名称
                Text(exercise.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer()

                // 开始指示
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GymStyle.mint)
                    .frame(width: 28, height: 28)
                    .background(GymStyle.mint.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? GymStyle.mint.opacity(0.07) : Color.clear)
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
