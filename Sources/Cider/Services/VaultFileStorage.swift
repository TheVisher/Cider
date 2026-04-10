import Foundation
import os

/// Persists metadata overlay for VaultFiles (title, notes, labels, OCR, colors).
/// VaultFileService owns file discovery (scanning); this service owns the metadata layer.
///
/// Primary storage (as of Task 9): SQLite — `items` + `vault_files` tables.
/// Legacy storage (kept only for the one-time migration path):
/// `.cider/vault-files/_cider_vault_files_index.json`
///
/// The in-memory `metadata` dictionary is the working cache; it mirrors SQLite
/// and is keyed by VaultFile ID (stable UUID resolved through
/// `VaultFileService`'s id-map sidecar).
@MainActor
final class VaultFileStorage: ObservableObject {
    static let shared = VaultFileStorage()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultFileStorage"
    )

    private let indexFileName = "_cider_vault_files_index.json"
    private var metadata: [UUID: VaultFileMetadata] = [:]

    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    private var storageDir: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("vault-files")
    }

    private var indexFileURL: URL {
        storageDir.appendingPathComponent(indexFileName)
    }

    private init() {
        ensureDirectory()

        // Try SQLite first (mirrors ContactStorage/TodoCardStorage pattern).
        if let db = resolvedDatabase {
            loadVaultFilesFromDatabase(db)
            if !metadata.isEmpty {
                return
            }
        }

        // Fall back to the legacy JSON index. This is the one-time migration
        // source — entries will be re-persisted to SQLite on the next write.
        loadLegacyIndex()
    }

    /// Testing-only initializer with an explicit database. Does NOT read the
    /// legacy JSON index.
    init(database: CiderDatabase) {
        self.database = database
    }

    // MARK: - Load / Save (legacy JSON index)

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    private func loadLegacyIndex() {
        guard let data = try? Data(contentsOf: indexFileURL) else { return }
        do {
            metadata = try JSONDecoder().decode([UUID: VaultFileMetadata].self, from: data)
            logger.info("Loaded vault file metadata (legacy JSON): \(self.metadata.count) entries")
        } catch {
            logger.warning("Failed to decode vault file metadata: \(error.localizedDescription)")
        }
    }

    /// Writes the in-memory metadata dictionary back to the legacy JSON index.
    /// Retained so the one-time SQLite migration path remains reversible until
    /// Task 13 removes the JSON fallback entirely.
    private func saveLegacyIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(metadata)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save vault file metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Merge with Scanned Files

    /// Applies persisted metadata onto scanned VaultFiles.
    /// Called by VaultFileService after scanning.
    func applyMetadata(to files: inout [VaultFile]) {
        for i in files.indices {
            guard let meta = metadata[files[i].id] else { continue }
            files[i].title = meta.title
            files[i].notes = meta.notes
            files[i].labelIDs = meta.labelIDs
            files[i].ocrText = meta.ocrText
            files[i].dominantColors = meta.dominantColors
        }
    }

    // MARK: - Update Metadata
    //
    // These methods take a `VaultFile` (not just an ID) so we don't need to
    // reach back into `VaultFileService.shared` to look one up. Callers already
    // have a VaultFile in hand — pass it through.

    func updateTitle(_ file: VaultFile, title: String?) {
        ensureEntry(file.id)
        metadata[file.id]?.title = title
        // Explicit title from the user: flag as manually set so load() restores
        // it even when it happens to match the filename stem.
        let hasTitle = (title?.isEmpty == false)
        metadata[file.id]?.titleManuallySet = hasTitle
        saveLegacyIndex()
        persistVaultFileToDatabase(file)
    }

    func updateNotes(_ file: VaultFile, notes: String) {
        ensureEntry(file.id)
        metadata[file.id]?.notes = notes
        saveLegacyIndex()
        persistVaultFileToDatabase(file)
    }

    func assignLabel(_ file: VaultFile, labelID: UUID) {
        ensureEntry(file.id)
        if metadata[file.id]?.labelIDs.contains(labelID) == false {
            metadata[file.id]?.labelIDs.append(labelID)
            saveLegacyIndex()
            persistVaultFileToDatabase(file)
        }
    }

    func removeLabel(_ file: VaultFile, labelID: UUID) {
        guard metadata[file.id] != nil else { return }
        metadata[file.id]?.labelIDs.removeAll { $0 == labelID }
        saveLegacyIndex()
        persistVaultFileToDatabase(file)
    }

    func applyEnrichment(file: VaultFile, ocrText: String, dominantColors: [String]?, title: String?) {
        ensureEntry(file.id)
        var changed = false
        if metadata[file.id]?.ocrText != ocrText {
            metadata[file.id]?.ocrText = ocrText; changed = true
        }
        if let dominantColors, metadata[file.id]?.dominantColors != dominantColors {
            metadata[file.id]?.dominantColors = dominantColors; changed = true
        }
        // Enrichment-suggested titles are NOT considered manually set — the
        // user didn't explicitly pick them. They fill in a title when there
        // wasn't one already, but don't flip titleManuallySet.
        if let title, !title.isEmpty, metadata[file.id]?.title != title {
            metadata[file.id]?.title = title; changed = true
        }
        if changed {
            saveLegacyIndex()
            persistVaultFileToDatabase(file)
        }
    }

    /// Migrates metadata from one file ID to another.
    ///
    /// With the stable-UUID design, this is called ONLY during the one-time
    /// migration from path-derived IDs to stable UUIDs (see
    /// `VaultFileService.runOneTimeIDMigration`). In-app moves preserve the
    /// UUID via the id-map, so the normal flow no longer needs this.
    func migrateMetadata(from oldID: UUID, to newID: UUID) {
        guard let existing = metadata.removeValue(forKey: oldID) else { return }
        metadata[newID] = existing
        saveLegacyIndex()
    }

    /// Removes metadata for a file (e.g., when permanently deleted).
    func removeMetadata(for fileID: UUID) {
        guard metadata.removeValue(forKey: fileID) != nil else {
            // Even if no in-memory metadata, make sure the DB row is gone.
            deleteVaultFileFromDatabase(fileID)
            return
        }
        saveLegacyIndex()
        deleteVaultFileFromDatabase(fileID)
    }

    /// Returns metadata for a file, if any exists.
    func metadata(for fileID: UUID) -> VaultFileMetadata? {
        metadata[fileID]
    }

    /// Restores metadata from a trashed VaultFile (re-registers after restore from trash).
    func restoreMetadata(from file: VaultFile) {
        var meta = VaultFileMetadata()
        meta.title = file.title
        // We can't know for certain whether the pre-trash title was user-set
        // or enrichment-set, but a non-nil title at restore time should survive
        // round-trip regardless of stem collision, so flag it.
        meta.titleManuallySet = (file.title?.isEmpty == false)
        meta.notes = file.notes
        meta.labelIDs = file.labelIDs
        meta.ocrText = file.ocrText
        meta.dominantColors = file.dominantColors
        metadata[file.id] = meta
        saveLegacyIndex()
        persistVaultFileToDatabase(file)
    }

    // MARK: - Private

    private func ensureEntry(_ fileID: UUID) {
        if metadata[fileID] == nil {
            metadata[fileID] = VaultFileMetadata()
        }
    }

    // MARK: - Database Persistence

    // Internal for testing
    /// SELECT all vault files from the database (items JOIN vault_files), loading
    /// labelIDs from item_labels. Rehydrates the in-memory `metadata` dictionary
    /// so mutation paths find their entries after a DB-first cold launch.
    ///
    /// NOTE: Base fields (filename, size, type, paths) are re-resolved from disk
    /// by `VaultFileService.scan()`; this function only rebuilds the overlay
    /// metadata cache and returns nothing to the scan layer directly.
    func loadVaultFilesFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       vf.filename, vf.file_type, vf.file_size, vf.notes, vf.ocr_text, vf.dominant_colors,
                       vf.title_manually_set
                FROM items i
                JOIN vault_files vf ON vf.item_id = i.id
                WHERE i.type = 'vaultFile';
                """)
            var rebuilt: [UUID: VaultFileMetadata] = [:]
            var count = 0
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let itemTitle = stmt.string(at: 1)
                let relativePath = stmt.optionalString(at: 5) ?? ""
                let filename = stmt.string(at: 6)
                let notes = stmt.string(at: 9)
                let ocrText = stmt.optionalString(at: 10)
                let dominantColorsJSON = stmt.optionalString(at: 11)
                let dominantColors = dominantColorsJSON.map { DatabaseHelpers.decodeStringArray($0) }
                let titleManuallySet = stmt.int(at: 12) != 0
                let labelIDs = (try? loadLabelIDs(db, itemID: id)) ?? []

                // items.title holds whatever the user sees (custom title OR
                // filename-without-extension). Use the explicit flag to decide
                // whether to treat the stored title as a custom title — this
                // prevents losing user intent when a custom title happens to
                // match the filename stem (e.g. title "sunset" on "sunset.jpg").
                let filenameStem = (filename as NSString).deletingPathExtension
                let customTitle: String?
                if titleManuallySet {
                    customTitle = itemTitle
                } else {
                    customTitle = (itemTitle == filenameStem) ? nil : itemTitle
                }

                var meta = VaultFileMetadata()
                meta.title = customTitle
                meta.titleManuallySet = titleManuallySet
                meta.notes = notes
                meta.labelIDs = labelIDs
                meta.ocrText = ocrText
                meta.dominantColors = dominantColors
                rebuilt[id] = meta
                count += 1

                _ = relativePath // silence unused warning; kept for future reconciliation
            }
            metadata = rebuilt
            logger.info("Loaded \(count) vault file metadata entries from database")
        } catch {
            logger.error("Failed to load vault files from database: \(error.localizedDescription)")
            metadata = [:]
        }
    }

    /// Load label IDs from the item_labels join table for a given item.
    private func loadLabelIDs(_ db: CiderDatabase, itemID: UUID) throws -> [UUID] {
        let stmt = try db.prepare("SELECT label_id FROM item_labels WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var ids: [UUID] = []
        while try stmt.step() {
            if let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) {
                ids.append(id)
            }
        }
        return ids
    }

    // Internal for testing
    /// Persist a single vault file to the resolved database inside a transaction.
    func persistVaultFileToDatabase(_ file: VaultFile) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for vault file \(file.id)")
            return
        }
        persistVaultFileToDatabase(db, file: file)
    }

    // Internal for testing
    /// Persist a single vault file to the given database inside its own transaction.
    func persistVaultFileToDatabase(_ db: CiderDatabase, file: VaultFile) {
        do {
            try db.withTransaction {
                try persistVaultFileToDatabaseInner(db, file: file)
            }
        } catch {
            logger.error("Failed to persist vault file \(file.id) to database: \(error.localizedDescription)")
        }
    }

    /// Core persist logic for a single vault file — must be called inside a transaction.
    /// Applies any in-memory metadata overlay for the file's ID so callers that
    /// pass a stale VaultFile (e.g. fresh from `scan()` before `applyMetadata`)
    /// don't accidentally null out labels/notes/title in SQLite.
    // Internal for testing
    func persistVaultFileToDatabaseInner(_ db: CiderDatabase, file: VaultFile) throws {
        // Overlay in-memory metadata so scan-time persists preserve user edits.
        var effective = file
        var effectiveTitleManuallySet = false
        if let meta = metadata[file.id] {
            effective.title = meta.title
            effective.notes = meta.notes
            effective.labelIDs = meta.labelIDs
            effective.ocrText = meta.ocrText
            effective.dominantColors = meta.dominantColors
            effectiveTitleManuallySet = meta.titleManuallySet
        }

        // items.title: what the user sees. Custom title if set, otherwise the
        // filename without extension. Matches VaultFile.displayTitle semantics.
        let displayTitle: String
        if let t = effective.title, !t.isEmpty {
            displayTitle = t
        } else {
            displayTitle = (effective.filename as NSString).deletingPathExtension
        }

        // 1. UPSERT into items (ON CONFLICT avoids DELETE+INSERT CASCADE).
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'vaultFile', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(effective.id)
        let folderIDText: String? = effective.folderID.map { DatabaseHelpers.encode($0) }
        itemStmt.bind(itemID, at: 1)
            .bind(displayTitle, at: 2)
            .bind(DatabaseHelpers.encode(effective.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(effective.modifiedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(effective.relativePath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into vault_files.
        let vfStmt = try db.prepare("""
            INSERT INTO vault_files (
                item_id, filename, file_type, file_size, notes, ocr_text, dominant_colors, title_manually_set
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                filename = excluded.filename,
                file_type = excluded.file_type,
                file_size = excluded.file_size,
                notes = excluded.notes,
                ocr_text = excluded.ocr_text,
                dominant_colors = excluded.dominant_colors,
                title_manually_set = excluded.title_manually_set;
            """)
        // Store nil for empty/nil dominantColors so the column is NULL rather than
        // an empty JSON array.
        let dominantColorsJSON: String? = {
            guard let colors = effective.dominantColors, !colors.isEmpty else { return nil }
            return DatabaseHelpers.encode(colors)
        }()
        vfStmt.bind(itemID, at: 1)
            .bind(effective.filename, at: 2)
            .bind(effective.fileType.rawValue, at: 3)
            .bind(Int64(effective.fileSize), at: 4)
            .bind(effective.notes, at: 5)
            .bind(effective.ocrText, at: 6)
            .bind(dominantColorsJSON, at: 7)
            .bind(Int64(effectiveTitleManuallySet ? 1 : 0), at: 8)
        try vfStmt.step()

        // 3. Sync item_labels: delete all, re-insert current.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !effective.labelIDs.isEmpty {
            let insLabel = try db.prepare("INSERT OR IGNORE INTO item_labels (item_id, label_id) VALUES (?, ?);")
            for labelID in effective.labelIDs {
                insLabel.reset()
                insLabel.bind(itemID, at: 1)
                    .bind(DatabaseHelpers.encode(labelID), at: 2)
                try insLabel.step()
            }
        }

        // Vault files do NOT have linkedEntities — skip item_links entirely.
    }

    // Internal for testing
    /// Delete a vault file from the database by ID. CASCADE handles vault_files + join tables.
    func deleteVaultFileFromDatabase(_ fileID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for vault file \(fileID)")
            return
        }
        deleteVaultFileFromDatabase(db, fileID: fileID)
    }

    // Internal for testing
    /// DELETE a vault file from the given database by ID.
    func deleteVaultFileFromDatabase(_ db: CiderDatabase, fileID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(fileID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete vault file \(fileID) from database: \(error.localizedDescription)")
        }
    }
}

// MARK: - Metadata Model

struct VaultFileMetadata: Codable {
    var title: String?
    var titleManuallySet: Bool = false
    var notes: String = ""
    var labelIDs: [UUID] = []
    var ocrText: String?
    var dominantColors: [String]?

    /// Backward-compatible decoder — new fields won't break existing JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        titleManuallySet = try c.decodeIfPresent(Bool.self, forKey: .titleManuallySet) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        labelIDs = try c.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        dominantColors = try c.decodeIfPresent([String].self, forKey: .dominantColors)
    }

    init() {}
}
