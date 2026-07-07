import Foundation

enum JournalMigrationPreviewClassification: String, Hashable {
    case canonical
    case legacyExact
    case safePersonalCandidate
    case excludedProductOrDev
    case ambiguous

    static let allReportCases: [JournalMigrationPreviewClassification] = [
        .canonical,
        .legacyExact,
        .safePersonalCandidate,
        .excludedProductOrDev,
        .ambiguous,
    ]
}

enum JournalMigrationDateEvidenceSource: String, Hashable {
    case title
    case body
}

enum JournalMigrationDateEvidenceKind: String, Hashable {
    case canonicalTitle
    case legacyTitle
    case isoDate
    case usNumericDate
    case monthNameDate
}

struct JournalMigrationDateEvidence: Hashable {
    let isoDate: String
    let source: JournalMigrationDateEvidenceSource
    let kind: JournalMigrationDateEvidenceKind
    let rawValue: String
}

struct JournalMigrationPreviewRow: Hashable {
    let note: Note
    let classification: JournalMigrationPreviewClassification
    let reason: String
    let proposedCanonicalTitle: String?
    let proposedISODate: String?
    let preservedCaptureHints: [String]
    let dateEvidence: [JournalMigrationDateEvidence]
    let dateIneligibilityReason: String?
}

struct JournalMigrationPreview: Hashable {
    let rows: [JournalMigrationPreviewRow]
    let mutatesLiveNotes = false

    var countsByClassification: [JournalMigrationPreviewClassification: Int] {
        Dictionary(grouping: rows, by: \.classification).mapValues(\.count)
    }

    var journalLibraryEligibleRowCount: Int {
        rows.filter(\.isJournalLibraryEligible).count
    }
}

extension JournalMigrationPreviewRow {
    var isJournalLibraryEligible: Bool {
        switch classification {
        case .canonical, .legacyExact, .safePersonalCandidate:
            return proposedISODate != nil
        case .excludedProductOrDev, .ambiguous:
            return false
        }
    }
}

struct JournalMigrationPreviewService {
    func preview(notes: [Note]) -> JournalMigrationPreview {
        JournalMigrationPreview(rows: notes.compactMap(classify(note:)))
    }

    private func classify(note: Note) -> JournalMigrationPreviewRow? {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTitle = title.localizedLowercase
        let lowerBody = note.resolvedContent.localizedLowercase
        let combined = "\(lowerTitle)\n\(lowerBody)"

        if let parsed = JournalTitle.parse(title) {
            let dateKind: JournalMigrationDateEvidenceKind = parsed.kind == .canonical ? .canonicalTitle : .legacyTitle
            return JournalMigrationPreviewRow(
                note: note,
                classification: parsed.kind == .canonical ? .canonical : .legacyExact,
                reason: parsed.kind == .canonical ? "Already uses canonical Journal MM-DD-YYYY title." : "Legacy Daily Journal YYYY-MM-DD title remains readable during transition.",
                proposedCanonicalTitle: parsed.kind == .canonical ? nil : JournalTitle.canonicalTitle(forISODate: parsed.isoDate),
                proposedISODate: parsed.isoDate,
                preservedCaptureHints: captureHints(in: title),
                dateEvidence: [
                    JournalMigrationDateEvidence(
                        isoDate: parsed.isoDate,
                        source: .title,
                        kind: dateKind,
                        rawValue: title
                    ),
                ],
                dateIneligibilityReason: nil
            )
        }

        guard combined.contains("journal") else { return nil }

        if isProductOrDevelopmentJournalMention(note: note, lowerTitle: lowerTitle, lowerBody: lowerBody) {
            return JournalMigrationPreviewRow(
                note: note,
                classification: .excludedProductOrDev,
                reason: "Journal appears in Cider/product/development planning context, not as a personal day entry.",
                proposedCanonicalTitle: nil,
                proposedISODate: nil,
                preservedCaptureHints: [],
                dateEvidence: [],
                dateIneligibilityReason: "Excluded product/development journal context."
            )
        }

        let dateResolution = sourceBackedDateResolution(title: title, body: note.resolvedContent)
        let isoDate = dateResolution.isoDate
        let hints = captureHints(in: title)
        if isPersonalJournalCandidate(title: lowerTitle, body: lowerBody, hints: hints, isoDate: isoDate) {
            return JournalMigrationPreviewRow(
                note: note,
                classification: .safePersonalCandidate,
                reason: "Looks like a personal journal capture candidate; preview only, no live mutation.",
                proposedCanonicalTitle: isoDate.map(JournalTitle.canonicalTitle(forISODate:)),
                proposedISODate: isoDate,
                preservedCaptureHints: hints,
                dateEvidence: dateResolution.evidence,
                dateIneligibilityReason: isoDate == nil ? dateResolution.ineligibilityReason : nil
            )
        }

        return JournalMigrationPreviewRow(
            note: note,
            classification: .ambiguous,
            reason: "Mentions journal but lacks enough personal/day-entry evidence for automatic promotion.",
            proposedCanonicalTitle: isoDate.map(JournalTitle.canonicalTitle(forISODate:)),
            proposedISODate: isoDate,
            preservedCaptureHints: hints,
            dateEvidence: dateResolution.evidence,
            dateIneligibilityReason: dateResolution.ineligibilityReason ?? "Journal mention is ambiguous and is not eligible for automatic promotion."
        )
    }

    private func isProductOrDevelopmentJournalMention(note: Note, lowerTitle: String, lowerBody: String) -> Bool {
        if note.relativePath.localizedLowercase.hasPrefix("projects/cider/") { return true }
        if note.projectID?.localizedCaseInsensitiveCompare("Cider") == .orderedSame { return true }
        if lowerTitle.hasPrefix("cider journal") { return true }
        let combined = "\(lowerTitle)\n\(lowerBody)"
        let productTerms = ["dashboard", "storage design", "note kind", "attachments", "transcript", "sidebar", "filter", " ia ", "product", "dev"]
        if productTerms.contains(where: { lowerTitle.contains($0) }) { return true }

        let ciderContextTerms = ["cider", "hermes", "kanban", "cid-", "cody", "cider-cli"]
        let productWorkTerms = ["north star", "backend", "second-brain", "second brain", "capability audit", "audit", "implementation lane", "verification lane", "product", "development", "review queue", "graph", "memory candidates"]
        return ciderContextTerms.contains { combined.contains($0) }
            && productWorkTerms.contains { combined.contains($0) }
    }

    private func isPersonalJournalCandidate(title: String, body: String, hints: [String], isoDate: String?) -> Bool {
        if title.hasPrefix("daily journal addendum") { return true }
        if isoDate != nil, !hints.isEmpty { return true }
        let personalTerms = ["reflection", "driving", "morning", "late-night", "voice", "midday"]
        return personalTerms.contains { title.contains($0) || body.contains($0) }
    }

    private func captureHints(in title: String) -> [String] {
        let lowerTitle = title.localizedLowercase
        let hints = ["morning", "driving", "voice", "midday", "late-night", "discord", "qa manager", "3d print"]
        return hints.filter { lowerTitle.contains($0) }
    }

    private func sourceBackedDateResolution(title: String, body: String) -> DateResolution {
        let evidence = dateEvidence(in: title, source: .title) + dateEvidence(in: body, source: .body)
        let uniqueDates = Set(evidence.map(\.isoDate))
        if uniqueDates.count == 1 {
            return DateResolution(isoDate: uniqueDates.first, evidence: evidence, ineligibilityReason: nil)
        }
        if uniqueDates.count > 1 {
            return DateResolution(
                isoDate: nil,
                evidence: evidence,
                ineligibilityReason: "Multiple conflicting source-backed dates found in title or body."
            )
        }
        return DateResolution(
            isoDate: nil,
            evidence: [],
            ineligibilityReason: "No unambiguous source-backed date found in title or body."
        )
    }

    private func dateEvidence(in text: String, source: JournalMigrationDateEvidenceSource) -> [JournalMigrationDateEvidence] {
        isoDateEvidence(in: text, source: source)
            + usNumericDateEvidence(in: text, source: source)
            + monthNameDateEvidence(in: text, source: source)
    }

    private func isoDateEvidence(in text: String, source: JournalMigrationDateEvidenceSource) -> [JournalMigrationDateEvidence] {
        matches(in: text, regex: Self.isoDateRegex).compactMap { match in
            guard match.captures.count == 1,
                  let isoDate = match.captures[0],
                  JournalTitle.isValidISODate(isoDate) else {
                return nil
            }
            return JournalMigrationDateEvidence(
                isoDate: isoDate,
                source: source,
                kind: .isoDate,
                rawValue: match.rawValue
            )
        }
    }

    private func usNumericDateEvidence(in text: String, source: JournalMigrationDateEvidenceSource) -> [JournalMigrationDateEvidence] {
        matches(in: text, regex: Self.usNumericDateRegex).compactMap { match in
            guard match.captures.count == 3,
                  let rawMonth = match.captures[0],
                  let rawDay = match.captures[1],
                  let rawYear = match.captures[2],
                  let month = Int(rawMonth),
                  let day = Int(rawDay),
                  let year = Int(rawYear),
                  let isoDate = isoDate(year: year, month: month, day: day) else {
                return nil
            }
            return JournalMigrationDateEvidence(
                isoDate: isoDate,
                source: source,
                kind: .usNumericDate,
                rawValue: match.rawValue
            )
        }
    }

    private func monthNameDateEvidence(in text: String, source: JournalMigrationDateEvidenceSource) -> [JournalMigrationDateEvidence] {
        matches(in: text, regex: Self.monthNameDateRegex).compactMap { match in
            guard match.captures.count == 3,
                  let monthName = match.captures[0],
                  let month = Self.monthNumbers[monthName.trimmingCharacters(in: CharacterSet(charactersIn: ".")).localizedLowercase],
                  let rawDay = match.captures[1],
                  let rawYear = match.captures[2],
                  let day = Int(rawDay),
                  let year = Int(rawYear),
                  let isoDate = isoDate(year: year, month: month, day: day) else {
                return nil
            }
            return JournalMigrationDateEvidence(
                isoDate: isoDate,
                source: source,
                kind: .monthNameDate,
                rawValue: match.rawValue
            )
        }
    }

    private func matches(in text: String, regex: NSRegularExpression) -> [RegexMatch] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let rawRange = Range(match.range(at: 0), in: text) else { return nil }
            let captures = (1..<match.numberOfRanges).map { index -> String? in
                guard let captureRange = Range(match.range(at: index), in: text) else { return nil }
                return String(text[captureRange])
            }
            return RegexMatch(rawValue: String(text[rawRange]), captures: captures)
        }
    }

    private func isoDate(year: Int, month: Int, day: Int) -> String? {
        var components = DateComponents()
        components.calendar = Self.gregorianCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        guard let date = Self.gregorianCalendar.date(from: components),
              Self.gregorianCalendar.component(.year, from: date) == year,
              Self.gregorianCalendar.component(.month, from: date) == month,
              Self.gregorianCalendar.component(.day, from: date) == day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private struct DateResolution {
        let isoDate: String?
        let evidence: [JournalMigrationDateEvidence]
        let ineligibilityReason: String?
    }

    private struct RegexMatch {
        let rawValue: String
        let captures: [String?]
    }

    private static let isoDateRegex = try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})"#)
    private static let usNumericDateRegex = try! NSRegularExpression(pattern: #"\b(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])/(\d{4})\b"#)
    private static let monthNameDateRegex = try! NSRegularExpression(
        pattern: #"\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan\.?|Feb\.?|Mar\.?|Apr\.?|Jun\.?|Jul\.?|Aug\.?|Sep\.?|Sept\.?|Oct\.?|Nov\.?|Dec\.?)\s+([0-3]?\d),?\s+(\d{4})\b"#,
        options: [.caseInsensitive]
    )
    private static let monthNumbers: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]
    private static let gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
