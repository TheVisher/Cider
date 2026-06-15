import Foundation

struct SecondBrainSourceEvidenceRecord: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var evidenceKind: String = "source_span"
    var sourceOwner: SecondBrainOwnerRef
    var sourceKind: String?
    var sourceQuote: String
    var spanStart: Int?
    var spanEnd: Int?
    var observedAt: Date?
    var capturedAt: Date?
    var extractedAt: Date?
    var extractionSource: String
    var extractionRunID: String?
    var extractionProvider: String?
    var extractionModel: String?
    var derivedOwner: SecondBrainOwnerRef
    var derivedKind: String
    var candidateRef: String?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var sourceOwnerRef: String { sourceOwner.canonicalRef }
    var derivedOwnerRef: String { derivedOwner.canonicalRef }
}

@MainActor
final class SecondBrainSourceEvidenceService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func record(_ record: SecondBrainSourceEvidenceRecord) throws {
        let now = Date()
        let metadata = DatabaseHelpers.encodeJSON(record.metadata) ?? "{}"
        let stmt = try database.prepare("""
            INSERT INTO source_evidence (
                id, evidence_kind, source_owner_type, source_owner_id, source_kind,
                source_quote, span_start, span_end, observed_at, captured_at, extracted_at,
                extraction_source, extraction_run_id, extraction_provider, extraction_model,
                derived_owner_type, derived_owner_id, derived_kind, candidate_ref, metadata,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(derived_owner_type, derived_owner_id, evidence_kind)
            DO UPDATE SET
                source_owner_type = excluded.source_owner_type,
                source_owner_id = excluded.source_owner_id,
                source_kind = excluded.source_kind,
                source_quote = excluded.source_quote,
                span_start = excluded.span_start,
                span_end = excluded.span_end,
                observed_at = excluded.observed_at,
                captured_at = excluded.captured_at,
                extracted_at = excluded.extracted_at,
                extraction_source = excluded.extraction_source,
                extraction_run_id = excluded.extraction_run_id,
                extraction_provider = excluded.extraction_provider,
                extraction_model = excluded.extraction_model,
                derived_kind = excluded.derived_kind,
                candidate_ref = excluded.candidate_ref,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(record.id, at: 1)
            .bind(record.evidenceKind, at: 2)
            .bind(record.sourceOwner.ownerType, at: 3)
            .bind(record.sourceOwner.ownerID, at: 4)
            .bind(record.sourceKind, at: 5)
            .bind(record.sourceQuote, at: 6)
            .bind(record.spanStart.map(Int64.init), at: 7)
            .bind(record.spanEnd.map(Int64.init), at: 8)
            .bind(record.observedAt.map(DatabaseHelpers.encode), at: 9)
            .bind(record.capturedAt.map(DatabaseHelpers.encode), at: 10)
            .bind(record.extractedAt.map(DatabaseHelpers.encode), at: 11)
            .bind(record.extractionSource, at: 12)
            .bind(record.extractionRunID, at: 13)
            .bind(record.extractionProvider, at: 14)
            .bind(record.extractionModel, at: 15)
            .bind(record.derivedOwner.ownerType, at: 16)
            .bind(record.derivedOwner.ownerID, at: 17)
            .bind(record.derivedKind, at: 18)
            .bind(record.candidateRef, at: 19)
            .bind(metadata, at: 20)
            .bind(DatabaseHelpers.encode(record.createdAt), at: 21)
            .bind(DatabaseHelpers.encode(record.updatedAt > record.createdAt ? record.updatedAt : now), at: 22)
        try stmt.step()
    }

    func record(for output: SecondBrainEnrichmentOutput) throws -> SecondBrainSourceEvidenceRecord? {
        let record = Self.recordFromOutput(output)
        if let record { try self.record(record) }
        return record
    }

    func record(for relation: SecondBrainRelation) throws -> SecondBrainSourceEvidenceRecord? {
        let record = Self.recordFromRelation(relation)
        if let record { try self.record(record) }
        return record
    }

    func record(derivedOwner: SecondBrainOwnerRef, evidenceKind: String = "source_span") throws -> SecondBrainSourceEvidenceRecord? {
        let stmt = try database.prepare("""
            SELECT id, evidence_kind, source_owner_type, source_owner_id, source_kind,
                   source_quote, span_start, span_end, observed_at, captured_at, extracted_at,
                   extraction_source, extraction_run_id, extraction_provider, extraction_model,
                   derived_owner_type, derived_owner_id, derived_kind, candidate_ref, metadata,
                   created_at, updated_at
            FROM source_evidence
            WHERE derived_owner_type = ? AND derived_owner_id = ? AND evidence_kind = ?
            LIMIT 1;
            """)
        stmt.bind(derivedOwner.ownerType, at: 1)
            .bind(derivedOwner.ownerID, at: 2)
            .bind(evidenceKind, at: 3)
        guard try stmt.step() else { return nil }
        return record(from: stmt)
    }

    static func recordFromOutput(_ output: SecondBrainEnrichmentOutput) -> SecondBrainSourceEvidenceRecord? {
        let quote = normalizedWhitespace(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote] ?? output.evidence)
        guard !quote.isEmpty else { return nil }
        let sourceOwner = sourceOwner(from: output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceOwnerRef]) ?? output.owner
        let derivedOwner = SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: output.id)
        let candidateRef = output.kind == SecondBrainGraphCandidateContract.outputKind ? "graph_candidate:\(output.id)" : output.metadata["candidate_ref"]
        var metadata: [String: String] = [
            "source_owner_ref": sourceOwner.canonicalRef,
            "derived_owner_ref": derivedOwner.canonicalRef,
            "output_kind": output.kind,
            "output_review_state": output.reviewState,
        ]
        if let chunkID = output.chunkID { metadata["chunk_id"] = chunkID }
        if let mention = output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mentionText] ?? output.metadata["memory_key"] {
            metadata["mention_text"] = mention
        }
        return SecondBrainSourceEvidenceRecord(
            evidenceKind: output.metadata["source_evidence_kind"] ?? "source_span",
            sourceOwner: sourceOwner,
            sourceKind: output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceKind] ?? output.metadata["source_kind"],
            sourceQuote: quote,
            spanStart: intValue(output.metadata["source_span_start"]),
            spanEnd: intValue(output.metadata["source_span_end"]),
            observedAt: dateValue(output.metadata["observed_at"]),
            capturedAt: dateValue(output.metadata["captured_at"]),
            extractedAt: output.createdAt,
            extractionSource: output.source,
            extractionRunID: output.metadata["extraction_run_id"],
            extractionProvider: output.metadata["extraction_provider"],
            extractionModel: output.metadata["extraction_model"],
            derivedOwner: derivedOwner,
            derivedKind: output.kind,
            candidateRef: candidateRef,
            metadata: metadata,
            createdAt: output.createdAt,
            updatedAt: output.updatedAt
        )
    }

    static func recordFromRelation(_ relation: SecondBrainRelation) -> SecondBrainSourceEvidenceRecord? {
        let quote = normalizedWhitespace(relation.metadata["source_quote"] ?? relation.evidence)
        guard !quote.isEmpty else { return nil }
        let sourceOwner = sourceOwner(from: relation.metadata["source_owner_ref"]) ?? relation.sourceOwner
        let derivedOwner = SecondBrainOwnerRef(ownerType: "owner_relation", ownerID: relation.id)
        var metadata: [String: String] = [
            "source_owner_ref": sourceOwner.canonicalRef,
            "derived_owner_ref": derivedOwner.canonicalRef,
            "relation_type": relation.relationType,
            "relation_source": relation.source,
            "target_owner_ref": relation.targetOwner.canonicalRef,
        ]
        if let mention = relation.metadata["mention_text"] { metadata["mention_text"] = mention }
        if let candidateRef = relation.metadata["candidate_ref"] { metadata["candidate_ref"] = candidateRef }
        return SecondBrainSourceEvidenceRecord(
            evidenceKind: relation.metadata["source_evidence_kind"] ?? "source_span",
            sourceOwner: sourceOwner,
            sourceKind: relation.metadata["source_kind"],
            sourceQuote: quote,
            spanStart: intValue(relation.metadata["source_span_start"]),
            spanEnd: intValue(relation.metadata["source_span_end"]),
            observedAt: dateValue(relation.metadata["observed_at"]),
            capturedAt: dateValue(relation.metadata["captured_at"]),
            extractedAt: relation.createdAt,
            extractionSource: relation.source,
            extractionRunID: relation.metadata["extraction_run_id"],
            extractionProvider: relation.metadata["extraction_provider"],
            extractionModel: relation.metadata["extraction_model"],
            derivedOwner: derivedOwner,
            derivedKind: "owner_relation",
            candidateRef: relation.metadata["candidate_ref"] ?? relation.metadata["candidate_id"].map { "graph_candidate:\($0)" },
            metadata: metadata,
            createdAt: relation.createdAt,
            updatedAt: relation.updatedAt
        )
    }

    private func record(from stmt: SQLStatement) -> SecondBrainSourceEvidenceRecord {
        SecondBrainSourceEvidenceRecord(
            id: stmt.string(at: 0),
            evidenceKind: stmt.string(at: 1),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 2), ownerID: stmt.string(at: 3)),
            sourceKind: stmt.optionalString(at: 4),
            sourceQuote: stmt.string(at: 5),
            spanStart: stmt.optionalInt(at: 6),
            spanEnd: stmt.optionalInt(at: 7),
            observedAt: stmt.optionalDouble(at: 8).map(DatabaseHelpers.decodeDate),
            capturedAt: stmt.optionalDouble(at: 9).map(DatabaseHelpers.decodeDate),
            extractedAt: stmt.optionalDouble(at: 10).map(DatabaseHelpers.decodeDate),
            extractionSource: stmt.string(at: 11),
            extractionRunID: stmt.optionalString(at: 12),
            extractionProvider: stmt.optionalString(at: 13),
            extractionModel: stmt.optionalString(at: 14),
            derivedOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 15), ownerID: stmt.string(at: 16)),
            derivedKind: stmt.string(at: 17),
            candidateRef: stmt.optionalString(at: 18),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 19)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 20)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 21))
        )
    }

    private static func normalizedWhitespace(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intValue(_ raw: String?) -> Int? {
        raw.flatMap { Int($0) }
    }

    private static func dateValue(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return DatabaseHelpers.decodeDate(seconds) }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func sourceOwner(from raw: String?) -> SecondBrainOwnerRef? {
        guard let raw, let separator = raw.firstIndex(of: ":") else { return nil }
        let type = String(raw[..<separator])
        let id = String(raw[raw.index(after: separator)...])
        guard !type.isEmpty, !id.isEmpty else { return nil }
        return SecondBrainOwnerRef(ownerType: type, ownerID: id)
    }
}
