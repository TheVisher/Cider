import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Candidate Outcome Aggregate Tests")
@MainActor
struct CiderCaptureProvenanceCandidateOutcomeAggregateTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-candidate-outcome-aggregate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return (database, vault)
    }

    @discardableResult
    private func insertEvent(
        id: UUID = UUID(),
        sourceKind: String = "url",
        sourceURL: String? = nil,
        metadataJSON: String = "{}",
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
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
    private func insertBookmark(url: String, into database: CiderDatabase) throws -> UUID {
        let id = UUID()
        let timestamp = DatabaseHelpers.encode(Date(timeIntervalSince1970: 1_780_000_000))
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', 'PRIVATE_ITEM_SENTINEL', ?, ?, NULL, ?);
            """)
        item.bind(id.uuidString, at: 1)
            .bind(timestamp, at: 2)
            .bind(timestamp, at: 3)
            .bind("Inbox/PRIVATE_PATH_SENTINEL_\(id.uuidString)", at: 4)
        try item.step()
        let bookmark = try database.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        bookmark.bind(id.uuidString, at: 1).bind(url, at: 2)
        try bookmark.step()
        return id
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
            .bind(DatabaseHelpers.encodeJSON([
                "canonicalURL": canonicalURL,
                "private": "PRIVATE_AUDIT_SENTINEL",
            ]) ?? "{}", at: 4)
        try statement.step()
    }

    private func rowCounts(_ database: CiderDatabase) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "bookmarks", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try database.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            result[table] = statement.int(at: 0)
        }
        return result
    }

    @Test("mixed candidate outcomes aggregate deterministically without mutation")
    func mixedOutcomesAreDeterministicAndNonMutating() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let urls = ["zero", "one", "multiple", "capped"].map { "https://example.com/\($0)" }
        _ = try insertEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, sourceURL: urls[0], into: database)
        _ = try insertBookmark(url: urls[1], into: database)
        _ = try insertEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, sourceURL: urls[1], into: database)
        for _ in 0..<2 { _ = try insertBookmark(url: urls[2], into: database) }
        _ = try insertEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, sourceURL: urls[2], into: database)
        for _ in 0..<11 { _ = try insertBookmark(url: urls[3], into: database) }
        _ = try insertEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, sourceURL: urls[3], into: database)
        let before = try rowCounts(database)
        let service = CiderCaptureProvenanceDiagnosticService(database: database)

        let first = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 3)
        let second = try service.aggregateUnresolvedGaps(limit: 20, sampleLimit: 3)
        let projection = first.candidateDiscovery

        #expect(try rowCounts(database) == before)
        #expect(first == second)
        #expect(projection.readOnly && !projection.changed)
        #expect(projection.eligibleCount == 4)
        #expect(projection.excludedCount == 0)
        #expect(projection.countsByOutcome.map(\.outcome) == [
            .zeroCandidates, .oneCandidateInsufficient, .multipleCandidatesAmbiguous, .cappedCandidateEvidence,
        ])
        #expect(projection.countsByOutcome.map(\.count) == [1, 1, 1, 1])
        #expect(projection.countsByOutcome.flatMap(\.sampleCaptureEventRefs).count == 3)
        #expect(projection.sampledCount == 3)
        #expect(projection.sampleRefsTruncated)
        #expect(projection.countsByEvidenceCategory.map(\.category) == [
            .exactPersistedItemReference, .canonicalURLMatch, .nearbyDuplicateAuditMatch,
        ])
        let canonical = try #require(projection.countsByEvidenceCategory.first { $0.category == .canonicalURLMatch })
        #expect(canonical.eventCount == 4)
        #expect(canonical.candidateCount == 14)
        #expect(canonical.candidateCountIsLowerBound)
        #expect(projection.saturated)
        #expect(projection.caps["sampleCaptureEventRefs"] == 3)
        #expect(projection.safeVerificationCommands.first == "cider-cli capture provenance-gap-patterns --limit 20 --sample-limit 3 --json")
        #expect(projection.safeVerificationCommands.dropFirst().allSatisfy {
            $0.hasPrefix("cider-cli capture provenance-gap capture_event:") && $0.hasSuffix(" --json")
        })
        #expect(projection.truthBoundary.contains("no_candidate_selection"))
    }

    @Test("malformed and unsupported rows fail closed while stale evidence remains explicit")
    func unsafeRowsFailClosedAndStaleRemainsExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventDate = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try insertEvent(sourceKind: "note", metadataJSON: "{bad-json", createdAt: eventDate, into: database)
        _ = try insertEvent(sourceKind: "unsupported", createdAt: eventDate, into: database)
        let staleURL = "https://example.com/private-stale"
        let staleItem = try insertBookmark(url: staleURL, into: database)
        try insertAudit(itemID: staleItem, occurredAt: eventDate.addingTimeInterval(-600), canonicalURL: staleURL, into: database)
        _ = try insertEvent(sourceURL: staleURL, createdAt: eventDate, into: database)

        let report = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 20, sampleLimit: 10)
        let projection = report.candidateDiscovery

        #expect(report.excludedCount == 1)
        #expect(report.failClosedCounts["unsupported_capture_source_kind"] == 1)
        #expect(report.failClosedCounts["malformed_candidate_discovery_input"] == 1)
        #expect(projection.eligibleCount == 1)
        #expect(projection.excludedCount == 2)
        #expect(projection.countsByOutcome.first { $0.outcome == .oneCandidateInsufficient }?.count == 1)
        let audit = try #require(projection.countsByEvidenceCategory.first { $0.category == .nearbyDuplicateAuditMatch })
        #expect(audit.statusCounts["stale"] == 1)
    }

    @Test("candidate aggregate remains content free and explicitly bounded")
    func aggregateIsContentFreeAndBounded() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let privateURL = "https://example.com/PRIVATE_URL_SENTINEL"
        _ = try insertBookmark(url: privateURL, into: database)
        _ = try insertEvent(
            sourceURL: privateURL,
            metadataJSON: DatabaseHelpers.encodeJSON(["private": "PRIVATE_METADATA_SENTINEL"])!,
            into: database
        )

        let projection = try CiderCaptureProvenanceDiagnosticService(database: database)
            .aggregateUnresolvedGaps(limit: 500, sampleLimit: 500).candidateDiscovery
        let serialized = projection.toDictionary().description

        #expect(projection.caps["scanEvents"] == 100)
        #expect(projection.caps["sampleCaptureEventRefs"] == 10)
        #expect(projection.caps["candidateRefsPerEvent"] == 10)
        #expect(projection.caps["duplicateAuditEntriesPerEvent"] == 500)
        for sentinel in ["PRIVATE_CAPTURE_SENTINEL", "PRIVATE_ITEM_SENTINEL", "PRIVATE_PATH_SENTINEL", "PRIVATE_URL_SENTINEL", "PRIVATE_METADATA_SENTINEL", "PRIVATE_AUDIT_SENTINEL"] {
            #expect(!serialized.contains(sentinel))
        }
    }
}
