import AppKit
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

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-bookmark-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempDatabase(in vault: URL) throws -> CiderDatabase {
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: dbURL)
        return db
    }

    private func withIsolatedVault<T>(
        _ body: (CiderDatabase, VaultBookmarkService) throws -> T
    ) throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let db = try makeTempDatabase(in: vault)
        defer {
            db.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        let service = VaultBookmarkService(database: db, schedulesEnrichment: false)
        return try body(db, service)
    }

    /// Create VaultBookmarkService wired to the test database.
    private func makeService(_ db: CiderDatabase) -> VaultBookmarkService {
        VaultBookmarkService(database: db)
    }

    private func makeImageData(color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    private func setFilesystemDates(
        for fileURL: URL,
        createdAt: Date,
        modifiedAt: Date? = nil
    ) throws {
        var values = URLResourceValues()
        values.creationDate = createdAt
        values.contentModificationDate = modifiedAt ?? createdAt
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }

    private func storedItemDates(_ db: CiderDatabase, id: UUID) throws -> (createdAt: Date, updatedAt: Date) {
        let stmt = try db.prepare("SELECT created_at, updated_at FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        #expect(try stmt.step())
        return (
            DatabaseHelpers.decodeDate(stmt.double(at: 0)),
            DatabaseHelpers.decodeDate(stmt.double(at: 1))
        )
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

    @Test("Provider carousel replacement is idempotent across metadata refetches")
    func providerCarouselReplacementIsIdempotent() throws {
        try withIsolatedVault { db, service in
            let heroData = try makeImageData(color: .blue)
            let firstExtraData = try makeImageData(color: .green)
            let secondExtraData = try makeImageData(color: .red)

            let bookmarkID = UUID()
            let originalRelativePath = ".originals/\(bookmarkID.uuidString).tiff"
            let originalURL = StoragePaths.cachedDirectoryURL(for: .bookmarks)
                .appendingPathComponent(originalRelativePath)
            try FileManager.default.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try heroData.write(to: originalURL)

            let bookmark = Bookmark(
                id: bookmarkID,
                title: "Reddit gallery",
                urlString: "https://www.reddit.com/r/macapps/comments/example/gallery/",
                originalImageRelativePath: originalRelativePath
            )
            service.persistBookmarkToDatabase(db, bookmark: bookmark)
            service.loadBookmarksFromDatabase(db)

            #expect(service.replaceCarouselImagesForEnrichment(
                for: bookmarkID,
                imageDataList: [firstExtraData, secondExtraData],
                preferredFileExtension: "tiff"
            ))
            let firstPass = try #require(service.bookmarks.first?.carouselImagePaths)
            #expect(firstPass.count == 3)

            #expect(service.replaceCarouselImagesForEnrichment(
                for: bookmarkID,
                imageDataList: [firstExtraData, secondExtraData],
                preferredFileExtension: "tiff"
            ))
            let secondPass = try #require(service.bookmarks.first?.carouselImagePaths)
            #expect(secondPass == firstPass)
            #expect(secondPass.count == 3)
            #expect(!secondPass.contains { $0.contains("_3.") })
        }
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

    @Test("OEmbed enrichment does not overwrite manually set bookmark title")
    func oEmbedDoesNotOverwriteManualTitle() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "My Curated Title",
            urlString: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            titleManuallySet: true
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmark.id,
            title: "Network Suggested Title",
            notes: "Network supplied notes"
        )

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = try #require(service2.bookmarks.first)
        #expect(loaded.title == "My Curated Title")
        #expect(loaded.titleManuallySet == true)
        #expect(loaded.notes == "Network supplied notes")
    }

    @Test("AI enrichment does not overwrite manually set bookmark title")
    func aiEnrichmentDoesNotOverwriteManualTitle() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "Manual Image Title",
            urlString: "https://example.com/image",
            titleManuallySet: true
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyAIResults(
            for: bookmark.id,
            tags: ["ai-suggested"],
            ocrText: "OCR text",
            dominantColors: ["#112233"],
            title: "AI Suggested Title"
        )

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = try #require(service2.bookmarks.first)
        #expect(loaded.title == "Manual Image Title")
        #expect(loaded.titleManuallySet == true)
        #expect(loaded.tags == ["ai-suggested"])
        #expect(loaded.ocrText == "OCR text")
        #expect(loaded.dominantColors == ["#112233"])
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

    // MARK: - Enrichment Fields

    @Test("Enrichment status and lastEnrichedAt round-trip through SQLite")
    func enrichmentFieldsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let enrichedDate = Date()
        let bookmark = Bookmark(
            title: "Enriched Bookmark",
            urlString: "https://enriched.com",
            enrichmentStatus: "complete",
            lastEnrichedAt: enrichedDate
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        #expect(service2.bookmarks.count == 1)
        let loaded = service2.bookmarks[0]
        #expect(loaded.enrichmentStatus == "complete")
        #expect(loaded.lastEnrichedAt != nil)
        #expect(abs(loaded.lastEnrichedAt!.timeIntervalSince(enrichedDate)) < 0.001)
    }

    @Test("OEmbed enrichment completion clears bookmark review issue")
    func oEmbedEnrichmentCompletionClearsBookmarkReviewIssue() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let bookmark = Bookmark(
            title: "Dynamic Dungeons - Animated Gaming Table",
            urlString: "https://www.tiktok.com/t/example/",
            notes: "",
            relativePath: "Hobbies/Gaming/Dynamic Dungeons - Animated Gaming Table.webloc",
            titleManuallySet: true
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        let queueBefore = CiderReviewQueueService(database: db)
        #expect(try queueBefore.list().items.map(\.itemID) == [bookmark.id])

        service.applyOEmbedResults(
            for: bookmark.id,
            title: "Ignored because title is manual",
            notes: "By Dynamic Dungeons\nVia TikTok"
        )

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)
        let enriched = try #require(service2.bookmarks.first)
        #expect(enriched.title == "Dynamic Dungeons - Animated Gaming Table")
        #expect(enriched.notes == "By Dynamic Dungeons\nVia TikTok")
        #expect(enriched.enrichmentStatus == "complete")
        #expect(enriched.lastEnrichedAt != nil)

        let queueAfter = CiderReviewQueueService(database: db)
        #expect(try queueAfter.list().items.isEmpty)
    }

    @Test("Nil enrichment fields round-trip as nil")
    func enrichmentFieldsNil() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let bookmark = Bookmark(
            title: "No Enrichment",
            urlString: "https://noenrich.com"
        )

        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)

        let loaded = service2.bookmarks[0]
        #expect(loaded.enrichmentStatus == nil)
        #expect(loaded.lastEnrichedAt == nil)
    }

    // MARK: - Legacy Sidecar Backfill

    @Test("Legacy bookmark sidecar metadata backfills missing SQLite fields")
    func mergeLegacySidecarBackfillsMissingFields() {
        var bookmark = Bookmark(
            title: "Example Site",
            urlString: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: "Inbox/Bookmarks/Example Site.webloc"
        )

        let labelID = UUID()
        let dismissedLabelID = UUID()
        let entry = BookmarkFileService.BookmarkSidecarEntry(
            id: bookmark.id,
            title: "Custom Example Title",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "Saved notes",
            tags: ["swift", "storage"],
            labelIDs: [labelID],
            dismissedLabelIDs: [dismissedLabelID],
            thumbnailRemoteURLString: "https://example.com/thumb.jpg",
            thumbnailFilename: "thumb.jpg",
            originalImageFilename: "original.jpg",
            metadataUpdatedAt: Date(timeIntervalSince1970: 2_500),
            aiSummary: "AI summary",
            ocrText: "OCR",
            dominantColors: ["#000000"],
            mediaType: .image,
            carouselImageFilenames: ["one.jpg", "two.jpg"],
            readerUnavailable: true,
            preferredHeroMode: "reader"
        )

        let changed = VaultBookmarkService.mergeLegacySidecarEntry(
            entry,
            into: &bookmark,
            fallbackFilename: "Example Site.webloc"
        )

        #expect(changed)
        #expect(bookmark.title == "Custom Example Title")
        #expect(bookmark.titleManuallySet == true)
        #expect(bookmark.notes == "Saved notes")
        #expect(bookmark.notesManuallySet == true)
        #expect(bookmark.tags == ["swift", "storage"])
        #expect(bookmark.labelIDs == [labelID])
        #expect(bookmark.dismissedLabelIDs == [dismissedLabelID])
        #expect(bookmark.thumbnailRemoteURLString == "https://example.com/thumb.jpg")
        #expect(bookmark.thumbnailRelativePath == ".thumbnails/thumb.jpg")
        #expect(bookmark.originalImageRelativePath == ".originals/original.jpg")
        #expect(bookmark.aiSummary == "AI summary")
        #expect(bookmark.ocrText == "OCR")
        #expect(bookmark.dominantColors == ["#000000"])
        #expect(bookmark.mediaType == .image)
        #expect(bookmark.carouselImagePaths == [".originals/one.jpg", ".originals/two.jpg"])
        #expect(bookmark.readerUnavailable == true)
        #expect(bookmark.preferredHeroMode == "reader")
        #expect(bookmark.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(bookmark.updatedAt == Date(timeIntervalSince1970: 3_000))
    }

    @Test("Legacy bookmark sidecar metadata does not overwrite populated SQLite fields")
    func mergeLegacySidecarPreservesExistingFields() {
        let labelID = UUID()
        var bookmark = Bookmark(
            title: "Already Curated",
            urlString: "https://example.com",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 4_000),
            notes: "Current notes",
            tags: ["existing"],
            labelIDs: [labelID],
            thumbnailRemoteURLString: "https://example.com/current-thumb.jpg",
            thumbnailRelativePath: ".thumbnails/current-thumb.jpg",
            aiSummary: "Current summary",
            relativePath: "Inbox/Bookmarks/Already Curated.webloc",
            titleManuallySet: true,
            notesManuallySet: true
        )

        let entry = BookmarkFileService.BookmarkSidecarEntry(
            id: bookmark.id,
            title: "Old Sidecar Title",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "Old notes",
            tags: ["old"],
            labelIDs: [UUID()],
            dismissedLabelIDs: [],
            thumbnailRemoteURLString: "https://example.com/old-thumb.jpg",
            thumbnailFilename: "old-thumb.jpg",
            originalImageFilename: nil,
            metadataUpdatedAt: nil,
            aiSummary: "Old summary",
            ocrText: nil,
            dominantColors: nil,
            mediaType: nil,
            carouselImageFilenames: nil,
            readerUnavailable: nil,
            preferredHeroMode: nil
        )

        let changed = VaultBookmarkService.mergeLegacySidecarEntry(
            entry,
            into: &bookmark,
            fallbackFilename: "Already Curated.webloc"
        )

        #expect(changed)
        #expect(bookmark.title == "Already Curated")
        #expect(bookmark.notes == "Current notes")
        #expect(bookmark.tags == ["existing"])
        #expect(bookmark.labelIDs == [labelID])
        #expect(bookmark.thumbnailRemoteURLString == "https://example.com/current-thumb.jpg")
        #expect(bookmark.thumbnailRelativePath == ".thumbnails/current-thumb.jpg")
        #expect(bookmark.aiSummary == "Current summary")
        #expect(bookmark.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(bookmark.updatedAt == Date(timeIntervalSince1970: 4_000))
    }

    @Test("Bookmark file reads ignore legacy sidecars unless explicitly requested")
    func bookmarkFileReadsRequireExplicitLegacySidecarOptIn() throws {
        let fm = FileManager.default
        let dirURL = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-sidecar-opt-in-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dirURL) }

        try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fileService = BookmarkFileService.shared
        let bookmark = Bookmark(
            title: "Filename Title",
            urlString: "https://example.com/path",
            relativePath: "Filename Title.webloc"
        )

        let relativePath = try fileService.write(
            bookmark: bookmark,
            toDirectory: dirURL,
            dirRelativePath: "Inbox/Bookmarks"
        )
        let filename = (relativePath as NSString).lastPathComponent

        fileService.updateSidecar(
            at: dirURL,
            setting: filename,
            to: BookmarkFileService.BookmarkSidecarEntry(
                id: bookmark.id,
                title: "Legacy Sidecar Title",
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000),
                notes: "Legacy notes",
                tags: ["legacy"],
                labelIDs: [],
                dismissedLabelIDs: [],
                thumbnailRemoteURLString: nil,
                thumbnailFilename: nil,
                originalImageFilename: nil,
                metadataUpdatedAt: nil,
                aiSummary: nil,
                ocrText: nil,
                dominantColors: nil,
                mediaType: nil,
                carouselImageFilenames: nil,
                readerUnavailable: nil,
                preferredHeroMode: nil
            )
        )

        let defaultRead = try #require(
            fileService.read(
                filename: filename,
                from: dirURL,
                dirRelativePath: "Inbox/Bookmarks"
            )
        )
        #expect(defaultRead.title == "Filename Title")
        #expect(defaultRead.notes.isEmpty)
        #expect(defaultRead.tags.isEmpty)

        let optedInRead = try #require(
            fileService.read(
                filename: filename,
                from: dirURL,
                dirRelativePath: "Inbox/Bookmarks",
                includeLegacySidecarMetadata: true
            )
        )
        #expect(optedInRead.title == "Legacy Sidecar Title")
        #expect(optedInRead.notes == "Legacy notes")
        #expect(optedInRead.tags == ["legacy"])
    }

    // MARK: - Sync Duplicate Prevention

    @Test("Synced bookmark with canonical duplicate URL merges instead of creating a second active bookmark")
    func addFromSyncMergesCanonicalDuplicateURL() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-sync-duplicate-bookmark-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(at: vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true), withIntermediateDirectories: true)

        let existingID = UUID()
        let existing = Bookmark(
            id: existingID,
            title: "Stonewards on Steam",
            urlString: "https://store.steampowered.com/app/4502710/Stonewards/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            tags: ["gaming"],
            thumbnailRemoteURLString: nil,
            thumbnailRelativePath: ".thumbnails/existing.png",
            relativePath: "Media/Games/Stonewards on Steam.webloc"
        )

        let service = makeService(db)
        service.persistBookmarkToDatabase(db, bookmark: existing)
        service.loadBookmarksFromDatabase(db)

        service.addFromSync(
            id: UUID(),
            title: "Store.Steampowered.Com (2)",
            urlString: "https://www.store.steampowered.com/app/4502710/Stonewards/?utm_source=cider#screenshots",
            notes: "",
            tags: ["shopping", "gaming"],
            thumbnailRemoteURLString: "https://cdn.example.test/stonewards.jpg",
            aiSummary: "Remote duplicate metadata",
            dominantColors: ["#AAFFFF"],
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 4_000),
            folderID: nil
        )

        #expect(service.bookmarks.count == 1)
        let merged = try #require(service.bookmarks.first)
        #expect(merged.id == existingID)
        #expect(merged.title == "Stonewards on Steam")
        #expect(merged.urlString == "https://store.steampowered.com/app/4502710/Stonewards/")
        #expect(Set(merged.tags) == Set(["gaming", "shopping"]))
        #expect(merged.thumbnailRemoteURLString == "https://cdn.example.test/stonewards.jpg")
        #expect(merged.aiSummary == "Remote duplicate metadata")
        #expect(merged.updatedAt == Date(timeIntervalSince1970: 4_000))

        let service2 = makeService(db)
        service2.loadBookmarksFromDatabase(db)
        #expect(service2.bookmarks.count == 1)
        #expect(service2.bookmarks.first?.id == existingID)
    }

    @Test("Orphan adoption deletes exact duplicate .webloc whose URL is already tracked")
    func orphanAdoptionDeletesCanonicalDuplicateURLArtifact() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-orphan-duplicate-bookmark-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let existing = Bookmark(
            title: "Stonewards on Steam",
            urlString: "https://store.steampowered.com/app/4502710/Stonewards/",
            tags: ["gaming"],
            relativePath: "Inbox/Bookmarks/Stonewards on Steam.webloc"
        )
        let service = makeService(db)
        service.persistBookmarkToDatabase(db, bookmark: existing)

        _ = try BookmarkFileService.shared.write(
            bookmark: existing,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        _ = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Store.Steampowered.Com (2)",
                urlString: "https://www.store.steampowered.com/app/4502710/Stonewards/?utm_source=cider#screenshots"
            ),
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )

        service.loadBookmarksFromDatabase(db)
        service.adoptOrphanedVaultFiles()

        #expect(service.bookmarks.count == 1)
        #expect(service.bookmarks.first?.id == existing.id)
        #expect(service.bookmarks.first?.relativePath == "Inbox/Bookmarks/Stonewards on Steam.webloc")
        #expect(fm.fileExists(atPath: inbox.appendingPathComponent("Stonewards on Steam.webloc").path))
        #expect(!fm.fileExists(atPath: inbox.appendingPathComponent("Store.Steampowered.Com (2).webloc").path))

        let itemStmt = try db.prepare("SELECT COUNT(*) FROM items WHERE type = 'bookmark';")
        try itemStmt.step()
        #expect(itemStmt.int(at: 0) == 1)

        let bookmarkStmt = try db.prepare("SELECT COUNT(*) FROM bookmarks;")
        try bookmarkStmt.step()
        #expect(bookmarkStmt.int(at: 0) == 1)
    }

    @Test("Orphan .webloc adoption preserves filesystem creation date")
    func orphanWeblocAdoptionPreservesFilesystemCreationDate() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-orphan-bookmark-date-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let fileDate = Date(timeIntervalSince1970: 1_701_000_000)
        let bookmark = Bookmark(title: "Plex", urlString: "https://www.plex.tv/")
        let relativePath = try BookmarkFileService.shared.write(
            bookmark: bookmark,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        try setFilesystemDates(for: vault.appendingPathComponent(relativePath), createdAt: fileDate)

        let service = makeService(db)
        service.loadBookmarksFromDatabase(db)
        service.adoptOrphanedVaultFiles()

        let adopted = try #require(service.bookmarks.first)
        let adoptedDates = try storedItemDates(db, id: adopted.id)
        #expect(adopted.title == "Plex")
        #expect(abs(adopted.createdAt.timeIntervalSince(fileDate)) < 0.01)
        #expect(abs(adoptedDates.createdAt.timeIntervalSince(fileDate)) < 0.01)
    }

    @Test("Duplicate .webloc adoption keeps canonical row and deletes duplicate file")
    func duplicateWeblocAdoptionKeepsCanonicalRowAndDeletesDuplicateFile() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-duplicate-bookmark-date-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let existing = Bookmark(
            title: "Fatty Fish Sushi Everett review",
            urlString: "https://www.tiktok.com/t/ZP8pPEsky/",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            relativePath: "Inbox/Bookmarks/Fatty Fish Sushi Everett review.webloc"
        )
        let service = makeService(db)
        service.persistBookmarkToDatabase(db, bookmark: existing)

        _ = try BookmarkFileService.shared.write(
            bookmark: existing,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        let duplicateRelativePath = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Tiktok.Com (2)",
                urlString: "https://www.tiktok.com/t/ZP8pPEsky/?utm_source=ios#caption"
            ),
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )

        service.loadBookmarksFromDatabase(db)
        service.adoptOrphanedVaultFiles()

        #expect(service.bookmarks.count == 1)
        let canonical = try #require(service.bookmarks.first)
        #expect(canonical.id == existing.id)
        #expect(canonical.relativePath == "Inbox/Bookmarks/Fatty Fish Sushi Everett review.webloc")
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent(duplicateRelativePath).path))

        let itemStmt = try db.prepare("SELECT COUNT(*) FROM items WHERE type = 'bookmark';")
        try itemStmt.step()
        #expect(itemStmt.int(at: 0) == 1)
    }

    @Test("SQLite load repairs adoption-created bookmark date from older .webloc date")
    func sqliteLoadRepairsAdoptionCreatedBookmarkDateFromFilesystem() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-date-repair-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let fileDate = Date(timeIntervalSince1970: 1_690_000_000)
        let corruptedScanDate = Date(timeIntervalSince1970: 1_770_000_000)
        let relativePath = try BookmarkFileService.shared.write(
            bookmark: Bookmark(title: "Plex", urlString: "https://www.plex.tv/"),
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        try setFilesystemDates(for: vault.appendingPathComponent(relativePath), createdAt: fileDate)

        let corrupted = Bookmark(
            title: "Plex",
            urlString: "https://www.plex.tv/",
            createdAt: corruptedScanDate,
            updatedAt: corruptedScanDate,
            relativePath: relativePath
        )
        let service = makeService(db)
        service.persistBookmarkToDatabase(db, bookmark: corrupted)

        let nonBookmarkID = UUID()
        let nonBookmarkRelativePath = "Inbox/Bookmarks/Plex note.webloc"
        let nonBookmarkFileURL = vault.appendingPathComponent(nonBookmarkRelativePath)
        let plist = ["URL": "https://www.plex.tv/note"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: nonBookmarkFileURL, options: .atomic)
        try setFilesystemDates(for: nonBookmarkFileURL, createdAt: fileDate.addingTimeInterval(-86_400))
        try db.withTransaction {
            let stmt = try db.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
                VALUES (?, 'note', 'Plex note', ?, ?, ?);
                """)
            stmt.bind(DatabaseHelpers.encode(nonBookmarkID), at: 1)
                .bind(DatabaseHelpers.encode(corruptedScanDate), at: 2)
                .bind(DatabaseHelpers.encode(corruptedScanDate), at: 3)
                .bind(nonBookmarkRelativePath, at: 4)
            try stmt.step()
        }

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)

        let repaired = try #require(reloaded.bookmarks.first)
        let repairedDates = try storedItemDates(db, id: corrupted.id)
        let nonBookmarkDates = try storedItemDates(db, id: nonBookmarkID)
        #expect(abs(repaired.createdAt.timeIntervalSince(fileDate)) < 0.01)
        #expect(abs(repairedDates.createdAt.timeIntervalSince(fileDate)) < 0.01)
        #expect(abs(nonBookmarkDates.createdAt.timeIntervalSince(corruptedScanDate)) < 0.01)
    }

    @Test("Date Added sort uses repaired Plex and Fatty Fish capture dates")
    func dateAddedSortUsesRepairedBookmarkFilesystemDates() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-sort-date-repair-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let corruptedScanDate = Date(timeIntervalSince1970: 1_770_000_000)
        let plexDate = Date(timeIntervalSince1970: 1_690_000_000)
        let fattyFishDate = Date(timeIntervalSince1970: 1_720_000_000)

        let plexPath = try BookmarkFileService.shared.write(
            bookmark: Bookmark(title: "Plex", urlString: "https://www.plex.tv/"),
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        try setFilesystemDates(for: vault.appendingPathComponent(plexPath), createdAt: plexDate)
        let fattyFishPath = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Fatty Fish Sushi Everett review - CiderGuyRatesIt",
                urlString: "https://www.tiktok.com/t/ZP8pPEsky/"
            ),
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        try setFilesystemDates(for: vault.appendingPathComponent(fattyFishPath), createdAt: fattyFishDate)

        let service = makeService(db)
        service.persistBookmarkToDatabase(db, bookmark: Bookmark(
            title: "Plex",
            urlString: "https://www.plex.tv/",
            createdAt: corruptedScanDate.addingTimeInterval(1),
            updatedAt: corruptedScanDate.addingTimeInterval(1),
            relativePath: plexPath
        ))
        service.persistBookmarkToDatabase(db, bookmark: Bookmark(
            title: "Fatty Fish Sushi Everett review - CiderGuyRatesIt",
            urlString: "https://www.tiktok.com/t/ZP8pPEsky/",
            createdAt: corruptedScanDate,
            updatedAt: corruptedScanDate,
            relativePath: fattyFishPath
        ))

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)
        let sortedTitles = reloaded.bookmarks
            .map(LibraryItemV2.bookmark)
            .sorted { $0.createdDate > $1.createdDate }
            .map(\.title)

        #expect(sortedTitles == [
            "Fatty Fish Sushi Everett review - CiderGuyRatesIt",
            "Plex",
        ])
    }

    @Test("SQLite load collapses canonical duplicate URL rows into one displayed bookmark")
    func sqliteLoadCollapsesCanonicalDuplicateURLRows() throws {
        let (db, url) = try makeTestDB()
        defer {
            db.close()
            cleanup(url)
        }

        let canonicalID = UUID()
        let staleID = UUID()
        let service = makeService(db)

        let canonical = Bookmark(
            id: canonicalID,
            title: "Fatty Fish Sushi Everett review — CiderGuyRatesIt",
            urlString: "https://www.tiktok.com/t/ZP8pPEsky/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            notes: "",
            tags: ["restaurants"],
            relativePath: "Food/Restaurants/Everett/Fatty Fish Sushi Everett review — CiderGuyRatesIt.webloc"
        )
        let stale = Bookmark(
            id: staleID,
            title: "Tiktok.Com (2)",
            urlString: "https://www.tiktok.com/t/ZP8pPEsky/?utm_source=ios#caption",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "Useful TikTok caption from the stale representation.",
            tags: ["tiktok"],
            relativePath: "Food/Restaurants/Everett/Tiktok.Com (2).webloc"
        )

        service.persistBookmarkToDatabase(db, bookmark: canonical)
        service.persistBookmarkToDatabase(db, bookmark: stale)

        let displayService = makeService(db)
        displayService.loadBookmarksFromDatabase(db)

        #expect(displayService.bookmarks.count == 1)
        let displayed = try #require(displayService.bookmarks.first)
        #expect(displayed.id == canonicalID)
        #expect(displayed.title == "Fatty Fish Sushi Everett review — CiderGuyRatesIt")
        #expect(displayed.urlString == "https://www.tiktok.com/t/ZP8pPEsky/")
        #expect(displayed.notes == "Useful TikTok caption from the stale representation.")
        #expect(Set(displayed.tags) == Set(["restaurants", "tiktok"]))
        #expect(displayed.relativePath == "Food/Restaurants/Everett/Fatty Fish Sushi Everett review — CiderGuyRatesIt.webloc")

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)
        #expect(reloaded.bookmarks.count == 1)
        #expect(reloaded.bookmarks.first?.id == canonicalID)
    }

    @Test("SQLite load removes duplicate URL .webloc artifact after row repair")
    func sqliteLoadRemovesDuplicateURLWeblocArtifactAfterRowRepair() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-duplicate-repair-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let canonicalID = UUID()
        let duplicateID = UUID()
        let service = makeService(db)
        let canonical = Bookmark(
            id: canonicalID,
            title: "Wyldheart co-op RPG for busy schedules — Furo",
            urlString: "https://www.tiktok.com/t/ZP8pShRv1/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: "Inbox/Bookmarks/Wyldheart co-op RPG for busy schedules — Furo.webloc"
        )
        let duplicate = Bookmark(
            id: duplicateID,
            title: "Wyldheart co-op RPG for busy schedules — Furo",
            urlString: "https://www.tiktok.com/t/ZP8pShRv1/",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Bookmarks/Wyldheart co-op RPG for busy schedules — Furo (2).webloc"
        )

        service.persistBookmarkToDatabase(db, bookmark: canonical)
        service.persistBookmarkToDatabase(db, bookmark: duplicate)
        _ = try BookmarkFileService.shared.write(
            bookmark: canonical,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        _ = try BookmarkFileService.shared.write(
            bookmark: duplicate,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)

        #expect(reloaded.bookmarks.count == 1)
        #expect(reloaded.bookmarks.first?.id == canonicalID)
        #expect(fm.fileExists(atPath: inbox.appendingPathComponent("Wyldheart co-op RPG for busy schedules — Furo.webloc").path))
        #expect(!fm.fileExists(atPath: inbox.appendingPathComponent("Wyldheart co-op RPG for busy schedules — Furo (2).webloc").path))

        let itemStmt = try db.prepare("SELECT COUNT(*) FROM items WHERE type = 'bookmark';")
        try itemStmt.step()
        #expect(itemStmt.int(at: 0) == 1)
    }

    @Test("SQLite duplicate URL repair keeps clean artifact path even when suffix row is richer")
    func sqliteDuplicateURLRepairKeepsCleanArtifactPathWhenSuffixRowIsRicher() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-rich-duplicate-repair-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let canonicalID = UUID()
        let duplicateID = UUID()
        let service = makeService(db)
        let canonical = Bookmark(
            id: canonicalID,
            title: "Thick As Thieves co-op Steam game — GROMO",
            urlString: "https://www.tiktok.com/t/ZP8pBDjbU/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: "Inbox/Bookmarks/Thick As Thieves co-op Steam game — GROMO.webloc"
        )
        var duplicate = Bookmark(
            id: duplicateID,
            title: "Thick As Thieves co-op Steam game — GROMO",
            urlString: "https://www.tiktok.com/t/ZP8pBDjbU/",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Bookmarks/Thick As Thieves co-op Steam game — GROMO (2).webloc",
            titleManuallySet: true
        )
        duplicate.notes = "Richer duplicate metadata should merge into the clean artifact row."
        duplicate.aiSummary = "A co-op game clip."
        duplicate.thumbnailRemoteURLString = "https://example.com/thumb.jpg"

        service.persistBookmarkToDatabase(db, bookmark: canonical)
        service.persistBookmarkToDatabase(db, bookmark: duplicate)
        _ = try BookmarkFileService.shared.write(
            bookmark: canonical,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        _ = try BookmarkFileService.shared.write(
            bookmark: duplicate,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)

        #expect(reloaded.bookmarks.count == 1)
        let repaired = try #require(reloaded.bookmarks.first)
        #expect(repaired.id == canonicalID)
        #expect(repaired.relativePath == "Inbox/Bookmarks/Thick As Thieves co-op Steam game — GROMO.webloc")
        #expect(repaired.notes == duplicate.notes)
        #expect(repaired.aiSummary == duplicate.aiSummary)
        #expect(fm.fileExists(atPath: inbox.appendingPathComponent("Thick As Thieves co-op Steam game — GROMO.webloc").path))
        #expect(!fm.fileExists(atPath: inbox.appendingPathComponent("Thick As Thieves co-op Steam game — GROMO (2).webloc").path))
    }

    @Test("SQLite load renames lone numeric suffix bookmark artifact when clean path is free")
    func sqliteLoadRenamesLoneNumericSuffixBookmarkArtifactWhenCleanPathIsFree() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-lone-suffix-repair-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        let service = makeService(db)
        let bookmarkID = UUID()
        var bookmark = Bookmark(
            id: bookmarkID,
            title: "Wyldheart co-op RPG for busy schedules — Furo",
            urlString: "https://www.tiktok.com/t/ZP8pShRv1/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let cleanRelativePath = try BookmarkFileService.shared.write(
            bookmark: bookmark,
            toDirectory: inbox,
            dirRelativePath: "Inbox/Bookmarks"
        )
        let suffixRelativePath = "Inbox/Bookmarks/Wyldheart co-op RPG for busy schedules — Furo (2).webloc"
        try fm.moveItem(
            at: vault.appendingPathComponent(cleanRelativePath),
            to: vault.appendingPathComponent(suffixRelativePath)
        )
        bookmark.relativePath = suffixRelativePath
        service.persistBookmarkToDatabase(db, bookmark: bookmark)

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)

        #expect(reloaded.bookmarks.count == 1)
        #expect(reloaded.bookmarks.first?.id == bookmarkID)
        #expect(reloaded.bookmarks.first?.relativePath == cleanRelativePath)
        #expect(fm.fileExists(atPath: vault.appendingPathComponent(cleanRelativePath).path))
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent(suffixRelativePath).path))

        let pathStmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        pathStmt.bind(DatabaseHelpers.encode(bookmarkID), at: 1)
        try pathStmt.step()
        #expect(pathStmt.string(at: 0) == cleanRelativePath)
    }

    @Test("Legacy index metadata merges into the SQLite canonical bookmark for the same URL")
    func legacyIndexMetadataMergesIntoSQLiteCanonicalBookmark() throws {
        let (db, url) = try makeTestDB()
        defer {
            db.close()
            cleanup(url)
        }

        let canonicalID = UUID()
        let legacyID = UUID()
        let service = makeService(db)
        let canonical = Bookmark(
            id: canonicalID,
            title: "TikTok - Make Your Day",
            urlString: "https://www.tiktok.com/@heyjosh_13/video/7635788415757258002?is_from_webapp=1&sender_device=pc",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            notes: "",
            tags: [],
            thumbnailRemoteURLString: nil,
            thumbnailRelativePath: ".thumbnails/canonical.png",
            relativePath: "Inbox/Bookmarks/Tiktok.Com (3).webloc"
        )
        let legacyIndexed = Bookmark(
            id: legacyID,
            title: "No Josh's were harmed in the making of this video... Maybe.",
            urlString: "https://www.tiktok.com/@heyjosh_13/video/7635788415757258002?sender_device=pc&is_from_webapp=1",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "No Josh's were harmed in the making of this video... Maybe.\n\nBy HeyJosh_\nVia TikTok",
            tags: ["tiktok"],
            thumbnailRemoteURLString: "https://p16-sign-va.tiktokcdn.com/example.jpeg",
            thumbnailRelativePath: ".thumbnails/legacy.png",
            metadataUpdatedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Bookmarks/No Josh's were harmed.webloc",
            titleManuallySet: true,
            notesManuallySet: true
        )

        service.persistBookmarkToDatabase(db, bookmark: canonical)
        service.loadBookmarksFromDatabase(db)

        #expect(service.mergeLegacyIndexBookmarks([legacyIndexed]) == true)
        #expect(service.bookmarks.count == 1)
        let merged = try #require(service.bookmarks.first)
        #expect(merged.id == canonicalID)
        #expect(merged.title == "No Josh's were harmed in the making of this video... Maybe.")
        #expect(merged.notes == "No Josh's were harmed in the making of this video... Maybe.\n\nBy HeyJosh_\nVia TikTok")
        #expect(Set(merged.tags) == Set(["tiktok"]))
        #expect(merged.thumbnailRelativePath == ".thumbnails/canonical.png")
        #expect(merged.thumbnailRemoteURLString == "https://p16-sign-va.tiktokcdn.com/example.jpeg")
        #expect(merged.relativePath == "Inbox/Bookmarks/Tiktok.Com (3).webloc")

        let reloaded = makeService(db)
        reloaded.loadBookmarksFromDatabase(db)
        #expect(reloaded.bookmarks.count == 1)
        #expect(reloaded.bookmarks.first?.id == canonicalID)
        #expect(reloaded.bookmarks.first?.title == "No Josh's were harmed in the making of this video... Maybe.")
        #expect(reloaded.bookmarks.first?.notes.contains("By HeyJosh_") == true)
    }

    @Test("Legacy index metadata renames generic bookmark artifact after rich title merge")
    func legacyIndexMetadataRenamesGenericArtifactAfterRichTitleMerge() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-bookmark-artifact-rename-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let oldRelativePath = "Inbox/Bookmarks/Tiktok.Com (2).webloc"
        let oldURL = vault.appendingPathComponent(oldRelativePath)
        let plist = ["URL": "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678?is_from_webapp=1"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: oldURL, options: .atomic)

        let canonicalID = UUID()
        let service = makeService(db)
        let canonical = Bookmark(
            id: canonicalID,
            title: "Tiktok.Com (2)",
            urlString: "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678?is_from_webapp=1",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            notes: "",
            tags: [],
            relativePath: oldRelativePath
        )
        let rich = Bookmark(
            id: UUID(),
            title: "This tiny dog has opinions about Mondays",
            urlString: "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678?is_from_webapp=1",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "This tiny dog has opinions about Mondays.\n\nVia TikTok",
            tags: ["tiktok"],
            thumbnailRemoteURLString: "https://p16-sign-va.tiktokcdn.com/dog.jpeg",
            metadataUpdatedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc",
            titleManuallySet: true,
            notesManuallySet: true
        )

        service.persistBookmarkToDatabase(db, bookmark: canonical)
        service.loadBookmarksFromDatabase(db)

        #expect(service.mergeLegacyIndexBookmarks([rich]) == true)

        let merged = try #require(service.bookmarks.first)
        #expect(merged.id == canonicalID)
        #expect(merged.title == "This tiny dog has opinions about Mondays")
        #expect(merged.relativePath == "Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc").path))
        #expect(!fm.fileExists(atPath: oldURL.path))

        let stmt = try db.prepare("""
            SELECT i.relative_path, b.url
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.id = ?;
            """)
        stmt.bind(DatabaseHelpers.encode(canonicalID), at: 1)
        #expect(try stmt.step())
        #expect(stmt.optionalString(at: 0) == "Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc")
        #expect(stmt.string(at: 1) == "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678?is_from_webapp=1")
    }

    @Test("OEmbed title enrichment renames generic bookmark artifact")
    func oEmbedTitleEnrichmentRenamesGenericArtifact() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-oembed-artifact-rename-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let oldRelativePath = "Inbox/Bookmarks/Tiktok.Com.webloc"
        let oldURL = vault.appendingPathComponent(oldRelativePath)
        let sourceURL = "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678"
        let plist = ["URL": sourceURL]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: oldURL, options: .atomic)

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Tiktok.Com",
            urlString: sourceURL,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: oldRelativePath
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmarkID,
            title: "This tiny dog has opinions about Mondays",
            notes: "This tiny dog has opinions about Mondays."
        )

        let updated = try #require(service.bookmarks.first)
        #expect(updated.title == "This tiny dog has opinions about Mondays")
        #expect(updated.relativePath == "Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/This tiny dog has opinions about Mondays.webloc").path))
        #expect(!fm.fileExists(atPath: oldURL.path))
    }

    @Test("Stored TikTok OCR title promotion renames generic bookmark artifact")
    func storedTikTokOCRTitlePromotionRenamesGenericArtifact() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-tiktok-ocr-artifact-rename-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let oldRelativePath = "Inbox/Bookmarks/Tiktok.Com (3).webloc"
        let oldURL = vault.appendingPathComponent(oldRelativePath)
        let sourceURL = "https://www.tiktok.com/t/ZP8poHUSr/"
        let plist = ["URL": sourceURL]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: oldURL, options: .atomic)

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "TikTok - Make Your Day",
            urlString: sourceURL,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            ocrText: "Richmond night market 5/29/26 BAU BOT TITKE",
            relativePath: oldRelativePath
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        let updated = try #require(service.applyStoredOCRTitleCandidateIfNeeded(for: bookmarkID))

        #expect(updated.title == "Richmond Night Market 5/29/26")
        #expect(updated.relativePath == "Inbox/Bookmarks/Richmond Night Market 5-29-26.webloc")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/Richmond Night Market 5-29-26.webloc").path))
        #expect(!fm.fileExists(atPath: oldURL.path))
    }

    @Test("OEmbed title enrichment replaces TikTok provider generic title")
    func oEmbedTitleEnrichmentReplacesTikTokProviderGenericTitle() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-tiktok-oembed-provider-generic-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let oldRelativePath = "Inbox/Bookmarks/Tiktok.Com (3).webloc"
        let oldURL = vault.appendingPathComponent(oldRelativePath)
        let sourceURL = "https://www.tiktok.com/t/ZP8s1eSw4/"
        let plist = ["URL": sourceURL]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: oldURL, options: .atomic)

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "TikTok - Make Your Day",
            urlString: sourceURL,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: oldRelativePath
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmarkID,
            title: "this viral smores bark is about to be your annual summer little treat after dinner",
            notes: "this viral smores bark is about to be your annual summer little treat after dinner\nBy ashleymarkletreats\nVia TikTok"
        )

        let updated = try #require(service.bookmarks.first)
        #expect(updated.title == "this viral smores bark is about to be your annual summer little treat after dinner")
        #expect(updated.relativePath == "Inbox/Bookmarks/this viral smores bark is about to be your annual summer little treat after dinner.webloc")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/this viral smores bark is about to be your annual summer little treat after dinner.webloc").path))
        #expect(!fm.fileExists(atPath: oldURL.path))
    }

    @Test("Stored TikTok notes title promotion renames generic bookmark artifact")
    func storedTikTokNotesTitlePromotionRenamesGenericArtifact() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-tiktok-notes-artifact-rename-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inbox = vault.appendingPathComponent("Inbox/Bookmarks", isDirectory: true)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let oldRelativePath = "Inbox/Bookmarks/Tiktok.Com (3).webloc"
        let oldURL = vault.appendingPathComponent(oldRelativePath)
        let sourceURL = "https://www.tiktok.com/t/ZP8s1eSw4/"
        let plist = ["URL": sourceURL]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: oldURL, options: .atomic)

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "TikTok - Make Your Day",
            urlString: sourceURL,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            notes: "this viral smores bark is about to be your annual summer little treat after dinner\nBy ashleymarkletreats\nVia TikTok",
            relativePath: oldRelativePath
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        let updated = try #require(service.applyStoredSemanticTitleCandidateIfNeeded(for: bookmarkID))

        #expect(updated.title == "Viral Smores Bark")
        #expect(updated.relativePath == "Inbox/Bookmarks/Viral Smores Bark.webloc")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/Viral Smores Bark.webloc").path))
        #expect(!fm.fileExists(atPath: oldURL.path))
    }

    @Test("OEmbed title enrichment can replace provider-generic manual title")
    func oEmbedTitleEnrichmentReplacesProviderGenericManualTitle() throws {
        let (db, url) = try makeTestDB()
        defer {
            db.close()
            cleanup(url)
        }

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "X.Com",
            urlString: "https://x.com/someone/status/123",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            titleManuallySet: true
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmarkID,
            title: "Someone on X: Actual post title",
            notes: nil
        )

        let updated = try #require(service.bookmarks.first)
        #expect(updated.title == "Someone on X: Actual post title")
        #expect(updated.titleManuallySet == true)
    }

    @Test("OEmbed title enrichment can replace Reddit host-derived manual title")
    func oEmbedTitleEnrichmentReplacesRedditHostDerivedManualTitle() throws {
        let (db, url) = try makeTestDB()
        defer {
            db.close()
            cleanup(url)
        }

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Reddit.Com (15)",
            urlString: "https://www.reddit.com/r/wow/comments/1rw8g15/gandalins_gearing_guide_midnight_season_1/",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            titleManuallySet: true
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmarkID,
            title: "Gandalin's Gearing Guide: Midnight Season 1",
            notes: nil
        )

        let updated = try #require(service.bookmarks.first)
        #expect(updated.title == "Gandalin's Gearing Guide: Midnight Season 1")
        #expect(updated.titleManuallySet == true)
    }

    @Test("OEmbed title enrichment preserves curated bookmark artifact path")
    func oEmbedTitleEnrichmentPreservesCuratedArtifactPath() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-oembed-curated-artifact-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let folder = vault.appendingPathComponent("Projects/Dogs", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let curatedRelativePath = "Projects/Dogs/Tiny dog research.webloc"
        let curatedURL = vault.appendingPathComponent(curatedRelativePath)
        let sourceURL = "https://www.tiktok.com/@petalbnesnp/video/7624097886959291678"
        let plist = ["URL": sourceURL]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: curatedURL, options: .atomic)

        let bookmarkID = UUID()
        let service = makeService(db)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Tiktok.Com",
            urlString: sourceURL,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: curatedRelativePath
        )
        service.persistBookmarkToDatabase(db, bookmark: bookmark)
        service.loadBookmarksFromDatabase(db)

        service.applyOEmbedResults(
            for: bookmarkID,
            title: "This tiny dog has opinions about Mondays",
            notes: nil
        )

        let updated = try #require(service.bookmarks.first)
        #expect(updated.title == "This tiny dog has opinions about Mondays")
        #expect(updated.relativePath == curatedRelativePath)
        #expect(fm.fileExists(atPath: curatedURL.path))
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent("Projects/Dogs/This tiny dog has opinions about Mondays.webloc").path))
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
