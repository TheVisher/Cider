import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Gap Aggregate Service Tests")
@MainActor
struct CiderCaptureProvenanceGapAggregateServiceTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-provenance-aggregate-\(UUID().uuidString)", isDirectory: true)
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
        metadataJSON: String = "{}",
        createdAt: Date,
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, 'cli', 'local', NULL, NULL, NULL, NULL, NULL, ?, NULL, 'PRIVATE_CAPTURE_SENTINEL', 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(sourceKind, at: 2)
            .bind(sourceURL, at: 3)
            .bind(metadataJSON, at: 4)
            .bind(DatabaseHelpers.encode(createdAt), at: 5)
        try statement.step()
        return id
    }

    @discardableResult
    private func insertItem(type: String, title: String, into database: CiderDatabase) throws -> UUID {
        let id = UUID()
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
            .bind("Inbox/PRIVATE_ITEM_PATH_\(id.uuidString)", at: 6)
        try statement.step()
        return id
    }

    private func insertBookmark(id: UUID, url: String, into database: CiderDatabase) throws {
        let statement = try database.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        statement.bind(id.uuidString, at: 1).bind(url, at: 2)
        try statement.step()
    }

    private func insertAudit(itemID: UUID, occurredAt: Date, canonicalURL: String, into database: CiderDatabase) throws {
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
        var result: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try database.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            result[table] = statement.int(at: 0)
        }
        return result
    }

    @Test("mixed unresolved patterns are deterministic, private, replayable, and non-mutating")
    func mixedPatternsAreDeterministicAndPrivate() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let january = Date(timeIntervalSince1970: 1_767_225_600)
        let february = Date(timeIntervalSince1970: 1_769_904_000)
        _ = try insertEvent(
            sourceKind: "text",
            metadataJSON: DatabaseHelpers.encodeJSON(["app_version": "1.2.3", "private": "PRIVATE_METADATA_SENTINEL"])!,
            createdAt: january,
            into: database
        )
        _ = try insertEvent(sourceKind: "note", metadataJSON: "{not-json", createdAt: february, into: database)
        _ = try insertEvent(
            sourceKind: "text",
            metadataJSON: DatabaseHelpers.encodeJSON(["app_version": "1.2.3"])!,
            createdAt: january,
            into: database
        )
        let before = try rowCounts(database)

        let service = CiderCaptureProvenanceDiagnosticService(database: database)
        let first = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 2)
        let second = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 2)

        #expect(try rowCounts(database) == before)
        #expect(first == second)
        #expect(first.command == "capture.provenance-gap-patterns")
        #expect(first.readOnly && !first.changed)
        #expect(first.scannedCount == 3)
        #expect(first.unresolvedCount == 3)
        #expect(first.groups.map(\.count).reduce(0, +) == 3)
        #expect(first.groups.first?.count == 2)
        #expect(first.groups.contains { $0.reasonCode == "malformed_capture_metadata" })
        #expect(first.groups.contains { $0.timeBucket == "2026-01" && $0.versionBucket == "1.2.3" })
        #expect(first.sampledCount == 2)
        #expect(first.groups.flatMap(\.sampleCaptureEventRefs).count == 2)
        #expect(first.safeVerificationCommands.contains { $0.hasPrefix("cider-cli capture provenance-gap capture_event:") })
        let serialized = first.toDictionary().description
        #expect(!serialized.contains("PRIVATE_CAPTURE_SENTINEL"))
        #expect(!serialized.contains("PRIVATE_METADATA_SENTINEL"))
        #expect(!serialized.contains("PRIVATE_ITEM_PATH"))
        #expect(!serialized.contains("sourceURL"))
        #expect(!serialized.contains("sourceText"))
    }

    @Test("scan and sample caps report saturation without leaking extra refs")
    func capsAndSaturationAreExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        for offset in 0..<5 {
            _ = try insertEvent(
                sourceKind: "text",
                createdAt: Date(timeIntervalSince1970: 1_767_225_600 + Double(offset)),
                into: database
            )
        }

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 2, sampleLimit: 1)

        #expect(report.totalMissingCount == 5)
        #expect(report.scannedCount == 2)
        #expect(report.omittedCount == 3)
        #expect(report.saturated)
        #expect(report.coverage == "partial_bounded_scan")
        #expect(report.sampledCount == 1)
        #expect(report.groups.flatMap(\.sampleCaptureEventRefs).count == 1)
        #expect(report.failClosedCounts["scan_cap_reached"] == 3)

        let clamped = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 500, sampleLimit: 500)
        #expect(clamped.appliedLimit == 100)
        #expect(clamped.maximumLimit == 100)
        #expect(clamped.appliedSampleLimit == 10)
        #expect(clamped.maximumSampleLimit == 10)
    }

    @Test("unsupported rows fail closed while malformed, ambiguous, and stale evidence remain explicit")
    func unsafeEvidenceFailsClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventDate = Date(timeIntervalSince1970: 1_767_225_600)
        _ = try insertEvent(sourceKind: "mystery_kind", createdAt: eventDate, into: database)
        _ = try insertEvent(sourceKind: "note", metadataJSON: "{bad-json", createdAt: eventDate, into: database)

        for _ in 0..<2 {
            let itemID = try insertItem(type: "bookmark", title: "PRIVATE TITLE", into: database)
            try insertBookmark(id: itemID, url: "https://example.com/ambiguous", into: database)
        }
        _ = try insertEvent(sourceKind: "url", sourceURL: "https://example.com/ambiguous", createdAt: eventDate, into: database)

        let staleID = try insertItem(type: "bookmark", title: "PRIVATE STALE", into: database)
        try insertBookmark(id: staleID, url: "https://example.com/stale", into: database)
        try insertAudit(itemID: staleID, occurredAt: eventDate.addingTimeInterval(-600), canonicalURL: "https://example.com/stale", into: database)
        _ = try insertEvent(sourceKind: "url", sourceURL: "https://example.com/stale", createdAt: eventDate, into: database)

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 20, sampleLimit: 10)

        #expect(report.scannedCount == 4)
        #expect(report.unresolvedCount == 3)
        #expect(report.excludedCount == 1)
        #expect(report.failClosedCounts["unsupported_capture_source_kind"] == 1)
        #expect(report.groups.contains { $0.reasonCode == "malformed_capture_metadata" })
        #expect(report.groups.contains { group in
            group.checkedEvidence.contains { $0.status == .ambiguous }
        })
        #expect(report.groups.contains { group in
            group.checkedEvidence.contains { $0.status == .stale }
        })
        #expect(!report.toDictionary().description.contains("PRIVATE TITLE"))
    }
}
