import Foundation
import UserNotifications

struct TrainingStreak {
    let days: Set<Date>
    let current: Int
    let longest: Int
    let trainedToday: Bool

    init(dates: [Date], now: Date = Date(), calendar: Calendar = .current) {
        days = Set(dates.filter { $0.timeIntervalSinceReferenceDate.isFinite && $0 <= now }
            .map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        trainedToday = days.contains(today)
        var cursor = trainedToday ? today : calendar.date(byAdding: .day, value: -1, to: today)
        var count = 0
        while let day = cursor, days.contains(day) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        current = count
        var best = 0, run = 0
        var previous: Date?
        for day in days.sorted() {
            run = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        longest = best
    }
}

struct TrainingReminderPlan {
    struct Entry {
        let id: String
        let date: Date
        let streakAtRisk: Int
        var body: String {
            streakAtRisk > 0
                ? String(localized: "已连续训练 \(streakAtRisk) 天，今天动一动，延续连动。")
                : String(localized: "今天还没训练，动一动吧。")
        }
    }

    let entries: [Entry]
    init(dates: [Date], now: Date = Date(), calendar: Calendar = .current,
         hour: Int = 20, minute: Int = 0, prefix: String) {
        let activity = TrainingStreak(dates: dates, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        // One-shot requests allow a saved workout to remove today's reminder.
        // Refresh after saves and activation. Leave room for other app notifications.
        entries = (0..<60).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  !activity.days.contains(day),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date > now else { return nil }
            let risk = offset == 0 ? activity.current : offset == 1 && activity.trainedToday ? activity.current : 0
            return Entry(id: Self.identifier(for: day, calendar: calendar, prefix: prefix), date: date, streakAtRisk: risk)
        }
    }

    static func identifier(for date: Date, calendar: Calendar = .current, prefix: String) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return prefix + ".\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

@MainActor
final class TrainingReminderScheduler {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var revision = 0
    nonisolated init() {}

    func cancelToday(prefix: String) {
        revision &+= 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            TrainingReminderPlan.identifier(for: Date(), prefix: prefix)
        ])
    }

    func replace(dates: [Date], enabled: Bool, hour: Int = 20, minute: Int = 0,
                 prefix: String, legacyIDs: [String] = []) async throws {
        revision &+= 1
        let version = revision
        if busy { await withCheckedContinuation { waiters.append($0) } }
        else { busy = true }
        defer {
            if waiters.isEmpty { busy = false }
            else { waiters.removeFirst().resume() }
        }
        guard version == revision else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard version == revision else { return }
        let owned = pending.filter { $0.identifier.hasPrefix(prefix + ".") || legacyIDs.contains($0.identifier) }
        center.removePendingNotificationRequests(withIdentifiers: owned.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        guard version == revision else { return }
        let activity = TrainingStreak(dates: dates)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            ($0.request.identifier.hasPrefix(prefix + ".") || legacyIDs.contains($0.request.identifier))
                && (!enabled || (activity.trainedToday && Calendar.current.isDateInToday($0.date)))
        }.map { $0.request.identifier })
        guard enabled else { return }
        let settings = await center.notificationSettings()
        guard version == revision else { return }
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
            throw TrainingReminderError.permission
        }
        let plan = TrainingReminderPlan(dates: dates, hour: hour, minute: minute, prefix: prefix)
        do {
            for entry in plan.entries {
                guard version == revision else { return }
                let content = UNMutableNotificationContent()
                content.title = String(localized: "训练提醒")
                content.body = entry.body
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
                try await center.add(UNNotificationRequest(identifier: entry.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                if version != revision {
                    center.removePendingNotificationRequests(withIdentifiers: [entry.id])
                    return
                }
            }
        } catch {
            // Keep already scheduled requests, surface the failure, and retry on activation.
            throw TrainingReminderError.scheduling
        }
    }
}

enum TrainingReminderError: LocalizedError {
    case permission, scheduling
    var errorDescription: String? {
        switch self {
        case .permission: String(localized: "请先允许通知，才能接收提醒")
        case .scheduling: String(localized: "提醒未能保存，请重试")
        }
    }
}
