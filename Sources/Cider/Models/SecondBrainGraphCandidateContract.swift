import Foundation

/// Stable contract for source-backed object and relation suggestions.
///
/// Graph candidates are stored as `enrichment_outputs` rows with
/// `kind == "graph_candidate"`. The source owner is the enrichment output
/// owner, the source quote is stored in `evidence`, and metadata carries typed
/// guesses until an explicit accept path promotes the candidate into graph truth.
enum SecondBrainGraphCandidateContract {
    static let outputKind = "graph_candidate"
    static let metadataVersion = "1"

    enum CandidateKind: String, Codable, CaseIterable {
        case object
        case relation
        case objectRelation = "object_relation"
    }

    enum ReviewState: String, Codable, CaseIterable {
        case suggested
        case needsReview = "needs_review"
        case deferred
        case accepted
        case rejected

        var isReviewable: Bool {
            switch self {
            case .suggested, .needsReview, .deferred:
                return true
            case .accepted, .rejected:
                return false
            }
        }
    }

    enum ObjectType: String, Codable, CaseIterable {
        case contact
        case person
        case place
        case restaurant
        case media
        case movie
        case show
        case video
        case book
        case music
        case recipe
        case food
        case drink
        case product
        case project
        case trip
        case reminder
        case event
        case note
        case file
        case url
        case topic
        case object
    }

    enum RelationType: String, Codable, CaseIterable {
        case mentions
        case represents
        case sourceFor = "source_for"
        case watched
        case read
        case listenedTo = "listened_to"
        case visited
        case likes
        case likesDrink = "likes_drink"
        case likesFood = "likes_food"
        case dislikes
        case includes
        case reminderFrom = "reminder_from"
        case happenedAt = "happened_at"
        case gifted
        case wants
        case owns
        case bought
        case cooked
        case ate
        case drank
        case relatedTo = "related_to"
    }

    enum SafeAction: String, Codable, CaseIterable {
        case inspectSource = "inspect_source"
        case linkExisting = "link_existing"
        case createObject = "create_object"
        case createRelation = "create_relation"
        case accept
        case reject
        case correct
        case deferCandidate = "defer"
        case delegateEnrichment = "delegate_enrichment"
        case searchExternal = "search_external"
    }

    enum MetadataKey {
        static let version = "graph_candidate_version"
        static let candidateKind = "candidate_kind"
        static let sourceOwnerRef = "source_owner_ref"
        static let sourceKind = "source_kind"
        static let sourceQuote = "source_quote"
        static let mentionText = "mention_text"
        static let objectTypeGuesses = "object_type_guesses"
        static let relationGuesses = "relation_guesses"
        static let actionGuesses = "action_guesses"
        static let safeActions = "safe_actions"
        static let confidenceReason = "confidence_reason"
        static let subjectText = "subject_text"
        static let subjectOwnerType = "subject_owner_type"
        static let subjectOwnerID = "subject_owner_id"
        static let acceptedTargetOwnerType = "accepted_target_owner_type"
        static let acceptedTargetOwnerID = "accepted_target_owner_id"
        static let acceptedRelationType = "accepted_relation_type"
    }

    struct Candidate: Equatable {
        var id: String
        var sourceOwner: SecondBrainOwnerRef
        var kind: CandidateKind
        var mentionText: String
        var sourceQuote: String
        var sourceKind: String?
        var objectTypeGuesses: [ObjectType]
        var relationGuesses: [RelationType]
        var actionGuesses: [String]
        var safeActions: [SafeAction]
        var confidence: Double?
        var confidenceReason: String?
        var reviewState: ReviewState
        var subjectText: String?
        var subjectOwner: SecondBrainOwnerRef?
        var acceptedTargetOwner: SecondBrainOwnerRef?
        var acceptedRelationType: RelationType?
    }

    enum ValidationError: LocalizedError, Equatable {
        case wrongKind(String)
        case missingMentionText
        case missingSourceQuote
        case invalidCandidateKind(String)
        case invalidReviewState(String)
        case invalidConfidence(Double)
        case missingObjectTypeGuess
        case missingRelationGuess
        case missingAcceptedTarget
        case missingAcceptedRelationType

        var errorDescription: String? {
            switch self {
            case .wrongKind(let kind):
                return "Expected enrichment output kind '\(SecondBrainGraphCandidateContract.outputKind)', got '\(kind)'."
            case .missingMentionText:
                return "Graph candidate requires a mention text."
            case .missingSourceQuote:
                return "Graph candidate requires a source quote in evidence."
            case .invalidCandidateKind(let kind):
                return "Unsupported graph candidate kind '\(kind)'."
            case .invalidReviewState(let state):
                return "Unsupported graph candidate review state '\(state)'."
            case .invalidConfidence(let confidence):
                return "Graph candidate confidence must be between 0 and 1; got \(confidence)."
            case .missingObjectTypeGuess:
                return "Object graph candidates require at least one object type guess."
            case .missingRelationGuess:
                return "Relation graph candidates require at least one relation guess."
            case .missingAcceptedTarget:
                return "Accepted graph candidates require accepted target owner metadata."
            case .missingAcceptedRelationType:
                return "Accepted relation graph candidates require accepted relation type metadata."
            }
        }
    }

    static func makeOutput(
        sourceOwner: SecondBrainOwnerRef,
        candidateKind: CandidateKind,
        mentionText rawMentionText: String,
        sourceQuote rawSourceQuote: String,
        sourceKind: String? = nil,
        objectTypeGuesses: [ObjectType] = [],
        relationGuesses: [RelationType] = [],
        actionGuesses: [String] = [],
        safeActions: [SafeAction] = [.inspectSource, .correct, .reject, .delegateEnrichment],
        confidence: Double? = nil,
        confidenceReason: String? = nil,
        reviewState: ReviewState = .suggested,
        subjectText: String? = nil,
        subjectOwner: SecondBrainOwnerRef? = nil,
        acceptedTargetOwner: SecondBrainOwnerRef? = nil,
        acceptedRelationType: RelationType? = nil,
        source: String = "graph_candidate.contract"
    ) throws -> SecondBrainEnrichmentOutput {
        if let confidence, confidence < 0 || confidence > 1 {
            throw ValidationError.invalidConfidence(confidence)
        }

        let mentionText = normalizedWhitespace(rawMentionText)
        guard !mentionText.isEmpty else { throw ValidationError.missingMentionText }

        let sourceQuote = normalizedWhitespace(rawSourceQuote)
        guard !sourceQuote.isEmpty else { throw ValidationError.missingSourceQuote }

        var metadata: [String: String] = [
            MetadataKey.version: metadataVersion,
            MetadataKey.candidateKind: candidateKind.rawValue,
            MetadataKey.sourceOwnerRef: sourceOwner.canonicalRef,
            MetadataKey.sourceQuote: sourceQuote,
            MetadataKey.mentionText: mentionText,
            MetadataKey.objectTypeGuesses: encodeStringArray(objectTypeGuesses.map(\.rawValue)),
            MetadataKey.relationGuesses: encodeStringArray(relationGuesses.map(\.rawValue)),
            MetadataKey.actionGuesses: encodeStringArray(actionGuesses),
            MetadataKey.safeActions: encodeStringArray(safeActions.map(\.rawValue)),
        ]
        metadata[MetadataKey.sourceKind] = sourceKind.flatMap(trimmedNonEmpty)
        metadata[MetadataKey.confidenceReason] = confidenceReason.flatMap(trimmedNonEmpty)
        metadata[MetadataKey.subjectText] = subjectText.flatMap(trimmedNonEmpty)
        metadata[MetadataKey.subjectOwnerType] = subjectOwner?.ownerType
        metadata[MetadataKey.subjectOwnerID] = subjectOwner?.ownerID
        metadata[MetadataKey.acceptedTargetOwnerType] = acceptedTargetOwner?.ownerType
        metadata[MetadataKey.acceptedTargetOwnerID] = acceptedTargetOwner?.ownerID
        metadata[MetadataKey.acceptedRelationType] = acceptedRelationType?.rawValue

        let label = labelForCandidate(kind: candidateKind, objectTypes: objectTypeGuesses, relations: relationGuesses)
        let output = SecondBrainEnrichmentOutput(
            owner: sourceOwner,
            chunkID: nil,
            kind: outputKind,
            value: mentionText,
            normalizedValue: normalizedValue(mentionText),
            label: label,
            evidence: sourceQuote,
            source: source,
            confidence: confidence,
            reviewState: reviewState.rawValue,
            metadata: metadata
        )
        try validate(output)
        return output
    }

    @discardableResult
    static func validate(_ output: SecondBrainEnrichmentOutput) throws -> Candidate {
        guard output.kind == outputKind else { throw ValidationError.wrongKind(output.kind) }
        if let confidence = output.confidence, confidence < 0 || confidence > 1 {
            throw ValidationError.invalidConfidence(confidence)
        }

        guard let reviewState = ReviewState(rawValue: output.reviewState) else {
            throw ValidationError.invalidReviewState(output.reviewState)
        }
        guard let kind = CandidateKind(rawValue: output.metadata[MetadataKey.candidateKind] ?? "") else {
            throw ValidationError.invalidCandidateKind(output.metadata[MetadataKey.candidateKind] ?? "")
        }

        let mentionText = trimmedNonEmpty(output.metadata[MetadataKey.mentionText] ?? output.value)
        guard let mentionText else { throw ValidationError.missingMentionText }

        let sourceQuote = trimmedNonEmpty(output.evidence)
        guard let sourceQuote else { throw ValidationError.missingSourceQuote }

        let objectTypes = decodedEnumArray(ObjectType.self, from: output.metadata[MetadataKey.objectTypeGuesses])
        let relations = decodedEnumArray(RelationType.self, from: output.metadata[MetadataKey.relationGuesses])
        switch kind {
        case .object:
            guard !objectTypes.isEmpty else { throw ValidationError.missingObjectTypeGuess }
        case .relation:
            guard !relations.isEmpty else { throw ValidationError.missingRelationGuess }
        case .objectRelation:
            guard !objectTypes.isEmpty else { throw ValidationError.missingObjectTypeGuess }
            guard !relations.isEmpty else { throw ValidationError.missingRelationGuess }
        }

        let acceptedTargetOwner = ownerRef(
            type: output.metadata[MetadataKey.acceptedTargetOwnerType],
            id: output.metadata[MetadataKey.acceptedTargetOwnerID]
        )
        let acceptedRelation = output.metadata[MetadataKey.acceptedRelationType].flatMap(RelationType.init(rawValue:))
        if reviewState == .accepted {
            guard acceptedTargetOwner != nil else { throw ValidationError.missingAcceptedTarget }
            if kind != .object {
                guard acceptedRelation != nil else { throw ValidationError.missingAcceptedRelationType }
            }
        }

        return Candidate(
            id: output.id,
            sourceOwner: output.owner,
            kind: kind,
            mentionText: mentionText,
            sourceQuote: sourceQuote,
            sourceKind: output.metadata[MetadataKey.sourceKind],
            objectTypeGuesses: objectTypes,
            relationGuesses: relations,
            actionGuesses: decodedStringArray(output.metadata[MetadataKey.actionGuesses]),
            safeActions: decodedEnumArray(SafeAction.self, from: output.metadata[MetadataKey.safeActions]),
            confidence: output.confidence,
            confidenceReason: output.metadata[MetadataKey.confidenceReason],
            reviewState: reviewState,
            subjectText: output.metadata[MetadataKey.subjectText],
            subjectOwner: ownerRef(
                type: output.metadata[MetadataKey.subjectOwnerType],
                id: output.metadata[MetadataKey.subjectOwnerID]
            ),
            acceptedTargetOwner: acceptedTargetOwner,
            acceptedRelationType: acceptedRelation
        )
    }

    static func canTransition(from current: ReviewState, to next: ReviewState) -> Bool {
        switch current {
        case .suggested, .needsReview, .deferred:
            return current != next
        case .accepted, .rejected:
            return false
        }
    }

    private static func labelForCandidate(
        kind: CandidateKind,
        objectTypes: [ObjectType],
        relations: [RelationType]
    ) -> String {
        switch kind {
        case .object:
            return "Graph object candidate: \(objectTypes.first?.rawValue ?? "object")"
        case .relation:
            return "Graph relation candidate: \(relations.first?.rawValue ?? "relation")"
        case .objectRelation:
            let objectType = objectTypes.first?.rawValue ?? "object"
            let relation = relations.first?.rawValue ?? "relation"
            return "Graph candidate: \(relation) \(objectType)"
        }
    }

    private static func ownerRef(type: String?, id: String?) -> SecondBrainOwnerRef? {
        guard let type = trimmedNonEmpty(type),
              let id = trimmedNonEmpty(id) else { return nil }
        return SecondBrainOwnerRef(ownerType: type, ownerID: id)
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        DatabaseHelpers.encode(values.compactMap(trimmedNonEmpty))
    }

    private static func decodedStringArray(_ value: String?) -> [String] {
        DatabaseHelpers.decodeStringArray(value).compactMap(trimmedNonEmpty)
    }

    private static func decodedEnumArray<T: RawRepresentable>(_ type: T.Type, from value: String?) -> [T] where T.RawValue == String {
        decodedStringArray(value).compactMap(T.init(rawValue:))
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = normalizedWhitespace(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedValue(_ value: String) -> String {
        normalizedWhitespace(value).lowercased()
    }
}
