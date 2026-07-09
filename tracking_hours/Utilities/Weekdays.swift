import Foundation

struct WeekdayOption: Identifiable {
    let id: Int
    let title: String
    let shortTitle: String
}

enum Weekdays {
    static let all: [WeekdayOption] = [
        WeekdayOption(id: 2, title: "Monday", shortTitle: "M"),
        WeekdayOption(id: 3, title: "Tuesday", shortTitle: "T"),
        WeekdayOption(id: 4, title: "Wednesday", shortTitle: "W"),
        WeekdayOption(id: 5, title: "Thursday", shortTitle: "T"),
        WeekdayOption(id: 6, title: "Friday", shortTitle: "F"),
        WeekdayOption(id: 7, title: "Saturday", shortTitle: "S"),
        WeekdayOption(id: 1, title: "Sunday", shortTitle: "S")
    ]
}
