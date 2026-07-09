import Foundation

struct TimeEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var ticketCode: String
    var summary: String
    var hours: Double
    var date: Date
    var comment: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ticketCode: String,
        summary: String = "",
        hours: Double,
        date: Date,
        comment: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ticketCode = ticketCode.normalizedTicketCode
        self.summary = summary.trimmed
        self.hours = hours
        self.date = Calendar.current.startOfDay(for: date)
        self.comment = comment.trimmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
