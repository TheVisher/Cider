import Foundation

struct SecondBrainGraphCandidateExtractionResult: Equatable {
    var owner: SecondBrainOwnerRef
    var candidates: [SecondBrainEnrichmentOutput]
    var agentAction: SecondBrainAgentAction?
}

struct SecondBrainGraphCandidateReviewResult: Equatable {
    var candidate: SecondBrainEnrichmentOutput
    var status: String
    var message: String
    var createdOwners: [SecondBrainOwnerRef]
    var relations: [SecondBrainRelation]
    var agentAction: SecondBrainAgentAction
}

@MainActor
final class SecondBrainGraphCandidateService {
    enum GraphCandidateError: LocalizedError, Equatable {
        case missingSource
        case candidateNotFound(String)
        case unsupportedCandidate(String)
        case invalidReviewState(String)
        case unresolvedOwner(String)

        var errorDescription: String? {
            switch self {
            case .missingSource:
                return "Graph candidate extraction needs source text or source URL."
            case .candidateNotFound(let id):
                return "Graph candidate '\(id)' was not found."
            case .unsupportedCandidate(let id):
                return "Enrichment output '\(id)' is not a graph candidate."
            case .invalidReviewState(let state):
                return "Graph candidate cannot be accepted from review state '\(state)'."
            case .unresolvedOwner(let ref):
                return "Could not resolve owner '\(ref)'."
            }
        }
    }

    static let outputKind = "graph_candidate"
    static let sourceName = "graph_candidate.prototype"

    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService
    private let store: SecondBrainStore

    init(
        database: CiderDatabase = .shared,
        outputService: SecondBrainEnrichmentOutputService? = nil,
        store: SecondBrainStore? = nil
    ) {
        self.database = database
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
        self.store = store ?? SecondBrainStore(database: database)
    }

    @discardableResult
    func extract(
        owner: SecondBrainOwnerRef,
        sourceText: String?,
        sourceURL: String? = nil,
        sourceKind: String = "source",
        title: String? = nil,
        date: String? = nil
    ) throws -> SecondBrainGraphCandidateExtractionResult {
        let text = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty || !url.isEmpty else { throw GraphCandidateError.missingSource }

        var drafts: [GraphCandidateDraft] = []
        if !text.isEmpty {
            drafts.append(contentsOf: journalPreferenceDrafts(owner: owner, text: text, sourceKind: sourceKind, date: date))
            drafts.append(contentsOf: mediaDrafts(owner: owner, text: text, sourceKind: sourceKind, date: date))
            drafts.append(contentsOf: placeDrafts(owner: owner, text: text, sourceKind: sourceKind, date: date))
        }
        if !url.isEmpty {
            drafts.append(contentsOf: urlDrafts(owner: owner, url: url, title: title, sourceKind: sourceKind))
        }

        let uniqueDrafts = unique(drafts)
        let outputs = uniqueDrafts.map { $0.output }
        let action: SecondBrainAgentAction?
        if outputs.isEmpty {
            action = nil
        } else {
            action = SecondBrainAgentAction(
                owner: owner,
                itemID: itemID(for: owner),
                toolName: "cider-cli item extract-graph-candidates",
                actionType: "graph_candidates_extracted",
                source: Self.sourceName,
                status: "suggested",
                summary: "Extracted \(outputs.count) reviewable graph candidate(s) for \(owner.canonicalRef).",
                argumentsJSON: DatabaseHelpers.encodeJSON([
                    "sourceKind": sourceKind,
                    "sourceURL": url,
                    "date": date ?? "",
                ]),
                resultJSON: DatabaseHelpers.encodeJSON([
                    "candidateIDs": outputs.map(\.id).joined(separator: ","),
                    "candidateCount": String(outputs.count),
                ])
            )
        }

        try database.withTransaction {
            for output in outputs {
                try outputService.record(output)
            }
            if let action {
                try store.recordAgentAction(action)
            }
        }

        return SecondBrainGraphCandidateExtractionResult(owner: owner, candidates: outputs, agentAction: action)
    }

    func candidates(
        owner: SecondBrainOwnerRef? = nil,
        includeReviewed: Bool = false,
        limit: Int? = nil
    ) throws -> [SecondBrainEnrichmentOutput] {
        let states: Set<String>? = includeReviewed ? nil : ["suggested", "needs_review", "deferred"]
        let all = try outputService.outputs(kind: Self.outputKind, reviewStates: states, limit: limit)
        guard let owner else { return all }
        return all.filter { $0.owner == owner }
    }

    @discardableResult
    func accept(
        candidateID: String,
        actor: String = "agent",
        targetOwner overrideTargetOwner: SecondBrainOwnerRef? = nil,
        relationType overrideRelationType: String? = nil
    ) throws -> SecondBrainGraphCandidateReviewResult {
        var candidate = try graphCandidate(id: candidateID)
        guard ["suggested", "needs_review", "deferred"].contains(candidate.reviewState) else {
            throw GraphCandidateError.invalidReviewState(candidate.reviewState)
        }

        let sourceOwner = sourceOwner(for: candidate)
        let sourceQuote = candidate.metadata["source_quote"] ?? candidate.evidence
        let relationType = overrideRelationType?.trimmedNonEmpty
            ?? candidate.metadata["accepted_relation_type"]?.trimmedNonEmpty
            ?? firstJSONValue(candidate.metadata["relation_guesses"])
            ?? "mentions"
        let targetOwner = overrideTargetOwner ?? acceptedTargetOwner(for: candidate)
        var createdOwners: [SecondBrainOwnerRef] = []
        var relations: [SecondBrainRelation] = []
        var reviewResult: SecondBrainGraphCandidateReviewResult?

        try database.withTransaction {
            if shouldProject(owner: targetOwner) {
                try upsertGraphObjectOwner(targetOwner, from: candidate)
                createdOwners.append(targetOwner)
            }

            let sourceRelation = relation(
                sourceOwner: sourceOwner,
                targetOwner: targetOwner,
                relationType: relationType,
                evidence: sourceQuote,
                actor: actor,
                candidate: candidate
            )
            try store.recordRelation(sourceRelation)
            relations.append(sourceRelation)

            if let subjectOwner = subjectOwner(for: candidate), subjectOwner != targetOwner {
                if shouldProject(owner: subjectOwner) {
                    try upsertSubjectOwner(subjectOwner, from: candidate)
                    createdOwners.append(subjectOwner)
                }
                let subjectRelation = relation(
                    sourceOwner: subjectOwner,
                    targetOwner: targetOwner,
                    relationType: relationType,
                    evidence: sourceQuote,
                    actor: actor,
                    candidate: candidate
                )
                try store.recordRelation(subjectRelation)
                relations.append(subjectRelation)

                let mentionRelation = relation(
                    sourceOwner: sourceOwner,
                    targetOwner: subjectOwner,
                    relationType: "mentions",
                    evidence: sourceQuote,
                    actor: actor,
                    candidate: candidate
                )
                try store.recordRelation(mentionRelation)
                relations.append(mentionRelation)
            }

            candidate.metadata["accepted_target_owner_type"] = targetOwner.ownerType
            candidate.metadata["accepted_target_owner_id"] = targetOwner.ownerID
            candidate.metadata["accepted_relation_type"] = relationType
            candidate.metadata["accepted_at"] = ISO8601DateFormatter().string(from: Date())
            try outputService.updateReviewState(id: candidate.id, reviewState: "accepted", metadata: candidate.metadata)

            let action = SecondBrainAgentAction(
                owner: sourceOwner,
                itemID: itemID(for: sourceOwner),
                toolName: "cider-cli item accept-graph-candidate",
                actionType: "graph_candidate_accepted",
                source: Self.sourceName,
                status: "accepted",
                summary: "Accepted graph candidate \(candidate.id) as \(relationType) relation.",
                argumentsJSON: DatabaseHelpers.encodeJSON([
                    "candidateID": candidate.id,
                    "actor": actor,
                ]),
                resultJSON: DatabaseHelpers.encodeJSON([
                    "targetOwner": targetOwner.canonicalRef,
                    "relationType": relationType,
                    "relationCount": String(relations.count),
                ])
            )
            try store.recordAgentAction(action)
            candidate.reviewState = "accepted"
            candidate.updatedAt = Date()
            candidate.metadata["accepted_target_owner_type"] = targetOwner.ownerType
            candidate.metadata["accepted_target_owner_id"] = targetOwner.ownerID
            candidate.metadata["accepted_relation_type"] = relationType
            candidate.metadata["accepted_at"] = candidate.metadata["accepted_at"] ?? ISO8601DateFormatter().string(from: Date())
            reviewResult = SecondBrainGraphCandidateReviewResult(
                candidate: candidate,
                status: "accepted",
                message: "Accepted graph candidate and recorded source-backed relation(s).",
                createdOwners: orderedUniqueOwners(createdOwners),
                relations: relations,
                agentAction: action
            )
        }
        return reviewResult!
    }

    @discardableResult
    func reject(candidateID: String, actor: String = "agent", reason: String? = nil) throws -> SecondBrainGraphCandidateReviewResult {
        var candidate = try graphCandidate(id: candidateID)
        let owner = sourceOwner(for: candidate)
        candidate.metadata["rejected_reason"] = reason?.trimmedNonEmpty ?? "Rejected by reviewer."
        candidate.metadata["rejected_at"] = ISO8601DateFormatter().string(from: Date())
        let action = SecondBrainAgentAction(
            owner: owner,
            itemID: itemID(for: owner),
            toolName: "cider-cli item reject-graph-candidate",
            actionType: "graph_candidate_rejected",
            source: Self.sourceName,
            status: "rejected",
            summary: "Rejected graph candidate \(candidate.id).",
            argumentsJSON: DatabaseHelpers.encodeJSON([
                "candidateID": candidate.id,
                "actor": actor,
                "reason": candidate.metadata["rejected_reason"] ?? "",
            ]),
            resultJSON: nil
        )

        try database.withTransaction {
            try outputService.updateReviewState(id: candidate.id, reviewState: "rejected", metadata: candidate.metadata)
            try store.recordAgentAction(action)
        }
        candidate.reviewState = "rejected"
        return SecondBrainGraphCandidateReviewResult(
            candidate: candidate,
            status: "rejected",
            message: "Rejected graph candidate; no graph truth was created.",
            createdOwners: [],
            relations: [],
            agentAction: action
        )
    }

    @discardableResult
    func delegate(candidateID: String, actor: String = "agent") throws -> SecondBrainGraphCandidateReviewResult {
        var candidate = try graphCandidate(id: candidateID)
        let owner = sourceOwner(for: candidate)
        candidate.metadata["delegation_status"] = "requested"
        candidate.metadata["delegated_at"] = ISO8601DateFormatter().string(from: Date())
        candidate.metadata["delegation_note"] = "Prototype action only: ask an LLM/web agent for possible matches, then write results back as reviewable evidence."
        let action = SecondBrainAgentAction(
            owner: owner,
            itemID: itemID(for: owner),
            toolName: "cider-cli item delegate-graph-candidate",
            actionType: "graph_candidate_delegation_requested",
            source: Self.sourceName,
            status: "suggested",
            summary: "Prepared delegated enrichment request for graph candidate \(candidate.id).",
            argumentsJSON: DatabaseHelpers.encodeJSON([
                "candidateID": candidate.id,
                "actor": actor,
            ]),
            resultJSON: DatabaseHelpers.encodeJSON([
                "reviewState": candidate.reviewState,
                "note": candidate.metadata["delegation_note"] ?? "",
            ])
        )
        try database.withTransaction {
            try outputService.updateReviewState(id: candidate.id, reviewState: candidate.reviewState, metadata: candidate.metadata)
            try store.recordAgentAction(action)
        }
        return SecondBrainGraphCandidateReviewResult(
            candidate: candidate,
            status: "delegation_requested",
            message: "Delegation request recorded as reviewable evidence; no graph truth was created.",
            createdOwners: [],
            relations: [],
            agentAction: action
        )
    }

    private struct GraphCandidateDraft: Equatable {
        var output: SecondBrainEnrichmentOutput
    }

    private func journalPreferenceDrafts(
        owner: SecondBrainOwnerRef,
        text: String,
        sourceKind: String,
        date: String?
    ) -> [GraphCandidateDraft] {
        var drafts: [GraphCandidateDraft] = []
        let gavePattern = #"\b(?:gave|Gave)\s+([A-Z][A-Za-z'-]+)\s+(?:that|the|a|an)?\s*([A-Za-z][A-Za-z\s'-]*?(?:drink|margarita|coffee|tea|cocktail|juice|smoothie))\s+and\s+(?:she|he|they)\s+(?:loved|liked)\s+it"#
        for match in regexMatches(pattern: gavePattern, in: text) {
            guard match.captures.count >= 2 else { continue }
            let object = preferenceObject(match.captures[1])
            drafts.append(candidateDraft(
                owner: owner,
                value: "\(match.captures[0]) likes \(object)",
                label: "Review contact drink preference",
                sourceKind: sourceKind,
                sourceQuote: quote(from: text, range: match.range),
                mentionText: object,
                subjectText: match.captures[0],
                objectText: object,
                candidateScope: "relation",
                typeGuesses: ["contact_preference", "drink"],
                relationGuesses: ["likes_drink"],
                actionGuess: "liked",
                acceptedRelationType: "likes_drink",
                confidence: 0.86,
                reason: "Matched explicit gave/loved-it preference phrasing.",
                reviewPrompt: "Confirm whether \(match.captures[0]) likes \(object).",
                date: date
            ))
        }

        let likedPattern = #"\b([A-Z][A-Za-z'-]+)\s+(?:really\s+)?(?:liked|loved)\s+(?:the|that|a|an)?\s*([A-Za-z][A-Za-z\s'-]*?(?:drink|margarita|coffee|tea|cocktail|juice|smoothie))"#
        for match in regexMatches(pattern: likedPattern, in: text) {
            guard match.captures.count >= 2 else { continue }
            let object = preferenceObject(match.captures[1])
            drafts.append(candidateDraft(
                owner: owner,
                value: "\(match.captures[0]) likes \(object)",
                label: "Review contact drink preference",
                sourceKind: sourceKind,
                sourceQuote: quote(from: text, range: match.range),
                mentionText: object,
                subjectText: match.captures[0],
                objectText: object,
                candidateScope: "relation",
                typeGuesses: ["contact_preference", "drink"],
                relationGuesses: ["likes_drink"],
                actionGuess: "liked",
                acceptedRelationType: "likes_drink",
                confidence: 0.78,
                reason: "Matched explicit person liked drink phrasing.",
                reviewPrompt: "Confirm whether \(match.captures[0]) likes \(object).",
                date: date
            ))
        }
        return drafts
    }

    private func mediaDrafts(
        owner: SecondBrainOwnerRef,
        text: String,
        sourceKind: String,
        date: String?
    ) -> [GraphCandidateDraft] {
        let pattern = #"\b(?:watched|Watched|saw|Saw)\s+([A-Z][A-Za-z0-9'&:-]*(?:\s+[A-Z][A-Za-z0-9'&:-]*){1,6})(?=\s+(?:last night|yesterday|today)|[\.\!,]|$)"#
        return regexMatches(pattern: pattern, in: text).map { match in
            let title = cleanupTitle(match.captures.first ?? "")
            return candidateDraft(
                owner: owner,
                value: "Possible movie: \(title)",
                label: "Review media object candidate",
                sourceKind: sourceKind,
                sourceQuote: quote(from: text, range: match.range),
                mentionText: title,
                subjectText: nil,
                objectText: title,
                candidateScope: "object_relation",
                typeGuesses: ["movie", "media_item"],
                relationGuesses: ["watched"],
                actionGuess: text.localizedCaseInsensitiveContains("last night") ? "watched_last_night" : "watched",
                acceptedRelationType: "watched",
                confidence: 0.74,
                reason: "Matched watched/saw media phrasing; object is unresolved until reviewed.",
                reviewPrompt: "Create or link a media item for \(title)?",
                date: date,
                extraMetadata: [
                    "possible_external_matches": encodeStringArray([
                        "IMDb search: \(title)",
                        "TMDb search: \(title)",
                        "Letterboxd search: \(title)",
                    ]),
                ]
            )
        }
    }

    private func placeDrafts(
        owner: SecondBrainOwnerRef,
        text: String,
        sourceKind: String,
        date: String?
    ) -> [GraphCandidateDraft] {
        let pattern = #"\b(?:went to|Went to|visited|Visited|ate at|Ate at)\s+([A-Z][A-Za-z0-9'&-]*(?:\s+[A-Z][A-Za-z0-9'&-]*){0,3})"#
        return regexMatches(pattern: pattern, in: text).map { match in
            let place = cleanupTitle(match.captures.first ?? "")
            return candidateDraft(
                owner: owner,
                value: "Ambiguous place/object: \(place)",
                label: "Review ambiguous object candidate",
                sourceKind: sourceKind,
                sourceQuote: quote(from: text, range: match.range),
                mentionText: place,
                subjectText: nil,
                objectText: place,
                candidateScope: "object_relation",
                typeGuesses: ["place", "restaurant", "object", "topic"],
                relationGuesses: ["visited"],
                actionGuess: "visited",
                acceptedRelationType: "visited",
                confidence: 0.55,
                reason: "Matched went-to/visited phrasing, but the object type is ambiguous.",
                reviewPrompt: "What is \(place) here?",
                date: date,
                extraMetadata: [
                    "review_choices": encodeStringArray([
                        "Restaurant/place",
                        "Plant/object",
                        "Existing note/topic",
                        "Ignore/wrong extraction",
                        "Delegate enrichment",
                    ]),
                ]
            )
        }
    }

    private func urlDrafts(
        owner: SecondBrainOwnerRef,
        url: String,
        title: String?,
        sourceKind: String
    ) -> [GraphCandidateDraft] {
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased() else { return [] }
        let display = cleanupTitle(title?.trimmedNonEmpty ?? parsed.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "))
        let classification: (types: [String], relation: String, confidence: Double, prompt: String)?
        if host.contains("imdb.com") || host.contains("themoviedb.org") || host.contains("letterboxd.com") {
            classification = (["media_item", "movie"], "represents", 0.82, "What media item does this URL represent?")
        } else if host.contains("youtube.com") || host.contains("youtu.be") || host.contains("vimeo.com") {
            classification = (["media_item", "video"], "represents", 0.76, "What video/media object does this URL represent?")
        } else if host.contains("github.com") {
            classification = (["project", "repository"], "source_for", 0.72, "What project or repository does this URL document?")
        } else if host.contains("allrecipes") || host.contains("seriouseats") || host.contains("smittenkitchen") {
            classification = (["recipe", "food"], "represents", 0.7, "What recipe does this URL represent?")
        } else {
            classification = nil
        }
        guard let classification else { return [] }
        return [
            candidateDraft(
                owner: owner,
                value: "\(classification.relation): \(display)",
                label: "Review URL represented object",
                sourceKind: sourceKind,
                sourceQuote: url,
                mentionText: display,
                subjectText: nil,
                objectText: display,
                candidateScope: "object_relation",
                typeGuesses: classification.types,
                relationGuesses: [classification.relation, "source_for"],
                actionGuess: "url_represents_object",
                acceptedRelationType: classification.relation,
                confidence: classification.confidence,
                reason: "Classified URL host \(host) as \(classification.types.joined(separator: "/")).",
                reviewPrompt: classification.prompt,
                date: nil,
                sourceURL: url,
                extraMetadata: [
                    "url_host": host,
                    "url_path": parsed.path,
                ]
            ),
        ]
    }

    private func candidateDraft(
        owner: SecondBrainOwnerRef,
        value: String,
        label: String,
        sourceKind: String,
        sourceQuote: String,
        mentionText: String,
        subjectText: String?,
        objectText: String,
        candidateScope: String,
        typeGuesses: [String],
        relationGuesses: [String],
        actionGuess: String,
        acceptedRelationType: String,
        confidence: Double,
        reason: String,
        reviewPrompt: String,
        date: String?,
        sourceURL: String? = nil,
        extraMetadata: [String: String] = [:]
    ) -> GraphCandidateDraft {
        var metadata: [String: String] = [
            "candidate_kind": candidateScope,
            "candidate_scope": candidateScope,
            "source_owner_type": owner.ownerType,
            "source_owner_id": owner.ownerID,
            "source_kind": sourceKind,
            "source_quote": sourceQuote,
            "mention_text": mentionText,
            "object_text": objectText,
            "type_guesses": encodeStringArray(typeGuesses),
            "relation_guesses": encodeStringArray(relationGuesses),
            "action_guess": actionGuess,
            "accepted_relation_type": acceptedRelationType,
            "confidence_reason": reason,
            "review_prompt": reviewPrompt,
            "safe_actions": encodeStringArray(["accept", "reject", "correct", "delegate_enrichment"]),
            "requires_review": "true",
            "prototype": "true",
        ]
        if let subject = subjectText?.trimmedNonEmpty {
            metadata["subject_text"] = subject
            metadata["subject_owner_type_guess"] = "contact"
        }
        if let date {
            metadata["source_date"] = date
        }
        if let sourceURL {
            metadata["source_url"] = sourceURL
        }
        metadata.merge(extraMetadata) { _, new in new }

        let normalized = [
            owner.canonicalRef,
            candidateScope,
            acceptedRelationType,
            subjectText ?? "",
            objectText,
            mentionText,
        ].joined(separator: "|").normalizedGraphToken

        let output = SecondBrainEnrichmentOutput(
            owner: owner,
            kind: Self.outputKind,
            value: value,
            normalizedValue: normalized,
            label: label,
            evidence: sourceQuote,
            source: Self.sourceName,
            confidence: confidence,
            reviewState: confidence < 0.65 ? "needs_review" : "suggested",
            metadata: metadata
        )
        return GraphCandidateDraft(output: output)
    }

    private func graphCandidate(id: String) throws -> SecondBrainEnrichmentOutput {
        guard let candidate = try outputService.output(id: id) else {
            throw GraphCandidateError.candidateNotFound(id)
        }
        guard candidate.kind == Self.outputKind else {
            throw GraphCandidateError.unsupportedCandidate(id)
        }
        return candidate
    }

    private func sourceOwner(for candidate: SecondBrainEnrichmentOutput) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(
            ownerType: candidate.metadata["source_owner_type"] ?? candidate.owner.ownerType,
            ownerID: candidate.metadata["source_owner_id"] ?? candidate.owner.ownerID
        )
    }

    private func acceptedTargetOwner(for candidate: SecondBrainEnrichmentOutput) -> SecondBrainOwnerRef {
        if let type = candidate.metadata["target_owner_type"]?.trimmedNonEmpty,
           let id = candidate.metadata["target_owner_id"]?.trimmedNonEmpty {
            return SecondBrainOwnerRef(ownerType: type, ownerID: id)
        }
        let guesses = decodeStringArray(candidate.metadata["type_guesses"])
        let objectType = guesses.first ?? "object"
        let text = candidate.metadata["object_text"]?.trimmedNonEmpty ?? candidate.metadata["mention_text"] ?? candidate.value
        return SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "\(objectType):\(text.normalizedGraphToken)")
    }

    private func subjectOwner(for candidate: SecondBrainEnrichmentOutput) -> SecondBrainOwnerRef? {
        guard let subject = candidate.metadata["subject_text"]?.trimmedNonEmpty else { return nil }
        return SecondBrainOwnerRef(ownerType: "graph_contact", ownerID: subject.normalizedGraphToken)
    }

    private func upsertGraphObjectOwner(_ owner: SecondBrainOwnerRef, from candidate: SecondBrainEnrichmentOutput) throws {
        let objectText = candidate.metadata["object_text"]?.trimmedNonEmpty ?? candidate.value
        let typeGuesses = decodeStringArray(candidate.metadata["type_guesses"]).joined(separator: ", ")
        let quote = candidate.metadata["source_quote"] ?? candidate.evidence
        try store.upsertSection(SecondBrainSection(
            owner: owner,
            itemID: nil,
            sectionKey: "identity",
            title: objectText,
            body: "Prototype graph object candidate.\nTypes: \(typeGuesses)\nSource quote: \(quote)",
            source: Self.sourceName,
            confidence: candidate.confidence,
            metadata: [
                "candidate_id": candidate.id,
                "review_state": "accepted",
            ],
            sortOrder: 0
        ))
    }

    private func upsertSubjectOwner(_ owner: SecondBrainOwnerRef, from candidate: SecondBrainEnrichmentOutput) throws {
        let subject = candidate.metadata["subject_text"]?.trimmedNonEmpty ?? owner.ownerID
        let quote = candidate.metadata["source_quote"] ?? candidate.evidence
        try store.upsertSection(SecondBrainSection(
            owner: owner,
            itemID: nil,
            sectionKey: "identity",
            title: subject,
            body: "Prototype graph contact candidate.\nSource quote: \(quote)",
            source: Self.sourceName,
            confidence: candidate.confidence,
            metadata: [
                "candidate_id": candidate.id,
                "review_state": "accepted",
            ],
            sortOrder: 0
        ))
    }

    private func relation(
        sourceOwner: SecondBrainOwnerRef,
        targetOwner: SecondBrainOwnerRef,
        relationType: String,
        evidence: String,
        actor: String,
        candidate: SecondBrainEnrichmentOutput
    ) -> SecondBrainRelation {
        SecondBrainRelation(
            sourceOwner: sourceOwner,
            targetOwner: targetOwner,
            relationType: relationType,
            evidence: evidence,
            source: Self.sourceName,
            actor: actor,
            confidence: candidate.confidence,
            metadata: [
                "candidate_id": candidate.id,
                "source_quote": candidate.metadata["source_quote"] ?? candidate.evidence,
                "mention_text": candidate.metadata["mention_text"] ?? "",
                "object_text": candidate.metadata["object_text"] ?? "",
                "subject_text": candidate.metadata["subject_text"] ?? "",
                "prototype": "true",
            ]
        )
    }

    private func shouldProject(owner: SecondBrainOwnerRef) -> Bool {
        owner.ownerType == "graph_object" || owner.ownerType == "graph_contact"
    }

    private func itemID(for owner: SecondBrainOwnerRef) -> String? {
        switch owner.ownerType {
        case "bookmark", "note", "dateCard", "contact", "todo", "vaultFile":
            return UUID(uuidString: owner.ownerID) == nil ? nil : owner.ownerID
        default:
            return nil
        }
    }

    private func unique(_ drafts: [GraphCandidateDraft]) -> [GraphCandidateDraft] {
        var seen = Set<String>()
        return drafts.filter { draft in
            seen.insert(draft.output.normalizedValue).inserted
        }
    }

    private func orderedUniqueOwners(_ owners: [SecondBrainOwnerRef]) -> [SecondBrainOwnerRef] {
        var seen = Set<SecondBrainOwnerRef>()
        return owners.filter { seen.insert($0).inserted }
    }

    private func firstJSONValue(_ value: String?) -> String? {
        decodeStringArray(value).first
    }

    private func encodeStringArray(_ values: [String]) -> String {
        DatabaseHelpers.encodeJSON(values) ?? "[]"
    }

    private func decodeStringArray(_ value: String?) -> [String] {
        DatabaseHelpers.decodeJSON([String].self, from: value) ?? []
    }

    private func regexMatches(pattern: String, in text: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { result in
            let captures = (1..<result.numberOfRanges).compactMap { index -> String? in
                let range = result.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return RegexMatch(range: result.range, captures: captures)
        }
    }

    private func quote(from text: String, range: NSRange) -> String {
        let nsText = text as NSString
        guard range.location != NSNotFound else { return text }
        return nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?:;")))
    }

    private func preferenceObject(_ value: String) -> String {
        cleanupTitle(value)
            .replacingOccurrences(of: #"^(?:the|that|a|an)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private struct RegexMatch {
        var range: NSRange
        var captures: [String]
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedGraphToken: String {
        let allowed = unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar).lowercased())
            }
            return "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "object" : collapsed
    }
}
