import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Diagnostic Service Tests")
@MainActor
struct CiderCaptureProvenanceDiagnosticServiceTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-diagnostic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".cider", isDirectory: true),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return (db, vault)
    }

    private func insertItem(
        id: UUID = UUID(),
        type: String,
        title: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        into db: CiderDatabase
    ) throws -> UUID {
        let statement = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(createdAt), at: 4)
            .bind(DatabaseHelpers.encode(createdAt), at: 5)
            .bind("Inbox/\(title)", at: 6)
        try statement.step()
        return id
    }

    @discardableResult
    private func insertEvent(
        id: UUID = UUID(),
        sourceKind: String,
        sourceURL: String? = nil,
        metadata: String = "{}",
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_010),
        into db: CiderDatabase
    ) throws -> UUID {
        let statement = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, 'cli', 'local', NULL, NULL, NULL, NULL, NULL, ?, NULL, 'fixture', 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(sourceKind, at: 2)
            .bind(sourceURL, at: 3)
            .bind(metadata, at: 4)
            .bind(DatabaseHelpers.encode(createdAt), at: 5)
        try statement.step()
        return id
    }

    private func metadata(_ values: [String: String]) -> String {
        DatabaseHelpers.encodeJSON(values) ?? "{}"
    }

    private func rowCounts(_ db: CiderDatabase) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try db.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            result[table] = statement.int(at: 0)
        }
        return result
    }

    @Test("mixed batch classifies every evidence-backed outcome and representative supported kinds")
    func mixedBatchClassifiesEveryOutcomeAndSupportedKinds() throws {
        let (db, vault) = try makeDatabase()
        defer { db.close(); try? FileManager.default.removeItem(at: vault) }

        let bookmarkID = try insertItem(type: "bookmark", title: "Canonical bookmark", into: db)
        let bookmark = try db.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        bookmark.bind(bookmarkID.uuidString, at: 1).bind("https://example.com/story", at: 2)
        try bookmark.step()
        _ = MutationAuditService(database: db).record(
            action: "deduplicate_url_capture",
            itemType: "bookmark",
            itemID: bookmarkID,
            metadata: ["incomingURL": "https://example.com/story", "canonicalURL": "https://example.com/story"]
        )
        let duplicateEvent = try insertEvent(sourceKind: "url", sourceURL: "https://example.com/story", createdAt: Date(), into: db)

        let failureEvent = try insertEvent(
            sourceKind: "file",
            metadata: metadata(["capture_outcome": "failed", "failure_reason": "source file disappeared"]),
            into: db
        )
        let abandonedEvent = try insertEvent(
            sourceKind: "chat_unsupported_attachment",
            metadata: metadata(["review_reason": "unsupported_attachment", "review_state": "needs_review"]),
            into: db
        )

        var recoverableEvents: [UUID: String] = [:]
        for (sourceKind, databaseType, cliType) in [
            ("text", "note", "note"),
            ("todo", "todo", "todo"),
            ("file", "vaultFile", "vaultFile"),
            ("event", "event", "dateCard"),
            ("contact", "contact", "contact"),
        ] {
            let itemID = try insertItem(type: databaseType, title: "\(cliType) fixture", into: db)
            let eventID = try insertEvent(
                sourceKind: sourceKind,
                metadata: metadata(["produced_item_id": itemID.uuidString, "produced_item_type": cliType]),
                into: db
            )
            recoverableEvents[eventID] = "\(cliType):\(itemID.uuidString)"
        }
        let unresolvedEvent = try insertEvent(sourceKind: "text", into: db)

        let report = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 50)

        #expect(report.totalMissingCount == 9)
        #expect(report.scannedCount == 9)
        #expect(report.hasMore == false)
        #expect(report.counts.evidenceBackedDuplicate == 1)
        #expect(report.counts.explicitFailureOrAbandonment == 2)
        #expect(report.counts.survivingCanonicalItemWithRecoverableProvenance == 5)
        #expect(report.counts.unresolvedProvenanceGap == 1)
        #expect(report.findings.first { $0.captureEventID == duplicateEvent.uuidString }?.classification == .evidenceBackedDuplicate)
        #expect(report.findings.first { $0.captureEventID == failureEvent.uuidString }?.reasonCode == "explicit_capture_failure")
        #expect(report.findings.first { $0.captureEventID == abandonedEvent.uuidString }?.reasonCode == "explicit_nonproducing_capture_event")
        #expect(report.findings.first { $0.captureEventID == unresolvedEvent.uuidString }?.classification == .unresolvedProvenanceGap)
        for (eventID, itemRef) in recoverableEvents {
            let finding = report.findings.first { $0.captureEventID == eventID.uuidString }
            #expect(finding?.classification == .survivingCanonicalItemWithRecoverableProvenance)
            #expect(finding?.itemRef == itemRef)
        }
        #expect(report.truthBoundary == "read_only_diagnostic_evidence_not_repaired_provenance_or_accepted_truth")
        #expect(report.safeVerificationCommands.contains("cider-cli capture provenance-gaps --limit 50 --json"))
    }

    @Test("cap is enforced and reports remaining missing events")
    func capIsEnforced() throws {
        let (db, vault) = try makeDatabase()
        defer { db.close(); try? FileManager.default.removeItem(at: vault) }
        for index in 0..<5 {
            _ = try insertEvent(
                sourceKind: "text",
                createdAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(index)),
                into: db
            )
        }

        let report = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 2)

        #expect(report.totalMissingCount == 5)
        #expect(report.scannedCount == 2)
        #expect(report.omittedCount == 3)
        #expect(report.hasMore)
        #expect(report.findings.count == 2)

        let maximumReport = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 500)
        #expect(maximumReport.requestedLimit == 500)
        #expect(maximumReport.appliedLimit == 100)
        #expect(maximumReport.maximumLimit == 100)
    }

    @Test("malformed history fails closed as an unresolved gap")
    func malformedHistoryFailsClosed() throws {
        let (db, vault) = try makeDatabase()
        defer { db.close(); try? FileManager.default.removeItem(at: vault) }
        let eventID = try insertEvent(sourceKind: "note", metadata: "{not-json", into: db)

        let report = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 10)
        let finding = try #require(report.findings.first { $0.captureEventID == eventID.uuidString })

        #expect(finding.classification == .unresolvedProvenanceGap)
        #expect(finding.reasonCode == "malformed_capture_metadata")
        #expect(finding.truthBoundary == "insufficient_evidence_no_inference_or_mutation")
    }

    @Test("missing or mismatched canonical refs fail closed")
    func missingOrMismatchedCanonicalRefsFailClosed() throws {
        let (db, vault) = try makeDatabase()
        defer { db.close(); try? FileManager.default.removeItem(at: vault) }
        let noteID = try insertItem(type: "note", title: "Existing note", into: db)
        _ = try insertEvent(
            sourceKind: "todo",
            metadata: metadata(["produced_item_id": noteID.uuidString, "produced_item_type": "todo"]),
            into: db
        )
        _ = try insertEvent(
            sourceKind: "note",
            metadata: metadata(["produced_item_id": UUID().uuidString, "produced_item_type": "note"]),
            into: db
        )

        let report = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 10)

        #expect(report.counts.unresolvedProvenanceGap == 2)
        #expect(report.findings.allSatisfy { $0.reasonCode == "referenced_canonical_item_not_found" })
    }

    @Test("diagnostic performs no database mutation and excludes already-related events")
    func diagnosticPerformsNoMutation() throws {
        let (db, vault) = try makeDatabase()
        defer { db.close(); try? FileManager.default.removeItem(at: vault) }
        let missingEvent = try insertEvent(sourceKind: "text", into: db)
        let relatedEvent = try insertEvent(sourceKind: "text", into: db)
        let itemID = try insertItem(type: "note", title: "Related note", into: db)
        try SecondBrainStore(database: db).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: relatedEvent.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: itemID.uuidString),
            relationType: "produced_item",
            evidence: "fixture",
            source: "test",
            actor: "test",
            confidence: 1
        ))
        let before = try rowCounts(db)

        let report = try CiderCaptureProvenanceDiagnosticService(database: db).diagnose(limit: 10)
        let after = try rowCounts(db)

        #expect(before == after)
        #expect(report.totalMissingCount == 1)
        #expect(report.findings.map(\.captureEventID) == [missingEvent.uuidString])
        #expect(!report.safeNextCommands.contains { $0.contains("repair") || $0.contains("backfill") || $0.contains("apply") })
    }
}
