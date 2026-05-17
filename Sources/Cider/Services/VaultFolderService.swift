import Combine
import Foundation
import os

/// Manages vault folders as real filesystem directories.
/// Creating/renaming/deleting a folder in Cider creates/renames/deletes
/// the corresponding directory on disk. FSEvents watches for external changes
/// (e.g. user modifies folders in Finder).
@MainActor
final class VaultFolderService: ObservableObject {
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
        MutationAuditService.shared.record(
            action: "create",
            itemType: "vaultFolder",
            itemID: folder.id,
            after: MutationAuditSnapshots.folder(folder)
        )
        return folder
    }

    /// Renames a folder by renaming its directory on disk.
    @discardableResult
    func renameFolder(_ folderID: UUID, to name: String) -> Bool {
        guard let folder = index[folderID] else { return false }
        let before = MutationAuditSnapshots.folder(folder)

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
        if let updatedFolder = index[folderID] {
            MutationAuditService.shared.record(
                action: "rename",
                itemType: "vaultFolder",
                itemID: folderID,
                before: before,
                after: MutationAuditSnapshots.folder(updatedFolder)
            )
        }
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
        let before = MutationAuditSnapshots.folder(folder)

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
        if let updatedFolder = index[folderID] {
            MutationAuditService.shared.record(
                action: "move",
                itemType: "vaultFolder",
                itemID: folderID,
                before: before,
                after: MutationAuditSnapshots.folder(updatedFolder)
            )
        }
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

    /// Sets `sessions.folder_id = NULL` for every browser session referencing
    /// any of the given folder IDs. Sessions live in their own table with
    /// a separate FK from the items table, so the items-table cleanup
    /// doesn't cover them.
    private func unassignSessionsFromFolders(_ folderIDs: [UUID]) {
        guard let db = resolvedDatabase, !folderIDs.isEmpty else { return }
        do {
            let stmt = try db.prepare("UPDATE sessions SET folder_id = NULL WHERE folder_id = ?;")
            for id in folderIDs {
                stmt.reset()
                stmt.bind(DatabaseHelpers.encode(id), at: 1)
                try stmt.step()
            }
        } catch {
            logger.error("unassignSessionsFromFolders: failed to clear folder_id: \(error.localizedDescription)")
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

    /// Result of a folder-delete drain step — one entry per item that was
    /// supposed to be relocated out of the deleted subtree. Used to detect
    /// partial-drain failures BEFORE we trash the folder directory.
    struct DeleteFolderFailure {
        let itemType: String
        let itemID: UUID
        let title: String
    }

    private func drainItemsFromFolders(_ folderIDs: Set<UUID>) -> (relocatedCount: Int, failures: [DeleteFolderFailure]) {
        MutationAuditContext.withSource(.cleanup) {
            var relocatedItemCount = 0
            var failures: [DeleteFolderFailure] = []
            for id in folderIDs {
                // Notes — assignNote returns Bool AND moves .md on disk
                for note in NotesStorage.shared.notes where note.folderID == id {
                    relocatedItemCount += 1
                    let ok = NotesStorage.shared.assignNote(note.id, toFolder: nil)
                    let nowUnfiled = NotesStorage.shared.notes.first(where: { $0.id == note.id })?.folderID == nil
                    if !ok || !nowUnfiled {
                        failures.append(.init(itemType: "note", itemID: note.id, title: note.title))
                    }
                }
                // Bookmarks — assignBookmark returns Bool AND moves .webloc on disk
                for bookmark in VaultBookmarkService.shared.bookmarks where bookmark.folderID == id {
                    relocatedItemCount += 1
                    let ok = VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: nil)
                    let nowUnfiled = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == bookmark.id })?.folderID == nil
                    if !ok || !nowUnfiled {
                        failures.append(.init(itemType: "bookmark", itemID: bookmark.id, title: bookmark.title))
                    }
                }
                // Vault files — assignFile is Void AND moves the file on disk; verify via post-check.
                for file in VaultFileService.shared.files where file.folderID == id {
                    relocatedItemCount += 1
                    VaultFileService.shared.assignFile(file.id, toFolder: nil)
                    let nowUnfiled = VaultFileService.shared.files.first(where: { $0.id == file.id })?.folderID == nil
                    if !nowUnfiled {
                        failures.append(.init(itemType: "vaultFile", itemID: file.id, title: file.displayTitle))
                    }
                }
                // Todos — assignTodoCard returns Bool AND moves the .ics file on disk
                for todo in TodoCardStorage.shared.todoCards where todo.folderID == id {
                    relocatedItemCount += 1
                    let ok = TodoCardStorage.shared.assignTodoCard(todo.id, toFolder: nil)
                    let nowUnfiled = TodoCardStorage.shared.todoCards.first(where: { $0.id == todo.id })?.folderID == nil
                    if !ok || !nowUnfiled {
                        failures.append(.init(itemType: "todo", itemID: todo.id, title: todo.title))
                    }
                }
                // Date cards (events) — assignDateCard returns Bool AND moves the .ics file on disk
                for dc in DateCardStorage.shared.dateCards where dc.folderID == id {
                    relocatedItemCount += 1
                    let ok = DateCardStorage.shared.assignDateCard(dc.id, toFolder: nil)
                    let nowUnfiled = DateCardStorage.shared.dateCards.first(where: { $0.id == dc.id })?.folderID == nil
                    if !ok || !nowUnfiled {
                        failures.append(.init(itemType: "event", itemID: dc.id, title: dc.title))
                    }
                }
                // Contacts — assignContact returns Bool AND moves the .vcf file on disk
                for contact in ContactStorage.shared.contacts where contact.folderID == id {
                    relocatedItemCount += 1
                    let ok = ContactStorage.shared.assignContact(contact.id, toFolder: nil)
                    let nowUnfiled = ContactStorage.shared.contacts.first(where: { $0.id == contact.id })?.folderID == nil
                    if !ok || !nowUnfiled {
                        failures.append(.init(itemType: "contact", itemID: contact.id, title: contact.displayName))
                    }
                }
            }
            return (relocatedItemCount, failures)
        }
    }

    /// Deletes a folder safely:
    ///   1. Enumerate EVERY folder-aware item in the subtree (all 7 types:
    ///      notes, bookmarks, vault files, todos, date cards, contacts,
    ///      browser sessions).
    ///   2. Write a breadcrumb file that records each item's pre-delete
    ///      folder path so `folder restore` can undo the delete.
    ///   3. Relocate every item out via the item services' own
    ///      `assign(..., toFolder: nil)` paths — these physically move
    ///      files on disk AND update SQLite atomically. Verify each
    ///      relocation succeeded by re-checking the in-memory folderID.
    ///   4. If ANY relocation fails, ABORT the delete: do not trash the
    ///      folder, do not delete folder rows, return nil. Already-moved
    ///      items stay in Inbox but no data is lost and the user can
    ///      investigate via the logs. Earlier versions would silently
    ///      cascade the failure, leaving split-brain state.
    ///   5. Scrub DB-only dangling references via SQL (items.folder_id
    ///      and sessions.folder_id) as a defensive fallback.
    ///   6. Move the now-empty folder directory to trash. If the trash
    ///      move fails, STOP — do NOT delete folder rows, because a
    ///      directory-still-on-disk + DB-row-gone combo causes the
    ///      "discovered external folder" reconcile branch to resurrect
    ///      the folder with a fresh UUID on the next FSEvent.
    ///   7. Delete folder rows, update index, notify sync.
    @discardableResult
    func deleteFolder(_ folderID: UUID) -> TrashItem? {
        guard let folder = index[folderID] else { return nil }
        let before = MutationAuditSnapshots.folder(folder)

        let sourceURL = vaultRoot.appendingPathComponent(folder.relativePath)
        let trashDestURL = trashDir.appendingPathComponent(folder.id.uuidString)
        let fm = FileManager.default

        isMutating = true
        defer { isMutating = false }

        // 1. Collect this folder and all descendants FIRST so we know the
        // complete subtree before we start mutating anything.
        let deletedPrefix = folder.relativePath + "/"
        var deletedFolders: [VaultFolder] = [folder]
        for (_, entry) in index where entry.relativePath.hasPrefix(deletedPrefix) {
            deletedFolders.append(entry)
        }
        let deletedFolderIDs = Set(deletedFolders.map(\.id))

        // 2. Write breadcrumbs BEFORE unassigning so we record where each
        // item lived right up to the moment of the delete.
        writeDeleteBreadcrumbs(rootFolder: folder, affectedFolderIDs: deletedFolderIDs)

        // 3. Drain items. Track failures — if any relocation fails,
        // we abort the folder delete entirely so we never trash a
        // directory with live content still inside.
        let drainResult = drainItemsFromFolders(deletedFolderIDs)
        let relocatedItemCount = drainResult.relocatedCount
        let failures = drainResult.failures

        // 4. Abort on any failure — do NOT trash the folder, do NOT delete
        // rows. Items that relocated successfully stay in Inbox; the user
        // can see the partial state in the logs and retry.
        if !failures.isEmpty {
            logger.error("deleteFolder ABORTED: \(failures.count) item(s) failed to relocate out of '\(folder.relativePath)' — folder preserved, DB rows preserved")
            for f in failures {
                logger.error("  failed: \(f.itemType) \(f.itemID.uuidString.prefix(8)) '\(f.title)'")
            }
            return nil
        }

        // 5. Defensive SQL fallback: scrub any dangling folder_id
        // references in `items` AND `sessions` tables. Usually a no-op
        // since the in-memory paths above already cleared them, but
        // catches rows where in-memory service state and DB disagree.
        unassignItemsFromFolders(deletedFolders.map(\.id))
        unassignSessionsFromFolders(deletedFolders.map(\.id))

        // Ensure trash dir exists, and if something with the same ID is
        // already there (rare — duplicate UUID collision), nuke it.
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: trashDestURL.path) {
            try? fm.removeItem(at: trashDestURL)
        }

        // 6. Move the now-empty folder directory to trash. If this fails
        // we must NOT continue — leaving the directory on disk while the
        // folder row is gone from SQLite would let the reconcile's
        // "discovered external folder" branch resurrect it with a fresh
        // UUID on the next FSEvent. Keep both disk and DB consistent.
        do {
            try fm.moveItem(at: sourceURL, to: trashDestURL)
        } catch {
            logger.error("deleteFolder: failed to move empty folder to trash: \(error.localizedDescription) — ABORTING row cleanup to avoid ghost resurrection. Items have been relocated to Inbox; folder '\(folder.relativePath)' is empty on disk.")
            NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
            return nil
        }

        // 7. Remove from index and database
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
        MutationAuditService.shared.record(
            action: "delete",
            itemType: "vaultFolder",
            itemID: folder.id,
            before: before,
            after: MutationAuditSnapshots.trashItem(trashItem),
            metadata: [
                "descendantCount": String(max(0, deletedFolders.count - 1)),
                "relocatedItemCount": String(relocatedItemCount),
            ]
        )
        return trashItem
    }

    // MARK: - Delete Breadcrumbs

    /// One breadcrumb entry per relocated item, written to a JSON file before
    /// the delete runs. Used by `restoreFromDeleteBreadcrumbs` (CLI: `folder restore`).
    struct DeleteBreadcrumb: Codable {
        let folderPath: String      // root folder at time of delete, e.g. "Food/Restaurants/Lynnwood"
        let deletedAt: Date
        let items: [BreadcrumbItem]
    }

    struct BreadcrumbItem: Codable {
        let itemID: UUID
        let itemType: String        // "bookmark" / "note" / "vaultFile"
        let title: String
        let previousFolderPath: String
    }

    private func writeDeleteBreadcrumbs(rootFolder: VaultFolder, affectedFolderIDs: Set<UUID>) {
        var items: [BreadcrumbItem] = []
        let folderPathByID: [UUID: String] = Dictionary(
            uniqueKeysWithValues: index.compactMap { (id, f) in
                affectedFolderIDs.contains(id) ? (id, f.relativePath) : nil
            }
        )
        for note in NotesStorage.shared.notes {
            guard let fid = note.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: note.id, itemType: "note", title: note.title, previousFolderPath: path
            ))
        }
        for bm in VaultBookmarkService.shared.bookmarks {
            guard let fid = bm.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: bm.id, itemType: "bookmark", title: bm.title, previousFolderPath: path
            ))
        }
        for f in VaultFileService.shared.files {
            guard let fid = f.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: f.id, itemType: "vaultFile", title: f.displayTitle, previousFolderPath: path
            ))
        }
        for todo in TodoCardStorage.shared.todoCards {
            guard let fid = todo.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: todo.id, itemType: "todo", title: todo.title, previousFolderPath: path
            ))
        }
        for dc in DateCardStorage.shared.dateCards {
            guard let fid = dc.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: dc.id, itemType: "event", title: dc.title, previousFolderPath: path
            ))
        }
        for contact in ContactStorage.shared.contacts {
            guard let fid = contact.folderID, let path = folderPathByID[fid] else { continue }
            items.append(BreadcrumbItem(
                itemID: contact.id, itemType: "contact", title: contact.displayName, previousFolderPath: path
            ))
        }

        guard !items.isEmpty else { return }

        let breadcrumb = DeleteBreadcrumb(
            folderPath: rootFolder.relativePath,
            deletedAt: Date(),
            items: items
        )

        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let fileURL = trashDir.appendingPathComponent("\(rootFolder.id.uuidString)-breadcrumbs.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(breadcrumb)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Wrote delete breadcrumbs for '\(rootFolder.name)' (\(items.count) items) to \(fileURL.lastPathComponent)")
        } catch {
            logger.error("Failed to write delete breadcrumbs: \(error.localizedDescription)")
        }
    }

    /// Reads the most recent breadcrumb file matching the given folder path
    /// and returns the parsed `DeleteBreadcrumb`. Used by `folder restore`.
    func readLatestDeleteBreadcrumb(forFolderPath folderPath: String) -> DeleteBreadcrumb? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: trashDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var candidates: [(Date, DeleteBreadcrumb)] = []
        for url in entries where url.lastPathComponent.hasSuffix("-breadcrumbs.json") {
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? decoder.decode(DeleteBreadcrumb.self, from: data),
                  parsed.folderPath == folderPath else { continue }
            candidates.append((parsed.deletedAt, parsed))
        }

        return candidates.max(by: { $0.0 < $1.0 })?.1
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
        MutationAuditService.shared.record(
            action: "restore",
            itemType: "vaultFolder",
            itemID: folder.id,
            before: MutationAuditSnapshots.trashItem(trashItem),
            after: MutationAuditSnapshots.folder(restoredFolder)
        )
    }

    // MARK: - Metadata

    @discardableResult
    func setIcon(_ icon: String?, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        let before = MutationAuditSnapshots.folder(folder)
        folder.icon = icon
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        MutationAuditService(database: resolvedDatabase).record(
            action: "set_icon",
            itemType: "vaultFolder",
            itemID: folderID,
            before: before,
            after: MutationAuditSnapshots.folder(folder)
        )
        return true
    }

    @discardableResult
    func setCoverImage(_ imageData: Data, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        let before = MutationAuditSnapshots.folder(folder)

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
        MutationAuditService(database: resolvedDatabase).record(
            action: "set_cover_image",
            itemType: "vaultFolder",
            itemID: folderID,
            before: before,
            after: MutationAuditSnapshots.folder(folder)
        )
        return true
    }

    @discardableResult
    func setCoverImageOffsetY(_ offsetY: Double, for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        let before = MutationAuditSnapshots.folder(folder)
        folder.coverImageOffsetY = offsetY
        folder.updatedAt = Date()
        index[folderID] = folder
        persistFolderToDatabase(folder)
        saveIndex()
        rebuildFolders()
        MutationAuditService(database: resolvedDatabase).record(
            action: "set_cover_offset",
            itemType: "vaultFolder",
            itemID: folderID,
            before: before,
            after: MutationAuditSnapshots.folder(folder)
        )
        return true
    }

    @discardableResult
    func removeCoverImage(for folderID: UUID) -> Bool {
        guard var folder = index[folderID] else { return false }
        let before = MutationAuditSnapshots.folder(folder)
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
        MutationAuditService(database: resolvedDatabase).record(
            action: "remove_cover_image",
            itemType: "vaultFolder",
            itemID: folderID,
            before: before,
            after: MutationAuditSnapshots.folder(folder)
        )
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

        let targetRelativePath = parentPath.map { "\($0)/\(sanitized)" } ?? sanitized
        if let existing = index.values.first(where: { $0.relativePath == targetRelativePath }) {
            var merged = existing
            if merged.icon == nil { merged.icon = icon }
            if updatedAt > merged.updatedAt { merged.updatedAt = updatedAt }
            index[merged.id] = merged
            persistFolderToDatabase(merged)
            saveIndex()
            rebuildFolders()
            logger.warning("Sync: skipped duplicate folder '\(targetRelativePath, privacy: .public)' for remote id \(id.uuidString, privacy: .public); using existing local folder \(merged.id.uuidString, privacy: .public)")
            return merged
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

        let targetParentPath: String?
        if let parentID, parentID != folderID {
            targetParentPath = index[parentID]?.relativePath
        } else {
            targetParentPath = nil
        }

        // Check if name or parent changed — requires directory move.
        let sanitized = Self.sanitizeDirectoryName(name)
        if !sanitized.isEmpty && (sanitized != folder.name || targetParentPath != folder.parentRelativePath) {
            let resolvedName = uniqueName(baseName: sanitized, parentPath: targetParentPath, excludingID: folderID)
            let newRelativePath = targetParentPath.map { "\($0)/\(resolvedName)" } ?? resolvedName
            let oldURL = vaultRoot.appendingPathComponent(folder.relativePath)
            let newURL = vaultRoot.appendingPathComponent(newRelativePath)

            if newRelativePath != folder.relativePath {
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                    rewriteItemPathsAfterMove(oldPrefix: folder.relativePath, newPrefix: newRelativePath)
                } catch {
                    logger.error("updateFolderFromSync: move failed: \(error.localizedDescription)")
                }
            }

            if FileManager.default.fileExists(atPath: newURL.path) || newRelativePath == folder.relativePath {
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
        let before = MutationAuditSnapshots.folder(folder)

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
        let drainResult = drainItemsFromFolders(deletedIDs)
        let relocatedItemCount = drainResult.relocatedCount
        if !drainResult.failures.isEmpty {
            logger.error("deleteFolderFromSync ABORTED: \(drainResult.failures.count) item(s) failed to relocate out of '\(folder.relativePath)' — folder preserved, DB rows preserved")
            for f in drainResult.failures {
                logger.error("  failed: \(f.itemType) \(f.itemID.uuidString.prefix(8)) '\(f.title)'")
            }
            return
        }

        unassignItemsFromFolders(Array(deletedIDs))
        unassignSessionsFromFolders(Array(deletedIDs))

        // Remove directory (contains all sub-folders and filed cards)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                logger.error("deleteFolderFromSync: failed to remove directory: \(error.localizedDescription) — preserving folder rows to avoid filesystem/database drift")
                return
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

        saveIndex()
        rebuildFolders()

        logger.info("Sync: deleted folder '\(folder.name)'")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        MutationAuditContext.withSource(.cleanup) {
            MutationAuditService.shared.record(
                action: "delete",
                itemType: "vaultFolder",
                itemID: folderID,
                before: before,
                after: ["state": "removed_by_sync"],
                metadata: [
                    "reason": "sync_delete",
                    "descendantCount": String(descendantIDs.count),
                    "relocatedItemCount": String(relocatedItemCount),
                ]
            )
        }
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
        //
        // If the reload FAILS (transient DB lock, corruption, etc.), we must
        // NOT run reconcile — stale in-memory state against fresh disk state
        // would let the discovery branch stamp new UUIDs over folders that
        // really do still exist but whose in-memory records are outdated.
        // Skip this event and wait for the next one to retry.
        guard loadIndexFromDatabaseOrJSON() else {
            logger.warning("handleFSEvent: skipping reconcile — DB reload failed, will retry on next event")
            return
        }
        reconcileWithFilesystem()
        // Rescan vault files after folder reconciliation settles.
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

    /// Load folders from SQLite. Returns true if the reload succeeded (or
    /// there was no DB to read from — nothing to do). Returns false only
    /// if a DB read error occurred, in which case callers should skip
    /// reconcile so stale in-memory state doesn't get treated as truth.
    @discardableResult
    private func loadIndexFromDatabaseOrJSON() -> Bool {
        guard let db = resolvedDatabase else { return true }
        return loadFromDatabase(db)
    }

    // Internal for testing
    /// SELECT all folders from the database, ordered by relative_path.
    /// Returns true on success, false on any read error.
    ///
    /// On a DB read error, the in-memory `index` is left ALONE — a
    /// transient SQLite failure must NOT wipe the folder model, because the
    /// next reconcile would then treat every directory on disk as an
    /// "external discovery" and stamp fresh UUIDs over your entire vault.
    /// Keep the stale state, log the error, and signal failure so callers
    /// can skip reconcile until a clean reload succeeds.
    @discardableResult
    func loadFromDatabase(_ db: CiderDatabase) -> Bool {
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
            return true
        } catch {
            logger.error("Failed to load folders from database — keeping stale in-memory state: \(error.localizedDescription)")
            // Intentionally NOT clearing `index` here — see doc comment above.
            return false
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
