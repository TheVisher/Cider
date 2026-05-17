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

    @Test("Folder metadata mutations record audit entries")
    func folderMetadataMutationsRecordAuditEntries() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-audit-\(UUID().uuidString)", isDirectory: true)
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

        let folder = VaultFolder(relativePath: "Audited")
        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: folder)
        let loadedService = VaultFolderService(database: db)

        #expect(loadedService.setIcon("sparkles", for: folder.id) == true)
        #expect(loadedService.setCoverImageOffsetY(0.25, for: folder.id) == true)

        let entries = MutationAuditService(database: db).loadEntries()
        let icon = entries.first { $0.itemID == folder.id && $0.action == "set_icon" }
        let coverOffset = entries.first { $0.itemID == folder.id && $0.action == "set_cover_offset" }

        #expect(icon?.itemType == "vaultFolder")
        #expect(icon?.beforeState["icon"] == nil)
        #expect(icon?.afterState["icon"] == "sparkles")

        #expect(coverOffset?.itemType == "vaultFolder")
        #expect(coverOffset?.beforeState["coverImageOffsetY"] == nil)
        #expect(coverOffset?.afterState["coverImageOffsetY"] == "0.25")
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

    @Test("Folder write gate creates folder and records provenance")
    func folderWriteGateCreatesFolderAndRecordsProvenance() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-write-gate-\(UUID().uuidString)", isDirectory: true)
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

        let service = VaultFolderService(database: db)
        let decision = service.applyFolderWrite(.init(
            name: "Projects",
            source: .agent,
            duplicatePolicy: .makeUniqueName
        ))

        guard case .created(let folder) = decision else {
            Issue.record("Expected write gate to create folder, got \(decision)")
            return
        }

        #expect(folder.relativePath == "Projects")
        #expect(service.folders.map(\.relativePath) == ["Projects"])
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Projects").path))

        let reloaded = VaultFolderService(database: db)
        #expect(reloaded.folders.map(\.relativePath) == ["Projects"])

        let audit = MutationAuditService(database: db).loadEntries()
        let entry = try #require(audit.first { $0.itemID == folder.id && $0.action == "folder.write.create" })
        #expect(entry.source == .agent)
        #expect(entry.metadata["origin"] == "applyFolderWrite")
        #expect(entry.metadata["source"] == "agent")
        #expect(entry.metadata["duplicatePolicy"] == "makeUniqueName")
    }

    @Test("Folder write gate rejects duplicate path when policy rejects")
    func folderWriteGateRejectsDuplicatePath() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-write-reject-\(UUID().uuidString)", isDirectory: true)
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

        let service = VaultFolderService(database: db)
        let existing = try #require(service.createFolder(name: "Projects", parentID: nil))

        let decision = service.applyFolderWrite(.init(
            name: "Projects",
            source: .sync,
            requestedID: UUID(),
            duplicatePolicy: .reject
        ))

        #expect(decision == .rejected(reason: "duplicate_path"))
        #expect(service.folders.count == 1)
        #expect(service.folders.first?.id == existing.id)
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent("Projects 2").path))

        let count = try db.prepare("SELECT COUNT(*) FROM folders;")
        #expect(try count.step())
        #expect(count.int(at: 0) == 1)
    }

    @Test("Folder write gate quarantines duplicate path with provenance")
    func folderWriteGateQuarantinesDuplicatePath() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-write-quarantine-\(UUID().uuidString)", isDirectory: true)
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

        let service = VaultFolderService(database: db)
        _ = try #require(service.createFolder(name: "Projects", parentID: nil))
        let remoteID = UUID()

        let decision = service.applyFolderWrite(.init(
            name: "Projects",
            source: .sync,
            requestedID: remoteID,
            duplicatePolicy: .quarantine
        ))

        #expect(decision == .quarantined(reason: "duplicate_path", requestedPath: "Projects"))
        #expect(service.folders.map(\.relativePath) == ["Projects"])

        let audit = MutationAuditService(database: db).loadEntries()
        let entry = try #require(audit.first { $0.itemID == remoteID && $0.action == "folder.write.quarantined" })
        #expect(entry.itemType == "vaultFolderProposal")
        #expect(entry.source == .sync)
        #expect(entry.metadata["reason"] == "duplicate_path")
        #expect(entry.metadata["requestedPath"] == "Projects")
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
        let remoteID = UUID()

        let returned = try #require(loadedService.addFolderFromSync(
            id: remoteID,
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

        let decision = try #require(loadedService.syncFolderDecision(forRemoteFolderID: remoteID))
        #expect(decision.decision == .alias)
        #expect(decision.localFolderID == existingID)
        #expect(decision.reason == "duplicate_path")
        #expect(decision.requestedPath == "Media")
        #expect(decision.metadata["origin"] == "addFolderFromSync")
        #expect(loadedService.localFolderAlias(forRemoteFolderID: remoteID) == existingID)
    }

    @Test("Sync add quarantines unknown remote folder instead of creating local row")
    func addFolderFromSyncQuarantinesUnknownRemoteFolder() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-sync-quarantine-folder-\(UUID().uuidString)", isDirectory: true)
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

        let service = VaultFolderService(database: db)
        let remoteID = UUID()
        let returned = service.addFolderFromSync(
            id: remoteID,
            name: "Media",
            icon: "🎬",
            parentID: nil,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )

        #expect(returned == nil)
        #expect(service.folders.isEmpty)
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent("Media").path))

        let service2 = VaultFolderService(database: db)
        #expect(service2.folders.isEmpty)

        let audit = MutationAuditService(database: db).loadEntries()
        let entry = try #require(audit.first { $0.itemID == remoteID && $0.action == "folder.write.quarantined" })
        #expect(entry.itemType == "vaultFolderProposal")
        #expect(entry.source == .sync)
        #expect(entry.metadata["reason"] == "new_folder_requires_backend_approval")
        #expect(entry.metadata["requestedPath"] == "Media")
        #expect(entry.metadata["allowsCreate"] == "false")

        let decision = try #require(service.syncFolderDecision(forRemoteFolderID: remoteID))
        #expect(decision.decision == .quarantine)
        #expect(decision.localFolderID == nil)
        #expect(decision.reason == "new_folder_requires_backend_approval")
        #expect(decision.requestedPath == "Media")
        #expect(decision.metadata["origin"] == "addFolderFromSync")
        #expect(service.localFolderAlias(forRemoteFolderID: remoteID) == nil)
    }

    @Test("Sync update rename collision is quarantined instead of creating numeric suffix")
    func updateFolderFromSyncQuarantinesRenameCollision() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-sync-update-collision-\(UUID().uuidString)", isDirectory: true)
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
        try fm.createDirectory(at: vault.appendingPathComponent("Alpha"), withIntermediateDirectories: true)
        try fm.createDirectory(at: vault.appendingPathComponent("Beta"), withIntermediateDirectories: true)

        let alpha = VaultFolder(
            id: UUID(),
            relativePath: "Alpha",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let beta = VaultFolder(
            id: UUID(),
            relativePath: "Beta",
            createdAt: Date(timeIntervalSince1970: 1_100),
            updatedAt: Date(timeIntervalSince1970: 2_100)
        )
        let service = VaultFolderService(database: db)
        service.persistToDatabase(db, folder: alpha)
        service.persistToDatabase(db, folder: beta)
        let loadedService = VaultFolderService(database: db)

        loadedService.updateFolderFromSync(
            folderID: alpha.id,
            name: "Beta",
            icon: "remote-icon",
            parentID: nil,
            remoteUpdatedAt: Date(timeIntervalSince1970: 3_000)
        )

        let paths = loadedService.folders.map(\.relativePath).sorted()
        #expect(paths == ["Alpha", "Beta"])
        #expect(loadedService.folder(for: alpha.id)?.relativePath == "Alpha")
        #expect(loadedService.folder(for: alpha.id)?.icon == nil)
        #expect(!fm.fileExists(atPath: vault.appendingPathComponent("Beta 2").path))

        let audit = MutationAuditService(database: db).loadEntries()
        let entry = try #require(audit.first { $0.itemID == alpha.id && $0.action == "sync.folder.update_quarantined" })
        #expect(entry.metadata["reason"] == "duplicate_path")
        #expect(entry.metadata["requestedPath"] == "Beta")
    }

    @Test("Empty database loads empty folders array")
    func emptyDatabaseLoadsEmpty() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = VaultFolderService(database: db)
        #expect(service.folders.isEmpty)
    }

    @Test("Filesystem reconcile does not recreate unindexed folder rows")
    func reconcileDoesNotAdoptUnindexedDirectories() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-reconcile-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        try fm.createDirectory(at: vault.appendingPathComponent("Spaces"), withIntermediateDirectories: true)
        try fm.createDirectory(at: vault.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        try fm.createDirectory(at: vault.appendingPathComponent("Development/Tools"), withIntermediateDirectories: true)
        #expect(StoragePaths.cachedVaultDirectoryURL.path == vault.path)
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Spaces").path))

        let service = VaultFolderService(database: db)
        let spaces = VaultFolder(relativePath: "Spaces")
        service.persistToDatabase(db, folder: spaces)

        let loadedService = VaultFolderService(database: db)
        loadedService.reconcileWithFilesystemForTesting()

        #expect(loadedService.folders.map(\.relativePath) == ["Spaces"])

        let countStmt = try db.prepare("SELECT COUNT(*) FROM folders;")
        #expect(try countStmt.step())
        #expect(countStmt.int(at: 0) == 1)
    }

    @Test("Folder restore recreates rows through canonical write gate")
    func folderRestoreRecreatesRowsThroughCanonicalWriteGate() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = fm.temporaryDirectory.appendingPathComponent("cider-folder-restore-gate-\(UUID().uuidString)", isDirectory: true)
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

        let service = VaultFolderService(database: db)
        let folder = VaultFolder(
            id: UUID(),
            relativePath: "Restored",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            icon: "folder"
        )
        let trashSourceURL = vault
            .appendingPathComponent(".cider/folders/.trash", isDirectory: true)
            .appendingPathComponent(folder.id.uuidString, isDirectory: true)
        try fm.createDirectory(
            at: trashSourceURL.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        let trashItem = TrashItem(
            itemID: folder.id,
            itemType: .vaultFolder,
            title: folder.name,
            originalFolderID: nil,
            vaultFolderPayload: VaultFolderTrashPayload(folder: folder)
        )

        service.restoreFolder(trashItem)

        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Restored").path))
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Restored/Nested").path))
        #expect(service.folders.map(\.relativePath) == ["Restored", "Restored/Nested"])

        let reloaded = VaultFolderService(database: db)
        #expect(reloaded.folders.map(\.relativePath) == ["Restored", "Restored/Nested"])
        #expect(reloaded.folders.first { $0.relativePath == "Restored" }?.id == folder.id)

        let audit = MutationAuditService(database: db).loadEntries()
        let rootCreate = try #require(audit.first { $0.itemID == folder.id && $0.action == "folder.write.create" })
        #expect(rootCreate.source == .filesystem)
        #expect(rootCreate.metadata["source"] == "restore")
        #expect(rootCreate.metadata["requestedPath"] == "Restored")

        let nested = try #require(reloaded.folders.first { $0.relativePath == "Restored/Nested" })
        let nestedCreate = try #require(audit.first { $0.itemID == nested.id && $0.action == "folder.write.create" })
        #expect(nestedCreate.source == .filesystem)
        #expect(nestedCreate.metadata["source"] == "restore")
        #expect(nestedCreate.metadata["requestedPath"] == "Restored/Nested")
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
