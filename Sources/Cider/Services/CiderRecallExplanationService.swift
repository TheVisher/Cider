import CryptoKit
import Foundation

struct CiderRecallScoreReason: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var kind: String
    var weight: Double
    var summary: String
    var owner: SecondBrainOwnerRef?
    var evidenceRef: String?
    var candidateRef: String?
    var relationID: String?
    var reviewState: String?
    var metadata: [String: String] = [:]
}

struct CiderRecallAccessEvent: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var surface: String
    var selectorKind: String
    var queryHash: String?
    var queryLength: Int?
    var queryTokenCount: Int?
    var anchorRefs: [String]
    var surfacedRefs: [String]
    var reasonKinds: [String]
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()

    var queryTextStored: Bool { false }
}

@MainActor
final class CiderRecallExplanationService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func anchorReasons(bundle: CiderItemContextBundle, query: String?, explicitItem: Bool) -> [CiderRecallScoreReason] {
        var reasons: [CiderRecallScoreReason] = []
        if explicitItem {
            reasons.append(CiderRecallScoreReason(
                kind: "explicit_item_anchor",
                weight: 1.0,
                summary: "Bundle was anchored by an explicit item selector.",
                owner: bundle.owner,
                evidenceRef: bundle.owner.canonicalRef
            ))
        }
        if queryMatches(query, bundle: bundle) {
            reasons.append(CiderRecallScoreReason(
                kind: "query_match",
                weight: 0.8,
                summary: "Query matched indexed item content or metadata.",
                owner: bundle.owner,
                evidenceRef: bundle.owner.canonicalRef,
                metadata: sanitizedQueryMetadata(query)
            ))
        }
        if !bundle.captureProvenance.isEmpty {
            reasons.append(CiderRecallScoreReason(
                kind: "capture_provenance",
                weight: 0.35,
                summary: "Item has capture provenance available for audit.",
                owner: bundle.owner,
                evidenceRef: bundle.owner.canonicalRef
            ))
        }
        if !bundle.routingDecisions.isEmpty {
            reasons.append(CiderRecallScoreReason(
                kind: "routing_signal",
                weight: 0.25,
                summary: "Routing decisions are available for this owner.",
                owner: bundle.owner,
                evidenceRef: bundle.owner.canonicalRef
            ))
        }
        if !bundle.ownerRelations.isEmpty || !bundle.backlinks.isEmpty {
            reasons.append(CiderRecallScoreReason(
                kind: "graph_link_signal",
                weight: 0.4,
                summary: "Accepted owner relations or backlinks connect this item to the graph.",
                owner: bundle.owner,
                evidenceRef: bundle.owner.canonicalRef
            ))
        }
        return reasons
    }

    func contentReasons(owner: SecondBrainOwnerRef, kind: String, id: String?, source: String) -> [CiderRecallScoreReason] {
        [CiderRecallScoreReason(
            kind: kind == "chunk" ? "source_chunk" : "source_section",
            weight: kind == "chunk" ? 0.7 : 0.55,
            summary: kind == "chunk" ? "Surfaced from an indexed content chunk." : "Surfaced from a structured item section.",
            owner: owner,
            evidenceRef: id.map { "\(kind):\($0)" } ?? owner.canonicalRef,
            metadata: ["source": source]
        )]
    }

    func relatedItemReasons(sourceOwner: SecondBrainOwnerRef, relatedID: String?) -> [CiderRecallScoreReason] {
        [CiderRecallScoreReason(
            kind: "related_item_link",
            weight: 0.6,
            summary: "Surfaced because it is linked or related to the recall anchor.",
            owner: sourceOwner,
            evidenceRef: sourceOwner.canonicalRef,
            metadata: relatedID.map { ["related_item_id": $0] } ?? [:]
        )]
    }

    func acceptedFactReasons(relation: SecondBrainRelation, evidenceRecord: SecondBrainSourceEvidenceRecord?, lifecycleHistory: [SecondBrainReviewLifecycleEvent]) -> [CiderRecallScoreReason] {
        var reasons: [CiderRecallScoreReason] = [
            CiderRecallScoreReason(
                kind: "accepted_graph_fact",
                weight: 1.0,
                summary: "Accepted graph relation recorded through an explicit review/link action.",
                owner: relation.sourceOwner,
                evidenceRef: "owner_relation:\(relation.id)",
                candidateRef: relation.metadata["candidate_ref"] ?? relation.metadata["candidate_id"].map { "graph_candidate:\($0)" },
                relationID: relation.id,
                reviewState: "accepted",
                metadata: ["relation_type": relation.relationType, "source": relation.source]
            )
        ]
        if let evidenceRecord {
            reasons.append(CiderRecallScoreReason(
                kind: "source_evidence",
                weight: 0.8,
                summary: "Accepted fact cites a shared source evidence record.",
                owner: evidenceRecord.sourceOwner,
                evidenceRef: "source_evidence:\(evidenceRecord.id)",
                candidateRef: evidenceRecord.candidateRef,
                relationID: relation.id
            ))
        }
        if lifecycleHistory.contains(where: { $0.eventKind == "accepted_truth_recorded" }) {
            reasons.append(CiderRecallScoreReason(
                kind: "lifecycle_state",
                weight: 0.45,
                summary: "Lifecycle history records explicit accepted truth.",
                owner: SecondBrainOwnerRef(ownerType: "owner_relation", ownerID: relation.id),
                evidenceRef: "owner_relation:\(relation.id)",
                candidateRef: relation.metadata["candidate_ref"],
                relationID: relation.id,
                reviewState: "accepted"
            ))
        }
        return reasons
    }

    func candidateReasons(output: SecondBrainEnrichmentOutput, evidenceRecord: SecondBrainSourceEvidenceRecord?, lifecycleHistory: [SecondBrainReviewLifecycleEvent]) -> [CiderRecallScoreReason] {
        let candidateRef = output.kind == SecondBrainGraphCandidateContract.outputKind ? "graph_candidate:\(output.id)" : "memory_candidate:\(output.id)"
        var reasons: [CiderRecallScoreReason] = [
            CiderRecallScoreReason(
                kind: "reviewable_candidate",
                weight: 0.7,
                summary: "Surfaced as a reviewable candidate, not accepted truth.",
                owner: output.owner,
                evidenceRef: "enrichment_output:\(output.id)",
                candidateRef: candidateRef,
                reviewState: output.reviewState,
                metadata: ["output_kind": output.kind, "source": output.source]
            )
        ]
        if let evidenceRecord {
            reasons.append(CiderRecallScoreReason(
                kind: "source_evidence",
                weight: 0.65,
                summary: "Candidate cites a shared source evidence record.",
                owner: evidenceRecord.sourceOwner,
                evidenceRef: "source_evidence:\(evidenceRecord.id)",
                candidateRef: evidenceRecord.candidateRef ?? candidateRef,
                reviewState: output.reviewState
            ))
        }
        if let latest = lifecycleHistory.last {
            reasons.append(CiderRecallScoreReason(
                kind: "lifecycle_state",
                weight: 0.35,
                summary: "Candidate lifecycle explains current review state.",
                owner: latest.owner,
                evidenceRef: latest.sourceEvidenceRef,
                candidateRef: latest.candidateRef ?? candidateRef,
                reviewState: latest.lifecycleState,
                metadata: ["event_kind": latest.eventKind]
            ))
        }
        return reasons
    }

    func score(_ reasons: [CiderRecallScoreReason]) -> Double {
        min(1.0, reasons.reduce(0.0) { $0 + max(0, $1.weight) } / 2.0)
    }

    func recordAccess(
        surface: String = "item.recall-context",
        selectorKind: String,
        query: String?,
        anchorRefs: [String],
        surfacedRefs: [String],
        reasonKinds: [String],
        metadata: [String: String] = [:]
    ) throws -> CiderRecallAccessEvent {
        let normalizedQuery = nonEmpty(query?.trimmingCharacters(in: .whitespacesAndNewlines))
        let event = CiderRecallAccessEvent(
            surface: surface,
            selectorKind: selectorKind,
            queryHash: normalizedQuery.map(Self.queryHash),
            queryLength: normalizedQuery?.count,
            queryTokenCount: normalizedQuery.map(Self.queryTokenCount),
            anchorRefs: anchorRefs,
            surfacedRefs: Array(orderedUnique(surfacedRefs).prefix(100)),
            reasonKinds: Array(orderedUnique(reasonKinds).prefix(100)),
            metadata: metadata
        )
        try insert(event)
        return event
    }

    func recentAccessEvents(limit: Int = 20) throws -> [CiderRecallAccessEvent] {
        let stmt = try database.prepare("""
            SELECT id, surface, selector_kind, query_hash, query_length, query_token_count,
                   anchor_refs, surfaced_refs, reason_kinds, metadata, created_at
            FROM recall_access_events
            ORDER BY created_at DESC
            LIMIT ?;
            """)
        stmt.bind(Int64(max(1, limit)), at: 1)
        var events: [CiderRecallAccessEvent] = []
        while try stmt.step() {
            events.append(CiderRecallAccessEvent(
                id: stmt.string(at: 0),
                surface: stmt.string(at: 1),
                selectorKind: stmt.string(at: 2),
                queryHash: stmt.optionalString(at: 3),
                queryLength: stmt.optionalInt(at: 4),
                queryTokenCount: stmt.optionalInt(at: 5),
                anchorRefs: DatabaseHelpers.decodeJSON([String].self, from: stmt.optionalString(at: 6)) ?? [],
                surfacedRefs: DatabaseHelpers.decodeJSON([String].self, from: stmt.optionalString(at: 7)) ?? [],
                reasonKinds: DatabaseHelpers.decodeJSON([String].self, from: stmt.optionalString(at: 8)) ?? [],
                metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 9)) ?? [:],
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 10))
            ))
        }
        return events
    }

    static func queryHash(_ query: String) -> String {
        let digest = SHA256.hash(data: Data(query.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func queryTokenCount(_ query: String) -> Int {
        query.split { $0.isWhitespace || $0.isPunctuation }.count
    }

    private func insert(_ event: CiderRecallAccessEvent) throws {
        let stmt = try database.prepare("""
            INSERT INTO recall_access_events (
                id, surface, selector_kind, query_hash, query_length, query_token_count,
                anchor_refs, surfaced_refs, reason_kinds, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(event.id, at: 1)
            .bind(event.surface, at: 2)
            .bind(event.selectorKind, at: 3)
            .bind(event.queryHash, at: 4)
            .bind(event.queryLength.map(Int64.init), at: 5)
            .bind(event.queryTokenCount.map(Int64.init), at: 6)
            .bind(DatabaseHelpers.encodeJSON(event.anchorRefs) ?? "[]", at: 7)
            .bind(DatabaseHelpers.encodeJSON(event.surfacedRefs) ?? "[]", at: 8)
            .bind(DatabaseHelpers.encodeJSON(event.reasonKinds) ?? "[]", at: 9)
            .bind(DatabaseHelpers.encodeJSON(event.metadata) ?? "{}", at: 10)
            .bind(DatabaseHelpers.encode(event.createdAt), at: 11)
        try stmt.step()
    }

    private func queryMatches(_ query: String?, bundle: CiderItemContextBundle) -> Bool {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty else { return false }
        let haystacks = [bundle.item.title]
            + bundle.sections.flatMap { [$0.title, $0.body] }
            + bundle.chunks.flatMap { [$0.title, $0.body] }
        return haystacks.contains { $0.lowercased().contains(query) }
    }

    private func sanitizedQueryMetadata(_ query: String?) -> [String: String] {
        guard let query = nonEmpty(query?.trimmingCharacters(in: .whitespacesAndNewlines)) else { return [:] }
        return [
            "query_hash": Self.queryHash(query),
            "query_length": String(query.count),
            "query_token_count": String(Self.queryTokenCount(query)),
            "query_text_stored": "false",
        ]
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
