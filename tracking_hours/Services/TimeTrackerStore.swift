import Combine
import Foundation

@MainActor
final class TimeTrackerStore: ObservableObject {
    @Published var selectedDate: Date
    @Published private(set) var tickets: [JiraTicket]
    @Published private(set) var entries: [TimeEntry]
    @Published private(set) var settings: AppSettings
    @Published private(set) var notificationPermission: NotificationPermissionState = .unknown
    @Published private(set) var lastPersistenceError: String?

    private let persistence: LocalJSONPersistence
    private let notificationService: NotificationService
    private let calendar: Calendar

    init(
        persistence: LocalJSONPersistence? = nil,
        notificationService: NotificationService? = nil,
        calendar: Calendar = .current
    ) {
        self.persistence = persistence ?? LocalJSONPersistence()
        self.notificationService = notificationService ?? NotificationService()
        self.calendar = calendar

        let dataFile = self.persistence.load()
        self.tickets = Self.normalizedTickets(dataFile.tickets)
        self.entries = dataFile.entries
        self.settings = dataFile.settings
        self.selectedDate = Date()

        Task {
            await bootstrapNotifications()
        }
    }

    var dataFileURL: URL {
        persistence.fileURL
    }

    var sortedTickets: [JiraTicket] {
        tickets.sorted { $0.code < $1.code }
    }

    var activeTickets: [JiraTicket] {
        sortedTickets.filter { !$0.isClosed }
    }

    var closedTickets: [JiraTicket] {
        sortedTickets.filter(\.isClosed)
    }

    func ticket(for code: String) -> JiraTicket? {
        let cleanedCode = code.normalizedTicketCode
        return tickets.first { $0.code == cleanedCode }
    }

    func ticketDescription(for code: String) -> String {
        ticket(for: code)?.summary ?? ""
    }

    func entries(on date: Date) -> [TimeEntry] {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.ticketCode < $1.ticketCode
                }

                return $0.createdAt < $1.createdAt
            }
    }

    func entries(forTicket code: String) -> [TimeEntry] {
        let cleanedCode = code.normalizedTicketCode
        return entries
            .filter { $0.ticketCode == cleanedCode }
            .sorted {
                if $0.date == $1.date {
                    return $0.createdAt < $1.createdAt
                }

                return $0.date > $1.date
            }
    }

    func totalHours(forTicket code: String) -> Double {
        entries(forTicket: code).reduce(0) { $0 + $1.hours }
    }

    func entryCount(forTicket code: String) -> Int {
        entries(forTicket: code).count
    }

    func ticketSummaries(on date: Date) -> [TicketDaySummary] {
        let groupedEntries = Dictionary(grouping: entries(on: date)) { entry in
            entry.ticketCode
        }

        return groupedEntries.map { ticketCode, entries in
            let sortedEntries = entries.sorted { $0.createdAt < $1.createdAt }
            let firstSummary = ticketDescription(for: ticketCode).isBlank
                ? sortedEntries.first { !$0.summary.isBlank }?.summary ?? ""
                : ticketDescription(for: ticketCode)
            let hours = entries.reduce(0) { $0 + $1.hours }

            return TicketDaySummary(
                ticketCode: ticketCode,
                summary: firstSummary,
                hours: hours,
                entryCount: entries.count
            )
        }
        .sorted { $0.ticketCode < $1.ticketCode }
    }

    func totalHours(on date: Date) -> Double {
        entries(on: date).reduce(0) { $0 + $1.hours }
    }

    func pendingHours(on date: Date) -> Double {
        max(settings.targetHours - totalHours(on: date), 0)
    }

    func excessHours(on date: Date) -> Double {
        max(totalHours(on: date) - settings.targetHours, 0)
    }

    func daySummary(for date: Date) -> DaySummary {
        let dayEntries = entries(on: date)
        let totalHours = dayEntries.reduce(0) { $0 + $1.hours }
        let distinctTickets = Set(dayEntries.map(\.ticketCode)).count

        return DaySummary(
            date: calendar.startOfDay(for: date),
            totalHours: totalHours,
            pendingHours: max(settings.targetHours - totalHours, 0),
            excessHours: max(totalHours - settings.targetHours, 0),
            distinctTicketCount: distinctTickets
        )
    }

    func historySummaries() -> [DaySummary] {
        let groupedEntries = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }

        return groupedEntries.keys
            .map { daySummary(for: $0) }
            .sorted { $0.date > $1.date }
    }

    func addEntry(ticketCode: String, summary: String, hours: Double, date: Date, comment: String) {
        let cleanedTicketCode = ticketCode.normalizedTicketCode
        guard !cleanedTicketCode.isEmpty, hours > 0 else {
            return
        }

        let now = Date()
        let ticket = upsertTicket(code: cleanedTicketCode, summary: summary, timestamp: now)
        let entry = TimeEntry(
            ticketCode: cleanedTicketCode,
            summary: ticket.summary,
            hours: hours,
            date: date,
            comment: comment,
            createdAt: now,
            updatedAt: now
        )

        entries.append(entry)
        persistAndRefreshNotifications()
    }

    @discardableResult
    func createTicket(code: String, summary: String) -> JiraTicket? {
        let cleanedCode = code.normalizedTicketCode
        guard !cleanedCode.isEmpty, ticket(for: cleanedCode) == nil else {
            return nil
        }

        let ticket = JiraTicket(code: cleanedCode, summary: summary)
        tickets.append(ticket)
        tickets = Self.normalizedTickets(tickets)
        persistAndRefreshNotifications()
        return ticket
    }

    func updateEntry(id: TimeEntry.ID, ticketCode: String, summary: String, hours: Double, date: Date, comment: String) {
        let cleanedTicketCode = ticketCode.normalizedTicketCode
        guard !cleanedTicketCode.isEmpty, hours > 0 else {
            return
        }

        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let ticket = upsertTicket(code: cleanedTicketCode, summary: summary)
        var updatedEntry = entries[index]
        updatedEntry.ticketCode = cleanedTicketCode
        updatedEntry.summary = ticket.summary
        updatedEntry.hours = hours
        updatedEntry.date = calendar.startOfDay(for: date)
        updatedEntry.comment = comment.trimmed
        updatedEntry.updatedAt = Date()

        entries[index] = updatedEntry
        persistAndRefreshNotifications()
    }

    func deleteEntry(id: TimeEntry.ID) {
        entries.removeAll { $0.id == id }
        persistAndRefreshNotifications()
    }

    func setTicketClosed(code: String, isClosed: Bool) {
        let cleanedCode = code.normalizedTicketCode
        guard let index = tickets.firstIndex(where: { $0.code == cleanedCode }) else {
            return
        }

        guard tickets[index].isClosed != isClosed else {
            return
        }

        tickets[index].isClosed = isClosed
        tickets[index].updatedAt = Date()
        tickets = Self.normalizedTickets(tickets)
        persistAndRefreshNotifications()
    }

    func deleteTicket(code: String) {
        let cleanedCode = code.normalizedTicketCode
        tickets.removeAll { $0.code == cleanedCode }
        entries.removeAll { $0.ticketCode == cleanedCode }
        persistAndRefreshNotifications()
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        normalizeSettings()
        persistAndRefreshNotifications()
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        let granted = await notificationService.requestAuthorization()
        await refreshNotificationPermission()
        await refreshNotifications()
        return granted
    }

    func refreshNotificationPermission() async {
        notificationPermission = await notificationService.authorizationState()
    }

    func refreshNotifications() async {
        await notificationService.refreshSchedule(settings: settings, entries: entries, calendar: calendar)
        await refreshNotificationPermission()
    }

    private func bootstrapNotifications() async {
        await refreshNotificationPermission()

        if settings.notificationsEnabled, notificationPermission == .notDetermined {
            _ = await requestNotificationPermission()
        } else {
            await refreshNotifications()
        }
    }

    private func persistAndRefreshNotifications() {
        do {
            let dataFile = AppDataFile(tickets: tickets, entries: entries, settings: settings)
            try persistence.save(dataFile)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }

        Task {
            await refreshNotifications()
        }
    }

    private func normalizeSettings() {
        settings.targetHours = min(max(settings.targetHours, 0.25), 24)
        settings.notificationHour = min(max(settings.notificationHour, 0), 23)
        settings.notificationMinute = min(max(settings.notificationMinute, 0), 59)
        settings.workdays = settings.workdays.filter { (1...7).contains($0) }
    }

    @discardableResult
    private func upsertTicket(code: String, summary: String, timestamp: Date = Date()) -> JiraTicket {
        let cleanedCode = code.normalizedTicketCode
        let cleanedSummary = summary.trimmed

        if let index = tickets.firstIndex(where: { $0.code == cleanedCode }) {
            var ticket = tickets[index]

            if ticket.summary.isBlank, !cleanedSummary.isBlank {
                ticket.summary = cleanedSummary
                ticket.updatedAt = timestamp
                tickets[index] = ticket
            }

            return tickets[index]
        }

        let ticket = JiraTicket(
            code: cleanedCode,
            summary: cleanedSummary,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        tickets.append(ticket)
        tickets = Self.normalizedTickets(tickets)
        return ticket
    }

    private static func normalizedTickets(_ tickets: [JiraTicket]) -> [JiraTicket] {
        var ticketsByCode: [String: JiraTicket] = [:]

        for ticket in tickets {
            let code = ticket.code.normalizedTicketCode
            guard !code.isEmpty else {
                continue
            }

            if var existingTicket = ticketsByCode[code] {
                if existingTicket.summary.isBlank, !ticket.summary.isBlank {
                    existingTicket.summary = ticket.summary.trimmed
                }

                if ticket.updatedAt > existingTicket.updatedAt {
                    existingTicket.isClosed = ticket.isClosed
                }

                existingTicket.updatedAt = max(existingTicket.updatedAt, ticket.updatedAt)
                ticketsByCode[code] = existingTicket
            } else {
                ticketsByCode[code] = JiraTicket(
                    code: code,
                    summary: ticket.summary,
                    isClosed: ticket.isClosed,
                    createdAt: ticket.createdAt,
                    updatedAt: ticket.updatedAt
                )
            }
        }

        return ticketsByCode.values.sorted { $0.code < $1.code }
    }
}
