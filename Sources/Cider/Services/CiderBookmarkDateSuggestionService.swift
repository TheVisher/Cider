import Foundation

struct CiderBookmarkDateSuggestion: Codable, Equatable {
    var bookmarkID: UUID
    var bookmarkTitle: String
    var sourceURL: String
    var kind: String
    var confidence: Double
    var date: Date
    var sourceField: String
    var sourceSnippet: String
    var nextSafeAction: String
}

struct CiderBookmarkDateSuggestionResult: Equatable {
    var command: String
    var bookmarkID: UUID
    var bookmarkTitle: String
    var sourceURL: String
    var suggestions: [CiderBookmarkDateSuggestion]
}

final class CiderBookmarkDateSuggestionService {
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        nowProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    func suggestions(for bookmark: Bookmark) -> [CiderBookmarkDateSuggestion] {
        let fields: [(name: String, text: String)] = [
            ("title", bookmark.title),
            ("notes", bookmark.notes),
            ("aiSummary", bookmark.aiSummary ?? ""),
            ("ocrText", bookmark.ocrText ?? ""),
        ].filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        var suggestions: [CiderBookmarkDateSuggestion] = []
        var seen = Set<String>()
        let now = nowProvider()

        for field in fields {
            let nsText = field.text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            detector.enumerateMatches(in: field.text, options: [], range: fullRange) { match, _, _ in
                guard let match,
                      let date = match.date,
                      date >= calendar.date(byAdding: .day, value: -1, to: now) ?? now else {
                    return
                }

                let contextRange = expandedRange(around: match.range, in: nsText, radius: 80)
                let context = nsText.substring(with: contextRange)
                let classification = classify(context: context)
                guard classification.confidence >= 0.65 else { return }

                let key = dedupeKey(kind: classification.kind, date: date, field: field.name)
                guard seen.insert(key).inserted else { return }

                suggestions.append(CiderBookmarkDateSuggestion(
                    bookmarkID: bookmark.id,
                    bookmarkTitle: bookmark.title,
                    sourceURL: bookmark.urlString,
                    kind: classification.kind,
                    confidence: classification.confidence,
                    date: date,
                    sourceField: field.name,
                    sourceSnippet: trimmedSnippet(context),
                    nextSafeAction: "review_date_suggestion"
                ))
            }
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.sourceField < rhs.sourceField
        }
    }

    func result(for bookmark: Bookmark) -> CiderBookmarkDateSuggestionResult {
        CiderBookmarkDateSuggestionResult(
            command: "bookmark.date-suggestions",
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            suggestions: suggestions(for: bookmark)
        )
    }

    private func classify(context: String) -> (kind: String, confidence: Double) {
        let lower = context.lowercased()
        if containsAny(lower, ["presale", "pre-sale", "on sale", "onsale", "tickets", "ticket window", "lottery"]) {
            return ("presale_date", 0.94)
        }
        if containsAny(lower, ["release date", "releases", "released", "launches", "launch date", "available", "preorder", "pre-order"]) {
            return ("release_date", 0.90)
        }
        if containsAny(lower, ["event", "show", "concert", "conference", "appointment", "game night", "premiere"]) {
            return ("event_date", 0.84)
        }
        if containsAny(lower, ["deadline", "due by", "apply by", "register by", "expires"]) {
            return ("deadline", 0.84)
        }
        if containsAny(lower, ["sale ends", "offer ends", "ends on", "last day"]) {
            return ("sale_end", 0.82)
        }
        return ("unknown_date", 0.0)
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func expandedRange(around range: NSRange, in text: NSString, radius: Int) -> NSRange {
        let location = max(0, range.location - radius)
        let upperBound = min(text.length, range.location + range.length + radius)
        return NSRange(location: location, length: max(0, upperBound - location))
    }

    private func trimmedSnippet(_ snippet: String) -> String {
        let collapsed = snippet
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 180 else { return collapsed }
        return String(collapsed.prefix(177)) + "..."
    }

    private func dedupeKey(kind: String, date: Date, field: String) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [
            kind,
            "\(components.year ?? 0)",
            "\(components.month ?? 0)",
            "\(components.day ?? 0)",
            "\(components.hour ?? 0)",
            "\(components.minute ?? 0)",
            field,
        ].joined(separator: ":")
    }
}
