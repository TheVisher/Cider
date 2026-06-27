import Foundation

struct MonthlyChapterPreview {
    var month: String
    var monthStart: String
    var monthEnd: String
    var title: String
    var exists: Bool
    var weeks: [MonthlyChapterWeekPreview]
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignals: [WeeklyChapterRecurringSignal]
    var candidateCoverageDiagnostic: MonthlyChapterCandidateCoverageDiagnostic
    var explanation: String?
    var safeNextCommands: [String]
}

struct MonthlyChapterWeekPreview {
    var weekStart: String
    var weekEnd: String
    var exists: Bool
    var daysInMonth: Int
    var daysInMonthWithSources: Int
    var sourceItemRefs: [DailyEpisodeSourceItem]
    var recurringSignals: [WeeklyChapterRecurringSignal]
    var candidateCoverageDiagnostic: WeeklyChapterCandidateCoverageDiagnostic
    var weeklyChapter: WeeklyChapterPreview
    var safeNextCommands: [String]
}

struct MonthlyChapterCandidateCoverageDiagnostic {
    var truthBoundary: String
    var explanation: String
    var whyRecurringSignals: String
    var reviewableRepeatThreshold: Int
    var counts: WeeklyChapterCandidateCoverageCounts
    var byWeek: [MonthlyChapterCandidateCoverageWeek]
    var singletonReviewableGroups: [WeeklyChapterCandidateCoverageGroup]
    var safeNextCommands: [String]
}

struct MonthlyChapterCandidateCoverageWeek {
    var weekStart: String
    var weekEnd: String
    var sourceItemCount: Int
    var daysWithSources: Int
    var graphCandidateOutputCount: Int
    var reviewableCandidateOutputCount: Int
    var repeatedReviewableGroupCount: Int
    var singletonReviewableGroupCount: Int
    var malformedCandidatePayloadCount: Int
}

@MainActor
final class MonthlyChapterReadModelService {
    private let weeklyService: WeeklyChapterReadModelService
    private let calendar: Calendar

    init(
        database: CiderDatabase = .shared,
        notesStorage: NotesStorage = .shared,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.weeklyService = WeeklyChapterReadModelService(
            database: database,
            notesStorage: notesStorage,
            calendar: calendar
        )
        var calendar = calendar
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    func preview(month rawMonth: String) throws -> MonthlyChapterPreview {
        let bounds = try monthBounds(rawMonth)
        let weekStarts = weekStartsCoveringMonth(start: bounds.startDate, end: bounds.endDate)
        let weekPreviews = try weekStarts.map { try weeklyService.preview(weekStart: $0) }
        let weekSummaries = weekPreviews.map {
            weekPreview(from: $0, monthStart: bounds.monthStart, monthEnd: bounds.monthEnd)
        }
        let sourceItemRefs = orderedUniqueSourceItems(weekSummaries.flatMap(\.sourceItemRefs))
        let recurringSignals = monthlyRecurringSignals(from: weekSummaries)
        let coverage = monthlyCoverage(
            month: rawMonth,
            monthStart: bounds.monthStart,
            monthEnd: bounds.monthEnd,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: recurringSignals,
            weekSummaries: weekSummaries
        )
        let exists = weekSummaries.contains(where: \.exists) || !recurringSignals.isEmpty
        let explanation = exists ? nil : "No daily journal notes or recurring candidate themes were found for \(rawMonth)."

        return MonthlyChapterPreview(
            month: rawMonth,
            monthStart: bounds.monthStart,
            monthEnd: bounds.monthEnd,
            title: "Monthly Chapter \(rawMonth)",
            exists: exists,
            weeks: weekSummaries,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: recurringSignals,
            candidateCoverageDiagnostic: coverage,
            explanation: explanation,
            safeNextCommands: safeNextCommands(
                month: rawMonth,
                weekSummaries: weekSummaries,
                sourceItemRefs: sourceItemRefs,
                recurringSignals: recurringSignals
            )
        )
    }

    private func weekPreview(
        from preview: WeeklyChapterPreview,
        monthStart: String,
        monthEnd: String
    ) -> MonthlyChapterWeekPreview {
        let monthDays = preview.dailyEpisodes.filter { $0.date >= monthStart && $0.date <= monthEnd }
        let sourceItemRefs = orderedUniqueSourceItems(monthDays.compactMap(\.dailyJournal))
        return MonthlyChapterWeekPreview(
            weekStart: preview.weekStart,
            weekEnd: preview.weekEnd,
            exists: monthDays.contains(where: \.exists) || preview.recurringSignals.contains {
                !$0.sourceRefs.allSatisfy { sourceRef in !sourceItemRefs.contains(where: { $0.ref == sourceRef }) }
            },
            daysInMonth: monthDays.count,
            daysInMonthWithSources: monthDays.filter { $0.dailyJournal != nil }.count,
            sourceItemRefs: sourceItemRefs,
            recurringSignals: preview.recurringSignals,
            candidateCoverageDiagnostic: preview.candidateCoverageDiagnostic,
            weeklyChapter: preview,
            safeNextCommands: [
                "cider-cli item weekly-chapter --week \(preview.weekStart) --json",
            ] + preview.safeNextCommands
        )
    }

    private struct MonthlySignalAccumulator {
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

    private func monthlyRecurringSignals(from weekSummaries: [MonthlyChapterWeekPreview]) -> [WeeklyChapterRecurringSignal] {
        var groups: [String: MonthlySignalAccumulator] = [:]
        let monthSourceRefs = Set(weekSummaries.flatMap { $0.sourceItemRefs.map(\.ref) })

        for week in weekSummaries {
            for signal in week.recurringSignals {
                guard !signal.sourceRefs.isEmpty,
                      signal.sourceRefs.allSatisfy(monthSourceRefs.contains) else { continue }
                merge(
                    signal: signal,
                    into: &groups
                )
            }
            for group in week.candidateCoverageDiagnostic.singletonReviewableGroups {
                guard !group.sourceRefs.isEmpty,
                      group.sourceRefs.allSatisfy(monthSourceRefs.contains) else { continue }
                merge(
                    group: group,
                    safeNextCommands: week.safeNextCommands,
                    into: &groups
                )
            }
        }

        return groups.values
            .filter { $0.count >= 2 }
            .map { accumulator in
                WeeklyChapterRecurringSignal(
                    id: accumulator.id,
                    mentionText: accumulator.mentionText,
                    normalizedValue: accumulator.normalizedValue,
                    count: accumulator.count,
                    reviewState: orderedUniqueStrings(accumulator.reviewStates).count == 1
                        ? orderedUniqueStrings(accumulator.reviewStates)[0]
                        : "mixed_review_states",
                    truthBoundary: "reviewable_candidate_not_truth",
                    candidateRefs: orderedUniqueStrings(accumulator.candidateRefs),
                    sourceRefs: orderedUniqueStrings(accumulator.sourceRefs),
                    relationGuesses: orderedUniqueStrings(accumulator.relationGuesses),
                    objectTypeGuesses: orderedUniqueStrings(accumulator.objectTypeGuesses),
                    examples: Array(accumulator.examples.prefix(5)),
                    safeNextCommands: orderedUniqueStrings(accumulator.safeNextCommands)
                )
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
            }
    }

    private func merge(
        signal: WeeklyChapterRecurringSignal,
        into groups: inout [String: MonthlySignalAccumulator]
    ) {
        let key = signalKey(id: signal.id, mentionText: signal.mentionText)
        var accumulator = groups[key] ?? MonthlySignalAccumulator(
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
        into groups: inout [String: MonthlySignalAccumulator]
    ) {
        let key = signalKey(id: group.id, mentionText: group.mentionText)
        var accumulator = groups[key] ?? MonthlySignalAccumulator(
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

    private func monthlyCoverage(
        month: String,
        monthStart: String,
        monthEnd: String,
        sourceItemRefs: [DailyEpisodeSourceItem],
        recurringSignals: [WeeklyChapterRecurringSignal],
        weekSummaries: [MonthlyChapterWeekPreview]
    ) -> MonthlyChapterCandidateCoverageDiagnostic {
        let monthSingletonGroups = monthlySingletonGroups(
            from: weekSummaries,
            sourceItemRefs: sourceItemRefs,
            excluding: recurringSignals
        )
        let counts = WeeklyChapterCandidateCoverageCounts(
            sourceItemCount: sourceItemRefs.count,
            daysWithSources: weekSummaries.reduce(0) { $0 + $1.daysInMonthWithSources },
            graphCandidateOutputCount: weekSummaries.reduce(0) {
                $0 + monthDays(in: $1, monthStart: monthStart, monthEnd: monthEnd).reduce(0) {
                    $0 + $1.graphCandidateOutputCount
                }
            },
            reviewableCandidateOutputCount: weekSummaries.reduce(0) {
                $0 + monthDays(in: $1, monthStart: monthStart, monthEnd: monthEnd).reduce(0) {
                    $0 + $1.reviewableCandidateOutputCount
                }
            },
            repeatedReviewableGroupCount: recurringSignals.count,
            singletonReviewableGroupCount: monthSingletonGroups.count,
            filteredAcceptedCount: weekSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredAcceptedCount },
            filteredRejectedCount: weekSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredRejectedCount },
            filteredOtherStateCount: weekSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.filteredOtherStateCount },
            malformedCandidatePayloadCount: weekSummaries.reduce(0) {
                $0 + monthDays(in: $1, monthStart: monthStart, monthEnd: monthEnd).reduce(0) {
                    $0 + $1.malformedCandidatePayloadCount
                }
            },
            unsupportedCandidatePayloadCount: weekSummaries.reduce(0) { $0 + $1.candidateCoverageDiagnostic.counts.unsupportedCandidatePayloadCount }
        )
        let reason = whyRecurringSignals(counts: counts)
        return MonthlyChapterCandidateCoverageDiagnostic(
            truthBoundary: "candidate_coverage_not_truth",
            explanation: explanation(forCoverageReason: reason),
            whyRecurringSignals: reason,
            reviewableRepeatThreshold: 2,
            counts: counts,
            byWeek: weekSummaries.map { week in
                let filteredDays = monthDays(in: week, monthStart: monthStart, monthEnd: monthEnd)
                let weekSourceRefs = Set(week.sourceItemRefs.map(\.ref))
                return MonthlyChapterCandidateCoverageWeek(
                    weekStart: week.weekStart,
                    weekEnd: week.weekEnd,
                    sourceItemCount: week.sourceItemRefs.count,
                    daysWithSources: week.daysInMonthWithSources,
                    graphCandidateOutputCount: filteredDays.reduce(0) { $0 + $1.graphCandidateOutputCount },
                    reviewableCandidateOutputCount: filteredDays.reduce(0) { $0 + $1.reviewableCandidateOutputCount },
                    repeatedReviewableGroupCount: week.recurringSignals.filter {
                        !$0.sourceRefs.isEmpty && $0.sourceRefs.allSatisfy(weekSourceRefs.contains)
                    }.count,
                    singletonReviewableGroupCount: week.candidateCoverageDiagnostic.singletonReviewableGroups.filter {
                        !$0.sourceRefs.isEmpty && $0.sourceRefs.allSatisfy(weekSourceRefs.contains)
                    }.count,
                    malformedCandidatePayloadCount: filteredDays.reduce(0) { $0 + $1.malformedCandidatePayloadCount }
                )
            },
            singletonReviewableGroups: Array(monthSingletonGroups.prefix(10)),
            safeNextCommands: diagnosticSafeNextCommands(month: month, weekSummaries: weekSummaries, sourceItemRefs: sourceItemRefs)
        )
    }

    private func monthlySingletonGroups(
        from weekSummaries: [MonthlyChapterWeekPreview],
        sourceItemRefs: [DailyEpisodeSourceItem],
        excluding recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> [WeeklyChapterCandidateCoverageGroup] {
        let recurringIDs = Set(recurringSignals.map { signalKey(id: $0.id, mentionText: $0.mentionText) })
        let monthSourceRefs = Set(sourceItemRefs.map(\.ref))
        var groups: [String: WeeklyChapterCandidateCoverageGroup] = [:]
        for group in weekSummaries.flatMap({ $0.candidateCoverageDiagnostic.singletonReviewableGroups }) {
            let key = signalKey(id: group.id, mentionText: group.mentionText)
            guard !recurringIDs.contains(key),
                  groups[key] == nil,
                  !group.sourceRefs.isEmpty,
                  group.sourceRefs.allSatisfy(monthSourceRefs.contains) else { continue }
            groups[key] = group
        }
        return groups.values.sorted {
            $0.mentionText.localizedCaseInsensitiveCompare($1.mentionText) == .orderedAscending
        }
    }

    private func monthDays(
        in week: MonthlyChapterWeekPreview,
        monthStart: String,
        monthEnd: String
    ) -> [WeeklyChapterCandidateCoverageDay] {
        week.candidateCoverageDiagnostic.byDay.filter { $0.date >= monthStart && $0.date <= monthEnd }
    }

    private func diagnosticSafeNextCommands(
        month: String,
        weekSummaries: [MonthlyChapterWeekPreview],
        sourceItemRefs: [DailyEpisodeSourceItem]
    ) -> [String] {
        orderedUniqueStrings(
            [
                "cider-cli item monthly-chapter --month \(month) --json",
                "cider-cli item search \"\(month)\" --scope personalMemory --json",
            ] + weekSummaries.map {
                "cider-cli item weekly-chapter --week \($0.weekStart) --json"
            } + sourceItemRefs.flatMap { item in
                [
                    "cider-cli item context \(item.type) \(item.id) --json",
                    "cider-cli item graph-candidates \(item.type) \(item.id) --json",
                ]
            } + ["cider-cli capture review-queue --kind graph_candidate --json"]
        )
    }

    private func safeNextCommands(
        month: String,
        weekSummaries: [MonthlyChapterWeekPreview],
        sourceItemRefs: [DailyEpisodeSourceItem],
        recurringSignals: [WeeklyChapterRecurringSignal]
    ) -> [String] {
        orderedUniqueStrings(
            [
                "cider-cli item monthly-chapter --month \(month) --json",
                "cider-cli item search \"\(month)\" --scope personalMemory --json",
            ] + weekSummaries.flatMap(\.safeNextCommands) + sourceItemRefs.flatMap { item in
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

    private func monthBounds(_ rawMonth: String) throws -> (startDate: Date, endDate: Date, monthStart: String, monthEnd: String) {
        guard let start = Self.monthFormatter.date(from: rawMonth),
              let range = calendar.range(of: .day, in: .month, for: start),
              let end = calendar.date(byAdding: .day, value: range.count - 1, to: start)
        else {
            throw MonthlyChapterReadModelError.invalidMonth(rawMonth)
        }
        return (
            startDate: start,
            endDate: end,
            monthStart: Self.dateFormatter.string(from: start),
            monthEnd: Self.dateFormatter.string(from: end)
        )
    }

    private func weekStartsCoveringMonth(start: Date, end: Date) -> [String] {
        var starts: [String] = []
        var current = startOfWeek(containing: start)
        let final = startOfWeek(containing: end)
        while current <= final {
            starts.append(Self.dateFormatter.string(from: current))
            current = calendar.date(byAdding: .day, value: 7, to: current) ?? current.addingTimeInterval(7 * 24 * 60 * 60)
        }
        return starts
    }

    private func startOfWeek(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromWeekStart, to: startOfDay) ?? startOfDay
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
            return "No source items were found for this month, so Cider did not find graph candidate outputs to group."
        case "source_items_but_no_graph_candidates":
            return "Source items exist for this month, but no graph candidate enrichment outputs were found for those sources."
        case "no_reviewable_graph_candidates_after_filters":
            return "Graph candidate outputs were found this month, but none are reviewable recurring-signal inputs after state and payload checks."
        case "singleton_only_reviewable_candidates":
            return "Reviewable graph candidates were found this month, but each candidate group appears only once."
        default:
            return "Repeated reviewable graph candidate groups were found across the month; recurringSignals only reflects source-backed candidates, not accepted truth."
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum MonthlyChapterReadModelError: LocalizedError {
    case invalidMonth(String)

    var errorDescription: String? {
        switch self {
        case .invalidMonth:
            return "Usage: cider-cli item monthly-chapter --month YYYY-MM [--json]"
        }
    }
}
