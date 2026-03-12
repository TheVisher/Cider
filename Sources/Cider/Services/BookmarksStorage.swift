import AppKit
import Combine
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

private struct BookmarksDiskSnapshot {
    var bookmarks: [Bookmark]
    var folders: [Folder]
}

private struct BookmarksMetadataSnapshot: Codable {
    var bookmarks: [Bookmark]
    var folders: [Folder]
}

private struct BookmarkImageAssets {
    let thumbnailRelativePath: String
    let originalImageRelativePath: String
}

@MainActor
final class BookmarksStorage: ObservableObject {
    static let shared = BookmarksStorage()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var folders: [Folder] = []

    private let legacyDefaultsKey = "CiderBookmarks"
    private let htmlFileName = "bookmarks.html"
    private let metadataFileName = "_cider_bookmarks_metadata.json"
    private let thumbnailsDirectoryName = ".thumbnails"
    private let originalImagesDirectoryName = ".originals"
    private let folderCoversDirectoryName = ".folder-covers"
    private let thumbnailMaxPixelDimension: CGFloat = 720
    private var enrichmentTasks: [UUID: Task<Void, Never>] = [:]

    private var directoryURL: URL

    private init() {
        directoryURL = StoragePaths.directoryURL(for: .bookmarks)
        ensureDirectory()

        // Read files off the main thread; parse and apply on MainActor
        let metaURL = metadataFileURL
        let htmlURL = htmlFileURL
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelAllEnrichmentTasks()

            let (metaData, htmlData) = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: metaURL), try? Data(contentsOf: htmlURL))
            }.value

            if let snapshot = self.buildSnapshotFromFiles(metaData: metaData, htmlData: htmlData) {
                self.bookmarks = snapshot.bookmarks
                self.folders = snapshot.folders
                self.normalizeBookmarkImageAssetsIfNeeded()
                self.scheduleEnrichmentForIncompleteBookmarks()
                self.runBookmarkFileMigrationIfNeeded()
                return
            }

            if let migrated = self.migrateLegacyUserDefaults() {
                self.bookmarks = migrated.bookmarks
                self.folders = migrated.folders
                self.normalizeBookmarkImageAssetsIfNeeded()
                self.persist()
                self.scheduleEnrichmentForIncompleteBookmarks()
                self.runBookmarkFileMigrationIfNeeded()
                return
            }

            self.bookmarks = []
            self.folders = []
        }
    }

    /// Reloads bookmarks and folders from disk. Call after external tools (e.g. AI Chat)
    /// may have modified the JSON files. Reconciles JSON folder UUIDs with VaultFolder UUIDs
    /// so bookmarks appear in the correct sidebar folders.
    func reloadFromDisk() {
        load()
        reconcileJSONFoldersWithVaultFolders()
    }

    /// Maps JSON folder IDs to VaultFolder IDs by matching folder names to directory paths.
    /// External tools (AI Chat) create folders in JSON with their own UUIDs, but the sidebar
    /// uses VaultFolderService UUIDs. This bridges the two by remapping bookmark folderIDs.
    private func reconcileJSONFoldersWithVaultFolders() {
        guard !folders.isEmpty else { return }

        // Build a lookup: JSON folder UUID → relative path (e.g. "Entertainment/Sports")
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var jsonIDToPath: [UUID: String] = [:]
        for folder in folders {
            var pathParts: [String] = [folder.name]
            var current = folder
            while let parentID = current.parentID, let parent = foldersByID[parentID] {
                pathParts.insert(parent.name, at: 0)
                current = parent
            }
            jsonIDToPath[folder.id] = pathParts.joined(separator: "/")
        }

        // Build remap: JSON folder UUID → VaultFolder UUID
        var remap: [UUID: UUID] = [:]
        for (jsonID, relativePath) in jsonIDToPath {
            if let vaultID = VaultFolderService.shared.folderID(for: relativePath),
               vaultID != jsonID {
                remap[jsonID] = vaultID
            }
        }

        guard !remap.isEmpty else { return }

        // Remap bookmark folderIDs
        var changed = false
        for i in bookmarks.indices {
            if let oldID = bookmarks[i].folderID, let newID = remap[oldID] {
                bookmarks[i].folderID = newID
                changed = true
            }
        }

        if changed {
            persist()
        }
    }

    func updateDirectory(to newPath: String) {
        let expanded = NSString(string: newPath).expandingTildeInPath
        let newDirectoryURL = URL(fileURLWithPath: expanded)
        guard newDirectoryURL.path != directoryURL.path else { return }

        let previousBookmarks = bookmarks
        let previousFolders = folders
        let previousDirectoryURL = directoryURL
        directoryURL = newDirectoryURL
        ensureDirectory()
        load()

        if bookmarks.isEmpty, folders.isEmpty, (!previousBookmarks.isEmpty || !previousFolders.isEmpty) {
            bookmarks = previousBookmarks
            folders = previousFolders
            persist()
            copyBookmarkImageAssetsIfNeeded(from: previousDirectoryURL, bookmarks: previousBookmarks)
            normalizeBookmarkImageAssetsIfNeeded()
            scheduleEnrichmentForIncompleteBookmarks()
        }
    }

    @discardableResult
    func importNetscapeHTML(from fileURL: URL) -> Int {
        guard let data = try? Data(contentsOf: fileURL),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return 0
        }

        let entries = NetscapeBookmarksCodec.decode(html)
        guard !entries.isEmpty else { return 0 }

        var importedCount = 0
        for entry in entries {
            let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if add(urlString: entry.urlString, title: title?.isEmpty == true ? nil : title) != nil {
                importedCount += 1
            }
        }

        return importedCount
    }

    func exportNetscapeHTML(to fileURL: URL) throws {
        let html = NetscapeBookmarksCodec.encode(bookmarks)
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func add(urlString: String, title: String?) -> Bookmark? {
        guard let normalizedURL = normalizedURL(from: urlString) else {
            return nil
        }

        let canonical = normalizedURL.absoluteString

        if let existingIndex = bookmarks.firstIndex(where: { $0.urlString.caseInsensitiveCompare(canonical) == .orderedSame }) {
            var existing = bookmarks.remove(at: existingIndex)
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            existing.updatedAt = Date()
            existing.urlString = canonical
            existing.isEnriching = false
            bookmarks.insert(existing, at: 0)
            persist()
            startEnrichmentIfNeeded(for: existing.id)
            return existing
        }

        let resolvedTitle = resolvedTitle(for: normalizedURL, override: title)
        let bookmark = Bookmark(title: resolvedTitle, urlString: canonical)
        bookmarks.insert(bookmark, at: 0)
        persist()
        startEnrichmentIfNeeded(for: bookmark.id)
        return bookmark
    }

    /// Creates a bookmark for a saved image (no URL required).
    func addImageBookmark(title: String) -> Bookmark {
        let bookmark = Bookmark(title: title, urlString: "")
        bookmarks.insert(bookmark, at: 0)
        persist()
        return bookmark
    }

    /// Sets the URL on an existing bookmark (used for image bookmarks that get source context).
    func updateURL(for bookmarkID: UUID, urlString: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].urlString = urlString
        persist()
    }

    @discardableResult
    func remove(_ bookmark: Bookmark) -> TrashItem {
        cancelEnrichment(for: bookmark.id)
        SyncService.shared.trackDeletion(of: bookmark.id)
        let trashItem = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: directoryURL)
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
        return trashItem
    }

    @discardableResult
    func removeAll(_ bookmarksToDelete: [Bookmark]) -> [TrashItem] {
        var trashItems: [TrashItem] = []
        for bookmark in bookmarksToDelete {
            cancelEnrichment(for: bookmark.id)
            SyncService.shared.trackDeletion(of: bookmark.id)
            let item = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: directoryURL)
            trashItems.append(item)
        }
        let ids = Set(bookmarksToDelete.map(\.id))
        bookmarks.removeAll { ids.contains($0.id) }
        persist()
        return trashItems
    }

    func restoreFromTrash(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        var restored = bookmark
        restored.isEnriching = false
        restored.updatedAt = Date()
        SyncService.shared.cancelDeletion(of: bookmark.id)
        bookmarks.insert(restored, at: 0)
        persist()
    }

    // MARK: - Sync helpers (called by SyncService)

    /// Add a bookmark received from the web, using the provided UUID so it stays in sync.
    func addFromSync(
        id: UUID,
        title: String,
        urlString: String,
        notes: String,
        tags: [String],
        thumbnailRemoteURLString: String?,
        aiSummary: String?,
        dominantColors: [String]?,
        createdAt: Date,
        updatedAt: Date,
        folderID: UUID? = nil
    ) {
        guard !bookmarks.contains(where: { $0.id == id }) else { return }

        var bookmark = Bookmark(
            id: id,
            title: title,
            urlString: urlString,
            createdAt: createdAt,
            updatedAt: updatedAt,
            notes: notes,
            tags: tags,
            thumbnailRemoteURLString: thumbnailRemoteURLString,
            aiSummary: aiSummary,
            dominantColors: dominantColors
        )
        bookmark.folderID = folderID
        bookmarks.insert(bookmark, at: 0)
        bookmarks.sort { $0.createdAt > $1.createdAt }
        persist()
        startEnrichmentIfNeeded(for: id)
    }

    /// Update an existing local bookmark with data from the web.
    /// Preserves local enrichment fields (aiSummary, dominantColors) if remote doesn't have them.
    func updateFromSync(
        bookmarkID: UUID,
        title: String,
        urlString: String,
        notes: String,
        tags: [String],
        thumbnailRemoteURLString: String?,
        aiSummary: String?,
        dominantColors: [String]?,
        folderID: UUID? = nil,
        remoteUpdatedAt: Date
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].title = title
        bookmarks[index].urlString = urlString
        bookmarks[index].notes = notes
        bookmarks[index].tags = tags
        bookmarks[index].thumbnailRemoteURLString = thumbnailRemoteURLString
        // Only overwrite enrichment fields if remote actually has them —
        // prevents web edits from wiping desktop-generated AI data
        if let aiSummary { bookmarks[index].aiSummary = aiSummary }
        if let dominantColors { bookmarks[index].dominantColors = dominantColors }
        bookmarks[index].folderID = folderID
        bookmarks[index].updatedAt = remoteUpdatedAt
        persist()

        // If the bookmark has no local thumbnail, kick off enrichment to fetch one
        if bookmarks[index].thumbnailRelativePath == nil {
            startEnrichmentIfNeeded(for: bookmarkID)
        }
    }

    /// Remove a bookmark that was deleted on the web, without trashing it locally.
    func removeSynced(_ bookmark: Bookmark) {
        cancelEnrichment(for: bookmark.id)
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    /// Move a bookmark deleted on the web into the desktop trash (so it can be restored).
    func trashFromSync(_ bookmark: Bookmark) {
        cancelEnrichment(for: bookmark.id)
        _ = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: directoryURL)
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    // MARK: - Folder sync helpers (called by SyncService)

    /// Add a folder received from the web, using the provided UUID so it stays in sync.
    func addFolderFromSync(
        id: UUID,
        name: String,
        icon: String?,
        parentID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        guard !folders.contains(where: { $0.id == id }) else { return }

        let folder = Folder(
            id: id,
            name: name,
            parentID: parentID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            icon: icon
        )
        folders.append(folder)
        folders.sort(by: folderSortOrder)
        persist()
    }

    /// Update an existing local folder with data from the web.
    func updateFolderFromSync(
        folderID: UUID,
        name: String,
        icon: String?,
        parentID: UUID?,
        remoteUpdatedAt: Date
    ) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = name
        folders[index].icon = icon
        folders[index].parentID = parentID
        folders[index].updatedAt = remoteUpdatedAt
        folders.sort(by: folderSortOrder)
        persist()
    }

    /// Delete a folder received from the web (soft delete — unassigns bookmarks, removes subtree).
    func deleteFolderFromSync(_ folderID: UUID) {
        guard folders.contains(where: { $0.id == folderID }) else { return }
        let subtree = folderSubtreeIDs(rootID: folderID)
        folders.removeAll { subtree.contains($0.id) }
        for index in bookmarks.indices {
            guard let assignedFolderID = bookmarks[index].folderID,
                  subtree.contains(assignedFolderID) else {
                continue
            }
            bookmarks[index].folderID = nil
        }
        persist()
    }

    func addFromPasteboard() -> Bookmark? {
        let pasteboard = NSPasteboard.general

        if let string = pasteboard.string(forType: .string) {
            return add(urlString: string, title: nil)
        }

        if let values = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = values.first {
            return add(urlString: first.absoluteString, title: nil)
        }

        return nil
    }

    @discardableResult
    func updateDetails(
        for bookmarkID: UUID,
        title: String,
        notes: String,
        tags: [String],
        labelIDs: [UUID]? = nil,
        urlString: String? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else {
            return false
        }

        var bookmark = bookmarks[index]
        let resolvedURL = URL(string: bookmark.urlString)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitleValue: String
        if normalizedTitle.isEmpty, let resolvedURL {
            resolvedTitleValue = resolvedTitle(for: resolvedURL, override: nil)
        } else if normalizedTitle.isEmpty {
            resolvedTitleValue = bookmark.title
        } else {
            resolvedTitleValue = normalizedTitle
        }

        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTags = deduplicatedTags(from: tags)

        var changed = false
        if bookmark.title != resolvedTitleValue {
            bookmark.title = resolvedTitleValue
            changed = true
        }
        if bookmark.notes != normalizedNotes {
            bookmark.notes = normalizedNotes
            changed = true
        }
        if bookmark.tags != normalizedTags {
            bookmark.tags = normalizedTags
            changed = true
        }
        if let labelIDs, bookmark.labelIDs != labelIDs {
            bookmark.labelIDs = labelIDs
            changed = true
        }
        if let urlString {
            let normalizedSource = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if bookmark.urlString != normalizedSource {
                bookmark.urlString = normalizedSource
                changed = true
            }
        }

        if changed {
            bookmark.updatedAt = Date()
            bookmarks[index] = bookmark
            persist()
        }

        return true
    }

    func previewNormalizedURLString(from rawValue: String) -> String? {
        normalizedURL(from: rawValue)?.absoluteString
    }

    @discardableResult
    func createFolder(name rawName: String, parentID: UUID?) -> Folder? {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        if let parentID, folders.first(where: { $0.id == parentID }) == nil {
            return nil
        }

        let resolvedName = uniqueFolderName(baseName: trimmedName, parentID: parentID)
        let folder = Folder(name: resolvedName, parentID: parentID)
        folders.append(folder)
        folders.sort(by: folderSortOrder)
        persist()
        return folder
    }

    @discardableResult
    func renameFolder(_ folderID: UUID, to rawName: String) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return false
        }

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let parentID = folders[index].parentID
        let resolvedName = uniqueFolderName(
            baseName: trimmedName,
            parentID: parentID,
            excluding: folderID
        )
        guard folders[index].name != resolvedName else { return true }

        folders[index].name = resolvedName
        folders[index].updatedAt = Date()
        folders.sort(by: folderSortOrder)
        persist()
        return true
    }

    @discardableResult
    func setFolderIcon(_ folderID: UUID, icon: String?) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return false }
        folders[index].icon = icon
        folders[index].updatedAt = Date()
        persist()
        return true
    }

    @discardableResult
    func deleteFolder(_ folderID: UUID) -> Bool {
        guard folders.contains(where: { $0.id == folderID }) else { return false }

        let subtree = folderSubtreeIDs(rootID: folderID)
        guard !subtree.isEmpty else { return false }

        // Track deletions for sync (all folders in subtree)
        for id in subtree {
            SyncService.shared.trackFolderDeletion(of: id)
        }

        folders.removeAll { subtree.contains($0.id) }
        for index in bookmarks.indices {
            guard let assignedFolderID = bookmarks[index].folderID,
                  subtree.contains(assignedFolderID) else {
                continue
            }
            bookmarks[index].folderID = nil
            bookmarks[index].updatedAt = Date()
        }
        persist()
        return true
    }

    @discardableResult
    func assignBookmark(_ bookmarkID: UUID, toFolder folderID: UUID?) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else {
            return false
        }

        if let folderID,
           folders.first(where: { $0.id == folderID }) == nil,
           VaultFolderService.shared.folder(for: folderID) == nil {
            return false
        }

        if bookmarks[index].folderID == folderID {
            return true
        }

        bookmarks[index].folderID = folderID
        bookmarks[index].updatedAt = Date()
        persist()
        return true
    }

    @discardableResult
    func assignLabel(_ bookmarkID: UUID, labelID: UUID) -> Bool {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        guard !bookmarks[idx].labelIDs.contains(labelID) else { return true }
        bookmarks[idx].labelIDs.append(labelID)
        persist()
        return true
    }

    @discardableResult
    func removeLabel(_ bookmarkID: UUID, labelID: UUID) -> Bool {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        bookmarks[idx].labelIDs.removeAll { $0 == labelID }
        if !bookmarks[idx].dismissedLabelIDs.contains(labelID) {
            bookmarks[idx].dismissedLabelIDs.append(labelID)
        }
        persist()
        return true
    }

    func removeLabelsFromAll(labelID: UUID) {
        var changed = false
        for i in bookmarks.indices where bookmarks[i].labelIDs.contains(labelID) {
            bookmarks[i].labelIDs.removeAll { $0 == labelID }
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Folder Cover Images

    private var folderCoversDirectoryURL: URL {
        directoryURL.appendingPathComponent(folderCoversDirectoryName, isDirectory: true)
    }

    @discardableResult
    func setFolderCoverImage(_ folderID: UUID, imageData: Data) -> Bool {
        guard NSImage(data: imageData) != nil else { return false }

        let filename = "\(folderID.uuidString).jpg"
        let relativePath = "\(folderCoversDirectoryName)/\(filename)"
        let fileURL = directoryURL.appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(
                at: folderCoversDirectoryURL,
                withIntermediateDirectories: true
            )
            deleteExistingFolderCoverFiles(for: folderID)
            try imageData.write(to: fileURL, options: .atomic)

            if let idx = folders.firstIndex(where: { $0.id == folderID }) {
                folders[idx].coverImagePath = relativePath
                folders[idx].updatedAt = Date()
                persist()
            }
            return true
        } catch {
            return false
        }
    }

    func setFolderCoverOffset(_ folderID: UUID, offsetY: Double) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].coverImageOffsetY = offsetY
        folders[idx].updatedAt = Date()
        persist()
    }

    func removeFolderCoverImage(_ folderID: UUID) {
        deleteExistingFolderCoverFiles(for: folderID)
        if let idx = folders.firstIndex(where: { $0.id == folderID }) {
            folders[idx].coverImagePath = nil
            folders[idx].updatedAt = Date()
            persist()
        }
    }

    func folderCoverImageURL(for folder: Folder) -> URL? {
        guard let path = folder.coverImagePath else { return nil }
        let url = directoryURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func deleteExistingFolderCoverFiles(for folderID: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folderCoversDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        let prefix = folderID.uuidString + "."
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
        }
    }

    @discardableResult
    func assignThumbnail(for bookmarkID: UUID, fromDroppedString rawValue: String) async -> Bool {
        guard let candidate = extractedURLCandidate(from: rawValue) else { return false }
        let sourceURL: URL
        if let direct = URL(string: candidate), direct.scheme != nil {
            sourceURL = direct
        } else if candidate.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: candidate)
        } else if let withHTTPS = URL(string: "https://\(candidate)") {
            sourceURL = withHTTPS
        } else {
            return false
        }

        if sourceURL.isFileURL {
            return assignThumbnail(for: bookmarkID, fromLocalFileURL: sourceURL)
        }

        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        guard let assets = await cacheImageAssets(from: sourceURL, for: bookmarkID) else {
            return false
        }

        return applyManualThumbnail(
            for: bookmarkID,
            assets: assets,
            remoteURLString: sourceURL.absoluteString
        )
    }

    @discardableResult
    func assignThumbnail(for bookmarkID: UUID, fromLocalFileURL fileURL: URL) -> Bool {
        guard fileURL.isFileURL else { return false }
        guard let data = try? Data(contentsOf: fileURL) else { return false }

        return assignThumbnail(
            for: bookmarkID,
            imageData: data,
            preferredFileExtension: fileURL.pathExtension
        )
    }

    @discardableResult
    func assignThumbnail(
        for bookmarkID: UUID,
        imageData: Data,
        preferredFileExtension: String? = nil
    ) -> Bool {
        guard let assets = cacheImageAssets(
            from: imageData,
            for: bookmarkID,
            preferredFileExtension: preferredFileExtension
        ) else {
            return false
        }

        return applyManualThumbnail(
            for: bookmarkID,
            assets: assets,
            remoteURLString: nil
        )
    }

    private var htmlFileURL: URL {
        directoryURL.appendingPathComponent(htmlFileName)
    }

    private var metadataFileURL: URL {
        directoryURL.appendingPathComponent(metadataFileName)
    }

    private var thumbnailsDirectoryURL: URL {
        directoryURL.appendingPathComponent(thumbnailsDirectoryName, isDirectory: true)
    }

    private var originalImagesDirectoryURL: URL {
        directoryURL.appendingPathComponent(originalImagesDirectoryName, isDirectory: true)
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: thumbnailsDirectoryURL.path) {
            try? fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: originalImagesDirectoryURL.path) {
            try? fm.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func load() {
        cancelAllEnrichmentTasks()

        if let loaded = loadFromDisk() {
            bookmarks = loaded.bookmarks
            folders = loaded.folders
            normalizeBookmarkImageAssetsIfNeeded()
            scheduleEnrichmentForIncompleteBookmarks()
            return
        }

        if let migrated = migrateLegacyUserDefaults() {
            bookmarks = migrated.bookmarks
            folders = migrated.folders
            normalizeBookmarkImageAssetsIfNeeded()
            persist()
            scheduleEnrichmentForIncompleteBookmarks()
            return
        }

        bookmarks = []
        folders = []
    }

    private func loadFromDisk() -> BookmarksDiskSnapshot? {
        let metadataSnapshot = loadMetadataSnapshot()
        let metadataFolders = sanitizedFolders(from: metadataSnapshot.folders)
        let metadataBookmarks = sanitizedBookmarks(
            from: metadataSnapshot.bookmarks,
            validFolderIDs: Set(metadataFolders.map(\.id))
        )
        let metadataByURL = Dictionary(
            metadataBookmarks
                .filter { !$0.urlString.isEmpty }
                .map { ($0.urlString.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        guard let htmlData = try? Data(contentsOf: htmlFileURL),
              let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) else {
            if metadataBookmarks.isEmpty, metadataFolders.isEmpty {
                return nil
            }
            return BookmarksDiskSnapshot(
                bookmarks: metadataBookmarks.sorted { $0.createdAt > $1.createdAt },
                folders: metadataFolders
            )
        }

        let entries = NetscapeBookmarksCodec.decode(html)
        if entries.isEmpty {
            if metadataBookmarks.isEmpty, metadataFolders.isEmpty {
                return BookmarksDiskSnapshot(bookmarks: [], folders: [])
            }
            return BookmarksDiskSnapshot(
                bookmarks: metadataBookmarks.sorted { $0.createdAt > $1.createdAt },
                folders: metadataFolders
            )
        }

        let loadedBookmarks = deduplicatedBookmarks(from: entries, metadataByURL: metadataByURL)

        // Append metadata-only bookmarks that have no URL (e.g. image bookmarks).
        // These aren't represented in the HTML file so they'd be lost without this.
        let loadedIDs = Set(loadedBookmarks.map(\.id))
        var allBookmarks = loadedBookmarks
        for meta in metadataBookmarks where meta.urlString.isEmpty && !loadedIDs.contains(meta.id) {
            allBookmarks.append(meta)
        }

        let sanitizedLoaded = sanitizedBookmarks(
            from: allBookmarks,
            validFolderIDs: Set(metadataFolders.map(\.id))
        )
        return BookmarksDiskSnapshot(
            bookmarks: sanitizedLoaded,
            folders: metadataFolders
        )
    }

    private func buildSnapshotFromFiles(metaData: Data?, htmlData: Data?) -> BookmarksDiskSnapshot? {
        let metadataSnapshot: BookmarksMetadataSnapshot
        if let data = metaData {
            do {
                metadataSnapshot = try JSONDecoder().decode(BookmarksMetadataSnapshot.self, from: data)
            } catch {
                do {
                    // Legacy metadata format before folders support.
                    let bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
                    metadataSnapshot = BookmarksMetadataSnapshot(bookmarks: bookmarks, folders: [])
                } catch {
                    NSLog("[BookmarksStorage] Failed to decode metadata: \(error)")
                    metadataSnapshot = BookmarksMetadataSnapshot(bookmarks: [], folders: [])
                }
            }
        } else {
            metadataSnapshot = BookmarksMetadataSnapshot(bookmarks: [], folders: [])
        }

        let metadataFolders = sanitizedFolders(from: metadataSnapshot.folders)
        let metadataBookmarks = sanitizedBookmarks(
            from: metadataSnapshot.bookmarks,
            validFolderIDs: Set(metadataFolders.map(\.id))
        )
        let metadataByURL = Dictionary(
            metadataBookmarks
                .filter { !$0.urlString.isEmpty }
                .map { ($0.urlString.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        guard let htmlData,
              let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) else {
            if metadataBookmarks.isEmpty, metadataFolders.isEmpty {
                return nil
            }
            return BookmarksDiskSnapshot(
                bookmarks: metadataBookmarks.sorted { $0.createdAt > $1.createdAt },
                folders: metadataFolders
            )
        }

        let entries = NetscapeBookmarksCodec.decode(html)
        if entries.isEmpty {
            if metadataBookmarks.isEmpty, metadataFolders.isEmpty {
                return BookmarksDiskSnapshot(bookmarks: [], folders: [])
            }
            return BookmarksDiskSnapshot(
                bookmarks: metadataBookmarks.sorted { $0.createdAt > $1.createdAt },
                folders: metadataFolders
            )
        }

        let loadedBookmarks = deduplicatedBookmarks(from: entries, metadataByURL: metadataByURL)

        // Append metadata-only bookmarks that have no URL (e.g. image bookmarks).
        let loadedIDs = Set(loadedBookmarks.map(\.id))
        var allBookmarks = loadedBookmarks
        for meta in metadataBookmarks where meta.urlString.isEmpty && !loadedIDs.contains(meta.id) {
            allBookmarks.append(meta)
        }

        let sanitizedLoaded = sanitizedBookmarks(
            from: allBookmarks,
            validFolderIDs: Set(metadataFolders.map(\.id))
        )
        return BookmarksDiskSnapshot(
            bookmarks: sanitizedLoaded,
            folders: metadataFolders
        )
    }

    /// Parse HTML entries into bookmarks, skipping duplicate URLs.
    /// First occurrence of each URL wins; metadata is merged from `metadataByURL`.
    private func deduplicatedBookmarks(
        from entries: [NetscapeBookmarksCodec.Entry],
        metadataByURL: [String: Bookmark]
    ) -> [Bookmark] {
        var result: [Bookmark] = []
        result.reserveCapacity(entries.count)
        var seenURLs = Set<String>()

        for entry in entries {
            guard let normalized = normalizedURL(from: entry.urlString) else { continue }
            let canonical = normalized.absoluteString
            let key = canonical.lowercased()

            // Skip duplicate URLs in the HTML file
            guard seenURLs.insert(key).inserted else { continue }

            var bookmark = metadataByURL[key] ?? Bookmark(
                title: resolvedTitle(for: normalized, override: entry.title),
                urlString: canonical
            )
            bookmark.urlString = canonical

            if let rawTitle = entry.title {
                let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    bookmark.title = trimmed
                }
            }
            if bookmark.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                bookmark.title = resolvedTitle(for: normalized, override: nil)
            }

            if let addDate = entry.addDate {
                bookmark.createdAt = addDate
            }
            if let modifiedDate = entry.lastModified {
                bookmark.updatedAt = max(bookmark.updatedAt, modifiedDate)
            }

            result.append(bookmark)
        }

        return result
    }

    private func loadMetadataSnapshot() -> BookmarksMetadataSnapshot {
        guard let data = try? Data(contentsOf: metadataFileURL) else {
            return BookmarksMetadataSnapshot(bookmarks: [], folders: [])
        }

        do {
            return try JSONDecoder().decode(BookmarksMetadataSnapshot.self, from: data)
        } catch {
            do {
                // Legacy metadata format before folders support.
                let bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
                return BookmarksMetadataSnapshot(bookmarks: bookmarks, folders: [])
            } catch {
                NSLog("[BookmarksStorage] Failed to decode metadata: \(error)")
                return BookmarksMetadataSnapshot(bookmarks: [], folders: [])
            }
        }
    }

    private func migrateLegacyUserDefaults() -> BookmarksDiskSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey) else {
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode([Bookmark].self, from: data)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return BookmarksDiskSnapshot(
                bookmarks: decoded.sorted { $0.createdAt > $1.createdAt },
                folders: []
            )
        } catch {
            NSLog("[BookmarksStorage] Failed to migrate legacy bookmarks: \(error)")
            return nil
        }
    }

    private func persist() {
        do {
            let html = NetscapeBookmarksCodec.encode(bookmarks)
            try html.write(to: htmlFileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[BookmarksStorage] Failed to write bookmarks HTML: \(error)")
        }

        do {
            let snapshot = BookmarksMetadataSnapshot(bookmarks: bookmarks, folders: folders)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: metadataFileURL, options: .atomic)
        } catch {
            NSLog("[BookmarksStorage] Failed to write bookmarks metadata: \(error)")
        }

        SyncService.shared.pushAfterLocalChange()

        // Dual-write: also update .webloc files + sidecars if migration has run
        if CiderConfig.load().didMigrateBookmarkFiles {
            persistBookmarkFiles()
        }
    }

    // MARK: - File-based persistence (dual-write)

    /// Writes all bookmarks as .webloc files + per-folder sidecars alongside the monolithic JSON.
    /// Only creates new .webloc files for bookmarks that don't already have one on disk.
    /// Always rewrites sidecar JSON to keep it in sync.
    private func persistBookmarkFiles() {
        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        let fileService = BookmarkFileService.shared
        let fm = FileManager.default

        // Group bookmarks by their target directory
        var byDirectory: [String: [(Bookmark, String)]] = [:] // dirRelativePath → [(bookmark, filename)]

        for var bookmark in bookmarks {
            let (dirURL, dirRelativePath) = resolveBookmarkDirectory(bookmark.folderID, vaultRoot: vaultRoot)

            // Determine filename
            let baseName = fileService.sanitizedFilename(bookmark.title.isEmpty ? "Untitled" : bookmark.title)
            let filename: String

            if let existingPath = bookmark.relativePath,
               !existingPath.isEmpty,
               fm.fileExists(atPath: vaultRoot.appendingPathComponent(existingPath).path) {
                // Use existing file
                filename = (existingPath as NSString).lastPathComponent
            } else {
                // Create new .webloc file
                let newFilename = fileService.uniqueFilename(for: baseName, extension: "webloc", in: dirURL)
                let fileURL = dirURL.appendingPathComponent(newFilename)

                if bookmark.hasURL, let url = bookmark.url {
                    let plist: [String: String] = ["URL": url.absoluteString]
                    if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
                filename = newFilename

                // Update relativePath on the in-memory bookmark
                let relativePath = dirRelativePath.isEmpty ? filename : "\(dirRelativePath)/\(filename)"
                if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                    bookmarks[idx].relativePath = relativePath
                }
                bookmark.relativePath = relativePath
            }

            byDirectory[dirRelativePath, default: []].append((bookmark, filename))
        }

        // Write sidecar JSON for each directory (one atomic write per folder)
        for (dirRelativePath, entries) in byDirectory {
            let dirURL = dirRelativePath.isEmpty
                ? vaultRoot
                : vaultRoot.appendingPathComponent(dirRelativePath)

            var sidecar = BookmarkFileService.BookmarkFolderSidecar()
            for (bookmark, filename) in entries {
                sidecar.items[filename] = fileService.sidecarEntry(from: bookmark)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(sidecar) {
                let sidecarURL = dirURL.appendingPathComponent(BookmarkFileService.sidecarFileName)
                try? data.write(to: sidecarURL, options: .atomic)
            }
        }
    }

    /// Maps a folderID to a vault directory URL and its relative path.
    private func resolveBookmarkDirectory(_ folderID: UUID?, vaultRoot: URL) -> (URL, String) {
        if let folderID {
            // Try VaultFolder (real directory)
            if let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
                let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                return (dirURL, vaultFolder.relativePath)
            }
            // Try legacy Folder → match to VaultFolder by name
            if let legacyFolder = folders.first(where: { $0.id == folderID }) {
                let name = VaultFolderService.sanitizeDirectoryName(legacyFolder.name)
                if let vaultFolder = VaultFolderService.shared.folders.first(where: { $0.relativePath == name }) {
                    let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                    return (dirURL, vaultFolder.relativePath)
                }
            }
        }
        // Default: Inbox/Bookmarks/ directory (visible to user in Finder)
        let inboxPath = "\(StoragePaths.inboxDir)/\(StorageType.bookmarks.inboxSubfolderName ?? "Bookmarks")"
        let dirURL = vaultRoot.appendingPathComponent(inboxPath)
        return (dirURL, inboxPath)
    }

    // MARK: - One-time migration

    /// Runs the one-time migration from monolithic JSON to individual .webloc files.
    /// Creates vault directories for legacy folders, writes .webloc + sidecar for each bookmark,
    /// and sets the migration flag so it doesn't run again.
    func runBookmarkFileMigrationIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateBookmarkFiles else { return }
        guard !bookmarks.isEmpty else {
            config.didMigrateBookmarkFiles = true
            config.save()
            return
        }

        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Cider",
            category: "BookmarkFileMigration"
        )
        logger.info("Starting bookmark file migration for \(self.bookmarks.count) bookmarks…")

        let vaultRoot = StoragePaths.cachedVaultDirectoryURL
        let fm = FileManager.default

        // Step 1: Ensure vault directories exist for legacy folders
        for folder in folders {
            let name = VaultFolderService.sanitizeDirectoryName(folder.name)
            guard !name.isEmpty else { continue }
            let dirURL = vaultRoot.appendingPathComponent(name)
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }

        // VaultFolderService will pick up new directories via FSEvents automatically

        // Step 2: Write .webloc + sidecar for all bookmarks
        persistBookmarkFiles()

        // Step 3: Set migration flag
        config.didMigrateBookmarkFiles = true
        config.save()

        let fileCount = bookmarks.filter { $0.relativePath != nil }.count
        logger.info("Bookmark file migration complete: \(fileCount) files written")
    }

    private func cancelAllEnrichmentTasks() {
        for task in enrichmentTasks.values {
            task.cancel()
        }
        enrichmentTasks.removeAll()
    }

    private func cancelEnrichment(for bookmarkID: UUID) {
        enrichmentTasks[bookmarkID]?.cancel()
        enrichmentTasks.removeValue(forKey: bookmarkID)
    }

    private func scheduleEnrichmentForIncompleteBookmarks() {
        for bookmark in bookmarks {
            startEnrichmentIfNeeded(for: bookmark.id)
        }
        recoverMissingThumbnails()
    }

    /// Downloads thumbnails for bookmarks that have a known remote URL but no local file.
    /// This handles cases where the image download previously failed or the local cache was lost.
    /// Runs independently of the normal enrichment pipeline (no retry throttling).
    private func recoverMissingThumbnails() {
        let candidates = bookmarks.filter { bookmark in
            guard let remoteURLString = bookmark.thumbnailRemoteURLString,
                  URL(string: remoteURLString) != nil else { return false }
            return !localThumbnailExists(relativePath: bookmark.thumbnailRelativePath)
        }

        guard !candidates.isEmpty else { return }
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cider", category: "ThumbnailRecovery")
        logger.info("Recovering missing thumbnails for \(candidates.count) bookmark(s)")

        for bookmark in candidates {
            guard enrichmentTasks[bookmark.id] == nil,
                  let remoteURLString = bookmark.thumbnailRemoteURLString,
                  let remoteURL = URL(string: remoteURLString) else { continue }

            let bookmarkID = bookmark.id
            let task = Task { [weak self] in
                guard let self else { return }
                let imageAssets = await self.cacheImageAssets(from: remoteURL, for: bookmarkID)
                await self.applyRecoveredThumbnail(bookmarkID: bookmarkID, imageAssets: imageAssets)
            }
            enrichmentTasks[bookmarkID] = task
        }
    }

    /// Applies a recovered thumbnail without re-running the full enrichment pipeline.
    private func applyRecoveredThumbnail(bookmarkID: UUID, imageAssets: BookmarkImageAssets?) async {
        defer { enrichmentTasks.removeValue(forKey: bookmarkID) }

        guard let imageAssets,
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }

        removeImageIfPresent(relativePath: bookmarks[index].thumbnailRelativePath)
        removeImageIfPresent(relativePath: bookmarks[index].originalImageRelativePath)

        bookmarks[index].thumbnailRelativePath = imageAssets.thumbnailRelativePath
        bookmarks[index].originalImageRelativePath = imageAssets.originalImageRelativePath

        // Fix stored http:// URLs to https:// so future downloads don't hit ATS again
        if let remoteURL = bookmarks[index].thumbnailRemoteURLString,
           remoteURL.hasPrefix("http://") {
            bookmarks[index].thumbnailRemoteURLString = "https://" + remoteURL.dropFirst(7)
        }

        bookmarks[index].updatedAt = Date()

        persist()
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cider", category: "ThumbnailRecovery")
        logger.info("Recovered thumbnail for bookmark \(bookmarkID)")
    }

    private func startEnrichmentIfNeeded(for bookmarkID: UUID, force: Bool = false) {
        guard enrichmentTasks[bookmarkID] == nil else { return }
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard let url = URL(string: bookmarks[index].urlString) else { return }

        let bookmark = bookmarks[index]
        guard force || shouldEnrich(bookmark, for: url) else { return }

        bookmarks[index].isEnriching = true
        objectWillChange.send()

        let task = Task { [weak self] in
            guard let self else { return }

            // Direct image URL — skip HTML parsing and download image as-is
            if Self.isDirectImageURL(url) {
                let imageAssets = await self.cacheImageAssets(from: url, for: bookmarkID)
                await self.completeEnrichment(
                    for: bookmarkID,
                    sourceURL: url,
                    payload: nil,
                    imageAssets: imageAssets
                )
                return
            }

            let payload = await Self.fetchEnrichmentPayload(for: url)

            var imageAssets: BookmarkImageAssets?
            if let thumbnailURL = payload?.thumbnailURL {
                imageAssets = await self.cacheImageAssets(from: thumbnailURL, for: bookmarkID, pageURL: url)
            }

            // Screenshot fallback — if og:image download failed but we have a page screenshot
            if imageAssets == nil, let screenshotData = payload?.screenshotData {
                imageAssets = self.cacheImageAssets(
                    from: screenshotData,
                    for: bookmarkID,
                    preferredFileExtension: "jpg"
                )
            }

            await self.completeEnrichment(
                for: bookmarkID,
                sourceURL: url,
                payload: payload,
                imageAssets: imageAssets
            )
        }

        enrichmentTasks[bookmarkID] = task
    }

    /// Force re-fetch metadata and thumbnail from the web for a bookmark.
    func refetchMetadata(for bookmarkID: UUID) {
        cancelEnrichment(for: bookmarkID)
        startEnrichmentIfNeeded(for: bookmarkID, force: true)
    }

    private func completeEnrichment(
        for bookmarkID: UUID,
        sourceURL: URL,
        payload: BookmarkEnrichmentPayload?,
        imageAssets: BookmarkImageAssets?
    ) async {
        defer { enrichmentTasks.removeValue(forKey: bookmarkID) }

        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }

        var bookmark = bookmarks[index]
        var changed = false

        if let enrichedTitle = payload?.title,
           shouldApplyEnrichedTitle(enrichedTitle, to: bookmark, sourceURL: sourceURL) {
            bookmark.title = enrichedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            changed = true
        }

        if let imageAssets {
            if bookmark.thumbnailRelativePath != imageAssets.thumbnailRelativePath {
                removeImageIfPresent(relativePath: bookmark.thumbnailRelativePath)
                bookmark.thumbnailRelativePath = imageAssets.thumbnailRelativePath
                changed = true
            }

            if bookmark.originalImageRelativePath != imageAssets.originalImageRelativePath {
                removeImageIfPresent(relativePath: bookmark.originalImageRelativePath)
                bookmark.originalImageRelativePath = imageAssets.originalImageRelativePath
                changed = true
            }

            if let remoteURL = payload?.thumbnailURL?.absoluteString,
               bookmark.thumbnailRemoteURLString != remoteURL {
                bookmark.thumbnailRemoteURLString = remoteURL
                changed = true
            }
        }

        bookmark.isEnriching = false
        bookmark.metadataUpdatedAt = Date()
        if changed {
            bookmark.updatedAt = Date()
        }

        bookmarks[index] = bookmark

        if changed {
            persist()
        } else {
            objectWillChange.send()
        }

        // Schedule AI enrichment after metadata + thumbnail are ready
        BookmarkAIEnrichment.shared.schedule(for: bookmarks[index])
    }

    private func shouldEnrich(_ bookmark: Bookmark, for url: URL) -> Bool {
        let needsTitle = isHostDerivedTitle(bookmark, sourceURL: url)
            || bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hasLocalThumbnail = localThumbnailExists(relativePath: bookmark.thumbnailRelativePath)
        let needsThumbnail = !hasLocalThumbnail
        guard needsTitle || needsThumbnail else { return false }

        guard let metadataUpdatedAt = bookmark.metadataUpdatedAt else {
            return true
        }

        let elapsed = Date().timeIntervalSince(metadataUpdatedAt)
        let retryInterval = enrichmentRetryInterval(for: bookmark, sourceURL: url)
        return elapsed >= retryInterval
    }

    private func enrichmentRetryInterval(for bookmark: Bookmark, sourceURL: URL) -> TimeInterval {
        let host = normalizedHost(from: sourceURL)
        let age = Date().timeIntervalSince(bookmark.createdAt)
        let isHighChurnSite = host.contains("reddit.com")
            || host == "x.com"
            || host == "twitter.com"
            || host.contains("tiktok.com")

        if isHighChurnSite {
            if age < EnrichmentRetryThresholds.firstHour {
                return EnrichmentRetryThresholds.socialEarly
            }
            return EnrichmentRetryThresholds.socialSteady
        }

        if bookmark.thumbnailRemoteURLString == nil {
            if age < EnrichmentRetryThresholds.firstHour {
                return EnrichmentRetryThresholds.noThumbnailEarly
            }
            return EnrichmentRetryThresholds.noThumbnailSteady
        }

        return EnrichmentRetryThresholds.defaultSteady
    }

    private func normalizedHost(from url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        if host.hasPrefix("m.") {
            return String(host.dropFirst(2))
        }
        return host
    }

    private func shouldApplyEnrichedTitle(_ title: String, to bookmark: Bookmark, sourceURL: URL) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if bookmark.title.caseInsensitiveCompare(normalized) == .orderedSame { return false }

        let currentTitle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentTitle.isEmpty { return true }
        if currentTitle.caseInsensitiveCompare(bookmark.urlString) == .orderedSame { return true }
        return isHostDerivedTitle(bookmark, sourceURL: sourceURL)
    }

    private func isHostDerivedTitle(_ bookmark: Bookmark, sourceURL: URL) -> Bool {
        let current = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return true }
        let hostTitle = resolvedTitle(for: sourceURL, override: nil)
        return current.caseInsensitiveCompare(hostTitle) == .orderedSame
    }

    private func localThumbnailExists(relativePath: String?) -> Bool {
        localImageExists(relativePath: relativePath)
    }

    private func localImageExists(relativePath: String?) -> Bool {
        guard let relativePath, !relativePath.isEmpty else { return false }
        let url = directoryURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func removeImageIfPresent(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        let fileURL = directoryURL.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func removeBookmarkImageAssetsIfPresent(for bookmark: Bookmark) {
        removeImageIfPresent(relativePath: bookmark.thumbnailRelativePath)
        removeImageIfPresent(relativePath: bookmark.originalImageRelativePath)
        if let carouselPaths = bookmark.carouselImagePaths {
            for path in carouselPaths {
                removeImageIfPresent(relativePath: path)
            }
        }
    }

    private func cacheImageAssets(from remoteURL: URL, for bookmarkID: UUID, pageURL: URL? = nil) async -> BookmarkImageAssets? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")

        // If the thumbnail URL is .webp, try the .gif variant first (works for Giphy, Tenor, Imgur, most CDNs)
        if remoteURL.pathExtension.lowercased() == "webp" {
            let gifURL = remoteURL.deletingPathExtension().appendingPathExtension("gif")
            if let gifAssets = await downloadImageAssets(from: gifURL, for: bookmarkID, pageURL: pageURL) {
                enrichLog.info("Found GIF variant at \(gifURL.lastPathComponent, privacy: .public) for \(remoteURL.host ?? "?", privacy: .public)")
                return gifAssets
            }
        }

        return await downloadImageAssets(from: remoteURL, for: bookmarkID, pageURL: pageURL)
    }

    private func downloadImageAssets(from remoteURL: URL, for bookmarkID: UUID, pageURL: URL? = nil) async -> BookmarkImageAssets? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")

        // Upgrade http:// → https:// to satisfy App Transport Security.
        // Most CDNs support HTTPS even when og:image tags specify HTTP.
        var downloadURL = remoteURL
        if var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false),
           components.scheme == "http" {
            components.scheme = "https"
            if let upgraded = components.url {
                downloadURL = upgraded
            }
        }

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 8
        Self.applyBrowserHeaders(&request)
        request.setValue("image/gif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let pageURL {
            request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return nil
            }
            enrichLog.info("Image download \(remoteURL.host ?? "?", privacy: .public): HTTP \(code), \(data.count) bytes")
            let fileExtension = inferredImageFileExtension(response: response, remoteURL: remoteURL)
            return cacheImageAssets(
                from: data,
                for: bookmarkID,
                preferredFileExtension: fileExtension
            )
        } catch {
            enrichLog.warning("Image download error \(remoteURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cacheImageAssets(
        from data: Data,
        for bookmarkID: UUID,
        preferredFileExtension: String?
    ) -> BookmarkImageAssets? {
        guard data.count > 128, data.count < 12_000_000 else { return nil }
        guard NSImage(data: data) != nil else { return nil }

        // Detect animated images: GIF magic bytes, file extension, or multi-frame image data
        let isAnimated = preferredFileExtension?.lowercased() == "gif"
            || Self.isGIFData(data)
            || Self.isAnimatedImageData(data)
        if isAnimated {
            setMediaType(.gif, for: bookmarkID)
        }

        return persistImageAssets(
            for: bookmarkID,
            sourceData: data,
            preferredFileExtension: isAnimated ? (Self.isGIFData(data) ? "gif" : preferredFileExtension) : preferredFileExtension
        )
    }

    /// Returns true if the URL points directly to an image file (by extension).
    private static func isDirectImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["gif", "png", "jpg", "jpeg", "webp", "heic", "avif", "bmp", "tiff", "ico"].contains(ext)
    }

    private static func isGIFData(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        // GIF87a or GIF89a magic bytes
        let header = data.prefix(6)
        return header.elementsEqual([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])  // GIF87a
            || header.elementsEqual([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // GIF89a
    }

    /// Detects animated images (animated GIF, WebP, APNG) by checking frame count via CGImageSource.
    private static func isAnimatedImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private func persistImageAssets(
        for bookmarkID: UUID,
        sourceData: Data,
        preferredFileExtension: String?
    ) -> BookmarkImageAssets? {
        guard let thumbnailData = Self.downsampledThumbnailData(
            from: sourceData,
            maxDimension: thumbnailMaxPixelDimension
        ) else {
            return nil
        }

        let originalFileExtension = normalizedImageFileExtension(preferredFileExtension)
        let originalFilename = "\(bookmarkID.uuidString).\(originalFileExtension)"
        let originalRelativePath = "\(originalImagesDirectoryName)/\(originalFilename)"
        let originalFileURL = directoryURL.appendingPathComponent(originalRelativePath)

        let thumbnailRelativePath = "\(thumbnailsDirectoryName)/\(bookmarkID.uuidString).png"
        let thumbnailFileURL = directoryURL.appendingPathComponent(thumbnailRelativePath)

        do {
            try FileManager.default.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
            deleteExistingThumbnailFiles(for: bookmarkID)
            deleteExistingOriginalImageFiles(for: bookmarkID)

            try sourceData.write(to: originalFileURL, options: .atomic)
            try thumbnailData.write(to: thumbnailFileURL, options: .atomic)

            return BookmarkImageAssets(
                thumbnailRelativePath: thumbnailRelativePath,
                originalImageRelativePath: originalRelativePath
            )
        } catch {
            return nil
        }
    }

    private func applyManualThumbnail(
        for bookmarkID: UUID,
        assets: BookmarkImageAssets,
        remoteURLString: String?
    ) -> Bool {
        cancelEnrichment(for: bookmarkID)

        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        var bookmark = bookmarks[index]
        if bookmark.thumbnailRelativePath != assets.thumbnailRelativePath {
            removeImageIfPresent(relativePath: bookmark.thumbnailRelativePath)
        }
        if bookmark.originalImageRelativePath != assets.originalImageRelativePath {
            removeImageIfPresent(relativePath: bookmark.originalImageRelativePath)
        }
        bookmark.thumbnailRelativePath = assets.thumbnailRelativePath
        bookmark.originalImageRelativePath = assets.originalImageRelativePath
        bookmark.thumbnailRemoteURLString = remoteURLString
        bookmark.metadataUpdatedAt = Date()
        bookmark.updatedAt = Date()
        bookmark.isEnriching = false

        bookmarks[index] = bookmark
        persist()
        // Re-run OCR + color extraction when thumbnail changes
        BookmarkAIEnrichment.shared.schedule(for: bookmarks[index])
        return true
    }

    private func deleteExistingThumbnailFiles(for bookmarkID: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: thumbnailsDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        let prefix = bookmarkID.uuidString + "."
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
        }
    }

    private func deleteExistingOriginalImageFiles(for bookmarkID: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: originalImagesDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        let prefix = bookmarkID.uuidString + "."
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
        }
    }

    private func inferredImageFileExtension(response: URLResponse, remoteURL: URL) -> String {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if contentType.contains("png") { return "png" }
            if contentType.contains("jpeg") || contentType.contains("jpg") { return "jpg" }
            if contentType.contains("webp") { return "webp" }
            if contentType.contains("gif") { return "gif" }
            if contentType.contains("heic") { return "heic" }
            if contentType.contains("icon") || contentType.contains("ico") { return "ico" }
        }

        let ext = remoteURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "gif", "heic", "avif", "ico"].contains(ext) {
            return ext == "jpeg" ? "jpg" : ext
        }

        return "jpg"
    }

    private func normalizedImageFileExtension(_ rawExtension: String?) -> String {
        guard let rawExtension else { return "png" }
        let normalized = rawExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "jpg", "jpeg":
            return "jpg"
        case "png", "webp", "gif", "heic", "avif", "bmp", "tif", "tiff", "ico":
            return normalized == "tif" ? "tiff" : normalized
        default:
            return "png"
        }
    }

    private func normalizeBookmarkImageAssetsIfNeeded() {
        guard !bookmarks.isEmpty else { return }

        var didChangeAnyBookmark = false
        let fm = FileManager.default

        for index in bookmarks.indices {
            var bookmark = bookmarks[index]
            var didChangeBookmark = false

            guard let thumbnailRelativePath = bookmark.thumbnailRelativePath,
                  !thumbnailRelativePath.isEmpty else {
                continue
            }

            let thumbnailURL = directoryURL.appendingPathComponent(thumbnailRelativePath)
            guard fm.fileExists(atPath: thumbnailURL.path) else { continue }

            // Ensure we preserve a local full-size original before rewriting old thumbnails.
            let originalResult = ensureOriginalImageAsset(for: bookmark, fallbackThumbnailURL: thumbnailURL)
            if let originalPath = originalResult.relativePath,
               bookmark.originalImageRelativePath != originalPath {
                bookmark.originalImageRelativePath = originalPath
                didChangeBookmark = true
            }

            let canonicalThumbnailRelativePath = "\(thumbnailsDirectoryName)/\(bookmark.id.uuidString).png"
            let currentMaxDimension = imageMaxPixelDimension(at: thumbnailURL) ?? 0
            let shouldRewriteThumbnail =
                thumbnailRelativePath != canonicalThumbnailRelativePath
                || currentMaxDimension > thumbnailMaxPixelDimension + 1

            if shouldRewriteThumbnail {
                let sourceURL = originalResult.fileURL ?? thumbnailURL
                if let sourceData = try? Data(contentsOf: sourceURL),
                   let downsampledData = Self.downsampledThumbnailData(
                       from: sourceData,
                       maxDimension: thumbnailMaxPixelDimension
                   ) {
                    let canonicalThumbnailURL = directoryURL.appendingPathComponent(canonicalThumbnailRelativePath)
                    try? fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
                    try? downsampledData.write(to: canonicalThumbnailURL, options: .atomic)

                    if thumbnailRelativePath != canonicalThumbnailRelativePath {
                        removeImageIfPresent(relativePath: thumbnailRelativePath)
                        bookmark.thumbnailRelativePath = canonicalThumbnailRelativePath
                        didChangeBookmark = true
                    }
                }
            }

            if didChangeBookmark {
                bookmark.metadataUpdatedAt = Date()
                bookmarks[index] = bookmark
                didChangeAnyBookmark = true
            }
        }

        if didChangeAnyBookmark {
            persist()
        }
    }

    private func ensureOriginalImageAsset(
        for bookmark: Bookmark,
        fallbackThumbnailURL: URL
    ) -> (relativePath: String?, fileURL: URL?) {
        let fm = FileManager.default

        if let existingPath = bookmark.originalImageRelativePath,
           !existingPath.isEmpty {
            let existingURL = directoryURL.appendingPathComponent(existingPath)
            if fm.fileExists(atPath: existingURL.path) {
                return (existingPath, existingURL)
            }
        }

        let originalFileExtension = normalizedImageFileExtension(fallbackThumbnailURL.pathExtension)
        let originalRelativePath = "\(originalImagesDirectoryName)/\(bookmark.id.uuidString).\(originalFileExtension)"
        let originalURL = directoryURL.appendingPathComponent(originalRelativePath)

        do {
            try fm.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: originalURL.path) {
                try fm.copyItem(at: fallbackThumbnailURL, to: originalURL)
            }
            return (originalRelativePath, originalURL)
        } catch {
            return (nil, nil)
        }
    }

    private func imageMaxPixelDimension(at fileURL: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }
        return max(CGFloat(widthNumber.doubleValue), CGFloat(heightNumber.doubleValue))
    }

    private static func downsampledThumbnailData(from sourceData: Data, maxDimension: CGFloat) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]

        guard let source = CGImageSourceCreateWithData(sourceData as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    private func copyBookmarkImageAssetsIfNeeded(from previousDirectoryURL: URL, bookmarks: [Bookmark]) {
        let fm = FileManager.default
        for bookmark in bookmarks {
            guard let relativePath = bookmark.thumbnailRelativePath, !relativePath.isEmpty else { continue }

            let sourceURL = previousDirectoryURL.appendingPathComponent(relativePath)
            let destinationURL = directoryURL.appendingPathComponent(relativePath)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            guard !fm.fileExists(atPath: destinationURL.path) else { continue }

            try? fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: sourceURL, to: destinationURL)
        }

        for bookmark in bookmarks {
            guard let relativePath = bookmark.originalImageRelativePath, !relativePath.isEmpty else { continue }

            let sourceURL = previousDirectoryURL.appendingPathComponent(relativePath)
            let destinationURL = directoryURL.appendingPathComponent(relativePath)
            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            guard !fm.fileExists(atPath: destinationURL.path) else { continue }

            try? fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: sourceURL, to: destinationURL)
        }

        // Copy carousel image files
        for bookmark in bookmarks {
            guard let carouselPaths = bookmark.carouselImagePaths else { continue }
            for relativePath in carouselPaths where !relativePath.isEmpty {
                let sourceURL = previousDirectoryURL.appendingPathComponent(relativePath)
                let destinationURL = directoryURL.appendingPathComponent(relativePath)
                guard fm.fileExists(atPath: sourceURL.path) else { continue }
                guard !fm.fileExists(atPath: destinationURL.path) else { continue }

                try? fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: sourceURL, to: destinationURL)
            }
        }
    }

    private static func fetchEnrichmentPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")
        let htmlResult = await fetchHTMLEnrichmentPayload(for: pageURL)

        // If HTML gave us a real thumbnail (not just a favicon), we're done
        let hasRealThumbnail = htmlResult?.thumbnailURL != nil
            && !isFaviconURL(htmlResult?.thumbnailURL)
        if let htmlResult, hasRealThumbnail {
            return htmlResult
        }

        // Try oEmbed fallback for known providers
        if let oembedResult = await BookmarkMetadataParser.fetchOEmbedPayload(for: pageURL) {
            return BookmarkEnrichmentPayload(
                title: htmlResult?.title ?? oembedResult.title,
                thumbnailURL: oembedResult.thumbnailURL,
                screenshotData: nil
            )
        }

        // WebView fallback — renders JS-heavy pages (IMDB WAF, Booking, etc.)
        let needsWebView = htmlResult?.title == nil || !hasRealThumbnail
        if needsWebView {
            enrichLog.info("Trying WebView fallback for \(pageURL.host ?? "?", privacy: .public)")
            let extracted = await WebViewMetadataExtractor.extract(from: pageURL)
            let hasResult = extracted.title != nil || extracted.imageURL != nil
            if hasResult || extracted.screenshotData != nil {
                enrichLog.info("WebView result for \(pageURL.host ?? "?", privacy: .public): title=\(extracted.title ?? "nil", privacy: .public) image=\(extracted.imageURL?.absoluteString ?? "nil", privacy: .public) screenshot=\(extracted.screenshotData != nil ? "\(extracted.screenshotData!.count) bytes" : "nil", privacy: .public)")
                return BookmarkEnrichmentPayload(
                    title: extracted.title ?? htmlResult?.title,
                    thumbnailURL: extracted.imageURL ?? htmlResult?.thumbnailURL,
                    screenshotData: extracted.screenshotData
                )
            }
        }

        return htmlResult
    }

    /// Check if a URL looks like a favicon (not a real og:image thumbnail).
    private static func isFaviconURL(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path.contains("favicon") || path.contains("apple-touch-icon")
    }

    private static func fetchHTMLEnrichmentPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        // CH-S03: Only allow http/https to prevent SSRF against local/internal services
        guard let scheme = pageURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 10
        Self.applyBrowserHeaders(&request)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                enrichLog.warning("HTML fetch failed for \(pageURL.host ?? "?", privacy: .public): HTTP \(code)")
                return nil
            }
            guard let html = decodeHTML(data: data) else {
                enrichLog.warning("HTML decode failed for \(pageURL.host ?? "?", privacy: .public) (\(data.count) bytes)")
                return nil
            }
            let result = BookmarkMetadataParser.parse(html: html, pageURL: pageURL)
            enrichLog.info("Parsed \(pageURL.host ?? "?", privacy: .public): title=\(result?.title ?? "nil", privacy: .public) thumbnail=\(result?.thumbnailURL?.absoluteString ?? "nil", privacy: .public)")
            return result
        } catch {
            enrichLog.warning("HTML fetch error for \(pageURL.host ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func decodeHTML(data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16), !utf16.isEmpty { return utf16 }
        if let latin1 = String(data: data, encoding: .isoLatin1), !latin1.isEmpty { return latin1 }
        if let windows = String(data: data, encoding: .windowsCP1252), !windows.isEmpty { return windows }
        return nil
    }

    /// Apply browser-like headers to avoid bot detection on major sites.
    private static func applyBrowserHeaders(_ request: inout URLRequest) {
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        guard let candidate = extractedURLCandidate(from: rawValue) else { return nil }

        let withScheme: String
        if candidate.lowercased().hasPrefix("http://") || candidate.lowercased().hasPrefix("https://") {
            withScheme = candidate
        } else {
            withScheme = "https://\(candidate)"
        }

        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host?.lowercased(),
              isLikelyWebHost(host) else {
            return nil
        }

        components.scheme = scheme
        return components.url
    }

    private func extractedURLCandidate(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)).first,
           let range = Range(match.range, in: trimmed) {
            return String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func isLikelyWebHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        if host.hasPrefix("[") && host.contains(":") { return true } // IPv6 literal
        if host.contains(".") { return true }

        let octets = host.split(separator: ".")
        if octets.count == 4,
           octets.allSatisfy({ part in
               guard let value = Int(part) else { return false }
               return (0...255).contains(value)
           }) {
            return true
        }

        return false
    }

    private func resolvedTitle(for url: URL, override: String?) -> String {
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let host = url.host {
            let hostWithoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return hostWithoutWWW.capitalized
        }

        return url.absoluteString
    }

    private func uniqueFolderName(baseName: String, parentID: UUID?, excluding excludedFolderID: UUID? = nil) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return baseName }

        let siblingNames = Set(
            folders
                .filter { folder in
                    folder.parentID == parentID && folder.id != excludedFolderID
                }
                .map { $0.name.lowercased() }
        )

        if !siblingNames.contains(trimmedBase.lowercased()) {
            return trimmedBase
        }

        var suffix = 2
        while siblingNames.contains("\(trimmedBase) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(trimmedBase) \(suffix)"
    }

    private func folderSubtreeIDs(rootID: UUID) -> Set<UUID> {
        let childrenByParent = Dictionary(grouping: folders, by: \.parentID)
        var queue: [UUID] = [rootID]
        var visited: Set<UUID> = [rootID]

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            let children = childrenByParent[currentID] ?? []
            for child in children where !visited.contains(child.id) {
                visited.insert(child.id)
                queue.append(child.id)
            }
        }

        return visited
    }

    private func folderSortOrder(_ lhs: Folder, _ rhs: Folder) -> Bool {
        switch (lhs.parentID, rhs.parentID) {
        case (nil, nil):
            break
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (leftParent?, rightParent?) where leftParent != rightParent:
            return leftParent.uuidString < rightParent.uuidString
        default:
            break
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sanitizedFolders(from rawFolders: [Folder]) -> [Folder] {
        guard !rawFolders.isEmpty else { return [] }

        var uniqueFoldersByID: [UUID: Folder] = [:]
        for folder in rawFolders where uniqueFoldersByID[folder.id] == nil {
            uniqueFoldersByID[folder.id] = folder
        }

        var sanitizedFolders = Array(uniqueFoldersByID.values)
        let knownFolderIDs = Set(sanitizedFolders.map(\.id))

        for index in sanitizedFolders.indices {
            if let parentID = sanitizedFolders[index].parentID {
                if parentID == sanitizedFolders[index].id || !knownFolderIDs.contains(parentID) {
                    sanitizedFolders[index].parentID = nil
                    sanitizedFolders[index].updatedAt = Date()
                }
            }
        }

        var parentByFolderID = Dictionary(
            uniqueKeysWithValues: sanitizedFolders.map { ($0.id, $0.parentID) }
        )
        for index in sanitizedFolders.indices {
            let folderID = sanitizedFolders[index].id
            if hasParentCycle(startFolderID: folderID, parentByFolderID: parentByFolderID) {
                sanitizedFolders[index].parentID = nil
                sanitizedFolders[index].updatedAt = Date()
                parentByFolderID[folderID] = nil
            }
        }

        sanitizedFolders.sort(by: folderSortOrder)
        return sanitizedFolders
    }

    private func hasParentCycle(
        startFolderID: UUID,
        parentByFolderID: [UUID: UUID?]
    ) -> Bool {
        var visited: Set<UUID> = [startFolderID]
        var currentParentID = parentByFolderID[startFolderID] ?? nil

        while let parentID = currentParentID {
            if visited.contains(parentID) {
                return true
            }
            visited.insert(parentID)
            currentParentID = parentByFolderID[parentID] ?? nil
        }

        return false
    }

    private func sanitizedBookmarks(from rawBookmarks: [Bookmark], validFolderIDs: Set<UUID>) -> [Bookmark] {
        guard !rawBookmarks.isEmpty else { return [] }

        func normalizedBookmark(_ bookmark: Bookmark) -> Bookmark {
            var normalized = bookmark

            if let thumbnailPath = normalized.thumbnailRelativePath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               thumbnailPath.isEmpty {
                normalized.thumbnailRelativePath = nil
            }

            if let originalPath = normalized.originalImageRelativePath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               originalPath.isEmpty {
                normalized.originalImageRelativePath = nil
            }

            return normalized
        }

        guard !validFolderIDs.isEmpty else {
            return rawBookmarks.map { bookmark in
                var normalized = normalizedBookmark(bookmark)
                normalized.folderID = nil
                return normalized
            }
        }

        return rawBookmarks.map { bookmark in
            var normalized = normalizedBookmark(bookmark)
            if let folderID = normalized.folderID, !validFolderIDs.contains(folderID) {
                normalized.folderID = nil
            }
            return normalized
        }
    }

    private func deduplicatedTags(from rawTags: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(rawTags.count)

        var seen = Set<String>()
        for raw in rawTags {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(normalized)
        }

        return result
    }

    // MARK: - AI Results

    /// Write AI-generated fields back to a bookmark without re-triggering AI enrichment.
    func applyAIResults(
        for bookmarkID: UUID,
        tags: [String],
        ocrText: String?,
        dominantColors: [String]?,
        title: String? = nil
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        var bookmark = bookmarks[index]
        var changed = false
        if bookmark.tags != tags { bookmark.tags = tags; changed = true }
        if bookmark.ocrText != ocrText { bookmark.ocrText = ocrText; changed = true }
        if bookmark.dominantColors != dominantColors { bookmark.dominantColors = dominantColors; changed = true }
        if let title, !title.isEmpty, bookmark.title != title { bookmark.title = title; changed = true }
        guard changed else { return }
        bookmarks[index] = bookmark
        persist()
    }

    /// Write an AI-generated summary back to a bookmark.
    func applyAISummary(_ summary: String, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].aiSummary != summary else { return }
        bookmarks[index].aiSummary = summary
        persist()
    }

    func setReaderUnavailable(_ unavailable: Bool, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].readerUnavailable != unavailable else { return }
        bookmarks[index].readerUnavailable = unavailable
        persist()
    }

    func setPreferredHeroMode(_ mode: String, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].preferredHeroMode != mode else { return }
        bookmarks[index].preferredHeroMode = mode
        persist()
    }

    func setMediaType(_ mediaType: BookmarkMediaType, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].mediaType != mediaType else { return }
        bookmarks[index].mediaType = mediaType
        persist()
    }

    // MARK: - Carousel Image Management

    private static let maxCarouselImages = 10

    /// Add an image to a bookmark's carousel. If the bookmark currently has a single image,
    /// it is promoted to a carousel with the existing image as index 0.
    @discardableResult
    func addCarouselImage(for bookmarkID: UUID, imageData: Data, preferredFileExtension: String? = nil) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        guard imageData.count > 128, imageData.count < 12_000_000 else { return false }
        guard NSImage(data: imageData) != nil else { return false }

        var bookmark = bookmarks[index]
        var paths = bookmark.carouselImagePaths ?? []

        // Promote existing single image to carousel index 0
        if paths.isEmpty, let existingOriginal = bookmark.originalImageRelativePath, !existingOriginal.isEmpty {
            let fm = FileManager.default
            let existingURL = directoryURL.appendingPathComponent(existingOriginal)
            if fm.fileExists(atPath: existingURL.path) {
                let ext = existingURL.pathExtension
                let newName = "\(originalImagesDirectoryName)/\(bookmarkID.uuidString)_0.\(ext)"
                let newURL = directoryURL.appendingPathComponent(newName)
                if existingURL.path != newURL.path {
                    try? fm.moveItem(at: existingURL, to: newURL)
                }
                bookmark.originalImageRelativePath = newName
                paths.append(newName)
            }
        }

        guard paths.count < Self.maxCarouselImages else { return false }

        let nextIndex = paths.count
        let ext = normalizedImageFileExtension(preferredFileExtension)
        let relativePath = "\(originalImagesDirectoryName)/\(bookmarkID.uuidString)_\(nextIndex).\(ext)"
        let fileURL = directoryURL.appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }

        paths.append(relativePath)
        bookmark.carouselImagePaths = paths
        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

    /// Remove a carousel image at the given index. If only one image remains, demote back to single-image.
    @discardableResult
    func removeCarouselImage(for bookmarkID: UUID, at imageIndex: Int) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        var bookmark = bookmarks[index]
        guard var paths = bookmark.carouselImagePaths, paths.indices.contains(imageIndex) else { return false }

        let removedPath = paths.remove(at: imageIndex)
        removeImageIfPresent(relativePath: removedPath)

        if paths.count <= 1 {
            // Demote to single-image bookmark
            bookmark.carouselImagePaths = nil
            if let remaining = paths.first {
                bookmark.originalImageRelativePath = remaining
            }
            // Regenerate thumbnail from the remaining image
            if let remaining = paths.first {
                regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: remaining)
            }
        } else {
            bookmark.carouselImagePaths = paths
            // If we removed the first image, regenerate thumbnail from new first
            if imageIndex == 0 {
                regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: paths[0])
            }
        }

        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

    /// Reorder carousel images by moving an image from one index to another.
    @discardableResult
    func reorderCarouselImages(for bookmarkID: UUID, fromIndex: Int, toIndex: Int) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        var bookmark = bookmarks[index]
        guard var paths = bookmark.carouselImagePaths,
              paths.indices.contains(fromIndex),
              toIndex >= 0, toIndex < paths.count,
              fromIndex != toIndex else { return false }

        let moved = paths.remove(at: fromIndex)
        paths.insert(moved, at: toIndex)
        bookmark.carouselImagePaths = paths

        // If the first image changed, regenerate thumbnail
        let firstChanged = fromIndex == 0 || toIndex == 0
        if firstChanged {
            regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: paths[0])
        }

        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

    /// Add a carousel image from a remote or local URL string.
    func addCarouselImage(for bookmarkID: UUID, fromDroppedString rawValue: String) async -> Bool {
        guard let candidate = extractedURLCandidate(from: rawValue) else { return false }
        let sourceURL: URL
        if let direct = URL(string: candidate), direct.scheme != nil {
            sourceURL = direct
        } else if candidate.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: candidate)
        } else if let withHTTPS = URL(string: "https://\(candidate)") {
            sourceURL = withHTTPS
        } else {
            return false
        }

        if sourceURL.isFileURL {
            guard let data = try? Data(contentsOf: sourceURL) else { return false }
            return addCarouselImage(for: bookmarkID, imageData: data, preferredFileExtension: sourceURL.pathExtension)
        }

        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 8
        Self.applyBrowserHeaders(&request)
        request.setValue("image/gif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else { return false }

        let ext = inferredImageFileExtension(response: response, remoteURL: sourceURL)
        return addCarouselImage(for: bookmarkID, imageData: data, preferredFileExtension: ext)
    }

    private func regenerateThumbnail(for bookmarkID: UUID, fromOriginalRelativePath relativePath: String) {
        let fileURL = directoryURL.appendingPathComponent(relativePath)
        guard let sourceData = try? Data(contentsOf: fileURL),
              let thumbnailData = Self.downsampledThumbnailData(from: sourceData, maxDimension: thumbnailMaxPixelDimension) else {
            return
        }

        let thumbnailRelativePath = "\(thumbnailsDirectoryName)/\(bookmarkID.uuidString).png"
        let thumbnailFileURL = directoryURL.appendingPathComponent(thumbnailRelativePath)
        try? thumbnailData.write(to: thumbnailFileURL, options: .atomic)

        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].thumbnailRelativePath = thumbnailRelativePath
    }
}

private struct BookmarkEnrichmentPayload {
    let title: String?
    let thumbnailURL: URL?
    let screenshotData: Data?
}

private enum EnrichmentRetryThresholds {
    static let firstHour: TimeInterval = 60 * 60
    static let socialEarly: TimeInterval = 60 * 5
    static let socialSteady: TimeInterval = 60 * 45
    static let noThumbnailEarly: TimeInterval = 60 * 10
    static let noThumbnailSteady: TimeInterval = 60 * 60 * 3
    static let defaultSteady: TimeInterval = 60 * 60 * 6
}

private enum BookmarkMetadataParser {
    private static let titleRegex = try? NSRegularExpression(
        pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#,
        options: []
    )
    private static let metaRegex = try? NSRegularExpression(
        pattern: #"(?is)<meta\b[^>]*>"#,
        options: []
    )
    private static let linkRegex = try? NSRegularExpression(
        pattern: #"(?is)<link\b[^>]*>"#,
        options: []
    )
    private static let scriptRegex = try? NSRegularExpression(
        pattern: #"(?is)<script\b([^>]*)>(.*?)</script>"#,
        options: []
    )
    private static let attributeRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_:][A-Za-z0-9_:\-\.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
        options: []
    )

    static func parse(html: String, pageURL: URL) -> BookmarkEnrichmentPayload? {
        let host = normalizedHost(for: pageURL)

        let titleCandidates = [
            metaContent(html: html, keys: [("property", "og:title")]),
            metaContent(html: html, keys: [("name", "twitter:title")]),
            metaContent(html: html, keys: [("name", "title")]),
            jsonLDTitle(html: html),
            titleTagContent(html: html),
        ]

        let title = titleCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let imageMetaRaw = [
            metaContent(html: html, keys: [("property", "og:image")]),
            metaContent(html: html, keys: [("name", "twitter:image")]),
            metaContent(html: html, keys: [("name", "twitter:image:src")]),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let imageMetaURL = imageMetaRaw.flatMap { resolvedRemoteURL(from: $0, baseURL: pageURL) }
        let jsonLDURL = jsonLDImageURL(html: html, pageURL: pageURL)
        let siteAdapterURL = siteSpecificThumbnailURL(html: html, pageURL: pageURL)
        let favicon = faviconURL(html: html, pageURL: pageURL)

        let thumbnailCandidates: [URL?]
        if host.contains("reddit.com") {
            // Reddit meta tags frequently point to removed/default placeholders.
            thumbnailCandidates = [
                siteAdapterURL,
                jsonLDURL,
            ]
        } else if host == "x.com" || host == "twitter.com" || host.contains("digg.com") {
            // Prefer real media URLs for social feeds; icon fallbacks are too noisy here.
            thumbnailCandidates = [
                siteAdapterURL,
                imageMetaURL,
                jsonLDURL,
            ]
        } else {
            thumbnailCandidates = [
                imageMetaURL,
                jsonLDURL,
                siteAdapterURL,
                favicon,
            ]
        }

        let thumbnailURL = thumbnailCandidates
            .compactMap { $0 }
            .first(where: { isThumbnailCandidateAcceptable($0, for: pageURL) })

        guard title != nil || thumbnailURL != nil else { return nil }
        return BookmarkEnrichmentPayload(title: title, thumbnailURL: thumbnailURL, screenshotData: nil)
    }

    private static func titleTagContent(html: String) -> String? {
        guard let titleRegex else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = titleRegex.firstMatch(in: html, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTMLEntities(String(html[range]))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func metaContent(html: String, keys: [(String, String)]) -> String? {
        guard let metaRegex else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = metaRegex.matches(in: html, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let attributes = parseAttributes(tag)

            let isMatch = keys.allSatisfy { key, expectedValue in
                attributes[key.lowercased()]?.lowercased() == expectedValue.lowercased()
            }
            if !isMatch { continue }

            if let content = attributes["content"], !content.isEmpty {
                return decodeHTMLEntities(content)
            }
        }

        return nil
    }

    private static func jsonLDTitle(html: String) -> String? {
        for object in jsonLDObjects(fromHTML: html) {
            if let title = firstJSONLDString(
                forKeys: ["headline", "name", "title"],
                in: object
            ) {
                return title
            }
        }
        return nil
    }

    private static func jsonLDImageURL(html: String, pageURL: URL) -> URL? {
        for object in jsonLDObjects(fromHTML: html) {
            if let imageRaw = firstJSONLDString(
                forKeys: ["image", "thumbnailUrl", "thumbnailURL", "contentUrl", "primaryImageOfPage", "associatedMedia"],
                in: object
            ),
               let imageURL = resolvedRemoteURL(from: imageRaw, baseURL: pageURL) {
                return imageURL
            }
        }
        return nil
    }

    private static func jsonLDObjects(fromHTML html: String) -> [Any] {
        guard let scriptRegex else { return [] }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = scriptRegex.matches(in: html, options: [], range: nsRange)
        guard !matches.isEmpty else { return [] }

        var results: [Any] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = parseAttributes(String(html[attrsRange]))
            guard let scriptType = attributes["type"]?.lowercased(),
                  scriptType.contains("application/ld+json") else {
                continue
            }

            let scriptBody = String(html[bodyRange])
            guard let object = parseJSONLDObject(from: scriptBody) else { continue }
            results.append(object)
        }

        return results
    }

    private static func parseJSONLDObject(from raw: String) -> Any? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = jsonLDCandidates(from: trimmed)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return object
            }
        }

        return nil
    }

    private static func jsonLDCandidates(from raw: String) -> [String] {
        var normalized = raw
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasSuffix(";") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return [raw, normalized]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func firstJSONLDString(forKeys keys: [String], in object: Any) -> String? {
        for key in keys {
            var values: [Any] = []
            collectJSONValues(forKey: key, from: object, into: &values)
            for value in values {
                if let stringValue = stringFromJSONValue(value), !stringValue.isEmpty {
                    return decodeEscapedURLString(stringValue)
                }
            }
        }
        return nil
    }

    private static func collectJSONValues(forKey key: String, from object: Any, into values: inout [Any]) {
        if let dictionary = object as? [String: Any] {
            for (candidateKey, value) in dictionary {
                if candidateKey.lowercased() == key.lowercased() {
                    values.append(value)
                }
                collectJSONValues(forKey: key, from: value, into: &values)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectJSONValues(forKey: key, from: item, into: &values)
            }
        }
    }

    private static func stringFromJSONValue(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let array = value as? [Any] {
            for item in array {
                if let resolved = stringFromJSONValue(item) {
                    return resolved
                }
            }
            return nil
        }

        if let dictionary = value as? [String: Any] {
            let prioritizedKeys = ["url", "contentUrl", "thumbnailUrl", "thumbnailURL"]
            for key in prioritizedKeys {
                if let nested = dictionary[key],
                   let resolved = stringFromJSONValue(nested) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func siteSpecificThumbnailURL(html: String, pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com") {
            return redditThumbnailURL(html: html, pageURL: pageURL)
        }
        if host == "x.com" || host == "twitter.com" {
            return xThumbnailURL(html: html, pageURL: pageURL)
        }
        return nil
    }

    private static func redditThumbnailURL(html: String, pageURL: URL) -> URL? {
        let patterns = [
            #"(?is)(https?:\\/\\/(?:i|preview)\.redd\.it\\/[^"'\\s<]+)"#,
            #"(?is)(https?://(?:i|preview)\.redd\.it/[^"'\\s<]+)"#,
            #"(?is)(https?:\\/\\/external-preview\.redd\.it\\/[^"'\\s<]+)"#,
            #"(?is)(https?://external-preview\.redd\.it/[^"'\\s<]+)"#,
        ]

        for pattern in patterns {
            if let raw = firstRegexCapture(pattern: pattern, in: html),
               let resolved = resolvedRemoteURL(from: raw, baseURL: pageURL),
               !isLikelyRedditPlaceholderImage(url: resolved) {
                return resolved
            }
        }

        return nil
    }

    private static func xThumbnailURL(html: String, pageURL: URL) -> URL? {
        let patterns = [
            #"(?is)(https?:\\/\\/pbs\.twimg\.com\\/(?:media|amplify_video_thumb)\\/[^"'\\s<]+)"#,
            #"(?is)(https?://pbs\.twimg\.com/(?:media|amplify_video_thumb)/[^"'\\s<]+)"#,
        ]

        for pattern in patterns {
            if let raw = firstRegexCapture(pattern: pattern, in: html),
               let resolved = resolvedRemoteURL(from: raw, baseURL: pageURL) {
                return resolved
            }
        }

        return nil
    }

    private static func faviconURL(html: String, pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com")
            || host == "x.com"
            || host == "twitter.com"
            || host.contains("digg.com")
            || host.contains("tiktok.com") {
            return nil
        }

        guard let linkRegex else { return defaultFaviconURL(for: pageURL) }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = linkRegex.matches(in: html, options: [], range: nsRange)

        var bestCandidate: (priority: Int, url: URL)?
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let attributes = parseAttributes(tag)
            guard let href = attributes["href"], !href.isEmpty else { continue }

            let rel = attributes["rel"]?.lowercased() ?? ""
            let priority: Int
            if rel.contains("apple-touch-icon") {
                priority = 0
            } else if rel.contains("shortcut icon") {
                priority = 1
            } else if rel.contains("icon") || rel.contains("mask-icon") {
                priority = 2
            } else {
                continue
            }

            guard let resolved = resolvedRemoteURL(from: href, baseURL: pageURL) else { continue }
            if let currentBest = bestCandidate {
                if priority < currentBest.priority {
                    bestCandidate = (priority, resolved)
                }
            } else {
                bestCandidate = (priority, resolved)
            }
        }

        return bestCandidate?.url ?? defaultFaviconURL(for: pageURL)
    }

    private static func isThumbnailCandidateAcceptable(_ url: URL, for pageURL: URL) -> Bool {
        let host = normalizedHost(for: pageURL)
        if host.contains("reddit.com"),
           isLikelyRedditPlaceholderImage(url: url) {
            return false
        }
        return true
    }

    private static func isLikelyRedditPlaceholderImage(url: URL) -> Bool {
        let fingerprint = [
            url.host ?? "",
            url.path,
            url.query ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        let blockedFragments = [
            "if-you-are-looking-for-an-image",
            "if_you_are_looking_for_an_image",
            "/removed.",
            "/deleted.",
            "/default.",
            "/self.",
            "/nsfw.",
            "/spoiler.",
            "preview.redd.it/default",
            "preview.redd.it/self",
            "preview.redd.it/nsfw",
            "preview.redd.it/spoiler",
        ]

        return blockedFragments.contains { fragment in
            fingerprint.contains(fragment)
        }
    }

    private static func defaultFaviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func parseAttributes(_ tag: String) -> [String: String] {
        guard let attributeRegex else { return [:] }
        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        let matches = attributeRegex.matches(in: tag, options: [], range: nsRange)

        var attributes: [String: String] = [:]
        attributes.reserveCapacity(matches.count)

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()

            let value: String
            if let range = Range(match.range(at: 2), in: tag) {
                value = String(tag[range])
            } else if let range = Range(match.range(at: 3), in: tag) {
                value = String(tag[range])
            } else if let range = Range(match.range(at: 4), in: tag) {
                value = String(tag[range])
            } else {
                continue
            }

            attributes[name] = value
        }

        return attributes
    }

    private static func resolvedURL(from rawValue: String, baseURL: URL) -> URL? {
        let decoded = decodeEscapedURLString(rawValue)
        if let absolute = URL(string: decoded), absolute.scheme != nil {
            return absolute
        }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }

    private static func resolvedRemoteURL(from rawValue: String, baseURL: URL) -> URL? {
        guard let resolved = resolvedURL(from: rawValue, baseURL: baseURL),
              let scheme = resolved.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return nil
        }
        return resolved
    }

    private static func normalizedHost(for pageURL: URL) -> String {
        let host = pageURL.host?.lowercased() ?? ""
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        if host.hasPrefix("m.") {
            return String(host.dropFirst(2))
        }
        return host
    }

    private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        let captureRange: NSRange
        if match.numberOfRanges > 1 {
            captureRange = match.range(at: 1)
        } else {
            captureRange = match.range(at: 0)
        }

        guard let range = Range(captureRange, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func decodeEscapedURLString(_ value: String) -> String {
        var decoded = decodeHTMLEntities(value)
        decoded = decoded
            .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u003A", with: ":")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u0025", with: "%")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if decoded.hasPrefix("\""), decoded.hasSuffix("\""), decoded.count > 1 {
            decoded.removeFirst()
            decoded.removeLast()
        }

        return decoded
    }

    fileprivate static let namedEntities: [String: String] = [
        "&quot;": "\"", "&apos;": "'", "&#39;": "'",
        "&gt;": ">", "&lt;": "<",
        "&ndash;": "\u{2013}", "&mdash;": "\u{2014}",
        "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
        "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        "&nbsp;": " ", "&hellip;": "\u{2026}",
        "&trade;": "\u{2122}", "&copy;": "\u{00A9}", "&reg;": "\u{00AE}",
        "&bull;": "\u{2022}", "&middot;": "\u{00B7}",
        "&laquo;": "\u{00AB}", "&raquo;": "\u{00BB}",
        "&amp;": "&",  // must be last
    ]
    fileprivate static let numericEntityRegex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")

    fileprivate static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode numeric entities: &#123; and &#x1F4A9;
        if let regex = numericEntityRegex {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let numRange = Range(match.range(at: 2), in: result) else { continue }
                let isHex = !result[hexRange].isEmpty
                let numStr = String(result[numRange])
                let codePoint = isHex ? UInt32(numStr, radix: 16) : UInt32(numStr, radix: 10)
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - oEmbed fallback

    static func oEmbedEndpointURL(for pageURL: URL) -> URL? {
        let host = normalizedHost(for: pageURL)
        let encoded = pageURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageURL.absoluteString

        if host.contains("tiktok.com") {
            return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
        }
        if host.contains("instagram.com") {
            return URL(string: "https://api.instagram.com/oembed?url=\(encoded)")
        }
        if host.contains("spotify.com") {
            return URL(string: "https://open.spotify.com/oembed?url=\(encoded)")
        }
        return nil
    }

    static func fetchOEmbedPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        guard let endpoint = oEmbedEndpointURL(for: pageURL) else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let title = json["title"] as? String
            let thumbnailRaw = json["thumbnail_url"] as? String
            let thumbnailURL = thumbnailRaw.flatMap { URL(string: $0) }

            guard title != nil || thumbnailURL != nil else { return nil }
            return BookmarkEnrichmentPayload(title: title, thumbnailURL: thumbnailURL, screenshotData: nil)
        } catch {
            return nil
        }
    }
}

enum NetscapeBookmarksCodec {
    private static let anchorRegex = try? NSRegularExpression(
        pattern: #"(?is)<a\b([^>]*)>(.*?)</a>"#,
        options: []
    )
    private static let hrefRegex = try? NSRegularExpression(
        pattern: #"(?is)\bhref\s*=\s*(['"])(.*?)\1"#,
        options: []
    )
    private static let addDateRegex = try? NSRegularExpression(
        pattern: #"(?is)\badd_date\s*=\s*(['"])(\d+)\1"#,
        options: []
    )
    private static let lastModifiedRegex = try? NSRegularExpression(
        pattern: #"(?is)\blast_modified\s*=\s*(['"])(\d+)\1"#,
        options: []
    )

    struct Entry {
        let urlString: String
        let title: String?
        let addDate: Date?
        let lastModified: Date?
    }

    static func decode(_ html: String) -> [Entry] {
        guard let anchorRegex,
              let hrefRegex,
              let addDateRegex,
              let lastModifiedRegex else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = anchorRegex.matches(in: html, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(matches.count)

        for match in matches {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = String(html[attrsRange])
            guard let href = firstCapture(of: hrefRegex, in: attributes, group: 2)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty else {
                continue
            }

            let addDate = unixDate(from: firstCapture(of: addDateRegex, in: attributes, group: 2))
            let lastModified = unixDate(from: firstCapture(of: lastModifiedRegex, in: attributes, group: 2))
            let titleRaw = String(html[titleRange])
            let decodedTitle = decodeHTMLEntities(titleRaw).trimmingCharacters(in: .whitespacesAndNewlines)

            entries.append(
                Entry(
                    urlString: decodeHTMLEntities(href),
                    title: decodedTitle.isEmpty ? nil : decodedTitle,
                    addDate: addDate,
                    lastModified: lastModified
                )
            )
        }

        return entries
    }

    static func encode(_ bookmarks: [Bookmark]) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file.",
            "     It will be read and overwritten.",
            "     DO NOT EDIT! -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]

        for bookmark in bookmarks {
            let escapedURL = escapeHTMLAttribute(bookmark.urlString)
            let escapedTitle = escapeHTMLText(bookmark.title)
            let addDate = Int(bookmark.createdAt.timeIntervalSince1970)
            let lastModified = Int(bookmark.updatedAt.timeIntervalSince1970)
            lines.append(
                "    <DT><A HREF=\"\(escapedURL)\" ADD_DATE=\"\(addDate)\" LAST_MODIFIED=\"\(lastModified)\">\(escapedTitle)</A>"
            )
        }

        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    private static func firstCapture(of regex: NSRegularExpression, in string: String, group: Int) -> String? {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let valueRange = Range(match.range(at: group), in: string) else {
            return nil
        }
        return String(string[valueRange])
    }

    private static func unixDate(from value: String?) -> Date? {
        guard let value, let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func escapeHTMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeHTMLAttribute(_ value: String) -> String {
        escapeHTMLText(value)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        BookmarkMetadataParser.decodeHTMLEntities(value)
    }
}
