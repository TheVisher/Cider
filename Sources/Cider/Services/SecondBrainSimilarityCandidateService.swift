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
                    "candidate_type": current.candidateType,
                    "signal": current.signal,
                    "reason": current.reason,
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
            let delete = try database.prepare("""
                DELETE FROM similarity_candidates
                WHERE source_owner_type = ?
                  AND source_owner_id = ?
                  AND source = 'chunk_overlap'
                  AND review_state != 'accepted';
                """)
            delete.bind(owner.ownerType, at: 1)
                .bind(owner.ownerID, at: 2)
            try delete.step()

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
