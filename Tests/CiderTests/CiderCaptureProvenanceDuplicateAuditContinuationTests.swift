import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Duplicate Audit Continuation Tests")
@MainActor
struct CiderCaptureProvenanceDuplicateAuditContinuationTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-duplicate-continuation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return (database, vault)
    }

    @discardableResult
    private func insertEvent(
        id: UUID = UUID(),
        url: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, 'url', 'cli', 'local', NULL, NULL, NULL, NULL, NULL, ?, NULL,
                      'PRIVATE_CAPTURE_SENTINEL', 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(url, at: 2)
            .bind(DatabaseHelpers.encodeJSON(["private": "PRIVATE_METADATA_SENTINEL"]) ?? "{}", at: 3)
            .bind(DatabaseHelpers.encode(createdAt), at: 4)
        try statement.step()
        return id
    }

    @discardableResult
    private func insertBookmark(id: UUID = UUID(), url: String, into database: CiderDatabase) throws -> UUID {
        let timestamp = DatabaseHelpers.encode(Date(timeIntervalSince1970: 1_780_000_000))
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', 'PRIVATE_TITLE_SENTINEL', ?, ?, NULL, 'Inbox/PRIVATE_PATH_SENTINEL');
            """)
        item.bind(id.uuidString, at: 1).bind(timestamp, at: 2).bind(timestamp, at: 3)
        try item.step()
        let bookmark = try database.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        bookmark.bind(id.uuidString, at: 1).bind(url, at: 2)
        try bookmark.step()
        return id
    }

    @discardableResult
    private func insertAudit(
        id: UUID,
        itemID: UUID,
        occurredAt: Date,
        canonicalURL: String,
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO mutation_audit (
                id, occurred_at, item_type, item_id, action, source,
                before_state, after_state, metadata
            ) VALUES (?, ?, 'bookmark', ?, 'deduplicate_url_capture', 'cli', '{}', '{}', ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(DatabaseHelpers.encode(occurredAt), at: 2)
            .bind(itemID.uuidString, at: 3)
            .bind(DatabaseHelpers.encodeJSON([
                "canonicalURL": canonicalURL,
                "private": "PRIVATE_AUDIT_SENTINEL",
            ]) ?? "{}", at: 4)
        try statement.step()
        return id
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

    @Test("first page is bounded, deterministic, private, replayable, and non-mutating")
    func firstPageContract() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let url = "https://example.com/PRIVATE_URL_SENTINEL"
        _ = try insertBookmark(url: url, into: database)
        let eventID = try insertEvent(url: url, into: database)
        let newer = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let older = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        _ = try insertAudit(id: older, itemID: UUID(), occurredAt: Date(timeIntervalSince1970: 1_780_000_100), canonicalURL: "https://unrelated.example/older", into: database)
        _ = try insertAudit(id: newer, itemID: UUID(), occurredAt: Date(timeIntervalSince1970: 1_780_000_200), canonicalURL: "https://unrelated.example/newer", into: database)
        _ = try insertAudit(id: UUID(), itemID: UUID(), occurredAt: Date(timeIntervalSince1970: 1_780_000_000), canonicalURL: "https://unrelated.example/last", into: database)
        let before = try rowCounts(database)
        let service = CiderCaptureProvenanceDiagnosticService(database: database)

        let first = try service.explain(captureEventRef: "capture_event:\(eventID.uuidString)", duplicateAuditLimit: 2)
        let replay = try service.explain(captureEventRef: "capture_event:\(eventID.uuidString)", duplicateAuditLimit: 2)

        #expect(try rowCounts(database) == before)
        #expect(first == replay)
        #expect(first.readOnly && !first.changed)
        #expect(first.duplicateAuditScan.appliedLimit == 2)
        #expect(first.duplicateAuditScan.maximumLimit == 500)
        #expect(first.duplicateAuditScan.scannedCount == 2)
        #expect(first.duplicateAuditScan.cumulativeScannedCount == 2)
        #expect(first.duplicateAuditScan.saturated && first.duplicateAuditScan.hasMore)
        #expect(!first.duplicateAuditScan.exhausted)
        #expect(first.duplicateAuditScan.continuationToken != nil)
        #expect(first.duplicateAuditScan.scannedAuditRefs == ["mutation_audit:\(newer.uuidString)", "mutation_audit:\(older.uuidString)"])
        #expect(first.checkedEvidence.first { $0.category == .duplicateAudit }?.status == .capped)
        #expect(first.safeNextCommands.contains { $0.contains("--duplicate-audit-cursor") && $0.contains("--duplicate-audit-limit 2") })
        let serialized = first.toDictionary().description
        for sentinel in ["PRIVATE_URL_SENTINEL", "PRIVATE_CAPTURE_SENTINEL", "PRIVATE_METADATA_SENTINEL", "PRIVATE_AUDIT_SENTINEL", "PRIVATE_TITLE_SENTINEL", "PRIVATE_PATH_SENTINEL"] {
            #expect(!serialized.contains(sentinel))
        }
    }

    @Test("continuation reaches later duplicate evidence and then exhausts")
    func continuationFindsLaterEvidence() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let url = "https://example.com/story"
        let itemID = try insertBookmark(url: url, into: database)
        let eventDate = Date(timeIntervalSince1970: 1_780_000_000)
        let eventID = try insertEvent(url: url, createdAt: eventDate, into: database)
        for offset in [400.0, 300.0] {
            _ = try insertAudit(id: UUID(), itemID: UUID(), occurredAt: eventDate.addingTimeInterval(offset), canonicalURL: "https://unrelated.example/\(offset)", into: database)
        }
        let matchingAuditID = try insertAudit(id: UUID(), itemID: itemID, occurredAt: eventDate.addingTimeInterval(30), canonicalURL: url, into: database)
        _ = try insertAudit(id: UUID(), itemID: UUID(), occurredAt: eventDate.addingTimeInterval(-300), canonicalURL: "https://unrelated.example/old", into: database)
        let before = try rowCounts(database)
        let service = CiderCaptureProvenanceDiagnosticService(database: database)
        let first = try service.explain(captureEventRef: "capture_event:\(eventID.uuidString)", duplicateAuditLimit: 2)
        let token = try #require(first.duplicateAuditScan.continuationToken)

        let second = try service.explain(
            captureEventRef: "capture_event:\(eventID.uuidString)",
            duplicateAuditContinuation: token,
            duplicateAuditLimit: 2
        )

        #expect(try rowCounts(database) == before)
        #expect(second.classification == .evidenceBackedDuplicate)
        #expect(second.reasonCode == "canonical_url_duplicate_audit")
        #expect(second.checkedEvidence.first { $0.category == .duplicateAudit }?.status == .found)
        #expect(second.checkedEvidence.first { $0.category == .duplicateAudit }?.evidenceRefs == ["mutation_audit:\(matchingAuditID.uuidString)"])
        #expect(second.duplicateAuditScan.scannedCount == 2)
        #expect(second.duplicateAuditScan.cumulativeScannedCount == 4)
        #expect(!second.duplicateAuditScan.hasMore && !second.duplicateAuditScan.saturated)
        #expect(second.duplicateAuditScan.exhausted)
        #expect(second.duplicateAuditScan.continuationToken == nil)
    }

    @Test("malformed, forged, mismatched, stale, and over-budget continuation state fails closed")
    func invalidContinuationFailsClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let url = "https://example.com/story"
        _ = try insertBookmark(url: url, into: database)
        let firstEventID = try insertEvent(url: url, into: database)
        let secondEventID = try insertEvent(url: url, into: database)
        for offset in 0..<3 {
            _ = try insertAudit(id: UUID(), itemID: UUID(), occurredAt: Date(timeIntervalSince1970: 1_780_001_000 + Double(offset)), canonicalURL: "https://unrelated.example/\(offset)", into: database)
        }
        let service = CiderCaptureProvenanceDiagnosticService(database: database)
        let first = try service.explain(captureEventRef: "capture_event:\(firstEventID.uuidString)", duplicateAuditLimit: 1)
        let token = try #require(first.duplicateAuditScan.continuationToken)
        let tampered = String(token.dropLast()) + (token.last == "A" ? "B" : "A")

        #expect(throws: CiderCaptureProvenanceExplanationError.malformedDuplicateAuditContinuation) {
            try service.explain(captureEventRef: "capture_event:\(firstEventID.uuidString)", duplicateAuditContinuation: "not-a-token", duplicateAuditLimit: 1)
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.forgedDuplicateAuditContinuation) {
            try service.explain(captureEventRef: "capture_event:\(firstEventID.uuidString)", duplicateAuditContinuation: tampered, duplicateAuditLimit: 1)
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.mismatchedDuplicateAuditContinuation) {
            try service.explain(captureEventRef: "capture_event:\(secondEventID.uuidString)", duplicateAuditContinuation: token, duplicateAuditLimit: 1)
        }
        #expect(throws: CiderCaptureProvenanceExplanationError.duplicateAuditLimitOutOfRange) {
            try service.explain(captureEventRef: "capture_event:\(firstEventID.uuidString)", duplicateAuditContinuation: token, duplicateAuditLimit: 501)
        }

        _ = try insertAudit(id: UUID(), itemID: UUID(), occurredAt: Date(timeIntervalSince1970: 1_780_002_000), canonicalURL: "https://unrelated.example/new", into: database)
        #expect(throws: CiderCaptureProvenanceExplanationError.staleDuplicateAuditContinuation) {
            try service.explain(captureEventRef: "capture_event:\(firstEventID.uuidString)", duplicateAuditContinuation: token, duplicateAuditLimit: 1)
        }
    }
}
