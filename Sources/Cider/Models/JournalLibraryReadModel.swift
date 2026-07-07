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

    func cachedDisplayContent(timestampFormat: JournalTimestampFormat) -> String? {
        JournalLibraryReadModel.cachedDisplayContent(
            entryID: id,
            content: content,
            timestampFormat: timestampFormat
        )
    }

    func preparedDisplayContent(timestampFormat: JournalTimestampFormat) -> String {
        JournalLibraryReadModel.preparedDisplayContent(
            entryID: id,
            content: content,
            timestampFormat: timestampFormat
        )
    }

    func displayContent(timestampFormat: JournalTimestampFormat) -> String {
        preparedDisplayContent(timestampFormat: timestampFormat)
    }
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
    private static let displayContentCache = JournalDisplayContentCache()

    var container: JournalLibraryContainer
    var entries: [JournalLibraryEntry]
    var navigation: [JournalNavigationNode]

    var defaultSelection: JournalLibraryEntry? {
        entries.first
    }

    static func build(from notes: [Note], calendar: Calendar = Self.calendar) -> JournalLibraryReadModel {
        let preview = JournalMigrationPreviewService().preview(notes: notes)
        let entries = preview.rows.compactMap { row -> JournalLibraryEntry? in
            guard row.isJournalLibraryEligible,
                  let dateLabel = row.proposedISODate,
                  let date = Self.dayFormatter.date(from: dateLabel) else {
                return nil
            }
            return JournalLibraryEntry(
                id: "journal-entry-\(row.note.id.uuidString)",
                note: row.note,
                date: date,
                dateLabel: dateLabel,
                content: row.note.resolvedContent
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

    static func formatJournalTimestamps(in content: String, format: JournalTimestampFormat) -> String {
        guard format == .twelveHour else { return content }
        return content
            .components(separatedBy: .newlines)
            .map { formatJournalTimestampLine($0) }
            .joined(separator: "\n")
    }

    static func cachedDisplayContent(
        entryID: String,
        content: String,
        timestampFormat: JournalTimestampFormat
    ) -> String? {
        guard timestampFormat == .twelveHour else { return content }
        return displayContentCache.value(for: displayCacheKey(
            entryID: entryID,
            content: content,
            timestampFormat: timestampFormat
        ))
    }

    static func preparedDisplayContent(
        entryID: String,
        content: String,
        timestampFormat: JournalTimestampFormat
    ) -> String {
        guard timestampFormat == .twelveHour else { return content }
        let key = displayCacheKey(entryID: entryID, content: content, timestampFormat: timestampFormat)
        if let cached = displayContentCache.value(for: key) {
            return cached
        }

        let formatted = formatJournalTimestamps(in: content, format: timestampFormat)
        displayContentCache.setValue(formatted, for: key)
        return formatted
    }

    private static func displayCacheKey(
        entryID: String,
        content: String,
        timestampFormat: JournalTimestampFormat
    ) -> String {
        "\(entryID)|\(timestampFormat.rawValue)|\(content.count)|\(content.hashValue)"
    }

    private static func formatJournalTimestampLine(_ line: String) -> String {
        if let range = line.range(
            of: #"^(\s*-\s)(\d{2}:\d{2})(\s-\s)"#,
            options: .regularExpression
        ) {
            let match = String(line[range])
            let time = String(match.drop { !$0.isNumber }.prefix(5))
            guard let formatted = twelveHourDisplayTime(from: time) else { return line }
            return line.replacingCharacters(in: range, with: match.replacingOccurrences(of: time, with: formatted))
        }

        if let range = line.range(
            of: #"^(\s*##\s)(\d{2}:\d{2})(\b)"#,
            options: .regularExpression
        ) {
            let match = String(line[range])
            let time = String(match.drop { !$0.isNumber }.prefix(5))
            guard let formatted = twelveHourDisplayTime(from: time) else { return line }
            return line.replacingCharacters(in: range, with: match.replacingOccurrences(of: time, with: formatted))
        }

        return line
    }

    private static func twelveHourDisplayTime(from rawTime: String) -> String? {
        let parts = rawTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        let suffix = hour < 12 ? "AM" : "PM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour):\(String(format: "%02d", minute)) \(suffix)"
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

private final class JournalDisplayContentCache: @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func value(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setValue(_ value: String, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
}
