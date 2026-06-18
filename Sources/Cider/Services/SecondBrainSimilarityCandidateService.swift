import Foundation

struct SecondBrainSimilarityCandidate: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var sourceOwner: SecondBrainOwnerRef
    var targetOwner: SecondBrainOwnerRef
    var candidateType: String
    var signal: String
    var score: Double
    var reason: String
    var evidence: String
    var source: String = "chunk_overlap"
    var reviewState: String = "suggested"
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var reviewedAt: Date?
}

struct SecondBrainSimilarityRebuildResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var candidateCount: Int
    var signal: String
}

struct SecondBrainSimilarityReconciliationRun: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef?
    var trigger: String
    var scope: String
    var threshold: Double
    var candidateLimit: Int
    var selectedCount: Int
    var createdCount: Int
    var updatedCount: Int
    var unchangedCount: Int
    var staleCount: Int
    var unseededCount: Int
    var candidateFamilies: [String: Int]
    var metadata: [String: String] = [:]
    var startedAt: Date = Date()
    var finishedAt: Date = Date()
}

struct SecondBrainSimilarityHealthReport: Codable, Equatable {
    var owner: SecondBrainOwnerRef?
    var totalCandidates: Int
    var staleCount: Int
    var unseededCount: Int
    var lastRun: SecondBrainSimilarityReconciliationRun?
    var candidateFamilies: [String: Int]
    var safeRepairCommands: [String]
    var checkedAt: Date = Date()
}

struct SecondBrainSimilarityReconcileResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var changed: Bool
    var selectedCount: Int
    var createdOrUpdatedCount: Int
    var unchangedCount: Int
    var candidates: [SecondBrainSimilarityCandidate]
    var health: SecondBrainSimilarityHealthReport
    var run: SecondBrainSimilarityReconciliationRun
    var truthBoundary: String = "reviewable_candidate_not_truth"
}

@MainActor
final class SecondBrainSimilarityCandidateService {
    enum SimilarityError: LocalizedError {
        case candidateNotFound(String)

        var errorDescription: String? {
            switch self {
            case .candidateNotFound(let id):
                "Similarity candidate '\(id)' not found."
            }
        }
    }

    private struct ChunkDocument {
        var owner: SecondBrainOwnerRef
        var text: String
        var tokens: Set<String>
    }

    private let database: CiderDatabase
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
    }

    func candidates(for owner: SecondBrainOwnerRef) throws -> [SecondBrainSimilarityCandidate] {
        let stmt = try database.prepare("""
            SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                   candidate_type, signal, score, reason, evidence, source, review_state,
                   metadata, created_at, updated_at, reviewed_at
            FROM similarity_candidates
            WHERE source_owner_type = ? AND source_owner_id = ?
            ORDER BY review_state COLLATE NOCASE ASC, score DESC, updated_at DESC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var candidates: [SecondBrainSimilarityCandidate] = []
        while try stmt.step() {
            candidates.append(candidate(from: stmt))
        }
        return candidates
    }

    func reviewableCandidates(limit: Int = 20) throws -> [SecondBrainSimilarityCandidate] {
        let stmt = try database.prepare("""
            SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                   candidate_type, signal, score, reason, evidence, source, review_state,
                   metadata, created_at, updated_at, reviewed_at
            FROM similarity_candidates
            WHERE review_state IS NULL OR review_state NOT IN ('accepted', 'rejected')
            ORDER BY score DESC, updated_at DESC
            LIMIT ?;
            """)
        stmt.bind(max(0, limit), at: 1)
        var candidates: [SecondBrainSimilarityCandidate] = []
        while try stmt.step() {
            candidates.append(candidate(from: stmt))
        }
        return candidates
    }

    func health(owner: SecondBrainOwnerRef? = nil, staleAfter: TimeInterval = 86_400) throws -> SecondBrainSimilarityHealthReport {
        let candidates = try similarityCandidates(owner: owner)
        var families: [String: Int] = ["chunk_overlap": 0, "entity_enrichment": 0]
        for candidate in candidates where candidate.reviewState != "accepted" {
            families[candidate.signal, default: 0] += 1
        }
        let cutoff = Date().addingTimeInterval(-max(1, staleAfter))
        let staleCount = candidates.filter { $0.reviewState != "accepted" && $0.updatedAt < cutoff }.count
        let unseededCount: Int
        if let owner {
            unseededCount = try ownerNeedsSimilaritySeeding(owner) && candidates.filter { $0.reviewState != "accepted" }.isEmpty ? 1 : 0
        } else {
            unseededCount = try unseededOwnerCount()
        }
        return SecondBrainSimilarityHealthReport(
            owner: owner,
            totalCandidates: candidates.count,
            staleCount: staleCount,
            unseededCount: unseededCount,
            lastRun: try lastRun(owner: owner),
            candidateFamilies: families,
            safeRepairCommands: similaritySafeRepairCommands(owner: owner),
            checkedAt: Date()
        )
    }

    func reconcile(
        owner: SecondBrainOwnerRef,
        threshold: Double = 0.34,
        limit: Int = 10,
        actor: String = "agent",
        trigger: String = "manual_reconcile"
    ) throws -> SecondBrainSimilarityReconcileResult {
        let started = Date()
        let before = try candidates(for: owner)
        let beforeSignatures = Set(before.map(candidateSignature))
        _ = try rebuildChunkOverlapCandidates(for: owner, threshold: threshold, limit: limit)
        let after = try candidates(for: owner)
        for candidate in after where candidate.reviewState != "accepted" {
            try ensureEvidenceAndLifecycle(for: candidate, actor: actor)
        }
        let afterSignatures = Set(after.map(candidateSignature))
        let changed = beforeSignatures != afterSignatures
        let createdOrUpdated = afterSignatures.subtracting(beforeSignatures).count
        let unchanged = afterSignatures.intersection(beforeSignatures).count
        let healthBeforeRun = try health(owner: owner)
        let run = SecondBrainSimilarityReconciliationRun(
            owner: owner,
            trigger: trigger,
            scope: "owner",
            threshold: threshold,
            candidateLimit: limit,
            selectedCount: 1,
            createdCount: createdOrUpdated,
            updatedCount: changed ? max(0, after.count - createdOrUpdated) : 0,
            unchangedCount: unchanged,
            staleCount: healthBeforeRun.staleCount,
            unseededCount: healthBeforeRun.unseededCount,
            candidateFamilies: healthBeforeRun.candidateFamilies,
            metadata: [
                "truth_boundary": "reviewable_candidate_not_truth",
                "actor": actor,
            ],
            startedAt: started,
            finishedAt: Date()
        )
        try recordRun(run)
        let finalHealth = try health(owner: owner)
        return SecondBrainSimilarityReconcileResult(
            owner: owner,
            changed: changed,
            selectedCount: 1,
            createdOrUpdatedCount: createdOrUpdated,
            unchangedCount: unchanged,
            candidates: after,
            health: finalHealth,
            run: run
        )
    }

    func sourceEvidenceRecord(for candidate: SecondBrainSimilarityCandidate) throws -> SecondBrainSourceEvidenceRecord? {
        let service = SecondBrainSourceEvidenceService(database: database)
        let derivedOwner = SecondBrainOwnerRef(ownerType: "similarity_candidate", ownerID: candidate.id)
        let record = SecondBrainSourceEvidenceRecord(
            sourceOwner: candidate.sourceOwner,
            sourceKind: candidate.signal,
            sourceQuote: candidate.evidence,
            extractedAt: candidate.updatedAt,
            extractionSource: candidate.source,
            derivedOwner: derivedOwner,
            derivedKind: candidate.candidateType,
            candidateRef: "similarity_candidate:\(candidate.id)",
            metadata: candidate.metadata.merging([
                "target_owner_ref": candidate.targetOwner.canonicalRef,
                "signal": candidate.signal,
                "reason": candidate.reason,
            ]) { current, _ in current },
            createdAt: candidate.createdAt,
            updatedAt: candidate.updatedAt
        )
        try service.record(record)
        return try service.record(derivedOwner: derivedOwner)
    }

    func lifecycleHistory(for candidate: SecondBrainSimilarityCandidate) throws -> [SecondBrainReviewLifecycleEvent] {
        try SecondBrainReviewLifecycleService(database: database).events(candidateRef: "similarity_candidate:\(candidate.id)")
    }

    func rebuildChunkOverlapCandidates(
        for owner: SecondBrainOwnerRef,
        threshold: Double = 0.34,
        limit: Int = 10
    ) throws -> SecondBrainSimilarityRebuildResult {
        guard let sourceDocument = try document(for: owner) else {
            try replaceSuggestedChunkOverlapCandidates(for: owner, with: [])
            return SecondBrainSimilarityRebuildResult(owner: owner, candidateCount: 0, signal: "chunk_overlap")
        }

        let candidates = try allDocuments(excluding: owner).compactMap { target -> SecondBrainSimilarityCandidate? in
            let overlap = sourceDocument.tokens.intersection(target.tokens)
            let union = sourceDocument.tokens.union(target.tokens)
            guard !union.isEmpty else { return nil }
            let score = Double(overlap.count) / Double(union.count)
            guard score >= threshold else { return nil }

            let overlapTerms = overlap.sorted().prefix(8).joined(separator: ", ")
            let candidateType = score >= 0.9 ? "duplicates" : "similar_to"
            return SecondBrainSimilarityCandidate(
                sourceOwner: owner,
                targetOwner: target.owner,
                candidateType: candidateType,
                signal: "chunk_overlap",
                score: score,
                reason: "Shared deterministic content terms from content_chunks.",
                evidence: "overlap \(overlap.count)/\(union.count): \(overlapTerms)",
                source: "chunk_overlap",
                reviewState: "suggested",
                metadata: [
                    "overlap_count": "\(overlap.count)",
                    "union_count": "\(union.count)",
                    "reason_codes": "chunk_overlap,content_terms",
                    "truth_boundary": "reviewable_candidate_not_truth",
                    "target_owner_ref": target.owner.canonicalRef,
                ]
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.targetOwner.canonicalRef < rhs.targetOwner.canonicalRef
        }
        .prefix(max(0, limit))

        let limited = Array(candidates)
        try replaceSuggestedChunkOverlapCandidates(for: owner, with: limited)
        return SecondBrainSimilarityRebuildResult(owner: owner, candidateCount: limited.count, signal: "chunk_overlap")
    }

    func rebuildEntityRelationCandidates(
        for owner: SecondBrainOwnerRef,
        targetTypes: [String] = ["contact"],
        limit: Int = 10
    ) throws -> SecondBrainSimilarityRebuildResult {
        let supportedTargetTypes = Set(targetTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard !supportedTargetTypes.isEmpty else {
            try replaceSuggestedEntityRelationCandidates(for: owner, with: [])
            return SecondBrainSimilarityRebuildResult(owner: owner, candidateCount: 0, signal: "entity_enrichment")
        }

        let outputs = try entityOutputs(for: owner)
        let contacts = supportedTargetTypes.contains("contact") ? try contactTargets() : []
        var candidates: [SecondBrainSimilarityCandidate] = []
        var seenTargets = Set<String>()

        for output in outputs {
            guard output.reviewState == "suggested" || output.reviewState == "needs_review" else { continue }
            guard let contact = contacts.first(where: { $0.normalizedName == output.normalizedValue }) else { continue }
            let target = SecondBrainOwnerRef(ownerType: "contact", ownerID: contact.id)
            guard owner != target else { continue }
            guard seenTargets.insert(target.canonicalRef).inserted else { continue }
            candidates.append(SecondBrainSimilarityCandidate(
                sourceOwner: owner,
                targetOwner: target,
                candidateType: "mentions",
                signal: "entity_enrichment",
                score: output.confidence.map { max($0, 0.8) } ?? 0.8,
                reason: "Detected entity enrichment matches an existing contact title.",
                evidence: output.evidence,
                source: "enrichment_output",
                reviewState: "suggested",
                metadata: [
                    "enrichment_output_id": output.id,
                    "matched_entity": output.value,
                    "target_title": contact.title,
                    "target_type": "contact",
                    "reason_codes": "entity_enrichment,existing_contact_match",
                    "truth_boundary": "reviewable_candidate_not_truth",
                    "target_owner_ref": target.canonicalRef,
                ]
            ))
        }

        let limited = Array(candidates.prefix(max(0, limit)))
        try replaceSuggestedEntityRelationCandidates(for: owner, with: limited)
        return SecondBrainSimilarityRebuildResult(owner: owner, candidateCount: limited.count, signal: "entity_enrichment")
    }

    func accept(candidateID: String, relationType: String? = nil, actor: String = "agent") throws -> SecondBrainSimilarityCandidate {
        let current = try candidate(id: candidateID)
        let acceptedType = relationType ?? current.candidateType
        let now = Date()

        try database.withTransaction {
            let update = try database.prepare("""
                UPDATE similarity_candidates
                SET review_state = 'accepted',
                    updated_at = ?,
                    reviewed_at = ?
                WHERE id = ?;
                """)
            let encodedNow = DatabaseHelpers.encode(now)
            update.bind(encodedNow, at: 1)
                .bind(encodedNow, at: 2)
                .bind(candidateID, at: 3)
            try update.step()

            let candidateEvidence = try sourceEvidenceRecord(for: current)
            try SecondBrainReviewLifecycleService(database: database).record(SecondBrainReviewLifecycleEvent(
                owner: SecondBrainOwnerRef(ownerType: "similarity_candidate", ownerID: current.id),
                candidateRef: "similarity_candidate:\(current.id)",
                lifecycleState: "accepted",
                eventKind: "accepted",
                actor: actor,
                source: "similarity_candidate.accept",
                toolName: "item.accept-similarity",
                reason: "Explicitly accepted similarity candidate into owner relation.",
                sourceEvidenceID: candidateEvidence?.id,
                sourceEvidenceRef: candidateEvidence.map { "source_evidence:\($0.id)" },
                metadata: [
                    "truth_boundary": "accepted_relation_requires_explicit_command",
                    "signal": current.signal,
                    "candidate_type": current.candidateType,
                    "accepted_relation_type": acceptedType,
                ],
                createdAt: now
            ))

            try store.recordRelation(SecondBrainRelation(
                sourceOwner: current.sourceOwner,
                targetOwner: current.targetOwner,
                relationType: acceptedType,
                evidence: current.evidence,
                source: "similarity_candidate",
                actor: actor,
                confidence: current.score,
                metadata: [
                    "candidate_id": current.id,
                    "candidate_ref": "similarity_candidate:\(current.id)",
                    "candidate_type": current.candidateType,
                    "signal": current.signal,
                    "reason": current.reason,
                    "source_quote": current.evidence,
                    "source_owner_ref": current.sourceOwner.canonicalRef,
                    "truth_boundary": "accepted_relation_requires_explicit_command",
                ],
                createdAt: now,
                updatedAt: now
            ))
        }

        return try candidate(id: candidateID)
    }

    private func replaceSuggestedChunkOverlapCandidates(
        for owner: SecondBrainOwnerRef,
        with candidates: [SecondBrainSimilarityCandidate]
    ) throws {
        try database.withTransaction {
            for candidate in candidates {
                try record(candidate)
            }
        }
    }

    private struct EntityRelationTarget {
        var id: String
        var title: String
        var normalizedName: String
    }

    private func entityOutputs(for owner: SecondBrainOwnerRef) throws -> [SecondBrainEnrichmentOutput] {
        try SecondBrainEnrichmentOutputService(database: database)
            .outputs(for: owner)
            .filter { $0.kind == "entity" }
    }

    private func contactTargets() throws -> [EntityRelationTarget] {
        let stmt = try database.prepare("""
            SELECT i.id, i.title
            FROM items i
            JOIN contacts c ON c.item_id = i.id
            WHERE i.type = 'contact'
            ORDER BY i.title COLLATE NOCASE ASC;
            """)
        var targets: [EntityRelationTarget] = []
        while try stmt.step() {
            let title = stmt.string(at: 1)
            targets.append(EntityRelationTarget(
                id: stmt.string(at: 0),
                title: title,
                normalizedName: normalizedEntityName(title)
            ))
        }
        return targets
    }

    private func replaceSuggestedEntityRelationCandidates(
        for owner: SecondBrainOwnerRef,
        with candidates: [SecondBrainSimilarityCandidate]
    ) throws {
        try database.withTransaction {
            for candidate in candidates {
                try record(candidate)
            }
        }
    }

    private func record(_ candidate: SecondBrainSimilarityCandidate) throws {
        guard candidate.sourceOwner != candidate.targetOwner else { return }
        let now = Date()
        let createdAt = DatabaseHelpers.encode(candidate.createdAt)
        let updatedAt = DatabaseHelpers.encode(candidate.updatedAt > candidate.createdAt ? candidate.updatedAt : now)
        let metadata = DatabaseHelpers.encodeJSON(candidate.metadata) ?? "{}"
        let reviewedAt = candidate.reviewedAt.map(DatabaseHelpers.encode)

        let stmt = try database.prepare("""
            INSERT INTO similarity_candidates (
                id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                candidate_type, signal, score, reason, evidence, source, review_state,
                metadata, created_at, updated_at, reviewed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_owner_type, source_owner_id, target_owner_type, target_owner_id, candidate_type, signal, source)
            DO UPDATE SET
                score = excluded.score,
                reason = excluded.reason,
                evidence = excluded.evidence,
                metadata = excluded.metadata,
                review_state = CASE
                    WHEN similarity_candidates.review_state = 'accepted' THEN similarity_candidates.review_state
                    ELSE excluded.review_state
                END,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(candidate.id, at: 1)
            .bind(candidate.sourceOwner.ownerType, at: 2)
            .bind(candidate.sourceOwner.ownerID, at: 3)
            .bind(candidate.targetOwner.ownerType, at: 4)
            .bind(candidate.targetOwner.ownerID, at: 5)
            .bind(candidate.candidateType, at: 6)
            .bind(candidate.signal, at: 7)
            .bind(candidate.score, at: 8)
            .bind(candidate.reason, at: 9)
            .bind(candidate.evidence, at: 10)
            .bind(candidate.source, at: 11)
            .bind(candidate.reviewState, at: 12)
            .bind(metadata, at: 13)
            .bind(createdAt, at: 14)
            .bind(updatedAt, at: 15)
            .bind(reviewedAt, at: 16)
        try stmt.step()
    }

    private func candidate(id: String) throws -> SecondBrainSimilarityCandidate {
        let stmt = try database.prepare("""
            SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                   candidate_type, signal, score, reason, evidence, source, review_state,
                   metadata, created_at, updated_at, reviewed_at
            FROM similarity_candidates
            WHERE id = ?
            LIMIT 1;
            """)
        stmt.bind(id, at: 1)
        guard try stmt.step() else {
            throw SimilarityError.candidateNotFound(id)
        }
        return candidate(from: stmt)
    }

    private func similarityCandidates(owner: SecondBrainOwnerRef?) throws -> [SecondBrainSimilarityCandidate] {
        let sql: String
        if owner == nil {
            sql = """
                SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                       candidate_type, signal, score, reason, evidence, source, review_state,
                       metadata, created_at, updated_at, reviewed_at
                FROM similarity_candidates
                ORDER BY updated_at DESC;
                """
        } else {
            sql = """
                SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                       candidate_type, signal, score, reason, evidence, source, review_state,
                       metadata, created_at, updated_at, reviewed_at
                FROM similarity_candidates
                WHERE source_owner_type = ? AND source_owner_id = ?
                ORDER BY updated_at DESC;
                """
        }
        let stmt = try database.prepare(sql)
        if let owner {
            stmt.bind(owner.ownerType, at: 1).bind(owner.ownerID, at: 2)
        }
        var candidates: [SecondBrainSimilarityCandidate] = []
        while try stmt.step() { candidates.append(candidate(from: stmt)) }
        return candidates
    }

    private func ownerNeedsSimilaritySeeding(_ owner: SecondBrainOwnerRef) throws -> Bool {
        guard try document(for: owner) != nil else { return false }
        return try !allDocuments(excluding: owner).isEmpty
    }

    private func unseededOwnerCount() throws -> Int {
        let stmt = try database.prepare("""
            WITH chunk_owners AS (
                SELECT owner_type, owner_id
                FROM content_chunks
                GROUP BY owner_type, owner_id
            ), owner_count AS (
                SELECT COUNT(*) AS total FROM chunk_owners
            )
            SELECT COUNT(*)
            FROM chunk_owners co, owner_count oc
            WHERE oc.total > 1
              AND NOT EXISTS (
                SELECT 1
                FROM similarity_candidates sc
                WHERE sc.source_owner_type = co.owner_type
                  AND sc.source_owner_id = co.owner_id
                  AND sc.review_state != 'accepted'
              );
            """)
        return try stmt.step() ? stmt.int(at: 0) : 0
    }

    private func candidateSignature(_ candidate: SecondBrainSimilarityCandidate) -> String {
        [
            candidate.sourceOwner.canonicalRef,
            candidate.targetOwner.canonicalRef,
            candidate.candidateType,
            candidate.signal,
            String(format: "%.4f", candidate.score),
            candidate.reason,
            candidate.evidence,
            candidate.source,
            candidate.reviewState,
            candidate.metadata.keys.sorted().map { "\($0)=\(candidate.metadata[$0] ?? "")" }.joined(separator: ","),
        ].joined(separator: "|")
    }

    private func similaritySafeRepairCommands(owner: SecondBrainOwnerRef?) -> [String] {
        if let owner {
            return [
                "cider-cli item similarity-health \(owner.ownerType) \(owner.ownerID) --json",
                "cider-cli item reconcile-similarity \(owner.ownerType) \(owner.ownerID) --limit 10 --json",
                "cider-cli item similarity \(owner.ownerType) \(owner.ownerID) --json",
            ]
        }
        return [
            "cider-cli item similarity-health --json",
            "cider-cli item reconcile-similarity <owner-type> <owner-id-or-ref> --limit 10 --json",
        ]
    }

    private func ensureEvidenceAndLifecycle(for candidate: SecondBrainSimilarityCandidate, actor: String) throws {
        let evidence = try sourceEvidenceRecord(for: candidate)
        let lifecycle = try lifecycleHistory(for: candidate)
        guard lifecycle.isEmpty else { return }
        try SecondBrainReviewLifecycleService(database: database).record(SecondBrainReviewLifecycleEvent(
            owner: SecondBrainOwnerRef(ownerType: "similarity_candidate", ownerID: candidate.id),
            candidateRef: "similarity_candidate:\(candidate.id)",
            lifecycleState: candidate.reviewState,
            eventKind: candidate.reviewState,
            actor: actor,
            source: candidate.source,
            toolName: "similarity.reconcile",
            reason: candidate.reason,
            sourceEvidenceID: evidence?.id,
            sourceEvidenceRef: evidence.map { "source_evidence:\($0.id)" },
            metadata: [
                "truth_boundary": "reviewable_candidate_not_truth",
                "signal": candidate.signal,
                "candidate_type": candidate.candidateType,
                "source_owner_ref": candidate.sourceOwner.canonicalRef,
                "target_owner_ref": candidate.targetOwner.canonicalRef,
            ],
            createdAt: candidate.updatedAt
        ))
    }

    private func recordRun(_ run: SecondBrainSimilarityReconciliationRun) throws {
        let stmt = try database.prepare("""
            INSERT INTO similarity_reconciliation_runs (
                id, owner_type, owner_id, trigger, scope, threshold, candidate_limit,
                selected_count, created_count, updated_count, unchanged_count,
                stale_count, unseeded_count, candidate_families, metadata,
                started_at, finished_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(run.id, at: 1)
            .bind(run.owner?.ownerType, at: 2)
            .bind(run.owner?.ownerID, at: 3)
            .bind(run.trigger, at: 4)
            .bind(run.scope, at: 5)
            .bind(run.threshold, at: 6)
            .bind(Int64(run.candidateLimit), at: 7)
            .bind(Int64(run.selectedCount), at: 8)
            .bind(Int64(run.createdCount), at: 9)
            .bind(Int64(run.updatedCount), at: 10)
            .bind(Int64(run.unchangedCount), at: 11)
            .bind(Int64(run.staleCount), at: 12)
            .bind(Int64(run.unseededCount), at: 13)
            .bind(DatabaseHelpers.encodeJSON(run.candidateFamilies) ?? "{}", at: 14)
            .bind(DatabaseHelpers.encodeJSON(run.metadata) ?? "{}", at: 15)
            .bind(DatabaseHelpers.encode(run.startedAt), at: 16)
            .bind(DatabaseHelpers.encode(run.finishedAt), at: 17)
        try stmt.step()
    }

    private func lastRun(owner: SecondBrainOwnerRef?) throws -> SecondBrainSimilarityReconciliationRun? {
        let sql: String
        if owner == nil {
            sql = """
                SELECT id, owner_type, owner_id, trigger, scope, threshold, candidate_limit,
                       selected_count, created_count, updated_count, unchanged_count,
                       stale_count, unseeded_count, candidate_families, metadata, started_at, finished_at
                FROM similarity_reconciliation_runs
                ORDER BY finished_at DESC
                LIMIT 1;
                """
        } else {
            sql = """
                SELECT id, owner_type, owner_id, trigger, scope, threshold, candidate_limit,
                       selected_count, created_count, updated_count, unchanged_count,
                       stale_count, unseeded_count, candidate_families, metadata, started_at, finished_at
                FROM similarity_reconciliation_runs
                WHERE owner_type = ? AND owner_id = ?
                ORDER BY finished_at DESC
                LIMIT 1;
                """
        }
        let stmt = try database.prepare(sql)
        if let owner {
            stmt.bind(owner.ownerType, at: 1).bind(owner.ownerID, at: 2)
        }
        guard try stmt.step() else { return nil }
        let ownerType = stmt.optionalString(at: 1)
        let ownerID = stmt.optionalString(at: 2)
        return SecondBrainSimilarityReconciliationRun(
            id: stmt.string(at: 0),
            owner: ownerType.flatMap { type in ownerID.map { SecondBrainOwnerRef(ownerType: type, ownerID: $0) } },
            trigger: stmt.string(at: 3),
            scope: stmt.string(at: 4),
            threshold: stmt.double(at: 5),
            candidateLimit: stmt.int(at: 6),
            selectedCount: stmt.int(at: 7),
            createdCount: stmt.int(at: 8),
            updatedCount: stmt.int(at: 9),
            unchangedCount: stmt.int(at: 10),
            staleCount: stmt.int(at: 11),
            unseededCount: stmt.int(at: 12),
            candidateFamilies: DatabaseHelpers.decodeJSON([String: Int].self, from: stmt.optionalString(at: 13)) ?? [:],
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 14)) ?? [:],
            startedAt: DatabaseHelpers.decodeDate(stmt.double(at: 15)),
            finishedAt: DatabaseHelpers.decodeDate(stmt.double(at: 16))
        )
    }

    private func document(for owner: SecondBrainOwnerRef) throws -> ChunkDocument? {
        let documents = try documents(whereSQL: "owner_type = ? AND owner_id = ?", bindings: [owner.ownerType, owner.ownerID])
        return documents.first
    }

    private func allDocuments(excluding owner: SecondBrainOwnerRef) throws -> [ChunkDocument] {
        try documents(
            whereSQL: "NOT (owner_type = ? AND owner_id = ?)",
            bindings: [owner.ownerType, owner.ownerID]
        )
    }

    private func documents(whereSQL: String, bindings: [String]) throws -> [ChunkDocument] {
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, group_concat(title || ' ' || body, ' ')
            FROM content_chunks
            WHERE \(whereSQL)
            GROUP BY owner_type, owner_id;
            """)
        for (index, binding) in bindings.enumerated() {
            stmt.bind(binding, at: Int32(index + 1))
        }

        var documents: [ChunkDocument] = []
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1))
            let text = stmt.string(at: 2)
            documents.append(ChunkDocument(owner: owner, text: text, tokens: tokens(in: text)))
        }
        return documents
    }

    private func tokens(in text: String) -> Set<String> {
        let matches = regexMatches(pattern: "[A-Za-z0-9][A-Za-z0-9_-]{2,}", in: text)
        return Set(matches.compactMap { raw in
            let value = raw.lowercased()
            guard !tokenStopwords.contains(value) else { return nil }
            return value
        })
    }

    private var tokenStopwords: Set<String> {
        [
            "and", "are", "but", "for", "from", "has", "have", "into", "not",
            "the", "this", "that", "with", "you", "your",
        ]
    }

    private func regexMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map {
            nsText.substring(with: $0.range)
        }
    }

    private func normalizedEntityName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func candidate(from stmt: SQLStatement) -> SecondBrainSimilarityCandidate {
        SecondBrainSimilarityCandidate(
            id: stmt.string(at: 0),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
            targetOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 3), ownerID: stmt.string(at: 4)),
            candidateType: stmt.string(at: 5),
            signal: stmt.string(at: 6),
            score: stmt.double(at: 7),
            reason: stmt.string(at: 8),
            evidence: stmt.string(at: 9),
            source: stmt.string(at: 10),
            reviewState: stmt.string(at: 11),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 12)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 13)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 14)),
            reviewedAt: stmt.optionalDouble(at: 15).map(DatabaseHelpers.decodeDate)
        )
    }
}
