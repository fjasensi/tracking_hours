import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                workdayPanel
                notificationPanel
                dataPanel
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .navigationTitle("Settings")
        .task {
            await store.refreshNotificationPermission()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Text("Configure the daily target and local reminder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var workdayPanel: some View {
        SectionPanel(title: "Workday", detail: "Target and workdays") {
            VStack(alignment: .leading, spacing: 14) {
                Stepper(value: targetHoursBinding, in: 0.25...24, step: 0.25) {
                    HStack {
                        Text("Daily target hours")
                        Spacer()
                        Text("\(store.settings.targetHours.hoursText)h")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Workdays")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Weekdays.all) { weekday in
                        Toggle(weekday.title, isOn: workdayBinding(for: weekday.id))
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private var notificationPanel: some View {
        SectionPanel(title: "Daily notification", detail: "Reminder when hours are missing") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable daily notification", isOn: notificationsEnabledBinding)
                    .toggleStyle(.switch)

                DatePicker("Reminder time", selection: notificationTimeBinding, displayedComponents: .hourAndMinute)
                    .disabled(!store.settings.notificationsEnabled)

                HStack {
                    Text("System permission")
                    Spacer()
                    Text(store.notificationPermission.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(permissionColor)
                }

                HStack {
                    Button {
                        Task {
                            await store.requestNotificationPermission()
                        }
                    } label: {
                        Label("Request permission", systemImage: "bell.badge")
                    }

                    Button {
                        Task {
                            await store.refreshNotifications()
                        }
                    } label: {
                        Label("Reschedule", systemImage: "arrow.clockwise")
                    }
                    .disabled(!store.settings.notificationsEnabled)
                }
            }
        }
    }

    private var dataPanel: some View {
        SectionPanel(title: "Local data", detail: "JSON in Application Support") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Data file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.dataFileURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(3)

                if let error = store.lastPersistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var targetHoursBinding: Binding<Double> {
        Binding {
            store.settings.targetHours
        } set: { newValue in
            store.updateSettings { settings in
                settings.targetHours = newValue
            }
        }
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding {
            store.settings.notificationsEnabled
        } set: { newValue in
            store.updateSettings { settings in
                settings.notificationsEnabled = newValue
            }

            if newValue {
                Task {
                    await store.requestNotificationPermission()
                }
            }
        }
    }

    private var notificationTimeBinding: Binding<Date> {
        Binding {
            let today = Calendar.current.startOfDay(for: Date())
            return Calendar.current.date(
                bySettingHour: store.settings.notificationHour,
                minute: store.settings.notificationMinute,
                second: 0,
                of: today
            ) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)

            store.updateSettings { settings in
                settings.notificationHour = components.hour ?? 17
                settings.notificationMinute = components.minute ?? 55
            }
        }
    }

    private func workdayBinding(for weekday: Int) -> Binding<Bool> {
        Binding {
            store.settings.workdays.contains(weekday)
        } set: { isEnabled in
            store.updateSettings { settings in
                if isEnabled {
                    settings.workdays.insert(weekday)
                } else {
                    settings.workdays.remove(weekday)
                }
            }
        }
    }

    private var permissionColor: Color {
        switch store.notificationPermission {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined, .unknown:
            return .secondary
        }
    }
}
