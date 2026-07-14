import Foundation
import Testing
@testable import Cider

@Suite("Journal Intelligence Panel Model Tests")
@MainActor
struct JournalIntelligencePanelModelTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-intelligence-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    @Test("snapshot maps latest journal capture health and noisy graph candidates without promoting truth")
    func snapshotMapsLatestJournalCaptureHealthAndCandidates() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try insertJournal(noteID: noteID, title: "Daily Journal 2026-06-18", content: "I ate one Maruchan ramen. GLP-1 is still too expensive. Move the rowing machine to the garage.", createdAt: now, updatedAt: now, into: db)
        try insertChunk(noteID: noteID, updatedAt: now.addingTimeInterval(1), into: db)
        try insertCaptureEvent(noteID: noteID, eventID: "capture-journal-1", createdAt: now.addingTimeInterval(2), into: db)

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let graphOutput = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "one",
            sourceQuote: "I ate one Maruchan ramen.",
            sourceKind: "journal",
            objectTypeGuesses: [.object],
            relationGuesses: [.wants],
            confidence: 0.64,
            confidenceReason: "Journal sentence produced a vague object candidate.",
            source: "test.graph_candidate"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(graphOutput)

        let snapshot = try JournalIntelligencePanelService(database: db, now: { now }).latestSnapshot()

        #expect(snapshot.note?.id == noteID)
        #expect(snapshot.note?.title == "Daily Journal 2026-06-18")
        #expect(snapshot.captureHealth.provenanceStatus == "recorded")
        #expect(snapshot.captureHealth.indexingStatus == "indexed")
        #expect(snapshot.captureHealth.chunkCount == 1)
        #expect(snapshot.captureHealth.captureEventID == "capture-journal-1")

        #expect(snapshot.graphCandidates.count == 1)
        let candidate = try #require(snapshot.graphCandidates.first)
        #expect(candidate.mentionOrValue == "one")
        #expect(candidate.relationOrType == "wants")
        #expect(candidate.targetKind == "object")
        #expect(candidate.sourceQuote == "I ate one Maruchan ramen.")
        #expect(candidate.reviewState == "suggested")
        #expect(candidate.truthBoundary == "reviewable_candidate_not_truth")
        #expect(candidate.qualityLevel == "low")
        #expect(candidate.qualityFlags.contains("pronoun_or_placeholder_only"))
        #expect(candidate.safeActions.contains("inspect_source"))
        #expect(snapshot.safeNextCommands.contains("cider-cli item graph-candidates note \(noteID.uuidString) --json"))

        #expect(snapshot.memoryCandidates.isEmpty)
        #expect(snapshot.missingMemoryOpportunities.contains { $0.label == "GLP-1 cost barrier" })
        #expect(snapshot.missingMemoryOpportunities.contains { $0.label == "Rowing-machine-to-garage habit" })
    }

    @Test("snapshot reports stale indexing and no provenance for latest journal")
    func snapshotReportsStaleIndexingAndMissingProvenance() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_800_010_000)
        try insertJournal(noteID: noteID, title: "Daily Journal 2026-06-19", content: "Work pace mindset note.", createdAt: updatedAt, updatedAt: updatedAt, into: db)
        try insertChunk(noteID: noteID, updatedAt: updatedAt.addingTimeInterval(-60), into: db)

        let snapshot = try JournalIntelligencePanelService(database: db, now: { updatedAt }).latestSnapshot()

        #expect(snapshot.note?.id == noteID)
        #expect(snapshot.captureHealth.provenanceStatus == "missing")
        #expect(snapshot.captureHealth.indexingStatus == "stale")
        #expect(snapshot.captureHealth.chunkCount == 1)
        #expect(snapshot.missingMemoryOpportunities.contains { $0.label == "Work pace mindset" })
    }

    @Test("production Journal Review composes explicit accessible action controls and refresh")
    func productionJournalReviewComposesAccessibleActionControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/Cider/Views/JournalIntelligencePanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for requiredComposition in [
            "performReviewAction(",
            "JournalIntelligenceNativeButton(",
            "ViewThatFits(in: .horizontal)",
            "TextField(\n                        \"Corrected wording\"",
            "Menu(selectedTargetLabel(for: proposal) ?? \"Choose exact target\")",
            "accessibilityLabel: \"Approve this exact suggestion as a Cider memory\"",
            "accessibilityLabel: \"Save selected target as a correction without approving it\"",
            "accessibilityLabel: \"Reject \\(proposal.value) without accepting truth\"",
            "accessibilityLabel: \"Defer \\(proposal.value) for later review\"",
            "onReload()",
        ] {
            #expect(source.contains(requiredComposition))
        }
        #expect(source.contains("Journal Review action blocked"))
        #expect(source.contains("Durable decisions remain attached to their original timestamped Journal evidence."))
    }

    private func insertJournal(noteID: UUID, title: String, content: String, createdAt: Date, updatedAt: Date, into db: CiderDatabase) throws {
        let item = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, NULL, ?);
            """)
        item.bind(noteID.uuidString, at: 1)
            .bind(title, at: 2)
            .bind(createdAt.timeIntervalSince1970, at: 3)
            .bind(updatedAt.timeIntervalSince1970, at: 4)
            .bind("Inbox/Notes/\(title).md", at: 5)
        try item.step()

        let note = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        note.bind(noteID.uuidString, at: 1)
            .bind(content, at: 2)
        try note.step()
    }

    private func insertChunk(noteID: UUID, updatedAt: Date, into db: CiderDatabase) throws {
        let chunk = try db.prepare("""
            INSERT INTO content_chunks (id, item_id, owner_type, owner_id, source, title, body, chunk_index, content_hash, metadata, created_at, updated_at)
            VALUES (?, ?, 'note', ?, 'test', 'Journal body', 'Body', 0, 'hash', '{}', ?, ?);
            """)
        chunk.bind(UUID().uuidString, at: 1)
            .bind(noteID.uuidString, at: 2)
            .bind(noteID.uuidString, at: 3)
            .bind(updatedAt.timeIntervalSince1970, at: 4)
            .bind(updatedAt.timeIntervalSince1970, at: 5)
        try chunk.step()
    }

    private func insertCaptureEvent(noteID: UUID, eventID: String, createdAt: Date, into db: CiderDatabase) throws {
        let event = try db.prepare("""
            INSERT INTO capture_events (id, source_kind, surface, channel, channel_id, thread_id, message_id, sender_id, sender_name, source_url, source_file, source_text, attachment_count, metadata, created_at)
            VALUES (?, 'journal', 'app', 'debug', NULL, NULL, NULL, NULL, 'Visher', NULL, NULL, 'Journal source', 0, '{}', ?);
            """)
        event.bind(eventID, at: 1)
            .bind(createdAt.timeIntervalSince1970, at: 2)
        try event.step()

        let relation = try db.prepare("""
            INSERT INTO owner_relations (id, source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at)
            VALUES (?, 'capture_event', ?, 'note', ?, 'produced_item', 'capture produced journal note', 'test', 'test', 1.0, '{}', ?, ?);
            """)
        relation.bind(UUID().uuidString, at: 1)
            .bind(eventID, at: 2)
            .bind(noteID.uuidString, at: 3)
            .bind(createdAt.timeIntervalSince1970, at: 4)
            .bind(createdAt.timeIntervalSince1970, at: 5)
        try relation.step()
    }
}
