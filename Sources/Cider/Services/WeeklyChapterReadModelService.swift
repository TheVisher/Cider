import Foundation

struct WeeklyChapterPreview {
    var weekStart: String
    var weekEnd: String
    var title: String
    var exists: Bool
    var dailyEpisodes: [WeeklyChapterDayPreview]
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignals: [WeeklyChapterRecurringSignal]
    var explanation: String?
    var safeNextCommands: [String]
}

struct WeeklyChapterDayPreview: Equatable {
    var date: String
    var exists: Bool
    var dailyJournal: DailyEpisodeSourceItem?
    var entryCount: Int
    var summaries: [String]
    var safeNextCommands: [String]
}

struct WeeklyChapterRecurringSignal: Equatable {
    var id: String
    var mentionText: String
    var normalizedValue: String
    var count: Int
    var reviewState: String
    var truthBoundary: String
    var candidateRefs: [String]
    var sourceRefs: [String]
    var relationGuesses: [String]
    var objectTypeGuesses: [String]
    var examples: [WeeklyChapterSignalExample]
    var safeNextCommands: [String]
}

struct WeeklyChapterSignalExample: Equatable {
    var candidateRef: String
    var sourceRef: String
    var sourceQuote: String
    var reviewState: String
    var confidence: Double?
}

@MainActor
final class WeeklyChapterReadModelService {
    private let database: CiderDatabase
    private let dailyEpisodeService: DailyEpisodeReadModelService
    private let enrichmentService: SecondBrainEnrichmentOutputService
    private let calendar: Calendar

    init(
        database: CiderDatabase = .shared,
        notesStorage: NotesStorage = .shared,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.database = database
        self.dailyEpisodeService = DailyEpisodeReadModelService(database: database, notesStorage: notesStorage)
        self.enrichmentService = SecondBrainEnrichmentOutputService(database: database)
        var calendar = calendar
        calendar.timeZone = TimeZone.current
        self.calendar = calendar
    }

    func preview(weekStart: String) throws -> WeeklyChapterPreview {
        let dates = try weekDates(startingAt: weekStart)
        let weekEnd = dates.last ?? weekStart
        let dailyPreviews = try dates.map { try dailyEpisodeService.preview(date: $0) }
        let dayPreviews = dailyPreviews.map(Self.dayPreview(from:))
        let sourceItemRefs = orderedUniqueSourceItems(dailyPreviews.flatMap(\.sourceItemRefs))
        let sourceOwnerRefs = Set(sourceItemRefs.map(\.ref))
        let recurringSignals = try recurringCandidateSignals(sourceOwnerRefs: sourceOwnerRefs)
        let exists = dayPreviews.contains(where: \.exists) || !recurringSignals.isEmpty
        let title = "Weekly Chapter \(weekStart) to \(weekEnd)"
        let explanation = exists ? nil : "No daily journal notes or recurring candidate themes were found for \(weekStart) to \(weekEnd)."

        return WeeklyChapterPreview(
            weekStart: weekStart,
            weekEnd: weekEnd,
            title: title,
            exists: exists,
            dailyEpisodes: dayPreviews,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: recurringSignals,
            explanation: explanation,
            safeNextCommands: safeNextCommands(
                weekStart: weekStart,
                dates: dates,
                sourceItemRefs: sourceItemRefs,
                recurringSignals: recurringSignals
            )
        )
    }

    private func weekDates(startingAt rawStart: String) throws -> [String] {
        guard let start = Self.dateFormatter.date(from: rawStart) else {
            throw WeeklyChapterReadModelError.invalidWeek(rawStart)
        }
        return try (0..<7).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                throw WeeklyChapterReadModelError.invalidWeek(rawStart)
            }
            return Self.dateFormatter.string(from: date)
        }
    }

    private static func dayPreview(from preview: DailyEpisodePreview) -> WeeklyChapterDayPreview {
        WeeklyChapterDayPreview(
            date: preview.date,
            exists: preview.exists,
            dailyJournal: preview.dailyJournal,
            entryCount: preview.entries.count,
            summaries: preview.entries.map(\.snippet),
            safeNextCommands: preview.safeNextCommands
        )
    }

    private func recurringCandidateSignals(sourceOwnerRefs: Set<String>) throws -> [WeeklyChapterRecurringSignal] {
        guard database.isOpen, !sourceOwnerRefs.isEmpty else { return [] }
        let outputs = try enrichmentService.outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: ["suggested", "needs_review", "deferred"],
            limit: nil
        )
        let weeklyOutputs = outputs.filter { sourceOwnerRefs.contains($0.owner.canonicalRef) }
        let valid = weeklyOutputs.compactMap { output -> (SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)? in
            guard let candidate = try? SecondBrainGraphCandidateContract.validate(output) else { return nil }
            return (output, candidate)
        }
        let grouped = Dictionary(grouping: valid) { pair in
            pair.0.normalizedValue.isEmpty
                ? pair.1.mentionText.lowercased()
                : pair.0.normalizedValue.lowercased()
        }

        return grouped.values.compactMap { pairs -> WeeklyChapterRecurringSignal? in
            guard pairs.count >= 2 else { return nil }
            let sorted = pairs.sorted {
                if $0.0.owner.canonicalRef != $1.0.owner.canonicalRef {
                    return $0.0.owner.canonicalRef < $1.0.owner.canonicalRef
                }
                return $0.0.id < $1.0.id
            }
            let first = sorted[0]
            let reviewStates = orderedUniqueStrings(sorted.map { $0.0.reviewState })
            let relationGuesses = orderedUniqueStrings(sorted.flatMap { $0.1.relationGuesses.map(\.rawValue) })
            let objectTypeGuesses = orderedUniqueStrings(sorted.flatMap { $0.1.objectTypeGuesses.map(\.rawValue) })
            let candidateRefs = sorted.map { "graph_candidate:\($0.0.id)" }
            let sourceRefs = orderedUniqueStrings(sorted.map { $0.0.owner.canonicalRef })
            let examples = sorted.prefix(5).map { output, candidate in
                WeeklyChapterSignalExample(
                    candidateRef: "graph_candidate:\(output.id)",
                    sourceRef: output.owner.canonicalRef,
                    sourceQuote: candidate.sourceQuote,
                    reviewState: output.reviewState,
                    confidence: output.confidence
                )
            }
            let safeCommands = orderedUniqueStrings(
                sorted.flatMap { output, _ in
                    [
                        "cider-cli item graph-candidate \(output.id) --json",
                        "cider-cli item graph-candidates \(output.owner.ownerType) \(output.owner.ownerID) --json",
                        "cider-cli item context \(output.owner.ownerType) \(output.owner.ownerID) --json",
                    ]
                } + ["cider-cli capture review-queue --kind graph_candidate --json"]
            )
            return WeeklyChapterRecurringSignal(
                id: first.0.normalizedValue.isEmpty ? first.1.mentionText.lowercased() : first.0.normalizedValue,
                mentionText: first.1.mentionText,
                normalizedValue: first.0.normalizedValue,
                count: sorted.count,
                reviewState: reviewStates.count == 1 ? reviewStates[0] : "mixed_review_states",
                truthBoundary: "reviewable_candidate_not_truth",
                candidateRefs: candidateRefs,
                sourceRefs: sourceRefs,
                relationGuesses: relationGuesses,
                objectTypeGuesses: objectTypeGuesses,
                examples: examples,
                safeNextCommands: safeCommands
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
        }
    }

    private func safeNextCommands(
        weekStart: String,
        dates: [String],
        sourceItemRefs: [DailyEpisodeSourceItem],
        recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> [String] {
        orderedUniqueStrings(
            [
                "cider-cli item search \"\(weekStart)\" --scope personalMemory --json",
            ] + dates.map {
                "cider-cli item daily-episode --date \($0) --json"
            } + sourceItemRefs.flatMap { item in
                [
                    "cider-cli item get \(item.type) \(item.id) --json",
                    "cider-cli item context \(item.type) \(item.id) --json",
                    "cider-cli item graph-candidates \(item.type) \(item.id) --json",
                ]
            } + recurringSignals.flatMap(\.safeNextCommands) + [
                "cider-cli capture review-queue --kind graph_candidate --json",
            ]
        )
    }

    private func orderedUniqueSourceItems(_ items: [DailyEpisodeSourceItem]) -> [DailyEpisodeSourceItem] {
        var seen = Set<String>()
        var unique: [DailyEpisodeSourceItem] = []
        for item in items where !seen.contains(item.ref) {
            seen.insert(item.ref)
            unique.append(item)
        }
        return unique
    }

    private func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            unique.append(trimmed)
        }
        return unique
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum WeeklyChapterReadModelError: LocalizedError {
    case invalidWeek(String)

    var errorDescription: String? {
        switch self {
        case .invalidWeek:
            return "Usage: cider-cli item weekly-chapter --week YYYY-MM-DD [--json]"
        }
    }
}
