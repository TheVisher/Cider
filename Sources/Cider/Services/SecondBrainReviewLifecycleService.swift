import Foundation

struct SecondBrainReviewLifecycleEvent: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef
    var candidateRef: String?
    var lifecycleState: String
    var eventKind: String
    var actor: String
    var source: String
    var toolName: String?
    var reason: String?
    var decisionNote: String?
    var sourceEvidenceID: String?
    var sourceEvidenceRef: String?
    var supersedesRef: String?
    var invalidatesRef: String?
    var correctsRef: String?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()

    var ownerRef: String { owner.canonicalRef }
}

@MainActor
final class SecondBrainReviewLifecycleService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func record(_ event: SecondBrainReviewLifecycleEvent) throws {
        let metadata = DatabaseHelpers.encodeJSON(event.metadata) ?? "{}"
        let stmt = try database.prepare("""
            INSERT INTO review_lifecycle_events (
                id, owner_type, owner_id, candidate_ref, lifecycle_state, event_kind,
                actor, source, tool_name, reason, decision_note,
                source_evidence_id, source_evidence_ref,
                supersedes_ref, invalidates_ref, corrects_ref,
                metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING;
            """)
        stmt.bind(event.id, at: 1)
            .bind(event.owner.ownerType, at: 2)
            .bind(event.owner.ownerID, at: 3)
            .bind(event.candidateRef, at: 4)
            .bind(event.lifecycleState, at: 5)
            .bind(event.eventKind, at: 6)
            .bind(event.actor, at: 7)
            .bind(event.source, at: 8)
            .bind(event.toolName, at: 9)
            .bind(event.reason, at: 10)
            .bind(event.decisionNote, at: 11)
            .bind(event.sourceEvidenceID, at: 12)
            .bind(event.sourceEvidenceRef, at: 13)
            .bind(event.supersedesRef, at: 14)
            .bind(event.invalidatesRef, at: 15)
            .bind(event.correctsRef, at: 16)
            .bind(metadata, at: 17)
            .bind(DatabaseHelpers.encode(event.createdAt), at: 18)
        try stmt.step()
    }

    func events(owner: SecondBrainOwnerRef, limit: Int = 50) throws -> [SecondBrainReviewLifecycleEvent] {
        let stmt = try database.prepare("""
            SELECT id, owner_type, owner_id, candidate_ref, lifecycle_state, event_kind,
                   actor, source, tool_name, reason, decision_note,
                   source_evidence_id, source_evidence_ref,
                   supersedes_ref, invalidates_ref, corrects_ref,
                   metadata, created_at
            FROM review_lifecycle_events
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY created_at ASC
            LIMIT ?;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
            .bind(Int64(max(1, limit)), at: 3)
        return try collect(stmt)
    }

    func events(candidateRef: String, limit: Int = 50) throws -> [SecondBrainReviewLifecycleEvent] {
        let stmt = try database.prepare("""
            SELECT id, owner_type, owner_id, candidate_ref, lifecycle_state, event_kind,
                   actor, source, tool_name, reason, decision_note,
                   source_evidence_id, source_evidence_ref,
                   supersedes_ref, invalidates_ref, corrects_ref,
                   metadata, created_at
            FROM review_lifecycle_events
            WHERE candidate_ref = ?
            ORDER BY created_at ASC
            LIMIT ?;
            """)
        stmt.bind(candidateRef, at: 1)
            .bind(Int64(max(1, limit)), at: 2)
        return try collect(stmt)
    }

    func events(sourceEvidenceID: String, limit: Int = 50) throws -> [SecondBrainReviewLifecycleEvent] {
        let stmt = try database.prepare("""
            SELECT id, owner_type, owner_id, candidate_ref, lifecycle_state, event_kind,
                   actor, source, tool_name, reason, decision_note,
                   source_evidence_id, source_evidence_ref,
                   supersedes_ref, invalidates_ref, corrects_ref,
                   metadata, created_at
            FROM review_lifecycle_events
            WHERE source_evidence_id = ?
            ORDER BY created_at ASC
            LIMIT ?;
            """)
        stmt.bind(sourceEvidenceID, at: 1)
            .bind(Int64(max(1, limit)), at: 2)
        return try collect(stmt)
    }

    func recordEnrichmentLifecycle(
        previous: SecondBrainEnrichmentOutput?,
        current: SecondBrainEnrichmentOutput,
        sourceEvidence: SecondBrainSourceEvidenceRecord? = nil,
        actor: String? = nil,
        source: String? = nil,
        toolName: String? = nil,
        reason: String? = nil
    ) throws -> SecondBrainReviewLifecycleEvent? {
        let eventKind: String
        let previousState = previous?.reviewState
        if previous == nil {
            eventKind = current.reviewState
        } else if previousState != current.reviewState {
            eventKind = transitionEventKind(from: previousState, to: current.reviewState, metadata: current.metadata)
        } else if current.metadata["corrected_at"] != nil, previous?.metadata["corrected_at"] != current.metadata["corrected_at"] {
            eventKind = "corrected"
        } else {
            return nil
        }

        let candidateRef = candidateRef(for: current)
        let lifecycleState = current.reviewState
        let resolvedActor = actor
            ?? current.metadata["reviewed_by"]
            ?? current.metadata["corrected_by"]
            ?? current.metadata["actor"]
            ?? "system"
        let resolvedReason = reason
            ?? current.metadata["rejection_reason"]
            ?? current.metadata["deferral_reason"]
            ?? current.metadata["correction_reason"]
            ?? current.metadata["decision_note"]
        var metadata: [String: String] = [
            "owner_ref": current.owner.canonicalRef,
            "output_kind": current.kind,
            "review_state": current.reviewState,
        ]
        if let previousState { metadata["previous_state"] = previousState }
        if let normalized = current.normalizedValue.nilIfEmpty { metadata["normalized_value"] = normalized }
        if let runID = current.metadata["extraction_run_id"] { metadata["extraction_run_id"] = runID }
        if let provider = current.metadata["extraction_provider"] { metadata["extraction_provider"] = provider }
        if let model = current.metadata["extraction_model"] { metadata["extraction_model"] = model }
        if let correctedFields = current.metadata["corrected_fields"] { metadata["corrected_fields"] = correctedFields }

        let event = SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: current.id),
            candidateRef: candidateRef,
            lifecycleState: lifecycleState,
            eventKind: eventKind,
            actor: resolvedActor,
            source: source ?? current.source,
            toolName: toolName,
            reason: resolvedReason,
            decisionNote: current.metadata["decision_note"],
            sourceEvidenceID: sourceEvidence?.id,
            sourceEvidenceRef: sourceEvidence.map { "source_evidence:\($0.id)" },
            supersedesRef: current.metadata["supersedes_ref"],
            invalidatesRef: current.metadata["invalidates_ref"],
            correctsRef: current.metadata["corrects_ref"],
            metadata: metadata,
            createdAt: current.updatedAt
        )
        try record(event)
        return event
    }

    func recordAcceptedRelationLifecycle(
        relation: SecondBrainRelation,
        sourceEvidence: SecondBrainSourceEvidenceRecord? = nil,
        actor: String? = nil,
        reason: String? = nil
    ) throws -> SecondBrainReviewLifecycleEvent {
        var metadata: [String: String] = [
            "source_owner_ref": relation.sourceOwner.canonicalRef,
            "target_owner_ref": relation.targetOwner.canonicalRef,
            "relation_type": relation.relationType,
        ]
        if let candidateRef = relation.metadata["candidate_ref"] { metadata["candidate_ref"] = candidateRef }
        if let candidateID = relation.metadata["candidate_id"] { metadata["candidate_id"] = candidateID }
        let event = SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "owner_relation", ownerID: relation.id),
            candidateRef: relation.metadata["candidate_ref"] ?? relation.metadata["candidate_id"].map { "graph_candidate:\($0)" },
            lifecycleState: "accepted",
            eventKind: "accepted_truth_recorded",
            actor: actor ?? relation.actor,
            source: relation.source,
            toolName: "owner_relation.record",
            reason: reason,
            decisionNote: relation.metadata["decision_note"],
            sourceEvidenceID: sourceEvidence?.id,
            sourceEvidenceRef: sourceEvidence.map { "source_evidence:\($0.id)" },
            supersedesRef: relation.metadata["supersedes_ref"],
            invalidatesRef: relation.metadata["invalidates_ref"],
            correctsRef: relation.metadata["corrects_ref"],
            metadata: metadata,
            createdAt: relation.updatedAt
        )
        try record(event)
        return event
    }

    private func collect(_ stmt: SQLStatement) throws -> [SecondBrainReviewLifecycleEvent] {
        var events: [SecondBrainReviewLifecycleEvent] = []
        while try stmt.step() {
            events.append(event(from: stmt))
        }
        return events
    }

    private func event(from stmt: SQLStatement) -> SecondBrainReviewLifecycleEvent {
        SecondBrainReviewLifecycleEvent(
            id: stmt.string(at: 0),
            owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
            candidateRef: stmt.optionalString(at: 3),
            lifecycleState: stmt.string(at: 4),
            eventKind: stmt.string(at: 5),
            actor: stmt.string(at: 6),
            source: stmt.string(at: 7),
            toolName: stmt.optionalString(at: 8),
            reason: stmt.optionalString(at: 9),
            decisionNote: stmt.optionalString(at: 10),
            sourceEvidenceID: stmt.optionalString(at: 11),
            sourceEvidenceRef: stmt.optionalString(at: 12),
            supersedesRef: stmt.optionalString(at: 13),
            invalidatesRef: stmt.optionalString(at: 14),
            correctsRef: stmt.optionalString(at: 15),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 16)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 17))
        )
    }

    private func transitionEventKind(from previousState: String?, to newState: String, metadata: [String: String]) -> String {
        if metadata["corrected_at"] != nil { return "corrected" }
        switch newState {
        case "accepted": return "accepted"
        case "rejected": return "rejected"
        case "deferred": return "deferred"
        case "invalidated": return "invalidated"
        case "superseded": return "superseded"
        case "needs_review", "suggested": return "state_changed"
        default: return newState
        }
    }

    static func candidateRef(for output: SecondBrainEnrichmentOutput) -> String? {
        switch output.kind {
        case SecondBrainGraphCandidateContract.outputKind:
            return "graph_candidate:\(output.id)"
        case "memory_candidate":
            return "memory_candidate:\(output.id)"
        default:
            return "enrichment_output:\(output.id)"
        }
    }

    private func candidateRef(for output: SecondBrainEnrichmentOutput) -> String? {
        Self.candidateRef(for: output)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
