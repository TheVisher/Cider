import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Item Content Indexing Tests")
@MainActor
struct SecondBrainItemContentIndexingTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-index-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-index-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func withIsolatedVault<T>(_ body: (CiderDatabase, NotesStorage) throws -> T) throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer {
            db.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        let notes = NotesStorage(database: db)
        return try body(db, notes)
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("item content indexer rebuilds searchable chunks for library item types")
    func itemContentIndexerRebuildsSearchableChunksForLibraryItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID().uuidString
        let todoID = UUID().uuidString
        let bookmarkID = UUID().uuidString
        try insertItem(id: noteID, type: "note", title: "Project field note", into: db)
        try insertNote(id: noteID, content: "The orchard-alpha audit belongs in project context.", summary: "Audit note", into: db)
        try insertItem(id: todoID, type: "todo", title: "Renew passport", into: db)
        try insertTodo(id: todoID, details: "Passport-renewal window opens in June.", notes: "Bring photos.", into: db)
        try insertItem(id: bookmarkID, type: "bookmark", title: "Reference bookmark", into: db)
        try insertBookmark(id: bookmarkID, url: "https://example.com/graph", notes: "Relation-graph reference", summary: "Graph source", into: db)

        let indexer = SecondBrainItemContentIndexingService(database: db)
        let results = try indexer.rebuildAll()

        #expect(results.count == 3)
        #expect(try SecondBrainStore(database: db).searchChunks(query: "orchard-alpha", limit: 5).first?.owner.ownerType == "note")
        #expect(try SecondBrainStore(database: db).searchChunks(query: "Passport-renewal", limit: 5).first?.owner.ownerType == "todo")
        #expect(try SecondBrainStore(database: db).searchChunks(query: "Relation-graph", limit: 5).first?.owner.ownerType == "bookmark")
    }

    @Test("item content index rebuild is idempotent and removes stale chunks")
    func itemContentIndexRebuildIsIdempotentAndRemovesStaleChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID().uuidString
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID)
        try insertItem(id: noteID, type: "note", title: "Mutable note", into: db)
        try insertNote(id: noteID, content: "obsolete-index-token", summary: nil, into: db)

        let indexer = SecondBrainItemContentIndexingService(database: db)
        _ = try indexer.rebuild(owner: owner)

        try updateNote(id: noteID, content: "fresh-index-token", into: db)
        let result = try indexer.rebuild(owner: owner)

        let store = SecondBrainStore(database: db)
        #expect(result.chunkCount == 1)
        #expect(try store.searchChunks(query: "obsolete-index-token", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "fresh-index-token", limit: 5).first?.owner == owner)
    }

    @Test("direct note creation immediately indexes searchable chunks")
    func directNoteCreationImmediatelyIndexesSearchableChunks() throws {
        try withIsolatedVault { db, notes in
            let note = notes.createNew(initialContent: "direct-note-index-token")

            let matches = try SecondBrainStore(database: db).searchChunks(
                query: "direct-note-index-token",
                limit: 5
            )
            #expect(matches.first?.owner == SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString))
        }
    }

    @Test("bookmark detail mutations rebuild searchable chunks")
    func bookmarkDetailMutationsRebuildSearchableChunks() throws {
        try withIsolatedVault { db, _ in
            let bookmark = Bookmark(
                title: "Mutable Bookmark",
                urlString: "https://example.com/original",
                notes: "obsolete-bookmark-token"
            )
            let seed = VaultBookmarkService(database: db, schedulesEnrichment: false)
            seed.persistBookmarkToDatabase(db, bookmark: bookmark)

            let service = VaultBookmarkService(database: db, schedulesEnrichment: false)
            service.loadBookmarksFromDatabase(db)

            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.id.uuidString)
            _ = try SecondBrainItemContentIndexingService(database: db).rebuild(owner: owner)

            #expect(service.updateDetails(
                for: bookmark.id,
                title: "Mutable Bookmark",
                notes: "fresh-bookmark-token",
                tags: []
            ) == true)

            let store = SecondBrainStore(database: db)
            #expect(try store.searchChunks(query: "obsolete-bookmark-token", limit: 5).isEmpty)
            #expect(try store.searchChunks(query: "fresh-bookmark-token", limit: 5).first?.owner == owner)
        }
    }

    @Test("bookmark OCR title promotion rebuilds searchable chunks")
    func bookmarkOCRTitlePromotionRebuildsSearchableChunks() throws {
        try withIsolatedVault { db, _ in
            let bookmark = Bookmark(
                title: "TikTok - Make Your Day",
                urlString: "https://www.tiktok.com/t/ZP8poHUSr/",
                ocrText: "Richmond night market 5/29/26 BAU BOT TITKE",
                relativePath: "Inbox/Bookmarks/Tiktok.Com (3).webloc"
            )
            let seed = VaultBookmarkService(database: db, schedulesEnrichment: false)
            seed.persistBookmarkToDatabase(db, bookmark: bookmark)

            let service = VaultBookmarkService(database: db, schedulesEnrichment: false)
            service.loadBookmarksFromDatabase(db)

            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.id.uuidString)
            _ = try SecondBrainItemContentIndexingService(database: db).rebuild(owner: owner)

            _ = service.applyStoredOCRTitleCandidateIfNeeded(for: bookmark.id)

            let store = SecondBrainStore(database: db)
            #expect(try store.searchChunks(query: "\"Make Your Day\"", limit: 5).isEmpty)
            #expect(try store.searchChunks(query: "\"Richmond Night Market\"", limit: 5).first?.owner == owner)
        }
    }

    @Test("bookmark folder assignment rebuilds searchable chunks")
    func bookmarkFolderAssignmentRebuildsSearchableChunks() throws {
        try withIsolatedVault { db, _ in
            let folderID = UUID()
            try insertFolder(id: folderID.uuidString, relativePath: "Projects/Research", into: db)

            let sourceDirectory = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent("Projects/Research")
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            let sourceFile = sourceDirectory.appendingPathComponent("Mutable Bookmark.webloc")
            let plist: [String: String] = ["URL": "https://example.com/original"]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: sourceFile, options: .atomic)

            let bookmark = Bookmark(
                title: "Mutable Bookmark",
                urlString: "https://example.com/original",
                notes: "bookmark-move-index-token",
                folderID: folderID,
                relativePath: "Projects/Research/Mutable Bookmark.webloc"
            )
            let seed = VaultBookmarkService(database: db, schedulesEnrichment: false)
            seed.persistBookmarkToDatabase(db, bookmark: bookmark)

            let service = VaultBookmarkService(database: db, schedulesEnrichment: false)
            service.loadBookmarksFromDatabase(db)

            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.id.uuidString)
            _ = try SecondBrainItemContentIndexingService(database: db).rebuild(owner: owner)

            #expect(service.assignBookmark(bookmark.id, toFolder: nil) == true)

            let store = SecondBrainStore(database: db)
            #expect(try store.searchChunks(query: "Research", limit: 5).isEmpty)
            #expect(try store.searchChunks(query: "Inbox", limit: 5).first?.owner == owner)
        }
    }

    private func insertItem(id: String, type: String, title: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(id, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
            .bind("Inbox/\(title).md", at: 6)
        try stmt.step()
    }

    private func insertNote(id: String, content: String, summary: String?, into db: CiderDatabase) throws {
        let stmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, ?, 0);")
        stmt.bind(id, at: 1)
            .bind(content, at: 2)
            .bind(summary, at: 3)
        try stmt.step()
    }

    private func updateNote(id: String, content: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("UPDATE notes SET content = ? WHERE item_id = ?;")
        stmt.bind(content, at: 1)
            .bind(id, at: 2)
        try stmt.step()
    }

    private func insertFolder(id: String, relativePath: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(id, at: 1)
            .bind(relativePath, at: 2)
            .bind(DatabaseHelpers.encode(Date()), at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
        try stmt.step()
    }

    private func insertTodo(id: String, details: String, notes: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO todos (
                item_id, details, due_date, priority, is_completed, completed_at,
                notes, checklist, surfacing_rules, action_url, snoozed_until
            ) VALUES (?, ?, NULL, 'medium', 0, NULL, ?, NULL, NULL, NULL, NULL);
            """)
        stmt.bind(id, at: 1)
            .bind(details, at: 2)
            .bind(notes, at: 3)
        try stmt.step()
    }

    private func insertBookmark(id: String, url: String, notes: String, summary: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO bookmarks (
                item_id, url, notes, notes_manually_set, title_manually_set,
                ai_summary, enrichment_status, last_enriched_at, ocr_text, dominant_colors,
                media_type, thumbnail_relative_path, thumbnail_remote_url, original_image_path,
                carousel_image_paths, reader_unavailable, preferred_hero_mode
            ) VALUES (?, ?, ?, 0, 0, ?, 'complete', NULL, NULL, NULL, 'article', NULL, NULL, NULL, NULL, NULL, NULL);
            """)
        stmt.bind(id, at: 1)
            .bind(url, at: 2)
            .bind(notes, at: 3)
            .bind(summary, at: 4)
        try stmt.step()
    }
}
