import SwiftUI
#if GYMCOUNT_SYNC
import HealthKit
import UIKit

final class GymCountPhoneDelegate: NSObject, UIApplicationDelegate {
    private let health = HKHealthStore()

    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Complete authorization requested by the companion Watch app.
        // The completion Boolean is not a grant; the Watch checks write status itself.
        health.handleAuthorizationForExtension { _, error in
            if error != nil { print("手表健康授权未完成，请重新请求权限") }
        }
    }
}
#endif

@main
struct GymCountPhoneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: PhoneWorkoutStore
    @StateObject private var trainingReminder: PhoneTrainingReminder
    private let trainingDefaults: UserDefaults
    #if GYMCOUNT_SYNC
    @UIApplicationDelegateAdaptor(GymCountPhoneDelegate.self) private var appDelegate
    @StateObject private var capture: PhoneCaptureStore
    #endif

    init() {
        var defaults = UserDefaults.standard
        var reminderID = "phone.training.rest"
        var watchArchiveURL: URL?
        #if GYMCOUNT_SYNC
        if ProcessInfo.processInfo.arguments.contains("--isolated-ui-test") {
            let storageID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-storage-id=") })?
                .replacingOccurrences(of: "--ui-test-storage-id=", with: "") ?? UUID().uuidString
            defaults = UserDefaults(suiteName: "GymCountUITest." + storageID)!
            if ProcessInfo.processInfo.arguments.contains("--reset-record-view-preferences") {
                for key in ["records.history", "records.time-chart", "records.trends"] { defaults.removeObject(forKey: key) }
            }
            reminderID += ".uitest." + storageID
            watchArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("GymCountUITest/\(storageID)/watch-history.json")
        }
        #endif
        trainingDefaults = defaults
        let workoutStore = PhoneWorkoutStore(defaults: defaults, reminderID: reminderID, watchArchiveURL: watchArchiveURL)
        _store = StateObject(wrappedValue: workoutStore)
        let reminders = PhoneTrainingReminder(defaults: defaults, prefix: reminderID + ".daily")
        workoutStore.onTrainingDatesChanged = { [weak reminders] dates in reminders?.recordsChanged(dates: dates) }
        reminders.recordsChanged(dates: workoutStore.trainingDates)
        _trainingReminder = StateObject(wrappedValue: reminders)
        #if GYMCOUNT_SYNC
        _capture = StateObject(wrappedValue: PhoneCaptureStore(workoutStore: workoutStore, defaults: defaults,
            activateConnectivity: !ProcessInfo.processInfo.arguments.contains("--isolated-ui-test")))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(store)
                .environmentObject(trainingReminder)
                .defaultAppStorage(trainingDefaults)
                .task { await store.enrichRetainedDurations() }
                .task {
                    await trainingReminder.refresh(dates: store.trainingDates,
                        requestPermission: !ProcessInfo.processInfo.arguments.contains("--isolated-ui-test"))
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await trainingReminder.refresh(dates: store.trainingDates) } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    Task { await trainingReminder.refresh(dates: store.trainingDates) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    Task { await trainingReminder.refresh(dates: store.trainingDates) }
                }
                #if GYMCOUNT_SYNC
                .environmentObject(capture)
                #endif
        }
    }
}
