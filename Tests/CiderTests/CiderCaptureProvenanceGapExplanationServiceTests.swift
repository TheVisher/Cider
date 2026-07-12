import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Gap Explanation Service Tests")
@MainActor
struct CiderCaptureProvenanceGapExplanationServiceTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-explanation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return (database, vault)
    }

    @discardableResult
    private func insertEvent(
        id: UUID = UUID(),
        sourceKind: String,
        sourceURL: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, 'cli', 'local', NULL, NULL, NULL, NULL, NULL, ?, NULL, 'fixture', 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(sourceKind, at: 2)
            .bind(sourceURL, at: 3)
            .bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 4)
            .bind(DatabaseHelpers.encode(createdAt), at: 5)
        try statement.step()
        return id
    }

    @discardableResult
    private func insertItem(
        id: UUID = UUID(),
        type: String,
        title: String,
        into database: CiderDatabase
    ) throws -> UUID {
        let timestamp = DatabaseHelpers.encode(Date(timeIntervalSince1970: 1_780_000_000))
        let statement = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(timestamp, at: 4)
            .bind(timestamp, at: 5)
            .bind("Inbox/\(title)", at: 6)
        try statement.step()
        return id
    }

    private func insertBookmark(id: UUID, url: String, into database: CiderDatabase) throws {
        let statement = try database.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        statement.bind(id.uuidString, at: 1).bind(url, at: 2)
        try statement.step()
    }

    private func insertAudit(
        itemID: UUID,
        occurredAt: Date,
        canonicalURL: String,
        into database: CiderDatabase
    ) throws {
        let statement = try database.prepare("""
            INSERT INTO mutation_audit (
                id, occurred_at, item_type, item_id, action, source,
                before_state, after_state, metadata
            ) VALUES (?, ?, 'bookmark', ?, 'deduplicate_url_capture', 'cli', '{}', '{}', ?);
            """)
        statement.bind(UUID().uuidString, at: 1)
            .bind(DatabaseHelpers.encode(occurredAt), at: 2)
            .bind(itemID.uuidString, at: 3)
            .bind(DatabaseHelpers.encodeJSON(["canonicalURL": canonicalURL]) ?? "{}", at: 4)
        try statement.step()
    }

    private func rowCounts(_ database: CiderDatabase) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try database.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            counts[table] = statement.int(at: 0)
        }
        return counts
    }

    @Test("unresolved explanation is content-free, bounded, replayable, and non-mutating")
    func unresolvedExplanationIsBoundedAndNonMutating() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventID = try insertEvent(sourceKind: "text", into: database)
        let before = try rowCounts(database)

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .explain(captureEventRef: "capture_event:\(eventID.uuidString)")

        #expect(try rowCounts(database) == before)
        #expect(report.command == "capture.provenance-gap")
        #expect(report.readOnly && !report.changed)
        #expect(report.classification == .unresolvedProvenanceGap)
        #expect(report.reasonCode == "no_conclusive_persisted_evidence")
        #expect(report.checkedEvidence.count == 5)
        #expect(report.checkedEvidence.first { $0.category == .captureEvent }?.status == .found)
        #expect(report.checkedEvidence.first { $0.category == .producedItemRelation }?.status == .missing)
        #expect(report.checkedEvidence.first { $0.category == .captureMetadata }?.status == .missing)
        #expect(report.checkedEvidence.allSatisfy { $0.evidenceRefs.count <= 10 })
        #expect(report.missingEvidenceReasons.contains("no_exact_persisted_item_reference"))
        #expect(report.truthBoundary == "read_only_explanation_no_inference_candidate_selection_or_provenance_repair")
        #expect(report.safeVerificationCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json"))
        #expect(!report.toDictionary().description.contains("fixture"))
        #expect(!report.safeNextCommands.contains {
            $0.contains(" repair") || $0.contains(" backfill") || $0.contains(" apply") || $0.contains(" item link ")
        })
    }

    @Test("resolved metadata evidence reports exact canonical readback refs")
    func resolvedMetadataEvidenceReportsCanonicalRefs() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let itemID = try insertItem(type: "note", title: "Canonical note", into: database)
        let eventID = try insertEvent(
            sourceKind: "text",
            metadata: ["produced_item_type": "note", "produced_item_id": itemID.uuidString],
            into: database
        )

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .explain(captureEventRef: "capture_event:\(eventID.uuidString)")

        #expect(report.classification == .survivingCanonicalItemWithRecoverableProvenance)
        #expect(report.itemRef == "note:\(itemID.uuidString)")
        #expect(report.checkedEvidence.first { $0.category == .captureMetadata }?.status == .found)
        #expect(report.checkedEvidence.first { $0.category == .canonicalItemReadback }?.status == .found)
        #expect(report.evidenceRefs.contains("capture_metadata:produced_item_ref"))
        #expect(report.safeNextCommands.contains("cider-cli item get note \(itemID.uuidString) --json"))
        #expect(report.safeNextCommands.contains("cider-cli item context note \(itemID.uuidString) --json"))
    }

    @Test("malformed, missing, unsupported, and no-longer-gap refs fail closed")
    func invalidRefsFailClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let unsupportedID = try insertEvent(sourceKind: "mystery_kind", into: database)
        let relatedID = try insertEvent(sourceKind: "text", into: database)
        let itemID = try insertItem(type: "note", title: "Related", into: database)
        try SecondBrainStore(database: database).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: relatedID.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: itemID.uuidString),
            relationType: "produced_item", evidence: "fixture", source: "test", actor: "test"
        ))
        let service = CiderCaptureProvenanceDiagnosticService(database: database)

        #expect(throws: CiderCaptureProvenanceExplanationError.malformedCaptureEventRef) {
            try service.explain(captureEventRef: "capture_event:not-a-uuid")
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.captureEventNotFound) {
            try service.explain(captureEventRef: "capture_event:\(UUID().uuidString)")
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.unsupportedSourceKind) {
            try service.explain(captureEventRef: "capture_event:\(unsupportedID.uuidString)")
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.captureEventNoLongerHasGap) {
            try service.explain(captureEventRef: "capture_event:\(relatedID.uuidString)")
        }
    }

    @Test("ambiguous canonical URL candidates are reported without selection")
    func ambiguousCandidatesFailClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        for suffix in ["a", "b"] {
            let itemID = try insertItem(type: "bookmark", title: "Bookmark \(suffix)", into: database)
            try insertBookmark(id: itemID, url: "https://example.com/story", into: database)
        }
        let eventID = try insertEvent(sourceKind: "url", sourceURL: "https://example.com/story", into: database)

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .explain(captureEventRef: "capture_event:\(eventID.uuidString)")

        #expect(report.classification == .unresolvedProvenanceGap)
        #expect(report.checkedEvidence.first { $0.category == .canonicalItemReadback }?.status == .ambiguous)
        #expect(report.missingEvidenceReasons.contains("ambiguous_canonical_url_candidates"))
        #expect(report.itemRef == nil)
        #expect(!report.safeNextCommands.contains { $0.contains("item get bookmark") })
    }

    @Test("stale audit evidence remains unresolved")
    func staleAuditEvidenceFailsClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventDate = Date(timeIntervalSince1970: 1_780_000_000)
        let itemID = try insertItem(type: "bookmark", title: "Bookmark", into: database)
        try insertBookmark(id: itemID, url: "https://example.com/stale", into: database)
        try insertAudit(
            itemID: itemID,
            occurredAt: eventDate.addingTimeInterval(-600),
            canonicalURL: "https://example.com/stale",
            into: database
        )
        let eventID = try insertEvent(
            sourceKind: "url", sourceURL: "https://example.com/stale", createdAt: eventDate, into: database
        )

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .explain(captureEventRef: "capture_event:\(eventID.uuidString)")

        #expect(report.classification == .unresolvedProvenanceGap)
        #expect(report.checkedEvidence.first { $0.category == .duplicateAudit }?.status == .stale)
        #expect(report.missingEvidenceReasons.contains("matching_duplicate_audit_outside_time_window"))
        #expect(!report.evidenceRefs.contains { $0.hasPrefix("mutation_audit:") })
    }

    @Test("audit scan cap is explicit and fails closed")
    func auditCapFailsClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let itemID = try insertItem(type: "bookmark", title: "Bookmark", into: database)
        try insertBookmark(id: itemID, url: "https://example.com/capped", into: database)
        for index in 0...500 {
            try insertAudit(
                itemID: UUID(),
                occurredAt: Date(timeIntervalSince1970: 1_780_001_000 + Double(index)),
                canonicalURL: "https://example.com/unrelated/\(index)",
                into: database
            )
        }
        let eventID = try insertEvent(sourceKind: "url", sourceURL: "https://example.com/capped", into: database)

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .explain(captureEventRef: "capture_event:\(eventID.uuidString)")

        #expect(report.classification == .unresolvedProvenanceGap)
        #expect(report.checkedEvidence.first { $0.category == .duplicateAudit }?.status == .capped)
        #expect(report.missingEvidenceReasons.contains("duplicate_audit_scan_cap_reached"))
        #expect(report.caps["duplicateAuditEntries"] == 500)
    }
}
