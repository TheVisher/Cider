import Foundation

enum CiderNaturalPreferenceRecallQuestionKind: String, Codable, Equatable {
    case existence
    case liked
    case lastOrder
    case recentLiked
    case repeatSuggestion
    case general
}

struct CiderNaturalPreferenceRecallIntent: Codable, Equatable {
    var originalQuery: String
    var normalizedQuery: String
    var questionKind: CiderNaturalPreferenceRecallQuestionKind
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
    var citations: [CiderNaturalPreferenceRecallCitation]
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
        let boundedLimit = max(1, limit)
        let intent = interpret(query)
        let searchPlan = intent.searchQueries.map {
            CiderNaturalPreferenceRecallSearchStep(
                query: $0,
                scope: .personalMemory,
                sort: .newest,
                limit: boundedLimit
            )
        }
        var citationsByOwner: [String: (citation: CiderNaturalPreferenceRecallCitation, score: Int)] = [:]
        var safeCommands: [String] = [
            "cider-cli item preference-recall \"\(escapedCommandArgument(intent.originalQuery))\" --limit \(boundedLimit) --json",
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
                let quote = bestQuote(in: bundle, result: result, intent: intent)
                guard qualifies(quote: quote, bundle: bundle, result: result, intent: intent) else { continue }
                let key = bundle.owner.canonicalRef
                if citationsByOwner[key] == nil {
                    let commands = [
                        "cider-cli item context \(bundle.item.type.rawValue) \(bundle.item.id.uuidString) --json",
                        "cider-cli item search \"\(escapedCommandArgument(step.query))\" --scope \(step.scope.rawValue) --sort \(step.sort.rawValue) --limit \(step.limit) --json",
                    ]
                    let citation = CiderNaturalPreferenceRecallCitation(
                        id: key,
                        owner: bundle.owner,
                        title: bundle.item.title,
                        quote: quote,
                        source: result.stage ?? result.kind.rawValue,
                        itemType: bundle.item.type.rawValue,
                        itemID: bundle.item.id.uuidString,
                        sourceRef: "\(bundle.item.type.rawValue):\(bundle.item.id.uuidString)",
                        safeNextCommands: commands
                    )
                    citationsByOwner[key] = (citation, evidenceScore(quote: quote, bundle: bundle, result: result, intent: intent))
                    safeCommands.append(contentsOf: commands)
                }
            }
        }

        let citations = citationsByOwner.values
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.citation.title.localizedStandardCompare($1.citation.title) == .orderedDescending
            }
            .prefix(boundedLimit)
            .map(\.citation)
        let warnings = citations.isEmpty
            ? ["No source-backed item or chunk matches were found for this natural preference recall query."]
            : []
        return CiderNaturalPreferenceRecallResponse(
            ok: true,
            command: "item.preference-recall",
            readOnly: true,
            changed: false,
            intent: intent,
            summary: summary(for: intent, citations: citations),
            truthBoundary: "source_backed_observations_not_accepted_truth",
            reviewStatus: CiderNaturalPreferenceRecallReviewStatus(
                needsReview: false,
                copy: "Journaled/captured observations are cited source evidence. They were not promoted into accepted memory truth."
            ),
            searchPlan: searchPlan,
            citations: citations,
            safeNextCommands: orderedUnique(safeCommands),
            warnings: warnings
        )
    }

    func interpret(_ rawQuery: String) -> CiderNaturalPreferenceRecallIntent {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = query.lowercased()
        let subject = extractSubject(from: query)
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
            questionKind: kind,
            subject: subject,
            searchQueries: searchQueries(subject: subject, kind: kind, normalizedQuery: normalized)
        )
    }

    private func searchQueries(
        subject: String?,
        kind: CiderNaturalPreferenceRecallQuestionKind,
        normalizedQuery: String
    ) -> [String] {
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
            return ["liked great worth ordering again food", "breakfast lunch dinner great liked"]
        }
        if kind == .repeatSuggestion {
            return ["worth ordering again food", "get it again liked food", "liked great restaurant cafeteria"]
        }
        return [normalizedQuery]
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
        intent: CiderNaturalPreferenceRecallIntent
    ) -> String {
        let candidates = bundle.chunks.map(\.body) + bundle.sections.map(\.body) + [result.snippet]
        let tokens = evidenceTokens(for: intent)
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
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Bool {
        let quoteText = quote.lowercased()
        let searchable = ([quote, result.title, result.snippet, bundle.item.title] + bundle.chunks.map(\.body))
            .joined(separator: "\n")
            .lowercased()
        if let subject = intent.subject?.lowercased(), !subject.isEmpty {
            return quoteText.contains(subject) || searchable.contains(subject)
        }
        if intent.normalizedQuery.contains("food") {
            return containsFoodSignal(quoteText) && containsPreferenceSignal(quoteText)
        }
        if intent.questionKind == .repeatSuggestion {
            return containsFoodSignal(quoteText) && containsPreferenceSignal(quoteText)
        }
        return containsPreferenceSignal(quoteText)
    }

    private func evidenceScore(
        quote: String,
        bundle: CiderItemContextBundle,
        result: CiderItemSearchResult,
        intent: CiderNaturalPreferenceRecallIntent
    ) -> Int {
        var total = score(quote, tokens: evidenceTokens(for: intent))
        let lower = quote.lowercased()
        if let subject = intent.subject?.lowercased(), lower.contains(subject) { total += 12 }
        if containsFoodSignal(lower) { total += 4 }
        if containsPreferenceSignal(lower) { total += 4 }
        if bundle.item.title.lowercased().contains("daily journal") { total += 2 }
        if result.kind == .chunk { total += 1 }
        return total
    }

    private func evidenceTokens(for intent: CiderNaturalPreferenceRecallIntent) -> [String] {
        var tokens = ["liked", "like", "great", "good", "okay", "worth", "again", "order", "ordered", "had", "ate", "food", "breakfast", "lunch", "dinner"]
        if let subject = intent.subject {
            tokens.append(contentsOf: subject.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        return orderedUnique(tokens)
    }

    private func containsPreferenceSignal(_ text: String) -> Bool {
        [
            "liked", "likes", "like ", "great", "good", "very good", "pretty damn good",
            "worth ordering again", "get it again", "get it more often", "wants more",
            "prefers", "preference", "favorite",
        ].contains { text.contains($0) }
    }

    private func containsFoodSignal(_ text: String) -> Bool {
        [
            "food", "breakfast", "lunch", "dinner", "restaurant", "cafeteria", "doordash",
            "ordered", "ramen", "chicken", "burrito", "musubi", "loco moco",
            "kimchee", "cucumber", "pasta", "soup", "drink", "candy", "latte", "flavor",
        ].contains { text.contains($0) }
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
        let matched = lines.filter { line in
            let lower = line.lowercased()
            if intent.normalizedQuery.contains("food") || intent.questionKind == .repeatSuggestion {
                return containsFoodSignal(lower) && containsPreferenceSignal(lower)
            }
            return tokens.contains { lower.contains($0) }
        }
        if !matched.isEmpty {
            return matched.prefix(5).joined(separator: "\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        citations: [CiderNaturalPreferenceRecallCitation]
    ) -> String {
        guard !citations.isEmpty else {
            return "I did not find source-backed journal or captured-item evidence for this preference/item recall question."
        }
        let subjectCopy = intent.subject.map { " for \($0)" } ?? ""
        let lead: String
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
        let bullets = citations.prefix(4).map { "- \($0.title): \($0.quote)" }.joined(separator: "\n")
        return "\(lead) These are observations from sources, not accepted memory truth:\n\(bullets)"
    }

    private func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end])
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
