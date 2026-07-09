import Foundation

struct AppSettings: Codable, Equatable {
    static let defaultWorkdays: Set<Int> = [2, 3, 4, 5, 6]

    var targetHours: Double
    var notificationHour: Int
    var notificationMinute: Int
    var notificationsEnabled: Bool
    var workdays: Set<Int>

    init(
        targetHours: Double = 8,
        notificationHour: Int = 17,
        notificationMinute: Int = 55,
        notificationsEnabled: Bool = true,
        workdays: Set<Int> = AppSettings.defaultWorkdays
    ) {
        self.targetHours = targetHours
        self.notificationHour = notificationHour
        self.notificationMinute = notificationMinute
        self.notificationsEnabled = notificationsEnabled
        self.workdays = workdays
    }

    func isWorkday(_ date: Date, calendar: Calendar = .current) -> Bool {
        workdays.contains(calendar.component(.weekday, from: date))
    }
}
