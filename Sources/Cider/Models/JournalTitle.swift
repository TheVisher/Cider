import Foundation

enum JournalTitleKind: String, Hashable {
    case canonical
    case legacyDaily
}

struct JournalTitle: Hashable {
    let kind: JournalTitleKind
    let isoDate: String

    static func parse(_ title: String) -> JournalTitle? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = canonicalRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let monthRange = Range(match.range(at: 1), in: trimmed),
           let dayRange = Range(match.range(at: 2), in: trimmed),
           let yearRange = Range(match.range(at: 3), in: trimmed) {
            let isoDate = "\(trimmed[yearRange])-\(trimmed[monthRange])-\(trimmed[dayRange])"
            guard isValidISODate(isoDate) else { return nil }
            return JournalTitle(kind: .canonical, isoDate: isoDate)
        }

        if let match = legacyRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let dateRange = Range(match.range(at: 1), in: trimmed) {
            let isoDate = String(trimmed[dateRange])
            guard isValidISODate(isoDate) else { return nil }
            return JournalTitle(kind: .legacyDaily, isoDate: isoDate)
        }

        return nil
    }

    static func canonicalTitle(forISODate isoDate: String) -> String {
        guard let date = isoDateFormatter.date(from: isoDate) else {
            return "Journal \(isoDate)"
        }
        return "Journal \(canonicalDateFormatter.string(from: date))"
    }

    static func appendSection(time: String, source: String, body: String) -> String {
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLine = cleanSource.isEmpty ? "Source: capture.add" : "Source: \(cleanSource)"
        return "## \(time)\n\(sourceLine)\n\n\(body)"
    }

    static func isValidISODate(_ value: String) -> Bool {
        isoDateFormatter.date(from: value).map { isoDateFormatter.string(from: $0) == value } ?? false
    }

    private static let canonicalRegex = try! NSRegularExpression(
        pattern: #"^Journal (\d{2})-(\d{2})-(\d{4})$"#,
        options: [.caseInsensitive]
    )

    private static let legacyRegex = try! NSRegularExpression(
        pattern: #"^Daily Journal (\d{4}-\d{2}-\d{2})$"#,
        options: [.caseInsensitive]
    )

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let canonicalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter
    }()
}
