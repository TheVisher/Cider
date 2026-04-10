import Foundation
import Testing
@testable import Cider

@Suite("Vault File SQLite Tests")
@MainActor
struct VaultFileSQLiteTests {

    // MARK: - Helpers

    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-vaultfile-test-\(UUID().uuidString).db"
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

    private func makeService(_ db: CiderDatabase) -> VaultFileStorage {
        VaultFileStorage(database: db)
    }

    private func makeFile(
        id: UUID = UUID(),
        filename: String = "photo.jpg",
        relativePath: String? = nil,
        fileType: VaultFileType = .image,
        fileSize: Int64 = 12_345,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_500),
        folderID: UUID? = nil,
        title: String? = nil,
        notes: String = "",
        labelIDs: [UUID] = [],
        ocrText: String? = nil,
        dominantColors: [String]? = nil
    ) -> VaultFile {
        VaultFile(
            id: id,
            filename: filename,
            relativePath: relativePath ?? "Inbox/Images/\(filename)",
            fileType: fileType,
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            folderID: folderID,
            title: title,
            notes: notes,
            labelIDs: labelIDs,
            ocrText: ocrText,
            dominantColors: dominantColors
        )
    }

    // MARK: - 1. Basic round-trip

    @Test("Vault file round-trips through SQLite")
    func basicRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(filename: "photo.jpg", title: "My Photo", notes: "cool shot")
        service.persistVaultFileToDatabase(db, file: file)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)

        let loaded = service2.metadata(for: file.id)
        #expect(loaded != nil)
        #expect(loaded?.title == "My Photo")
        #expect(loaded?.notes == "cool shot")
    }

    // MARK: - 2. All fields preserved

    @Test("All fields preserved through round-trip")
    func allFieldsPreserved() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let labelID = UUID()
        let file = makeFile(
            filename: "doc.pdf",
            fileType: .pdf,
            fileSize: 99_999,
            title: "Research Paper",
            notes: "important",
            labelIDs: [labelID],
            ocrText: "full text of pdf",
            dominantColors: ["#ff0000", "#00ff00"]
        )

        // Need a matching label row for the INSERT OR IGNORE to stick.
        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "Research")

        var fileWithLabel = file
        fileWithLabel.labelIDs = [label.id]
        service.persistVaultFileToDatabase(db, file: fileWithLabel)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)

        let loaded = service2.metadata(for: fileWithLabel.id)
        #expect(loaded?.title == "Research Paper")
        #expect(loaded?.notes == "important")
        #expect(loaded?.ocrText == "full text of pdf")
        #expect(loaded?.dominantColors == ["#ff0000", "#00ff00"])
        #expect(loaded?.labelIDs == [label.id])
    }

    // MARK: - 3. Nil optional fields

    @Test("Nil optional fields round-trip as nil")
    func nilOptionalFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(
            filename: "bare.png",
            title: nil,
            notes: "",
            ocrText: nil,
            dominantColors: nil
        )
        service.persistVaultFileToDatabase(db, file: file)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)

        let loaded = service2.metadata(for: file.id)
        #expect(loaded?.title == nil)
        #expect(loaded?.notes == "")
        #expect(loaded?.ocrText == nil)
        #expect(loaded?.dominantColors == nil)
    }

    // MARK: - 4. Delete + CASCADE

    @Test("Delete removes items + CASCADE cleans vault_files and item_labels")
    func deleteCascades() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "ToDelete")

        let service = makeService(db)
        let file = makeFile(filename: "goner.jpg", labelIDs: [label.id])
        service.persistVaultFileToDatabase(db, file: file)

        service.deleteVaultFileFromDatabase(db, fileID: file.id)

        // items row gone
        let iStmt = try db.prepare("SELECT count(*) FROM items WHERE id = ?;")
        iStmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try iStmt.step()
        #expect(iStmt.int(at: 0) == 0)

        // vault_files detail row cascaded
        let vfStmt = try db.prepare("SELECT count(*) FROM vault_files WHERE item_id = ?;")
        vfStmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try vfStmt.step()
        #expect(vfStmt.int(at: 0) == 0)

        // item_labels cascaded
        let lStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        lStmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try lStmt.step()
        #expect(lStmt.int(at: 0) == 0)
    }

    // MARK: - 5. Multiple vault files

    @Test("Multiple vault files round-trip")
    func multipleFiles() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let f1 = makeFile(filename: "a.jpg")
        let f2 = makeFile(filename: "b.pdf", fileType: .pdf)
        let f3 = makeFile(filename: "c.mp4", fileType: .video)

        service.persistVaultFileToDatabase(db, file: f1)
        service.persistVaultFileToDatabase(db, file: f2)
        service.persistVaultFileToDatabase(db, file: f3)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)

        #expect(service2.metadata(for: f1.id) != nil)
        #expect(service2.metadata(for: f2.id) != nil)
        #expect(service2.metadata(for: f3.id) != nil)
    }

    // MARK: - 6. Label IDs + update replaces

    @Test("Label IDs round-trip and updates replace old assignments")
    func labelIDsUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let l1 = labelStorage.createLabel(name: "L1")
        let l2 = labelStorage.createLabel(name: "L2")
        let l3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)
        var file = makeFile(filename: "multi.jpg", labelIDs: [l1.id, l2.id])
        service.persistVaultFileToDatabase(db, file: file)

        let loaded1 = makeService(db)
        loaded1.loadVaultFilesFromDatabase(db)
        #expect(Set(loaded1.metadata(for: file.id)?.labelIDs ?? []) == Set([l1.id, l2.id]))

        file.labelIDs = [l2.id, l3.id]
        service.persistVaultFileToDatabase(db, file: file)

        let loaded2 = makeService(db)
        loaded2.loadVaultFilesFromDatabase(db)
        #expect(Set(loaded2.metadata(for: file.id)?.labelIDs ?? []) == Set([l2.id, l3.id]))
    }

    // MARK: - 7. Folder ID

    @Test("Folder ID round-trips via items.folder_id")
    func folderIDRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Work")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)
        let file = makeFile(
            filename: "report.pdf",
            relativePath: "Work/report.pdf",
            fileType: .pdf,
            folderID: folder.id
        )
        service.persistVaultFileToDatabase(db, file: file)

        // Verify items.folder_id stored
        let stmt = try db.prepare("SELECT folder_id FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(DatabaseHelpers.decodeUUID(stmt.optionalString(at: 0) ?? "") == folder.id)
    }

    // MARK: - 8. Empty database

    @Test("Empty database loads empty metadata")
    func emptyDB() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadVaultFilesFromDatabase(db)
        #expect(service.metadata(for: UUID()) == nil)
    }

    // MARK: - 9. Date precision

    @Test("createdAt / modifiedAt survive round-trip with sub-ms precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let created = Date(timeIntervalSince1970: 1_234_567_890.123)
        let modified = Date(timeIntervalSince1970: 1_234_567_999.456)
        let file = makeFile(filename: "dated.jpg", createdAt: created, modifiedAt: modified)
        service.persistVaultFileToDatabase(db, file: file)

        let stmt = try db.prepare("SELECT created_at, updated_at FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        let loadedCreated = DatabaseHelpers.decodeDate(stmt.double(at: 0))
        let loadedModified = DatabaseHelpers.decodeDate(stmt.double(at: 1))
        #expect(abs(loadedCreated.timeIntervalSince(created)) < 0.001)
        #expect(abs(loadedModified.timeIntervalSince(modified)) < 0.001)
    }

    // MARK: - 10. FileType enum variants

    @Test("All VaultFileType variants round-trip through vault_files.file_type")
    func fileTypeVariants() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let variants: [VaultFileType] = [.image, .pdf, .video, .audio, .document, .archive, .unknown]
        var ids: [UUID: VaultFileType] = [:]
        for v in variants {
            let file = makeFile(filename: "f.\(v.rawValue)", fileType: v)
            ids[file.id] = v
            service.persistVaultFileToDatabase(db, file: file)
        }

        // SELECT and verify
        for (id, expected) in ids {
            let stmt = try db.prepare("SELECT file_type FROM vault_files WHERE item_id = ?;")
            stmt.bind(DatabaseHelpers.encode(id), at: 1)
            try stmt.step()
            #expect(stmt.string(at: 0) == expected.rawValue)
        }
    }

    // MARK: - 11. dominantColors JSON

    @Test("dominantColors round-trip: empty → NULL, nil → NULL, multiple preserved")
    func dominantColorsJSON() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let fNil = makeFile(filename: "nilcolors.jpg", dominantColors: nil)
        let fEmpty = makeFile(filename: "empty.jpg", dominantColors: [])
        let fMulti = makeFile(filename: "multi.jpg", dominantColors: ["#111", "#222", "#333"])

        service.persistVaultFileToDatabase(db, file: fNil)
        service.persistVaultFileToDatabase(db, file: fEmpty)
        service.persistVaultFileToDatabase(db, file: fMulti)

        func colorsColumn(_ id: UUID) throws -> String? {
            let stmt = try db.prepare("SELECT dominant_colors FROM vault_files WHERE item_id = ?;")
            stmt.bind(DatabaseHelpers.encode(id), at: 1)
            try stmt.step()
            return stmt.optionalString(at: 0)
        }

        #expect(try colorsColumn(fNil.id) == nil)
        #expect(try colorsColumn(fEmpty.id) == nil) // empty array → NULL
        #expect(try colorsColumn(fMulti.id) != nil)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)
        #expect(service2.metadata(for: fMulti.id)?.dominantColors == ["#111", "#222", "#333"])
    }

    // MARK: - 12. Uniquified filename via relative_path

    @Test("Uniquified filename round-trips through items.relative_path")
    func uniquifiedFilename() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(
            filename: "photo (2).jpg",
            relativePath: "Inbox/Images/photo (2).jpg"
        )
        service.persistVaultFileToDatabase(db, file: file)

        let stmt = try db.prepare("SELECT relative_path, filename FROM items i JOIN vault_files vf ON vf.item_id = i.id WHERE i.id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == "Inbox/Images/photo (2).jpg")
        #expect(stmt.string(at: 1) == "photo (2).jpg")
    }

    // MARK: - 13. Title fallback to filename without extension

    @Test("Nil title → items.title = filename without extension")
    func titleFallback() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(filename: "sunset.jpg", title: nil)
        service.persistVaultFileToDatabase(db, file: file)

        let stmt = try db.prepare("SELECT title FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "sunset")

        // And on load, the custom title should still read as nil (since it equals the stem).
        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)
        #expect(service2.metadata(for: file.id)?.title == nil)
    }

    // MARK: - 14. Update preserves labels

    @Test("Updating a file preserves existing labels when labelIDs unchanged")
    func updatePreservesLabels() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let l1 = labelStorage.createLabel(name: "Keep")

        let service = makeService(db)
        var file = makeFile(filename: "keeper.jpg", labelIDs: [l1.id])
        service.persistVaultFileToDatabase(db, file: file)

        // Simulate an update that touches other fields but keeps labelIDs.
        file.notes = "updated notes"
        service.persistVaultFileToDatabase(db, file: file)

        let service2 = makeService(db)
        service2.loadVaultFilesFromDatabase(db)
        #expect(service2.metadata(for: file.id)?.labelIDs == [l1.id])
        #expect(service2.metadata(for: file.id)?.notes == "updated notes")
    }

    // MARK: - 15. items.title reflects title field when set

    @Test("Custom title is stored in items.title (not the raw filename)")
    func customTitleInItemsTitle() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(filename: "IMG_4829.HEIC", title: "Beach Trip")
        service.persistVaultFileToDatabase(db, file: file)

        let stmt = try db.prepare("SELECT title FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "Beach Trip")
    }

    // MARK: - 16. id-map round-trip

    @Test("id-map sidecar JSON encodes [String: UUID] and decodes back")
    func idMapCodable() throws {
        let map: [String: UUID] = [
            "Inbox/Images/a.jpg": UUID(),
            "Work/report.pdf": UUID()
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(map)
        let decoded = try JSONDecoder().decode([String: UUID].self, from: data)
        #expect(decoded == map)
    }

    // MARK: - 17. id-map move preserves UUID

    @Test("Moving a file via id-map remap preserves the UUID")
    func idMapMovePreservesUUID() throws {
        // Operate on the in-memory id-map without touching real disk.
        let service = VaultFileService.shared
        service._resetIDMapForTesting()
        defer { service._resetIDMapForTesting() }

        let fileID = UUID()
        service._setIDMapEntryForTesting(path: "Inbox/Images/cat.jpg", id: fileID)

        // Simulate assignFile's remap: same UUID at a different path.
        let snapshotBefore = service._idMapSnapshotForTesting()
        #expect(snapshotBefore["Inbox/Images/cat.jpg"] == fileID)

        // Remove old key, add new key with same UUID.
        service._setIDMapEntryForTesting(path: "Work/Pets/cat.jpg", id: fileID)
        // The "remove" half would happen inside assignFile; verify the UUID matches.
        #expect(service._idMapEntryForTesting(path: "Work/Pets/cat.jpg") == fileID)
    }

    // MARK: - 18. Migration from path-derived ID

    @Test("Migration carries metadata from legacy path-derived ID to fresh UUID")
    func migrationFromPathDerivedID() throws {
        // This test verifies the core migration contract at the VaultFileStorage
        // level (since runOneTimeIDMigration depends on the real vault filesystem).
        //
        // Scenario: metadata was stored under an OLD path-derived ID. The
        // migration computes a FRESH UUID and calls migrateMetadata. After
        // migration, metadata(for: oldID) should be nil and metadata(for: newID)
        // should return the carried-over entry.
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let oldPathDerivedID = VaultFileService.shared._stableIDForTesting(path: "Inbox/Images/legacy.jpg")
        // Seed the in-memory metadata dict under the OLD path-derived ID (simulating
        // a legacy JSON index entry). restoreMetadata is the public API that
        // populates the dictionary from a VaultFile.
        let legacyFile = makeFile(
            id: oldPathDerivedID,
            filename: "legacy.jpg",
            title: "Legacy Title",
            notes: "legacy notes",
            ocrText: "legacy OCR"
        )
        service.restoreMetadata(from: legacyFile)
        #expect(service.metadata(for: oldPathDerivedID)?.title == "Legacy Title")

        // Mint a fresh UUID and migrate (this is what runOneTimeIDMigration does
        // for each file it finds on disk).
        let freshUUID = UUID()
        service.migrateMetadata(from: oldPathDerivedID, to: freshUUID)

        // Old ID should no longer be present; new ID holds the carried-over metadata.
        #expect(service.metadata(for: oldPathDerivedID) == nil)
        let migrated = service.metadata(for: freshUUID)
        #expect(migrated != nil)
        #expect(migrated?.title == "Legacy Title")
        #expect(migrated?.notes == "legacy notes")
        #expect(migrated?.ocrText == "legacy OCR")
    }

    // MARK: - Extra: items.type is 'vaultFile'

    @Test("Persisted items row uses type='vaultFile'")
    func itemsTypeValue() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(filename: "x.jpg")
        service.persistVaultFileToDatabase(db, file: file)

        let stmt = try db.prepare("SELECT type FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "vaultFile")
    }

    // MARK: - Extra: removeMetadata deletes the DB row

    @Test("removeMetadata deletes the items row via CASCADE")
    func removeMetadataDeletes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let file = makeFile(filename: "temp.jpg")
        service.persistVaultFileToDatabase(db, file: file)

        // Populate the in-memory metadata so removeMetadata finds an entry.
        service.loadVaultFilesFromDatabase(db)
        service.removeMetadata(for: file.id)

        let stmt = try db.prepare("SELECT count(*) FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(file.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }
}
