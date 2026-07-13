import Foundation
import Testing
@testable import Cider

@Suite("Capture Provenance Candidate Discovery Tests")
@MainActor
struct CiderCaptureProvenanceCandidateDiscoveryTests {
    private func makeDatabase() throws -> (CiderDatabase, URL) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-candidate-discovery-\(UUID().uuidString)", isDirectory: true)
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
        sourceURL: String? = "https://example.com/candidate",
        metadataJSON: String = "{}",
        sourceText: String = "PRIVATE_CAPTURE_SENTINEL",
        createdAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        into database: CiderDatabase
    ) throws -> UUID {
        let statement = try database.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, 'cli', 'local', NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 0, ?, ?);
            """)
        statement.bind(id.uuidString, at: 1)
            .bind(sourceKind, at: 2)
            .bind(sourceURL, at: 3)
            .bind(sourceText, at: 4)
            .bind(metadataJSON, at: 5)
            .bind(DatabaseHelpers.encode(createdAt), at: 6)
        try statement.step()
        return id
    }

    @discardableResult
    private func insertBookmark(
        id: UUID = UUID(),
        url: String = "https://example.com/candidate",
        title: String = "PRIVATE_ITEM_SENTINEL",
        into database: CiderDatabase
    ) throws -> UUID {
        let timestamp = DatabaseHelpers.encode(Date(timeIntervalSince1970: 1_780_000_000))
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', ?, ?, ?, NULL, ?);
            """)
        item.bind(id.uuidString, at: 1)
            .bind(title, at: 2)
            .bind(timestamp, at: 3)
            .bind(timestamp, at: 4)
            .bind("Inbox/PRIVATE_PATH_SENTINEL_\(id.uuidString)", at: 5)
        try item.step()
        let bookmark = try database.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, ?);")
        bookmark.bind(id.uuidString, at: 1).bind(url, at: 2)
        try bookmark.step()
        return id
    }

    private func insertAudit(
        itemID: UUID,
        occurredAt: Date,
        canonicalURL: String = "https://example.com/candidate",
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
            .bind(DatabaseHelpers.encodeJSON([
                "canonicalURL": canonicalURL,
                "private": "PRIVATE_AUDIT_SENTINEL",
            ]) ?? "{}", at: 4)
        try statement.step()
    }

    private func rowCounts(_ database: CiderDatabase) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["capture_events", "owner_relations", "items", "bookmarks", "mutation_audit", "agent_actions", "action_receipts"] {
            let statement = try database.prepare("SELECT count(*) FROM \(table);")
            _ = try statement.step()
            counts[table] = statement.int(at: 0)
        }
        return counts
    }

    private func explain(_ eventID: UUID, database: CiderDatabase, auditLimit: Int = 500) throws -> CiderCaptureProvenanceGapExplanation {
        try CiderCaptureProvenanceDiagnosticService(database: database).explain(
            captureEventRef: "capture_event:\(eventID.uuidString)",
            duplicateAuditLimit: auditLimit
        )
    }

    @Test("zero candidate evidence is explicit and content-free")
    func zeroCandidatesAreExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventID = try insertEvent(into: database)

        let discovery = try #require(try explain(eventID, database: database).candidateDiscovery)

        #expect(discovery.outcome == .zeroCandidates)
        #expect(discovery.reasonCode == "zero_surviving_canonical_candidates")
        #expect(discovery.discoveredCandidateCount == 0)
        #expect(discovery.countsByEvidenceCategory.first { $0.category == .canonicalURLMatch }?.candidateCount == 0)
        #expect(discovery.candidateRefs.isEmpty)
        #expect(!discovery.candidateSelected)
    }

    @Test("one canonical candidate remains insufficient without provenance evidence")
    func oneCandidateIsInsufficient() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let itemID = try insertBookmark(into: database)
        let eventID = try insertEvent(into: database)

        let discovery = try #require(try explain(eventID, database: database).candidateDiscovery)

        #expect(discovery.outcome == .oneCandidateInsufficient)
        #expect(discovery.reasonCode == "one_candidate_without_sufficient_provenance_evidence")
        #expect(discovery.discoveredCandidateCount == 1)
        #expect(discovery.candidateRefs == ["bookmark:\(itemID.uuidString)"])
        #expect(!discovery.candidateSelected)
        #expect(discovery.truthBoundary.contains("no_candidate_selection"))
    }

    @Test("multiple canonical candidates remain ambiguous without selection")
    func multipleCandidatesAreAmbiguous() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let ids = try [insertBookmark(into: database), insertBookmark(into: database)].sorted { $0.uuidString < $1.uuidString }
        let eventID = try insertEvent(into: database)

        let discovery = try #require(try explain(eventID, database: database).candidateDiscovery)

        #expect(discovery.outcome == .multipleCandidatesAmbiguous)
        #expect(discovery.reasonCode == "multiple_surviving_canonical_candidates")
        #expect(discovery.discoveredCandidateCount == 2)
        #expect(discovery.candidateRefs == ids.map { "bookmark:\($0.uuidString)" })
        #expect(!discovery.candidateSelected)
    }

    @Test("candidate cap reports a bounded lower count and saturation")
    func candidateCapIsExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        for _ in 0..<11 { _ = try insertBookmark(into: database) }
        let eventID = try insertEvent(into: database)

        let discovery = try #require(try explain(eventID, database: database).candidateDiscovery)
        let canonical = try #require(discovery.countsByEvidenceCategory.first { $0.category == .canonicalURLMatch })

        #expect(discovery.outcome == .cappedCandidateEvidence)
        #expect(discovery.saturated)
        #expect(discovery.discoveredCandidateCount == 11)
        #expect(discovery.discoveredCandidateCountIsLowerBound)
        #expect(discovery.candidateRefs.count == 10)
        #expect(discovery.candidateRefsTruncated)
        #expect(canonical.candidateCountIsLowerBound)
        #expect(discovery.caps["candidateRefs"] == 10)
    }

    @Test("supporting audit saturation does not hide a definitive zero candidate count")
    func auditSaturationPreservesZeroCandidateOutcome() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        for offset in 0..<2 {
            try insertAudit(
                itemID: UUID(),
                occurredAt: Date(timeIntervalSince1970: 1_780_001_000 + Double(offset)),
                canonicalURL: "https://unrelated.example/\(offset)",
                into: database
            )
        }
        let eventID = try insertEvent(into: database)

        let discovery = try #require(try explain(eventID, database: database, auditLimit: 1).candidateDiscovery)

        #expect(discovery.outcome == .zeroCandidates)
        #expect(discovery.reasonCode == "zero_surviving_canonical_candidates")
        #expect(discovery.discoveredCandidateCount == 0)
        #expect(!discovery.discoveredCandidateCountIsLowerBound)
        #expect(discovery.saturated)
        #expect(discovery.countsByEvidenceCategory.first { $0.category == .nearbyDuplicateAuditMatch }?.candidateCountIsLowerBound == true)
    }

    @Test("stale support leaves one candidate explicitly insufficient")
    func staleEvidenceIsExplicit() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        let eventDate = Date(timeIntervalSince1970: 1_780_000_000)
        let itemID = try insertBookmark(into: database)
        try insertAudit(itemID: itemID, occurredAt: eventDate.addingTimeInterval(-600), into: database)
        let eventID = try insertEvent(createdAt: eventDate, into: database)

        let discovery = try #require(try explain(eventID, database: database).candidateDiscovery)

        #expect(discovery.outcome == .oneCandidateInsufficient)
        #expect(discovery.reasonCode == "one_candidate_with_stale_supporting_evidence")
        #expect(discovery.countsByEvidenceCategory.first { $0.category == .nearbyDuplicateAuditMatch }?.status == .stale)
        #expect(!discovery.candidateSelected)
    }

    @Test("malformed refs still fail closed before discovery")
    func malformedRefFailsClosed() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }

        #expect(throws: CiderCaptureProvenanceExplanationError.malformedCaptureEventRef) {
            try CiderCaptureProvenanceDiagnosticService(database: database)
                .explain(captureEventRef: "capture_event:not-a-uuid")
        }
    }

    @Test("candidate explanation ordering is deterministic")
    func orderingIsDeterministic() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        for _ in 0..<3 { _ = try insertBookmark(into: database) }
        let eventID = try insertEvent(into: database)
        let service = CiderCaptureProvenanceDiagnosticService(database: database)

        let first = try #require(try service.explain(captureEventRef: "capture_event:\(eventID.uuidString)").candidateDiscovery)
        let second = try #require(try service.explain(captureEventRef: "capture_event:\(eventID.uuidString)").candidateDiscovery)

        #expect(first == second)
        #expect(first.countsByEvidenceCategory.map(\.category) == [.exactPersistedItemReference, .canonicalURLMatch, .nearbyDuplicateAuditMatch])
        #expect(first.candidateRefs == first.candidateRefs.sorted())
    }

    @Test("candidate explanation excludes private capture item URL and audit content")
    func privacySentinelsAreExcluded() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        _ = try insertBookmark(url: "https://example.com/private-candidate", into: database)
        let eventID = try insertEvent(
            sourceURL: "https://example.com/private-candidate",
            metadataJSON: DatabaseHelpers.encodeJSON(["private": "PRIVATE_METADATA_SENTINEL"])!,
            into: database
        )

        let serialized = try #require(try explain(eventID, database: database).candidateDiscovery).toDictionary().description

        for sentinel in ["PRIVATE_CAPTURE_SENTINEL", "PRIVATE_ITEM_SENTINEL", "PRIVATE_PATH_SENTINEL", "PRIVATE_METADATA_SENTINEL", "PRIVATE_AUDIT_SENTINEL", "private-candidate"] {
            #expect(!serialized.contains(sentinel))
        }
    }

    @Test("candidate discovery performs no database mutation")
    func discoveryDoesNotMutate() throws {
        let (database, vault) = try makeDatabase()
        defer { database.close(); try? FileManager.default.removeItem(at: vault) }
        _ = try insertBookmark(into: database)
        let eventID = try insertEvent(into: database)
        let before = try rowCounts(database)

        let report = try explain(eventID, database: database)

        #expect(try rowCounts(database) == before)
        #expect(report.readOnly && !report.changed)
        #expect(report.candidateDiscovery?.readOnly == true)
        #expect(report.candidateDiscovery?.changed == false)
        #expect(report.candidateDiscovery?.safeVerificationCommands.allSatisfy {
            !$0.contains(" repair") && !$0.contains(" backfill") && !$0.contains(" apply") && !$0.contains(" link ")
        } == true)
    }
}
