import Foundation

struct SecondBrainFactValidityCandidate: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var targetRef: String
    var proposedState: String
    var validAt: Date?
    var invalidAt: Date?
    var expiredAt: Date?
    var supersedesRef: String?
    var supersededByRef: String?
    var sourceOwner: SecondBrainOwnerRef
    var sourceQuote: String
    var reason: String
    var reviewState: String = "suggested"
    var source: String
    var actor: String
    var sourceEvidenceID: String?
    var sourceEvidenceRef: String?
    var decisionNote: String?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var reviewedAt: Date?

    var candidateRef: String { "fact_validity_candidate:\(id)" }
    var truthBoundary: String {
        reviewState == "accepted" ? "accepted_fact_validity" : "reviewable_candidate_not_truth"
    }
}

struct SecondBrainFactValidityState: Codable, Equatable {
    var targetRef: String
    var currentState: String
    var isCurrent: Bool
    var validAt: Date?
    var invalidAt: Date?
    var expiredAt: Date?
    var supersedesRef: String?
    var supersededByRef: String?
    var acceptedCandidate: SecondBrainFactValidityCandidate
    var sourceEvidenceRecord: SecondBrainSourceEvidenceRecord?
    var lifecycleHistory: [SecondBrainReviewLifecycleEvent]

    var stateRef: String { acceptedCandidate.candidateRef }
}

struct SecondBrainFactValidityCandidateView: Codable, Equatable {
    var candidate: SecondBrainFactValidityCandidate
    var sourceEvidenceRecord: SecondBrainSourceEvidenceRecord?
    var lifecycleHistory: [SecondBrainReviewLifecycleEvent]

    var id: String { candidate.id }
    var targetRef: String { candidate.targetRef }
    var reviewState: String { candidate.reviewState }
    var truthBoundary: String { candidate.truthBoundary }
}

@MainActor
final class SecondBrainFactValidityService {
    private let database: CiderDatabase
    private let lifecycle: SecondBrainReviewLifecycleService
    private let evidence: SecondBrainSourceEvidenceService

    init(database: CiderDatabase = .shared) {
        self.database = database
        self.lifecycle = SecondBrainReviewLifecycleService(database: database)
        self.evidence = SecondBrainSourceEvidenceService(database: database)
    }

    func propose(
        targetRef: String,
        proposedState: String,
        sourceOwner: SecondBrainOwnerRef,
        sourceQuote: String,
        actor: String,
        reason: String,
        supersedesRef: String? = nil,
        supersededByRef: String? = nil,
        validAt: Date? = nil,
        invalidAt: Date? = nil,
        expiredAt: Date? = nil,
        source: String = "fact_validity.propose",
        metadata: [String: String] = [:]
    ) throws -> SecondBrainFactValidityCandidateView {
        let now = Date()
        var candidate = SecondBrainFactValidityCandidate(
            targetRef: targetRef,
            proposedState: normalizedState(proposedState),
            validAt: validAt,
            invalidAt: invalidAt,
            expiredAt: expiredAt,
            supersedesRef: supersedesRef,
            supersededByRef: supersededByRef,
            sourceOwner: sourceOwner,
            sourceQuote: sourceQuote,
            reason: reason,
            source: source,
            actor: actor,
            metadata: metadata,
            createdAt: now,
            updatedAt: now
        )
        let evidenceRecord = SecondBrainSourceEvidenceRecord(
            evidenceKind: "fact_validity_evidence",
            sourceOwner: sourceOwner,
            sourceKind: sourceOwner.ownerType,
            sourceQuote: sourceQuote,
            observedAt: validAt,
            extractedAt: now,
            extractionSource: source,
            derivedOwner: SecondBrainOwnerRef(ownerType: "fact_validity_candidate", ownerID: candidate.id),
            derivedKind: candidate.proposedState,
            candidateRef: candidate.candidateRef,
            metadata: [
                "target_ref": targetRef,
                "proposed_state": candidate.proposedState,
            ].merging(metadata) { current, _ in current }
        )
        try evidence.record(evidenceRecord)
        let storedEvidence = try evidence.record(derivedOwner: evidenceRecord.derivedOwner, evidenceKind: evidenceRecord.evidenceKind) ?? evidenceRecord
        candidate.sourceEvidenceID = storedEvidence.id
        candidate.sourceEvidenceRef = "source_evidence:\(storedEvidence.id)"
        try insert(candidate)
        try recordLifecycle(candidate, eventKind: "suggested", actor: actor, reason: reason, sourceEvidence: storedEvidence)
        return try view(candidateID: candidate.id)
    }

    func accept(candidateID: String, actor: String, decisionNote: String? = nil) throws -> SecondBrainFactValidityCandidateView {
        var candidate = try requireCandidate(candidateID)
        guard candidate.reviewState != "accepted" else { return try view(candidateID: candidateID) }
        let previousState = candidate.reviewState
        candidate.reviewState = "accepted"
        candidate.reviewedAt = Date()
        candidate.updatedAt = candidate.reviewedAt ?? Date()
        candidate.decisionNote = decisionNote
        try update(candidate)
        let sourceEvidence = try sourceEvidenceRecord(for: candidate)
        try recordLifecycle(
            candidate,
            eventKind: "accepted",
            actor: actor,
            reason: decisionNote ?? candidate.reason,
            previousState: previousState,
            sourceEvidence: sourceEvidence
        )
        try recordAcceptedTargetLifecycle(candidate, actor: actor, decisionNote: decisionNote, sourceEvidence: sourceEvidence)
        return try view(candidateID: candidateID)
    }

    func reject(candidateID: String, actor: String, reason: String) throws -> SecondBrainFactValidityCandidateView {
        try transition(candidateID: candidateID, to: "rejected", actor: actor, reason: reason, decisionNote: reason)
    }

    func deferReview(candidateID: String, actor: String, reason: String) throws -> SecondBrainFactValidityCandidateView {
        try transition(candidateID: candidateID, to: "deferred", actor: actor, reason: reason, decisionNote: reason)
    }

    func candidates(reviewStates: [String] = ["suggested", "needs_review", "deferred"]) throws -> [SecondBrainFactValidityCandidateView] {
        let placeholders = reviewStates.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT id, target_ref, proposed_state, valid_at, invalid_at, expired_at,
                   supersedes_ref, superseded_by_ref, source_owner_type, source_owner_id,
                   source_quote, reason, review_state, source, actor,
                   source_evidence_id, source_evidence_ref, decision_note, metadata,
                   created_at, updated_at, reviewed_at
            FROM fact_validity_candidates
            WHERE review_state IN (\(placeholders))
            ORDER BY updated_at DESC;
            """
        let stmt = try database.prepare(sql)
        for (index, state) in reviewStates.enumerated() { stmt.bind(state, at: Int32(index + 1)) }
        return try collect(stmt).map { try view(candidate: $0) }
    }

    func candidate(id: String) throws -> SecondBrainFactValidityCandidateView? {
        try candidateRow(id).map { try view(candidate: $0) }
    }

    func validityState(targetRef: String) throws -> SecondBrainFactValidityState? {
        let stmt = try database.prepare("""
            SELECT id, target_ref, proposed_state, valid_at, invalid_at, expired_at,
                   supersedes_ref, superseded_by_ref, source_owner_type, source_owner_id,
                   source_quote, reason, review_state, source, actor,
                   source_evidence_id, source_evidence_ref, decision_note, metadata,
                   created_at, updated_at, reviewed_at
            FROM fact_validity_candidates
            WHERE target_ref = ? AND review_state = 'accepted'
            ORDER BY reviewed_at DESC, updated_at DESC
            LIMIT 1;
            """)
        stmt.bind(targetRef, at: 1)
        guard try stmt.step() else { return nil }
        let candidate = candidate(from: stmt)
        let sourceEvidence = try sourceEvidenceRecord(for: candidate)
        let history = try lifecycle.events(owner: SecondBrainOwnerRef(ownerType: "fact_validity_candidate", ownerID: candidate.id))
        return SecondBrainFactValidityState(
            targetRef: targetRef,
            currentState: candidate.proposedState,
            isCurrent: isCurrentState(candidate.proposedState),
            validAt: candidate.validAt,
            invalidAt: candidate.invalidAt,
            expiredAt: candidate.expiredAt,
            supersedesRef: candidate.supersedesRef,
            supersededByRef: candidate.supersededByRef,
            acceptedCandidate: candidate,
            sourceEvidenceRecord: sourceEvidence,
            lifecycleHistory: history
        )
    }

    private func transition(candidateID: String, to reviewState: String, actor: String, reason: String, decisionNote: String?) throws -> SecondBrainFactValidityCandidateView {
        var candidate = try requireCandidate(candidateID)
        let previousState = candidate.reviewState
        candidate.reviewState = reviewState
        candidate.reviewedAt = Date()
        candidate.updatedAt = candidate.reviewedAt ?? Date()
        candidate.decisionNote = decisionNote
        try update(candidate)
        let sourceEvidence = try sourceEvidenceRecord(for: candidate)
        try recordLifecycle(candidate, eventKind: reviewState, actor: actor, reason: reason, previousState: previousState, sourceEvidence: sourceEvidence)
        return try view(candidateID: candidateID)
    }

    private func insert(_ candidate: SecondBrainFactValidityCandidate) throws {
        let stmt = try database.prepare("""
            INSERT INTO fact_validity_candidates (
                id, target_ref, proposed_state, valid_at, invalid_at, expired_at,
                supersedes_ref, superseded_by_ref, source_owner_type, source_owner_id,
                source_quote, reason, review_state, source, actor,
                source_evidence_id, source_evidence_ref, decision_note, metadata,
                created_at, updated_at, reviewed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        bind(candidate, to: stmt)
        try stmt.step()
    }

    private func update(_ candidate: SecondBrainFactValidityCandidate) throws {
        let stmt = try database.prepare("""
            UPDATE fact_validity_candidates
            SET target_ref = ?, proposed_state = ?, valid_at = ?, invalid_at = ?, expired_at = ?,
                supersedes_ref = ?, superseded_by_ref = ?, source_owner_type = ?, source_owner_id = ?,
                source_quote = ?, reason = ?, review_state = ?, source = ?, actor = ?,
                source_evidence_id = ?, source_evidence_ref = ?, decision_note = ?, metadata = ?,
                updated_at = ?, reviewed_at = ?
            WHERE id = ?;
            """)
        stmt.bind(candidate.targetRef, at: 1)
            .bind(candidate.proposedState, at: 2)
            .bind(candidate.validAt.map(DatabaseHelpers.encode), at: 3)
            .bind(candidate.invalidAt.map(DatabaseHelpers.encode), at: 4)
            .bind(candidate.expiredAt.map(DatabaseHelpers.encode), at: 5)
            .bind(candidate.supersedesRef, at: 6)
            .bind(candidate.supersededByRef, at: 7)
            .bind(candidate.sourceOwner.ownerType, at: 8)
            .bind(candidate.sourceOwner.ownerID, at: 9)
            .bind(candidate.sourceQuote, at: 10)
            .bind(candidate.reason, at: 11)
            .bind(candidate.reviewState, at: 12)
            .bind(candidate.source, at: 13)
            .bind(candidate.actor, at: 14)
            .bind(candidate.sourceEvidenceID, at: 15)
            .bind(candidate.sourceEvidenceRef, at: 16)
            .bind(candidate.decisionNote, at: 17)
            .bind(DatabaseHelpers.encodeJSON(candidate.metadata) ?? "{}", at: 18)
            .bind(DatabaseHelpers.encode(candidate.updatedAt), at: 19)
            .bind(candidate.reviewedAt.map(DatabaseHelpers.encode), at: 20)
            .bind(candidate.id, at: 21)
        try stmt.step()
    }

    private func bind(_ candidate: SecondBrainFactValidityCandidate, to stmt: SQLStatement) {
        stmt.bind(candidate.id, at: 1)
            .bind(candidate.targetRef, at: 2)
            .bind(candidate.proposedState, at: 3)
            .bind(candidate.validAt.map(DatabaseHelpers.encode), at: 4)
            .bind(candidate.invalidAt.map(DatabaseHelpers.encode), at: 5)
            .bind(candidate.expiredAt.map(DatabaseHelpers.encode), at: 6)
            .bind(candidate.supersedesRef, at: 7)
            .bind(candidate.supersededByRef, at: 8)
            .bind(candidate.sourceOwner.ownerType, at: 9)
            .bind(candidate.sourceOwner.ownerID, at: 10)
            .bind(candidate.sourceQuote, at: 11)
            .bind(candidate.reason, at: 12)
            .bind(candidate.reviewState, at: 13)
            .bind(candidate.source, at: 14)
            .bind(candidate.actor, at: 15)
            .bind(candidate.sourceEvidenceID, at: 16)
            .bind(candidate.sourceEvidenceRef, at: 17)
            .bind(candidate.decisionNote, at: 18)
            .bind(DatabaseHelpers.encodeJSON(candidate.metadata) ?? "{}", at: 19)
            .bind(DatabaseHelpers.encode(candidate.createdAt), at: 20)
            .bind(DatabaseHelpers.encode(candidate.updatedAt), at: 21)
            .bind(candidate.reviewedAt.map(DatabaseHelpers.encode), at: 22)
    }

    private func requireCandidate(_ id: String) throws -> SecondBrainFactValidityCandidate {
        guard let candidate = try candidateRow(id) else {
            throw NSError(domain: "SecondBrainFactValidityService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Fact validity candidate not found: \(id)"])
        }
        return candidate
    }

    private func candidateRow(_ id: String) throws -> SecondBrainFactValidityCandidate? {
        let stmt = try database.prepare("""
            SELECT id, target_ref, proposed_state, valid_at, invalid_at, expired_at,
                   supersedes_ref, superseded_by_ref, source_owner_type, source_owner_id,
                   source_quote, reason, review_state, source, actor,
                   source_evidence_id, source_evidence_ref, decision_note, metadata,
                   created_at, updated_at, reviewed_at
            FROM fact_validity_candidates
            WHERE id = ?;
            """)
        stmt.bind(id, at: 1)
        guard try stmt.step() else { return nil }
        return candidate(from: stmt)
    }

    private func collect(_ stmt: SQLStatement) throws -> [SecondBrainFactValidityCandidate] {
        var rows: [SecondBrainFactValidityCandidate] = []
        while try stmt.step() { rows.append(candidate(from: stmt)) }
        return rows
    }

    private func candidate(from stmt: SQLStatement) -> SecondBrainFactValidityCandidate {
        SecondBrainFactValidityCandidate(
            id: stmt.string(at: 0),
            targetRef: stmt.string(at: 1),
            proposedState: stmt.string(at: 2),
            validAt: stmt.optionalDouble(at: 3).map(DatabaseHelpers.decodeDate),
            invalidAt: stmt.optionalDouble(at: 4).map(DatabaseHelpers.decodeDate),
            expiredAt: stmt.optionalDouble(at: 5).map(DatabaseHelpers.decodeDate),
            supersedesRef: stmt.optionalString(at: 6),
            supersededByRef: stmt.optionalString(at: 7),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 8), ownerID: stmt.string(at: 9)),
            sourceQuote: stmt.string(at: 10),
            reason: stmt.string(at: 11),
            reviewState: stmt.string(at: 12),
            source: stmt.string(at: 13),
            actor: stmt.string(at: 14),
            sourceEvidenceID: stmt.optionalString(at: 15),
            sourceEvidenceRef: stmt.optionalString(at: 16),
            decisionNote: stmt.optionalString(at: 17),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 18)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 19)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 20)),
            reviewedAt: stmt.optionalDouble(at: 21).map(DatabaseHelpers.decodeDate)
        )
    }

    private func view(candidateID: String) throws -> SecondBrainFactValidityCandidateView {
        try view(candidate: requireCandidate(candidateID))
    }

    private func view(candidate: SecondBrainFactValidityCandidate) throws -> SecondBrainFactValidityCandidateView {
        let sourceEvidence = try sourceEvidenceRecord(for: candidate)
        let history = try lifecycle.events(owner: SecondBrainOwnerRef(ownerType: "fact_validity_candidate", ownerID: candidate.id))
        return SecondBrainFactValidityCandidateView(candidate: candidate, sourceEvidenceRecord: sourceEvidence, lifecycleHistory: history)
    }

    private func sourceEvidenceRecord(for candidate: SecondBrainFactValidityCandidate) throws -> SecondBrainSourceEvidenceRecord? {
        try evidence.record(derivedOwner: SecondBrainOwnerRef(ownerType: "fact_validity_candidate", ownerID: candidate.id), evidenceKind: "fact_validity_evidence")
    }

    private func recordLifecycle(
        _ candidate: SecondBrainFactValidityCandidate,
        eventKind: String,
        actor: String,
        reason: String?,
        previousState: String? = nil,
        sourceEvidence: SecondBrainSourceEvidenceRecord?
    ) throws {
        var metadata: [String: String] = [
            "target_ref": candidate.targetRef,
            "proposed_state": candidate.proposedState,
            "review_state": candidate.reviewState,
        ]
        if let previousState { metadata["previous_state"] = previousState }
        try lifecycle.record(SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "fact_validity_candidate", ownerID: candidate.id),
            candidateRef: candidate.candidateRef,
            lifecycleState: candidate.reviewState,
            eventKind: eventKind,
            actor: actor,
            source: candidate.source,
            toolName: "fact_validity.\(eventKind)",
            reason: reason,
            decisionNote: candidate.decisionNote,
            sourceEvidenceID: sourceEvidence?.id,
            sourceEvidenceRef: sourceEvidence.map { "source_evidence:\($0.id)" },
            supersedesRef: candidate.supersedesRef,
            invalidatesRef: candidate.proposedState == "invalidated" ? candidate.targetRef : nil,
            metadata: metadata,
            createdAt: candidate.updatedAt
        ))
    }

    private func recordAcceptedTargetLifecycle(
        _ candidate: SecondBrainFactValidityCandidate,
        actor: String,
        decisionNote: String?,
        sourceEvidence: SecondBrainSourceEvidenceRecord?
    ) throws {
        guard candidate.reviewState == "accepted" else { return }
        let owner = ownerRef(from: candidate.targetRef) ?? SecondBrainOwnerRef(ownerType: "fact_ref", ownerID: candidate.targetRef)
        try lifecycle.record(SecondBrainReviewLifecycleEvent(
            owner: owner,
            candidateRef: candidate.candidateRef,
            lifecycleState: candidate.proposedState,
            eventKind: candidate.proposedState,
            actor: actor,
            source: "fact_validity.accept",
            toolName: "fact_validity.accept",
            reason: candidate.reason,
            decisionNote: decisionNote,
            sourceEvidenceID: sourceEvidence?.id,
            sourceEvidenceRef: sourceEvidence.map { "source_evidence:\($0.id)" },
            supersedesRef: candidate.supersedesRef,
            invalidatesRef: candidate.proposedState == "invalidated" ? candidate.targetRef : nil,
            metadata: [
                "target_ref": candidate.targetRef,
                "fact_validity_candidate_ref": candidate.candidateRef,
                "proposed_state": candidate.proposedState,
            ],
            createdAt: candidate.updatedAt
        ))
    }

    private func normalizedState(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "invalidated", "invalid", "stale": return "invalidated"
        case "superseded", "supersedes": return "superseded"
        case "expired", "expires": return "expired"
        case "current", "valid": return "current"
        default: return value.isEmpty ? "needs_review" : value
        }
    }

    private func isCurrentState(_ state: String) -> Bool {
        !["invalidated", "superseded", "expired", "rejected"].contains(state)
    }

    private func ownerRef(from ref: String) -> SecondBrainOwnerRef? {
        guard let separator = ref.firstIndex(of: ":") else { return nil }
        let type = String(ref[..<separator])
        let id = String(ref[ref.index(after: separator)...])
        guard !type.isEmpty, !id.isEmpty else { return nil }
        return SecondBrainOwnerRef(ownerType: type, ownerID: id)
    }
}
