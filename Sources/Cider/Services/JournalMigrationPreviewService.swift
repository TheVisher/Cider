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

struct JournalMigrationPreviewRow: Hashable {
    let note: Note
    let classification: JournalMigrationPreviewClassification
    let reason: String
    let proposedCanonicalTitle: String?
    let proposedISODate: String?
    let preservedCaptureHints: [String]
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
            return JournalMigrationPreviewRow(
                note: note,
                classification: parsed.kind == .canonical ? .canonical : .legacyExact,
                reason: parsed.kind == .canonical ? "Already uses canonical Journal MM-DD-YYYY title." : "Legacy Daily Journal YYYY-MM-DD title remains readable during transition.",
                proposedCanonicalTitle: parsed.kind == .canonical ? nil : JournalTitle.canonicalTitle(forISODate: parsed.isoDate),
                proposedISODate: parsed.isoDate,
                preservedCaptureHints: captureHints(in: title)
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
                preservedCaptureHints: []
            )
        }

        let isoDate = firstISODate(in: title) ?? firstISODate(in: note.resolvedContent)
        let hints = captureHints(in: title)
        if isPersonalJournalCandidate(title: lowerTitle, body: lowerBody, hints: hints, isoDate: isoDate) {
            return JournalMigrationPreviewRow(
                note: note,
                classification: .safePersonalCandidate,
                reason: "Looks like a personal journal capture candidate; preview only, no live mutation.",
                proposedCanonicalTitle: isoDate.map(JournalTitle.canonicalTitle(forISODate:)),
                proposedISODate: isoDate,
                preservedCaptureHints: hints
            )
        }

        return JournalMigrationPreviewRow(
            note: note,
            classification: .ambiguous,
            reason: "Mentions journal but lacks enough personal/day-entry evidence for automatic promotion.",
            proposedCanonicalTitle: isoDate.map(JournalTitle.canonicalTitle(forISODate:)),
            proposedISODate: isoDate,
            preservedCaptureHints: hints
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

    private func firstISODate(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.isoDateRegex.firstMatch(in: text, range: range),
              let dateRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let candidate = String(text[dateRange])
        return JournalTitle.isValidISODate(candidate) ? candidate : nil
    }

    private static let isoDateRegex = try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})"#)
}
