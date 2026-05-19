import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Enrichment Output Tests")
@MainActor
struct SecondBrainEnrichmentOutputTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-enrichment-\(UUID().uuidString).db")
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

    @Test("chunk enrichment extracts reviewable links dates topics and entities")
    func chunkEnrichmentExtractsReviewableOutputs() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertNoteItem(owner: owner, into: db)
        try SecondBrainStore(database: db).replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: owner.ownerID,
                source: "item_index.note",
                title: "Launch note",
                body: "Title: Apple Park launch\nContent: Meet Jane Doe on June 20, 2026. Read https://example.com/launch #ProductLaunch",
                chunkIndex: 0
            )
        ])

        let service = SecondBrainEnrichmentOutputService(database: db)
        let result = try service.rebuildFromChunks(owner: owner)
        let outputs = try service.outputs(for: owner)

        #expect(result.outputCount >= 4)
        #expect(outputs.contains { $0.kind == "link" && $0.value == "https://example.com/launch" && $0.reviewState == "suggested" })
        #expect(outputs.contains { $0.kind == "date" && $0.evidence.contains("June 20, 2026") })
        #expect(outputs.contains { $0.kind == "topic" && $0.normalizedValue == "productlaunch" })
        #expect(outputs.contains { $0.kind == "entity" && $0.value == "Jane Doe" })
    }

    @Test("item context includes enrichment outputs")
    func itemContextIncludesEnrichmentOutputs() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertNoteItem(owner: owner, into: db)
        try SecondBrainStore(database: db).replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: owner.ownerID,
                source: "item_index.note",
                title: "Reference note",
                body: "Content: See https://example.com/context for the context packet.",
                chunkIndex: 0
            )
        ])
        _ = try SecondBrainEnrichmentOutputService(database: db).rebuildFromChunks(owner: owner)

        let ref = LibraryEntityRef(type: .note, entityID: UUID(uuidString: owner.ownerID)!)
        let bundle = try CiderItemContextService(database: db).context(for: ref)

        #expect(bundle.enrichmentOutputs.contains { $0.kind == "link" && $0.value == "https://example.com/context" })
    }

    private func insertNoteItem(owner: SecondBrainOwnerRef, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', 'Enriched note', ?, ?, NULL, 'Inbox/Enriched note.md');
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(now, at: 2)
            .bind(now, at: 3)
        try itemStmt.step()

        let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, '', NULL, 0);")
        noteStmt.bind(owner.ownerID, at: 1)
        try noteStmt.step()
    }
}
