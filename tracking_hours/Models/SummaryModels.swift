import Foundation

struct TicketDaySummary: Identifiable, Equatable {
    var id: String { ticketCode }

    let ticketCode: String
    let summary: String
    let hours: Double
    let entryCount: Int
}

struct DaySummary: Identifiable, Equatable {
    var id: Date { date }

    let date: Date
    let totalHours: Double
    let pendingHours: Double
    let excessHours: Double
    let distinctTicketCount: Int

    var isComplete: Bool {
        pendingHours <= 0.005
    }

    var balanceText: String {
        if pendingHours > 0.005 {
            return "\(pendingHours.hoursText)h remaining"
        }

        if excessHours > 0.005 {
            return "\(excessHours.hoursText)h over"
        }

        return "Complete"
    }
}
