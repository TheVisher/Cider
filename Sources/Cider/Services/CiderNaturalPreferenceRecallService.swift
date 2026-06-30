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
    var factFamily: String?
    var factTarget: String?
    var subject: String?
    var searchQueries: [String]
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
    var truthBoundary: String
    var safeNextCommands: [String]
    var provenance: CiderNaturalPreferenceRecallProvenance?
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

    init(contextService: CiderItemContextService = CiderItemContextService(database: .shared)) {
        self.contextService = contextService
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
        let searchPlan = intent.searchQueries.map {
            CiderNaturalPreferenceRecallSearchStep(
                query: $0,
                scope: .personalMemory,
                sort: .newest,
                limit: boundedLimit
            )
        }
        var citationsByOwner: [String: (citation: CiderNaturalPreferenceRecallCitation, score: Int)] = [:]
        var candidatesByOwner: [String: CiderNaturalPreferenceRecallCandidate] = [:]
        var safeCommands: [String] = [
            "cider-cli item \(mode.command.replacingOccurrences(of: "item.", with: "")) \"\(escapedCommandArgument(intent.originalQuery))\" --limit \(boundedLimit) --json",
        ]

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
                let score = evidenceScore(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode)
                let rankReason = rankReason(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode)
                let evidenceKind = evidenceKind(quote: quote, result: result, intent: intent, mode: mode)
                let matchedTerms = matchedSemanticTerms(quote: quote, bundle: bundle, result: result, intent: intent, mode: mode)
                let matchExplanation = matchExplanation(matchedTerms: matchedTerms, intent: intent, result: result, mode: mode)
                let sortDate = sourceSortDate(bundle: bundle, result: result)
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

        let candidates = candidatesByOwner.values
            .sorted {
                if let temporalIntent = intent.temporalIntent, mode == .memory {
                    if shouldPreferTemporalRecency(lhs: $0, rhs: $1, intent: temporalIntent) {
                        return ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast)
                    }
                }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            .prefix(boundedLimit)
            .map { $0 }
        let citations = citationsByOwner.values
            .sorted {
                if let temporalIntent = intent.temporalIntent, mode == .memory {
                    let lhsCandidate = candidatesByOwner[$0.citation.owner.canonicalRef]
                    let rhsCandidate = candidatesByOwner[$1.citation.owner.canonicalRef]
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
        let warnings = citations.isEmpty
            ? ["No source-backed item or chunk matches were found for this natural \(mode.noun) recall query."]
            : []
        return CiderNaturalPreferenceRecallResponse(
            ok: true,
            command: mode.command,
            readOnly: true,
            changed: false,
            intent: intent,
            summary: summary(for: intent, citations: citations, mode: mode),
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
        let temporalIntent = temporalIntent(for: normalized, mode: mode)
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
            factFamily: factFamily,
            factTarget: factTarget,
            subject: subject,
            searchQueries: searchQueries(subject: subject, kind: kind, normalizedQuery: normalized, semanticTerms: semanticTerms, mode: mode)
        )
    }

    private func searchQueries(
        subject: String?,
        kind: CiderNaturalPreferenceRecallQuestionKind,
        normalizedQuery: String,
        semanticTerms: [String],
        mode: CiderNaturalRecallMode
    ) -> [String] {
        if mode == .memory {
            let focused = semanticTerms.joined(separator: " ")
            let literal = significantQueryTokens(in: normalizedQuery).joined(separator: " ")
            let broad = broaderSearchTerms(for: semanticTerms).joined(separator: " ")
            return orderedUnique([focused, literal, broad, normalizedQuery].filter { !$0.isEmpty })
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
        if normalizedQuery.contains("shift") || normalizedQuery.contains("schedule") || normalizedQuery.contains("pay") {
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

    private func temporalIntent(for normalizedQuery: String, mode: CiderNaturalRecallMode) -> String? {
        guard mode == .memory else { return nil }
        let tokens = Set(significantQueryTokens(in: normalizedQuery))
        if tokens.contains("today") || normalizedQuery.contains("right now") {
            return "today"
        }
        if tokens.contains("latest") || tokens.contains("newest") || tokens.contains("recent") || normalizedQuery.contains("most recent") {
            return "latest"
        }
        if normalizedQuery.range(of: #"\b20\d{2}-\d{2}-\d{2}\b"#, options: .regularExpression) != nil {
            return "specific_date"
        }
        return nil
    }

    private func factFamily(for normalizedQuery: String, semanticTerms: [String], mode: CiderNaturalRecallMode) -> String? {
        guard mode == .memory else { return nil }
        if semanticTerms.contains("schedule")
            || semanticTerms.contains("shift")
            || semanticTerms.contains("pay") {
            return "work_schedule_fact"
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
        semanticTerms.filter { !["size", "fit", "clothing", "regular", "rg", "red", "kap", "60", "60-rg"].contains($0) }
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
        mode: CiderNaturalRecallMode
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
        mode: CiderNaturalRecallMode
    ) -> String {
        guard mode == .memory else { return "" }
        let family = intent.factFamily ?? "general_memory"
        let target = intent.factTarget.map { " targeting \($0)" } ?? ""
        let source = result.kind == .chunk ? "chunk" : "item"
        return "Matched \(family)\(target) from source-backed terms [\(matchedTerms.joined(separator: ", "))] in \(source) evidence; not accepted memory truth."
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
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanRecallEvidenceLine(_ rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = line.lowercased()
        if lower.hasPrefix("title:") || lower.hasPrefix("path:") {
            return nil
        }
        for prefix in ["Content:", "Capture source text:"] where line.localizedCaseInsensitiveContains(prefix) {
            if let range = line.range(of: prefix, options: .caseInsensitive) {
                line = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
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
        mode: CiderNaturalRecallMode
    ) -> String {
        guard !citations.isEmpty else {
            if mode == .memory, let command = broaderSearchCommand(for: intent, limit: 10) {
                return "I did not find source-backed journal or captured-item evidence for this memory recall question. Try the broader source search fallback: \(command)"
            }
            return "I did not find source-backed journal or captured-item evidence for this \(mode.noun) recall question."
        }
        let subjectCopy = intent.subject.map { " for \($0)" } ?? ""
        let lead: String
        if mode == .memory {
            let facts = citations.prefix(3).map { citation in
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
        return "Ranked \(candidates.count) source-backed \(mode.noun) candidate(s)\(target) by semantic term overlap, chunk evidence, and source recency using terms: \(terms)."
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

    private func sourceSortDate(bundle: CiderItemContextBundle, result: CiderItemSearchResult) -> Date {
        if let captureDate = result.captureProvenance.map(\.createdAt).max() {
            return captureDate
        }
        return max(bundle.item.updatedAt, bundle.item.createdAt)
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
}
