import Foundation
import os

/// Manages vault folders as real filesystem directories.
/// Creating/renaming/deleting a folder in Cider creates/renames/deletes
/// the corresponding directory on disk. FSEvents watches for external changes
/// (e.g. user modifies folders in Finder).
@MainActor
final class VaultFolderService {
    static let shared = VaultFolderService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultFolderService"
    )

    /// All vault folders, sorted alphabetically by path.
    @Published private(set) var folders: [VaultFolder] = []

    // MARK: - Internal State

    /// UUID → VaultFolder index, persisted to disk.
    private var index: [UUID: VaultFolder] = [:]

    /// FSEvents watcher for the vault root.
    private var watcher: FSEventsWatcher?

    /// Whether we're currently performing a mutation (suppresses FSEvents reconcile).
    private var isMutating = false

    /// Explicit database instance (injected for testing).
    private let database: CiderDatabase?

    // MARK: - Paths

    private let metaDirName = ".cider/folders"
    private let coversDirName = "covers"
    private let trashDirName = ".trash"

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private var metaDir: URL {
        vaultRoot.appendingPathComponent(metaDirName)
    }

    private var coversDir: URL {
        metaDir.appendingPathComponent(coversDirName)
    }

    private var trashDir: URL {
        metaDir.appendingPathComponent(trashDirName)
    }

    // MARK: - Init

    private init() {
        self.database = nil
        ensureDirectories()
        loadIndexFromDatabaseOrJSON()
        reconcileWithFilesystem()
        startWatching()
    }

    /// Testing-only initializer that accepts an explicit database instance.
    /// Skips filesystem operations (directory creation, FSEvents, reconciliation).
    init(database: CiderDatabase) {
        self.database = database
        loadFromDatabase(database)
    }

    // MARK: - CRUD

    /// Creates a new folder as a real directory on disk.
    @discardableResult
    func createFolder(name: String, parentID: UUID?) -> VaultFolder? {
        let sanitized = Self.sanitizeDirectoryName(name)
        guard !sanitized.isEmpty else { return nil }

        // Resolve parent path
        let parentPath: String?
        if let parentID {
            guard let parent = index[parentID] else {
                logger.warning("createFolder: parent \(parentID) not found")
                return nil
            }
            parentPath = parent.relativePath
        } else {
            parentPath = nil
        }

        let resolvedName = uniqueName(baseName: sanitized, parentPath: parentPath)
        let relativePath = parentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
        let directoryURL = vaultRoot.appendingPathComponent(relativePath)

        isMutating = true
        defer { isMutating = false }

        // Check if directory already exists on disk (e.g. created by external process)
        // and is already in the index — return existing folder to avoid duplicate UUIDs
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            if let existing = index.values.first(where: { $0.relativePath == relativePath }) {
                logger.info("createFolder: directory already exists and indexed — returning existing")
                return existing
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("createFolder: failed to create directory: \(error.localizedDescription)")
            return nil
        }

        let folder = VaultFolder(relativePath: relativePath)
        index[folder.id] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()

        logger.info("Created folder '\(resolvedName)' at \(relativePath)")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return folder
    }

    /// Renames a folder by renaming its directory on disk.
    @discardableResult
    func renameFolder(_ folderID: UUID, to name: String) -> Bool {
        guard let folder = index[folderID] else { return false }

        let sanitized = Self.sanitizeDirectoryName(name)
        guard !sanitized.isEmpty else { return false }

        let parentPath = folder.parentRelativePath
        let resolvedName = uniqueName(
            baseName: sanitized,
            parentPath: parentPath,
            excludingID: folderID
        )

        // No change needed
        guard resolvedName != folder.name else { return true }

        let oldRelativePath = folder.relativePath
        let newRelativePath = parentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
        let oldURL = vaultRoot.appendingPathComponent(oldRelativePath)
        let newURL = vaultRoot.appendingPathComponent(newRelativePath)

        isMutating = true
        defer { isMutating = false }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            logger.error("renameFolder: failed to rename: \(error.localizedDescription)")
            return false
        }

        // Update this folder and all descendants
        let oldPrefix = oldRelativePath + "/"
        for (id, var entry) in index {
            if id == folderID {
                entry.relativePath = newRelativePath
                entry.updatedAt = Date()
                index[id] = entry
                persistFolderToDatabase(entry)
            } else if entry.relativePath.hasPrefix(oldPrefix) {
                entry.relativePath = newRelativePath + "/" + entry.relativePath.dropFirst(oldPrefix.count)
                entry.updatedAt = Date()
                index[id] = entry
                persistFolderToDatabase(entry)
            }
        }

        saveIndex()
        rebuildFolders()

        logger.info("Renamed folder '\(folder.name)' → '\(resolvedName)'")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return true
    }

    /// Moves a folder (and every descendant folder + every item inside the
    /// subtree) to a new parent. Pass `newParentID: nil` to move to the root.
    ///
    /// This is the folder-level analogue of `assignBookmark`: disk move +
    /// folder rows + `items.relative_path` all updated in one shot so the
    /// filesystem, the index, and SQLite stay consistent without waiting
    /// for a scan.
    @discardableResult
    func moveFolder(_ folderID: UUID, toParentID newParentID: UUID?) -> Bool {
        guard let folder = index[folderID] else { return false }

        // Resolve new parent path, with guards against moving into self / a descendant.
        let newParentPath: String?
        if let newParentID {
            guard let newParent = index[newParentID] else {
                logger.warning("moveFolder: target parent \(newParentID) not found")
                return false
            }
            if newParent.id == folder.id {
                logger.warning("moveFolder: cannot move folder into itself")
                return false
            }
            let folderPrefix = folder.relativePath + "/"
            if newParent.relativePath == folder.relativePath ||
               newParent.relativePath.hasPrefix(folderPrefix) {
                logger.warning("moveFolder: cannot move '\(folder.relativePath)' into its own descendant '\(newParent.relativePath)'")
                return false
            }
            newParentPath = newParent.relativePath
        } else {
            newParentPath = nil
        }

        // Already at the target parent — no-op success.
        if newParentPath == folder.parentRelativePath {
            return true
        }

        let resolvedName = uniqueName(
            baseName: folder.name,
            parentPath: newParentPath,
            excludingID: folderID
        )

        let oldRelativePath = folder.relativePath
        let newRelativePath = newParentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
        let oldURL = vaultRoot.appendingPathComponent(oldRelativePath)
        let newURL = vaultRoot.appendingPathComponent(newRelativePath)

        isMutating = true
        defer { isMutating = false }

        // Ensure the destination parent directory actually exists on disk.
        // Normal flow uses a registered parent (guaranteed to exist) but we
        // also accept root moves, so this is a cheap safety net.
        if let newParentPath {
            let parentURL = vaultRoot.appendingPathComponent(newParentPath)
            try? FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            logger.error("moveFolder: failed to move directory: \(error.localizedDescription)")
            return false
        }

        // Update this folder and all descendants in the index + folders table.
        let oldPrefix = oldRelativePath + "/"
        for (id, var entry) in index {
            if id == folderID {
                entry.relativePath = newRelativePath
                entry.updatedAt = Date()
                index[id] = entry
                persistFolderToDatabase(entry)
            } else if entry.relativePath.hasPrefix(oldPrefix) {
                entry.relativePath = newRelativePath + "/" + entry.relativePath.dropFirst(oldPrefix.count)
                entry.updatedAt = Date()
                index[id] = entry
                persistFolderToDatabase(entry)
            }
        }

        // Rewrite items.relative_path for every item in the moved subtree so
        // the items table doesn't point at stale paths until the next scan.
        rewriteItemPathsAfterMove(oldPrefix: oldRelativePath, newPrefix: newRelativePath)

        saveIndex()
        rebuildFolders()

        logger.info("Moved folder '\(folder.name)' from \(oldRelativePath) → \(newRelativePath)")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        SyncService.shared.pushAfterLocalChange()
        return true
    }

    /// Sets `items.folder_id = NULL` for every item referencing any of the
    /// given folder IDs. Called before deleting folder rows so the FK
    /// (no ON DELETE clause) doesn't abort the delete.
    private func unassignItemsFromFolders(_ folderIDs: [UUID]) {
        guard let db = resolvedDatabase, !folderIDs.isEmpty else { return }
        do {
            let stmt = try db.prepare("UPDATE items SET folder_id = NULL WHERE folder_id = ?;")
            for id in folderIDs {
                stmt.reset()
                stmt.bind(DatabaseHelpers.encode(id), at: 1)
                try stmt.step()
            }
        } catch {
            logger.error("unassignItemsFromFolders: failed to clear folder_id: \(error.localizedDescription)")
        }
    }

    /// UPDATE items.relative_path for every item whose path sits inside the
    /// moved folder. Uses LIKE with a trailing `/` so siblings with a shared
    /// prefix (e.g. "Tech" vs "Technology") don't get swept up. Folder names
    /// are sanitized so literal `%`/`_` in paths aren't a concern.
    private func rewriteItemPathsAfterMove(oldPrefix: String, newPrefix: String) {
        guard let db = resolvedDatabase else { return }
        do {
            let likePattern = oldPrefix + "/%"
            let newReplacementPrefix = newPrefix + "/"
            // substr is 1-indexed; start one past "oldPrefix/" so we keep the
            // descendant portion unchanged.
            let substrStart = Int64(oldPrefix.count + 2)
            let stmt = try db.prepare("""
                UPDATE items
                SET relative_path = ? || substr(relative_path, ?)
                WHERE relative_path LIKE ?;
                """)
            stmt.bind(newReplacementPrefix, at: 1)
                .bind(substrStart, at: 2)
                .bind(likePattern, at: 3)
            try stmt.step()
        } catch {
            logger.error("moveFolder: failed to rewrite item paths: \(error.localizedDescription)")
        }
    }

    /// Deletes a folder by moving its directory to the vault trash.
    /// Returns the TrashItem for undo support.
    @discardableResult
    func deleteFolder(_ folderID: UUID) -> TrashItem? {
        guard let folder = index[folderID] else { return nil }

        let sourceURL = vaultRoot.appendingPathComponent(folder.relativePath)
        let trashDestURL = trashDir.appendingPathComponent(folder.id.uuidString)
        let fm = FileManager.default

        isMutating = true
        defer { isMutating = false }

        // Ensure trash dir exists
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)

        // If something with same name already in trash, remove it
        if fm.fileExists(atPath: trashDestURL.path) {
            try? fm.removeItem(at: trashDestURL)
        }

        do {
            try fm.moveItem(at: sourceURL, to: trashDestURL)
        } catch {
            logger.error("deleteFolder: failed to move to trash: \(error.localizedDescription)")
            return nil
        }

        // Collect this folder and all descendants
        let deletedPrefix = folder.relativePath + "/"
        var deletedFolders: [VaultFolder] = [folder]
        for (_, entry) in index where entry.relativePath.hasPrefix(deletedPrefix) {
            deletedFolders.append(entry)
        }

        // Unfile any items referencing these folders at the SQL level before
        // deleting the folder rows. Without this, the FK on items.folder_id
        // (no ON DELETE clause in schema) makes `DELETE FROM folders` silently
        // fail via SQLite FK enforcement, leaving the folder row in place.
        // Setting folder_id = NULL mirrors `deleteFolderFromSync`'s semantic:
        // items survive a folder deletion and reappear in the Inbox view.
        unassignItemsFromFolders(deletedFolders.map(\.id))

        // Remove from index and database
        for deleted in deletedFolders {
            index.removeValue(forKey: deleted.id)
            deleteFolderFromDatabase(folderID: deleted.id)
        }

        let payload = VaultFolderTrashPayload(folder: folder)
        let trashItem = TrashItem(
            itemID: folder.id,
            itemType: .vaultFolder,
            title: folder.name,
            originalFolderID: nil,
            vaultFolderPayload: payload
        )

        // Add to trash manifest
        addToTrashManifest(trashItem)

        saveIndex()
        rebuildFolders()

        // Notify sync service of all deleted folders (root + descendants)
        for deleted in deletedFolders {
            SyncService.shared.trackFolderDeletion(of: deleted.id)
        }

        logger.info("Trashed folder '\(folder.name)' and \(deletedFolders.count - 1) subfolder(s)")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return trashItem
    }

    /// Restores a trashed vault folder by moving it back from trash.
    func restoreFolder(_ trashItem: TrashItem) {
        guard let payload = trashItem.vaultFolderPayload else { return }

        let folder = payload.folder
        let trashSourceURL = trashDir.appendingPathComponent(folder.id.uuidString)
        let restoreURL = vaultRoot.appendingPathComponent(folder.relativePath)
        let fm = FileManager.default

        isMutating = true
        defer { isMutating = false }

        // Ensure parent directory exists
        let parentURL = restoreURL.deletingLastPathComponent()
        try? fm.createDirectory(at: parentURL, withIntermediateDirectories: true)

        do {
            try fm.moveItem(at: trashSourceURL, to: restoreURL)
        } catch {
            logger.error("restoreFolder: failed to restore: \(error.localizedDescription)")
            return
        }

        // Re-add to index with updated timestamp so sync picks it up
        var restoredFolder = folder
        restoredFolder.updatedAt = Date()
        index[folder.id] = restoredFolder
        persistFolderToDatabase(restoredFolder)

        // Re-scan for any subdirectories that were inside the restored folder
        scanSubdirectories(of: folder.relativePath)

        removeFromTrashManifest(trashItem.id)

        saveIndex()
        rebuildFolders()

        // Cancel any pending sync deletion and trigger a push so the folder reappears on web
        SyncService.shared.cancelFolderDeletion(of: folder.id)
        SyncService.shared.pushAfterLocalChange()

        logger.info("Restored folder '\(folder.name)'")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
    }

    // MARK: - Metadata

    @discardableResult
    func setIcon(_ icon: String?, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        folder.icon = icon
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return true
    }

    @discardableResult
    func setCoverImage(_ imageData: Data, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }

        let fm = FileManager.default
        try? fm.createDirectory(at: coversDir, withIntermediateDirectories: true)

        // Remove old cover if exists
        if let existing = folder.coverImagePath {
            let existingURL = vaultRoot.appendingPathComponent(existing)
            try? fm.removeItem(at: existingURL)
        }

        let filename = "\(folderID.uuidString).jpg"
        let coverRelPath = "\(metaDirName)/\(coversDirName)/\(filename)"
        let coverURL = vaultRoot.appendingPathComponent(coverRelPath)

        do {
            try imageData.write(to: coverURL, options: .atomic)
        } catch {
            logger.error("setCoverImage: failed to write: \(error.localizedDescription)")
            return false
        }

        folder.coverImagePath = coverRelPath
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return true
    }

    @discardableResult
    func setCoverImageOffsetY(_ offsetY: Double, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        folder.coverImageOffsetY = offsetY
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        return true
    }

    @discardableResult
    func removeCoverImage(for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        if let existing = folder.coverImagePath {
            let existingURL = vaultRoot.appendingPathComponent(existing)
            try? FileManager.default.removeItem(at: existingURL)
        }
        folder.coverImagePath = nil
        folder.coverImageOffsetY = nil
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return true
    }

    func coverImageURL(for folder: VaultFolder) -> URL? {
        guard let path = folder.coverImagePath else { return nil }
        let url = vaultRoot.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Queries

    func folder(for id: UUID) -> VaultFolder? {
        index[id]
    }

    /// Returns direct children of the given parent (nil = root-level folders).
    func children(of parentID: UUID?) -> [VaultFolder] {
        let parentPath = parentID.flatMap { index[$0]?.relativePath }
        return folders.filter { $0.parentRelativePath == parentPath }
    }

    /// Returns the breadcrumb chain from root to the given folder.
    func path(to folderID: UUID) -> [VaultFolder] {
        guard let folder = index[folderID] else { return [] }

        var chain: [VaultFolder] = []
        let components = folder.relativePath.split(separator: "/").map(String.init)

        // Build path from root to this folder
        var accumulated = ""
        for component in components {
            accumulated = accumulated.isEmpty ? component : "\(accumulated)/\(component)"
            if let match = folders.first(where: { $0.relativePath == accumulated }) {
                chain.append(match)
            }
        }
        return chain
    }

    /// Returns the absolute URL for a folder's directory.
    func absoluteURL(for folder: VaultFolder) -> URL {
        vaultRoot.appendingPathComponent(folder.relativePath)
    }

    /// Finds the folder ID for a given relative path.
    func folderID(for relativePath: String) -> UUID? {
        index.first(where: { $0.value.relativePath == relativePath })?.key
    }

    // MARK: - Legacy Bridge

    /// Resolves the parent UUID for a vault folder by looking up its parent path in the index.
    func parentID(for folder: VaultFolder) -> UUID? {
        guard let parentPath = folder.parentRelativePath else { return nil }
        return index.first(where: { $0.value.relativePath == parentPath })?.key
    }

    /// Converts a VaultFolder to the legacy Folder type used by the existing UI.
    func toLegacyFolder(_ vaultFolder: VaultFolder) -> Folder {
        Folder(
            id: vaultFolder.id,
            name: vaultFolder.name,
            parentID: parentID(for: vaultFolder),
            createdAt: vaultFolder.createdAt,
            updatedAt: vaultFolder.updatedAt,
            coverImagePath: vaultFolder.coverImagePath,
            coverImageOffsetY: vaultFolder.coverImageOffsetY,
            icon: vaultFolder.icon
        )
    }

    /// Returns all folders converted to the legacy Folder type.
    var legacyFolders: [Folder] {
        folders.map { toLegacyFolder($0) }
    }

    // MARK: - Sync Operations

    /// Creates a folder from sync data, creating the directory on disk.
    /// Uses the provided UUID so local and remote IDs match.
    @discardableResult
    func addFolderFromSync(
        id: UUID,
        name: String,
        icon: String?,
        parentID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) -> VaultFolder? {
        guard index[id] == nil else { return index[id] }

        let sanitized = Self.sanitizeDirectoryName(name)
        guard !sanitized.isEmpty else { return nil }

        let parentPath: String?
        if let parentID {
            parentPath = index[parentID]?.relativePath
        } else {
            parentPath = nil
        }

        let resolvedName = uniqueName(baseName: sanitized, parentPath: parentPath)
        let relativePath = parentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
        let directoryURL = vaultRoot.appendingPathComponent(relativePath)

        isMutating = true
        defer { isMutating = false }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("addFolderFromSync: failed to create directory: \(error.localizedDescription)")
            return nil
        }

        let folder = VaultFolder(
            id: id,
            relativePath: relativePath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            icon: icon
        )
        index[folder.id] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()

        logger.info("Sync: created folder '\(resolvedName)' at \(relativePath)")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return folder
    }

    /// Updates an existing folder from sync data. Renames directory if name changed.
    func updateFolderFromSync(
        folderID: UUID,
        name: String,
        icon: String?,
        parentID: UUID?,
        remoteUpdatedAt: Date
    ) {
        guard var folder = index[folderID] else { return }

        isMutating = true
        defer { isMutating = false }

        // Check if name changed — requires directory rename
        let sanitized = Self.sanitizeDirectoryName(name)
        if !sanitized.isEmpty && sanitized != folder.name {
            let parentPath = folder.parentRelativePath
            let resolvedName = uniqueName(baseName: sanitized, parentPath: parentPath, excludingID: folderID)
            let newRelativePath = parentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
            let oldURL = vaultRoot.appendingPathComponent(folder.relativePath)
            let newURL = vaultRoot.appendingPathComponent(newRelativePath)

            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                // Update this folder and all descendants
                let oldPrefix = folder.relativePath + "/"
                for (id, var entry) in index {
                    if id == folderID {
                        entry.relativePath = newRelativePath
                        index[id] = entry
                        persistFolderToDatabase(entry)
                    } else if entry.relativePath.hasPrefix(oldPrefix) {
                        entry.relativePath = newRelativePath + "/" + entry.relativePath.dropFirst(oldPrefix.count)
                        index[id] = entry
                        persistFolderToDatabase(entry)
                    }
                }
                folder = index[folderID]!
            } catch {
                logger.error("updateFolderFromSync: rename failed: \(error.localizedDescription)")
            }
        }

        // Update metadata
        folder.icon = icon
        folder.updatedAt = remoteUpdatedAt
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()

        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
    }

    /// Deletes a folder from sync. Removes the directory from disk permanently
    /// (sync deletions are not recoverable via local trash).
    func deleteFolderFromSync(_ folderID: UUID) {
        guard let folder = index[folderID] else { return }

        let directoryURL = vaultRoot.appendingPathComponent(folder.relativePath)

        isMutating = true
        defer { isMutating = false }

        // Unassign items before removing the folder directory so their files move
        // back to Inbox instead of being deleted with the folder tree.
        let deletedIDs: Set<UUID> = {
            var ids: Set<UUID> = [folderID]
            let prefix = folder.relativePath + "/"
            for (id, entry) in index where entry.relativePath.hasPrefix(prefix) {
                ids.insert(id)
            }
            return ids
        }()
        for id in deletedIDs {
            for note in NotesStorage.shared.notes where note.folderID == id {
                NotesStorage.shared.assignNote(note.id, toFolder: nil)
            }
            for bookmark in VaultBookmarkService.shared.bookmarks where bookmark.folderID == id {
                VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: nil)
            }
            for todo in TodoCardStorage.shared.todoCards where todo.folderID == id {
                TodoCardStorage.shared.assignTodoCard(todo.id, toFolder: nil)
            }
            for dc in DateCardStorage.shared.dateCards where dc.folderID == id {
                DateCardStorage.shared.assignDateCard(dc.id, toFolder: nil)
            }
            for contact in ContactStorage.shared.contacts where contact.folderID == id {
                ContactStorage.shared.assignContact(contact.id, toFolder: nil)
            }
            for session in BrowserSessionStorage.shared.sessions where session.folderID == id {
                BrowserSessionStorage.shared.assignSession(session.id, toFolder: nil)
            }
            for file in VaultFileService.shared.files where file.folderID == id {
                VaultFileService.shared.assignFile(file.id, toFolder: nil)
            }
        }

        // Remove all descendants from index and database
        let prefix = folder.relativePath + "/"
        let descendantIDs = index.filter { $0.value.relativePath.hasPrefix(prefix) }.map(\.key)
        for id in descendantIDs {
            index.removeValue(forKey: id)
            deleteFolderFromDatabase(folderID: id)
        }
        index.removeValue(forKey: folderID)
        deleteFolderFromDatabase(folderID: folderID)

        // Remove directory (contains all sub-folders and filed cards)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                logger.error("deleteFolderFromSync: failed to remove directory: \(error.localizedDescription)")
            }
        }

        saveIndex()
        rebuildFolders()

        logger.info("Sync: deleted folder '\(folder.name)'")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
    }

    // MARK: - FSEvents

    func startWatching() {
        stopWatching()
        watcher = FSEventsWatcher(path: vaultRoot.path) { [weak self] paths in
            // Filter out writes inside `.cider/` — those are our own bookkeeping
            // (cider.db, cider.db-wal, id-map.json, sidecars, etc.) and if we
            // re-triggered scan on them, every SQLite write would feed back as
            // an FSEvents burst → rescan → more SQLite writes → infinite loop.
            let hasUserFileChange = paths.contains { !$0.contains("/.cider/") }
            guard hasUserFileChange else { return }
            // FSEventsWatcher delivers on main queue
            MainActor.assumeIsolated {
                self?.handleFSEvent()
            }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// Called when the vault root changes (e.g. user changes in Settings).
    func updateVaultRoot() {
        stopWatching()
        StoragePaths.invalidateCachedDirectory()
        ensureDirectories()
        loadIndexFromDatabaseOrJSON()
        reconcileWithFilesystem()
        startWatching()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
    }

    // MARK: - Private: FSEvents Handling

    /// Debounced task for vault file adoption after FSEvents settle.
    private var adoptionDebounceTask: Task<Void, Never>?

    private func handleFSEvent() {
        guard !isMutating else { return }
        // Re-read the in-memory folder index from SQLite FIRST so that changes
        // made by another process (e.g. `cider-cli folder move/delete`) are
        // picked up before we reconcile against disk. Without this, the
        // running app's index is a frozen snapshot of startup state, and the
        // reconciler's "discovered external folder" branch will keep
        // resurrecting folders that the CLI just deleted (with fresh UUIDs).
        loadIndexFromDatabaseOrJSON()
        reconcileWithFilesystem()
        // Reload sidecar metadata and rescan vault files
        SidecarService.shared.loadAll()
        VaultFileService.shared.scan()
        NotificationCenter.default.post(name: .vaultFilesystemDidChange, object: nil)
        // Debounced adoption: wait for FSEvents to settle, then scan once
        adoptionDebounceTask?.cancel()
        adoptionDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            VaultBookmarkService.shared.adoptOrphanedVaultFiles()
        }
    }

    // MARK: - Private: Filesystem Reconciliation

    /// Scans the vault root for directories and reconciles with the index.
    /// - Directories on disk but not in index → add with new UUID
    /// - Entries in index but directory missing from disk → remove from index
    private func reconcileWithFilesystem() {
        let fm = FileManager.default
        let root = vaultRoot

        // Enumerate all directories under vault root
        var diskPaths = Set<String>()
        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isDir else { continue }

                let relativePath = url.path.replacingOccurrences(
                    of: root.path + "/",
                    with: ""
                )

                // Skip storage-type subdirectories (Bookmarks/, Notes/, etc.)
                if isStorageTypeDirectory(relativePath) { continue }

                diskPaths.insert(relativePath)
            }
        }

        var changed = false

        // Paths on disk not in index → new folders from Finder
        let indexedPaths = Set(index.values.map(\.relativePath))
        for diskPath in diskPaths where !indexedPaths.contains(diskPath) {
            let folder = VaultFolder(relativePath: diskPath)
            index[folder.id] = folder
            persistFolderToDatabase(folder)
            logger.info("Discovered external folder: \(diskPath)")
            changed = true
        }

        // Paths in index not on disk → deleted from Finder.
        //
        // Safety net: skip the delete if SQLite still has items referencing
        // this folder. FSEvents can briefly see a folder as "gone" during a
        // rename or sync operation; we don't want to aggressively wipe a
        // folder (and trigger the items FK cascade) just because scan caught
        // a transient state. Empty folders remain safe to remove.
        for (id, entry) in index {
            if !diskPaths.contains(entry.relativePath) {
                if folderHasItemsInDatabase(id) {
                    logger.warning("Skipping removal of missing folder \(entry.relativePath) — still has items or sessions in database (transient FS state?)")
                    continue
                }
                index.removeValue(forKey: id)
                deleteFolderFromDatabase(folderID: id)
                logger.info("Removed missing folder: \(entry.relativePath)")
                changed = true
            }
        }

        if changed {
            saveIndex()
            rebuildFolders()
            NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        }
    }

    private func folderHasItemsInDatabase(_ folderID: UUID) -> Bool {
        guard let db = resolvedDatabase else { return false }
        let encodedFolderID = DatabaseHelpers.encode(folderID)
        do {
            let itemStmt = try db.prepare("SELECT COUNT(*) FROM items WHERE folder_id = ?;")
            itemStmt.bind(encodedFolderID, at: 1)
            let itemCount = try itemStmt.step() ? itemStmt.int64(at: 0) : 0

            let sessionStmt = try db.prepare("SELECT COUNT(*) FROM sessions WHERE folder_id = ?;")
            sessionStmt.bind(encodedFolderID, at: 1)
            let sessionCount = try sessionStmt.step() ? sessionStmt.int64(at: 0) : 0

            return itemCount > 0 || sessionCount > 0
        } catch {
            logger.error("Failed to check folder references for \(folderID): \(error.localizedDescription)")
            return true
        }
    }

    /// Scans subdirectories of a given path and adds any missing ones to the index.
    /// Used after restoring a folder from trash.
    private func scanSubdirectories(of parentPath: String) {
        let fm = FileManager.default
        let parentURL = vaultRoot.appendingPathComponent(parentPath)

        guard let enumerator = fm.enumerator(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let indexedPaths = Set(index.values.map(\.relativePath))

        for case let url as URL in enumerator {
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }

            let relativePath = url.path.replacingOccurrences(
                of: vaultRoot.path + "/",
                with: ""
            )

            if !indexedPaths.contains(relativePath) {
                let folder = VaultFolder(relativePath: relativePath)
                index[folder.id] = folder
                persistFolderToDatabase(folder)
            }
        }
    }

    /// Directories that are Cider internals or reserved, not user-created folders.
    /// All StorageType dirs now live inside `.cider/` (hidden, auto-skipped by .skipsHiddenFiles).
    private static let reservedDirectoryNames: Set<String> = [
        "Inbox", "Unsorted",
        // Storage type directories that may exist at vault root from legacy migrations
        "Bookmarks", "Contacts", "DateCards", "Labels", "Notes",
        "SavedViews", "Sources", "Stacks", "Tags",
    ]

    /// Returns true if the path is a reserved directory that should not appear as a vault folder.
    private func isStorageTypeDirectory(_ relativePath: String) -> Bool {
        let topComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
        return Self.reservedDirectoryNames.contains(topComponent)
    }

    // MARK: - Database Persistence

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Load folders from SQLite.
    private func loadIndexFromDatabaseOrJSON() {
        if let db = resolvedDatabase {
            loadFromDatabase(db)
        }
    }

    // Internal for testing
    /// SELECT all folders from the database, ordered by relative_path.
    func loadFromDatabase(_ db: CiderDatabase) {
        do {
            let stmt = try db.prepare("""
                SELECT id, relative_path, created_at, updated_at, icon, cover_image_path, cover_image_offset_y
                FROM folders ORDER BY relative_path COLLATE NOCASE;
                """)
            var loaded: [UUID: VaultFolder] = [:]
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let folder = VaultFolder(
                    id: id,
                    relativePath: stmt.string(at: 1),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 2)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
                    icon: stmt.optionalString(at: 4),
                    coverImagePath: stmt.optionalString(at: 5),
                    coverImageOffsetY: stmt.optionalDouble(at: 6)
                )
                loaded[id] = folder
            }
            index = loaded
            rebuildFolders()
            logger.info("Loaded \(loaded.count) folders from database")
        } catch {
            logger.error("Failed to load folders from database: \(error.localizedDescription)")
            index = [:]
        }
    }

    /// Persist a single folder to the resolved database (production wrapper).
    private func persistFolderToDatabase(_ folder: VaultFolder) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for folder \(folder.id)")
            return
        }
        persistToDatabase(db, folder: folder)
    }

    // Internal for testing
    /// UPSERT a single folder into the given database (ON CONFLICT avoids DELETE+INSERT; consistent with items/labels pattern).
    func persistToDatabase(_ db: CiderDatabase, folder: VaultFolder) {
        // Defensive guard: refuse to persist folder rows for reserved
        // storage-type paths. These aren't real user folders — they're
        // subtrees the reconciler excludes from disk scans, and letting
        // them into the folders table produces ghost rows that block
        // reconciliation forever. See migrateToV3.
        if isStorageTypeDirectory(folder.relativePath) {
            logger.warning("Refusing to persist reserved-path folder \(folder.relativePath) (id: \(folder.id))")
            return
        }
        do {
            let stmt = try db.prepare("""
                INSERT INTO folders (id, relative_path, created_at, updated_at, icon, cover_image_path, cover_image_offset_y)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    relative_path = excluded.relative_path,
                    updated_at = excluded.updated_at,
                    icon = excluded.icon,
                    cover_image_path = excluded.cover_image_path,
                    cover_image_offset_y = excluded.cover_image_offset_y;
                """)
            stmt.bind(DatabaseHelpers.encode(folder.id), at: 1)
                .bind(folder.relativePath, at: 2)
                .bind(DatabaseHelpers.encode(folder.createdAt), at: 3)
                .bind(DatabaseHelpers.encode(folder.updatedAt), at: 4)
                .bind(folder.icon, at: 5)
                .bind(folder.coverImagePath, at: 6)
                .bind(folder.coverImageOffsetY, at: 7)
            try stmt.step()
        } catch {
            logger.error("Failed to persist folder \(folder.id) to database: \(error.localizedDescription)")
        }
    }

    /// Delete a single folder from the resolved database (production wrapper).
    private func deleteFolderFromDatabase(folderID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for folder \(folderID)")
            return
        }
        deleteFromDatabase(db, folderID: folderID)
    }

    // Internal for testing
    /// DELETE a folder from the given database by ID.
    func deleteFromDatabase(_ db: CiderDatabase, folderID: UUID) {
        do {
            let stmt = try db.prepare("DELETE FROM folders WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(folderID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete folder \(folderID) from database: \(error.localizedDescription)")
        }
    }

    // Task 13: JSON index persistence removed. SQLite is the primary store;
    // the in-memory `index` is rebuilt on launch by `loadFromDatabase`.
    private func saveIndex() { /* no-op */ }

    private func rebuildFolders() {
        folders = index.values.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    // MARK: - Private: Trash (SQLite-backed)

    private func addToTrashManifest(_ item: TrashItem) {
        TrashStorage.shared.persistTrashItemToDatabase(item)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    private func removeFromTrashManifest(_ itemID: UUID) {
        TrashStorage.shared.deleteTrashItemFromDatabase(itemID)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    /// Returns all trashed vault folders (for Settings → Trash display).
    func trashedFolders() -> [TrashItem] {
        TrashStorage.shared.allTrashItems().filter { $0.itemType == .vaultFolder }
    }

    /// Permanently deletes all trashed vault folders.
    func emptyFolderTrash() {
        let items = trashedFolders()
        let fm = FileManager.default
        for item in items {
            if let payload = item.vaultFolderPayload {
                let trashFolderURL = trashDir.appendingPathComponent(payload.folder.id.uuidString)
                try? fm.removeItem(at: trashFolderURL)
            }
            TrashStorage.shared.deleteTrashItemFromDatabase(item.id)
        }
    }

    // MARK: - Private: Helpers

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: metaDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: coversDir, withIntermediateDirectories: true)
    }

    /// Sanitizes a raw name for use as a directory name.
    static func sanitizeDirectoryName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.replacingOccurrences(of: "\0", with: "")
        // Prevent macOS hidden-file treatment
        while s.hasPrefix(".") { s = String(s.dropFirst()) }
        return s.isEmpty ? "Folder" : s
    }

    /// Resolves name collisions among siblings by appending " 2", " 3", etc.
    private func uniqueName(baseName: String, parentPath: String?, excludingID: UUID? = nil) -> String {
        let siblings = index.values.filter { entry in
            entry.parentRelativePath == parentPath && entry.id != excludingID
        }
        let siblingNames = Set(siblings.map(\.name))

        if !siblingNames.contains(baseName) { return baseName }

        var counter = 2
        while true {
            let candidate = "\(baseName) \(counter)"
            if !siblingNames.contains(candidate) { return candidate }
            counter += 1
        }
    }
}
