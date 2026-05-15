import Foundation
import Testing
@testable import Cider

@Suite("Cider Capture Service Tests")
@MainActor
struct CiderCaptureServiceTests {
    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-test-\(UUID().uuidString)", isDirectory: true)
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

    private func withIsolatedVault<T>(_ body: (CiderDatabase, VaultBookmarkService) throws -> T) throws -> T {
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
        let bookmarks = VaultBookmarkService(database: db, schedulesEnrichment: false)
        return try body(db, bookmarks)
    }

    @Test("capture add stores a URL in Inbox immediately and returns agent state")
    func captureAddStoresURLImmediately() throws {
        try withIsolatedVault { db, bookmarks in
            let service = CiderCaptureService(bookmarkService: bookmarks)

            let result = try service.add("https://example.com/articles/42?utm_source=test")

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "url")
            #expect(result.source.url == "https://example.com/articles/42?utm_source=test")
            #expect(result.source.itemID == result.item.id)
            #expect(result.source.itemType == "bookmark")
            #expect(result.item.type == "bookmark")
            #expect(result.item.title == "Example.Com")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Bookmarks/") == true)
            #expect(result.enrichment.status == "pending")
            #expect(result.duplicate.status == "new")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Bookmarks")
            #expect(result.nextSafeAction == "enrich")

            let stored = bookmarks.bookmarks.first(where: { $0.id == result.item.id })
            #expect(stored?.urlString == "https://example.com/articles/42?utm_source=test")

            let itemStatement = try db.prepare("SELECT type, title, relative_path FROM items WHERE id = ?;")
            itemStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try itemStatement.step())
            #expect(itemStatement.string(at: 0) == "bookmark")
            #expect(itemStatement.string(at: 1) == "Example.Com")
            #expect(itemStatement.string(at: 2).hasPrefix("Inbox/Bookmarks/"))

            let bookmarkStatement = try db.prepare("SELECT url FROM bookmarks WHERE item_id = ?;")
            bookmarkStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try bookmarkStatement.step())
            #expect(bookmarkStatement.string(at: 0) == "https://example.com/articles/42?utm_source=test")
        }
    }

    @Test("capture add returns duplicate state for an existing URL")
    func captureAddReportsDuplicate() throws {
        try withIsolatedVault { _, bookmarks in
            let service = CiderCaptureService(bookmarkService: bookmarks)

            let first = try service.add("https://example.com/duplicate")
            let second = try service.add("https://example.com/duplicate")

            #expect(bookmarks.bookmarks.count == 1)
            #expect(second.item.id == first.item.id)
            #expect(second.duplicate.status == "duplicate")
            #expect(second.duplicate.existingItemID == first.item.id)
            #expect(second.routing.reviewNeeded == true)
            #expect(second.nextSafeAction == "inspect_existing_item")
        }
    }
}
