import Foundation
import Testing
@testable import Cider

@Suite("Bookmark SQLite Tests")
@MainActor
struct BookmarkSQLiteTests {

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-bookmark-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    /// Create and open a fresh database for testing.
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    /// Create VaultBookmarkService wired to the test database.
    private func makeService(_ db: CiderDatabase) -> VaultBookmarkService {
        VaultBookmarkService(database: db)
    }

    // MARK: - Basic Round-Trip

    @Test("Bookmark round-trips through SQLite: persist and load")
    func bookmarkRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Example Site",
            urlString: "https://example.com",
            notes: "A test note",
            relativePath: "Inbox/Bookmarks/Example Site.webloc"
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Load into a fresh service
        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = service2.bookmarks[0]
        #expect(loaded.id == bookmark.id)
        #expect(loaded.title == "Example Site")
        #expect(loaded.urlString == "https://example.com")
        #expect(loaded.notes == "A test note")
        #expect(loaded.relativePath == "Inbox/Bookmarks/Example Site.webloc")
    }

    @Test("Bookmark preserves all optional fields")
    func bookmarkAllFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Full Bookmark",
            urlString: "https://example.com/full",
            notes: "Detailed notes here",
            thumbnailRemoteURLString: "https://example.com/thumb.jpg",
            thumbnailRelativePath: ".thumbnails/thumb.jpg",
            originalImageRelativePath: ".originals/original.jpg",
            aiSummary: "This is an AI summary",
            ocrText: "OCR extracted text",
            dominantColors: ["#FF0000", "#00FF00", "#0000FF"],
            mediaType: .image,
            carouselImagePaths: [".originals/img1.jpg", ".originals/img2.jpg"],
            readerUnavailable: true,
            preferredHeroMode: "thumbnail",
            relativePath: "Tech/Full Bookmark.webloc",
            titleManuallySet: true,
            notesManuallySet: true
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = service2.bookmarks[0]
        #expect(loaded.title == "Full Bookmark")
        #expect(loaded.thumbnailRemoteURLString == "https://example.com/thumb.jpg")
        #expect(loaded.thumbnailRelativePath == ".thumbnails/thumb.jpg")
        #expect(loaded.originalImageRelativePath == ".originals/original.jpg")
        #expect(loaded.aiSummary == "This is an AI summary")
        #expect(loaded.ocrText == "OCR extracted text")
        #expect(loaded.dominantColors == ["#FF0000", "#00FF00", "#0000FF"])
        #expect(loaded.mediaType == .image)
        #expect(loaded.carouselImagePaths == [".originals/img1.jpg", ".originals/img2.jpg"])
        #expect(loaded.readerUnavailable == true)
        #expect(loaded.preferredHeroMode == "thumbnail")
        #expect(loaded.titleManuallySet == true)
        #expect(loaded.notesManuallySet == true)
    }

    @Test("Bookmark with nil optional fields round-trips correctly")
    func bookmarkNilFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Minimal",
            urlString: "https://minimal.com"
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(loaded.thumbnailRemoteURLString == nil)
        #expect(loaded.thumbnailRelativePath == nil)
        #expect(loaded.originalImageRelativePath == nil)
        #expect(loaded.aiSummary == nil)
        #expect(loaded.ocrText == nil)
        #expect(loaded.dominantColors == nil)
        #expect(loaded.mediaType == nil)
        #expect(loaded.carouselImagePaths == nil)
        #expect(loaded.readerUnavailable == nil)
        #expect(loaded.preferredHeroMode == nil)
        #expect(loaded.titleManuallySet == false)
        #expect(loaded.notesManuallySet == false)
    }

    // MARK: - Tags

    @Test("Tags round-trip through item_tags join table")
    func tagsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Tagged Bookmark",
            urlString: "https://tagged.com",
            tags: ["swift", "database", "testing"]
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(Set(loaded.tags) == Set(["swift", "database", "testing"]))
    }

    @Test("Tags are shared between bookmarks (find-or-create)")
    func tagsShared() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bk1 = Bookmark(title: "BK1", urlString: "https://one.com", tags: ["shared", "unique1"])
        let bk2 = Bookmark(title: "BK2", urlString: "https://two.com", tags: ["shared", "unique2"])

        service.persistBookmarkToDatabase(db, bookmark: bk1)
        service.persistBookmarkToDatabase(db, bookmark: bk2)

        // Verify only 3 tag rows exist (not 4)
        let stmt = try db.prepare("SELECT count(*) FROM tags;")
        try stmt.step()
        #expect(stmt.int(at: 0) == 3) // "shared", "unique1", "unique2"
    }

    @Test("Updating tags replaces old ones")
    func tagsUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var bookmark = Bookmark(title: "Evolving", urlString: "https://evolve.com", tags: ["old1", "old2"])
        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Update tags
        bookmark.tags = ["new1", "new2", "new3"]
        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(Set(loaded.tags) == Set(["new1", "new2", "new3"]))
    }

    // MARK: - Labels (Join Tables)

    @Test("Label IDs round-trip through item_labels join table")
    func labelIDsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        // Insert labels first (FK constraint)
        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Work", colorHex: "#3B82F6")
        let label2 = labelStorage.createLabel(name: "Personal", colorHex: "#22C55E")

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Labeled",
            urlString: "https://labeled.com",
            labelIDs: [label1.id, label2.id]
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(Set(loaded.labelIDs) == Set([label1.id, label2.id]))
    }

    @Test("Dismissed label IDs round-trip through dismissed_labels join table")
    func dismissedLabelIDsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Dismissed1", colorHex: "#EF4444")
        let label2 = labelStorage.createLabel(name: "Dismissed2", colorHex: "#F59E0B")

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Dismissed",
            urlString: "https://dismissed.com",
            dismissedLabelIDs: [label1.id, label2.id]
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(Set(loaded.dismissedLabelIDs) == Set([label1.id, label2.id]))
    }

    @Test("Updating labels replaces old label assignments")
    func labelIDsUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "L1")
        let label2 = labelStorage.createLabel(name: "L2")
        let label3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)

        var bookmark = Bookmark(
            title: "Label Update",
            urlString: "https://update.com",
            labelIDs: [label1.id, label2.id]
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Update to different labels
        bookmark.labelIDs = [label2.id, label3.id]
        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(Set(loaded.labelIDs) == Set([label2.id, label3.id]))
    }

    // MARK: - Folder Assignment

    @Test("Bookmark with folder ID round-trips")
    func bookmarkWithFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        // Create a folder first (FK constraint)
        let folder = VaultFolder(relativePath: "Tech")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "In Folder",
            urlString: "https://folder.com",
            folderID: folder.id,
            relativePath: "Tech/In Folder.webloc"
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(loaded.folderID == folder.id)
    }

    // MARK: - Delete

    @Test("Delete bookmark removes from items (CASCADE cleans detail + join tables)")
    func deleteBookmark() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "ToDelete")

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Doomed",
            urlString: "https://doomed.com",
            tags: ["doomed-tag"],
            labelIDs: [label.id]
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Verify it exists
        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)
        #expect(service2.bookmarks.count == 1)

        // Delete it
        service.deleteBookmarkFromDatabase(db, bookmarkID: bookmark.id)

        // Verify all traces are gone
        let service3 = makeService(db)
        service3.loadBookmarksFromDatabase(db)
        #expect(service3.bookmarks.isEmpty)

        // Verify join tables are cleaned up via CASCADE
        let labelsStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelsStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try labelsStmt.step()
        #expect(labelsStmt.int(at: 0) == 0)

        let tagsStmt = try db.prepare("SELECT count(*) FROM item_tags WHERE item_id = ?;")
        tagsStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try tagsStmt.step()
        #expect(tagsStmt.int(at: 0) == 0)

        // Verify the bookmark detail row is gone
        let bkStmt = try db.prepare("SELECT count(*) FROM bookmarks WHERE item_id = ?;")
        bkStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try bkStmt.step()
        #expect(bkStmt.int(at: 0) == 0)
    }

    // MARK: - Multiple Bookmarks

    @Test("Multiple bookmarks persist and load correctly")
    func multipleBookmarks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bk1 = Bookmark(title: "First", urlString: "https://first.com")
        let bk2 = Bookmark(title: "Second", urlString: "https://second.com")
        let bk3 = Bookmark(title: "Third", urlString: "https://third.com")

        service.persistBookmarkToDatabase(db, bookmark: bk1)
        service.persistBookmarkToDatabase(db, bookmark: bk2)
        service.persistBookmarkToDatabase(db, bookmark: bk3)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 3)
        let titles = Set(service2.bookmarks.map(\.title))
        #expect(titles == Set(["First", "Second", "Third"]))
    }

    @Test("Updating an existing bookmark replaces its data")
    func updateBookmark() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var bookmark = Bookmark(
            title: "Original Title",
            urlString: "https://original.com",
            notes: "Original notes"
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Update
        bookmark.title = "Updated Title"
        bookmark.notes = "Updated notes"
        bookmark.titleManuallySet = true
        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = service2.bookmarks[0]
        #expect(loaded.title == "Updated Title")
        #expect(loaded.notes == "Updated notes")
        #expect(loaded.titleManuallySet == true)
    }

    // MARK: - Date Precision

    @Test("Date fields survive round-trip with reasonable precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let now = Date()
        let bookmark = Bookmark(
            title: "Timed",
            urlString: "https://timed.com",
            createdAt: now,
            updatedAt: now
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(abs(loaded.createdAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(now)) < 0.001)
    }

    // MARK: - Empty Database

    @Test("Empty database loads empty bookmarks array")
    func emptyDatabaseLoadsEmpty() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadBookmarksFromDatabase(db)

        #expect(service.bookmarks.isEmpty)
    }

    // MARK: - Transaction Integrity

    @Test("Bookmark persist is atomic — all tables written together")
    func transactionIntegrity() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "Atomic")

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Atomic Bookmark",
            urlString: "https://atomic.com",
            tags: ["atomic-tag"],
            labelIDs: [label.id],
            dismissedLabelIDs: []
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        // Verify items row
        let itemStmt = try db.prepare("SELECT count(*) FROM items WHERE id = ?;")
        itemStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try itemStmt.step()
        #expect(itemStmt.int(at: 0) == 1)

        // Verify bookmarks row
        let bkStmt = try db.prepare("SELECT count(*) FROM bookmarks WHERE item_id = ?;")
        bkStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try bkStmt.step()
        #expect(bkStmt.int(at: 0) == 1)

        // Verify item_labels row
        let labelStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try labelStmt.step()
        #expect(labelStmt.int(at: 0) == 1)

        // Verify item_tags row
        let tagStmt = try db.prepare("SELECT count(*) FROM item_tags WHERE item_id = ?;")
        tagStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
        try tagStmt.step()
        #expect(tagStmt.int(at: 0) == 1)

        // Verify tags row
        let tagNameStmt = try db.prepare("SELECT name FROM tags LIMIT 1;")
        try tagNameStmt.step()
        #expect(tagNameStmt.string(at: 0) == "atomic-tag")
    }
}
