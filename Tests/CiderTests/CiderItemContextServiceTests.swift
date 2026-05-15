import Foundation
import Testing
@testable import Cider

@Suite("Cider Item Context Service Tests")
@MainActor
struct CiderItemContextServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-context-\(UUID().uuidString).db")
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

    private func insertItem(
        _ ref: LibraryEntityRef,
        title: String,
        relativePath: String?,
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    @Test("context bundle includes item identity, sections, chunks, and related items")
    func contextBundleIncludesIdentitySectionsChunksAndRelatedItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and check insurance first.",
                source: "test",
                sortOrder: 0
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Dentist follow-up",
                body: "Call the dentist and check insurance first.",
                chunkIndex: 0
            )
        ])

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(database: db, linkService: linkService, secondBrainStore: store)

        let bundle = try service.context(for: note)

        #expect(bundle.item.id == note.entityID)
        #expect(bundle.item.type == .note)
        #expect(bundle.item.title == "Dentist follow-up")
        #expect(bundle.item.relativePath == "Inbox/Notes/Dentist follow-up.md")
        #expect(bundle.sections.map(\.sectionKey) == ["summary"])
        #expect(bundle.chunks.map(\.body) == ["Call the dentist and check insurance first."])
        #expect(bundle.related.map(\.title) == ["Dental insurance portal"])
    }

    @Test("search returns item title matches and chunk text matches through one surface")
    func searchReturnsItemTitleMatchesAndChunkTextMatchesThroughOneSurface() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let dentist = LibraryEntityRef(type: .note, entityID: UUID())
        let renewal = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(dentist, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(renewal, title: "Review home insurance", relativePath: "Inbox/Todos/Review home insurance.md", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "todo", ownerID: renewal.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: renewal.entityID.uuidString,
                source: "test",
                title: "Insurance renewal",
                body: "The renewal window opens in September.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let titleMatches = try service.search("dentist", limit: 10)
        #expect(titleMatches.contains {
            $0.kind == .item && $0.item?.id == dentist.entityID && $0.title == "Dentist follow-up"
        })

        let chunkMatches = try service.search("renewal window", limit: 10)
        #expect(chunkMatches.contains {
            $0.kind == .chunk && $0.item?.id == renewal.entityID && $0.owner.ownerType == "todo"
        })
    }
}
