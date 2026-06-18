import Foundation

struct SecondBrainEntityResolutionConflict: Codable, Equatable {
    var kind: String
    var severity: String
    var message: String
    var conflictingOwner: SecondBrainOwnerRef?
}

struct SecondBrainEntityResolutionCandidate: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var candidateType: String
    var sourceEntity: SecondBrainOwnerRef
    var sourceLabel: String
    var inputMention: String
    var targetEntity: SecondBrainOwnerRef
    var targetLabel: String
    var sourceOwner: SecondBrainOwnerRef
    var sourceQuote: String
    var confidence: Double?
    var confidenceReasons: [String]
    var conflicts: [SecondBrainEntityResolutionConflict]
    var reviewState: String = "suggested"
    var source: String
    var actor: String
    var sourceEvidenceID: String?
    var sourceEvidenceRef: String?
    var acceptedRelationID: String?
    var decisionNote: String?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var reviewedAt: Date?
    var sourceEvidenceRecord: SecondBrainSourceEvidenceRecord?
    var lifecycleHistory: [SecondBrainReviewLifecycleEvent] = []

    var candidateRef: String { "entity_resolution_candidate:\(id)" }
    var sourceEntityRef: String { sourceEntity.canonicalRef }
    var targetEntityRef: String { targetEntity.canonicalRef }
    var hasConflicts: Bool { !conflicts.isEmpty }
    var conflictCount: Int { conflicts.count }
    var truthBoundary: String {
        reviewState == "accepted" ? "accepted_entity_resolution" : "reviewable_candidate_not_truth"
    }
    var safeNextCommands: [String] {
        var commands = [
            "cider-cli item entity-resolution inspect \(id) --json",
            "cider-cli item entity-resolution accept \(id) --json",
            "cider-cli item entity-resolution reject \(id) --json",
            "cider-cli item entity-resolution merge \(id) --json",
            "cider-cli item context \(targetEntity.ownerType) \(targetEntity.ownerID) --json",
        ]
        if sourceOwner.ownerType != sourceEntity.ownerType || sourceOwner.ownerID != sourceEntity.ownerID {
            commands.append("cider-cli item context \(sourceOwner.ownerType) \(sourceOwner.ownerID) --json")
        }
        var seen = Set<String>()
        return commands.filter { seen.insert($0).inserted }
    }
}

@MainActor
final class SecondBrainEntityResolutionService {
    private let database: CiderDatabase
    private let store: SecondBrainStore
    private let evidenceService: SecondBrainSourceEvidenceService
    private let lifecycleService: SecondBrainReviewLifecycleService

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
        self.evidenceService = SecondBrainSourceEvidenceService(database: database)
        self.lifecycleService = SecondBrainReviewLifecycleService(database: database)
    }

    func suggest(
        candidateType: String,
        sourceEntity: SecondBrainOwnerRef,
        sourceLabel: String,
        inputMention: String,
        targetEntity: SecondBrainOwnerRef,
        targetLabel: String,
        sourceOwner: SecondBrainOwnerRef,
        sourceQuote: String,
        confidence: Double?,
        confidenceReasons: [String],
        conflicts: [SecondBrainEntityResolutionConflict] = [],
        actor: String = "system",
        source: String = "entity_resolution.suggest",
        metadata: [String: String] = [:]
    ) throws -> SecondBrainEntityResolutionCandidate {
        var candidate = SecondBrainEntityResolutionCandidate(
            candidateType: candidateType,
            sourceEntity: sourceEntity,
            sourceLabel: sourceLabel,
            inputMention: inputMention,
            targetEntity: targetEntity,
            targetLabel: targetLabel,
            sourceOwner: sourceOwner,
            sourceQuote: sourceQuote,
            confidence: confidence,
            confidenceReasons: confidenceReasons,
            conflicts: conflicts,
            reviewState: "suggested",
            source: source,
            actor: actor,
            metadata: metadata
        )
        let evidence = SecondBrainSourceEvidenceRecord(
            evidenceKind: "entity_resolution_candidate",
            sourceOwner: sourceOwner,
            sourceKind: metadata["source_kind"],
            sourceQuote: sourceQuote,
            spanStart: metadata["source_span_start"].flatMap(Int.init),
            spanEnd: metadata["source_span_end"].flatMap(Int.init),
            observedAt: nil,
            capturedAt: nil,
            extractedAt: candidate.createdAt,
            extractionSource: source,
            extractionRunID: metadata["extraction_run_id"],
            extractionProvider: metadata["extraction_provider"],
            extractionModel: metadata["extraction_model"],
            derivedOwner: SecondBrainOwnerRef(ownerType: "entity_resolution_candidate", ownerID: candidate.id),
            derivedKind: candidateType,
            candidateRef: candidate.candidateRef,
            metadata: [
                "source_entity_ref": sourceEntity.canonicalRef,
                "target_entity_ref": targetEntity.canonicalRef,
                "input_mention": inputMention,
            ].merging(metadata) { current, _ in current },
            createdAt: candidate.createdAt,
            updatedAt: candidate.updatedAt
        )
        try evidenceService.record(evidence)
        let storedEvidence = try evidenceService.record(derivedOwner: evidence.derivedOwner, evidenceKind: evidence.evidenceKind) ?? evidence
        candidate.sourceEvidenceID = storedEvidence.id
        candidate.sourceEvidenceRef = "source_evidence:\(storedEvidence.id)"
        try record(candidate)
        try lifecycleService.record(SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "entity_resolution_candidate", ownerID: candidate.id),
            candidateRef: candidate.candidateRef,
            lifecycleState: "suggested",
            eventKind: "suggested",
            actor: actor,
            source: source,
            toolName: "entity_resolution.suggest",
            reason: conflicts.isEmpty ? nil : "candidate_has_conflicts",
            sourceEvidenceID: storedEvidence.id,
            sourceEvidenceRef: "source_evidence:\(storedEvidence.id)",
            metadata: ["candidate_type": candidateType, "truth_boundary": "reviewable_candidate_not_truth"],
            createdAt: candidate.createdAt
        ))
        return try self.candidate(id: candidate.id) ?? candidate
    }

    func candidates(reviewStates: Set<String>? = nil, limit: Int = 50) throws -> [SecondBrainEntityResolutionCandidate] {
        let stmt = try database.prepare("""
            SELECT id, candidate_type, source_entity_type, source_entity_id, source_label, input_mention,
                   target_entity_type, target_entity_id, target_label, source_owner_type, source_owner_id,
                   source_quote, confidence, confidence_reasons, conflicts_json, review_state, source, actor,
                   source_evidence_id, source_evidence_ref, accepted_relation_id, decision_note, metadata,
                   created_at, updated_at, reviewed_at
            FROM entity_resolution_candidates
            ORDER BY updated_at DESC, confidence DESC, target_label COLLATE NOCASE ASC
            LIMIT ?;
            """)
        stmt.bind(Int64(max(1, limit)), at: 1)
        let normalizedStates = reviewStates.map { Set($0.map { $0.lowercased() }) }
        var result: [SecondBrainEntityResolutionCandidate] = []
        while try stmt.step() {
            let candidate = try candidate(from: stmt, includeJoinedRecords: true)
            if let normalizedStates, !normalizedStates.contains(candidate.reviewState.lowercased()) { continue }
            result.append(candidate)
        }
        return result
    }

    func candidate(id: String) throws -> SecondBrainEntityResolutionCandidate? {
        let stmt = try database.prepare("""
            SELECT id, candidate_type, source_entity_type, source_entity_id, source_label, input_mention,
                   target_entity_type, target_entity_id, target_label, source_owner_type, source_owner_id,
                   source_quote, confidence, confidence_reasons, conflicts_json, review_state, source, actor,
                   source_evidence_id, source_evidence_ref, accepted_relation_id, decision_note, metadata,
                   created_at, updated_at, reviewed_at
            FROM entity_resolution_candidates
            WHERE id = ?
            LIMIT 1;
            """)
        stmt.bind(id, at: 1)
        guard try stmt.step() else { return nil }
        return try candidate(from: stmt, includeJoinedRecords: true)
    }

    func reject(candidateID: String, actor: String = "agent", reason: String? = nil) throws -> SecondBrainEntityResolutionCandidate {
        guard let current = try candidate(id: candidateID) else { throw EntityResolutionError.notFound(candidateID) }
        guard current.reviewState != "accepted" else { return current }
        return try updateReviewState(candidate: current, state: "rejected", actor: actor, reason: reason, eventKind: "rejected")
    }

    func accept(candidateID: String, actor: String = "agent", reason: String? = nil) throws -> SecondBrainEntityResolutionCandidate {
        guard let current = try candidate(id: candidateID) else { throw EntityResolutionError.notFound(candidateID) }
        guard current.reviewState != "accepted" else { return current }
        return try updateReviewState(candidate: current, state: "accepted", actor: actor, reason: reason, eventKind: "accepted")
    }

    func merge(candidateID: String, actor: String = "agent", reason: String? = nil) throws -> SecondBrainEntityResolutionCandidate {
        guard var current = try candidate(id: candidateID) else { throw EntityResolutionError.notFound(candidateID) }
        guard current.reviewState != "accepted" else { return current }
        var metadata = current.metadata
        metadata["candidate_id"] = current.id
        metadata["candidate_ref"] = current.candidateRef
        metadata["source_quote"] = current.sourceQuote
        metadata["source_owner_ref"] = current.sourceOwner.canonicalRef
        metadata["mention_text"] = current.inputMention
        metadata["decision_note"] = reason
        if let sourceEvidenceID = current.sourceEvidenceID {
            metadata["source_evidence_id"] = sourceEvidenceID
            metadata["source_evidence_ref"] = "source_evidence:\(sourceEvidenceID)"
        }
        let relation = SecondBrainRelation(
            sourceOwner: current.sourceEntity,
            targetOwner: current.targetEntity,
            relationType: "entity_alias_of",
            evidence: current.sourceQuote,
            source: "entity_resolution.merge",
            actor: actor,
            confidence: current.confidence,
            metadata: metadata
        )
        try store.recordRelation(relation)
        current.acceptedRelationID = relation.id
        return try updateReviewState(candidate: current, state: "accepted", actor: actor, reason: reason, eventKind: "accepted")
    }

    private func updateReviewState(candidate: SecondBrainEntityResolutionCandidate, state: String, actor: String, reason: String?, eventKind: String) throws -> SecondBrainEntityResolutionCandidate {
        var candidate = candidate
        candidate.reviewState = state
        candidate.actor = actor
        candidate.decisionNote = reason
        candidate.reviewedAt = Date()
        candidate.updatedAt = candidate.reviewedAt ?? Date()
        try record(candidate)
        try lifecycleService.record(SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "entity_resolution_candidate", ownerID: candidate.id),
            candidateRef: candidate.candidateRef,
            lifecycleState: state,
            eventKind: eventKind,
            actor: actor,
            source: "entity_resolution.review",
            toolName: "entity_resolution.\(eventKind)",
            reason: reason,
            decisionNote: reason,
            sourceEvidenceID: candidate.sourceEvidenceID,
            sourceEvidenceRef: candidate.sourceEvidenceRef,
            metadata: ["candidate_type": candidate.candidateType, "truth_boundary": candidate.truthBoundary],
            createdAt: candidate.updatedAt
        ))
        return try self.candidate(id: candidate.id) ?? candidate
    }

    private func record(_ candidate: SecondBrainEntityResolutionCandidate) throws {
        let stmt = try database.prepare("""
            INSERT INTO entity_resolution_candidates (
                id, candidate_type, source_entity_type, source_entity_id, source_label, input_mention,
                target_entity_type, target_entity_id, target_label, source_owner_type, source_owner_id,
                source_quote, confidence, confidence_reasons, conflicts_json, review_state, source, actor,
                source_evidence_id, source_evidence_ref, accepted_relation_id, decision_note, metadata,
                created_at, updated_at, reviewed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(candidate_type, source_entity_type, source_entity_id, target_entity_type, target_entity_id, source)
            DO UPDATE SET
                source_label = excluded.source_label,
                input_mention = excluded.input_mention,
                target_label = excluded.target_label,
                source_owner_type = excluded.source_owner_type,
                source_owner_id = excluded.source_owner_id,
                source_quote = excluded.source_quote,
                confidence = excluded.confidence,
                confidence_reasons = excluded.confidence_reasons,
                conflicts_json = excluded.conflicts_json,
                review_state = excluded.review_state,
                actor = excluded.actor,
                source_evidence_id = excluded.source_evidence_id,
                source_evidence_ref = excluded.source_evidence_ref,
                accepted_relation_id = excluded.accepted_relation_id,
                decision_note = excluded.decision_note,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at,
                reviewed_at = excluded.reviewed_at;
            """)
        stmt.bind(candidate.id, at: 1)
            .bind(candidate.candidateType, at: 2)
            .bind(candidate.sourceEntity.ownerType, at: 3)
            .bind(candidate.sourceEntity.ownerID, at: 4)
            .bind(candidate.sourceLabel, at: 5)
            .bind(candidate.inputMention, at: 6)
            .bind(candidate.targetEntity.ownerType, at: 7)
            .bind(candidate.targetEntity.ownerID, at: 8)
            .bind(candidate.targetLabel, at: 9)
            .bind(candidate.sourceOwner.ownerType, at: 10)
            .bind(candidate.sourceOwner.ownerID, at: 11)
            .bind(candidate.sourceQuote, at: 12)
            .bind(candidate.confidence, at: 13)
            .bind(DatabaseHelpers.encodeJSON(candidate.confidenceReasons) ?? "[]", at: 14)
            .bind(DatabaseHelpers.encodeJSON(candidate.conflicts) ?? "[]", at: 15)
            .bind(candidate.reviewState, at: 16)
            .bind(candidate.source, at: 17)
            .bind(candidate.actor, at: 18)
            .bind(candidate.sourceEvidenceID, at: 19)
            .bind(candidate.sourceEvidenceRef, at: 20)
            .bind(candidate.acceptedRelationID, at: 21)
            .bind(candidate.decisionNote, at: 22)
            .bind(DatabaseHelpers.encodeJSON(candidate.metadata) ?? "{}", at: 23)
            .bind(DatabaseHelpers.encode(candidate.createdAt), at: 24)
            .bind(DatabaseHelpers.encode(candidate.updatedAt), at: 25)
            .bind(candidate.reviewedAt.map(DatabaseHelpers.encode), at: 26)
        try stmt.step()
    }

    private func candidate(from stmt: SQLStatement, includeJoinedRecords: Bool) throws -> SecondBrainEntityResolutionCandidate {
        let id = stmt.string(at: 0)
        let sourceEvidenceID = stmt.optionalString(at: 18)
        let sourceEvidenceRecord = includeJoinedRecords && sourceEvidenceID != nil
            ? try evidenceService.record(derivedOwner: SecondBrainOwnerRef(ownerType: "entity_resolution_candidate", ownerID: id), evidenceKind: "entity_resolution_candidate")
            : nil
        let lifecycle = includeJoinedRecords
            ? try lifecycleService.events(candidateRef: "entity_resolution_candidate:\(id)")
            : []
        return SecondBrainEntityResolutionCandidate(
            id: id,
            candidateType: stmt.string(at: 1),
            sourceEntity: SecondBrainOwnerRef(ownerType: stmt.string(at: 2), ownerID: stmt.string(at: 3)),
            sourceLabel: stmt.string(at: 4),
            inputMention: stmt.string(at: 5),
            targetEntity: SecondBrainOwnerRef(ownerType: stmt.string(at: 6), ownerID: stmt.string(at: 7)),
            targetLabel: stmt.string(at: 8),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 9), ownerID: stmt.string(at: 10)),
            sourceQuote: stmt.string(at: 11),
            confidence: stmt.optionalDouble(at: 12),
            confidenceReasons: DatabaseHelpers.decodeJSON([String].self, from: stmt.optionalString(at: 13)) ?? [],
            conflicts: DatabaseHelpers.decodeJSON([SecondBrainEntityResolutionConflict].self, from: stmt.optionalString(at: 14)) ?? [],
            reviewState: stmt.string(at: 15),
            source: stmt.string(at: 16),
            actor: stmt.string(at: 17),
            sourceEvidenceID: sourceEvidenceID,
            sourceEvidenceRef: stmt.optionalString(at: 19),
            acceptedRelationID: stmt.optionalString(at: 20),
            decisionNote: stmt.optionalString(at: 21),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 22)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 23)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 24)),
            reviewedAt: stmt.optionalDouble(at: 25).map(DatabaseHelpers.decodeDate),
            sourceEvidenceRecord: sourceEvidenceRecord,
            lifecycleHistory: lifecycle
        )
    }

    enum EntityResolutionError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let id): return "Entity-resolution candidate not found: \(id)"
            }
        }
    }
}
