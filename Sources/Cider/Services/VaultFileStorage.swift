import Foundation
import os

/// Persists metadata overlay for VaultFiles (title, notes, labels, OCR, colors).
/// VaultFileService owns file discovery (scanning); this service owns the metadata layer.
///
/// Primary storage: SQLite — `items` + `vault_files` tables.
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

    private var metadata: [UUID: VaultFileMetadata] = [:]

    private var database: CiderDatabase?

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Returns the encoded folder_id TEXT if the folder exists in the target
    /// database, otherwise nil. Used to defuse items.folder_id FK violations.
    private func resolveSafeFolderID(_ db: CiderDatabase, folderID: UUID?) throws -> String? {
        guard let id = folderID else { return nil }
        let encoded = DatabaseHelpers.encode(id)
        let stmt = try db.prepare("SELECT 1 FROM folders WHERE id = ? LIMIT 1;")
        stmt.bind(encoded, at: 1)
        let exists = try stmt.step()
        return exists ? encoded : nil
    }

    private func existingItemType(_ db: CiderDatabase, itemID: UUID) throws -> String? {
        let stmt = try db.prepare("SELECT type FROM items WHERE id = ? LIMIT 1;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        guard try stmt.step() else { return nil }
        return stmt.optionalString(at: 0)
    }

    private var storageDir: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("vault-files")
    }

    private init() {
        ensureDirectory()
        if let db = resolvedDatabase {
            loadVaultFilesFromDatabase(db)
        }
    }

    /// Testing-only initializer with an explicit database.
    init(database: CiderDatabase) {
        self.database = database
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
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
            files[i].tags = meta.tags
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
        let before = snapshot(for: file)
        ensureEntry(file.id)
        metadata[file.id]?.title = title
        // Explicit title from the user: flag as manually set so load() restores
        // it even when it happens to match the filename stem.
        let hasTitle = (title?.isEmpty == false)
        metadata[file.id]?.titleManuallySet = hasTitle
        persistVaultFileToDatabase(file)
        MutationAuditService(database: resolvedDatabase).record(
            action: "update_title",
            itemType: "vaultFile",
            itemID: file.id,
            before: before,
            after: snapshot(for: file)
        )
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "vaultFile",
            ownerID: file.id
        )
    }

    func updateNotes(_ file: VaultFile, notes: String) {
        let before = snapshot(for: file)
        ensureEntry(file.id)
        metadata[file.id]?.notes = notes
        persistVaultFileToDatabase(file)
        MutationAuditService(database: resolvedDatabase).record(
            action: "update_notes",
            itemType: "vaultFile",
            itemID: file.id,
            before: before,
            after: snapshot(for: file)
        )
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "vaultFile",
            ownerID: file.id
        )
    }

    func assignLabel(_ file: VaultFile, labelID: UUID) {
        ensureEntry(file.id)
        if metadata[file.id]?.labelIDs.contains(labelID) == false {
            let before = snapshot(for: file)
            metadata[file.id]?.labelIDs.append(labelID)
            persistVaultFileToDatabase(file)
            MutationAuditService(database: resolvedDatabase).record(
                action: "assign_label",
                itemType: "vaultFile",
                itemID: file.id,
                before: before,
                after: snapshot(for: file),
                metadata: ["labelID": labelID.uuidString]
            )
        }
    }

    func removeLabel(_ file: VaultFile, labelID: UUID) {
        guard metadata[file.id] != nil else { return }
        let before = snapshot(for: file)
        let labelCount = metadata[file.id]?.labelIDs.count ?? 0
        metadata[file.id]?.labelIDs.removeAll { $0 == labelID }
        guard metadata[file.id]?.labelIDs.count != labelCount else { return }
        persistVaultFileToDatabase(file)
        MutationAuditService(database: resolvedDatabase).record(
            action: "remove_label",
            itemType: "vaultFile",
            itemID: file.id,
            before: before,
            after: snapshot(for: file),
            metadata: ["labelID": labelID.uuidString]
        )
    }

    /// Add a free-text tag to the file (case-insensitive dedup).
    /// Returns true on add (or already-present), false if the tag is blank.
    @discardableResult
    func addTag(_ file: VaultFile, tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        ensureEntry(file.id)
        let already = metadata[file.id]?.tags.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? false
        if !already {
            let before = snapshot(for: file)
            metadata[file.id]?.tags.append(trimmed)
            persistVaultFileToDatabase(file)
            MutationAuditService(database: resolvedDatabase).record(
                action: "add_tag",
                itemType: "vaultFile",
                itemID: file.id,
                before: before,
                after: snapshot(for: file),
                metadata: ["tag": trimmed]
            )
        }
        return true
    }

    /// Remove a free-text tag from the file (case-insensitive match).
    @discardableResult
    func removeTag(_ file: VaultFile, tag: String) -> Bool {
        guard metadata[file.id] != nil else { return false }
        let beforeSnapshot = snapshot(for: file)
        let before = metadata[file.id]?.tags.count ?? 0
        metadata[file.id]?.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        let after = metadata[file.id]?.tags.count ?? 0
        guard before != after else { return false }
        persistVaultFileToDatabase(file)
        MutationAuditService(database: resolvedDatabase).record(
            action: "remove_tag",
            itemType: "vaultFile",
            itemID: file.id,
            before: beforeSnapshot,
            after: snapshot(for: file),
            metadata: ["tag": tag]
        )
        return true
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
    }

    /// Removes metadata for a file (e.g., when permanently deleted).
    func removeMetadata(for fileID: UUID) {
        guard metadata.removeValue(forKey: fileID) != nil else {
            // Even if no in-memory metadata, make sure the DB row is gone.
            deleteVaultFileFromDatabase(fileID)
            return
        }
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
        meta.tags = file.tags
        meta.ocrText = file.ocrText
        meta.dominantColors = file.dominantColors
        metadata[file.id] = meta
        persistVaultFileToDatabase(file)
    }

    // MARK: - Private

    private func ensureEntry(_ fileID: UUID) {
        if metadata[fileID] == nil {
            metadata[fileID] = VaultFileMetadata()
        }
    }

    private func snapshot(for file: VaultFile) -> [String: String] {
        MutationAuditSnapshots.vaultFile(file, metadata: metadata[file.id])
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
                let tags = (try? loadTags(db, itemID: id)) ?? []

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
                meta.tags = tags
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

    /// Load free-text tags from the item_tags join table for a given item.
    private func loadTags(_ db: CiderDatabase, itemID: UUID) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT t.name FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.item_id = ?;
            """)
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var names: [String] = []
        while try stmt.step() {
            names.append(stmt.string(at: 0))
        }
        return names
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
        let itemID = DatabaseHelpers.encode(file.id)
        if let existingType = try existingItemType(db, itemID: file.id),
           existingType != "vaultFile" {
            logger.error("Skipped vault file persist for \(file.id.uuidString, privacy: .public): existing item type is \(existingType, privacy: .public)")
            return
        }

        // Overlay in-memory metadata so scan-time persists preserve user edits.
        var effective = file
        var effectiveTitleManuallySet = false
        if let meta = metadata[file.id] {
            effective.title = meta.title
            effective.notes = meta.notes
            effective.labelIDs = meta.labelIDs
            effective.tags = meta.tags
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
        //    Scrub folder_id against target DB to defuse FK failures.
        let folderIDText = try resolveSafeFolderID(db, folderID: effective.folderID)
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'vaultFile', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
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

        // 4. Sync item_tags: find-or-create tags by name, delete all, re-insert.
        let delTags = try db.prepare("DELETE FROM item_tags WHERE item_id = ?;")
        delTags.bind(itemID, at: 1)
        try delTags.step()

        if !effective.tags.isEmpty {
            let findTag = try db.prepare("SELECT id FROM tags WHERE name = ?;")
            let createTag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
            let insItemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")

            for tagName in effective.tags {
                findTag.reset()
                findTag.bind(tagName, at: 1)
                let tagID: String
                if try findTag.step() {
                    tagID = findTag.string(at: 0)
                } else {
                    tagID = DatabaseHelpers.encode(UUID())
                    createTag.reset()
                    createTag.bind(tagID, at: 1).bind(tagName, at: 2)
                    try createTag.step()
                }

                insItemTag.reset()
                insItemTag.bind(itemID, at: 1).bind(tagID, at: 2)
                try insItemTag.step()
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
            try SecondBrainStore(database: db).deleteOwnerFootprint(
                for: SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: fileID.uuidString)
            )
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
    var tags: [String] = []
    var ocrText: String?
    var dominantColors: [String]?

    /// Backward-compatible decoder — new fields won't break existing JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        titleManuallySet = try c.decodeIfPresent(Bool.self, forKey: .titleManuallySet) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        labelIDs = try c.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        dominantColors = try c.decodeIfPresent([String].self, forKey: .dominantColors)
    }

    init() {}
}
