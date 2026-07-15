import SwiftUI

private enum TicketSelection {
    static let newTicket = "__new_ticket__"
}

struct TodayView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedEntryID: TimeEntry.ID?
    @State private var editingEntry: TimeEntry?
    @State private var entryPendingDeletion: TimeEntry?
    @State private var showingDeleteConfirmation = false

    private var summary: DaySummary {
        store.daySummary(for: store.selectedDate)
    }

    private var dayEntries: [TimeEntry] {
        store.entries(on: store.selectedDate)
    }

    private var ticketSummaries: [TicketDaySummary] {
        store.ticketSummaries(on: store.selectedDate)
    }

    private var selectedEntry: TimeEntry? {
        guard let selectedEntryID else {
            return nil
        }

        return store.entries.first { $0.id == selectedEntryID }
    }

    private var entryAvailableForDeletion: TimeEntry? {
        selectedEntry ?? (dayEntries.count == 1 ? dayEntries.first : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)
            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        metrics
                        ticketSummaryPanel
                        entryPanel

                        if let error = store.lastPersistenceError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    QuickEntryPanel()
                        .frame(width: 320)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Today")
        .sheet(item: $editingEntry) { entry in
            EntryEditorView(entry: entry)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Delete time entry",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedEntry()
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            if let entryPendingDeletion {
                Text("This will delete \(entryPendingDeletion.hours.hoursText)h from \(entryPendingDeletion.ticketCode).")
            } else {
                Text("This will delete the selected entry.")
            }
        }
        .onChange(of: store.selectedDate) { _, _ in
            selectedEntryID = nil
            entryPendingDeletion = nil
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily tracking")
                    .font(.title2.weight(.semibold))
                Text(AppFormatters.longDateFormatter.string(from: store.selectedDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DayStatusPill(summary: summary)

            Spacer()

            DatePicker("Date", selection: $store.selectedDate, displayedComponents: .date)
                .labelsHidden()

            Button {
                store.selectedDate = Date()
            } label: {
                Label("Today", systemImage: "calendar")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Logged total",
                value: "\(summary.totalHours.hoursText)h",
                footnote: "Target \(store.settings.targetHours.hoursText)h",
                systemImage: "sum",
                tint: .accentColor
            )

            MetricTile(
                title: "Remaining",
                value: "\(summary.pendingHours.hoursText)h",
                footnote: summary.isComplete ? "Day complete" : "Until the day is complete",
                systemImage: summary.isComplete ? "checkmark.circle.fill" : "hourglass",
                tint: summary.isComplete ? .green : .orange
            )

            MetricTile(
                title: "Over target",
                value: "\(summary.excessHours.hoursText)h",
                footnote: summary.excessHours > 0.005 ? "Above the target" : "No overage",
                systemImage: "plus.forwardslash.minus",
                tint: .blue
            )

            MetricTile(
                title: "Tickets",
                value: "\(summary.distinctTicketCount)",
                footnote: "Distinct tickets today",
                systemImage: "tag",
                tint: .purple
            )
        }
    }

    private var ticketSummaryPanel: some View {
        SectionPanel(title: "Tickets for the day", detail: "Grouped by ticket") {
            if ticketSummaries.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "No tickets yet",
                    message: "Add a time entry to see the grouped summary here."
                )
                .frame(minHeight: 170)
            } else {
                Table(ticketSummaries) {
                    TableColumn("Ticket") { ticket in
                        DoubleClickText(text: ticket.ticketCode) {
                            openTicketDetail(ticket.ticketCode)
                        }
                    }
                    TableColumn("Description") { ticket in
                        DoubleClickText(text: ticket.summary.isEmpty ? "-" : ticket.summary) {
                            openTicketDetail(ticket.ticketCode)
                        }
                    }
                    TableColumn("Hours") { ticket in
                        DoubleClickText(text: "\(ticket.hours.hoursText)h", monospaced: true) {
                            openTicketDetail(ticket.ticketCode)
                        }
                    }
                    TableColumn("Entries") { ticket in
                        DoubleClickText(text: "\(ticket.entryCount)", monospaced: true) {
                            openTicketDetail(ticket.ticketCode)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
        }
    }

    private var entryPanel: some View {
        SectionPanel(title: "Entries for the day", detail: "Editable individually") {
            if dayEntries.isEmpty {
                EmptyStateView(
                    systemImage: "square.and.pencil",
                    title: "No entries",
                    message: "Use the quick entry panel to log the first ticket for the day."
                )
                .frame(minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    Table(dayEntries, selection: $selectedEntryID) {
                        TableColumn("Ticket") { entry in
                            entryCell(text: entry.ticketCode, entry: entry)
                        }
                        TableColumn("Description") { entry in
                            entryCell(text: entry.summary.isEmpty ? "-" : entry.summary, entry: entry)
                        }
                        TableColumn("Hours") { entry in
                            entryCell(text: "\(entry.hours.hoursText)h", monospaced: true, entry: entry)
                        }
                        TableColumn("Comment") { entry in
                            entryCell(text: entry.comment.isEmpty ? "-" : entry.comment, entry: entry)
                        }
                    }
                    .frame(minHeight: 220)

                    HStack {
                        Text("\(dayEntries.count) entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            editingEntry = selectedEntry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(selectedEntry == nil)

                        Button(role: .destructive) {
                            entryPendingDeletion = entryAvailableForDeletion
                            showingDeleteConfirmation = entryPendingDeletion != nil
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(entryAvailableForDeletion == nil)
                    }
                }
            }
        }
    }

    private func deleteSelectedEntry() {
        guard let entryPendingDeletion else {
            return
        }

        store.deleteEntry(id: entryPendingDeletion.id)
        selectedEntryID = nil
        self.entryPendingDeletion = nil
    }

    private func openTicketDetail(_ ticketCode: String) {
        openWindow(value: TicketDetailPayload(ticketCode: ticketCode, date: store.selectedDate))
    }

    private func openEntryDetail(_ entryID: TimeEntry.ID) {
        openWindow(value: EntryDetailPayload(entryID: entryID))
    }

    private func entryCell(text: String, monospaced: Bool = false, entry: TimeEntry) -> some View {
        DoubleClickText(
            text: text,
            monospaced: monospaced,
            onSelect: { selectedEntryID = entry.id }
        ) {
            openEntryDetail(entry.id)
        }
    }
}

private struct DoubleClickText: View {
    let text: String
    let monospaced: Bool
    let onSelect: () -> Void
    let action: () -> Void

    init(
        text: String,
        monospaced: Bool = false,
        onSelect: @escaping () -> Void = {},
        action: @escaping () -> Void
    ) {
        self.text = text
        self.monospaced = monospaced
        self.onSelect = onSelect
        self.action = action
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .modifier(MonospacedModifier(isEnabled: monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .simultaneousGesture(TapGesture(count: 2).onEnded(action))
    }
}

private struct MonospacedModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.monospacedDigit()
        } else {
            content
        }
    }
}

private struct TicketPickerField: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Binding var selectedTicketCode: String

    private var pickerTickets: [JiraTicket] {
        var tickets = store.activeTickets

        if
            selectedTicketCode != TicketSelection.newTicket,
            let selectedTicket = store.ticket(for: selectedTicketCode),
            selectedTicket.isClosed,
            !tickets.contains(where: { $0.code == selectedTicket.code })
        {
            tickets.append(selectedTicket)
        }

        return tickets.sorted { $0.code < $1.code }
    }

    var body: some View {
        Picker("Existing ticket", selection: $selectedTicketCode) {
            Text("New ticket").tag(TicketSelection.newTicket)

            ForEach(pickerTickets) { ticket in
                Text(ticket.isClosed ? "\(ticket.menuTitle) (closed)" : ticket.menuTitle)
                    .tag(ticket.code)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickEntryPanel: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @FocusState private var focusedField: Field?

    @State private var selectedTicketCode = TicketSelection.newTicket
    @State private var matchedCodeFromTyping: String?
    @State private var ticketCode = ""
    @State private var summary = ""
    @State private var hours = 0.5
    @State private var date = Date()
    @State private var comment = ""

    private enum Field: Hashable {
        case ticketCode
        case summary
        case hours
        case comment
    }

    private var canSubmit: Bool {
        !ticketCode.normalizedTicketCode.isEmpty && hours > 0 && hours <= 24
    }

    private var existingTicket: JiraTicket? {
        if selectedTicketCode != TicketSelection.newTicket {
            return store.ticket(for: selectedTicketCode)
        }

        if let matchedCodeFromTyping {
            return store.ticket(for: matchedCodeFromTyping)
        }

        return nil
    }

    var body: some View {
        SectionPanel(title: "New time entry", detail: "Quick entry") {
            VStack(alignment: .leading, spacing: 14) {
                field("Existing ticket") {
                    TicketPickerField(selectedTicketCode: $selectedTicketCode)
                }

                field("Ticket") {
                    TextField("ABC-123", text: $ticketCode)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .ticketCode)
                        .disabled(selectedTicketCode != TicketSelection.newTicket)
                }

                field("Description") {
                    TextField("Optional", text: $summary)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .summary)
                        .disabled(existingTicket != nil)
                }

                field("Hours") {
                    HStack {
                        TextField(
                            "0.5",
                            value: $hours,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .hours)
                        .frame(width: 86)

                        Stepper("", value: $hours, in: 0.25...24, step: 0.25)
                            .labelsHidden()

                        Text("h")
                            .foregroundStyle(.secondary)
                    }
                }

                field("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                field("Comment") {
                    TextField("Optional", text: $comment)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .comment)
                }

                Button {
                    submit()
                } label: {
                    Label("Add time entry", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .onAppear {
            date = store.selectedDate
            focusedField = .ticketCode
        }
        .onChange(of: store.selectedDate) { _, newDate in
            date = newDate
        }
        .onChange(of: selectedTicketCode) { _, newValue in
            selectTicket(newValue)
        }
        .onChange(of: ticketCode) { _, newValue in
            matchTypedTicket(newValue)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        store.addEntry(
            ticketCode: ticketCode,
            summary: summary,
            hours: hours,
            date: date,
            comment: comment
        )
        store.selectedDate = date

        ticketCode = ""
        summary = ""
        hours = 0.5
        comment = ""
        selectedTicketCode = TicketSelection.newTicket
        matchedCodeFromTyping = nil
        focusedField = .ticketCode
    }

    private func selectTicket(_ selection: String) {
        guard selection != TicketSelection.newTicket else {
            ticketCode = ""
            summary = ""
            matchedCodeFromTyping = nil
            focusedField = .ticketCode
            return
        }

        guard let ticket = store.ticket(for: selection) else {
            return
        }

        ticketCode = ticket.code
        summary = ticket.summary
        matchedCodeFromTyping = ticket.code
    }

    private func matchTypedTicket(_ code: String) {
        guard selectedTicketCode == TicketSelection.newTicket else {
            return
        }

        let cleanedCode = code.normalizedTicketCode
        guard !cleanedCode.isEmpty else {
            matchedCodeFromTyping = nil
            return
        }

        if let ticket = store.ticket(for: cleanedCode) {
            matchedCodeFromTyping = ticket.code
            summary = ticket.summary
        } else if matchedCodeFromTyping != nil {
            matchedCodeFromTyping = nil
            summary = ""
        }
    }
}

private struct EntryEditorView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry

    @State private var selectedTicketCode = TicketSelection.newTicket
    @State private var matchedCodeFromTyping: String?
    @State private var ticketCode: String
    @State private var summary: String
    @State private var hours: Double
    @State private var date: Date
    @State private var comment: String

    private var canSave: Bool {
        !ticketCode.normalizedTicketCode.isEmpty && hours > 0 && hours <= 24
    }

    private var existingTicket: JiraTicket? {
        if selectedTicketCode != TicketSelection.newTicket {
            return store.ticket(for: selectedTicketCode)
        }

        if let matchedCodeFromTyping {
            return store.ticket(for: matchedCodeFromTyping)
        }

        return nil
    }

    init(entry: TimeEntry) {
        self.entry = entry
        _ticketCode = State(initialValue: entry.ticketCode)
        _summary = State(initialValue: entry.summary)
        _hours = State(initialValue: entry.hours)
        _date = State(initialValue: entry.date)
        _comment = State(initialValue: entry.comment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit time entry")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                field("Existing ticket") {
                    TicketPickerField(selectedTicketCode: $selectedTicketCode)
                }

                field("Ticket") {
                    TextField("ABC-123", text: $ticketCode)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedTicketCode != TicketSelection.newTicket)
                }

                field("Description") {
                    TextField("Optional", text: $summary)
                        .textFieldStyle(.roundedBorder)
                        .disabled(existingTicket != nil)
                }

                field("Hours") {
                    HStack {
                        TextField(
                            "0.5",
                            value: $hours,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                        Stepper("", value: $hours, in: 0.25...24, step: 0.25)
                            .labelsHidden()

                        Text("h")
                            .foregroundStyle(.secondary)
                    }
                }

                field("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                field("Comment") {
                    TextField("Optional", text: $comment)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            configureInitialTicketSelection()
        }
        .onChange(of: selectedTicketCode) { _, newValue in
            selectTicket(newValue)
        }
        .onChange(of: ticketCode) { _, newValue in
            matchTypedTicket(newValue)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        store.updateEntry(
            id: entry.id,
            ticketCode: ticketCode,
            summary: summary,
            hours: hours,
            date: date,
            comment: comment
        )
        store.selectedDate = date
        dismiss()
    }

    private func configureInitialTicketSelection() {
        if let ticket = store.ticket(for: entry.ticketCode) {
            selectedTicketCode = ticket.code
            matchedCodeFromTyping = ticket.code
            summary = ticket.summary
        } else {
            selectedTicketCode = TicketSelection.newTicket
            matchedCodeFromTyping = nil
        }
    }

    private func selectTicket(_ selection: String) {
        guard selection != TicketSelection.newTicket else {
            ticketCode = ""
            summary = ""
            matchedCodeFromTyping = nil
            return
        }

        guard let ticket = store.ticket(for: selection) else {
            return
        }

        ticketCode = ticket.code
        summary = ticket.summary
        matchedCodeFromTyping = ticket.code
    }

    private func matchTypedTicket(_ code: String) {
        guard selectedTicketCode == TicketSelection.newTicket else {
            return
        }

        let cleanedCode = code.normalizedTicketCode
        guard !cleanedCode.isEmpty else {
            matchedCodeFromTyping = nil
            return
        }

        if let ticket = store.ticket(for: cleanedCode) {
            matchedCodeFromTyping = ticket.code
            summary = ticket.summary
        } else if matchedCodeFromTyping != nil {
            matchedCodeFromTyping = nil
            summary = ""
        }
    }
}

struct TicketDetailView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss

    let ticketCode: String
    let date: Date?

    @State private var showingDeleteTicketConfirmation = false

    private var ticket: JiraTicket? {
        store.ticket(for: ticketCode)
    }

    private var entries: [TimeEntry] {
        if let date {
            return store.entries(on: date).filter { $0.ticketCode == ticketCode.normalizedTicketCode }
        }

        return store.entries(forTicket: ticketCode)
    }

    private var totalHours: Double {
        entries.reduce(0) { $0 + $1.hours }
    }

    private var allEntryCount: Int {
        store.entryCount(forTicket: ticketCode)
    }

    private var allTotalHours: Double {
        store.totalHours(forTicket: ticketCode)
    }

    private var entriesTitle: String {
        date == nil ? "All entries" : "Entries for selected day"
    }

    var body: some View {
        if let ticket {
            ticketDetail(ticket)
        } else {
            EmptyStateView(
                systemImage: "tag.slash",
                title: "Ticket unavailable",
                message: "This ticket no longer exists."
            )
            .frame(width: 460, height: 280)
        }
    }

    private func ticketDetail(_ ticket: JiraTicket) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(ticket)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text("Status").foregroundStyle(.secondary)
                    Text(ticket.isClosed ? "Closed" : "Active")
                }
                if let date {
                    GridRow {
                        Text("Date").foregroundStyle(.secondary)
                        Text(AppFormatters.shortDateFormatter.string(from: date))
                    }
                }
                GridRow {
                    Text(date == nil ? "Total hours" : "Hours in scope").foregroundStyle(.secondary)
                    Text("\(totalHours.hoursText)h").monospacedDigit()
                }
                GridRow {
                    Text(date == nil ? "Entries" : "Entries in scope").foregroundStyle(.secondary)
                    Text("\(entries.count)").monospacedDigit()
                }
                if date != nil {
                    GridRow {
                        Text("Total logged").foregroundStyle(.secondary)
                        Text("\(allTotalHours.hoursText)h across \(allEntryCount) entries")
                            .monospacedDigit()
                    }
                }
            }

            actionBar(ticket)

            Divider()

            Text(entriesTitle)
                .font(.headline)

            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "No entries",
                    message: date == nil
                        ? "There are no time entries for this ticket."
                        : "There are no time entries for this ticket on the selected day."
                )
                .frame(height: 180)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(entry.hours.hoursText)h")
                                .font(.headline)
                                .monospacedDigit()
                            Spacer()
                            Text(AppFormatters.shortDateFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.comment.isBlank ? "No comment" : entry.comment)
                            .foregroundStyle(entry.comment.isBlank ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 420)
        .confirmationDialog(
            "Delete ticket",
            isPresented: $showingDeleteTicketConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete ticket and entries", role: .destructive) {
                store.deleteTicket(code: ticket.code)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if allEntryCount > 0 {
                Text("This will delete \(ticket.code) and its \(allEntryCount) associated time entries.")
            } else {
                Text("This will delete \(ticket.code).")
            }
        }
    }

    private func header(_ ticket: JiraTicket) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ticket.code)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Text(ticket.isClosed ? "Closed" : "Active")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ticket.isClosed ? .orange : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((ticket.isClosed ? Color.orange : Color.green).opacity(0.12), in: Capsule())
                }
                Text(ticket.summary.isBlank ? "No description" : ticket.summary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func actionBar(_ ticket: JiraTicket) -> some View {
        HStack {
            Button {
                store.setTicketClosed(code: ticket.code, isClosed: !ticket.isClosed)
            } label: {
                Label(ticket.isClosed ? "Restore ticket" : "Close ticket", systemImage: ticket.isClosed ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }

            Spacer()

            Button(role: .destructive) {
                showingDeleteTicketConfirmation = true
            } label: {
                Label("Delete ticket", systemImage: "trash")
            }
        }
    }
}

struct EntryDetailView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss

    let entryID: TimeEntry.ID

    private var entry: TimeEntry? {
        store.entries.first { $0.id == entryID }
    }

    var body: some View {
        if let entry {
            entryDetail(entry)
        } else {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Entry unavailable",
                message: "This entry no longer exists."
            )
            .frame(width: 420, height: 260)
        }
    }

    private func ticketSummary(for entry: TimeEntry) -> String {
        let summary = store.ticket(for: entry.ticketCode)?.summary ?? entry.summary
        return summary.isBlank ? "No description" : summary
    }

    private func entryDetail(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.ticketCode)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Text(ticketSummary(for: entry))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    Text("Date").foregroundStyle(.secondary)
                    Text(AppFormatters.shortDateFormatter.string(from: entry.date))
                }
                GridRow {
                    Text("Hours").foregroundStyle(.secondary)
                    Text("\(entry.hours.hoursText)h").monospacedDigit()
                }
                GridRow {
                    Text("Created").foregroundStyle(.secondary)
                    Text(AppFormatters.shortDateFormatter.string(from: entry.createdAt))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Comment")
                    .font(.headline)
                Text(entry.comment.isBlank ? "No comment" : entry.comment)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 320)
    }
}
