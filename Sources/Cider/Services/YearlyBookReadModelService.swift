import Foundation

struct YearlyBookPreview {
    var year: String
    var yearStart: String
    var yearEnd: String
    var title: String
    var exists: Bool
    var months: [YearlyBookMonthPreview]
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignals: [WeeklyChapterRecurringSignal]
    var candidateCoverageDiagnostic: YearlyBookCandidateCoverageDiagnostic
    var explanation: String?
    var safeNextCommands: [String]
}

struct YearlyBookMonthPreview {
    var month: String
    var monthStart: String
    var monthEnd: String
    var exists: Bool
    var sourceItemCount: Int
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignalCount: Int
    var candidateCoverageDiagnostic: MonthlyChapterCandidateCoverageDiagnostic
    var safeNextCommands: [String]
}

struct YearlyBookCandidateCoverageDiagnostic {
    var truthBoundary: String
    var explanation: String
    var whyRecurringSignals: String
    var reviewableRepeatThreshold: Int
    var counts: WeeklyChapterCandidateCoverageCounts
    var byMonth: [YearlyBookCandidateCoverageMonth]
    var singletonReviewableGroups: [WeeklyChapterCandidateCoverageGroup]
    var safeNextCommands: [String]
}

struct YearlyBookCandidateCoverageMonth {
    var month: String
    var monthStart: String
    var monthEnd: String
    var sourceItemCount: Int
    var daysWithSources: Int
    var graphCandidateOutputCount: Int
    var reviewableCandidateOutputCount: Int
    var repeatedReviewableGroupCount: Int
    var singletonReviewableGroupCount: Int
    var malformedCandidatePayloadCount: Int
}

@MainActor
final class YearlyBookReadModelService {
    private let monthlyService: MonthlyChapterReadModelService

    init(
        database: CiderDatabase = .shared,
        notesStorage: NotesStorage = .shared,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.monthlyService = MonthlyChapterReadModelService(
            database: database,
            notesStorage: notesStorage,
            calendar: calendar
        )
    }

    func preview(year rawYear: String) throws -> YearlyBookPreview {
        guard Self.yearFormatter.date(from: rawYear).map({ Self.yearFormatter.string(from: $0) == rawYear }) == true else {
            throw YearlyBookReadModelError.invalidYear(rawYear)
        }

        let monthlyPreviews = try (1...12).map { monthIndex in
            try monthlyService.preview(month: "\(rawYear)-\(String(format: "%02d", monthIndex))")
        }
        let monthSummaries = monthlyPreviews.map(Self.monthPreview(from:))
        let sourceItemRefs = orderedUniqueSourceItems(monthSummaries.flatMap(\.sourceItemRefs))
        let recurringSignals = yearlyRecurringSignals(from: monthlyPreviews)
        let coverage = yearlyCoverage(
            year: rawYear,
            monthSummaries: monthSummaries,
            monthlyPreviews: monthlyPreviews,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: recurringSignals
        )
        let exists = monthSummaries.contains(where: \.exists) || !recurringSignals.isEmpty
        let explanation = exists ? nil : "No monthly chapters, daily journal notes, or recurring candidate themes were found for \(rawYear)."

        return YearlyBookPreview(
            year: rawYear,
            yearStart: "\(rawYear)-01-01",
            yearEnd: "\(rawYear)-12-31",
            title: "Yearly Book Index \(rawYear)",
            exists: exists,
            months: monthSummaries,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: recurringSignals,
            candidateCoverageDiagnostic: coverage,
            explanation: explanation,
            safeNextCommands: safeNextCommands(
                year: rawYear,
                monthSummaries: monthSummaries,
                sourceItemRefs: sourceItemRefs,
                recurringSignals: recurringSignals
            )
        )
    }

    private static func monthPreview(from preview: MonthlyChapterPreview) -> YearlyBookMonthPreview {
        YearlyBookMonthPreview(
            month: preview.month,
            monthStart: preview.monthStart,
            monthEnd: preview.monthEnd,
            exists: preview.exists,
            sourceItemCount: preview.sourceItemRefs.count,
            sourceItemRefs: preview.sourceItemRefs,
            recurringSignalCount: preview.recurringSignals.count,
            candidateCoverageDiagnostic: preview.candidateCoverageDiagnostic,
            safeNextCommands: [
                "cider-cli item monthly-chapter --month \(preview.month) --json",
            ]
        )
    }

    private struct SignalAccumulator {
        var id: String
        var mentionText: String
        var normalizedValue: String
        var count: Int
        var reviewStates: [String]
        var candidateRefs: [String]
        var sourceRefs: [String]
        var relationGuesses: [String]
        var objectTypeGuesses: [String]
        var examples: [WeeklyChapterSignalExample]
        var safeNextCommands: [String]
    }

    private func yearlyRecurringSignals(from monthlyPreviews: [MonthlyChapterPreview]) -> [WeeklyChapterRecurringSignal] {
        var groups: [String: SignalAccumulator] = [:]
        let yearSourceRefs = Set(monthlyPreviews.flatMap { $0.sourceItemRefs.map(\.ref) })

        for month in monthlyPreviews {
            for signal in month.recurringSignals {
                guard !signal.sourceRefs.isEmpty,
                      signal.sourceRefs.allSatisfy(yearSourceRefs.contains) else { continue }
                merge(signal: signal, into: &groups)
            }
            for group in month.candidateCoverageDiagnostic.singletonReviewableGroups {
                guard !group.sourceRefs.isEmpty,
                      group.sourceRefs.allSatisfy(yearSourceRefs.contains) else { continue }
                merge(group: group, safeNextCommands: month.safeNextCommands, into: &groups)
            }
        }

        return groups.values
            .filter { $0.count >= 2 }
            .map { accumulator in
                let reviewStates = orderedUniqueStrings(accumulator.reviewStates)
                return WeeklyChapterRecurringSignal(
                    id: accumulator.id,
                    mentionText: accumulator.mentionText,
                    normalizedValue: accumulator.normalizedValue,
                    count: accumulator.count,
                    reviewState: reviewStates.count == 1 ? reviewStates[0] : "mixed_review_states",
                    truthBoundary: "reviewable_candidate_not_truth",
                    candidateRefs: orderedUniqueStrings(accumulator.candidateRefs),
                    sourceRefs: orderedUniqueStrings(accumulator.sourceRefs),
                    relationGuesses: orderedUniqueStrings(accumulator.relationGuesses),
                    objectTypeGuesses: orderedUniqueStrings(accumulator.objectTypeGuesses),
                    examples: Array(accumulator.examples.prefix(8)),
                    safeNextCommands: orderedUniqueStrings(accumulator.safeNextCommands)
                )
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
            }
    }

    private func merge(signal: WeeklyChapterRecurringSignal, into groups: inout [String: SignalAccumulator]) {
        let key = signalKey(id: signal.id, mentionText: signal.mentionText)
        var accumulator = groups[key] ?? SignalAccumulator(
            id: signal.id,
            mentionText: signal.mentionText,
            normalizedValue: signal.normalizedValue,
            count: 0,
            reviewStates: [],
            candidateRefs: [],
            sourceRefs: [],
            relationGuesses: [],
            objectTypeGuesses: [],
            examples: [],
            safeNextCommands: []
        )
        accumulator.count += signal.count
        accumulator.reviewStates.append(signal.reviewState)
        accumulator.candidateRefs.append(contentsOf: signal.candidateRefs)
        accumulator.sourceRefs.append(contentsOf: signal.sourceRefs)
        accumulator.relationGuesses.append(contentsOf: signal.relationGuesses)
        accumulator.objectTypeGuesses.append(contentsOf: signal.objectTypeGuesses)
        accumulator.examples.append(contentsOf: signal.examples)
        accumulator.safeNextCommands.append(contentsOf: signal.safeNextCommands)
        groups[key] = accumulator
    }

    private func merge(
        group: WeeklyChapterCandidateCoverageGroup,
        safeNextCommands: [String],
        into groups: inout [String: SignalAccumulator]
    ) {
        let key = signalKey(id: group.id, mentionText: group.mentionText)
        var accumulator = groups[key] ?? SignalAccumulator(
            id: group.id,
            mentionText: group.mentionText,
            normalizedValue: group.normalizedValue,
            count: 0,
            reviewStates: [],
            candidateRefs: [],
            sourceRefs: [],
            relationGuesses: [],
            objectTypeGuesses: [],
            examples: [],
            safeNextCommands: []
        )
        accumulator.count += group.count
        accumulator.reviewStates.append(group.reviewState)
        accumulator.candidateRefs.append(contentsOf: group.candidateRefs)
        accumulator.sourceRefs.append(contentsOf: group.sourceRefs)
        accumulator.safeNextCommands.append(contentsOf: safeNextCommands)
        groups[key] = accumulator
    }

    private func yearlyCoverage(
        year: String,
        monthSummaries: [YearlyBookMonthPreview],
        monthlyPreviews: [MonthlyChapterPreview],
        sourceItemRefs: [DailyEpisodeSourceItem],
        recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> YearlyBookCandidateCoverageDiagnostic {
        let singletonGroups = yearlySingletonGroups(
            from: monthlyPreviews,
            sourceItemRefs: sourceItemRefs,
            excluding: recurringSignals
        )
        let counts = WeeklyChapterCandidateCoverageCounts(
            sourceItemCount: sourceItemRefs.count,
            daysWithSources: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.daysWithSources },
            graphCandidateOutputCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.graphCandidateOutputCount },
            reviewableCandidateOutputCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.reviewableCandidateOutputCount },
            repeatedReviewableGroupCount: recurringSignals.count,
            singletonReviewableGroupCount: singletonGroups.count,
            filteredAcceptedCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredAcceptedCount },
            filteredRejectedCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredRejectedCount },
            filteredOtherStateCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredOtherStateCount },
            malformedCandidatePayloadCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.malformedCandidatePayloadCount },
            unsupportedCandidatePayloadCount: monthSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.unsupportedCandidatePayloadCount }
        )
        let reason = whyRecurringSignals(counts: counts)
        return YearlyBookCandidateCoverageDiagnostic(
            truthBoundary: "candidate_coverage_not_truth",
            explanation: explanation(forCoverageReason: reason),
            whyRecurringSignals: reason,
            reviewableRepeatThreshold: 2,
            counts: counts,
            byMonth: monthSummaries.map { month in
                YearlyBookCandidateCoverageMonth(
                    month: month.month,
                    monthStart: month.monthStart,
                    monthEnd: month.monthEnd,
                    sourceItemCount: month.sourceItemCount,
                    daysWithSources: month.candidateCoverageDiagnostic.counts.daysWithSources,
                    graphCandidateOutputCount: month.candidateCoverageDiagnostic.counts.graphCandidateOutputCount,
                    reviewableCandidateOutputCount: month.candidateCoverageDiagnostic.counts.reviewableCandidateOutputCount,
                    repeatedReviewableGroupCount: month.recurringSignalCount,
                    singletonReviewableGroupCount: month.candidateCoverageDiagnostic.singletonReviewableGroups.count,
                    malformedCandidatePayloadCount: month.candidateCoverageDiagnostic.counts.malformedCandidatePayloadCount
                )
            },
            singletonReviewableGroups: Array(singletonGroups.prefix(12)),
            safeNextCommands: diagnosticSafeNextCommands(
                year: year,
                monthSummaries: monthSummaries,
                sourceItemRefs: sourceItemRefs
            )
        )
    }

    private func yearlySingletonGroups(
        from monthlyPreviews: [MonthlyChapterPreview],
        sourceItemRefs: [DailyEpisodeSourceItem],
        excluding recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> [WeeklyChapterCandidateCoverageGroup] {
        let recurringIDs = Set(recurringSignals.map { signalKey(id: $0.id, mentionText: $0.mentionText) })
        let yearSourceRefs = Set(sourceItemRefs.map(\.ref))
        var groups: [String: WeeklyChapterCandidateCoverageGroup] = [:]

        for group in monthlyPreviews.flatMap({ $0.candidateCoverageDiagnostic.singletonReviewableGroups }) {
            let key = signalKey(id: group.id, mentionText: group.mentionText)
            guard !recurringIDs.contains(key),
                  groups[key] == nil,
                  !group.sourceRefs.isEmpty,
                  group.sourceRefs.allSatisfy(yearSourceRefs.contains) else { continue }
            groups[key] = group
        }

        return groups.values.sorted {
            $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
        }
    }

    private func diagnosticSafeNextCommands(
        year: String,
        monthSummaries: [YearlyBookMonthPreview],
        sourceItemRefs: [DailyEpisodeSourceItem]
    ) -> [String] {
        orderedUniqueStrings(
            [
                "cider-cli item yearly-book --year \(year) --json",
                "cider-cli item search \"\(year)\" --scope personalMemory --json",
            ] + monthSummaries.map {
                "cider-cli item monthly-chapter --month \($0.month) --json"
            } + sourceItemRefs.flatMap { item in
                [
                    "cider-cli item context \(item.type) \(item.id) --json",
                    "cider-cli item graph-candidates \(item.type) \(item.id) --json",
                ]
            } + ["cider-cli capture review-queue --kind graph_candidate --json"]
        )
    }

    private func safeNextCommands(
        year: String,
        monthSummaries: [YearlyBookMonthPreview],
        sourceItemRefs: [DailyEpisodeSourceItem],
        recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> [String] {
        orderedUniqueStrings(
            [
                "cider-cli item yearly-book --year \(year) --json",
                "cider-cli item search \"\(year)\" --scope personalMemory --json",
            ] + monthSummaries.map {
                "cider-cli item monthly-chapter --month \($0.month) --json"
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
            return "No source items were found for this year, so Cider did not find graph candidate outputs to group."
        case "source_items_but_no_graph_candidates":
            return "Source items exist for this year, but no graph candidate enrichment outputs were found for those sources."
        case "no_reviewable_graph_candidates_after_filters":
            return "Graph candidate outputs were found this year, but none are reviewable recurring-signal inputs after state and payload checks."
        case "singleton_only_reviewable_candidates":
            return "Reviewable graph candidates were found this year, but each candidate group appears only once."
        default:
            return "Repeated reviewable graph candidate groups were found across the year; recurringSignals only reflects source-backed candidates, not accepted truth."
        }
    }

    private func signalKey(id: String, mentionText: String) -> String {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalized.isEmpty { return normalized }
        return mentionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

enum YearlyBookReadModelError: LocalizedError {
    case invalidYear(String)

    var errorDescription: String? {
        switch self {
        case .invalidYear:
            return "Usage: cider-cli item yearly-book --year YYYY [--json]"
        }
    }
}
