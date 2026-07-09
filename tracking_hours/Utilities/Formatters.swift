import Foundation

enum AppFormatters {
    static let appLocale = Locale(identifier: "en_US")

    static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = appLocale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension Double {
    var hoursText: String {
        let normalized = abs(self) < 0.0001 ? 0 : self
        return AppFormatters.hoursFormatter.string(from: NSNumber(value: normalized)) ?? "\(normalized)"
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedTicketCode: String {
        trimmed.uppercased()
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }
}
