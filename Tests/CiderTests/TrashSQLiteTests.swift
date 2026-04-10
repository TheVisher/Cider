import Foundation
import Testing
@testable import Cider

@Suite("Trash SQLite Tests")
@MainActor
struct TrashSQLiteTests {

    // MARK: - Helpers

    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-trash-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func makeService(_ db: CiderDatabase) -> TrashStorage {
        TrashStorage(database: db)
    }

    private func makeBookmark(
        id: UUID = UUID(),
        title: String = "Example Bookmark",
        urlString: String = "https://example.com",
        folderID: UUID? = nil
    ) -> Bookmark {
        Bookmark(
            id: id,
            title: title,
            urlString: urlString,
            folderID: folderID
        )
    }

    private func makeBookmarkTrashItem(
        id: UUID = UUID(),
        bookmark: Bookmark? = nil,
        originalFolderID: UUID? = nil,
        deletedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        trashThumbnailRelativePath: String? = nil,
        trashOriginalRelativePath: String? = nil
    ) -> TrashItem {
        let bm = bookmark ?? makeBookmark()
        let payload = BookmarkTrashPayload(
            bookmark: bm,
            trashThumbnailRelativePath: trashThumbnailRelativePath,
            trashOriginalRelativePath: trashOriginalRelativePath
        )
        return TrashItem(
            id: id,
            itemID: bm.id,
            itemType: .bookmark,
            title: bm.title,
            originalFolderID: originalFolderID,
            deletedAt: deletedAt,
            bookmarkPayload: payload
        )
    }

    // MARK: - 1. Basic round-trip

    @Test("Trash item round-trips all top-level fields")
    func basicRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let folderID = UUID()
        let item = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Hello World", urlString: "https://hello.world"),
            originalFolderID: folderID,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
        service.persistTrashItemToDatabase(db, item: item)

        let service2 = makeService(db)
        let loaded = service2.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == 1)
        let got = loaded[0]
        #expect(got.id == item.id)
        #expect(got.itemID == item.itemID)
        #expect(got.itemType == .bookmark)
        #expect(got.title == "Hello World")
        #expect(got.originalFolderID == folderID)
        #expect(got.bookmarkPayload?.bookmark.urlString == "https://hello.world")
    }

    // MARK: - 2. All TrashItemType variants

    @Test("Every TrashItemType variant persists and decodes")
    func allTrashItemTypes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = makeBookmarkTrashItem()

        let note = TrashItem(
            itemID: UUID(),
            itemType: .note,
            title: "My Note",
            originalFolderID: nil,
            notePayload: NoteTrashPayload(
                noteFilename: "note-1.md",
                folderID: nil,
                createdAt: Date(timeIntervalSince1970: 1_690_000_000)
            )
        )

        let dateCard = DateCard(
            title: "Birthday",
            startAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let dateCardTrash = TrashItem(
            itemID: dateCard.id,
            itemType: .dateCard,
            title: dateCard.title,
            originalFolderID: nil,
            dateCardPayload: DateCardTrashPayload(dateCard: dateCard, trashICSFilename: "dc.ics")
        )

        let todoCard = TodoCard(title: "Buy milk")
        let todoTrash = TrashItem(
            itemID: todoCard.id,
            itemType: .todo,
            title: todoCard.title,
            originalFolderID: nil,
            todoCardPayload: TodoCardTrashPayload(todoCard: todoCard, trashICSFilename: nil)
        )

        let whiteboard = WhiteboardCanvas(name: "Sketch")
        let whiteboardTrash = TrashItem(
            itemID: whiteboard.id,
            itemType: .whiteboard,
            title: whiteboard.name,
            originalFolderID: nil,
            whiteboardPayload: WhiteboardTrashPayload(canvas: whiteboard)
        )

        let kanban = TrashItem(
            itemID: UUID(),
            itemType: .kanbanBoard,
            title: "Roadmap",
            originalFolderID: nil,
            kanbanBoardPayload: KanbanBoardTrashPayload(
                yamlContent: "columns: []\n",
                boardID: "abc123"
            )
        )

        let session = BrowserSession(
            name: "Session",
            tabs: [],
            sourceBrowserBundleID: nil,
            sourceBrowserName: nil,
            folderID: nil,
            labelIDs: []
        )
        let sessionTrash = TrashItem(
            itemID: session.id,
            itemType: .session,
            title: session.name,
            originalFolderID: nil,
            sessionPayload: BrowserSessionTrashPayload(session: session)
        )

        let items = [bookmark, note, dateCardTrash, todoTrash, whiteboardTrash, kanban, sessionTrash]
        for item in items {
            service.persistTrashItemToDatabase(db, item: item)
        }

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == items.count)
        let loadedTypes = Set(loaded.map(\.itemType))
        let expectedTypes: Set<TrashItemType> = [.bookmark, .note, .dateCard, .todo, .whiteboard, .kanbanBoard, .session]
        #expect(loadedTypes == expectedTypes)
    }

    // MARK: - 3. Nil originalFolderID

    @Test("Nil originalFolderID round-trips as nil")
    func nilOriginalFolderID() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let item = makeBookmarkTrashItem(originalFolderID: nil)
        service.persistTrashItemToDatabase(db, item: item)

        // Verify column value
        let stmt = try db.prepare("SELECT original_folder_id FROM trash WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(item.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == nil)

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.first?.originalFolderID == nil)
    }

    // MARK: - 4. UPSERT updates existing row

    @Test("Updating an existing trash item (UPSERT) replaces payload without duplicating row")
    func updateTrashItem() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let bookmark = makeBookmark(title: "v1", urlString: "https://v1.example")
        var item = makeBookmarkTrashItem(bookmark: bookmark)
        service.persistTrashItemToDatabase(db, item: item)

        // Replace payload with a renamed bookmark
        let updatedBookmark = makeBookmark(id: bookmark.id, title: "v2", urlString: "https://v2.example")
        item = TrashItem(
            id: item.id,
            itemID: item.itemID,
            itemType: .bookmark,
            title: "v2",
            originalFolderID: nil,
            deletedAt: item.deletedAt,
            bookmarkPayload: BookmarkTrashPayload(
                bookmark: updatedBookmark,
                trashThumbnailRelativePath: nil,
                trashOriginalRelativePath: nil
            )
        )
        service.persistTrashItemToDatabase(db, item: item)

        let countStmt = try db.prepare("SELECT count(*) FROM trash WHERE id = ?;")
        countStmt.bind(DatabaseHelpers.encode(item.id), at: 1)
        try countStmt.step()
        #expect(countStmt.int(at: 0) == 1)

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.first?.title == "v2")
        #expect(loaded.first?.bookmarkPayload?.bookmark.title == "v2")
        #expect(loaded.first?.bookmarkPayload?.bookmark.urlString == "https://v2.example")
    }

    // MARK: - 5. Delete removes row

    @Test("Delete removes trash row")
    func deleteTrashItem() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let item = makeBookmarkTrashItem()
        service.persistTrashItemToDatabase(db, item: item)

        service.deleteTrashItemFromDatabase(db, trashItemID: item.id)

        let stmt = try db.prepare("SELECT count(*) FROM trash WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(item.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    // MARK: - 6. Multiple items persist independently

    @Test("Multiple trash items persist and load independently ordered by deleted_at DESC")
    func multipleItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let item1 = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "First"),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let item2 = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Second"),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let item3 = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Third"),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        service.persistTrashItemToDatabase(db, item: item1)
        service.persistTrashItemToDatabase(db, item: item2)
        service.persistTrashItemToDatabase(db, item: item3)

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == 3)
        #expect(loaded.map(\.title) == ["First", "Second", "Third"])
    }

    // MARK: - 7. Empty database loads empty

    @Test("Empty database loads zero trash items")
    func emptyDatabase() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.isEmpty)
    }

    // MARK: - 8. deletedAt date precision

    @Test("deletedAt survives round-trip with sub-ms precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let deleted = Date(timeIntervalSince1970: 1_234_567_890.456)
        let item = makeBookmarkTrashItem(deletedAt: deleted)
        service.persistTrashItemToDatabase(db, item: item)

        let loaded = service.loadTrashItemsFromDatabase(db)
        let got = loaded.first!
        #expect(abs(got.deletedAt.timeIntervalSince(deleted)) < 0.001)
    }

    // MARK: - 9. Folder trash with nested folderContents round-trip

    @Test("Folder trash item with nested folderContents round-trips via payload")
    func folderWithNestedContents() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let childBookmark = makeBookmarkTrashItem(bookmark: makeBookmark(title: "Child BM"))
        let childNote = TrashItem(
            itemID: UUID(),
            itemType: .note,
            title: "Child Note",
            originalFolderID: nil,
            notePayload: NoteTrashPayload(noteFilename: "child.md", folderID: nil, createdAt: Date())
        )
        let folderItem = TrashItem(
            itemID: UUID(),
            itemType: .folder,
            title: "My Folder",
            originalFolderID: nil,
            folderContents: [childBookmark, childNote]
        )
        service.persistTrashItemToDatabase(db, item: folderItem)

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == 1)
        let got = loaded.first!
        #expect(got.itemType == .folder)
        #expect(got.folderContents?.count == 2)
        #expect(got.folderContents?.first?.title == "Child BM")
        #expect(got.folderContents?.last?.title == "Child Note")
    }

    // MARK: - 10. Bookmark payload with trash asset paths round-trip

    @Test("Bookmark payload with trashThumbnailRelativePath / trashOriginalRelativePath round-trips")
    func bookmarkWithAssetPaths() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let item = makeBookmarkTrashItem(
            trashThumbnailRelativePath: "thumbnails/foo.png",
            trashOriginalRelativePath: "originals/foo.jpg"
        )
        service.persistTrashItemToDatabase(db, item: item)

        let loaded = service.loadTrashItemsFromDatabase(db)
        let got = loaded.first!
        #expect(got.bookmarkPayload?.trashThumbnailRelativePath == "thumbnails/foo.png")
        #expect(got.bookmarkPayload?.trashOriginalRelativePath == "originals/foo.jpg")
    }

    // MARK: - 11. All top-level columns populated correctly

    @Test("All top-level columns are populated from item fields")
    func topLevelColumnsPopulated() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let folderID = UUID()
        let bookmark = makeBookmark(title: "Cols", urlString: "https://cols.example")
        let item = TrashItem(
            itemID: bookmark.id,
            itemType: .bookmark,
            title: "Cols",
            originalFolderID: folderID,
            deletedAt: Date(timeIntervalSince1970: 1_700_555_555),
            bookmarkPayload: BookmarkTrashPayload(
                bookmark: bookmark,
                trashThumbnailRelativePath: nil,
                trashOriginalRelativePath: nil
            )
        )
        service.persistTrashItemToDatabase(db, item: item)

        let stmt = try db.prepare("""
            SELECT id, item_id, item_type, title, original_folder_id, deleted_at
            FROM trash WHERE id = ?;
            """)
        stmt.bind(DatabaseHelpers.encode(item.id), at: 1)
        try stmt.step()
        #expect(DatabaseHelpers.decodeUUID(stmt.string(at: 0)) == item.id)
        #expect(DatabaseHelpers.decodeUUID(stmt.string(at: 1)) == bookmark.id)
        #expect(stmt.string(at: 2) == "bookmark")
        #expect(stmt.string(at: 3) == "Cols")
        #expect(DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "") == folderID)
        #expect(abs(stmt.double(at: 5) - item.deletedAt.timeIntervalSince1970) < 0.001)
    }

    // MARK: - 12. Batch persist inside a transaction (migration path)

    @Test("Batch persist via withTransaction + persistTrashItemToDatabaseInner persists all items")
    func batchMigrationInsideTransaction() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let batch = (0..<5).map { i in
            makeBookmarkTrashItem(
                bookmark: makeBookmark(title: "Migrated \(i)", urlString: "https://m\(i).example"),
                deletedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            )
        }

        try db.withTransaction {
            for item in batch {
                try service.persistTrashItemToDatabaseInner(db, item: item)
            }
        }

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == 5)
        let titles = Set(loaded.map(\.title))
        #expect(titles == Set(["Migrated 0", "Migrated 1", "Migrated 2", "Migrated 3", "Migrated 4"]))
    }

    // MARK: - 13. deleteAllTrashItemsFromDatabase clears the table

    @Test("deleteAllTrashItemsFromDatabase removes every row")
    func deleteAllClearsTable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        for i in 0..<3 {
            service.persistTrashItemToDatabase(
                db,
                item: makeBookmarkTrashItem(bookmark: makeBookmark(title: "Item \(i)"))
            )
        }
        #expect(service.loadTrashItemsFromDatabase(db).count == 3)

        // Use the test db via explicit delete — wipe all
        let stmt = try db.prepare("DELETE FROM trash;")
        try stmt.step()
        #expect(service.loadTrashItemsFromDatabase(db).isEmpty)
    }

    // MARK: - 14. Payload encodes full TrashItem (self-contained for decode)

    @Test("Payload is a full TrashItem JSON blob and decodes all per-type payload fields")
    func payloadSelfContained() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let bookmark = makeBookmark(title: "Full", urlString: "https://full.example")
        let item = TrashItem(
            itemID: bookmark.id,
            itemType: .bookmark,
            title: "Full",
            originalFolderID: UUID(),
            bookmarkPayload: BookmarkTrashPayload(
                bookmark: bookmark,
                trashThumbnailRelativePath: "thumbnails/a.png",
                trashOriginalRelativePath: nil
            )
        )
        service.persistTrashItemToDatabase(db, item: item)

        // Read the payload column directly and decode it.
        let stmt = try db.prepare("SELECT payload FROM trash WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(item.id), at: 1)
        try stmt.step()
        let payload = stmt.optionalString(at: 0) ?? ""
        let data = payload.data(using: .utf8) ?? Data()
        let decoded = try JSONDecoder().decode(TrashItem.self, from: data)
        #expect(decoded.id == item.id)
        #expect(decoded.itemType == .bookmark)
        #expect(decoded.title == "Full")
        #expect(decoded.bookmarkPayload?.bookmark.urlString == "https://full.example")
        #expect(decoded.bookmarkPayload?.trashThumbnailRelativePath == "thumbnails/a.png")
        #expect(decoded.bookmarkPayload?.trashOriginalRelativePath == nil)
    }
}
