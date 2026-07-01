import Foundation

struct CiderReviewCandidateActionResult: Equatable {
    var candidateID: String
    var candidateRef: String
    var action: String
    var reviewState: String
    var changed: Bool
}

@MainActor
final class CiderReviewCandidateActionService {
    enum ReviewCandidateActionError: LocalizedError, Equatable {
        case missingCandidateID
        case candidateNotFound(String)
        case wrongCandidateKind(expected: String, actual: String)
        case notReviewable(candidateID: String, reviewState: String)
        case graphAcceptNeedsResolvedTarget(String)

        var errorDescription: String? {
            switch self {
            case .missingCandidateID:
                return "Review candidate id is required."
            case .candidateNotFound(let candidateID):
                return "Review candidate '\(candidateID)' was not found."
            case .wrongCandidateKind(let expected, let actual):
                return "Expected \(expected), got \(actual)."
            case .notReviewable(let candidateID, let reviewState):
                return "Review candidate '\(candidateID)' is \(reviewState) and cannot be changed."
            case .graphAcceptNeedsResolvedTarget(let candidateID):
                return "Graph candidate '\(candidateID)' needs a resolved target before it can be accepted in the app."
            }
        }
    }

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
    func acceptMemoryCandidate(
        _ candidateID: String?,
        actor: String = "user"
    ) throws -> CiderReviewCandidateActionResult {
        let output = try memoryCandidateOutput(candidateID)
        try requireReviewableMemoryCandidate(output)

        var accepted = reviewedMemoryCandidate(output, reviewState: "accepted", actor: actor)
        accepted.metadata["accepted_value"] = accepted.value
        accepted.metadata["accepted_memory_kind"] = accepted.metadata["memory_kind"] ?? accepted.metadata["candidate_kind"] ?? ""

        let action = memoryCandidateAgentAction(
            output: output,
            toolName: "item.accept-memory-candidate",
            actionType: "memory_candidate.accept",
            source: "memory_candidate.accept",
            status: "succeeded",
            summary: "Accepted memory candidate \(output.value).",
            arguments: [
                "candidateID": output.id,
                "actor": actor,
            ],
            result: [
                "reviewState": accepted.reviewState,
            ]
        )

        try database.withTransaction {
            try outputService.record(accepted)
            try store.recordAgentAction(action)
        }

        return result(candidate: accepted, action: "accept", refPrefix: "memory_candidate")
    }

    @discardableResult
    func rejectMemoryCandidate(
        _ candidateID: String?,
        reason: String = "Rejected from Home Review Queue.",
        actor: String = "user"
    ) throws -> CiderReviewCandidateActionResult {
        let output = try memoryCandidateOutput(candidateID)
        try requireReviewableMemoryCandidate(output)

        var rejected = reviewedMemoryCandidate(output, reviewState: "rejected", actor: actor)
        rejected.metadata["rejection_reason"] = normalizedReason(reason)

        let action = memoryCandidateAgentAction(
            output: output,
            toolName: "item.reject-memory-candidate",
            actionType: "memory_candidate.reject",
            source: "memory_candidate.reject",
            status: "succeeded",
            summary: "Rejected memory candidate \(output.value).",
            arguments: [
                "candidateID": output.id,
                "actor": actor,
                "reason": normalizedReason(reason),
            ],
            result: [
                "reviewState": rejected.reviewState,
            ]
        )

        try database.withTransaction {
            try outputService.record(rejected)
            try store.recordAgentAction(action)
        }

        return result(candidate: rejected, action: "reject", refPrefix: "memory_candidate")
    }

    @discardableResult
    func deferMemoryCandidate(
        _ candidateID: String?,
        reason: String = "Deferred from Home Review Queue.",
        actor: String = "user"
    ) throws -> CiderReviewCandidateActionResult {
        let output = try memoryCandidateOutput(candidateID)
        try requireReviewableMemoryCandidate(output)

        var deferred = reviewedMemoryCandidate(output, reviewState: "deferred", actor: actor)
        deferred.metadata["deferral_reason"] = normalizedReason(reason)

        let action = memoryCandidateAgentAction(
            output: output,
            toolName: "item.defer-memory-candidate",
            actionType: "memory_candidate.defer",
            source: "memory_candidate.defer",
            status: "deferred",
            summary: "Deferred memory candidate \(output.value).",
            arguments: [
                "candidateID": output.id,
                "actor": actor,
                "reason": normalizedReason(reason),
            ],
            result: [
                "reviewState": deferred.reviewState,
            ]
        )

        try database.withTransaction {
            try outputService.record(deferred)
            try store.recordAgentAction(action)
        }

        return result(candidate: deferred, action: "defer", refPrefix: "memory_candidate")
    }

    @discardableResult
    func acceptGraphCandidateIfResolved(
        _ candidateID: String?,
        actor: String = "user",
        targetOwner overrideTargetOwner: SecondBrainOwnerRef? = nil,
        relationType overrideRelationType: String? = nil
    ) throws -> CiderReviewCandidateActionResult {
        let output = try graphCandidateOutput(candidateID)
        let candidate = try SecondBrainGraphCandidateContract.validate(output)
        try requireReviewableGraphCandidate(candidate)
        guard let targetOwner = overrideTargetOwner ?? candidate.acceptedTargetOwner else {
            throw ReviewCandidateActionError.graphAcceptNeedsResolvedTarget(output.id)
        }

        let relationType = overrideRelationType
            ?? candidate.acceptedRelationType?.rawValue
            ?? candidate.relationGuesses.first?.rawValue
            ?? SecondBrainGraphCandidateContract.RelationType.mentions.rawValue
        let relationSourceOwner = candidate.subjectOwner ?? output.owner

        var accepted = output
        accepted.reviewState = SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] = targetOwner.ownerType
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] = targetOwner.ownerID
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType] = relationType
        accepted.metadata["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
        accepted.metadata["reviewed_by"] = actor
        accepted.metadata["accepted_source_owner_ref"] = output.owner.canonicalRef
        accepted.metadata["accepted_relation_source_owner_ref"] = relationSourceOwner.canonicalRef
        accepted.updatedAt = Date()
        _ = try SecondBrainGraphCandidateContract.validate(accepted)

        let relation = SecondBrainRelation(
            sourceOwner: relationSourceOwner,
            targetOwner: targetOwner,
            relationType: relationType,
            evidence: candidate.sourceQuote,
            source: "graph_candidate.accept",
            actor: actor,
            confidence: output.confidence,
            metadata: graphCandidateRelationMetadata(output: output, candidate: candidate, targetOwner: targetOwner)
        )
        let action = SecondBrainAgentAction(
            owner: output.owner,
            itemID: itemID(for: output.owner),
            toolName: "item.accept-graph-candidate",
            actionType: "graph_candidate.accept",
            source: "graph_candidate.accept",
            status: "succeeded",
            summary: "Accepted graph candidate \(candidate.mentionText) as \(relationType) -> \(targetOwner.canonicalRef).",
            argumentsJSON: DatabaseHelpers.encodeJSON([
                "candidateID": output.id,
                "actor": actor,
                "targetOwner": targetOwner.canonicalRef,
                "relationType": relationType,
            ]),
            resultJSON: DatabaseHelpers.encodeJSON([
                "reviewState": accepted.reviewState,
                "relationID": relation.id,
            ])
        )

        try database.withTransaction {
            try store.recordRelation(relation)
            try outputService.record(accepted)
            try store.recordAgentAction(action)
        }

        return result(candidate: accepted, action: "accept", refPrefix: "graph_candidate")
    }

    @discardableResult
    func rejectGraphCandidate(
        _ candidateID: String?,
        reason: String = "Rejected from Home Review Queue.",
        actor: String = "user"
    ) throws -> CiderReviewCandidateActionResult {
        let output = try graphCandidateOutput(candidateID)
        let candidate = try SecondBrainGraphCandidateContract.validate(output)
        try requireReviewableGraphCandidate(candidate)

        var rejected = output
        rejected.reviewState = SecondBrainGraphCandidateContract.ReviewState.rejected.rawValue
        rejected.metadata["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
        rejected.metadata["reviewed_by"] = actor
        rejected.metadata["rejection_reason"] = normalizedReason(reason)
        rejected.updatedAt = Date()
        _ = try SecondBrainGraphCandidateContract.validate(rejected)

        let action = SecondBrainAgentAction(
            owner: output.owner,
            itemID: itemID(for: output.owner),
            toolName: "item.reject-graph-candidate",
            actionType: "graph_candidate.reject",
            source: "graph_candidate.reject",
            status: "succeeded",
            summary: "Rejected graph candidate \(candidate.mentionText).",
            argumentsJSON: DatabaseHelpers.encodeJSON([
                "candidateID": output.id,
                "actor": actor,
                "reason": normalizedReason(reason),
            ]),
            resultJSON: DatabaseHelpers.encodeJSON([
                "reviewState": rejected.reviewState,
            ])
        )

        try database.withTransaction {
            try outputService.record(rejected)
            try store.recordAgentAction(action)
        }

        return result(candidate: rejected, action: "reject", refPrefix: "graph_candidate")
    }

    @discardableResult
    func deferGraphCandidate(
        _ candidateID: String?,
        reason: String = "Deferred from Home Review Queue.",
        actor: String = "user"
    ) throws -> CiderReviewCandidateActionResult {
        let output = try graphCandidateOutput(candidateID)
        let candidate = try SecondBrainGraphCandidateContract.validate(output)
        try requireReviewableGraphCandidate(candidate)

        var deferred = output
        deferred.reviewState = SecondBrainGraphCandidateContract.ReviewState.deferred.rawValue
        deferred.metadata["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
        deferred.metadata["reviewed_by"] = actor
        deferred.metadata["deferral_reason"] = normalizedReason(reason)
        deferred.updatedAt = Date()
        _ = try SecondBrainGraphCandidateContract.validate(deferred)

        let action = SecondBrainAgentAction(
            owner: output.owner,
            itemID: itemID(for: output.owner),
            toolName: "item.defer-graph-candidate",
            actionType: "graph_candidate.defer",
            source: "graph_candidate.defer",
            status: "deferred",
            summary: "Deferred graph candidate \(candidate.mentionText).",
            argumentsJSON: DatabaseHelpers.encodeJSON([
                "candidateID": output.id,
                "actor": actor,
                "reason": normalizedReason(reason),
            ]),
            resultJSON: DatabaseHelpers.encodeJSON([
                "reviewState": deferred.reviewState,
            ])
        )

        try database.withTransaction {
            try outputService.record(deferred)
            try store.recordAgentAction(action)
        }

        return result(candidate: deferred, action: "defer", refPrefix: "graph_candidate")
    }

    private func memoryCandidateOutput(_ rawID: String?) throws -> SecondBrainEnrichmentOutput {
        let candidateID = try normalizedCandidateID(rawID, prefix: "memory_candidate")
        guard let output = try outputService.output(id: candidateID) else {
            throw ReviewCandidateActionError.candidateNotFound(candidateID)
        }
        guard output.kind == "memory_candidate" else {
            throw ReviewCandidateActionError.wrongCandidateKind(expected: "memory_candidate", actual: output.kind)
        }
        return output
    }

    private func graphCandidateOutput(_ rawID: String?) throws -> SecondBrainEnrichmentOutput {
        let candidateID = try normalizedCandidateID(rawID, prefix: "graph_candidate")
        guard let output = try outputService.output(id: candidateID) else {
            throw ReviewCandidateActionError.candidateNotFound(candidateID)
        }
        guard output.kind == SecondBrainGraphCandidateContract.outputKind else {
            throw ReviewCandidateActionError.wrongCandidateKind(
                expected: SecondBrainGraphCandidateContract.outputKind,
                actual: output.kind
            )
        }
        return output
    }

    private func normalizedCandidateID(_ rawID: String?, prefix: String) throws -> String {
        guard let rawID else { throw ReviewCandidateActionError.missingCandidateID }
        let trimmed = rawID
            .replacingOccurrences(of: "\(prefix):", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReviewCandidateActionError.missingCandidateID }
        return trimmed
    }

    private func requireReviewableMemoryCandidate(_ output: SecondBrainEnrichmentOutput) throws {
        guard ["suggested", "needs_review", "deferred"].contains(output.reviewState) else {
            throw ReviewCandidateActionError.notReviewable(candidateID: output.id, reviewState: output.reviewState)
        }
    }

    private func requireReviewableGraphCandidate(_ candidate: SecondBrainGraphCandidateContract.Candidate) throws {
        guard candidate.reviewState.isReviewable else {
            throw ReviewCandidateActionError.notReviewable(
                candidateID: candidate.id,
                reviewState: candidate.reviewState.rawValue
            )
        }
    }

    private func reviewedMemoryCandidate(
        _ output: SecondBrainEnrichmentOutput,
        reviewState: String,
        actor: String
    ) -> SecondBrainEnrichmentOutput {
        var reviewed = output
        reviewed.reviewState = reviewState
        reviewed.metadata["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
        reviewed.metadata["reviewed_by"] = actor
        reviewed.updatedAt = Date()
        return reviewed
    }

    private func memoryCandidateAgentAction(
        output: SecondBrainEnrichmentOutput,
        toolName: String,
        actionType: String,
        source: String,
        status: String,
        summary: String,
        arguments: [String: String],
        result: [String: String]
    ) -> SecondBrainAgentAction {
        SecondBrainAgentAction(
            owner: output.owner,
            itemID: itemID(for: output.owner),
            toolName: toolName,
            actionType: actionType,
            source: source,
            status: status,
            summary: summary,
            argumentsJSON: DatabaseHelpers.encodeJSON(arguments),
            resultJSON: DatabaseHelpers.encodeJSON(result)
        )
    }

    private func graphCandidateRelationMetadata(
        output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        targetOwner: SecondBrainOwnerRef
    ) -> [String: String] {
        var metadata: [String: String] = [
            "candidate_id": output.id,
            "candidate_ref": "graph_candidate:\(output.id)",
            "candidate_kind": candidate.kind.rawValue,
            "mention_text": candidate.mentionText,
            "source_quote": candidate.sourceQuote,
            "source_owner_ref": output.owner.canonicalRef,
            "target_owner_ref": targetOwner.canonicalRef,
        ]
        metadata["object_type_guesses"] = DatabaseHelpers.encode(candidate.objectTypeGuesses.map(\.rawValue))
        metadata["relation_guesses"] = DatabaseHelpers.encode(candidate.relationGuesses.map(\.rawValue))
        metadata["action_guesses"] = DatabaseHelpers.encode(candidate.actionGuesses)
        if let sourceKind = candidate.sourceKind {
            metadata["source_kind"] = sourceKind
        }
        if let subjectText = candidate.subjectText {
            metadata["subject_text"] = subjectText
        }
        if let confidenceReason = candidate.confidenceReason {
            metadata["confidence_reason"] = confidenceReason
        }
        return metadata
    }

    private func itemID(for owner: SecondBrainOwnerRef) -> String? {
        switch owner.ownerType {
        case "bookmark", "note", "dateCard", "contact", "todo", "vaultFile":
            return UUID(uuidString: owner.ownerID) == nil ? nil : owner.ownerID
        default:
            return nil
        }
    }

    private func normalizedReason(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Reviewed from Home Review Queue." : trimmed
    }

    private func result(
        candidate: SecondBrainEnrichmentOutput,
        action: String,
        refPrefix: String
    ) -> CiderReviewCandidateActionResult {
        CiderReviewCandidateActionResult(
            candidateID: candidate.id,
            candidateRef: "\(refPrefix):\(candidate.id)",
            action: action,
            reviewState: candidate.reviewState,
            changed: true
        )
    }
}
