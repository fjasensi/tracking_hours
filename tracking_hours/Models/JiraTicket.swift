import Foundation

struct JiraTicket: Identifiable, Codable, Equatable, Hashable {
    var id: String { code }

    var code: String
    var summary: String
    var isClosed: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        code: String,
        summary: String = "",
        isClosed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.code = code.normalizedTicketCode
        self.summary = summary.trimmed
        self.isClosed = isClosed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case code
        case summary
        case isClosed
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code).normalizedTicketCode
        summary = try container.decodeIfPresent(String.self, forKey: .summary)?.trimmed ?? ""
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var menuTitle: String {
        if summary.isBlank {
            return code
        }

        return "\(code) - \(summary)"
    }
}
