import Foundation

struct AppDataFile: Codable {
    var schemaVersion: Int
    var tickets: [JiraTicket]
    var entries: [TimeEntry]
    var settings: AppSettings

    init(
        schemaVersion: Int = 3,
        tickets: [JiraTicket] = [],
        entries: [TimeEntry] = [],
        settings: AppSettings = AppSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.tickets = tickets
        self.entries = entries
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tickets
        case entries
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        entries = try container.decodeIfPresent([TimeEntry].self, forKey: .entries) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        tickets = try container.decodeIfPresent([JiraTicket].self, forKey: .tickets)
            ?? AppDataFile.deriveTickets(from: entries)
    }

    static func deriveTickets(from entries: [TimeEntry]) -> [JiraTicket] {
        let sortedEntries = entries.sorted { $0.createdAt < $1.createdAt }
        var ticketsByCode: [String: JiraTicket] = [:]

        for entry in sortedEntries {
            let code = entry.ticketCode.normalizedTicketCode
            guard !code.isEmpty else {
                continue
            }

            if var ticket = ticketsByCode[code] {
                if ticket.summary.isBlank, !entry.summary.isBlank {
                    ticket.summary = entry.summary.trimmed
                    ticket.updatedAt = entry.updatedAt
                    ticketsByCode[code] = ticket
                }
            } else {
                ticketsByCode[code] = JiraTicket(
                    code: code,
                    summary: entry.summary,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            }
        }

        return ticketsByCode.values.sorted { $0.code < $1.code }
    }
}

final class LocalJSONPersistence {
    private let fileManager: FileManager
    private let directoryName = "tracking_hours"
    private let fileName = "tracking-hours-data.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var directoryURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    func load() -> AppDataFile {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AppDataFile()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppDataFile.self, from: data)
        } catch {
            print("Could not load local JSON: \(error.localizedDescription)")
            return AppDataFile()
        }
    }

    func save(_ dataFile: AppDataFile) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(dataFile)
        try data.write(to: fileURL, options: [.atomic])
    }
}
