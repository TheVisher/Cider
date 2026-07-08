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

struct JournalSourceSpan: Hashable {
    let location: Int
    let length: Int
}

struct JournalEntrySection: Identifiable, Hashable {
    let id: String
    let timestamp24Hour: String
    let capturedAt: Date?
    let captureSource: String
    let sourceSpan: JournalSourceSpan
    let sourceSnippet: String

    func displayTimestamp(format: JournalTimestampFormat) -> String {
        guard format == .twelveHour else { return timestamp24Hour }
        return JournalLibraryReadModel.twelveHourDisplayTime(from: timestamp24Hour) ?? timestamp24Hour
    }
}

struct JournalEntryMetadata: Hashable {
    let journalDate: String
    let displayTitle: String
    let titleKind: JournalTitleKind
    let createdAt: Date
    let capturedAt: Date?
    let captureSource: String
    let sections: [JournalEntrySection]
}

struct JournalLibraryEntry: Identifiable, Hashable {
    let id: String
    let note: Note
    let date: Date
    let dateLabel: String
    let content: String
    let metadata: JournalEntryMetadata

    var displayTitle: String {
        metadata.displayTitle
    }

    func cachedDisplayContent(timestampFormat: JournalTimestampFormat) -> String? {
        JournalLibraryReadModel.cachedDisplayContent(
            entryID: id,
            content: content,
            date: date,
            metadata: metadata,
            timestampFormat: timestampFormat
        )
    }

    func preparedDisplayContent(timestampFormat: JournalTimestampFormat) -> String {
        JournalLibraryReadModel.preparedDisplayContent(
            entryID: id,
            content: content,
            date: date,
            metadata: metadata,
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
                content: row.note.resolvedContent,
                metadata: Self.metadata(for: row, date: date, dateLabel: dateLabel)
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
        date: Date,
        metadata: JournalEntryMetadata? = nil,
        timestampFormat: JournalTimestampFormat
    ) -> String? {
        if timestampFormat == .twentyFourHour {
            return canonicalizedJournalDisplayContent(content, date: date, metadata: metadata)
        }
        return displayContentCache.value(for: displayCacheKey(
            entryID: entryID,
            content: content,
            date: date,
            timestampFormat: timestampFormat
        ))
    }

    static func preparedDisplayContent(
        entryID: String,
        content: String,
        date: Date,
        metadata: JournalEntryMetadata? = nil,
        timestampFormat: JournalTimestampFormat
    ) -> String {
        let key = displayCacheKey(entryID: entryID, content: content, date: date, timestampFormat: timestampFormat)
        if let cached = displayContentCache.value(for: key) {
            return cached
        }

        let formatted = formatJournalTimestamps(
            in: canonicalizedJournalDisplayContent(content, date: date, metadata: metadata),
            format: timestampFormat
        )
        displayContentCache.setValue(formatted, for: key)
        return formatted
    }

    private static func displayCacheKey(
        entryID: String,
        content: String,
        date: Date,
        timestampFormat: JournalTimestampFormat
    ) -> String {
        "\(entryID)|\(timestampFormat.rawValue)|\(canonicalDateLabel(for: date))|\(content.count)|\(content.hashValue)"
    }

    static func canonicalDisplayTitle(for date: Date) -> String {
        "Journal \(displayDateFormatter.string(from: date))"
    }

    static func canonicalizedJournalDisplayContent(
        _ content: String,
        date: Date,
        metadata: JournalEntryMetadata? = nil
    ) -> String {
        let title = metadata?.displayTitle ?? canonicalDisplayTitle(for: date)
        let isoDate = metadata?.journalDate ?? canonicalDateLabel(for: date)
        var didReplaceHeading = false

        return content
            .components(separatedBy: .newlines)
            .map { line in
                if !didReplaceHeading, isJournalHeadingLine(line) {
                    didReplaceHeading = true
                    return "# \(title)"
                }
                if line.trimmingCharacters(in: .whitespaces) == isoDate {
                    return title
                }
                return line
            }
            .joined(separator: "\n")
    }

    private static func isJournalHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.range(
            of: #"^#\s+(Daily Journal \d{4}-\d{2}-\d{2}|Journal \d{2}-\d{2}-\d{4})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func canonicalDateLabel(for date: Date) -> String {
        dayFormatter.string(from: date)
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

    static func twelveHourDisplayTime(from rawTime: String) -> String? {
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

    static func metadata(
        for note: Note,
        dateLabel: String,
        titleKind: JournalTitleKind? = nil
    ) -> JournalEntryMetadata? {
        guard let date = dayFormatter.date(from: dateLabel) else { return nil }
        let content = note.resolvedContent
        let sections = timestampedSections(in: content, journalDate: dateLabel)
        return JournalEntryMetadata(
            journalDate: dateLabel,
            displayTitle: canonicalDisplayTitle(for: date),
            titleKind: titleKind ?? note.journalTitle?.kind ?? .importedCandidate,
            createdAt: note.createdAt,
            capturedAt: sections.first?.capturedAt,
            captureSource: "journal.read_model",
            sections: sections
        )
    }

    private static func metadata(
        for row: JournalMigrationPreviewRow,
        date: Date,
        dateLabel: String
    ) -> JournalEntryMetadata {
        metadata(for: row.note, dateLabel: dateLabel, titleKind: titleKind(for: row)) ?? JournalEntryMetadata(
            journalDate: dateLabel,
            displayTitle: canonicalDisplayTitle(for: date),
            titleKind: titleKind(for: row),
            createdAt: row.note.createdAt,
            capturedAt: nil,
            captureSource: "journal.read_model",
            sections: []
        )
    }

    private static func titleKind(for row: JournalMigrationPreviewRow) -> JournalTitleKind {
        switch row.classification {
        case .canonical:
            return .canonical
        case .legacyExact:
            return .legacyDaily
        case .safePersonalCandidate, .excludedProductOrDev, .ambiguous:
            return .importedCandidate
        }
    }

    private static func timestampedSections(in content: String, journalDate: String) -> [JournalEntrySection] {
        let starts = timestampedLineStarts(in: content)
        return starts.enumerated().compactMap { index, marker in
            let end = index + 1 < starts.count ? starts[index + 1].offset : content.count
            guard end > marker.offset else { return nil }
            let snippet = substring(in: content, offset: marker.offset, length: end - marker.offset)
            return JournalEntrySection(
                id: "journal-section-\(journalDate)-\(marker.time)-\(marker.offset)",
                timestamp24Hour: marker.time,
                capturedAt: capturedAt(journalDate: journalDate, time: marker.time),
                captureSource: captureSource(in: snippet),
                sourceSpan: JournalSourceSpan(location: marker.offset, length: end - marker.offset),
                sourceSnippet: snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func timestampedLineStarts(in content: String) -> [(offset: Int, time: String)] {
        var result: [(offset: Int, time: String)] = []
        var offset = 0
        for line in content.components(separatedBy: .newlines) {
            if let time = timestamp(in: line) {
                result.append((offset, time))
            }
            offset += line.count + 1
        }
        return result
    }

    private static func timestamp(in line: String) -> String? {
        for pattern in [#"^\s*##\s+(\d{2}:\d{2})\b"#, #"^\s*-\s+(\d{2}:\d{2})\s+-\s+"#] {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 1,
                  let timeRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            let time = String(line[timeRange])
            if isValidClockTime(time) { return time }
        }
        return nil
    }

    private static func isValidClockTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func captureSource(in snippet: String) -> String {
        for line in snippet.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.localizedLowercase.hasPrefix("source:") else { continue }
            let value = String(trimmed.dropFirst("Source:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return "markdown"
    }

    private static func substring(in content: String, offset: Int, length: Int) -> String {
        let start = content.index(content.startIndex, offsetBy: offset)
        let end = content.index(start, offsetBy: length)
        return String(content[start..<end])
    }

    private static func capturedAt(journalDate: String, time: String) -> Date? {
        timestampFormatter.date(from: "\(journalDate)T\(time):00Z")
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

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
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
