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

        let contact = ContactCard(displayName: "Alice")
        let contactTrash = TrashItem(
            itemID: contact.id,
            itemType: .contact,
            title: contact.displayName,
            originalFolderID: nil,
            contactPayload: ContactTrashPayload(
                contact: contact,
                trashVCFFilename: "alice.vcf",
                trashAvatarRelativePath: nil,
                cascadedDateCardTrashIDs: []
            )
        )

        let vaultFolder = VaultFolder(relativePath: "Work/Projects")
        let vaultFolderTrash = TrashItem(
            itemID: vaultFolder.id,
            itemType: .vaultFolder,
            title: vaultFolder.name,
            originalFolderID: nil,
            vaultFolderPayload: VaultFolderTrashPayload(folder: vaultFolder)
        )

        let vaultFile = VaultFile(
            id: UUID(),
            filename: "photo.jpg",
            relativePath: "Work/photo.jpg",
            fileType: .image,
            fileSize: 1024,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            folderID: nil
        )
        let vaultFileTrash = TrashItem(
            itemID: vaultFile.id,
            itemType: .vaultFile,
            title: vaultFile.displayTitle,
            originalFolderID: nil,
            vaultFilePayload: VaultFileTrashPayload(vaultFile: vaultFile, trashFilename: "photo.jpg")
        )

        let items = [
            bookmark, note, dateCardTrash, todoTrash, kanban,
            contactTrash, vaultFolderTrash, vaultFileTrash
        ]
        for item in items {
            service.persistTrashItemToDatabase(db, item: item)
        }

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == items.count)
        let loadedTypes = Set(loaded.map(\.itemType))
        let expectedTypes: Set<TrashItemType> = [
            .bookmark, .note, .dateCard, .todo, .kanbanBoard,
            .contact, .vaultFolder, .vaultFile
        ]
        #expect(loadedTypes == expectedTypes)

        // Spot-check per-type payloads survived the round-trip.
        let loadedContact = loaded.first { $0.itemType == .contact }
        #expect(loadedContact?.contactPayload?.contact.displayName == "Alice")
        let loadedVaultFolder = loaded.first { $0.itemType == .vaultFolder }
        #expect(loadedVaultFolder?.vaultFolderPayload?.folder.relativePath == "Work/Projects")
        let loadedVaultFile = loaded.first { $0.itemType == .vaultFile }
        #expect(loadedVaultFile?.vaultFilePayload?.vaultFile.filename == "photo.jpg")
        #expect(loadedVaultFile?.vaultFilePayload?.trashFilename == "photo.jpg")
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

        // Exercise the real API — not raw SQL — so a regression that skips the
        // SQLite delete would be caught here.
        service.deleteAllTrashItemsFromDatabase()
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

    // MARK: - 15. VaultFolder trash mirrors into SQLite

    @Test("Persisting a vault folder TrashItem writes to the SQLite trash table")
    func vaultFolderTrashMirrored() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let folder = VaultFolder(relativePath: "Work/Deleted")
        let trashItem = TrashItem(
            itemID: folder.id,
            itemType: .vaultFolder,
            title: folder.name,
            originalFolderID: nil,
            vaultFolderPayload: VaultFolderTrashPayload(folder: folder)
        )

        service.persistTrashItemToDatabase(db, item: trashItem)

        let loaded = service.loadTrashItemsFromDatabase(db)
        #expect(loaded.count == 1)
        #expect(loaded.first?.itemType == .vaultFolder)
        #expect(loaded.first?.vaultFolderPayload?.folder.id == folder.id)
        #expect(loaded.first?.vaultFolderPayload?.folder.relativePath == "Work/Deleted")
    }

    // MARK: - 16. VaultFolder restore removes SQLite row

    @Test("Deleting a vault folder TrashItem clears the SQLite row (mirrors restore)")
    func vaultFolderRestoreRemovesFromSQLite() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let folder = VaultFolder(relativePath: "Archive")
        let trashItem = TrashItem(
            itemID: folder.id,
            itemType: .vaultFolder,
            title: folder.name,
            originalFolderID: nil,
            vaultFolderPayload: VaultFolderTrashPayload(folder: folder)
        )

        service.persistTrashItemToDatabase(db, item: trashItem)
        #expect(service.loadTrashItemsFromDatabase(db).count == 1)

        service.deleteTrashItemFromDatabase(db, trashItemID: trashItem.id)
        #expect(service.loadTrashItemsFromDatabase(db).isEmpty)
    }

    // MARK: - 17. purgeExpired clears SQLite rows

    @Test("purgeExpired removes stale rows from the SQLite trash table")
    func purgeExpiredClearsSQLite() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let audit = MutationAuditService(database: db)

        // Build a temp trash dir with a manifest containing one expired + one fresh item.
        let tmpTrashDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-trash-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpTrashDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpTrashDir) }

        let expiredItem = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Expired"),
            deletedAt: Date(timeIntervalSince1970: 1_600_000_000) // very old
        )
        let freshItem = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Fresh"),
            deletedAt: Date() // now
        )

        // Persist both to SQLite.
        service.persistTrashItemToDatabase(db, item: expiredItem)
        service.persistTrashItemToDatabase(db, item: freshItem)
        #expect(service.loadTrashItemsFromDatabase(db).count == 2)

        // Write both into the JSON manifest that purgeExpired scans.
        let manifestURL = tmpTrashDir.appendingPathComponent("_cider_trash_manifest.json")
        let encoder = JSONEncoder()
        let manifestData = try encoder.encode([expiredItem, freshItem])
        try manifestData.write(to: manifestURL, options: .atomic)

        // Cutoff: anything before "now - 1 day" is expired — matches expiredItem only.
        let cutoff = Date(timeIntervalSince1970: 1_650_000_000)
        service.purgeExpired(olderThan: cutoff, in: tmpTrashDir)

        let remaining = service.loadTrashItemsFromDatabase(db)
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Fresh")

        let entries = audit.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].action == "purge_expired")
        #expect(entries[0].itemID == expiredItem.itemID)
        #expect(entries[0].source == .cleanup)
    }

    @Test("permanentlyDelete removes row and records an audit entry")
    func permanentlyDeleteRecordsAuditEntry() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let audit = MutationAuditService(database: db)
        let item = makeBookmarkTrashItem(
            bookmark: makeBookmark(title: "Disposable"),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_111)
        )

        service.persistTrashItemToDatabase(db, item: item)
        #expect(service.loadTrashItemsFromDatabase(db).count == 1)

        service.permanentlyDelete(item)

        #expect(service.loadTrashItemsFromDatabase(db).isEmpty)
        let entries = audit.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].action == "permanently_delete")
        #expect(entries[0].itemID == item.itemID)
        #expect(entries[0].beforeState["trashItemID"] == item.id.uuidString)
    }
}
