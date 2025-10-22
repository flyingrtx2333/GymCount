import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - 权限检查
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
                print("🔔 通知权限状态: \(self.statusDescription(settings.authorizationStatus))")
            }
        }
    }
    
    // MARK: - 请求通知权限
    func requestNotificationPermission() async -> Bool {
        // 先检查当前状态
        let currentSettings = await UNUserNotificationCenter.current().notificationSettings()
        print("🔔 当前通知权限状态: \(statusDescription(currentSettings.authorizationStatus))")
        
        // 如果已经是 authorized，不需要再次请求
        if currentSettings.authorizationStatus == .authorized {
            print("🔔 通知权限已完全授权，无需重复请求")
            await MainActor.run {
                self.checkAuthorizationStatus()
            }
            return true
        }
        
        // 如果是 provisional 状态，尝试请求完全授权
        if currentSettings.authorizationStatus == .provisional {
            print("🔔 当前为临时授权状态，尝试请求完全授权...")
        }
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            await MainActor.run {
                self.checkAuthorizationStatus()
            }
            
            print("🔔 通知权限请求结果: \(granted ? "已授权" : "已拒绝")")
            return granted
        } catch {
            print("❌ 请求通知权限失败: \(error)")
            return false
        }
    }
    
    // MARK: - 设置每日提醒通知
    func scheduleDailyReminder() {
        guard isAuthorized else {
            print("❌ 通知权限未授权，无法设置每日提醒")
            return
        }
        
        // 清除之前的每日提醒
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        
        // 生成个性化的鼓励消息
        let dataManager = DataManager.shared
        let (title, message) = dataManager.generateDailyEncouragementMessage()
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.badge = 1
        
        // 设置每天下午2:29触发
        var dateComponents = DateComponents()
        dateComponents.hour = 14
        dateComponents.minute = 29
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "daily_reminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 设置每日提醒失败: \(error)")
            } else {
                print("✅ 每日提醒已设置（每天下午2:29）")
            }
        }
    }
    
    // MARK: - 发送每日鼓励通知
    func sendDailyEncouragementNotification() {
        guard isAuthorized else {
            print("❌ 通知权限未授权，无法发送通知")
            return
        }
        
        let dataManager = DataManager.shared
        let (title, message) = dataManager.generateDailyEncouragementMessage()
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "daily_encouragement_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 发送每日鼓励通知失败: \(error)")
            } else {
                print("✅ 每日鼓励通知已发送")
            }
        }
    }
    
    // MARK: - 发送提醒通知
    func sendReminderNotification(message: String) {
        guard isAuthorized else {
            print("❌ 通知权限未授权，无法发送通知")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("reminder", comment: "提醒")
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "reminder_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 发送提醒通知失败: \(error)")
            } else {
                print("✅ 提醒通知已发送")
            }
        }
    }
    
    // MARK: - 清除所有通知
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        print("✅ 已清除所有通知")
    }
    
    // MARK: - 状态描述
    private func statusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return NSLocalizedString("not_determined", comment: "未确定")
        case .denied:
            return NSLocalizedString("denied", comment: "已拒绝")
        case .authorized:
            return NSLocalizedString("authorized", comment: "已授权")
        case .provisional:
            return NSLocalizedString("provisional", comment: "临时授权")
        case .ephemeral:
            return NSLocalizedString("ephemeral", comment: "临时授权")
        @unknown default:
            return NSLocalizedString("unknown_status", comment: "未知")
        }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "测试通知"
        content.body = "这是一条测试通知，5秒后显示"
        content.sound = .default
        
        // 5秒后触发,给你时间切换到后台
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 测试通知失败: \(error)")
            } else {
                print("✅ 测试通知将在5秒后显示，请切换到后台")
            }
        }
    }
    
    // MARK: - 调试方法
    func debugPendingNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            print("📋 当前待发送的通知数量: \(requests.count)")
            for (index, request) in requests.enumerated() {
                print("  \(index + 1). ID: \(request.identifier)")
                print("     标题: \(request.content.title)")
                print("     内容: \(request.content.body)")
                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                    print("     触发时间: \(trigger.dateComponents)")
                }
            }
        }
    }
}