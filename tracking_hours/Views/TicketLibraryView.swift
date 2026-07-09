import SwiftUI

struct TicketLibraryView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @Environment(\.openWindow) private var openWindow

    @State private var filter: TicketFilter = .active
    @State private var selectedTicketCode: String?
    @State private var ticketPendingDeletion: JiraTicket?
    @State private var showingDeleteConfirmation = false

    private enum TicketFilter: String, CaseIterable, Identifiable {
        case active
        case closed
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .active:
                return "Active"
            case .closed:
                return "Closed"
            case .all:
                return "All"
            }
        }
    }

    private var tickets: [JiraTicket] {
        switch filter {
        case .active:
            return store.activeTickets
        case .closed:
            return store.closedTickets
        case .all:
            return store.sortedTickets
        }
    }

    private var selectedTicket: JiraTicket? {
        guard let selectedTicketCode else {
            return nil
        }

        return store.ticket(for: selectedTicketCode)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                if tickets.isEmpty {
                    EmptyStateView(
                        systemImage: filter == .closed ? "archivebox" : "tag",
                        title: emptyTitle,
                        message: emptyMessage
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(tickets, selection: $selectedTicketCode) {
                        TableColumn("Ticket") { ticket in
                            TicketLibraryCellText(text: ticket.code) {
                                openTicketDetail(ticket.code)
                            }
                        }
                        TableColumn("Description") { ticket in
                            TicketLibraryCellText(text: ticket.summary.isBlank ? "-" : ticket.summary) {
                                openTicketDetail(ticket.code)
                            }
                        }
                        TableColumn("Status") { ticket in
                            TicketStatusBadge(isClosed: ticket.isClosed)
                                .onTapGesture(count: 2) {
                                    openTicketDetail(ticket.code)
                                }
                        }
                        TableColumn("Entries") { ticket in
                            TicketLibraryCellText(text: "\(store.entryCount(forTicket: ticket.code))", monospaced: true) {
                                openTicketDetail(ticket.code)
                            }
                        }
                        TableColumn("Total") { ticket in
                            TicketLibraryCellText(text: "\(store.totalHours(forTicket: ticket.code).hoursText)h", monospaced: true) {
                                openTicketDetail(ticket.code)
                            }
                        }
                    }
                    .frame(minHeight: 360)
                }

                actionBar
            }
            .padding(20)
        }
        .navigationTitle("Tickets")
        .confirmationDialog(
            "Delete ticket",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete ticket and entries", role: .destructive) {
                deletePendingTicket()
            }
            Button("Cancel", role: .cancel) {
                ticketPendingDeletion = nil
            }
        } message: {
            if let ticketPendingDeletion {
                let entryCount = store.entryCount(forTicket: ticketPendingDeletion.code)
                if entryCount > 0 {
                    Text("This will delete \(ticketPendingDeletion.code) and its \(entryCount) associated time entries.")
                } else {
                    Text("This will delete \(ticketPendingDeletion.code).")
                }
            }
        }
        .onChange(of: filter) { _, _ in
            selectedTicketCode = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tickets")
                    .font(.title2.weight(.semibold))
                Text("\(store.activeTickets.count) active, \(store.closedTickets.count) closed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(TicketFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let selectedTicket {
                Text(selectedTicket.menuTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Select a ticket")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let selectedTicket {
                    openTicketDetail(selectedTicket.code)
                }
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
            .disabled(selectedTicket == nil)

            Button {
                toggleSelectedTicketState()
            } label: {
                Label(
                    selectedTicket?.isClosed == true ? "Restore" : "Close",
                    systemImage: selectedTicket?.isClosed == true ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }
            .disabled(selectedTicket == nil)

            Button(role: .destructive) {
                ticketPendingDeletion = selectedTicket
                showingDeleteConfirmation = ticketPendingDeletion != nil
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedTicket == nil)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .active:
            return "No active tickets"
        case .closed:
            return "No closed tickets"
        case .all:
            return "No tickets yet"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .active:
            return "Add a time entry to create the first active ticket."
        case .closed:
            return "Closed tickets will appear here when you archive them."
        case .all:
            return "Tickets are created automatically from time entries."
        }
    }

    private func openTicketDetail(_ ticketCode: String) {
        openWindow(value: TicketDetailPayload(ticketCode: ticketCode, date: nil))
    }

    private func toggleSelectedTicketState() {
        guard let selectedTicket else {
            return
        }

        store.setTicketClosed(code: selectedTicket.code, isClosed: !selectedTicket.isClosed)

        if filter != .all {
            selectedTicketCode = nil
        }
    }

    private func deletePendingTicket() {
        guard let ticketPendingDeletion else {
            return
        }

        store.deleteTicket(code: ticketPendingDeletion.code)
        selectedTicketCode = nil
        self.ticketPendingDeletion = nil
    }
}

private struct TicketLibraryCellText: View {
    let text: String
    var monospaced = false
    let action: () -> Void

    var body: some View {
        Text(text)
            .lineLimit(1)
            .modifier(TicketLibraryMonospacedModifier(isEnabled: monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: action)
    }
}

private struct TicketLibraryMonospacedModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.monospacedDigit()
        } else {
            content
        }
    }
}

private struct TicketStatusBadge: View {
    let isClosed: Bool

    var body: some View {
        Text(isClosed ? "Closed" : "Active")
            .font(.caption.weight(.medium))
            .foregroundStyle(isClosed ? .orange : .green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isClosed ? Color.orange : Color.green).opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
