import Foundation
import UserNotifications

enum NotificationPermissionState: String {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .notDetermined:
            return "Not determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "tracking-hours-daily-reminder"

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Could not request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    func authorizationState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    func refreshSchedule(settings: AppSettings, entries: [TimeEntry], calendar: Calendar = .current) async {
        let pendingRequests = await center.pendingNotificationRequests()
        let reminderIDs = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }

        center.removePendingNotificationRequests(withIdentifiers: reminderIDs)

        guard settings.notificationsEnabled else {
            return
        }

        for day in upcomingDays(count: 14, calendar: calendar) {
            await scheduleReminderIfNeeded(for: day, settings: settings, entries: entries, calendar: calendar)
        }
    }

    private func scheduleReminderIfNeeded(
        for day: Date,
        settings: AppSettings,
        entries: [TimeEntry],
        calendar: Calendar
    ) async {
        guard settings.isWorkday(day, calendar: calendar) else {
            return
        }

        guard let fireDate = calendar.date(
            bySettingHour: settings.notificationHour,
            minute: settings.notificationMinute,
            second: 0,
            of: day
        ), fireDate > Date() else {
            return
        }

        let dayTotal = entries
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.hours }
        let pendingHours = max(settings.targetHours - dayTotal, 0)

        guard pendingHours > 0.005 else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Time tracking reminder"
        content.body = "You still need to log \(pendingHours.hoursText)h today."
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: day, calendar: calendar),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Could not schedule notification: \(error.localizedDescription)")
        }
    }

    private func upcomingDays(count: Int, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: Date())

        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func identifier(for day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0

        return String(format: "%@-%04d%02d%02d", identifierPrefix, year, month, day)
    }
}
