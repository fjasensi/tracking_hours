import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case today
    case tickets
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .tickets:
            return "Tickets"
        case .history:
            return "History"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "calendar.badge.clock"
        case .tickets:
            return "tag"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @State private var selection: SidebarDestination? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                }
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 28)
            }
            .navigationTitle("Jira Hours")
            .frame(minWidth: 180)
        } detail: {
            switch selection ?? .today {
            case .today:
                TodayView()
            case .tickets:
                TicketLibraryView()
            case .history:
                HistoryView { date in
                    store.selectedDate = date
                    selection = .today
                }
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
    }
}

#Preview {
    ContentView()
        .environmentObject(TimeTrackerStore())
}
