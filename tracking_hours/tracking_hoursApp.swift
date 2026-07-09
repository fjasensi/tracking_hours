import SwiftUI
import UserNotifications

@main
struct TrackingHoursApp: App {
    @StateObject private var store = TimeTrackerStore()
    private let notificationDelegate = NotificationDelegate.shared

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }

        WindowGroup("Ticket Details", for: TicketDetailPayload.self) { $payload in
            if let payload {
                TicketDetailView(ticketCode: payload.ticketCode, date: payload.date)
                    .environmentObject(store)
            }
        }
        .defaultSize(width: 560, height: 460)

        WindowGroup("Entry Details", for: EntryDetailPayload.self) { $payload in
            if let payload {
                EntryDetailView(entryID: payload.entryID)
                    .environmentObject(store)
            }
        }
        .defaultSize(width: 520, height: 340)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
