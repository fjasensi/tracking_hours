import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @State private var isExporting = false
    @State private var isChoosingImport = false
    @State private var isChoosingBackupParent = false
    @State private var exportDocument = JSONDataDocument()
    @State private var pendingImport: PendingImport?
    @State private var dataOperationMessage: String?
    @State private var dataOperationFailed = false

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
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                showDataMessage("Data exported successfully.")
            case .failure(let error):
                showDataMessage(error.localizedDescription, isError: true)
            }
        }
        .fileImporter(
            isPresented: $isChoosingImport,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            prepareImport(result)
        }
        .fileImporter(
            isPresented: $isChoosingBackupParent,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            configureBackupFolder(result)
        }
        .alert(
            "Replace all local data?",
            isPresented: importConfirmationBinding,
            presenting: pendingImport
        ) { pendingImport in
            Button("Cancel", role: .cancel) {}
            Button("Import", role: .destructive) {
                performImport(pendingImport)
            }
        } message: { pendingImport in
            Text("\(pendingImport.filename) contains \(pendingImport.ticketCount) tickets and \(pendingImport.entryCount) time entries. Current data will be replaced.")
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
        SectionPanel(title: "Data and backups", detail: "Export, import and automatic copies") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.dataFileURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(3)

                HStack {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isChoosingImport = true
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                }

                Divider()

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic backups")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let directoryURL = store.automaticBackupDirectoryURL {
                            Text(directoryURL.path)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(3)
                            Text("A copy is created after every change; the latest 30 are kept.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not configured. Choose Documents as the parent folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(store.automaticBackupDirectoryURL == nil ? "Choose folder…" : "Change folder…") {
                            isChoosingBackupParent = true
                        }

                        if store.automaticBackupDirectoryURL != nil {
                            Button("Disable", role: .destructive) {
                                store.disableAutomaticBackups()
                                showDataMessage("Automatic backups disabled. Existing copies were not deleted.")
                            }
                        }
                    }
                }

                if let error = store.lastPersistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let error = store.lastBackupError {
                    Label(error, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let dataOperationMessage {
                    Label(
                        dataOperationMessage,
                        systemImage: dataOperationFailed ? "exclamationmark.triangle" : "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(dataOperationFailed ? .red : .green)
                }
            }
        }
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "tracking-hours-export-\(formatter.string(from: Date()))"
    }

    private var importConfirmationBinding: Binding<Bool> {
        Binding {
            pendingImport != nil
        } set: { isPresented in
            if !isPresented {
                pendingImport = nil
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = JSONDataDocument(data: try store.exportData())
            isExporting = true
        } catch {
            showDataMessage(error.localizedDescription, isError: true)
        }
    }

    private func prepareImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let preview = try store.importPreview(from: data)
            pendingImport = PendingImport(
                data: data,
                filename: url.lastPathComponent,
                ticketCount: preview.ticketCount,
                entryCount: preview.entryCount
            )
        } catch {
            showDataMessage(error.localizedDescription, isError: true)
        }
    }

    private func performImport(_ pendingImport: PendingImport) {
        do {
            try store.importData(pendingImport.data)
            showDataMessage("Imported \(pendingImport.filename) successfully.")
        } catch {
            showDataMessage(error.localizedDescription, isError: true)
        }
    }

    private func configureBackupFolder(_ result: Result<[URL], Error>) {
        do {
            guard let parentURL = try result.get().first else {
                return
            }

            let directoryURL = try store.configureAutomaticBackups(parentURL: parentURL)
            showDataMessage("Automatic backups enabled in \(directoryURL.lastPathComponent).")
        } catch {
            showDataMessage(error.localizedDescription, isError: true)
        }
    }

    private func showDataMessage(_ message: String, isError: Bool = false) {
        dataOperationMessage = message
        dataOperationFailed = isError
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

private struct PendingImport: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    let ticketCount: Int
    let entryCount: Int
}
