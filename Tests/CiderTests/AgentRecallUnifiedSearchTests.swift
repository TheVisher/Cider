import Foundation
import Testing
@testable import Cider

@Suite("Agent Recall Unified Search Tests")
@MainActor
struct AgentRecallUnifiedSearchTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-agent-recall-\(UUID().uuidString).db")
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

    @Test("assistant recall search formats unified item results with ids paths snippets and commands")
    func assistantRecallSearchFormatsUnifiedItemResults() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            note,
            title: "Dental follow-up",
            relativePath: "Inbox/Notes/Dental follow-up.md",
            into: db
        )
        try insertItem(
            bookmark,
            title: "Dental insurance portal",
            relativePath: "Inbox/Bookmarks/Dental insurance portal.url",
            into: db
        )

        let store = SecondBrainStore(database: db)
        try store.replaceChunks(
            owner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.entityID.uuidString),
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    itemID: bookmark.entityID.uuidString,
                    source: "bookmark-summary",
                    title: "Insurance details",
                    body: "The dental claim renewal window opens in September.",
                    chunkIndex: 0
                ),
            ]
        )

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let response = try CiderAgentItemSearchFormatter.searchResponse(
            query: "dental",
            itemType: nil,
            service: service,
            limit: 10
        )

        #expect(response.contains("Found 2 result(s) through unified item search:"))
        #expect(response.contains("note \(note.entityID.uuidString)"))
        #expect(response.contains("bookmark \(bookmark.entityID.uuidString)"))
        #expect(response.contains("Path: Inbox/Notes/Dental follow-up.md"))
        #expect(response.contains("Path: Inbox/Bookmarks/Dental insurance portal.url"))
        #expect(response.contains("Snippet: Inbox/Notes/Dental follow-up.md"))
        #expect(response.contains("claim renewal window opens in September."))
        #expect(response.contains("cider-cli item context note \(note.entityID.uuidString) --json"))
        #expect(response.contains("cider-cli item context bookmark \(bookmark.entityID.uuidString) --json"))

        let noteOnly = try CiderAgentItemSearchFormatter.searchResponse(
            query: "dental",
            itemType: "notes",
            service: service,
            limit: 10
        )

        #expect(noteOnly.contains("note \(note.entityID.uuidString)"))
        #expect(!noteOnly.contains("bookmark \(bookmark.entityID.uuidString)"))
    }

    @Test("assistant recent items formats shared item context refs and commands")
    func assistantRecentItemsFormatsSharedItemContextRefsAndCommands() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            note,
            title: "Recent Main Brain note",
            relativePath: "Inbox/Notes/Recent Main Brain note.md",
            into: db
        )
        try insertItem(
            bookmark,
            title: "Recent shared context bookmark",
            relativePath: "Inbox/Bookmarks/Recent shared context bookmark.url",
            into: db
        )

        let service = CiderItemContextService(database: db, nowProvider: { now })

        let response = try CiderAgentRecentItemsFormatter.recentItemsResponse(
            days: 7,
            service: service,
            now: now,
            limit: 10
        )

        #expect(response.contains("Items from the last 7 day(s) through shared item context:"))
        #expect(response.contains("note \(note.entityID.uuidString): \"Recent Main Brain note\""))
        #expect(response.contains("bookmark \(bookmark.entityID.uuidString): \"Recent shared context bookmark\""))
        #expect(response.contains("Path: Inbox/Notes/Recent Main Brain note.md"))
        #expect(response.contains("Path: Inbox/Bookmarks/Recent shared context bookmark.url"))
        #expect(response.contains("Command: cider-cli item context note \(note.entityID.uuidString) --json"))
        #expect(response.contains("Command: cider-cli item context bookmark \(bookmark.entityID.uuidString) --json"))
    }
}
