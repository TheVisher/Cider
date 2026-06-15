import Foundation

struct SecondBrainCanonicalEntitySummary: Equatable {
    var owner: SecondBrainOwnerRef
    var stableKey: String
    var displayName: String
    var aliases: [String]
    var possibleTypes: [String]
    var acceptedOutputs: [SecondBrainEnrichmentOutput]
    var acceptedRelations: [SecondBrainRelation]
    var reviewableCandidates: [SecondBrainEnrichmentOutput]

    var ref: String { owner.canonicalRef }
    var sourceEvidenceCount: Int { acceptedOutputs.count }
    var acceptedRelationCount: Int { acceptedRelations.count }
    var reviewableCandidateCount: Int { reviewableCandidates.count }
}

struct SecondBrainCanonicalEntityInspection: Equatable {
    var summary: SecondBrainCanonicalEntitySummary
    var sourceEvidence: [SecondBrainEnrichmentOutput]
    var relatedRelations: [SecondBrainRelation]
    var conflicts: [SecondBrainCanonicalEntitySummary]
}

enum SecondBrainCanonicalEntityLookupError: Error, Equatable, LocalizedError {
    case notFound(selector: String)
    case ambiguous(selector: String, matches: [SecondBrainCanonicalEntitySummary])

    var errorDescription: String? {
        switch self {
        case .notFound(let selector):
            return "No accepted canonical entity matched '\(selector)'."
        case .ambiguous(let selector, let matches):
            return "Entity selector '\(selector)' matched \(matches.count) accepted canonical entities. Use a stable owner ref."
        }
    }
}

@MainActor
final class SecondBrainCanonicalEntityService {
    private let database: CiderDatabase
    private let store: SecondBrainStore
    private let outputService: SecondBrainEnrichmentOutputService

    init(
        database: CiderDatabase = .shared,
        store: SecondBrainStore? = nil,
        outputService: SecondBrainEnrichmentOutputService? = nil
    ) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
    }

    func listEntities(limit: Int? = nil) throws -> [SecondBrainCanonicalEntitySummary] {
        let acceptedOutputs = try acceptedGraphOutputs()
        let grouped = Dictionary(grouping: acceptedOutputs) { output in
            acceptedTargetOwner(for: output)?.canonicalRef ?? output.metadata["canonical_owner_ref"] ?? output.id
        }

        var summaries: [SecondBrainCanonicalEntitySummary] = []
        for (_, outputs) in grouped {
            guard let first = outputs.first,
                  let owner = acceptedTargetOwner(for: first) else { continue }
            summaries.append(try makeSummary(owner: owner, acceptedOutputs: outputs, allAcceptedOutputs: acceptedOutputs))
        }

        let sorted = summaries.sorted {
            if $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedSame {
                return $0.ref < $1.ref
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        if let limit { return Array(sorted.prefix(max(0, limit))) }
        return sorted
    }

    func inspect(selector: String) throws -> SecondBrainCanonicalEntityInspection {
        let summary = try resolve(selector: selector)
        let all = try listEntities()
        let conflicts = all.filter { candidate in
            candidate.owner != summary.owner
                && !Set(candidate.aliases.map(normalizeLookupToken)).isDisjoint(with: Set(summary.aliases.map(normalizeLookupToken)))
        }
        return SecondBrainCanonicalEntityInspection(
            summary: summary,
            sourceEvidence: summary.acceptedOutputs,
            relatedRelations: summary.acceptedRelations,
            conflicts: conflicts
        )
    }

    func resolve(selector: String) throws -> SecondBrainCanonicalEntitySummary {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SecondBrainCanonicalEntityLookupError.notFound(selector: selector) }
        let entities = try listEntities()
        if let exact = entities.first(where: { $0.ref == trimmed || $0.owner.ownerID == trimmed }) {
            return exact
        }

        let normalized = normalizeLookupToken(trimmed)
        let matches = entities.filter { entity in
            normalizeLookupToken(entity.displayName) == normalized
                || entity.aliases.map(normalizeLookupToken).contains(normalized)
                || normalizeLookupToken(entity.stableKey) == normalized
        }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { throw SecondBrainCanonicalEntityLookupError.ambiguous(selector: selector, matches: matches) }
        throw SecondBrainCanonicalEntityLookupError.notFound(selector: selector)
    }

    private func makeSummary(
        owner: SecondBrainOwnerRef,
        acceptedOutputs: [SecondBrainEnrichmentOutput],
        allAcceptedOutputs: [SecondBrainEnrichmentOutput]
    ) throws -> SecondBrainCanonicalEntitySummary {
        let stableKey = acceptedOutputs.first?.metadata["canonical_stable_key"]
            ?? acceptedOutputs.first.map { Self.stableKey(for: candidateMention(for: $0)) }
            ?? owner.ownerID
        let displayName = acceptedOutputs.first?.metadata["canonical_display_name"]
            ?? acceptedOutputs.first.map { Self.displayName(for: candidateMention(for: $0)) }
            ?? owner.ownerID
        let aliases = uniqueStrings(
            acceptedOutputs.flatMap { output in
                let stored = DatabaseHelpers.decodeStringArray(output.metadata["canonical_aliases"])
                return stored + [candidateMention(for: output), displayName]
            }
        )
        let possibleTypes = uniqueStrings(acceptedOutputs.flatMap { output in
            DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses])
        })
        let acceptedRelations = try store.relatedRelations(for: owner).filter { relation in
            relation.source == "graph_candidate.accept" || relation.metadata["candidate_ref"] != nil || relation.metadata["candidate_id"] != nil
        }
        let acceptedIDs = Set(acceptedOutputs.map(\.id))
        let reviewable = try outputService.outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: Set(SecondBrainGraphCandidateContract.ReviewState.allCases.filter(\.isReviewable).map(\.rawValue)),
            limit: nil
        ).filter { output in
            !acceptedIDs.contains(output.id)
                && Self.stableKey(for: candidateMention(for: output)) == stableKey
        }

        return SecondBrainCanonicalEntitySummary(
            owner: owner,
            stableKey: stableKey,
            displayName: displayName,
            aliases: aliases,
            possibleTypes: possibleTypes,
            acceptedOutputs: acceptedOutputs,
            acceptedRelations: acceptedRelations,
            reviewableCandidates: reviewable
        )
    }

    private func acceptedGraphOutputs() throws -> [SecondBrainEnrichmentOutput] {
        try outputService.outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: [SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue],
            limit: nil
        ).filter { acceptedTargetOwner(for: $0) != nil }
    }

    private func acceptedTargetOwner(for output: SecondBrainEnrichmentOutput) -> SecondBrainOwnerRef? {
        guard let type = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType],
              let id = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID],
              !type.isEmpty,
              !id.isEmpty else { return nil }
        return SecondBrainOwnerRef(ownerType: type, ownerID: id)
    }

    private func candidateMention(for output: SecondBrainEnrichmentOutput) -> String {
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mentionText] ?? output.value
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let key = normalizeLookupToken(value)
            if seen.insert(key).inserted { output.append(value) }
        }
        return output
    }

    private func normalizeLookupToken(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9:]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func stableKey(for mentionText: String) -> String {
        let slug = mentionText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "graph_object:\(slug.isEmpty ? "unknown" : slug)"
    }

    static func displayName(for mentionText: String) -> String {
        let normalized = mentionText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Unknown Object" }
        return normalized.split(separator: " ").map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }
}
