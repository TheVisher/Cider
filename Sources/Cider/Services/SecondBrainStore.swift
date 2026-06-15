import Foundation

struct SecondBrainOwnerRef: Codable, Equatable, Hashable {
    var ownerType: String
    var ownerID: String

    var canonicalRef: String {
        "\(ownerType):\(ownerID)"
    }
}

struct SecondBrainSection: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef
    var itemID: String?
    var sectionKey: String
    var title: String
    var body: String
    var source: String
    var confidence: Double?
    var metadata: [String: String] = [:]
    var sortOrder: Int
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct SecondBrainChunkDraft: Codable, Equatable {
    var sectionID: String?
    var itemID: String?
    var source: String
    var title: String
    var body: String
    var chunkIndex: Int
    var metadata: [String: String] = [:]
}

struct SecondBrainChunkSearchResult: Identifiable, Codable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var title: String
    var snippet: String
    var rank: Double
}

struct SecondBrainRoutingDecision: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef
    var itemID: String?
    var targetType: String
    var targetID: String?
    var targetPath: String?
    var confidence: Double
    var reason: String
    var status: String
    var actor: String
    var source: String
    var candidatesJSON: String?
    var createdAt: Date = Date()
    var reviewedAt: Date?
}

struct SecondBrainAgentAction: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var owner: SecondBrainOwnerRef
    var itemID: String?
    var toolName: String
    var actionType: String
    var source: String
    var status: String
    var summary: String
    var argumentsJSON: String?
    var resultJSON: String?
    var createdAt: Date = Date()
}

struct SecondBrainRelation: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var sourceOwner: SecondBrainOwnerRef
    var targetOwner: SecondBrainOwnerRef
    var relationType: String
    var evidence: String
    var source: String
    var actor: String
    var confidence: Double?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

@MainActor
final class SecondBrainStore {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func upsertSection(_ section: SecondBrainSection) throws {
        let now = Date()
        let createdAt = DatabaseHelpers.encode(section.createdAt)
        let updatedAt = DatabaseHelpers.encode(section.updatedAt > section.createdAt ? section.updatedAt : now)
        let metadata = DatabaseHelpers.encodeJSON(section.metadata) ?? "{}"

        let stmt = try database.prepare("""
            INSERT INTO item_sections (
                id, item_id, owner_type, owner_id, section_key, title, body,
                source, confidence, metadata, sort_order, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_type, owner_id, section_key) DO UPDATE SET
                item_id = excluded.item_id,
                title = excluded.title,
                body = excluded.body,
                source = excluded.source,
                confidence = excluded.confidence,
                metadata = excluded.metadata,
                sort_order = excluded.sort_order,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(section.id, at: 1)
            .bind(section.itemID, at: 2)
            .bind(section.owner.ownerType, at: 3)
            .bind(section.owner.ownerID, at: 4)
            .bind(section.sectionKey, at: 5)
            .bind(section.title, at: 6)
            .bind(section.body, at: 7)
            .bind(section.source, at: 8)
            .bind(section.confidence, at: 9)
            .bind(metadata, at: 10)
            .bind(section.sortOrder, at: 11)
            .bind(createdAt, at: 12)
            .bind(updatedAt, at: 13)
        try stmt.step()
    }

    func sections(for owner: SecondBrainOwnerRef) throws -> [SecondBrainSection] {
        let stmt = try database.prepare("""
            SELECT id, item_id, section_key, title, body, source, confidence,
                   metadata, sort_order, created_at, updated_at
            FROM item_sections
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY sort_order ASC, title COLLATE NOCASE ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var sections: [SecondBrainSection] = []
        while try stmt.step() {
            sections.append(
                SecondBrainSection(
                    id: stmt.string(at: 0),
                    owner: owner,
                    itemID: stmt.optionalString(at: 1),
                    sectionKey: stmt.string(at: 2),
                    title: stmt.string(at: 3),
                    body: stmt.string(at: 4),
                    source: stmt.string(at: 5),
                    confidence: stmt.optionalDouble(at: 6),
                    metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 7)) ?? [:],
                    sortOrder: stmt.int(at: 8),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 9)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 10))
                )
            )
        }
        return sections
    }

    func deleteSections(for owner: SecondBrainOwnerRef, keeping sectionKeys: Set<String>) throws {
        if sectionKeys.isEmpty {
            let stmt = try database.prepare("""
                DELETE FROM item_sections
                WHERE owner_type = ? AND owner_id = ?;
                """)
            stmt.bind(owner.ownerType, at: 1)
                .bind(owner.ownerID, at: 2)
            try stmt.step()
            return
        }

        let placeholders = Array(repeating: "?", count: sectionKeys.count).joined(separator: ", ")
        let stmt = try database.prepare("""
            DELETE FROM item_sections
            WHERE owner_type = ? AND owner_id = ?
              AND section_key NOT IN (\(placeholders));
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        for (index, key) in sectionKeys.sorted().enumerated() {
            stmt.bind(key, at: Int32(index + 3))
        }
        try stmt.step()
    }

    func replaceChunks(owner: SecondBrainOwnerRef, chunks: [SecondBrainChunkDraft]) throws {
        try database.withTransaction {
            let deleteStmt = try database.prepare("""
                DELETE FROM content_chunks
                WHERE owner_type = ? AND owner_id = ?;
                """)
            deleteStmt.bind(owner.ownerType, at: 1)
                .bind(owner.ownerID, at: 2)
            try deleteStmt.step()

            for chunk in chunks {
                try insertChunk(owner: owner, chunk: chunk)
            }
        }
    }

    func replaceProjection(
        owner: SecondBrainOwnerRef,
        sections: [SecondBrainSection],
        keeping sectionKeys: Set<String>,
        chunks: [SecondBrainChunkDraft]
    ) throws {
        try database.withTransaction {
            for section in sections {
                try upsertSection(section)
            }

            try deleteSections(for: owner, keeping: sectionKeys)

            let deleteChunks = try database.prepare("""
                DELETE FROM content_chunks
                WHERE owner_type = ? AND owner_id = ?;
                """)
            deleteChunks.bind(owner.ownerType, at: 1)
                .bind(owner.ownerID, at: 2)
            try deleteChunks.step()

            for chunk in chunks {
                try insertChunk(owner: owner, chunk: chunk)
            }
        }
    }

    func deleteProjection(for owner: SecondBrainOwnerRef) throws {
        try deleteOwnerFootprint(for: owner)
    }

    func deleteOwnerFootprint(for owner: SecondBrainOwnerRef) throws {
        try database.withTransaction {
            try deleteProjectionRows(for: owner)
            try deleteOwnerSidecars(for: owner)
        }
    }

    func deleteProjections(ownerType: String, ownerIDPrefix: String) throws {
        try database.withTransaction {
            let likePrefix = ownerIDPrefix.replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            let deleteChunks = try database.prepare("""
                DELETE FROM content_chunks
                WHERE owner_type = ? AND owner_id LIKE ? ESCAPE '\\';
                """)
            deleteChunks.bind(ownerType, at: 1)
                .bind(likePrefix, at: 2)
            try deleteChunks.step()

            let deleteSections = try database.prepare("""
                DELETE FROM item_sections
                WHERE owner_type = ? AND owner_id LIKE ? ESCAPE '\\';
                """)
            deleteSections.bind(ownerType, at: 1)
                .bind(likePrefix, at: 2)
            try deleteSections.step()

            try deleteOwnerSidecars(ownerType: ownerType, ownerIDLike: likePrefix)
        }
    }

    private func deleteProjectionRows(for owner: SecondBrainOwnerRef) throws {
        let deleteChunks = try database.prepare("""
            DELETE FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?;
            """)
        deleteChunks.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        try deleteChunks.step()

        let deleteSections = try database.prepare("""
            DELETE FROM item_sections
            WHERE owner_type = ? AND owner_id = ?;
            """)
        deleteSections.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        try deleteSections.step()
    }

    private func deleteOwnerSidecars(for owner: SecondBrainOwnerRef) throws {
        try deleteOwnerSidecars(ownerType: owner.ownerType, ownerID: owner.ownerID)
    }

    private func deleteOwnerSidecars(ownerType: String, ownerID: String) throws {
        let deleteRelations = try database.prepare("""
            DELETE FROM owner_relations
            WHERE (source_owner_type = ? AND source_owner_id = ?)
               OR (target_owner_type = ? AND target_owner_id = ?);
            """)
        deleteRelations.bind(ownerType, at: 1)
            .bind(ownerID, at: 2)
            .bind(ownerType, at: 3)
            .bind(ownerID, at: 4)
        try deleteRelations.step()

        let ownerTables = [
            "second_brain_routing_decisions",
            "agent_actions",
            "enrichment_outputs",
        ]
        for table in ownerTables where try tableExists(table) {
            let stmt = try database.prepare("""
                DELETE FROM \(table)
                WHERE owner_type = ? AND owner_id = ?;
                """)
            stmt.bind(ownerType, at: 1)
                .bind(ownerID, at: 2)
            try stmt.step()
        }

        if try tableExists("source_evidence") {
            let deleteEvidence = try database.prepare("""
                DELETE FROM source_evidence
                WHERE (source_owner_type = ? AND source_owner_id = ?)
                   OR (derived_owner_type = ? AND derived_owner_id = ?);
                """)
            deleteEvidence.bind(ownerType, at: 1)
                .bind(ownerID, at: 2)
                .bind(ownerType, at: 3)
                .bind(ownerID, at: 4)
            try deleteEvidence.step()
        }

        if try tableExists("similarity_candidates") {
            let deleteSimilarity = try database.prepare("""
                DELETE FROM similarity_candidates
                WHERE (source_owner_type = ? AND source_owner_id = ?)
                   OR (target_owner_type = ? AND target_owner_id = ?);
                """)
            deleteSimilarity.bind(ownerType, at: 1)
                .bind(ownerID, at: 2)
                .bind(ownerType, at: 3)
                .bind(ownerID, at: 4)
            try deleteSimilarity.step()
        }
    }

    private func deleteOwnerSidecars(ownerType: String, ownerIDLike: String) throws {
        let deleteRelations = try database.prepare("""
            DELETE FROM owner_relations
            WHERE (source_owner_type = ? AND source_owner_id LIKE ? ESCAPE '\\')
               OR (target_owner_type = ? AND target_owner_id LIKE ? ESCAPE '\\');
            """)
        deleteRelations.bind(ownerType, at: 1)
            .bind(ownerIDLike, at: 2)
            .bind(ownerType, at: 3)
            .bind(ownerIDLike, at: 4)
        try deleteRelations.step()

        let ownerTables = [
            "second_brain_routing_decisions",
            "agent_actions",
            "enrichment_outputs",
        ]
        for table in ownerTables where try tableExists(table) {
            let stmt = try database.prepare("""
                DELETE FROM \(table)
                WHERE owner_type = ? AND owner_id LIKE ? ESCAPE '\\';
                """)
            stmt.bind(ownerType, at: 1)
                .bind(ownerIDLike, at: 2)
            try stmt.step()
        }

        if try tableExists("source_evidence") {
            let deleteEvidence = try database.prepare("""
                DELETE FROM source_evidence
                WHERE (source_owner_type = ? AND source_owner_id LIKE ? ESCAPE '\\')
                   OR (derived_owner_type = ? AND derived_owner_id LIKE ? ESCAPE '\\');
                """)
            deleteEvidence.bind(ownerType, at: 1)
                .bind(ownerIDLike, at: 2)
                .bind(ownerType, at: 3)
                .bind(ownerIDLike, at: 4)
            try deleteEvidence.step()
        }

        if try tableExists("similarity_candidates") {
            let deleteSimilarity = try database.prepare("""
                DELETE FROM similarity_candidates
                WHERE (source_owner_type = ? AND source_owner_id LIKE ? ESCAPE '\\')
                   OR (target_owner_type = ? AND target_owner_id LIKE ? ESCAPE '\\');
                """)
            deleteSimilarity.bind(ownerType, at: 1)
                .bind(ownerIDLike, at: 2)
                .bind(ownerType, at: 3)
                .bind(ownerIDLike, at: 4)
            try deleteSimilarity.step()
        }
    }

    func searchChunks(query: String, limit: Int = 20) throws -> [SecondBrainChunkSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let stmt = try database.prepare("""
            SELECT c.id,
                   c.owner_type,
                   c.owner_id,
                   c.title,
                   snippet(content_chunks_fts, 1, '[', ']', '...', 16),
                   bm25(content_chunks_fts)
            FROM content_chunks_fts
            JOIN content_chunks c ON c.rowid = content_chunks_fts.rowid
            WHERE content_chunks_fts MATCH ?
            ORDER BY bm25(content_chunks_fts)
            LIMIT ?;
            """)
        stmt.bind(sanitizeFTSQuery(trimmed), at: 1)
            .bind(max(1, limit), at: 2)

        var results: [SecondBrainChunkSearchResult] = []
        while try stmt.step() {
            results.append(
                SecondBrainChunkSearchResult(
                    id: stmt.string(at: 0),
                    owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
                    title: stmt.string(at: 3),
                    snippet: stmt.string(at: 4),
                    rank: stmt.double(at: 5)
                )
            )
        }
        return results
    }

    func recordRoutingDecision(_ decision: SecondBrainRoutingDecision) throws {
        let stmt = try database.prepare("""
            INSERT INTO second_brain_routing_decisions (
                id, item_id, owner_type, owner_id, target_type, target_id,
                target_path, confidence, reason, status, actor, source,
                candidates_json, created_at, reviewed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(decision.id, at: 1)
            .bind(decision.itemID, at: 2)
            .bind(decision.owner.ownerType, at: 3)
            .bind(decision.owner.ownerID, at: 4)
            .bind(decision.targetType, at: 5)
            .bind(decision.targetID, at: 6)
            .bind(decision.targetPath, at: 7)
            .bind(decision.confidence, at: 8)
            .bind(decision.reason, at: 9)
            .bind(decision.status, at: 10)
            .bind(decision.actor, at: 11)
            .bind(decision.source, at: 12)
            .bind(decision.candidatesJSON, at: 13)
            .bind(DatabaseHelpers.encode(decision.createdAt), at: 14)
            .bind(decision.reviewedAt.map(DatabaseHelpers.encode), at: 15)
        try stmt.step()
    }

    func routingDecisions(for owner: SecondBrainOwnerRef) throws -> [SecondBrainRoutingDecision] {
        guard try tableExists("second_brain_routing_decisions") else {
            return []
        }

        let stmt = try database.prepare("""
            SELECT id, item_id, target_type, target_id, target_path, confidence,
                   reason, status, actor, source, candidates_json, created_at, reviewed_at
            FROM second_brain_routing_decisions
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY created_at ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var decisions: [SecondBrainRoutingDecision] = []
        while try stmt.step() {
            decisions.append(
                SecondBrainRoutingDecision(
                    id: stmt.string(at: 0),
                    owner: owner,
                    itemID: stmt.optionalString(at: 1),
                    targetType: stmt.string(at: 2),
                    targetID: stmt.optionalString(at: 3),
                    targetPath: stmt.optionalString(at: 4),
                    confidence: stmt.double(at: 5),
                    reason: stmt.string(at: 6),
                    status: stmt.string(at: 7),
                    actor: stmt.string(at: 8),
                    source: stmt.string(at: 9),
                    candidatesJSON: stmt.optionalString(at: 10),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11)),
                    reviewedAt: stmt.optionalDouble(at: 12).map(DatabaseHelpers.decodeDate)
                )
            )
        }
        return decisions
    }

    private func tableExists(_ tableName: String) throws -> Bool {
        let stmt = try database.prepare("""
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1;
            """)
        stmt.bind(tableName, at: 1)
        return try stmt.step()
    }

    func recordAgentAction(_ action: SecondBrainAgentAction) throws {
        let stmt = try database.prepare("""
            INSERT INTO agent_actions (
                id, item_id, owner_type, owner_id, tool_name, action_type,
                source, status, summary, arguments_json, result_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(action.id, at: 1)
            .bind(action.itemID, at: 2)
            .bind(action.owner.ownerType, at: 3)
            .bind(action.owner.ownerID, at: 4)
            .bind(action.toolName, at: 5)
            .bind(action.actionType, at: 6)
            .bind(action.source, at: 7)
            .bind(action.status, at: 8)
            .bind(action.summary, at: 9)
            .bind(action.argumentsJSON, at: 10)
            .bind(action.resultJSON, at: 11)
            .bind(DatabaseHelpers.encode(action.createdAt), at: 12)
        try stmt.step()
    }

    func agentActions(for owner: SecondBrainOwnerRef) throws -> [SecondBrainAgentAction] {
        let stmt = try database.prepare("""
            SELECT id, item_id, tool_name, action_type, source, status, summary,
                   arguments_json, result_json, created_at
            FROM agent_actions
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY created_at ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var actions: [SecondBrainAgentAction] = []
        while try stmt.step() {
            actions.append(
                SecondBrainAgentAction(
                    id: stmt.string(at: 0),
                    owner: owner,
                    itemID: stmt.optionalString(at: 1),
                    toolName: stmt.string(at: 2),
                    actionType: stmt.string(at: 3),
                    source: stmt.string(at: 4),
                    status: stmt.string(at: 5),
                    summary: stmt.string(at: 6),
                    argumentsJSON: stmt.optionalString(at: 7),
                    resultJSON: stmt.optionalString(at: 8),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 9))
                )
            )
        }
        return actions
    }

    func recordRelation(_ relation: SecondBrainRelation) throws {
        guard relation.sourceOwner != relation.targetOwner else { return }
        var relation = relation
        let evidenceRecord = SecondBrainSourceEvidenceService.recordFromRelation(relation)
        if let evidenceRecord {
            relation.metadata["source_evidence_id"] = evidenceRecord.id
            relation.metadata["source_evidence_ref"] = "source_evidence:\(evidenceRecord.id)"
            relation.metadata["source_evidence_kind"] = evidenceRecord.evidenceKind
            relation.metadata["source_owner_ref"] = evidenceRecord.sourceOwnerRef
            relation.metadata["derived_owner_ref"] = evidenceRecord.derivedOwnerRef
        }
        let now = Date()
        let createdAt = DatabaseHelpers.encode(relation.createdAt)
        let updatedAt = DatabaseHelpers.encode(relation.updatedAt > relation.createdAt ? relation.updatedAt : now)
        let metadata = DatabaseHelpers.encodeJSON(relation.metadata) ?? "{}"

        let stmt = try database.prepare("""
            INSERT INTO owner_relations (
                id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, source)
            DO UPDATE SET
                evidence = excluded.evidence,
                actor = excluded.actor,
                confidence = excluded.confidence,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(relation.id, at: 1)
            .bind(relation.sourceOwner.ownerType, at: 2)
            .bind(relation.sourceOwner.ownerID, at: 3)
            .bind(relation.targetOwner.ownerType, at: 4)
            .bind(relation.targetOwner.ownerID, at: 5)
            .bind(relation.relationType, at: 6)
            .bind(relation.evidence, at: 7)
            .bind(relation.source, at: 8)
            .bind(relation.actor, at: 9)
            .bind(relation.confidence, at: 10)
            .bind(metadata, at: 11)
            .bind(createdAt, at: 12)
            .bind(updatedAt, at: 13)
        try stmt.step()
        if let evidenceRecord {
            try SecondBrainSourceEvidenceService(database: database).record(evidenceRecord)
        }
    }

    func replaceRelations(
        sourceOwner: SecondBrainOwnerRef,
        sourcePrefix: String,
        with relations: [SecondBrainRelation]
    ) throws {
        try database.withTransaction {
            let escapedPrefix = sourcePrefix
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let deleteStmt = try database.prepare("""
                DELETE FROM owner_relations
                WHERE source_owner_type = ?
                  AND source_owner_id = ?
                  AND source LIKE ? ESCAPE '\\';
                """)
            deleteStmt.bind(sourceOwner.ownerType, at: 1)
                .bind(sourceOwner.ownerID, at: 2)
                .bind("\(escapedPrefix)%", at: 3)
            try deleteStmt.step()

            for relation in relations {
                try recordRelation(relation)
            }
        }
    }

    func outgoingRelations(for owner: SecondBrainOwnerRef) throws -> [SecondBrainRelation] {
        var relations = try storedRelations(
            owner: owner,
            sql: """
                SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                       relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at
                FROM owner_relations
                WHERE source_owner_type = ? AND source_owner_id = ?
                ORDER BY updated_at DESC, relation_type COLLATE NOCASE ASC;
                """
        )
        relations.append(contentsOf: try bridgedItemLinkRelations(for: owner, direction: .outgoing))
        return uniqueRelations(relations)
    }

    func backlinks(for owner: SecondBrainOwnerRef) throws -> [SecondBrainRelation] {
        var relations = try storedRelations(
            owner: owner,
            sql: """
                SELECT id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                       relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at
                FROM owner_relations
                WHERE target_owner_type = ? AND target_owner_id = ?
                ORDER BY updated_at DESC, relation_type COLLATE NOCASE ASC;
                """
        )
        relations.append(contentsOf: try bridgedItemLinkRelations(for: owner, direction: .backlink))
        return uniqueRelations(relations)
    }

    func relatedRelations(for owner: SecondBrainOwnerRef) throws -> [SecondBrainRelation] {
        try uniqueRelations(outgoingRelations(for: owner) + backlinks(for: owner))
    }

    private func insertChunk(owner: SecondBrainOwnerRef, chunk: SecondBrainChunkDraft) throws {
        let now = Date()
        let body = chunk.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        let stmt = try database.prepare("""
            INSERT INTO content_chunks (
                id, section_id, item_id, owner_type, owner_id, source, title,
                body, chunk_index, content_hash, metadata, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(UUID().uuidString, at: 1)
            .bind(chunk.sectionID, at: 2)
            .bind(chunk.itemID, at: 3)
            .bind(owner.ownerType, at: 4)
            .bind(owner.ownerID, at: 5)
            .bind(chunk.source, at: 6)
            .bind(chunk.title, at: 7)
            .bind(body, at: 8)
            .bind(chunk.chunkIndex, at: 9)
            .bind(Self.contentHash(title: chunk.title, body: body), at: 10)
            .bind(DatabaseHelpers.encodeJSON(chunk.metadata) ?? "{}", at: 11)
            .bind(DatabaseHelpers.encode(now), at: 12)
            .bind(DatabaseHelpers.encode(now), at: 13)
        try stmt.step()
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { term in
                term
                    .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            }
            .filter { !$0.isEmpty }

        return terms.isEmpty
            ? quotedFTSTerm(query)
            : terms.map { quotedFTSTerm(String($0)) }.joined(separator: " ")
    }

    private func quotedFTSTerm(_ term: String) -> String {
        "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func contentHash(title: String, body: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(title)\n\(body)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private enum ItemLinkBridgeDirection {
        case outgoing
        case backlink
    }

    private func storedRelations(owner: SecondBrainOwnerRef, sql: String) throws -> [SecondBrainRelation] {
        guard try tableExists("owner_relations") else { return [] }
        let stmt = try database.prepare(sql)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var relations: [SecondBrainRelation] = []
        while try stmt.step() {
            relations.append(relation(from: stmt))
        }
        return relations
    }

    private func relation(from stmt: SQLStatement) -> SecondBrainRelation {
        SecondBrainRelation(
            id: stmt.string(at: 0),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
            targetOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 3), ownerID: stmt.string(at: 4)),
            relationType: stmt.string(at: 5),
            evidence: stmt.string(at: 6),
            source: stmt.string(at: 7),
            actor: stmt.string(at: 8),
            confidence: stmt.optionalDouble(at: 9),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 10)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 12))
        )
    }

    private func bridgedItemLinkRelations(
        for owner: SecondBrainOwnerRef,
        direction: ItemLinkBridgeDirection
    ) throws -> [SecondBrainRelation] {
        guard let ownerType = libraryEntityType(owner.ownerType),
              UUID(uuidString: owner.ownerID) != nil else {
            return []
        }
        let databaseType = ItemLinkService.databaseItemType(for: ownerType)
        let existsStmt = try database.prepare("SELECT 1 FROM items WHERE id = ? AND type = ? LIMIT 1;")
        existsStmt.bind(owner.ownerID, at: 1)
            .bind(databaseType, at: 2)
        guard try existsStmt.step() else { return [] }

        let sql: String
        switch direction {
        case .outgoing:
            sql = """
                SELECT l.source_id, si.type, l.target_id, ti.type, l.link_type, l.created_at
                FROM item_links l
                JOIN items si ON si.id = l.source_id
                JOIN items ti ON ti.id = l.target_id
                WHERE l.source_id = ?
                ORDER BY l.created_at ASC, ti.title COLLATE NOCASE ASC;
                """
        case .backlink:
            sql = """
                SELECT l.source_id, si.type, l.target_id, ti.type, l.link_type, l.created_at
                FROM item_links l
                JOIN items si ON si.id = l.source_id
                JOIN items ti ON ti.id = l.target_id
                WHERE l.target_id = ?
                ORDER BY l.created_at ASC, si.title COLLATE NOCASE ASC;
                """
        }

        let stmt = try database.prepare(sql)
        stmt.bind(owner.ownerID, at: 1)
        var relations: [SecondBrainRelation] = []
        while try stmt.step() {
            guard let sourceType = libraryEntityTypeFromDatabase(stmt.string(at: 1)),
                  let targetType = libraryEntityTypeFromDatabase(stmt.string(at: 3)) else {
                continue
            }
            let sourceOwner = SecondBrainOwnerRef(ownerType: sourceType.rawValue, ownerID: stmt.string(at: 0))
            let targetOwner = SecondBrainOwnerRef(ownerType: targetType.rawValue, ownerID: stmt.string(at: 2))
            let linkType = stmt.string(at: 4)
            let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 5))
            relations.append(SecondBrainRelation(
                id: "item_links:\(sourceOwner.canonicalRef):\(targetOwner.canonicalRef):\(linkType)",
                sourceOwner: sourceOwner,
                targetOwner: targetOwner,
                relationType: linkType,
                evidence: "Bridged from item_links.",
                source: "item_links",
                actor: "system",
                confidence: 1,
                metadata: ["bridge": "item_links"],
                createdAt: createdAt,
                updatedAt: createdAt
            ))
        }
        return relations
    }

    private func libraryEntityType(_ raw: String) -> LibraryEntityType? {
        let normalized = raw == "event" ? "dateCard" : raw
        guard let type = LibraryEntityType(rawValue: normalized),
              LibraryEntityType.activeCases.contains(type) else {
            return nil
        }
        return type
    }

    private func libraryEntityTypeFromDatabase(_ raw: String) -> LibraryEntityType? {
        libraryEntityType(raw)
    }

    private func uniqueRelations(_ relations: [SecondBrainRelation]) -> [SecondBrainRelation] {
        var seen = Set<String>()
        var output: [SecondBrainRelation] = []
        for relation in relations {
            let key = [
                relation.sourceOwner.canonicalRef,
                relation.targetOwner.canonicalRef,
                relation.relationType,
                relation.source,
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            output.append(relation)
        }
        return output
    }
}
