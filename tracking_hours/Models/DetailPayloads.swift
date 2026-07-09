import Foundation

struct TicketDetailPayload: Codable, Hashable, Identifiable {
    var id: String {
        if let date {
            return "\(ticketCode)-\(date.timeIntervalSinceReferenceDate)"
        }

        return "\(ticketCode)-all"
    }

    let ticketCode: String
    let date: Date?
}

struct EntryDetailPayload: Codable, Hashable, Identifiable {
    var id: UUID { entryID }

    let entryID: TimeEntry.ID
}
