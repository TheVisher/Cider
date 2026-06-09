import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Similarity Candidate Tests")
@MainActor
struct SecondBrainSimilarityCandidateTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-similarity-\(UUID().uuidString).db")
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

    @Test("chunk overlap rebuild creates reviewable owner similarity candidates")
    func chunkOverlapRebuildCreatesReviewableOwnerCandidates() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let near = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let unrelated = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertNoteItem(owner: owner, title: "Launch graph", into: db)
        try insertNoteItem(owner: near, title: "Launch roadmap", into: db)
        try insertNoteItem(owner: unrelated, title: "Kitchen note", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: owner, chunks: [
            chunk(owner: owner, body: "Cider graph launch roadmap agent context Apple Park")
        ])
        try store.replaceChunks(owner: near, chunks: [
            chunk(owner: near, body: "Apple Park product launch roadmap for Cider agent context")
        ])
        try store.replaceChunks(owner: unrelated, chunks: [
            chunk(owner: unrelated, body: "Sourdough starter hydration kitchen baking schedule")
        ])

        let service = SecondBrainSimilarityCandidateService(database: db, store: store)
        let result = try service.rebuildChunkOverlapCandidates(for: owner, threshold: 0.35, limit: 10)
        let candidates = try service.candidates(for: owner)

        #expect(result.candidateCount == 1)
        #expect(candidates.count == 1)
        #expect(candidates[0].sourceOwner == owner)
        #expect(candidates[0].targetOwner == near)
        #expect(candidates[0].candidateType == "similar_to")
        #expect(candidates[0].signal == "chunk_overlap")
        #expect(candidates[0].reviewState == "suggested")
        #expect(candidates[0].evidence.contains("overlap"))
        #expect(try store.outgoingRelations(for: owner).isEmpty)
    }

    @Test("accepting a similarity candidate creates a typed owner relation")
    func acceptingSimilarityCandidateCreatesTypedOwnerRelation() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let near = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertNoteItem(owner: owner, title: "Launch graph", into: db)
        try insertNoteItem(owner: near, title: "Launch roadmap", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: owner, chunks: [
            chunk(owner: owner, body: "Cider graph launch roadmap agent context Apple Park")
        ])
        try store.replaceChunks(owner: near, chunks: [
            chunk(owner: near, body: "Apple Park product launch roadmap for Cider agent context")
        ])

        let service = SecondBrainSimilarityCandidateService(database: db, store: store)
        _ = try service.rebuildChunkOverlapCandidates(for: owner, threshold: 0.35, limit: 10)
        let candidate = try #require(try service.candidates(for: owner).first)

        let accepted = try service.accept(candidateID: candidate.id, relationType: nil, actor: "test")
        let relations = try store.outgoingRelations(for: owner)

        #expect(accepted.reviewState == "accepted")
        #expect(relations.count == 1)
        #expect(relations[0].targetOwner == near)
        #expect(relations[0].relationType == "similar_to")
        #expect(relations[0].source == "similarity_candidate")
        #expect(relations[0].metadata["candidate_id"] == candidate.id)
    }

    @Test("entity enrichment creates reviewable contact relation candidates")
    func entityEnrichmentCreatesReviewableContactRelationCandidates() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let contactID = UUID()
        let contact = SecondBrainOwnerRef(ownerType: "contact", ownerID: contactID.uuidString)
        try insertNoteItem(owner: note, title: "Cafe follow-up", into: db)
        try insertContactItem(id: contactID, displayName: "Avery Stone", into: db)

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(owner: note, chunks: [
            chunk(owner: note, body: "Met Avery Stone at Sightglass and promised to send the launch graph notes.")
        ])
        _ = try SecondBrainEnrichmentOutputService(database: db).rebuildFromChunks(owner: note)

        let service = SecondBrainSimilarityCandidateService(database: db, store: store)
        let result = try service.rebuildEntityRelationCandidates(for: note, targetTypes: ["contact"], limit: 10)
        let candidate = try #require(try service.candidates(for: note).first { $0.signal == "entity_enrichment" })

        #expect(result.candidateCount == 1)
        #expect(candidate.sourceOwner == note)
        #expect(candidate.targetOwner == contact)
        #expect(candidate.candidateType == "mentions")
        #expect(candidate.signal == "entity_enrichment")
        #expect(candidate.source == "enrichment_output")
        #expect(candidate.score >= 0.8)
        #expect(candidate.reviewState == "suggested")
        #expect(candidate.evidence.contains("Avery Stone"))
        #expect(candidate.metadata["matched_entity"] == "Avery Stone")
        #expect(candidate.metadata["target_type"] == "contact")
        #expect(try store.outgoingRelations(for: note).isEmpty)

        let accepted = try service.accept(candidateID: candidate.id, relationType: nil, actor: "test")
        let relations = try store.outgoingRelations(for: note)

        #expect(accepted.reviewState == "accepted")
        #expect(relations.count == 1)
        #expect(relations[0].targetOwner == contact)
        #expect(relations[0].relationType == "mentions")
        #expect(relations[0].source == "similarity_candidate")
        #expect(relations[0].metadata["signal"] == "entity_enrichment")
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
