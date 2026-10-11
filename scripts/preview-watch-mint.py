"""Build a separate sensor-free simulator fixture using the real Watch views.

The shipping entry point is never changed. Fixture actions stay in memory and
never upload data, start motion capture or write workouts to HealthKit.
"""
from pathlib import Path
import shutil

source = Path(__file__).resolve().parents[1]
target = Path('/tmp/GymCountMintFixture')
shutil.copytree(source, target, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.git', 'build', 'design', '*.xcarchive', '__pycache__'))
project = target / 'GymCountSync.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('com.flyingrtx.GymCount', 'com.flyingrtx.GymCount.mintfixture'))
info = target / 'GymCount-Sync-Watch-Info.plist'
info.write_text(info.read_text().replace('com.flyingrtx.GymCount', 'com.flyingrtx.GymCount.mintfixture'))
(target / 'GymCount Watch App/GymCountApp.swift').write_text(r'''import SwiftUI
@main
struct MintFixtureApp: App {
    init() {
        var settings = AppSettings.shared
        settings.healthKitSyncEnabled = false
        UserDefaults.standard.set(try! JSONEncoder().encode(settings), forKey: "app_settings")
        let manager = DataManager.shared
        manager.settings = settings
        manager.workoutHistory = []
        let monday = manager.getWeekInfo(for: Date()).startDate
        for (day, count) in [8, 12, 6, 10, 14, 8, 2].enumerated() {
            var session = WorkoutSession(exerciseType: .squat,
                startTime: Calendar.current.date(byAdding: .day, value: day, to: monday)!, weight: 50)
            for _ in 0..<count { session.addRep(weight: 50) }
            session.endSession()
            manager.workoutHistory.append(WorkoutHistory(from: session))
        }
    }
    var body: some Scene { WindowGroup { MintFixtureScreen() } }
}
struct MintFixtureScreen: View {
    @State private var exercise = "squat"
    @State private var actual = 10
    @State private var count = 10
    @State private var notes = ""
    @State private var recording = false
    @State private var reviewing = false
    @State private var settings = false
    @State private var history = false
    @State private var status = ""
    var mode: String { ProcessInfo.processInfo.environment["GYMCOUNT_LAYOUT_SCREEN"] ?? "home" }
    var body: some View {
        Group {
            if mode == "settings" { SettingsView() }
            else if mode == "help" { HelpView() }
            else if mode == "weightinput" { WeightInputView(weight: .constant(50), onSave: { _ in }) }
            else {
                NavigationStack {
                    if mode == "home" {
                        MainMenuView(selectedExercise: .constant(.squat), showingHistory: $history, showingSettings: $settings)
                            .sheet(isPresented: $settings) { SettingsView() }
                            .sheet(isPresented: $history) { HistoryView(showingHistory: $history) }
                    } else if mode == "history" {
                        HistoryView(showingHistory: $history)
                    } else if mode == "weight" {
                        WeightAdjustmentView(label: "器械重量", value: .constant(50), step: 2.5, minValue: 0, maxValue: .infinity)
                    } else if mode == "counter" {
                        CounterPanel(exercise: "深蹲", count: count, weight: 50,
                            onWeight: { settings = true },
                            onMinus: { count = max(0, count - 1) }, onPlus: { count += 1 },
                            onEnd: { status = "结束" })
                            .toolbar(.hidden)
                    } else {
                        CollectionPanel(exercise: $exercise, actual: $actual, notes: $notes,
                            recording: recording || mode == "recording",
                            reviewing: reviewing || ["review", "uploading", "retry"].contains(mode),
                            detected: mode == "ready" ? 0 : 9,
                            uploading: mode == "uploading", pending: mode == "retry" ? 2 : 0,
                            message: status.isEmpty && mode == "retry" ? "记录已保留，可重试上传" : status,
                            onStartStop: { if recording { recording = false; reviewing = true } else { recording = true } },
                            onUpload: { status = "预览 · 未上传" },
                            onDiscard: { reviewing = false; status = "预览 · 已丢弃" },
                            onRetry: { status = "预览 · 未上传" }, onBack: {},
                            onPhoneSync: { status = "预览 · 未连接手机" })
                            .toolbar(.hidden)
                    }
                }
            }
        }
        .environmentObject(DataManager.shared)
        .environmentObject(NotificationManager.shared)
        .environment(\.locale, Locale(identifier: "zh_Hans"))
        .tint(GymStyle.mint)
    }
}
''')
print(target)
