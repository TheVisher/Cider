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

    // MARK: - Paths

    private let metaDirName = ".cider/folders"
    private let indexFileName = "index.json"
    private let coversDirName = "covers"
    private let trashDirName = ".trash"
    private let manifestFileName = "_cider_trash_manifest.json"

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private var metaDir: URL {
        vaultRoot.appendingPathComponent(metaDirName)
    }

    private var indexFileURL: URL {
        metaDir.appendingPathComponent(indexFileName)
    }

    private var coversDir: URL {
        metaDir.appendingPathComponent(coversDirName)
    }

    private var trashDir: URL {
        metaDir.appendingPathComponent(trashDirName)
    }

    private var trashManifestURL: URL {
        trashDir.appendingPathComponent(manifestFileName)
    }

    // MARK: - Init

    private init() {
        ensureDirectories()
        loadIndex()
        reconcileWithFilesystem()
        startWatching()
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
            } else if entry.relativePath.hasPrefix(oldPrefix) {
                entry.relativePath = newRelativePath + "/" + entry.relativePath.dropFirst(oldPrefix.count)
                entry.updatedAt = Date()
                index[id] = entry
            }
        }

        saveIndex()
        rebuildFolders()

        logger.info("Renamed folder '\(folder.name)' → '\(resolvedName)'")
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        return true
    }

    /// Deletes a folder by moving its directory to the vault trash.
    /// Returns the TrashItem for undo support.
    @discardableResult
    func deleteFolder(_ folderID: UUID) -> TrashItem? {
        guard let folder = index[folderID] else { return nil }

        let sourceURL = vaultRoot.appendingPathComponent(folder.relativePath)
        let trashDestURL = trashDir.appendingPathComponent(folder.name)
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

        // Remove from index
        for deleted in deletedFolders {
            index.removeValue(forKey: deleted.id)
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
        let trashSourceURL = trashDir.appendingPathComponent(folder.name)
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
                    } else if entry.relativePath.hasPrefix(oldPrefix) {
                        entry.relativePath = newRelativePath + "/" + entry.relativePath.dropFirst(oldPrefix.count)
                        index[id] = entry
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

        // Remove all descendants from index
        let prefix = folder.relativePath + "/"
        let descendantIDs = index.filter { $0.value.relativePath.hasPrefix(prefix) }.map(\.key)
        for id in descendantIDs {
            index.removeValue(forKey: id)
        }
        index.removeValue(forKey: folderID)

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
        watcher = FSEventsWatcher(path: vaultRoot.path) { [weak self] _ in
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
        loadIndex()
        reconcileWithFilesystem()
        startWatching()
        NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
    }

    // MARK: - Private: FSEvents Handling

    private func handleFSEvent() {
        guard !isMutating else { return }
        reconcileWithFilesystem()
        // Reload sidecar metadata and rescan vault files
        SidecarService.shared.loadAll()
        VaultFileService.shared.scan()
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
            logger.info("Discovered external folder: \(diskPath)")
            changed = true
        }

        // Paths in index not on disk → deleted from Finder
        for (id, entry) in index {
            if !diskPaths.contains(entry.relativePath) {
                index.removeValue(forKey: id)
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
            }
        }
    }

    /// Directories that are Cider internals or reserved, not user-created folders.
    /// All StorageType dirs now live inside `.cider/` (hidden, auto-skipped by .skipsHiddenFiles).
    private static let reservedDirectoryNames: Set<String> = ["Inbox", "Unsorted"]

    /// Returns true if the path is a reserved directory that should not appear as a vault folder.
    private func isStorageTypeDirectory(_ relativePath: String) -> Bool {
        let topComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
        return Self.reservedDirectoryNames.contains(topComponent)
    }

    // MARK: - Private: Index Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([UUID: VaultFolder].self, from: data) else {
            index = [:]
            return
        }
        index = decoded
        rebuildFolders()
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }

    private func rebuildFolders() {
        folders = index.values.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    // MARK: - Private: Trash Manifest

    private func addToTrashManifest(_ item: TrashItem) {
        var manifest = loadTrashManifest()
        manifest.insert(item, at: 0)
        saveTrashManifest(manifest)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    private func removeFromTrashManifest(_ itemID: UUID) {
        var manifest = loadTrashManifest()
        manifest.removeAll { $0.id == itemID }
        saveTrashManifest(manifest)
        NotificationCenter.default.post(name: .trashContentsChanged, object: nil)
    }

    private func loadTrashManifest() -> [TrashItem] {
        guard let data = try? Data(contentsOf: trashManifestURL) else { return [] }
        return (try? JSONDecoder().decode([TrashItem].self, from: data)) ?? []
    }

    private func saveTrashManifest(_ items: [TrashItem]) {
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: trashManifestURL, options: .atomic)
    }

    /// Returns all trashed vault folders (for Settings → Trash display).
    func trashedFolders() -> [TrashItem] {
        loadTrashManifest()
    }

    /// Permanently deletes all trashed vault folders.
    func emptyFolderTrash() {
        let items = loadTrashManifest()
        let fm = FileManager.default
        for item in items {
            if let payload = item.vaultFolderPayload {
                let trashFolderURL = trashDir.appendingPathComponent(payload.folder.name)
                try? fm.removeItem(at: trashFolderURL)
            }
        }
        saveTrashManifest([])
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
