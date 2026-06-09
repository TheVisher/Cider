import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Intelligence Dogfood Service Tests")
@MainActor
struct SecondBrainIntelligenceDogfoodServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-intelligence-dogfood-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("dogfood rebuild populates reviewable enrichment and similarity stores from chunked owners")
    func dogfoodRebuildPopulatesReviewableIntelligenceStoresFromChunkedOwners() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let launch = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let roadmap = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let contactID = UUID()
        let contact = SecondBrainOwnerRef(ownerType: "contact", ownerID: contactID.uuidString)
        try insertNoteItem(owner: launch, title: "Launch graph", into: db)
        try insertNoteItem(owner: roadmap, title: "Launch roadmap", into: db)
        try insertContactItem(id: contactID, displayName: "Avery Stone", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: launch, chunks: [
            chunk(
                owner: launch,
                body: "Met Avery Stone about the Cider graph launch roadmap agent context Apple Park https://example.com/launch #ProductLaunch"
            )
        ])
        try store.replaceChunks(owner: roadmap, chunks: [
            chunk(
                owner: roadmap,
                body: "Apple Park product launch roadmap for Cider agent context https://example.com/roadmap #ProductLaunch"
            )
        ])

        let result = try SecondBrainIntelligenceDogfoodService(database: db, store: store)
            .rebuild(limit: 2, threshold: 0.35, candidateLimit: 10)

        #expect(result.ownerCount == 2)
        #expect(result.enrichmentOutputCount >= 2)
        #expect(result.similarityCandidateCount >= 1)
        #expect(result.reviewRequired == true)
        #expect(result.owners.allSatisfy { $0.enrichmentReviewStates["suggested", default: 0] == $0.enrichmentOutputCount })
        #expect(result.owners.contains { $0.similarityReviewStates["suggested", default: 0] > 0 })
        #expect(try SecondBrainEnrichmentOutputService(database: db).outputs(for: launch).contains { $0.reviewState == "suggested" })
        let candidates = try SecondBrainSimilarityCandidateService(database: db, store: store).candidates(for: launch)
        #expect(candidates.contains { $0.reviewState == "suggested" })
        #expect(candidates.contains {
            $0.signal == "entity_enrichment"
                && $0.targetOwner == contact
                && $0.candidateType == "mentions"
                && $0.source == "enrichment_output"
                && $0.evidence.contains("Avery Stone")
        })
        #expect(try store.outgoingRelations(for: launch).isEmpty)
    }

    private func chunk(owner: SecondBrainOwnerRef, body: String) -> SecondBrainChunkDraft {
        SecondBrainChunkDraft(
            sectionID: nil,
            itemID: owner.ownerID,
            source: "item_index.note",
            title: "Test chunk",
            body: body,
            chunkIndex: 0
        )
    }

    private func insertNoteItem(owner: SecondBrainOwnerRef, title: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(title, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind("Inbox/\(owner.ownerID).md", at: 5)
        try itemStmt.step()

        let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, '', NULL, 0);")
        noteStmt.bind(owner.ownerID, at: 1)
        try noteStmt.step()
    }

    private func insertContactItem(id: UUID, displayName: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'contact', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(id.uuidString, at: 1)
            .bind(displayName, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind("Inbox/Contacts/\(displayName).vcf", at: 5)
        try itemStmt.step()

        let contactStmt = try db.prepare("""
            INSERT INTO contacts (item_id, relationship_label, notes, email, phone, address, has_avatar, custom_fields)
            VALUES (?, '', '', '', '', '', 0, '[]');
            """)
        contactStmt.bind(id.uuidString, at: 1)
        try contactStmt.step()
    }
}
