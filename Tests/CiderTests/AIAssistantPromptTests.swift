import Foundation
import Testing
@testable import Cider

@MainActor
struct AIAssistantPromptTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-ai-context-\(UUID().uuidString).db")
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

    @Test("Foundation Models prompt includes vault routing doctrine")
    func foundationPromptIncludesRoutingDoctrine() {
        let provider = FoundationModelsProvider()
        let prompt = provider._buildInstructionsForTesting(context: AIAssistantContext())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }

    @Test("MLX prompt includes vault routing doctrine")
    func mlxPromptIncludesRoutingDoctrine() {
        let provider = MLXProvider()
        let prompt = provider._buildSystemPromptForTesting(context: AIAssistantContext())

        #expect(prompt.contains("Vault save routing rules:"))
        #expect(prompt.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(prompt.contains("If the destination is unclear, save to Inbox and explain why."))
    }

    @Test("assistant prompt includes unified current item context for bookmark and note")
    func assistantPromptIncludesUnifiedCurrentItemContextForBookmarkAndNote() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            bookmark,
            title: "Swift Markdown Engine",
            relativePath: "Inbox/Bookmarks/Swift Markdown Engine.url",
            into: db
        )
        try insertItem(
            note,
            title: "Dentist follow-up",
            relativePath: "Inbox/Notes/Dentist follow-up.md",
            into: db
        )

        let service = CiderItemContextService(database: db)
        let bookmarkPacket = try service.agentContext(for: bookmark)
        let notePacket = try service.agentContext(for: note)
        let provider = FoundationModelsProvider()

        var bookmarkContext = AIAssistantContext()
        bookmarkContext.currentBookmark = (title: "Swift Markdown Engine", url: "https://example.com", summary: nil)
        bookmarkContext.currentItemContext = bookmarkPacket
        let bookmarkPrompt = provider._buildInstructionsForTesting(context: bookmarkContext)

        #expect(bookmarkPrompt.contains("Unified current item context: bookmark \"Swift Markdown Engine\""))
        #expect(bookmarkPrompt.contains("Provenance: item:bookmark"))
        #expect(bookmarkPrompt.contains("path:Inbox/Bookmarks/Swift Markdown Engine.url"))
        #expect(bookmarkPrompt.contains("cider-cli item get bookmark \(bookmark.entityID.uuidString) --json"))
        #expect(bookmarkPrompt.contains("cider-cli item context bookmark \(bookmark.entityID.uuidString) --json"))

        var noteContext = AIAssistantContext()
        noteContext.currentNote = (title: "Dentist follow-up", excerpt: "Call the dentist.")
        noteContext.currentItemContext = notePacket
        let notePrompt = provider._buildInstructionsForTesting(context: noteContext)

        #expect(notePrompt.contains("Unified current item context: note \"Dentist follow-up\""))
        #expect(notePrompt.contains("Provenance: item:note"))
        #expect(notePrompt.contains("path:Inbox/Notes/Dentist follow-up.md"))
        #expect(notePrompt.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(notePrompt.contains("cider-cli item context note \(note.entityID.uuidString) --json"))
    }
}
