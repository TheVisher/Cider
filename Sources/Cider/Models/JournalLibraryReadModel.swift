import Foundation

struct JournalLibraryContainer: Hashable {
    static let id = "journal-library-container"

    var title: String = "Journal"
    var entryCount: Int
    var latestEntryDate: Date?

    var createdDate: Date {
        latestEntryDate ?? .distantPast
    }

    var updatedDate: Date {
        latestEntryDate ?? .distantPast
    }
}

struct JournalLibraryEntry: Identifiable, Hashable {
    let id: String
    let note: Note
    let date: Date
    let dateLabel: String
    let content: String
}

struct JournalNavigationNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case year(Int)
        case month(Int, Int)
        case week(Int, Int)
        case day(String)
    }

    let id: String
    let title: String
    let kind: Kind
    var entryID: String?
    var children: [JournalNavigationNode] = []
}

struct JournalLibraryReadModel: Hashable {
    var container: JournalLibraryContainer
    var entries: [JournalLibraryEntry]
    var navigation: [JournalNavigationNode]

    var defaultSelection: JournalLibraryEntry? {
        entries.first
    }

    static func build(from notes: [Note], calendar: Calendar = Self.calendar) -> JournalLibraryReadModel {
        let entries = notes.compactMap { note -> JournalLibraryEntry? in
            guard let dateLabel = note.dailyJournalDateLabel,
                  let date = Self.dayFormatter.date(from: dateLabel) else {
                return nil
            }
            return JournalLibraryEntry(
                id: "journal-entry-\(note.id.uuidString)",
                note: note,
                date: date,
                dateLabel: dateLabel,
                content: note.resolvedContent
            )
        }
        .sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.note.modifiedAt > rhs.note.modifiedAt
        }

        return JournalLibraryReadModel(
            container: JournalLibraryContainer(entryCount: entries.count, latestEntryDate: entries.first?.date),
            entries: entries,
            navigation: Self.navigation(for: entries, calendar: calendar)
        )
    }

    private static func navigation(
        for entries: [JournalLibraryEntry],
        calendar: Calendar
    ) -> [JournalNavigationNode] {
        let groupedByYear = Dictionary(grouping: entries) { calendar.component(.year, from: $0.date) }
        return groupedByYear.keys.sorted(by: >).map { year in
            let yearEntries = groupedByYear[year] ?? []
            let monthNodes = monthNodes(for: yearEntries, year: year, calendar: calendar)
            return JournalNavigationNode(
                id: "journal-year-\(year)",
                title: "\(year)",
                kind: .year(year),
                children: monthNodes
            )
        }
    }

    private static func monthNodes(
        for entries: [JournalLibraryEntry],
        year: Int,
        calendar: Calendar
    ) -> [JournalNavigationNode] {
        let groupedByMonth = Dictionary(grouping: entries) { calendar.component(.month, from: $0.date) }
        return groupedByMonth.keys.sorted(by: >).map { month in
            let monthEntries = groupedByMonth[month] ?? []
            let weekNodes = weekNodes(for: monthEntries, year: year, month: month, calendar: calendar)
            return JournalNavigationNode(
                id: "journal-month-\(year)-\(month)",
                title: monthFormatter.monthSymbols[month - 1],
                kind: .month(year, month),
                children: weekNodes
            )
        }
    }

    private static func weekNodes(
        for entries: [JournalLibraryEntry],
        year: Int,
        month: Int,
        calendar: Calendar
    ) -> [JournalNavigationNode] {
        let groupedByWeek = Dictionary(grouping: entries) { calendar.component(.weekOfYear, from: $0.date) }
        return groupedByWeek.keys.sorted(by: >).map { week in
            let weekEntries = (groupedByWeek[week] ?? []).sorted { $0.date > $1.date }
            return JournalNavigationNode(
                id: "journal-week-\(year)-\(month)-\(week)",
                title: "Week \(week)",
                kind: .week(year, week),
                children: weekEntries.map { entry in
                    JournalNavigationNode(
                        id: "journal-day-\(entry.dateLabel)",
                        title: dayTitleFormatter.string(from: entry.date),
                        kind: .day(entry.dateLabel),
                        entryID: entry.id
                    )
                }
            )
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
