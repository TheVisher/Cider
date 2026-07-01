import Foundation

enum CiderNaturalPreferenceRecallQuestionKind: String, Codable, Equatable {
    case existence
    case liked
    case lastOrder
    case recentLiked
    case repeatSuggestion
    case general
}

enum CiderNaturalRecallMode: String, Codable, Equatable {
    case preference
    case memory

    var command: String {
        switch self {
        case .preference: return "item.preference-recall"
        case .memory: return "item.memory-recall"
        }
    }

    var answerKind: String {
        switch self {
        case .preference: return "natural_preference_item_recall"
        case .memory: return "natural_memory_recall"
        }
    }

    var noun: String {
        switch self {
        case .preference: return "preference"
        case .memory: return "memory"
        }
    }
}

struct CiderNaturalPreferenceRecallIntent: Codable, Equatable {
    var originalQuery: String
    var normalizedQuery: String
    var semanticQueryTerms: [String]
    var questionKind: CiderNaturalPreferenceRecallQuestionKind
    var temporalIntent: String?
    var temporalDate: String?
    var temporalRange: CiderNaturalPreferenceRecallTemporalRange?
    var eventResolution: CiderNaturalPreferenceRecallEventResolution?
    var factFamily: String?
    var factTarget: String?
    var subject: String?
    var searchQueries: [String]
}

struct CiderNaturalPreferenceRecallTemporalRange: Codable, Equatable {
    var originalQuery: String
    var recognizedText: String
    var rangeType: String
    var startDate: String
    var endDate: String
    var source: String
    var remainingSemanticQuery: String
    var safeNextCommands: [String]
    var eventResolution: CiderNaturalPreferenceRecallEventResolution?
}

struct CiderNaturalPreferenceRecallEventResolutionSource: Codable, Equatable {
    var sourceRef: String
    var sourceType: String
    var sourceID: String
    var title: String
    var sourceKind: String
    var dateSource: String
    var evidence: String
    var safeNextCommands: [String]
}

struct CiderNaturalPreferenceRecallEventResolution: Codable, Equatable {
    var eventQuery: String
    var recognizedText: String
    var resolvedDate: String?
    var confidence: String
    var sourceKind: String
    var truthBoundary: String
    var fallbackReason: String?
    var sources: [CiderNaturalPreferenceRecallEventResolutionSource]
    var safeNextCommands: [String]
}

struct CiderNaturalPreferenceRecallSearchStep: Codable, Equatable {
    var query: String
    var scope: CiderItemSearchScope
    var sort: CiderItemSearchSort
    var limit: Int
}

struct CiderNaturalPreferenceRecallCitation: Identifiable, Codable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var title: String
    var quote: String
    var source: String
    var itemType: String?
    var itemID: String?
    var sourceRef: String
    var safeNextCommands: [String]
}

struct CiderNaturalPreferenceRecallProvenance: Codable, Equatable {
    var sourceRef: String
    var sourceType: String
    var sourceID: String
    var sourceTitle: String
    var sourceLocation: String?
    var evidenceKind: String
    var evidenceExcerpt: String
    var evidenceSummary: String
    var citationRefs: [String]
    var contextCommands: [String]
    var verificationCommands: [String]
}

struct CiderNaturalPreferenceRecallCandidate: Identifiable, Codable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var title: String
    var itemType: String?
    var itemID: String?
    var evidenceKind: String
    var snippet: String
    var claim: String
    var citationRefs: [String]
    var score: Int
    var rankReason: String
    var sortDate: Date?
    var matchedSemanticTerms: [String]
    var matchExplanation: String
    var explanationReasons: [String]
    var evidenceRole: String
    var confidenceBand: String
    var truthBoundary: String
    var safeNextCommands: [String]
    var provenance: CiderNaturalPreferenceRecallProvenance?
}

struct CiderNaturalPreferenceRecallExplanation: Codable, Equatable {
    var confidenceBand: String
    var reasons: [String]
    var primaryEvidenceRefs: [String]
    var relatedEvidenceRefs: [String]
    var weakEvidenceRefs: [String]
    var copy: String
    var safeNextCommands: [String]
}

struct CiderNaturalPreferenceRecallReviewStatus: Codable, Equatable {
    var needsReview: Bool
    var copy: String
}

struct CiderNaturalPreferenceRecallResponse: Codable, Equatable {
    var ok: Bool
    var command: String
    var readOnly: Bool
    var changed: Bool
    var intent: CiderNaturalPreferenceRecallIntent
    var summary: String
    var answerExplanation: CiderNaturalPreferenceRecallExplanation
    var truthBoundary: String
    var reviewStatus: CiderNaturalPreferenceRecallReviewStatus
    var searchPlan: [CiderNaturalPreferenceRecallSearchStep]
    var candidates: [CiderNaturalPreferenceRecallCandidate]
    var citations: [CiderNaturalPreferenceRecallCitation]
    var rankingExplanation: String
    var broaderSearchCommand: String?
    var verificationCommands: [String]
    var safeNextCommands: [String]
    var warnings: [String]
}

@MainActor
final class CiderNaturalPreferenceRecallService {
    private let contextService: CiderItemContextService
    private let database: CiderDatabase
    private let currentDate: Date?
    private let knownEventDates: [String: String]

    init(
        contextService: CiderItemContextService = CiderItemContextService(database: .shared),
        database: CiderDatabase = .shared,
        currentDate: Date? = nil,
        knownEventDates: [String: String] = [:]
    ) {
        self.contextService = contextService
        self.database = database
        self.currentDate = currentDate
        self.knownEventDates = knownEventDates
    }

    func answer(_ query: String, limit: Int = 8) throws -> CiderNaturalPreferenceRecallResponse {
        try answer(query, limit: limit, mode: .preference)
    }

    func answerMemory(_ query: String, limit: Int = 8) throws -> CiderNaturalPreferenceRecallResponse {
        try answer(query, limit: limit, mode: .memory)
    }

    func answer(_ query: String, limit: Int = 8, mode: CiderNaturalRecallMode) throws -> CiderNaturalPreferenceRecallResponse {
        let boundedLimit = max(1, limit)
        let intent = interpret(query, mode: mode)
        let searchPlan = intent.searchQueries.map { query in
            CiderNaturalPreferenceRecallSearchStep(
                query: query,
                scope: .personalMemory,
                sort: searchSort(for: query, intent: intent, mode: mode),
                limit: searchLimit(for: query, intent: intent, mode: mode, requestedLimit: boundedLimit)
            )
        }
        var citationsByOwner: [String: (citation: CiderNaturalPreferenceRecallCitation, score: Int)] = [:]
        var candidatesByOwner: [String: CiderNaturalPreferenceRecallCandidate] = [:]
        var safeCommands: [String] = [
            "cider-cli item \(mode.command.replacingOccurrences(of: "item.", with: "")) \"\(escapedCommandArgument(intent.originalQuery))\" --limit \(boundedLimit) --json",
            "cider-cli item search-debug \"\(escapedCommandArgument(intent.originalQuery))\" --json",
        ]
        if let temporalRange = intent.temporalRange {
            safeCommands.append(contentsOf: temporalRange.safeNextCommands)
        }

        for step in searchPlan {
            safeCommands.append("cider-cli item search \"\(escapedCommandArgument(step.query))\" --scope \(step.scope.rawValue) --sort \(step.sort.rawValue) --limit \(step.limit) --json")
            let results = try contextService.search(
                step.query,
                limit: step.limit,
                scope: step.scope,
                sort: step.sort
            )
            for result in results {
                guard let item = result.item else { continue }
                let bundle = try contextService.context(for: LibraryEntityRef(type: item.type, entityID: item.id))
                let quote = bestQuote(in: bundle, result: result, intent: intent, mode: mode)
                guard qualifies(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode) else { continue }
                let key = bundle.owner.canonicalRef
                let commands = [
                    "cider-cli item context \(bundle.item.type.rawValue) \(bundle.item.id.uuidString) --json",
                    "cider-cli item search \"\(escapedCommandArgument(step.query))\" --scope \(step.scope.rawValue) --sort \(step.sort.rawValue) --limit \(step.limit) --json",
                ]
                let verificationCommands = [
                    "cider-cli item context \(bundle.item.type.rawValue) \(bundle.item.id.uuidString) --json",
                    "cider-cli item get \(bundle.item.type.rawValue) \(bundle.item.id.uuidString) --json",
                ]
                let sourceRef = "\(bundle.item.type.rawValue):\(bundle.item.id.uuidString)"
                let sortDate = sourceSortDate(bundle: bundle, result: result)
                guard sourceDateMatchesTemporalRangeIfNeeded(sortDate, intent: intent) else { continue }
                let score = evidenceScore(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode)
                let rankReason = rankReason(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode, sortDate: sortDate)
                let evidenceKind = evidenceKind(quote: quote, result: result, intent: intent, mode: mode)
                let matchedTerms = matchedSemanticTerms(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode)
                let matchExplanation = matchExplanation(matchedTerms: matchedTerms, intent: intent, result: result, mode: mode, sortDate: sortDate)
                if var candidate = candidatesByOwner[key] {
                    candidate.claim = mergeClaims(candidate.claim, quote)
                    candidate.snippet = mergeClaims(candidate.snippet, clipped(result.snippet, limit: 260))
                    candidate.citationRefs = orderedUnique(candidate.citationRefs + [sourceRef])
                    candidate.score = max(candidate.score, score)
                    candidate.rankReason = mergeRankReasons(candidate.rankReason, rankReason)
                    if sortDate > (candidate.sortDate ?? .distantPast) {
                        candidate.sortDate = sortDate
                    }
                    candidate.matchedSemanticTerms = orderedUnique(candidate.matchedSemanticTerms + matchedTerms)
                    candidate.matchExplanation = mergeRankReasons(candidate.matchExplanation, matchExplanation)
                    candidate.explanationReasons = orderedUnique(candidate.explanationReasons + explanationReasons(
                        rankReason: rankReason,
                        matchedTerms: matchedTerms,
                        intent: intent,
                        mode: mode
                    ))
                    candidate.safeNextCommands = orderedUnique(candidate.safeNextCommands + commands)
                    if var provenance = candidate.provenance {
                        provenance.evidenceExcerpt = mergeClaims(provenance.evidenceExcerpt, quote)
                        provenance.evidenceSummary = mergeClaims(provenance.evidenceSummary, clipped(result.snippet, limit: 220))
                        provenance.citationRefs = orderedUnique(provenance.citationRefs + [sourceRef])
                        provenance.contextCommands = orderedUnique(provenance.contextCommands + commands)
                        provenance.verificationCommands = orderedUnique(provenance.verificationCommands + verificationCommands)
                        candidate.provenance = provenance
                    }
                    if evidenceKind == "source_backed_candidate" {
                        candidate.evidenceKind = evidenceKind
                    }
                    candidatesByOwner[key] = candidate
                } else {
                    candidatesByOwner[key] = CiderNaturalPreferenceRecallCandidate(
                        id: key,
                        owner: bundle.owner,
                        title: bundle.item.title,
                        itemType: bundle.item.type.rawValue,
                        itemID: bundle.item.id.uuidString,
                        evidenceKind: evidenceKind,
                        snippet: clipped(result.snippet, limit: 260),
                        claim: quote,
                        citationRefs: [sourceRef],
                        score: score,
                        rankReason: rankReason,
                        sortDate: sortDate,
                        matchedSemanticTerms: matchedTerms,
                        matchExplanation: matchExplanation,
                        explanationReasons: explanationReasons(
                            rankReason: rankReason,
                            matchedTerms: matchedTerms,
                            intent: intent,
                            mode: mode
                        ),
                        evidenceRole: "unclassified",
                        confidenceBand: "weak",
                        truthBoundary: "source_backed_observations_not_accepted_truth",
                        safeNextCommands: commands,
                        provenance: CiderNaturalPreferenceRecallProvenance(
                            sourceRef: sourceRef,
                            sourceType: bundle.item.type.rawValue,
                            sourceID: bundle.item.id.uuidString,
                            sourceTitle: bundle.item.title,
                            sourceLocation: safeSourceLocation(bundle.item.relativePath),
                            evidenceKind: evidenceKind,
                            evidenceExcerpt: quote,
                            evidenceSummary: clipped(result.snippet, limit: 220),
                            citationRefs: [sourceRef],
                            contextCommands: commands,
                            verificationCommands: verificationCommands
                        )
                    )
                }
                if citationsByOwner[key] == nil {
                    let citation = CiderNaturalPreferenceRecallCitation(
                        id: key,
                        owner: bundle.owner,
                        title: bundle.item.title,
                        quote: quote,
                        source: result.stage ?? result.kind.rawValue,
                        itemType: bundle.item.type.rawValue,
                        itemID: bundle.item.id.uuidString,
                        sourceRef: sourceRef,
                        safeNextCommands: commands
                    )
                    citationsByOwner[key] = (citation, score)
                    safeCommands.append(contentsOf: commands)
                }
            }
        }

        let rankedCandidates = candidatesByOwner.values
            .sorted {
                if let temporalRange = intent.temporalRange, mode == .memory {
                    if shouldPreferTemporalRangeMatch(lhs: $0, rhs: $1, intent: intent) {
                        return sourceDateMatchesTemporalRange($0.sortDate, range: temporalRange)
                    }
                    if temporalRange.rangeType == "month_name",
                       $0.score != $1.score {
                        return $0.score > $1.score
                    }
                    if $0.sortDate != $1.sortDate {
                        return ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast)
                    }
                }
                if let temporalIntent = intent.temporalIntent, mode == .memory {
                    if shouldPreferSpecificDateSourceAnchor(lhs: $0, rhs: $1, intent: intent) {
                        return sourceDateMatchesTemporalIntent($0.sortDate, intent: intent)
                    }
                    if shouldPreferGenericDateSourceAnchor(lhs: $0, rhs: $1, intent: intent) {
                        return sourceDateMatchesTemporalIntent($0.sortDate, intent: temporalIntent)
                    }
                    if shouldPreferLatestJournalSourceDateAnchor(lhs: $0, rhs: $1, intent: intent) {
                        return ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast)
                    }
                    if shouldPreferTemporalRecency(lhs: $0, rhs: $1, intent: temporalIntent) {
                        return ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast)
                    }
                }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(boundedLimit)
            .map { $0 }
        let candidates = classifiedCandidates(rankedCandidates, intent: intent, mode: mode)
        let citations = citationsByOwner.values
            .sorted {
                if let temporalRange = intent.temporalRange, mode == .memory {
                    let lhsCandidate = candidatesByOwner[$0.citation.owner.canonicalRef]
                    let rhsCandidate = candidatesByOwner[$1.citation.owner.canonicalRef]
                    if let lhsCandidate,
                       let rhsCandidate,
                       shouldPreferTemporalRangeMatch(lhs: lhsCandidate, rhs: rhsCandidate, intent: intent) {
                        return sourceDateMatchesTemporalRange(lhsCandidate.sortDate, range: temporalRange)
                    }
                    if let lhsCandidate,
                       let rhsCandidate,
                       temporalRange.rangeType == "month_name",
                       lhsCandidate.score != rhsCandidate.score {
                        return lhsCandidate.score > rhsCandidate.score
                    }
                    if let lhsCandidate,
                       let rhsCandidate,
                       lhsCandidate.sortDate != rhsCandidate.sortDate {
                        return (lhsCandidate.sortDate ?? .distantPast) > (rhsCandidate.sortDate ?? .distantPast)
                    }
                }
                if let temporalIntent = intent.temporalIntent, mode == .memory {
                    let lhsCandidate = candidatesByOwner[$0.citation.owner.canonicalRef]
                    let rhsCandidate = candidatesByOwner[$1.citation.owner.canonicalRef]
                    if let lhsCandidate,
                       let rhsCandidate,
                       shouldPreferSpecificDateSourceAnchor(lhs: lhsCandidate, rhs: rhsCandidate, intent: intent) {
                        return sourceDateMatchesTemporalIntent(lhsCandidate.sortDate, intent: intent)
                    }
                    if let lhsCandidate,
                       let rhsCandidate,
                       shouldPreferGenericDateSourceAnchor(lhs: lhsCandidate, rhs: rhsCandidate, intent: intent) {
                        return sourceDateMatchesTemporalIntent(lhsCandidate.sortDate, intent: temporalIntent)
                    }
                    if let lhsCandidate,
                       let rhsCandidate,
                       shouldPreferLatestJournalSourceDateAnchor(lhs: lhsCandidate, rhs: rhsCandidate, intent: intent) {
                        return (lhsCandidate.sortDate ?? .distantPast) > (rhsCandidate.sortDate ?? .distantPast)
                    }
                    if let lhsCandidate,
                       let rhsCandidate,
                       shouldPreferTemporalRecency(lhs: lhsCandidate, rhs: rhsCandidate, intent: temporalIntent) {
                        return (lhsCandidate.sortDate ?? .distantPast) > (rhsCandidate.sortDate ?? .distantPast)
                    }
                }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.citation.title.localizedStandardCompare($1.citation.title) == .orderedDescending
            }
            .prefix(boundedLimit)
            .map(\.citation)
        let fallbackCommand = citations.isEmpty ? broaderSearchCommand(for: intent, limit: 10) : nil
        if let fallbackCommand {
            safeCommands.append(fallbackCommand)
        }
        var verificationCommands = orderedUnique(candidates.flatMap { candidate in
            candidate.provenance?.verificationCommands ?? candidate.safeNextCommands
        })
        if let fallbackCommand, verificationCommands.isEmpty {
            verificationCommands.append(fallbackCommand)
        }
        let answerExplanation = explanation(
            for: intent,
            candidates: candidates,
            fallbackCommand: fallbackCommand,
            mode: mode
        )
        let warnings = citations.isEmpty
            ? ["No source-backed item or chunk matches were found for this natural \(mode.noun) recall query."]
            : []
        return CiderNaturalPreferenceRecallResponse(
            ok: true,
            command: mode.command,
            readOnly: true,
            changed: false,
            intent: intent,
            summary: summary(for: intent, citations: citations, candidates: candidates, mode: mode),
            answerExplanation: answerExplanation,
            truthBoundary: "source_backed_observations_not_accepted_truth",
            reviewStatus: CiderNaturalPreferenceRecallReviewStatus(
                needsReview: false,
                copy: "Journaled/captured observations are cited source evidence. They were not promoted into accepted memory truth."
            ),
            searchPlan: searchPlan,
            candidates: candidates,
            citations: citations,
            rankingExplanation: rankingExplanation(for: intent, candidates: candidates, mode: mode),
            broaderSearchCommand: fallbackCommand,
            verificationCommands: verificationCommands,
            safeNextCommands: orderedUnique(safeCommands),
            warnings: warnings
        )
    }

    func interpret(_ rawQuery: String, mode: CiderNaturalRecallMode = .preference) -> CiderNaturalPreferenceRecallIntent {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = query.lowercased()
        let subject = extractSubject(from: query)
        let semanticTerms = semanticQueryTerms(for: normalized, mode: mode)
        let temporalDate = temporalDateAnchor(in: normalized, mode: mode)
        let eventPhrase = aroundEventPhrase(in: normalized)
        let eventResolution = eventPhrase.map { phrase in
            resolveAroundEvent(phrase: phrase.phrase, recognizedText: phrase.recognizedText)
        }
        let temporalRange = temporalRangeAnchor(
            in: normalized,
            originalQuery: query,
            mode: mode,
            eventResolution: eventResolution
        )
        let temporalIntent = temporalRange == nil
            ? temporalIntent(for: normalized, mode: mode, temporalDate: temporalDate)
            : "date_range"
        let factFamily = factFamily(for: normalized, semanticTerms: semanticTerms, mode: mode)
        let factTarget = factTarget(for: normalized, semanticTerms: semanticTerms, factFamily: factFamily, mode: mode)
        let kind: CiderNaturalPreferenceRecallQuestionKind
        if normalized.contains("eaten at") || normalized.contains("been to") || normalized.contains("before") {
            kind = .existence
        } else if normalized.contains("order") && normalized.contains("last") {
            kind = .lastOrder
        } else if normalized.contains("get again") || normalized.contains("ordering again") || normalized.contains("should i get") {
            kind = .repeatSuggestion
        } else if normalized.contains("liked lately") || normalized.contains("liked recently") {
            kind = .recentLiked
        } else if normalized.contains("like") || normalized.contains("liked") {
            kind = .liked
        } else {
            kind = .general
        }

        return CiderNaturalPreferenceRecallIntent(
            originalQuery: query,
            normalizedQuery: normalized,
            semanticQueryTerms: semanticTerms,
            questionKind: kind,
            temporalIntent: temporalIntent,
            temporalDate: temporalDate,
            temporalRange: temporalRange,
            eventResolution: eventResolution,
            factFamily: factFamily,
            factTarget: factTarget,
            subject: subject,
            searchQueries: searchQueries(subject: subject, kind: kind, normalizedQuery: normalized, semanticTerms: semanticTerms, temporalRange: temporalRange, mode: mode)
        )
    }

    private func searchQueries(
        subject: String?,
        kind: CiderNaturalPreferenceRecallQuestionKind,
        normalizedQuery: String,
        semanticTerms: [String],
        temporalRange: CiderNaturalPreferenceRecallTemporalRange?,
        mode: CiderNaturalRecallMode
    ) -> [String] {
        if mode == .memory {
            if let temporalRange {
                let remainingTerms = significantQueryTokens(in: temporalRange.remainingSemanticQuery)
                    .filter { !memoryRecallStopTokens.contains($0) }
                let focused = remainingTerms.joined(separator: " ")
                let dayAnchors = dailyJournalAnchorQueries(for: temporalRange)
                return orderedUnique(([focused].filter { !$0.isEmpty } + dayAnchors + ["Daily Journal"]))
            }
            let focused = semanticTerms.joined(separator: " ")
            let literal = significantQueryTokens(in: normalizedQuery).joined(separator: " ")
            let broad = broaderSearchTerms(for: semanticTerms).joined(separator: " ")
            let dateAnchor = genericExplicitDateAnchorSearchQuery(
                normalizedQuery: normalizedQuery,
                semanticTerms: semanticTerms,
                mode: mode
            )
            let specificDateAnchor = specificDateAnchorSearchQuery(normalizedQuery: normalizedQuery, mode: mode)
            let latestJournalAnchor = isLatestJournalSourceRecall(normalizedQuery: normalizedQuery, semanticTerms: semanticTerms)
                ? "Daily Journal"
                : nil
            return orderedUnique([specificDateAnchor, dateAnchor, latestJournalAnchor, focused, literal, broad, normalizedQuery].compactMap { $0 }.filter { !$0.isEmpty })
        }

        if let subject, !subject.isEmpty {
            switch kind {
            case .liked, .repeatSuggestion:
                return [subject, "\(subject) great", "\(subject) worth ordering again"]
            case .lastOrder:
                return [subject, "\(subject) order"]
            default:
                return [subject]
            }
        }

        if normalizedQuery.contains("food") {
            if containsSavedCandidateIntent(normalizedQuery) {
                return [normalizedQuery, "saved try lynnwood asian food", "saved place try food"]
            }
            return ["liked great worth ordering again food", "breakfast lunch dinner great liked"]
        }
        if kind == .repeatSuggestion {
            return ["worth ordering again food", "get it again liked food", "liked great restaurant cafeteria"]
        }
        return [normalizedQuery]
    }

    private func searchSort(
        for query: String,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> CiderItemSearchSort {
        if mode == .memory, isSpecificDateAnchorQuery(query, intent: intent) {
            return .relevance
        }
        if mode == .memory, isTemporalRangeAnchorQuery(query, intent: intent) {
            return .relevance
        }
        return .newest
    }

    private func searchLimit(
        for query: String,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode,
        requestedLimit: Int
    ) -> Int {
        if mode == .memory, isSpecificDateAnchorQuery(query, intent: intent) {
            return max(requestedLimit, 25)
        }
        if mode == .memory, isTemporalRangeAnchorQuery(query, intent: intent) {
            return max(requestedLimit, 25)
        }
        return requestedLimit
    }

    private func isSpecificDateAnchorQuery(_ query: String, intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        guard let temporalDate = intent.temporalDate else { return false }
        return query == "Daily Journal \(temporalDate)"
    }

    private func isTemporalRangeAnchorQuery(_ query: String, intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        guard let temporalRange = intent.temporalRange else { return false }
        return query == "Daily Journal"
            || query.hasPrefix("Daily Journal ")
            || query == temporalRange.remainingSemanticQuery
    }

    private func semanticQueryTerms(for normalizedQuery: String, mode: CiderNaturalRecallMode) -> [String] {
        guard mode == .memory else {
            return significantQueryTokens(in: normalizedQuery)
        }
        var terms = significantQueryTokens(in: normalizedQuery)
            .filter { !memoryRecallStopTokens.contains($0) }
        if normalizedQuery.contains("coverall") {
            terms.append(contentsOf: ["coveralls", "work", "size", "fit", "clothing", "regular", "rg"])
            if normalizedQuery.contains("height") || normalizedQuery.contains("foot") || normalizedQuery.contains("6") {
                terms.append(contentsOf: ["6'3", "60-rg", "60", "red", "kap"])
            }
        }
        let asksSizeOrFit = normalizedQuery.contains("size") || normalizedQuery.contains("fit") || normalizedQuery.contains("fits")
        if (asksSizeOrFit && (normalizedQuery.contains("boot") || normalizedQuery.contains("shoe")))
            || normalizedQuery.contains("clothing")
            || normalizedQuery.contains("shirt")
            || normalizedQuery.contains("pants") {
            terms.append(contentsOf: ["clothing", "size", "fit"])
            if normalizedQuery.contains("boot") {
                terms.append(contentsOf: ["boot", "boots", "wide", "workshop"])
            }
        }
        let asksToolPreference = normalizedQuery.contains("prefer") || normalizedQuery.contains("preferred") || normalizedQuery.contains("kit") || normalizedQuery.contains("gadget") || normalizedQuery.contains("screwdriver")
        if asksToolPreference {
            terms.append(contentsOf: ["tool", "gadget", "preferred", "prefer", "kit"])
            if normalizedQuery.contains("screwdriver") {
                terms.append(contentsOf: ["screwdriver", "wera", "bits", "desk"])
            }
        }
        if normalizedQuery.contains("dental") || normalizedQuery.contains("toothpaste") || normalizedQuery.contains("medication") || normalizedQuery.contains("medicine") || normalizedQuery.contains("care") {
            terms.append(contentsOf: ["health", "care", "note"])
            if normalizedQuery.contains("dental") || normalizedQuery.contains("toothpaste") {
                terms.append(contentsOf: ["dental", "toothpaste", "sensitive", "flossing"])
            }
        }
        if normalizedQuery.contains("gas") || normalizedQuery.contains("fuel") || normalizedQuery.contains("fill-up") || normalizedQuery.contains("fill up") {
            terms.append(contentsOf: ["gas", "fuel", "fill-up", "spending", "total", "gallons", "price", "cost"])
            if normalizedQuery.contains("pay") || normalizedQuery.contains("paid") || normalizedQuery.contains("much") {
                terms.append(contentsOf: ["paid", "amount"])
            }
        }
        if normalizedQuery.contains("shift")
            || normalizedQuery.contains("schedule")
            || ((normalizedQuery.contains("pay") || normalizedQuery.contains("paid")) && containsWorkContext(normalizedQuery)) {
            terms.append(contentsOf: ["work", "schedule"])
            if normalizedQuery.contains("shift") {
                terms.append(contentsOf: ["shift", "night"])
            }
            if normalizedQuery.contains("pay") {
                terms.append("pay")
            }
        }
        return orderedUnique(terms)
    }

    private var memoryRecallStopTokens: Set<String> {
        [
            "about", "being", "happen", "happened", "remember", "recall", "saved", "save",
            "note", "notes", "someone", "thing", "things",
        ]
    }

    private var genericMemoryRecallTokens: Set<String> {
        [
            "ask", "asked", "capture", "captured", "did", "journal", "journaled", "log", "logged",
            "in", "mention", "mentioned", "note", "notes", "recall", "remember", "said", "say", "saying",
            "tell", "thing", "things", "voice",
        ]
    }

    private var explicitDateTokens: Set<String> {
        ["today", "yesterday"]
    }

    private func temporalRangeAnchor(
        in normalizedQuery: String,
        originalQuery: String,
        mode: CiderNaturalRecallMode,
        eventResolution: CiderNaturalPreferenceRecallEventResolution?
    ) -> CiderNaturalPreferenceRecallTemporalRange? {
        guard mode == .memory else { return nil }
        let calendar = Self.recallCalendar
        let reference = referenceDate()
        let today = calendar.startOfDay(for: reference)
        let currentWeekStart = weekStart(containing: today, calendar: calendar)

        if normalizedQuery.contains("last week"),
           let start = calendar.date(byAdding: .day, value: -7, to: currentWeekStart),
           let end = calendar.date(byAdding: .day, value: 6, to: start) {
            return makeTemporalRange(
                originalQuery: originalQuery,
                normalizedQuery: normalizedQuery,
                recognizedText: "last week",
                rangeType: "last_week",
                start: start,
                end: end,
                source: "deterministic_calendar"
            )
        }

        if normalizedQuery.contains("this week"),
           let end = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) {
            return makeTemporalRange(
                originalQuery: originalQuery,
                normalizedQuery: normalizedQuery,
                recognizedText: "this week",
                rangeType: "this_week",
                start: currentWeekStart,
                end: end,
                source: "deterministic_calendar"
            )
        }

        if normalizedQuery.contains("last month"),
           let previousMonth = calendar.date(byAdding: .month, value: -1, to: today),
           let interval = calendar.dateInterval(of: .month, for: previousMonth),
           let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
            return makeTemporalRange(
                originalQuery: originalQuery,
                normalizedQuery: normalizedQuery,
                recognizedText: "last month",
                rangeType: "last_month",
                start: interval.start,
                end: end,
                source: "deterministic_calendar"
            )
        }

        if normalizedQuery.contains("this month"),
           let interval = calendar.dateInterval(of: .month, for: today),
           let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
            return makeTemporalRange(
                originalQuery: originalQuery,
                normalizedQuery: normalizedQuery,
                recognizedText: "this month",
                rangeType: "this_month",
                start: interval.start,
                end: end,
                source: "deterministic_calendar"
            )
        }

        if let monthRange = namedMonthRange(in: normalizedQuery, originalQuery: originalQuery, referenceDate: reference) {
            return monthRange
        }

        return aroundRange(in: normalizedQuery, originalQuery: originalQuery, eventResolution: eventResolution)
    }

    private func namedMonthRange(
        in normalizedQuery: String,
        originalQuery: String,
        referenceDate: Date
    ) -> CiderNaturalPreferenceRecallTemporalRange? {
        let monthPattern = Self.monthNameToNumber.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: #"\bin\s+("# + monthPattern + #")(?:\s+(20\d{2}))?\b"#),
              let match = regex.firstMatch(in: normalizedQuery, range: NSRange(normalizedQuery.startIndex..., in: normalizedQuery)),
              let monthRange = Range(match.range(at: 1), in: normalizedQuery),
              let month = Self.monthNameToNumber[String(normalizedQuery[monthRange])]
        else {
            return nil
        }
        let year: Int
        if match.range(at: 2).location != NSNotFound,
           let yearRange = Range(match.range(at: 2), in: normalizedQuery),
           let parsedYear = Int(normalizedQuery[yearRange]) {
            year = parsedYear
        } else {
            year = Self.recallCalendar.component(.year, from: referenceDate)
        }
        var components = DateComponents()
        components.calendar = Self.recallCalendar
        components.year = year
        components.month = month
        components.day = 1
        guard let start = components.date,
              let interval = Self.recallCalendar.dateInterval(of: .month, for: start),
              let end = Self.recallCalendar.date(byAdding: .day, value: -1, to: interval.end),
              let recognizedRange = Range(match.range, in: normalizedQuery)
        else {
            return nil
        }
        return makeTemporalRange(
            originalQuery: originalQuery,
            normalizedQuery: normalizedQuery,
            recognizedText: String(normalizedQuery[recognizedRange]),
            rangeType: "month_name",
            start: start,
            end: end,
            source: "deterministic_calendar"
        )
    }

    private func aroundRange(
        in normalizedQuery: String,
        originalQuery: String,
        eventResolution: CiderNaturalPreferenceRecallEventResolution?
    ) -> CiderNaturalPreferenceRecallTemporalRange? {
        guard let phraseMatch = aroundEventPhrase(in: normalizedQuery)
        else {
            return nil
        }
        let phrase = phraseMatch.phrase
        let anchorDateString = specificDateAnchor(in: phrase) ?? knownEventDates[phrase] ?? eventResolution?.resolvedDate
        guard let anchorDateString,
              let anchorDate = Self.localDayFormatter.date(from: anchorDateString),
              let start = Self.recallCalendar.date(byAdding: .day, value: -3, to: anchorDate),
              let end = Self.recallCalendar.date(byAdding: .day, value: 3, to: anchorDate)
        else {
            return nil
        }
        return makeTemporalRange(
            originalQuery: originalQuery,
            normalizedQuery: normalizedQuery,
            recognizedText: phraseMatch.recognizedText,
            rangeType: specificDateAnchor(in: phrase) == anchorDateString ? "around_date" : "around_event",
            start: start,
            end: end,
            source: aroundRangeSource(phrase: phrase, anchorDateString: anchorDateString, eventResolution: eventResolution),
            remainingOverride: phrase.replacingOccurrences(of: "'", with: " "),
            eventResolution: eventResolution?.resolvedDate == anchorDateString ? eventResolution : nil
        )
    }

    private func aroundEventPhrase(in normalizedQuery: String) -> (phrase: String, recognizedText: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"\baround\s+(.+?)(?:\?|$)"#),
              let match = regex.firstMatch(in: normalizedQuery, range: NSRange(normalizedQuery.startIndex..., in: normalizedQuery)),
              let phraseRange = Range(match.range(at: 1), in: normalizedQuery),
              let fullRange = Range(match.range, in: normalizedQuery)
        else {
            return nil
        }
        let phrase = String(normalizedQuery[phraseRange])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let recognizedText = String(normalizedQuery[fullRange])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !phrase.isEmpty else { return nil }
        return (phrase, recognizedText)
    }

    private func aroundRangeSource(
        phrase: String,
        anchorDateString: String,
        eventResolution: CiderNaturalPreferenceRecallEventResolution?
    ) -> String {
        if specificDateAnchor(in: phrase) == anchorDateString {
            return "deterministic_date_parse"
        }
        if knownEventDates[phrase] == anchorDateString {
            return "known_event"
        }
        if eventResolution?.resolvedDate == anchorDateString {
            return "source_backed_event_observation"
        }
        return "unknown"
    }

    private func resolveAroundEvent(
        phrase: String,
        recognizedText: String
    ) -> CiderNaturalPreferenceRecallEventResolution {
        let cleanedPhrase = phrase.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let searchQuery = cleanedPhrase.replacingOccurrences(of: "'", with: " ")
        let fallbackCommands = [
            "cider-cli item search \"\(escapedCommandArgument(searchQuery))\" --scope personalMemory --sort newest --limit 10 --json",
            "cider-cli item search-debug \"\(escapedCommandArgument(searchQuery))\" --json",
        ]
        guard !searchQuery.isEmpty else {
            return CiderNaturalPreferenceRecallEventResolution(
                eventQuery: cleanedPhrase,
                recognizedText: recognizedText,
                resolvedDate: nil,
                confidence: "unresolved",
                sourceKind: "unresolved",
                truthBoundary: "no_event_date_invented",
                fallbackReason: "empty_event_query",
                sources: [],
                safeNextCommands: fallbackCommands
            )
        }

        let results = (try? contextService.search(searchQuery, limit: 12, scope: .personalMemory, sort: .newest)) ?? []
        let phraseTokens = significantQueryTokens(in: searchQuery)
            .filter { !genericMemoryRecallTokens.contains($0) && $0 != "around" }
        var candidates = normalizedEventDateAliasCandidates(cleanedPhrase: cleanedPhrase, phraseTokens: phraseTokens)
        for result in results {
            guard let item = result.item else { continue }
            let bundle = try? contextService.context(for: LibraryEntityRef(type: item.type, entityID: item.id))
            let searchable = ((bundle?.chunks.map(\.body) ?? []) + (bundle?.sections.map(\.body) ?? []) + [result.title, result.snippet, item.title])
                .joined(separator: "\n")
            let lowerSearchable = searchable.lowercased()
            guard eventEvidenceMatches(phraseTokens: phraseTokens, searchable: lowerSearchable) else { continue }
            guard let resolved = eventEvidenceDate(searchable: searchable, bundle: bundle, result: result) else { continue }
            let sourceRef = "\(item.type.rawValue):\(item.id.uuidString)"
            let commands = [
                "cider-cli item context \(item.type.rawValue) \(item.id.uuidString) --json",
                "cider-cli item get \(item.type.rawValue) \(item.id.uuidString) --json",
            ]
            let source = CiderNaturalPreferenceRecallEventResolutionSource(
                sourceRef: sourceRef,
                sourceType: item.type.rawValue,
                sourceID: item.id.uuidString,
                title: item.title,
                sourceKind: resolved.sourceKind,
                dateSource: resolved.dateSource,
                evidence: eventEvidenceExcerpt(from: searchable, phraseTokens: phraseTokens),
                safeNextCommands: commands
            )
            candidates.append((resolved.date, source, eventResolutionScore(sourceKind: resolved.sourceKind, dateSource: resolved.dateSource, phraseTokens: phraseTokens, searchable: lowerSearchable)))
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.date > rhs.date
        }).first else {
            return CiderNaturalPreferenceRecallEventResolution(
                eventQuery: cleanedPhrase,
                recognizedText: recognizedText,
                resolvedDate: nil,
                confidence: "unresolved",
                sourceKind: "unresolved",
                truthBoundary: "no_event_date_invented",
                fallbackReason: "no_source_backed_event_date_found",
                sources: [],
                safeNextCommands: fallbackCommands
            )
        }

        let matchingSources = candidates
            .filter { Self.localDayFormatter.string(from: $0.date) == Self.localDayFormatter.string(from: best.date) }
            .sorted { $0.score > $1.score }
            .map(\.source)
        var seenSourceKeys: Set<String> = []
        let uniqueMatchingSources = matchingSources.reduce(into: [CiderNaturalPreferenceRecallEventResolutionSource]()) { partial, source in
            let key = "\(source.sourceRef)|\(source.sourceKind)|\(source.dateSource)"
            if seenSourceKeys.insert(key).inserted {
                partial.append(source)
            }
        }
        return CiderNaturalPreferenceRecallEventResolution(
            eventQuery: cleanedPhrase,
            recognizedText: recognizedText,
            resolvedDate: Self.localDayFormatter.string(from: best.date),
            confidence: eventResolutionConfidence(sourceKind: best.source.sourceKind),
            sourceKind: best.source.sourceKind,
            truthBoundary: eventResolutionTruthBoundary(sourceKind: best.source.sourceKind),
            fallbackReason: nil,
            sources: Array(uniqueMatchingSources.prefix(3)),
            safeNextCommands: orderedUnique(fallbackCommands + uniqueMatchingSources.flatMap(\.safeNextCommands))
        )
    }

    private func eventResolutionConfidence(sourceKind: String) -> String {
        switch sourceKind {
        case "accepted_event_date":
            return "accepted_event_date"
        case "contact_birthday":
            return "contact_birthday"
        default:
            return "source_backed_observation"
        }
    }

    private func eventResolutionTruthBoundary(sourceKind: String) -> String {
        switch sourceKind {
        case "accepted_event_date":
            return "accepted_event_date_item"
        case "contact_birthday":
            return "accepted_contact_birthday"
        default:
            return "source_backed_observation_not_accepted_memory_truth"
        }
    }

    private func eventEvidenceMatches(phraseTokens: [String], searchable: String) -> Bool {
        guard !phraseTokens.isEmpty else { return false }
        let required = min(2, phraseTokens.count)
        let overlap = phraseTokens.filter { searchable.contains($0) }.count
        return overlap >= required
    }

    private func eventEvidenceDate(
        searchable: String,
        bundle: CiderItemContextBundle?,
        result: CiderItemSearchResult
    ) -> (date: Date, sourceKind: String, dateSource: String)? {
        let lower = searchable.lowercased()
        if let normalized = normalizedEventDateFact(result: result, searchable: lower) {
            return normalized
        }
        if result.item?.type == .dateCard {
            if let dateString = specificDateAnchor(in: lower),
               let date = Self.localDayFormatter.date(from: dateString) {
                return (date, "accepted_event_date", "event_indexed_date")
            }
        }
        if lower.contains("today") || lower.contains("birthday") || lower.contains("event") {
            if let bundle {
                return (sourceSortDate(bundle: bundle, result: result), "journal_observation", "source_date")
            }
            if let item = result.item {
                return (max(item.updatedAt, item.createdAt), "item_observation", "item_timestamp")
            }
        }
        if let explicitDate = specificDateAnchor(in: lower),
           let date = Self.localDayFormatter.date(from: explicitDate) {
            return (date, "journal_observation", "explicit_date_in_source")
        }
        return nil
    }

    private func normalizedEventDateAliasCandidates(
        cleanedPhrase: String,
        phraseTokens: [String]
    ) -> [(date: Date, source: CiderNaturalPreferenceRecallEventResolutionSource, score: Int)] {
        guard !phraseTokens.isEmpty else { return [] }
        return normalizedDateCardAliasCandidates(phraseTokens: phraseTokens)
            + normalizedContactBirthdayAliasCandidates(cleanedPhrase: cleanedPhrase, phraseTokens: phraseTokens)
    }

    private func normalizedDateCardAliasCandidates(
        phraseTokens: [String]
    ) -> [(date: Date, source: CiderNaturalPreferenceRecallEventResolutionSource, score: Int)] {
        do {
            let stmt = try database.prepare("""
                SELECT i.id, i.title, e.start_at
                FROM events e
                JOIN items i ON i.id = e.item_id
                WHERE i.type = 'event' AND e.start_at IS NOT NULL
                ORDER BY e.start_at DESC
                LIMIT 200;
                """)
            var candidates: [(date: Date, source: CiderNaturalPreferenceRecallEventResolutionSource, score: Int)] = []
            while try stmt.step() {
                guard let itemID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let title = stmt.string(at: 1)
                let aliasText = normalizedEventAliasSurface(title)
                guard eventAliasMatches(phraseTokens: phraseTokens, aliasText: aliasText) else { continue }
                let date = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let sourceRef = "dateCard:\(itemID.uuidString)"
                let commands = [
                    "cider-cli item context dateCard \(itemID.uuidString) --json",
                    "cider-cli item get dateCard \(itemID.uuidString) --json",
                ]
                let source = CiderNaturalPreferenceRecallEventResolutionSource(
                    sourceRef: sourceRef,
                    sourceType: "dateCard",
                    sourceID: itemID.uuidString,
                    title: title,
                    sourceKind: "accepted_event_date",
                    dateSource: "events.start_at",
                    evidence: title,
                    safeNextCommands: commands
                )
                candidates.append((date, source, eventAliasScore(sourceKind: "accepted_event_date", phraseTokens: phraseTokens, aliasText: aliasText)))
            }
            return candidates
        } catch {
            return []
        }
    }

    private func normalizedContactBirthdayAliasCandidates(
        cleanedPhrase: String,
        phraseTokens: [String]
    ) -> [(date: Date, source: CiderNaturalPreferenceRecallEventResolutionSource, score: Int)] {
        guard phraseTokens.contains("birthday") else { return [] }
        do {
            let stmt = try database.prepare("""
                SELECT i.id, i.title, c.birthday
                FROM contacts c
                JOIN items i ON i.id = c.item_id
                WHERE i.type = 'contact' AND c.birthday IS NOT NULL
                ORDER BY c.birthday DESC
                LIMIT 200;
                """)
            var candidates: [(date: Date, source: CiderNaturalPreferenceRecallEventResolutionSource, score: Int)] = []
            while try stmt.step() {
                guard let itemID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let title = stmt.string(at: 1)
                let aliasText = normalizedBirthdayAliasSurface(for: title)
                guard eventAliasMatches(phraseTokens: phraseTokens, aliasText: aliasText) else { continue }
                let date = DatabaseHelpers.decodeDate(stmt.double(at: 2))
                let sourceRef = "contact:\(itemID.uuidString)"
                let commands = [
                    "cider-cli item context contact \(itemID.uuidString) --json",
                    "cider-cli item get contact \(itemID.uuidString) --json",
                ]
                let source = CiderNaturalPreferenceRecallEventResolutionSource(
                    sourceRef: sourceRef,
                    sourceType: "contact",
                    sourceID: itemID.uuidString,
                    title: title,
                    sourceKind: "contact_birthday",
                    dateSource: "contacts.birthday",
                    evidence: "\(title) birthday",
                    safeNextCommands: commands
                )
                candidates.append((date, source, eventAliasScore(sourceKind: "contact_birthday", phraseTokens: phraseTokens, aliasText: aliasText)))
            }
            return candidates
        } catch {
            return []
        }
    }

    private func normalizedEventAliasSurface(_ title: String) -> String {
        let aliases = title.lowercased().contains("birthday")
            ? birthdayAliases(for: title)
            : [title]
        return normalizedAliasText(orderedUnique(aliases).joined(separator: " "))
    }

    private func normalizedBirthdayAliasSurface(for name: String) -> String {
        normalizedAliasText(birthdayAliases(for: name).joined(separator: " "))
    }

    private func birthdayAliases(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return [] }
        let unpossessed = trimmed.replacingOccurrences(of: #"'s\b"#, with: "", options: .regularExpression)
        let base = unpossessed.lowercased().contains("birthday") ? unpossessed : "\(unpossessed) birthday"
        return orderedUnique([
            trimmed,
            base,
            "\(unpossessed)'s birthday",
            "birthday for \(unpossessed)",
            "\(unpossessed) bday",
        ])
    }

    private func normalizedAliasText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"'s\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9-]+"#, with: " ", options: .regularExpression)
    }

    private func eventAliasMatches(phraseTokens: [String], aliasText: String) -> Bool {
        let aliasTokens = Set(significantQueryTokens(in: aliasText))
        let requiredTokens = phraseTokens.filter { $0 != "birthday" && $0 != "bday" }
        guard !requiredTokens.isEmpty else { return false }
        return requiredTokens.allSatisfy { aliasTokens.contains($0) }
            && (!phraseTokens.contains("birthday") || aliasTokens.contains("birthday") || aliasTokens.contains("bday"))
    }

    private func eventAliasScore(sourceKind: String, phraseTokens: [String], aliasText: String) -> Int {
        var total = phraseTokens.filter { aliasText.contains($0) }.count * 8
        if sourceKind == "accepted_event_date" { total += 40 }
        if sourceKind == "contact_birthday" { total += 38 }
        if aliasText.contains("birthday") { total += 6 }
        return total
    }

    private func normalizedEventDateFact(
        result: CiderItemSearchResult,
        searchable: String
    ) -> (date: Date, sourceKind: String, dateSource: String)? {
        guard let item = result.item else { return nil }
        switch item.type {
        case .dateCard:
            guard let startAt = normalizedDateCardStartDate(itemID: item.id) else { return nil }
            return (startAt, "accepted_event_date", "events.start_at")
        case .contact:
            guard searchable.contains("birthday"),
                  let birthday = normalizedContactBirthday(itemID: item.id)
            else { return nil }
            return (birthday, "contact_birthday", "contacts.birthday")
        default:
            return nil
        }
    }

    private func normalizedDateCardStartDate(itemID: UUID) -> Date? {
        do {
            let stmt = try database.prepare("""
                SELECT e.start_at
                FROM events e
                JOIN items i ON i.id = e.item_id
                WHERE e.item_id = ? AND i.type = 'event'
                LIMIT 1;
                """)
            stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
            guard try stmt.step() else { return nil }
            return DatabaseHelpers.decodeDate(stmt.double(at: 0))
        } catch {
            return nil
        }
    }

    private func normalizedContactBirthday(itemID: UUID) -> Date? {
        do {
            let stmt = try database.prepare("""
                SELECT c.birthday
                FROM contacts c
                JOIN items i ON i.id = c.item_id
                WHERE c.item_id = ? AND i.type = 'contact' AND c.birthday IS NOT NULL
                LIMIT 1;
                """)
            stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
            guard try stmt.step(),
                  let rawBirthday = stmt.optionalDouble(at: 0)
            else { return nil }
            return DatabaseHelpers.decodeDate(rawBirthday)
        } catch {
            return nil
        }
    }

    private func eventResolutionScore(
        sourceKind: String,
        dateSource: String,
        phraseTokens: [String],
        searchable: String
    ) -> Int {
        var total = phraseTokens.filter { searchable.contains($0) }.count * 5
        if sourceKind == "accepted_event_date" { total += 20 }
        if sourceKind == "contact_birthday" { total += 18 }
        if dateSource == "source_date" { total += 8 }
        if dateSource == "events.start_at" || dateSource == "contacts.birthday" { total += 10 }
        if searchable.contains("today is") { total += 4 }
        if searchable.contains("birthday") { total += 3 }
        return total
    }

    private func eventEvidenceExcerpt(from searchable: String, phraseTokens: [String]) -> String {
        let lines = searchable
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let matched = lines.first(where: { line in
            let lower = line.lowercased()
            return phraseTokens.allSatisfy { lower.contains($0) }
        }) {
            return clipped(matched, limit: 240)
        }
        if let matched = lines.first(where: { line in
            let lower = line.lowercased()
            return phraseTokens.contains { lower.contains($0) }
        }) {
            return clipped(matched, limit: 240)
        }
        return clipped(searchable.trimmingCharacters(in: .whitespacesAndNewlines), limit: 240)
    }

    private func makeTemporalRange(
        originalQuery: String,
        normalizedQuery: String,
        recognizedText: String,
        rangeType: String,
        start: Date,
        end: Date,
        source: String,
        remainingOverride: String? = nil,
        eventResolution: CiderNaturalPreferenceRecallEventResolution? = nil
    ) -> CiderNaturalPreferenceRecallTemporalRange {
        let startDate = Self.localDayFormatter.string(from: start)
        let endDate = Self.localDayFormatter.string(from: end)
        let remaining = cleanedRemainingSemanticQuery(
            normalizedQuery: normalizedQuery,
            recognizedText: recognizedText,
            override: remainingOverride
        )
        return CiderNaturalPreferenceRecallTemporalRange(
            originalQuery: originalQuery,
            recognizedText: recognizedText,
            rangeType: rangeType,
            startDate: startDate,
            endDate: endDate,
            source: source,
            remainingSemanticQuery: remaining,
            safeNextCommands: temporalRangeSafeNextCommands(
                rangeType: rangeType,
                startDate: startDate,
                endDate: endDate,
                remainingSemanticQuery: remaining
            ),
            eventResolution: eventResolution
        )
    }

    private func cleanedRemainingSemanticQuery(
        normalizedQuery: String,
        recognizedText: String,
        override: String? = nil
    ) -> String {
        let source = override ?? normalizedQuery.replacingOccurrences(of: recognizedText, with: " ")
        let drop: Set<String> = [
            "about", "did", "going", "happen", "happened", "i", "journal", "journaled",
            "like", "on", "say", "the", "there", "things", "was", "what", "were",
        ]
        return orderedUnique(
            source
                .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
                .map(String.init)
                .map { $0 == "ryland's" ? "ryland" : $0 }
                .filter { $0.count > 1 && !drop.contains($0) && !memoryRecallStopTokens.contains($0) }
        )
        .joined(separator: " ")
    }

    private func temporalRangeSafeNextCommands(
        rangeType: String,
        startDate: String,
        endDate: String,
        remainingSemanticQuery: String
    ) -> [String] {
        var commands: [String] = []
        if rangeType.contains("week") || rangeType == "around_date" || rangeType == "around_event" {
            commands.append("cider-cli item weekly-chapter --week \(startDate) --json")
        }
        if rangeType.contains("month") {
            commands.append("cider-cli item monthly-chapter --month \(String(startDate.prefix(7))) --json")
        }
        var tracker = "cider-cli item daily-tracker --from \(startDate) --to \(endDate)"
        if !remainingSemanticQuery.isEmpty {
            tracker += " --query \"\(escapedCommandArgument(remainingSemanticQuery))\""
        }
        tracker += " --sort oldest --limit 5 --json"
        commands.append(tracker)
        return orderedUnique(commands)
    }

    private func dailyJournalAnchorQueries(for range: CiderNaturalPreferenceRecallTemporalRange) -> [String] {
        guard let start = Self.localDayFormatter.date(from: range.startDate),
              let end = Self.localDayFormatter.date(from: range.endDate)
        else {
            return []
        }
        var queries: [String] = []
        var date = start
        while date <= end && queries.count < 31 {
            queries.append("Daily Journal \(Self.localDayFormatter.string(from: date))")
            guard let next = Self.recallCalendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return queries
    }

    private func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let distanceFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -distanceFromMonday, to: startOfDay) ?? startOfDay
    }

    private func temporalIntent(for normalizedQuery: String, mode: CiderNaturalRecallMode, temporalDate: String? = nil) -> String? {
        guard mode == .memory else { return nil }
        let tokens = Set(significantQueryTokens(in: normalizedQuery))
        if tokens.contains("today") || normalizedQuery.contains("right now") {
            return "today"
        }
        if tokens.contains("yesterday") {
            return "yesterday"
        }
        if temporalDate != nil || normalizedQuery.range(of: #"\b20\d{2}-\d{2}-\d{2}\b"#, options: .regularExpression) != nil {
            return "specific_date"
        }
        if tokens.contains("latest") || tokens.contains("newest") || tokens.contains("recent") || normalizedQuery.contains("most recent") {
            return "latest"
        }
        return nil
    }

    private func genericExplicitDateAnchorSearchQuery(
        normalizedQuery: String,
        semanticTerms: [String],
        mode: CiderNaturalRecallMode
    ) -> String? {
        guard mode == .memory,
              isGenericExplicitDateRecall(normalizedQuery: normalizedQuery, semanticTerms: semanticTerms),
              let intent = temporalIntent(for: normalizedQuery, mode: mode),
              ["today", "yesterday"].contains(intent),
              let date = temporalDateAnchor(in: normalizedQuery, mode: mode)
        else {
            return nil
        }
        return "Daily Journal \(date)"
    }

    private func specificDateAnchorSearchQuery(normalizedQuery: String, mode: CiderNaturalRecallMode) -> String? {
        guard mode == .memory,
              let date = temporalDateAnchor(in: normalizedQuery, mode: mode),
              temporalIntent(for: normalizedQuery, mode: mode, temporalDate: date) == "specific_date"
        else {
            return nil
        }
        return "Daily Journal \(date)"
    }

    private func factFamily(for normalizedQuery: String, semanticTerms: [String], mode: CiderNaturalRecallMode) -> String? {
        guard mode == .memory else { return nil }
        if semanticTerms.contains("schedule")
            || semanticTerms.contains("shift")
            || ((semanticTerms.contains("pay") || semanticTerms.contains("paid")) && containsWorkContext(normalizedQuery)) {
            return "work_schedule_fact"
        }
        if semanticTerms.contains("gas")
            || semanticTerms.contains("fuel")
            || semanticTerms.contains("gallons") {
            return "spending_fact"
        }
        let asksClothingSizeOrFit = normalizedQuery.contains("size")
            || normalizedQuery.contains("fit")
            || normalizedQuery.contains("fits")
        if normalizedQuery.contains("coverall")
            || semanticTerms.contains("clothing")
            || (asksClothingSizeOrFit && (semanticTerms.contains("boot") || semanticTerms.contains("boots") || semanticTerms.contains("shoe"))) {
            return "clothing_size_fit"
        }
        if semanticTerms.contains("screwdriver")
            || (semanticTerms.contains("tool") && (semanticTerms.contains("prefer") || semanticTerms.contains("preferred") || semanticTerms.contains("kit"))) {
            return "tool_gadget_preference"
        }
        if semanticTerms.contains("dental")
            || semanticTerms.contains("toothpaste")
            || semanticTerms.contains("medication")
            || semanticTerms.contains("medicine") {
            return "health_care_note"
        }
        return nil
    }

    private func containsWorkContext(_ normalizedQuery: String) -> Bool {
        normalizedQuery.contains("work")
            || normalizedQuery.contains("shift")
            || normalizedQuery.contains("schedule")
            || normalizedQuery.contains("boeing")
            || normalizedQuery.contains("overtime")
    }

    private func factTarget(
        for normalizedQuery: String,
        semanticTerms: [String],
        factFamily: String?,
        mode: CiderNaturalRecallMode
    ) -> String? {
        guard mode == .memory else { return nil }
        if normalizedQuery.contains("coverall") && semanticTerms.contains("work") {
            return "work_coveralls_size"
        }
        if factFamily == "clothing_size_fit", semanticTerms.contains("boot"), semanticTerms.contains("workshop") {
            return "workshop_boot_size"
        }
        if factFamily == "tool_gadget_preference", semanticTerms.contains("screwdriver"), semanticTerms.contains("desk") {
            return "desk_screwdriver_kit_preference"
        }
        if factFamily == "health_care_note", semanticTerms.contains("dental"), semanticTerms.contains("toothpaste") {
            return "dental_toothpaste_care_note"
        }
        if normalizedQuery.contains("locker") && normalizedQuery.contains("code") {
            return "work_locker_code"
        }
        return nil
    }

    private func broaderSearchTerms(for semanticTerms: [String]) -> [String] {
        semanticTerms.filter {
            !["size", "fit", "clothing", "regular", "rg", "red", "kap", "60", "60-rg"].contains($0)
                && !genericMemoryRecallTokens.contains($0)
        }
    }

    private func extractSubject(from query: String) -> String? {
        let patterns = [
            #"(?i)\bat\s+(.+?)(?:\s+before|\s+last\s+time|\?|$)"#,
            #"(?i)\bfrom\s+(.+?)(?:\s+i['’]?ve|\s+we['’]?ve|\?|$)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: query) else {
                continue
            }
            let candidate = String(query[range])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if candidate.count >= 2 && !isGenericSubject(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isGenericSubject(_ candidate: String) -> Bool {
        let normalized = candidate.lowercased()
        return ["place", "places", "restaurant", "restaurants", "somewhere"].contains(normalized)
            || normalized.contains("journaled about")
    }

    private func bestQuote(
        in bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> String {
        let candidates = bundle.chunks.map(\.body) + bundle.sections.map(\.body) + [result.snippet]
        let tokens = evidenceTokens(for: intent, mode: mode)
        let scored = candidates
            .map { quoteLines(from: $0, tokens: tokens, intent: intent) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in score(lhs, tokens: tokens) > score(rhs, tokens: tokens) }
        return scored.first.map { clipped($0, limit: 700) } ?? ""
    }

    private func qualifies(
        quote: String,
        bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> Bool {
        let quoteText = quote.lowercased()
        let searchable = ([quote, result.title, result.snippet, bundle.item.title] + bundle.chunks.map(\.body))
            .joined(separator: "\n")
            .lowercased()
        if mode == .memory {
            if let temporalRange = intent.temporalRange,
               sourceDateMatchesTemporalRange(sourceSortDate(bundle: bundle, result: result), range: temporalRange) {
                let nonRangeTerms = nonRangeSemanticTerms(for: intent)
                if nonRangeTerms.isEmpty {
                    return true
                }
                if intent.factFamily == "spending_fact",
                   nonRangeTerms.contains("gas") || nonRangeTerms.contains("fuel") {
                    return containsGasSpendingSignal(searchable)
                        || searchable.contains("gas station")
                        || searchable.contains("gallon")
                }
                return nonRangeTerms.contains { searchable.contains($0) }
            }
            if isGenericExplicitDateRecall(intent: intent),
               sourceDateMatchesTemporalIntent(sourceSortDate(bundle: bundle, result: result), intent: intent.temporalIntent) {
                return true
            }
            if isSpecificDateSourceRecall(intent: intent),
               sourceDateMatchesTemporalIntent(sourceSortDate(bundle: bundle, result: result), intent: intent) {
                return true
            }
            if isLatestJournalSourceRecall(intent: intent),
               isDailyJournalSource(bundle: bundle, result: result) {
                return true
            }
            let tokens = intent.semanticQueryTerms
            let overlap = tokens.filter { searchable.contains($0) }.count
            return overlap >= min(2, max(1, tokens.count))
        }

        if let subject = intent.subject?.lowercased(), !subject.isEmpty {
            return quoteText.contains(subject) || searchable.contains(subject)
        }
        if intent.normalizedQuery.contains("food") {
            return containsFoodSignal(quoteText) && (containsPreferenceSignal(quoteText) || containsSavedCandidateSignal(searchable))
        }
        if intent.questionKind == .repeatSuggestion {
            return containsFoodSignal(quoteText) && (containsPreferenceSignal(quoteText) || containsSavedCandidateSignal(searchable))
        }
        return containsPreferenceSignal(quoteText)
    }

    private func evidenceScore(
        quote: String,
        bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> Int {
        var total = score(quote, tokens: evidenceTokens(for: intent, mode: mode))
        let lower = quote.lowercased()
        if mode == .memory {
            let tokens = intent.semanticQueryTerms
            total = tokens.filter { lower.contains($0) }.count * 4
            if result.kind == .chunk { total += 3 }
            if bundle.item.title.lowercased().contains("daily journal") { total += 2 }
            if intent.temporalIntent != nil {
                total += 4
            }
            if let temporalRange = intent.temporalRange,
               sourceDateMatchesTemporalRange(sourceSortDate(bundle: bundle, result: result), range: temporalRange) {
                total += 8
            }
            if intent.factFamily == "spending_fact",
               intent.semanticQueryTerms.contains(where: { ["gas", "fuel", "fill-up", "gallons"].contains($0) }) {
                if containsGasSpendingSignal(lower) {
                    total += 14
                    if containsFuelReceiptSignal(lower) {
                        total += 16
                    }
                } else if containsSpendingSignal(lower) {
                    total -= 12
                }
            }
            return total
        }
        if let subject = intent.subject?.lowercased(), lower.contains(subject) { total += 12 }
        if containsFoodSignal(lower) { total += 4 }
        if containsPreferenceSignal(lower) { total += 4 }
        if containsSavedCandidateSignal(lower) { total += 3 }
        if result.kind == .chunk { total += 3 }
        if bundle.item.title.lowercased().contains("daily journal") { total += 2 }
        if containsSavedCandidateIntent(intent.normalizedQuery) {
            if containsSavedCandidateSignal(lower) { total += 10 }
            if lower.contains("lynnwood") { total += 8 }
            if lower.contains("asian") { total += 6 }
            if lower.contains("place") || lower.contains("restaurant") { total += 3 }
            if !containsSavedCandidateSignal(lower) { total -= 10 }
            if containsPreferenceSignal(lower) && !containsSavedCandidateSignal(lower) { total -= 6 }
        }
        return total
    }

    private func evidenceKind(
        quote: String,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> String {
        if mode == .memory {
            return "source_backed_memory_observation"
        }
        let text = [quote, result.title, result.snippet].joined(separator: "\n").lowercased()
        if containsSavedCandidateSignal(text) {
            return "source_backed_candidate"
        }
        return "source_backed_observation"
    }

    private func rankReason(
        quote: String,
        bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode,
        sortDate: Date?
    ) -> String {
        var reasons: [String] = []
        let lower = quote.lowercased()
        if mode == .memory {
            let overlap = intent.semanticQueryTerms.filter { lower.contains($0) }.count
            if overlap > 0 {
                reasons.append("query fact match")
            }
            if result.kind == .chunk {
                reasons.append("source-backed chunk evidence")
            } else {
                reasons.append("source-backed item evidence")
            }
            if bundle.item.title.lowercased().contains("daily journal") {
                reasons.append("journal source")
            }
            if intent.temporalIntent != nil {
                reasons.append("explicit temporal intent")
            }
            if let temporalRange = intent.temporalRange,
               sourceDateMatchesTemporalRange(sortDate, range: temporalRange) {
                reasons.append("resolved temporal range source-date match")
            }
            if isGenericExplicitDateRecall(intent: intent),
               sourceDateMatchesTemporalIntent(sortDate, intent: intent.temporalIntent) {
                reasons.append("generic explicit-date source-date match")
            }
            if isSpecificDateSourceRecall(intent: intent),
               sourceDateMatchesTemporalIntent(sortDate, intent: intent) {
                reasons.append("specific-date source-date match")
            }
            if isLatestJournalSourceRecall(intent: intent),
               isDailyJournalSource(bundle: bundle, result: result) {
                reasons.append("latest journal source-date match")
            }
            return orderedUnique(reasons).joined(separator: "; ")
        }
        if let subject = intent.subject?.lowercased(), lower.contains(subject) {
            reasons.append("specific subject match")
        }
        if result.kind == .chunk {
            reasons.append("source-backed chunk evidence")
        } else {
            reasons.append("source-backed item evidence")
        }
        if containsPreferenceSignal(lower) {
            reasons.append("specific preference wording")
        }
        if containsSavedCandidateSignal(lower) {
            reasons.append("saved-to-try source-backed candidate")
        }
        if bundle.item.title.lowercased().contains("daily journal") {
            reasons.append("journal source")
        }
        return orderedUnique(reasons).joined(separator: "; ")
    }

    private func matchedSemanticTerms(
        quote: String,
        bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> [String] {
        guard mode == .memory else { return [] }
        let searchable = ([quote, result.title, result.snippet, bundle.item.title] + bundle.chunks.map(\.body))
            .joined(separator: "\n")
            .lowercased()
        return intent.semanticQueryTerms.filter { searchable.contains($0) }
    }

    private func matchExplanation(
        matchedTerms: [String],
        intent: CiderNaturalPreferenceRecallIntent,
        result: CiderItemSearchResult,
        mode: CiderNaturalRecallMode,
        sortDate: Date?
    ) -> String {
        guard mode == .memory else { return "" }
        if isGenericExplicitDateRecall(intent: intent),
           sourceDateMatchesTemporalIntent(sortDate, intent: intent.temporalIntent) {
            return "Matched general_memory from generic explicit-date recall anchored to source date \(Self.localDayFormatter.string(from: sortDate ?? Date())); not accepted memory truth."
        }
        if isSpecificDateSourceRecall(intent: intent),
           sourceDateMatchesTemporalIntent(sortDate, intent: intent) {
            return "Matched general_memory from specific-date recall anchored to source date \(Self.localDayFormatter.string(from: sortDate ?? Date())); not accepted memory truth."
        }
        if isLatestJournalSourceRecall(intent: intent) {
            return "Matched general_memory from latest journal recall anchored to Daily Journal source date \(Self.localDayFormatter.string(from: sortDate ?? Date())); not accepted memory truth."
        }
        if let temporalRange = intent.temporalRange,
           sourceDateMatchesTemporalRange(sortDate, range: temporalRange) {
            let date = Self.localDayFormatter.string(from: sortDate ?? referenceDate())
            return "Matched general_memory inside resolved temporal range \(temporalRange.startDate) to \(temporalRange.endDate), anchored to source date \(date); not accepted memory truth."
        }
        let family = intent.factFamily ?? "general_memory"
        let target = intent.factTarget.map { " targeting \($0)" } ?? ""
        let source = result.kind == .chunk ? "chunk" : "item"
        return "Matched \(family)\(target) from source-backed terms [\(matchedTerms.joined(separator: ", "))] in \(source) evidence; not accepted memory truth."
    }

    private func explanationReasons(
        rankReason: String,
        matchedTerms: [String],
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> [String] {
        let lower = rankReason.lowercased()
        var reasons: [String] = []
        if lower.contains("specific-date source-date match") {
            reasons.append("source_date_match")
            reasons.append("temporal_date_match")
        }
        if lower.contains("generic explicit-date source-date match") {
            reasons.append("source_date_match")
            reasons.append("temporal_date_match")
        }
        if lower.contains("latest journal source-date match") {
            reasons.append("latest_match")
            reasons.append("journal_source")
        }
        if lower.contains("resolved temporal range source-date match") {
            reasons.append("source_date_match")
            reasons.append("temporal_range_match")
        }
        if lower.contains("journal source") {
            reasons.append("journal_source")
        }
        if lower.contains("query fact match") {
            reasons.append("query_fact_match")
        }
        if lower.contains("source-backed chunk evidence") {
            reasons.append("semantic_chunk_match")
        }
        if lower.contains("specific subject match") {
            reasons.append("entity_person_match")
        }
        if !matchedTerms.isEmpty {
            reasons.append("semantic_term_match")
        }
        if mode == .memory,
           intent.semanticQueryTerms.contains(where: { ["chris", "jacob"].contains($0) }) {
            reasons.append("entity_person_match")
        }
        return orderedUnique(reasons)
    }

    private func classifiedCandidates(
        _ candidates: [CiderNaturalPreferenceRecallCandidate],
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> [CiderNaturalPreferenceRecallCandidate] {
        candidates.enumerated().map { index, candidate in
            var copy = candidate
            let strong = isStrongEvidence(candidate, intent: intent, mode: mode)
            let related = !strong && isRelatedEvidence(candidate, intent: intent, mode: mode)
            if index == 0 && strong {
                copy.evidenceRole = "primary"
                copy.confidenceBand = "strong"
            } else if strong || related {
                copy.evidenceRole = index == 0 ? "primary" : "related"
                copy.confidenceBand = index == 0 && strong ? "strong" : "related"
                if copy.evidenceRole == "related" {
                    copy.explanationReasons = orderedUnique(copy.explanationReasons + ["fallback_related_match"])
                }
            } else {
                copy.evidenceRole = "weak"
                copy.confidenceBand = "weak"
                copy.explanationReasons = orderedUnique(copy.explanationReasons + ["fallback_related_match"])
            }
            return copy
        }
    }

    private func isStrongEvidence(
        _ candidate: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> Bool {
        if candidate.explanationReasons.contains("source_date_match") { return true }
        if candidate.explanationReasons.contains("latest_match") { return true }
        if mode == .memory {
            let nonGenericTerms = nonRangeSemanticTerms(for: intent)
            let required = min(2, max(1, nonGenericTerms.count))
            let matchedNonGeneric = candidate.matchedSemanticTerms.filter { nonGenericTerms.contains($0) }
            return matchedNonGeneric.count >= required && candidate.score >= 8
        }
        return candidate.score >= 8
    }

    private func isRelatedEvidence(
        _ candidate: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent,
        mode: CiderNaturalRecallMode
    ) -> Bool {
        if mode == .memory {
            return !candidate.matchedSemanticTerms.isEmpty || candidate.score >= 4
        }
        return candidate.score >= 4
    }

    private func explanation(
        for intent: CiderNaturalPreferenceRecallIntent,
        candidates: [CiderNaturalPreferenceRecallCandidate],
        fallbackCommand: String?,
        mode: CiderNaturalRecallMode
    ) -> CiderNaturalPreferenceRecallExplanation {
        let primaryRefs = candidates
            .filter { $0.evidenceRole == "primary" }
            .flatMap(\.citationRefs)
        let relatedRefs = candidates
            .filter { $0.evidenceRole == "related" }
            .flatMap(\.citationRefs)
        let weakRefs = candidates
            .filter { $0.evidenceRole == "weak" }
            .flatMap(\.citationRefs)
        let band: String
        if !primaryRefs.isEmpty {
            band = candidates.first?.confidenceBand ?? "strong"
        } else if !relatedRefs.isEmpty {
            band = "related"
        } else if !weakRefs.isEmpty {
            band = "weak"
        } else {
            band = "none"
        }
        var reasons = orderedUnique(candidates.flatMap(\.explanationReasons))
        if band == "none" {
            reasons.append("no_source_backed_exact_answer")
        } else if primaryRefs.isEmpty {
            reasons.append("related_matches_only")
        }
        var commands = orderedUnique(candidates.flatMap { candidate in
            candidate.provenance?.contextCommands ?? candidate.safeNextCommands
        })
        if let fallbackCommand {
            commands.append(fallbackCommand)
        }
        let copy: String
        switch band {
        case "strong":
            copy = "Primary evidence is source-backed and ranked ahead of related matches; observations remain outside accepted memory truth."
        case "related":
            copy = "Only related source-backed matches were found; use the context commands before treating this as an answer."
        case "weak":
            copy = "Only weak source-backed matches were found; no exact answer is supported by the current evidence."
        default:
            copy = "No source-backed exact answer was found for this \(mode.noun) recall query."
        }
        return CiderNaturalPreferenceRecallExplanation(
            confidenceBand: band,
            reasons: orderedUnique(reasons),
            primaryEvidenceRefs: orderedUnique(primaryRefs),
            relatedEvidenceRefs: orderedUnique(relatedRefs),
            weakEvidenceRefs: orderedUnique(weakRefs),
            copy: copy,
            safeNextCommands: orderedUnique(commands)
        )
    }

    private func evidenceTokens(for intent: CiderNaturalPreferenceRecallIntent, mode: CiderNaturalRecallMode) -> [String] {
        if mode == .memory {
            return intent.semanticQueryTerms
        }
        var tokens = ["liked", "like", "great", "good", "okay", "worth", "again", "order", "ordered", "had", "ate", "food", "breakfast", "lunch", "dinner"]
        tokens.append(contentsOf: significantQueryTokens(in: intent.normalizedQuery))
        if let subject = intent.subject {
            tokens.append(contentsOf: subject.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        return orderedUnique(tokens)
    }

    private func containsPreferenceSignal(_ text: String) -> Bool {
        [
            "liked", "likes", "like ", "great", "good", "very good", "pretty damn good",
            "worth ordering again", "get it again", "get it more often", "wants more",
            "prefers", "favorite",
        ].contains { text.contains($0) }
    }

    private func containsFoodSignal(_ text: String) -> Bool {
        [
            "food", "breakfast", "lunch", "dinner", "restaurant", "cafeteria", "doordash",
            "ordered", "ramen", "chicken", "burrito", "musubi", "loco moco",
            "kimchee", "cucumber", "pasta", "soup", "drink", "candy", "latte", "flavor",
            "asian",
        ].contains { text.contains($0) }
    }

    private func containsSavedCandidateIntent(_ text: String) -> Bool {
        text.contains("save to try")
            || text.contains("saved to try")
            || text.contains("places did i save")
            || text.contains("place did i save")
    }

    private func containsSavedCandidateSignal(_ text: String) -> Bool {
        text.contains("saved to try")
            || text.contains("save to try")
            || text.contains("place to try")
            || text.contains("places to try")
            || text.contains("want to try")
            || text.contains("try for")
    }

    private func containsSpendingSignal(_ text: String) -> Bool {
        text.contains("$")
            || text.contains("gallon")
            || text.contains("total")
            || text.contains("fuel amount")
            || text.contains("effective price")
            || text.contains("unit price")
            || text.contains("paid")
            || text.contains("cost")
            || text.contains("expensive")
    }

    private func containsGasSpendingSignal(_ text: String) -> Bool {
        containsSpendingSignal(text)
            && (
                text.contains("gas")
                    || text.contains("fuel")
                    || text.contains("fill-up")
                    || text.contains("fill up")
                    || text.contains("gallon")
                    || text.contains("/gal")
            )
    }

    private func containsFuelReceiptSignal(_ text: String) -> Bool {
        text.contains("fuel")
            || text.contains("fill-up")
            || text.contains("fill up")
            || text.contains("gallon")
            || text.contains("/gal")
    }

    private func quoteLines(
        from text: String,
        tokens: [String],
        intent: CiderNaturalPreferenceRecallIntent
    ) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("{") && !$0.hasPrefix("[") }
            .filter { !isMetaRecallPlanningLine($0) }
            .compactMap(cleanRecallEvidenceLine)
        if intent.factFamily == "spending_fact" {
            let spendingLines = lines.filter { containsSpendingSignal($0.lowercased()) }
            if intent.semanticQueryTerms.contains(where: { ["gas", "fuel", "fill-up", "gallons"].contains($0) }) {
                let gasSpendingLines = spendingLines.filter { containsGasSpendingSignal($0.lowercased()) }
                if !gasSpendingLines.isEmpty {
                    return gasSpendingLines.prefix(5).joined(separator: "\n")
                }
            }
            if !spendingLines.isEmpty {
                return spendingLines.prefix(5).joined(separator: "\n")
            }
        }
        let matched = lines.filter { line in
            let lower = line.lowercased()
            if intent.normalizedQuery.contains("food") || intent.questionKind == .repeatSuggestion {
                return containsFoodSignal(lower) && (containsPreferenceSignal(lower) || containsSavedCandidateSignal(lower))
            }
            return tokens.contains { lower.contains($0) }
        }
        if !matched.isEmpty {
            return matched.prefix(5).joined(separator: "\n")
        }
        if !lines.isEmpty {
            return lines.prefix(5).joined(separator: "\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanRecallEvidenceLine(_ rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = line.lowercased()
        if lower.hasPrefix("title:") || lower.hasPrefix("path:") {
            return nil
        }
        if lower.hasPrefix("#") {
            return nil
        }
        if isJournalScaffoldEvidenceLine(lower) {
            return nil
        }
        for prefix in ["Content:", "Capture source text:"] where line.localizedCaseInsensitiveContains(prefix) {
            if let range = line.range(of: prefix, options: .caseInsensitive) {
                line = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let strippedLower = line.lowercased()
        if strippedLower.hasPrefix("title:") || strippedLower.hasPrefix("path:") {
            return nil
        }
        if strippedLower.hasPrefix("#") {
            return nil
        }
        if isJournalScaffoldEvidenceLine(strippedLower) {
            return nil
        }
        for marker in [". Source image:", " Source image:"] {
            if let range = line.range(of: marker, options: .caseInsensitive) {
                line = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let colon = line.firstIndex(of: ":") {
            let prefix = String(line[..<colon])
            let suffix = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count <= 80 && memoryFactLineScore(suffix) >= memoryFactLineScore(prefix) {
                line = suffix
            }
        }
        return line.isEmpty ? nil : line
    }

    private func isJournalScaffoldEvidenceLine(_ lowercasedLine: String) -> Bool {
        lowercasedLine.contains("voice journal addendum")
            || lowercasedLine.contains("voice journal entry")
            || lowercasedLine.contains("daily journal entry")
    }

    private func significantQueryTokens(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "at", "did", "do", "does", "for", "have", "how", "i",
            "is", "it", "me", "my", "of", "on", "or", "the", "to", "was", "what", "when",
            "where", "which", "who", "why", "with",
        ]
        return orderedUnique(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
                .map(String.init)
                .filter { $0.count > 1 && !stopWords.contains($0) }
        )
    }

    private func isMetaRecallPlanningLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("i want cider")
            || lower.contains("easy to recall")
            || lower.contains("not just as loose chat summaries")
            || lower.contains("examples:")
            || lower.contains("i want to be able to ask")
    }

    private func score(_ text: String, tokens: [String]) -> Int {
        let lower = text.lowercased()
        return tokens.reduce(0) { partial, token in
            partial + (lower.contains(token) ? 1 : 0)
        }
    }

    private func summary(
        for intent: CiderNaturalPreferenceRecallIntent,
        citations: [CiderNaturalPreferenceRecallCitation],
        candidates: [CiderNaturalPreferenceRecallCandidate],
        mode: CiderNaturalRecallMode
    ) -> String {
        guard !citations.isEmpty else {
            if mode == .memory, let command = broaderSearchCommand(for: intent, limit: 10) {
                return "I did not find a source-backed exact answer for this memory recall question. Try the broader source search fallback: \(command)"
            }
            return "I did not find source-backed journal or captured-item evidence for this \(mode.noun) recall question."
        }
        let subjectCopy = intent.subject.map { " for \($0)" } ?? ""
        let lead: String
        if mode == .memory {
            let primaryRefs = Set(candidates.filter { $0.evidenceRole == "primary" }.flatMap(\.citationRefs))
            let primaryCitations = citations.filter { primaryRefs.contains($0.sourceRef) }
            let selectedCitations = primaryCitations.isEmpty ? Array(citations.prefix(1)) : primaryCitations
            let facts = selectedCitations.prefix(3).map { citation in
                let fact = synthesizedMemoryFact(from: citation.quote, intent: intent)
                return citation.title.isEmpty ? fact : "\(fact) (source: \(citation.title))"
            }
            return "Source-backed answer\(subjectCopy): \(facts.joined(separator: " ")) This is cited source evidence, not accepted memory truth."
        } else {
            switch intent.questionKind {
            case .existence:
                lead = "I found journaled/captured evidence\(subjectCopy)."
            case .lastOrder:
                lead = "I found source-backed order/item notes\(subjectCopy)."
            case .repeatSuggestion:
                lead = "Based only on cited journaled/captured observations, these are repeat candidates\(subjectCopy)."
            case .liked, .recentLiked:
                lead = "I found source-backed liked/preference observations\(subjectCopy)."
            case .general:
                lead = "I found source-backed preference/item observations\(subjectCopy)."
            }
        }
        let bullets = citations.prefix(4).map { "- \($0.title): \($0.quote)" }.joined(separator: "\n")
        return "\(lead) These are observations from sources, not accepted memory truth:\n\(bullets)"
    }

    private func synthesizedMemoryFact(from quote: String, intent: CiderNaturalPreferenceRecallIntent) -> String {
        let lines = quote
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if intent.factFamily == "spending_fact" {
            let spendingLines = lines.filter { containsSpendingSignal($0.lowercased()) }
            if !spendingLines.isEmpty {
                return clipped(spendingLines.prefix(4).joined(separator: " "), limit: 220)
            }
        }
        let selected = lines.max { lhs, rhs in
            memoryFactLineScore(lhs, intent: intent) < memoryFactLineScore(rhs, intent: intent)
        } ?? quote
        return clipped(selected, limit: 220)
    }

    private func memoryFactLineScore(_ line: String, intent: CiderNaturalPreferenceRecallIntent) -> Int {
        let lower = line.lowercased()
        let semanticScore = intent.semanticQueryTerms.reduce(0) { partial, term in
            partial + (lower.contains(term) ? 10 : 0)
        }
        return semanticScore + memoryFactLineScore(line)
    }

    private func memoryFactLineScore(_ line: String) -> Int {
        let lower = line.lowercased()
        var total = 0
        if lower.contains("coverall") { total += 8 }
        if lower.contains("boot") || lower.contains("shoe") { total += 7 }
        if lower.contains("screwdriver") || lower.contains("tool") || lower.contains("kit") { total += 7 }
        if lower.contains("dental") || lower.contains("toothpaste") || lower.contains("medication") { total += 7 }
        if lower.contains(" fit") || lower.contains("fits") { total += 6 }
        if lower.contains("preferred") || lower.contains("prefer") { total += 6 }
        if lower.contains("60-rg") || lower.contains("60 regular") { total += 6 }
        if lower.contains(" size ") { total += 4 }
        if lower.contains(" code") { total += 4 }
        if lower.contains("red kap") { total += 4 }
        if containsSpendingSignal(lower) { total += 6 }
        if lower.contains("context:") || lower.contains("unrelated:") { total -= 8 }
        return total
    }

    private func rankingExplanation(
        for intent: CiderNaturalPreferenceRecallIntent,
        candidates: [CiderNaturalPreferenceRecallCandidate],
        mode: CiderNaturalRecallMode
    ) -> String {
        let terms = intent.semanticQueryTerms.joined(separator: ", ")
        guard !candidates.isEmpty else {
            return "No source-backed candidates met the bounded \(mode.noun) recall overlap check for semantic terms: \(terms)."
        }
        let target = intent.factTarget.map { " targeting \($0)" } ?? ""
        if mode == .memory, isGenericExplicitDateRecall(intent: intent) {
            return "Ranked \(candidates.count) source-backed memory candidate(s)\(target) by explicit date intent first when source dates match, then semantic term overlap, chunk evidence, and source recency using terms: \(terms)."
        }
        if mode == .memory, intent.temporalRange != nil {
            return "Ranked \(candidates.count) source-backed memory candidate(s)\(target) by resolved temporal range source-date match first, then semantic term overlap, chunk evidence, and source recency using terms: \(terms)."
        }
        if mode == .memory, isSpecificDateSourceRecall(intent: intent) {
            return "Ranked \(candidates.count) source-backed memory candidate(s)\(target) by specific source date first when source dates match, then semantic term overlap, chunk evidence, and source recency using terms: \(terms)."
        }
        if mode == .memory, isLatestJournalSourceRecall(intent: intent) {
            return "Ranked \(candidates.count) source-backed memory candidate(s)\(target) by latest journal source date first for Daily Journal evidence, then semantic term overlap and chunk evidence using terms: \(terms)."
        }
        return "Ranked \(candidates.count) source-backed \(mode.noun) candidate(s)\(target) by semantic term overlap, chunk evidence, and source recency using terms: \(terms)."
    }

    private func shouldPreferGenericDateSourceAnchor(
        lhs: CiderNaturalPreferenceRecallCandidate,
        rhs: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Bool {
        guard isGenericExplicitDateRecall(intent: intent) else { return false }
        let lhsMatches = sourceDateMatchesTemporalIntent(lhs.sortDate, intent: intent.temporalIntent)
        let rhsMatches = sourceDateMatchesTemporalIntent(rhs.sortDate, intent: intent.temporalIntent)
        return lhsMatches != rhsMatches
    }

    private func shouldPreferSpecificDateSourceAnchor(
        lhs: CiderNaturalPreferenceRecallCandidate,
        rhs: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Bool {
        guard isSpecificDateSourceRecall(intent: intent) else { return false }
        let lhsMatches = sourceDateMatchesTemporalIntent(lhs.sortDate, intent: intent)
        let rhsMatches = sourceDateMatchesTemporalIntent(rhs.sortDate, intent: intent)
        return lhsMatches != rhsMatches
    }

    private func shouldPreferLatestJournalSourceDateAnchor(
        lhs: CiderNaturalPreferenceRecallCandidate,
        rhs: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Bool {
        guard isLatestJournalSourceRecall(intent: intent) else { return false }
        let lhsIsJournal = lhs.title.lowercased().contains("daily journal")
        let rhsIsJournal = rhs.title.lowercased().contains("daily journal")
        if lhsIsJournal != rhsIsJournal {
            return lhsIsJournal
        }
        guard lhsIsJournal, rhsIsJournal else { return false }
        return lhs.sortDate != rhs.sortDate
    }

    private func shouldPreferTemporalRecency(
        lhs: CiderNaturalPreferenceRecallCandidate,
        rhs: CiderNaturalPreferenceRecallCandidate,
        intent: String
    ) -> Bool {
        switch intent {
        case "today", "latest", "specific_date":
            let scoreGap = abs(lhs.score - rhs.score)
            return scoreGap <= 8 && lhs.sortDate != rhs.sortDate
        default:
            return false
        }
    }

    private func shouldPreferTemporalRangeMatch(
        lhs: CiderNaturalPreferenceRecallCandidate,
        rhs: CiderNaturalPreferenceRecallCandidate,
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Bool {
        guard let range = intent.temporalRange else { return false }
        let lhsMatches = sourceDateMatchesTemporalRange(lhs.sortDate, range: range)
        let rhsMatches = sourceDateMatchesTemporalRange(rhs.sortDate, range: range)
        return lhsMatches != rhsMatches
    }

    private func sourceSortDate(bundle: CiderItemContextBundle, result: CiderItemSearchResult) -> Date {
        if let sourceDate = dailyJournalSourceDate(from: [bundle.item.title, result.title, bundle.item.relativePath].compactMap { $0 }) {
            return sourceDate
        }
        if let captureDate = result.captureProvenance.map(\.createdAt).max() {
            return captureDate
        }
        return max(bundle.item.updatedAt, bundle.item.createdAt)
    }

    private func dailyJournalSourceDate(from values: [String]) -> Date? {
        for value in values {
            let lower = value.lowercased()
            guard lower.contains("daily journal") else { continue }
            if let dateString = specificDateAnchor(in: lower),
               let date = Self.localDayFormatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    private func isGenericExplicitDateRecall(intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        isGenericExplicitDateRecall(
            normalizedQuery: intent.normalizedQuery,
            semanticTerms: intent.semanticQueryTerms
        )
    }

    private func isSpecificDateSourceRecall(intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        intent.temporalIntent == "specific_date" && intent.temporalDate != nil
    }

    private func isGenericExplicitDateRecall(normalizedQuery: String, semanticTerms: [String]) -> Bool {
        let dateTokens = explicitDateTokens.filter { normalizedQuery.contains($0) || semanticTerms.contains($0) }
        guard !dateTokens.isEmpty else { return false }
        let nonDateSignalTerms = semanticTerms.filter { term in
            !explicitDateTokens.contains(term) && !genericMemoryRecallTokens.contains(term)
        }
        return nonDateSignalTerms.count <= 1
    }

    private func isLatestJournalSourceRecall(intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        isLatestJournalSourceRecall(
            normalizedQuery: intent.normalizedQuery,
            semanticTerms: intent.semanticQueryTerms
        )
    }

    private func isLatestJournalSourceRecall(normalizedQuery: String, semanticTerms: [String]) -> Bool {
        guard normalizedQuery.contains("journal"),
              temporalIntent(for: normalizedQuery, mode: .memory) == "latest"
        else {
            return false
        }
        let journalSourceTerms: Set<String> = ["daily", "entry", "journal", "journaled", "latest", "newest", "recent"]
        let nonJournalSignalTerms = semanticTerms.filter { term in
            !journalSourceTerms.contains(term) && !genericMemoryRecallTokens.contains(term)
        }
        return nonJournalSignalTerms.isEmpty
    }

    private func isDailyJournalSource(bundle: CiderItemContextBundle, result: CiderItemSearchResult) -> Bool {
        [bundle.item.title, result.title]
            .contains { $0.lowercased().contains("daily journal") }
    }

    private func sourceDateMatchesTemporalIntent(_ date: Date?, intent: String?) -> Bool {
        guard let date, let intent else { return false }
        let calendar = Calendar.current
        switch intent {
        case "today":
            return Self.localDayFormatter.string(from: date) == Self.localDayFormatter.string(from: referenceDate())
        case "yesterday":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate()) else { return false }
            return Self.localDayFormatter.string(from: date) == Self.localDayFormatter.string(from: yesterday)
        default:
            return false
        }
    }

    private func sourceDateMatchesTemporalIntent(_ date: Date?, intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        guard let date,
              intent.temporalIntent == "specific_date",
              let temporalDate = intent.temporalDate
        else {
            return false
        }
        return Self.localDayFormatter.string(from: date) == temporalDate
    }

    private func sourceDateMatchesTemporalRangeIfNeeded(_ date: Date?, intent: CiderNaturalPreferenceRecallIntent) -> Bool {
        guard let range = intent.temporalRange else { return true }
        return sourceDateMatchesTemporalRange(date, range: range)
    }

    private func sourceDateMatchesTemporalRange(_ date: Date?, range: CiderNaturalPreferenceRecallTemporalRange) -> Bool {
        guard let date,
              let start = Self.localDayFormatter.date(from: range.startDate),
              let end = Self.localDayFormatter.date(from: range.endDate)
        else {
            return false
        }
        let day = Self.recallCalendar.startOfDay(for: date)
        return day >= start && day <= end
    }

    private func nonRangeSemanticTerms(for intent: CiderNaturalPreferenceRecallIntent) -> [String] {
        if let range = intent.temporalRange {
            return significantQueryTokens(in: range.remainingSemanticQuery)
                .filter { !genericMemoryRecallTokens.contains($0) && !explicitDateTokens.contains($0) }
        }
        return intent.semanticQueryTerms.filter { !genericMemoryRecallTokens.contains($0) && !explicitDateTokens.contains($0) }
    }

    private func temporalDateAnchor(in normalizedQuery: String, mode: CiderNaturalRecallMode) -> String? {
        guard mode == .memory else { return nil }
        let tokens = Set(significantQueryTokens(in: normalizedQuery))
        if tokens.contains("today") || normalizedQuery.contains("right now") {
            return Self.localDayFormatter.string(from: referenceDate())
        }
        if tokens.contains("yesterday"),
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: referenceDate()) {
            return Self.localDayFormatter.string(from: yesterday)
        }
        return specificDateAnchor(in: normalizedQuery)
    }

    private func specificDateAnchor(in normalizedQuery: String) -> String? {
        if let range = normalizedQuery.range(of: #"\b20\d{2}-\d{2}-\d{2}\b"#, options: .regularExpression) {
            return String(normalizedQuery[range])
        }
        if let slashDate = slashDateAnchor(in: normalizedQuery) {
            return slashDate
        }
        return naturalMonthDateAnchor(in: normalizedQuery)
    }

    private func slashDateAnchor(in normalizedQuery: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})/(20\d{2})\b"#),
              let match = regex.firstMatch(in: normalizedQuery, range: NSRange(normalizedQuery.startIndex..., in: normalizedQuery)),
              let monthRange = Range(match.range(at: 1), in: normalizedQuery),
              let dayRange = Range(match.range(at: 2), in: normalizedQuery),
              let yearRange = Range(match.range(at: 3), in: normalizedQuery),
              let month = Int(normalizedQuery[monthRange]),
              let day = Int(normalizedQuery[dayRange]),
              let year = Int(normalizedQuery[yearRange])
        else {
            return nil
        }
        return formattedDate(year: year, month: month, day: day)
    }

    private func naturalMonthDateAnchor(in normalizedQuery: String) -> String? {
        let monthPattern = Self.monthNameToNumber.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: #"\b("# + monthPattern + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d{2}))?\b"#),
              let match = regex.firstMatch(in: normalizedQuery, range: NSRange(normalizedQuery.startIndex..., in: normalizedQuery)),
              let monthRange = Range(match.range(at: 1), in: normalizedQuery),
              let dayRange = Range(match.range(at: 2), in: normalizedQuery),
              let month = Self.monthNameToNumber[String(normalizedQuery[monthRange])],
              let day = Int(normalizedQuery[dayRange])
        else {
            return nil
        }
        let year: Int
        if match.range(at: 3).location != NSNotFound,
           let yearRange = Range(match.range(at: 3), in: normalizedQuery),
           let parsedYear = Int(normalizedQuery[yearRange]) {
            year = parsedYear
        } else {
            year = Calendar.current.component(.year, from: referenceDate())
        }
        return formattedDate(year: year, month: month, day: day)
    }

    private func formattedDate(year: Int, month: Int, day: Int) -> String? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date,
              components.calendar?.component(.year, from: date) == year,
              components.calendar?.component(.month, from: date) == month,
              components.calendar?.component(.day, from: date) == day
        else {
            return nil
        }
        return Self.localDayFormatter.string(from: date)
    }

    private func referenceDate() -> Date {
        currentDate ?? Date()
    }

    private func broaderSearchCommand(for intent: CiderNaturalPreferenceRecallIntent, limit: Int) -> String? {
        let semanticTerms = broaderSearchTerms(for: intent.semanticQueryTerms)
        let fallbackTerms = semanticTerms.isEmpty
            ? significantQueryTokens(in: intent.normalizedQuery).filter { !memoryRecallStopTokens.contains($0) }
            : semanticTerms
        let fallback = orderedUnique(fallbackTerms).joined(separator: " ")
        guard !fallback.isEmpty else { return nil }
        return "cider-cli item search \"\(escapedCommandArgument(fallback))\" --scope personalMemory --sort newest --limit \(limit) --json"
    }

    private func safeSourceLocation(_ relativePath: String?) -> String? {
        guard let relativePath,
              !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..")
        else {
            return nil
        }
        return relativePath
    }

    private func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end])
    }

    private func mergeClaims(_ lhs: String, _ rhs: String) -> String {
        let lines = (lhs + "\n" + rhs)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return clipped(orderedUnique(lines).prefix(6).joined(separator: "\n"), limit: 700)
    }

    private func mergeRankReasons(_ lhs: String, _ rhs: String) -> String {
        let parts = (lhs + ";" + rhs)
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return orderedUnique(parts).joined(separator: "; ")
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func escapedCommandArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let recallCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    private static let monthNameToNumber: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]
}
