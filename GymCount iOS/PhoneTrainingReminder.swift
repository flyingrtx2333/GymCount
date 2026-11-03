import Foundation
import Combine
import UserNotifications

@MainActor
final class PhoneTrainingReminder: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var enabled: Bool
    @Published private(set) var authorized = false
    @Published private(set) var updating = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let prefix: String
    private let scheduler = TrainingReminderScheduler()
    private var refreshCount = 0
    private var trainingDates: [Date] = []

    init(defaults: UserDefaults, prefix: String) {
        self.defaults = defaults
        self.prefix = prefix
        enabled = defaults.object(forKey: "records.training-reminder.enabled") as? Bool ?? true
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func recordsChanged(dates: [Date]) {
        trainingDates = dates
        if TrainingStreak(dates: dates).trainedToday { scheduler.cancelToday(prefix: prefix) }
        Task { await refresh(dates: dates) }
    }

    func setEnabled(_ value: Bool, dates: [Date]) async {
        guard !updating else { return }
        enabled = value
        defaults.set(value, forKey: "records.training-reminder.enabled")
        await refresh(dates: dates, requestPermission: value)
    }

    func refresh(dates: [Date], requestPermission: Bool = false) async {
        trainingDates = dates
        refreshCount += 1
        updating = true
        defer { refreshCount -= 1; updating = refreshCount > 0 }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if enabled && requestPermission && settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { self.error = String(localized: "提醒未能保存，请重试"); return }
            settings = await center.notificationSettings()
        }
        authorized = [.authorized, .provisional].contains(settings.authorizationStatus)
        do {
            try await scheduler.replace(dates: dates, enabled: enabled, prefix: prefix)
            error = nil
        } catch { self.error = error.localizedDescription }
        #if GYMCOUNT_SYNC
        if ProcessInfo.processInfo.arguments.contains("--isolated-ui-test"),
           ProcessInfo.processInfo.arguments.contains("--inspect-training-reminders") {
            let requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix + ".") }
            let observation: [String: Any] = ["enabled": enabled, "authorized": authorized,
                "error": error as Any? ?? NSNull(), "requests": requests.map {
                    ["id": $0.identifier, "body": $0.content.body,
                     "nextDate": ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()?.timeIntervalSince1970 as Any? ?? NSNull(),
                     "repeats": $0.trigger?.repeats ?? false] as [String: Any]
                }]
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("reminder-\(enabled ? "enabled" : "disabled").json"), options: .atomic)
            }
        }
        #endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let isTraining = notification.request.identifier.hasPrefix(prefix + ".")
            let suppressed = isTraining && (!enabled || TrainingStreak(dates: trainingDates).trainedToday)
            completionHandler(suppressed ? [] : [.banner, .sound])
        }
    }
}
