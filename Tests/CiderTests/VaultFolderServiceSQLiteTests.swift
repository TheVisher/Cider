import Foundation
import Testing
@testable import Cider

@Suite("VaultFolderService SQLite Tests")
@MainActor
struct VaultFolderServiceSQLiteTests {

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-folder-test-\(UUID().uuidString).db"
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

    // MARK: - Round-Trip

    @Test("Folders round-trip through SQLite: persist, load, verify")
    func foldersRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = VaultFolderService(database: db)

        // Persist two folders directly via database methods
        let folder1 = VaultFolder(relativePath: "Work")
        let folder2 = VaultFolder(relativePath: "Work/Projects")
        service.persistToDatabase(db, folder: folder1)
        service.persistToDatabase(db, folder: folder2)

        // Create a fresh service that loads from the same DB
        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.count == 2)

        // Verify data integrity
        let loaded1 = service2.folders.first { $0.id == folder1.id }
        #expect(loaded1 != nil)
        #expect(loaded1?.relativePath == "Work")
        #expect(loaded1?.name == "Work")

        let loaded2 = service2.folders.first { $0.id == folder2.id }
        #expect(loaded2 != nil)
        #expect(loaded2?.relativePath == "Work/Projects")
        #expect(loaded2?.name == "Projects")
    }

    @Test("Folder with all metadata fields survives round-trip")
    func fullMetadataRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(
            relativePath: "Photos/Vacation",
            icon: "🏖️",
            coverImagePath: ".cider/folders/covers/test.jpg",
            coverImageOffsetY: 0.35
        )

        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)

        let service2 = VaultFolderService(database: db)
        let loaded = service2.folders.first { $0.id == folder.id }
        #expect(loaded != nil)
        #expect(loaded?.icon == "🏖️")
        #expect(loaded?.coverImagePath == ".cider/folders/covers/test.jpg")
        #expect(loaded?.coverImageOffsetY == 0.35)
    }

    @Test("Folder with nil optional fields round-trips correctly")
    func nilOptionalFieldsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Plain")
        // icon, coverImagePath, coverImageOffsetY are all nil

        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)

        let service2 = VaultFolderService(database: db)
        let loaded = service2.folders.first { $0.id == folder.id }
        #expect(loaded != nil)
        #expect(loaded?.icon == nil)
        #expect(loaded?.coverImagePath == nil)
        #expect(loaded?.coverImageOffsetY == nil)
    }

    @Test("Delete folder removes from SQLite")
    func deleteFolderRemoves() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Temporary")
        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)

        // Verify it was persisted
        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.count == 1)

        // Delete directly via the database method
        service2.deleteFromDatabase(db, folderID: folder.id)

        // Reload and verify deletion
        let service3 = VaultFolderService(database: db)
        #expect(service3.folders.isEmpty)
    }

    @Test("UPSERT updates existing folder")
    func upsertUpdatesExistingFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        var folder = VaultFolder(relativePath: "Original")
        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)

        // Update the folder and re-persist with same ID
        folder.relativePath = "Renamed"
        folder.icon = "📁"
        folder.updatedAt = Date()
        service.persistToDatabase(db, folder: folder)

        // Reload and verify update (not duplicate)
        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.count == 1)
        let loaded = service2.folders.first
        #expect(loaded?.relativePath == "Renamed")
        #expect(loaded?.icon == "📁")
    }

    @Test("Folders load sorted by relative_path (case-insensitive)")
    func foldersSortedByPath() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: VaultFolder(relativePath: "Zebra"))
        service.persistToDatabase(db, folder: VaultFolder(relativePath: "alpha"))
        service.persistToDatabase(db, folder: VaultFolder(relativePath: "Beta"))

        // Reload and check order
        let service2 = VaultFolderService(database: db)
        let paths = service2.folders.map(\.relativePath)
        #expect(paths == ["alpha", "Beta", "Zebra"])
    }

    @Test("Date fields survive round-trip with reasonable precision")
    func dateFieldsPrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let before = Date()
        let folder = VaultFolder(relativePath: "Timed")
        let after = Date()

        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)

        let service2 = VaultFolderService(database: db)
        let loaded = service2.folders.first { $0.id == folder.id }
        #expect(loaded != nil)

        // createdAt should be between before and after
        #expect(loaded!.createdAt.timeIntervalSince(before) >= -0.01)
        #expect(loaded!.createdAt.timeIntervalSince(after) <= 0.01)
    }

    @Test("Sync add for existing folder path reuses folder instead of creating numeric suffix")
    func addFolderFromSyncReusesExistingRelativePath() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-sync-duplicate-folder-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)

        let existingID = UUID()
        let existing = VaultFolder(
            id: existingID,
            relativePath: "Media",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            icon: nil
        )
        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: existing)
        let loadedService = VaultFolderService(database: db)

        let returned = try #require(loadedService.addFolderFromSync(
            id: UUID(),
            name: "Media",
            icon: "🎬",
            parentID: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        ))

        #expect(returned.id == existingID)
        #expect(returned.relativePath == "Media")
        #expect(loadedService.folders.count == 1)
        #expect(loadedService.folders.first?.relativePath == "Media")
        #expect(loadedService.folders.first?.icon == "🎬")
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent("Media 2").path))

        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.count == 1)
        #expect(service2.folders.first?.id == existingID)
        #expect(service2.folders.first?.relativePath == "Media")
    }

    @Test("Empty database loads empty folders array")
    func emptyDatabaseLoadsEmpty() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = VaultFolderService(database: db)
        #expect(service.folders.isEmpty)
    }

    @Test("Multiple folders with parent-child paths load correctly")
    func parentChildPathsLoad() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let parent = VaultFolder(relativePath: "Work")
        let child = VaultFolder(relativePath: "Work/Projects")
        let grandchild = VaultFolder(relativePath: "Work/Projects/Alpha")

        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: parent)
        service.persistToDatabase(db, folder: child)
        service.persistToDatabase(db, folder: grandchild)

        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.count == 3)

        // Verify parent-child derived properties
        let loadedChild = service2.folders.first { $0.id == child.id }
        #expect(loadedChild?.parentRelativePath == "Work")
        #expect(loadedChild?.name == "Projects")
    }
}
