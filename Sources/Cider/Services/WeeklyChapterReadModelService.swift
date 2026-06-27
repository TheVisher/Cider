import Foundation

struct WeeklyChapterPreview {
    var weekStart: String
    var weekEnd: String
    var title: String
    var exists: Bool
    var dailyEpisodes: [WeeklyChapterDayPreview]
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignals: [WeeklyChapterRecurringSignal]
    var candidateCoverageDiagnostic: WeeklyChapterCandidateCoverageDiagnostic
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

struct WeeklyChapterCandidateCoverageDiagnostic: Equatable {
    var truthBoundary: String
    var explanation: String
    var whyRecurringSignals: String
    var reviewableRepeatThreshold: Int
    var counts: WeeklyChapterCandidateCoverageCounts
    var byDay: [WeeklyChapterCandidateCoverageDay]
    var singletonReviewableGroups: [WeeklyChapterCandidateCoverageGroup]
    var safeNextCommands: [String]
}

struct WeeklyChapterCandidateCoverageCounts: Equatable {
    var sourceItemCount: Int
    var daysWithSources: Int
    var graphCandidateOutputCount: Int
    var reviewableCandidateOutputCount: Int
    var repeatedReviewableGroupCount: Int
    var singletonReviewableGroupCount: Int
    var filteredAcceptedCount: Int
    var filteredRejectedCount: Int
    var filteredOtherStateCount: Int
    var malformedCandidatePayloadCount: Int
    var unsupportedCandidatePayloadCount: Int
}

struct WeeklyChapterCandidateCoverageDay: Equatable {
    var date: String
    var sourceItemCount: Int
    var graphCandidateOutputCount: Int
    var reviewableCandidateOutputCount: Int
    var repeatedReviewableGroupCount: Int
    var singletonReviewableGroupCount: Int
    var malformedCandidatePayloadCount: Int
}

struct WeeklyChapterCandidateCoverageGroup: Equatable {
    var id: String
    var mentionText: String
    var normalizedValue: String
    var count: Int
    var candidateRefs: [String]
    var sourceRefs: [String]
    var reviewState: String
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
        let coverage = try recurringCandidateCoverage(
            sourceOwnerRefs: sourceOwnerRefs,
            dayPreviews: dayPreviews
        )
        let recurringSignals = coverage.signals
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
            candidateCoverageDiagnostic: coverage.diagnostic,
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

    private struct CandidateCoverageResult {
        var signals: [WeeklyChapterRecurringSignal]
        var diagnostic: WeeklyChapterCandidateCoverageDiagnostic
    }

    private func recurringCandidateCoverage(
        sourceOwnerRefs: Set<String>,
        dayPreviews: [WeeklyChapterDayPreview]
    ) throws -> CandidateCoverageResult {
        guard database.isOpen, !sourceOwnerRefs.isEmpty else {
            let diagnostic = WeeklyChapterCandidateCoverageDiagnostic(
                truthBoundary: "candidate_coverage_not_truth",
                explanation: "No source items were found for this week, so Cider did not find graph candidate outputs to group.",
                whyRecurringSignals: "no_source_items",
                reviewableRepeatThreshold: 2,
                counts: WeeklyChapterCandidateCoverageCounts(
                    sourceItemCount: 0,
                    daysWithSources: 0,
                    graphCandidateOutputCount: 0,
                    reviewableCandidateOutputCount: 0,
                    repeatedReviewableGroupCount: 0,
                    singletonReviewableGroupCount: 0,
                    filteredAcceptedCount: 0,
                    filteredRejectedCount: 0,
                    filteredOtherStateCount: 0,
                    malformedCandidatePayloadCount: 0,
                    unsupportedCandidatePayloadCount: 0
                ),
                byDay: dayPreviews.map {
                    WeeklyChapterCandidateCoverageDay(
                        date: $0.date,
                        sourceItemCount: $0.dailyJournal == nil ? 0 : 1,
                        graphCandidateOutputCount: 0,
                        reviewableCandidateOutputCount: 0,
                        repeatedReviewableGroupCount: 0,
                        singletonReviewableGroupCount: 0,
                        malformedCandidatePayloadCount: 0
                    )
                },
                singletonReviewableGroups: [],
                safeNextCommands: ["cider-cli capture review-queue --kind graph_candidate --json"]
            )
            return CandidateCoverageResult(signals: [], diagnostic: diagnostic)
        }

        let outputs = try enrichmentService.outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: nil,
            limit: nil
        )
        let weeklyOutputs = outputs.filter { sourceOwnerRefs.contains($0.owner.canonicalRef) }
        var reviewable: [(SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)] = []
        var acceptedCount = 0
        var rejectedCount = 0
        var filteredOtherStateCount = 0
        var malformedCount = 0
        var unsupportedCount = 0

        for output in weeklyOutputs {
            do {
                let candidate = try SecondBrainGraphCandidateContract.validate(output)
                switch candidate.reviewState {
                case .suggested, .needsReview, .deferred:
                    reviewable.append((output, candidate))
                case .accepted:
                    acceptedCount += 1
                case .rejected:
                    rejectedCount += 1
                }
            } catch let error as SecondBrainGraphCandidateContract.ValidationError {
                switch error {
                case .invalidCandidateKind, .wrongKind:
                    unsupportedCount += 1
                case .invalidReviewState:
                    filteredOtherStateCount += 1
                default:
                    malformedCount += 1
                }
            } catch {
                malformedCount += 1
            }
        }
        let grouped = Dictionary(grouping: reviewable) { pair in
            pair.0.normalizedValue.isEmpty
                ? pair.1.mentionText.lowercased()
                : pair.0.normalizedValue.lowercased()
        }
        let repeatedGroups = grouped.values.filter { $0.count >= 2 }
        let singletonGroups = grouped.values.filter { $0.count == 1 }

        let signals = repeatedGroups.map(signal(from:)).sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
        }
        let singletonDiagnostics = singletonGroups.map(candidateCoverageGroup(from:)).sorted {
            $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
        }

        let ownerOutputs = Dictionary(grouping: weeklyOutputs, by: { $0.owner.canonicalRef })
        let ownerReviewable = Dictionary(grouping: reviewable, by: { $0.0.owner.canonicalRef })
        let ownerMalformedCounts = malformedCandidateCountsByOwner(weeklyOutputs)
        let byDay = dayPreviews.map { day -> WeeklyChapterCandidateCoverageDay in
            let refs = [day.dailyJournal?.ref].compactMap { $0 }
            let dayOutputs = refs.flatMap { ownerOutputs[$0] ?? [] }
            let dayReviewable = refs.flatMap { ownerReviewable[$0] ?? [] }
            let dayGrouped = Dictionary(grouping: dayReviewable) { pair in
                pair.0.normalizedValue.isEmpty
                    ? pair.1.mentionText.lowercased()
                    : pair.0.normalizedValue.lowercased()
            }
            return WeeklyChapterCandidateCoverageDay(
                date: day.date,
                sourceItemCount: refs.count,
                graphCandidateOutputCount: dayOutputs.count,
                reviewableCandidateOutputCount: dayReviewable.count,
                repeatedReviewableGroupCount: dayGrouped.values.filter { $0.count >= 2 }.count,
                singletonReviewableGroupCount: dayGrouped.values.filter { $0.count == 1 }.count,
                malformedCandidatePayloadCount: refs.reduce(0) { $0 + (ownerMalformedCounts[$1] ?? 0) }
            )
        }

        let counts = WeeklyChapterCandidateCoverageCounts(
            sourceItemCount: sourceOwnerRefs.count,
            daysWithSources: dayPreviews.filter { $0.dailyJournal != nil }.count,
            graphCandidateOutputCount: weeklyOutputs.count,
            reviewableCandidateOutputCount: reviewable.count,
            repeatedReviewableGroupCount: repeatedGroups.count,
            singletonReviewableGroupCount: singletonGroups.count,
            filteredAcceptedCount: acceptedCount,
            filteredRejectedCount: rejectedCount,
            filteredOtherStateCount: filteredOtherStateCount,
            malformedCandidatePayloadCount: malformedCount,
            unsupportedCandidatePayloadCount: unsupportedCount
        )
        let reason = whyRecurringSignals(counts: counts)
        let diagnostic = WeeklyChapterCandidateCoverageDiagnostic(
            truthBoundary: "candidate_coverage_not_truth",
            explanation: explanation(forCoverageReason: reason),
            whyRecurringSignals: reason,
            reviewableRepeatThreshold: 2,
            counts: counts,
            byDay: byDay,
            singletonReviewableGroups: Array(singletonDiagnostics.prefix(10)),
            safeNextCommands: diagnosticSafeNextCommands(dayPreviews: dayPreviews, weeklyOutputs: weeklyOutputs)
        )

        return CandidateCoverageResult(signals: signals, diagnostic: diagnostic)
    }

    private func signal(
        from pairs: [(SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)]
    ) -> WeeklyChapterRecurringSignal {
        let sorted = sortedCandidatePairs(pairs)
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

    private func candidateCoverageGroup(
        from pairs: [(SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)]
    ) -> WeeklyChapterCandidateCoverageGroup {
        let sorted = sortedCandidatePairs(pairs)
        let first = sorted[0]
        let reviewStates = orderedUniqueStrings(sorted.map { $0.0.reviewState })
        return WeeklyChapterCandidateCoverageGroup(
            id: first.0.normalizedValue.isEmpty ? first.1.mentionText.lowercased() : first.0.normalizedValue,
            mentionText: first.1.mentionText,
            normalizedValue: first.0.normalizedValue,
            count: sorted.count,
            candidateRefs: sorted.map { "graph_candidate:\($0.0.id)" },
            sourceRefs: orderedUniqueStrings(sorted.map { $0.0.owner.canonicalRef }),
            reviewState: reviewStates.count == 1 ? reviewStates[0] : "mixed_review_states"
        )
    }

    private func sortedCandidatePairs(
        _ pairs: [(SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)]
    ) -> [(SecondBrainEnrichmentOutput, SecondBrainGraphCandidateContract.Candidate)] {
        pairs.sorted {
            if $0.0.owner.canonicalRef != $1.0.owner.canonicalRef {
                return $0.0.owner.canonicalRef < $1.0.owner.canonicalRef
            }
            return $0.0.id < $1.0.id
        }
    }

    private func malformedCandidateCountsByOwner(_ outputs: [SecondBrainEnrichmentOutput]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for output in outputs {
            do {
                _ = try SecondBrainGraphCandidateContract.validate(output)
            } catch let error as SecondBrainGraphCandidateContract.ValidationError {
                switch error {
                case .invalidCandidateKind, .wrongKind, .invalidReviewState:
                    continue
                default:
                    counts[output.owner.canonicalRef, default: 0] += 1
                }
            } catch {
                counts[output.owner.canonicalRef, default: 0] += 1
            }
        }
        return counts
    }

    private func whyRecurringSignals(counts: WeeklyChapterCandidateCoverageCounts) -> String {
        if counts.sourceItemCount == 0 { return "no_source_items" }
        if counts.graphCandidateOutputCount == 0 { return "source_items_but_no_graph_candidates" }
        if counts.reviewableCandidateOutputCount == 0 { return "no_reviewable_graph_candidates_after_filters" }
        if counts.repeatedReviewableGroupCount == 0 { return "singleton_only_reviewable_candidates" }
        return "repeated_reviewable_candidates_found"
    }

    private func explanation(forCoverageReason reason: String) -> String {
        switch reason {
        case "no_source_items":
            return "No source items were found for this week, so Cider did not find graph candidate outputs to group."
        case "source_items_but_no_graph_candidates":
            return "Source items exist for this week, but no graph candidate enrichment outputs were found for those sources."
        case "no_reviewable_graph_candidates_after_filters":
            return "Graph candidate outputs were found, but none are reviewable recurring-signal inputs after state and payload checks."
        case "singleton_only_reviewable_candidates":
            return "Reviewable graph candidates were found, but each candidate group appears only once in the week."
        default:
            return "Repeated reviewable graph candidate groups were found; recurringSignals only reflects source-backed candidates, not accepted truth."
        }
    }

    private func diagnosticSafeNextCommands(
        dayPreviews: [WeeklyChapterDayPreview],
        weeklyOutputs: [SecondBrainEnrichmentOutput]
    ) -> [String] {
        orderedUniqueStrings(
            dayPreviews.map {
                "cider-cli item daily-episode --date \($0.date) --json"
            } + dayPreviews.compactMap(\.dailyJournal).flatMap { item in
                [
                    "cider-cli item context \(item.type) \(item.id) --json",
                    "cider-cli item graph-candidates \(item.type) \(item.id) --json",
                ]
            } + weeklyOutputs.prefix(10).map {
                "cider-cli item graph-candidate \($0.id) --json"
            } + ["cider-cli capture review-queue --kind graph_candidate --json"]
        )
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
