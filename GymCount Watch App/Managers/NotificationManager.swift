import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published private(set) var reminderError: String?
    // The phone owns the default reminder; Watch-local reminders are opt-in.
    var dailyReminderEnabled: Bool { UserDefaults.standard.object(forKey: "notifications.daily.enabled") as? Bool ?? false }
    var dailyReminderTime: Date {
        Calendar.current.date(bySettingHour: UserDefaults.standard.object(forKey: "notifications.daily.hour") as? Int ?? 20,
            minute: UserDefaults.standard.object(forKey: "notifications.daily.minute") as? Int ?? 0, second: 0, of: Date()) ?? Date()
    }
    private var reminderGeneration = UUID()
    private var updatingReminder = false
    private let dailyScheduler = TrainingReminderScheduler()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let id = notification.request.identifier
            let isTraining = id.hasPrefix("watch.training.daily.") || id == "daily_reminder"
            let suppressed = isTraining && (!dailyReminderEnabled || TrainingStreak(dates: DataManager.shared.trainingDates).trainedToday)
            completionHandler(suppressed ? [] : [.banner, .sound])
        }
    }

    private func updateAuthorization(_ status: UNAuthorizationStatus) {
        authorizationStatus = status
        isAuthorized = status == .authorized || status == .provisional
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.updateAuthorization(settings.authorizationStatus) }
        }
    }

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        let status = settings.authorizationStatus
        await MainActor.run { updateAuthorization(status) }
        return status == .authorized || status == .provisional
    }

    @MainActor
    func updateDailyReminder(enabled: Bool, time: Date) async -> Bool {
        guard !updatingReminder else { return false }
        updatingReminder = true
        defer { updatingReminder = false }
        if enabled { _ = await requestNotificationPermission() }
        let generation = UUID(); reminderGeneration = generation
        guard await configureDailyReminder(generation, enabled: enabled, time: time) else { return false }
        let values = Calendar.current.dateComponents([.hour, .minute], from: time)
        UserDefaults.standard.set(enabled, forKey: "notifications.daily.enabled")
        UserDefaults.standard.set(values.hour ?? 20, forKey: "notifications.daily.hour")
        UserDefaults.standard.set(values.minute ?? 0, forKey: "notifications.daily.minute")
        scheduleDailyReminder()
        return true
    }

    func scheduleDailyReminder() {
        Task { @MainActor in
            if TrainingStreak(dates: DataManager.shared.trainingDates).trainedToday {
                dailyScheduler.cancelToday(prefix: "watch.training.daily")
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
            }
            guard !updatingReminder else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard !updatingReminder else { return }
            updateAuthorization(settings.authorizationStatus)
            let generation = UUID(); reminderGeneration = generation
            _ = await configureDailyReminder(generation, enabled: dailyReminderEnabled, time: dailyReminderTime)
        }
    }

    @MainActor
    private func configureDailyReminder(_ generation: UUID, enabled: Bool, time: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard reminderGeneration == generation else { return false }
        updateAuthorization(settings.authorizationStatus)
        reminderError = nil
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        do {
            try await dailyScheduler.replace(dates: DataManager.shared.trainingDates, enabled: enabled,
                hour: components.hour ?? 20, minute: components.minute ?? 0,
                prefix: "watch.training.daily", legacyIDs: ["daily_reminder"])
            guard reminderGeneration == generation else { return false }
            return true
        } catch {
            guard reminderGeneration == generation else { return false }
            reminderError = error.localizedDescription
            return false
        }
    }

    func sendDailyEncouragementNotification() {
        sendReminderNotification(message: String(localized: "有空时，动一动。"))
    }

    func sendReminderNotification(message: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "训练提醒")
        content.body = message
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "reminder_\(UUID().uuidString)", content: content, trigger: nil))
    }

    func clearAllNotifications() {
        reminderGeneration = UUID()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func sendTestNotification() {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "测试通知")
        content.body = String(localized: "这是一条测试通知，5秒后显示")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "notification_test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    func debugPendingNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { print("Pending notifications: \($0.count)") }
    }
}
