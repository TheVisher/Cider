import AppKit
import Combine
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

// MARK: - VaultBookmarkService

/// File-based bookmark service that treats `.webloc` files as the durable
/// artifact and SQLite as the canonical metadata layer.
/// Legacy sidecars are imported once during migration, but normal runtime
/// reads and writes should not depend on them.
@MainActor
final class VaultBookmarkService: ObservableObject {
    static let shared = VaultBookmarkService()

    @Published private(set) var bookmarks: [Bookmark] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultBookmarkService"
    )

    // MARK: - Constants

    private let indexFileName = "_cider_bookmarks_index.json"
    private let thumbnailsDirectoryName = ".thumbnails"
    private let originalImagesDirectoryName = ".originals"
    private let thumbnailMaxPixelDimension: CGFloat = 720
    private var enrichmentTasks: [UUID: Task<Void, Never>] = [:]
    /// URLs recently deleted — adoption skips these to prevent zombie re-adoption from duplicate files.
    /// Entries expire after 30 seconds so the dictionary doesn't grow forever.
    private var recentlyDeletedURLs: [String: Date] = [:]
    private let recentlyDeletedTTL: TimeInterval = 30

    // MARK: - Index Cache Contract

    /// The JSON index is a cache only. External agents must mutate bookmarks
    /// through `VaultBookmarkService`/`cider-cli`, not by editing this file.

    // MARK: - Computed Paths

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    /// The `.cider/bookmarks/` directory for index cache + thumbnails + originals.
    private var bookmarksMetaDir: URL {
        StoragePaths.cachedDirectoryURL(for: .bookmarks)
    }

    private var indexFileURL: URL {
        bookmarksMetaDir.appendingPathComponent(indexFileName)
    }

    private var thumbnailsDirectoryURL: URL {
        bookmarksMetaDir.appendingPathComponent(thumbnailsDirectoryName, isDirectory: true)
    }

    private var originalImagesDirectoryURL: URL {
        bookmarksMetaDir.appendingPathComponent(originalImagesDirectoryName, isDirectory: true)
    }

    /// The default inbox directory for unfiled bookmarks.
    private var inboxBookmarksDir: URL {
        StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks)
    }

    private var inboxRelativePath: String {
        "\(StoragePaths.inboxDir)/\(StorageType.bookmarks.inboxSubfolderName ?? "Bookmarks")"
    }

    // MARK: - Adoption Debounce

    private var isAdopting = false
    private var lastAdoptionScan: Date = .distantPast
    private let adoptionDebounceInterval: TimeInterval = 5

    // MARK: - Database

    /// Explicit database reference for testing. Production uses `CiderDatabase.shared`.
    private var database: CiderDatabase?
    private let writesVaultCaches: Bool
    private let schedulesEnrichment: Bool

    // MARK: - Init

    private init() {
        writesVaultCaches = true
        schedulesEnrichment = true
        ensureDirectories()
        loadBookmarks()
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT call loadBookmarks() — tests call loadBookmarksFromDatabase() directly.
    init(database: CiderDatabase, schedulesEnrichment: Bool = true) {
        self.database = database
        writesVaultCaches = false
        self.schedulesEnrichment = schedulesEnrichment
    }

    /// Testing-only: clear the orphan adoption debounce so shared-singleton
    /// integration tests can run deterministically after other scanner tests.
    func _resetAdoptionDebounceForTesting() {
        lastAdoptionScan = .distantPast
    }

    // MARK: - Load

    /// Loads bookmarks: tries SQLite first, then index cache, then full vault scan.
    private func loadBookmarks() {
        cancelAllEnrichmentTasks()

        // Try SQLite first
        if let db = resolvedDatabase {
            loadBookmarksFromDatabase(db)
            if !bookmarks.isEmpty {
                let importedLegacySidecars = migrateLegacyBookmarkSidecarsIfNeeded()
                let mergedLegacyIndexCache = mergeLegacyIndexCacheIntoCanonicalBookmarks()
                if importedLegacySidecars || mergedLegacyIndexCache {
                    persistAllBookmarksToDatabase()
                    writeIndexCache()
                }
                pruneMissingBookmarksFromDisk(db)
                logger.info("Loaded \(self.bookmarks.count) bookmarks from database")
                Task { @MainActor [weak self] in
                    self?.adoptOrphanedVaultFiles()
                    self?.scheduleEnrichmentForIncompleteBookmarks()
                }
                return
            }
        }

        // Fall back to JSON index cache
        if var cached = loadFromIndexCache() {
            // Filter out bookmarks whose .webloc file no longer exists on disk
            cached = cached.filter { bookmark in
                guard let path = bookmark.relativePath else { return true }
                return FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(path).path)
            }
            bookmarks = cached
            let importedLegacySidecars = migrateLegacyBookmarkSidecarsIfNeeded()
            if importedLegacySidecars {
                writeIndexCache()
            }
            logger.info("Loaded \(cached.count) bookmarks from index cache")
            // One-time migration: persist JSON bookmarks to SQLite.
            // `persistBookmarkToDatabaseInner` scrubs dangling folder_id /
            // label_id references at the lowest level, so a single stale
            // reference can't abort the whole transaction.
            if !bookmarks.isEmpty, let db = resolvedDatabase {
                logger.info("Migrating \(self.bookmarks.count) bookmarks from JSON to SQLite")
                do {
                    try db.withTransaction {
                        for bookmark in self.bookmarks {
                            try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
                        }
                    }
                } catch {
                    logger.error("Failed to migrate JSON bookmarks to SQLite: \(error.localizedDescription)")
                }
            }
            // Verify cache against disk in background, adopt orphans
            Task { @MainActor [weak self] in
                self?.adoptOrphanedVaultFiles()
                self?.scheduleEnrichmentForIncompleteBookmarks()
            }
            return
        }

        // Full scan
        let scanned = scanAllVaultFolders()
        bookmarks = scanned
        _ = migrateLegacyBookmarkSidecarsIfNeeded()
        logger.info("Scanned \(self.bookmarks.count) bookmarks from vault folders")
        writeIndexCache()
        // Persist scanned bookmarks to SQLite
        if let db = resolvedDatabase {
            do {
                try db.withTransaction {
                    for bookmark in self.bookmarks {
                        try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
                    }
                }
            } catch {
                logger.error("Failed to persist scanned bookmarks to SQLite: \(error.localizedDescription)")
            }
        }
        scheduleEnrichmentForIncompleteBookmarks()
    }

    /// Reads the performance index cache.
    private func loadFromIndexCache() -> [Bookmark]? {
        guard let data = try? Data(contentsOf: indexFileURL) else { return nil }
        do {
            let decoded = try JSONDecoder().decode([Bookmark].self, from: data)
            return decoded
        } catch {
            logger.warning("Index cache decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes the current bookmarks array as the index cache.
    private func writeIndexCache() {
        guard writesVaultCaches else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(bookmarks)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            logger.error("Failed to write index cache: \(error.localizedDescription)")
        }
    }

    /// Full scan of all vault folders + Inbox/Bookmarks for .webloc files.
    private func scanAllVaultFolders() -> [Bookmark] {
        let fileService = BookmarkFileService.shared
        var result: [Bookmark] = []

        // Helper to process a single directory
        func processDirectory(dirURL: URL, dirRelativePath: String, folderID: UUID?) {
            let found = fileService.readAll(
                from: dirURL,
                dirRelativePath: dirRelativePath,
                includeLegacySidecarMetadata: false
            )
            for var bookmark in found {
                bookmark.folderID = folderID

                result.append(bookmark)
            }
        }

        // Scan vault folders FIRST — they are authoritative for folder assignment
        for folder in VaultFolderService.shared.folders {
            let dirURL = vaultRoot.appendingPathComponent(folder.relativePath)
            processDirectory(dirURL: dirURL, dirRelativePath: folder.relativePath, folderID: folder.id)
        }

        // Scan Inbox/Bookmarks (unfiled)
        processDirectory(dirURL: inboxBookmarksDir, dirRelativePath: inboxRelativePath, folderID: nil)

        // Sort by creation date descending (newest first)
        result.sort { $0.createdAt > $1.createdAt }
        return result
    }

    private func pruneMissingBookmarksFromDisk(_ db: CiderDatabase) {
        // Identify stale bookmarks WITHOUT mutating the in-memory array — if the
        // DB delete fails, we want memory and SQLite to stay consistent. Only
        // prune the array after the transaction commits successfully.
        let removedBookmarks: [Bookmark] = bookmarks.compactMap { bookmark in
            guard let relativePath = bookmark.relativePath else { return nil }
            let fileURL = vaultRoot.appendingPathComponent(relativePath)
            return FileManager.default.fileExists(atPath: fileURL.path) ? nil : bookmark
        }
        let removedIDs = removedBookmarks.map(\.id)
        guard !removedIDs.isEmpty else { return }

        do {
            try db.withTransaction {
                let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                for removedID in removedIDs {
                    stmt.reset()
                    stmt.bind(DatabaseHelpers.encode(removedID), at: 1)
                    try stmt.step()
                }
            }
            for bookmark in removedBookmarks {
                MutationAuditService(database: db).record(
                    action: "scanner.bookmark.prune_missing_file",
                    itemType: LibraryEntityType.bookmark.rawValue,
                    itemID: bookmark.id,
                    before: MutationAuditSnapshots.bookmark(bookmark),
                    metadata: [
                        "scanner": "pruneMissingBookmarksFromDisk",
                        "operation": "prune_missing_file",
                        "source": "filesystem",
                        "relativePath": bookmark.relativePath ?? "",
                    ],
                    source: .filesystem
                )
            }
            // Transaction committed — now it's safe to drop the stale rows from
            // the published array.
            let removedSet = Set(removedIDs)
            bookmarks.removeAll { removedSet.contains($0.id) }
            writeIndexCache()
            logger.info("Pruned \(removedIDs.count) bookmarks missing their .webloc files from disk")
        } catch {
            logger.error("Failed to prune bookmarks missing .webloc files: \(error.localizedDescription)")
        }
    }

    // MARK: - Persist

    /// Writes the index cache and pushes to sync. Does NOT write monolithic JSON/HTML.
    private func persist() {
        writeIndexCache()
        persistAllBookmarksToDatabase()
        if writesVaultCaches {
            SyncService.shared.pushAfterLocalChange()
        }
    }

    /// Persist all current bookmarks to the database.
    /// Mirrors the writeIndexCache() approach — full snapshot of current state.
    /// Wraps all writes in a single transaction for performance.
    ///
    /// `persistBookmarkToDatabaseInner` scrubs dangling folder_id and label_id
    /// references at the lowest level, so a single stale reference can't roll
    /// back the whole transaction and leave every write silently failing.
    private func persistAllBookmarksToDatabase() {
        guard let db = resolvedDatabase else { return }
        do {
            try db.withTransaction {
                for bookmark in bookmarks {
                    try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
                }
            }
        } catch {
            logger.error("Failed to persist bookmarks to database: \(error.localizedDescription)")
        }
    }

    /// One-time import of legacy bookmark sidecars into SQLite-backed bookmarks.
    /// Existing bookmarks only merge missing metadata; live `.webloc` files that
    /// never made it into SQLite are adopted if they are not duplicate URLs.
    @discardableResult
    private func migrateLegacyBookmarkSidecarsIfNeeded() -> Bool {
        var config = CiderConfig.load()
        guard !config.didMigrateBookmarkSidecarsToSQLite else { return false }

        let fileService = BookmarkFileService.shared
        let fm = FileManager.default
        var existingRelativePaths = Set(bookmarks.compactMap(\.relativePath))
        var existingURLs = Set(bookmarks.compactMap { bookmark -> String? in
            let url = bookmark.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return url.isEmpty ? nil : url
        })
        var adopted: [Bookmark] = []
        var changed = false

        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            config.didMigrateBookmarkSidecarsToSQLite = true
            config.save()
            return false
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent == BookmarkFileService.sidecarFileName else { continue }
            let dirURL = url.deletingLastPathComponent()
            let dirRelativePath = dirURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            let normalizedDirRelativePath = dirRelativePath == vaultRoot.path ? "" : dirRelativePath
            let folderID = normalizedDirRelativePath == inboxRelativePath
                ? nil
                : VaultFolderService.shared.folderID(for: normalizedDirRelativePath)

            let sidecar = fileService.loadSidecar(at: dirURL)
            for (filename, entry) in sidecar.items {
                let relativePath = normalizedDirRelativePath.isEmpty ? filename : "\(normalizedDirRelativePath)/\(filename)"
                let fileURL = dirURL.appendingPathComponent(filename)
                guard fm.fileExists(atPath: fileURL.path) else { continue }

                if let idx = bookmarks.firstIndex(where: { $0.relativePath == relativePath }) {
                    if Self.mergeLegacySidecarEntry(entry, into: &bookmarks[idx], fallbackFilename: filename) {
                        changed = true
                    }
                    continue
                }

                guard !existingRelativePaths.contains(relativePath),
                      var bookmark = fileService.read(
                        filename: filename,
                        from: dirURL,
                        dirRelativePath: normalizedDirRelativePath,
                        includeLegacySidecarMetadata: true
                      ) else { continue }

                let normalizedURL = bookmark.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !normalizedURL.isEmpty && existingURLs.contains(normalizedURL) {
                    continue
                }

                bookmark.folderID = folderID
                adopted.append(bookmark)
                existingRelativePaths.insert(relativePath)
                if !normalizedURL.isEmpty {
                    existingURLs.insert(normalizedURL)
                }
                changed = true
            }
        }

        if !adopted.isEmpty {
            bookmarks.append(contentsOf: adopted)
        }

        config.didMigrateBookmarkSidecarsToSQLite = true
        config.save()

        if !adopted.isEmpty {
            logger.info("Imported \(adopted.count) live bookmarks from legacy sidecars")
        }

        return changed
    }

    @discardableResult
    private func mergeLegacyIndexCacheIntoCanonicalBookmarks() -> Bool {
        guard let cached = loadFromIndexCache(), !cached.isEmpty else { return false }
        return mergeLegacyIndexBookmarks(cached, persistChanges: false)
    }

    /// Public to same-module callers that need to collapse cache-only bookmark
    /// metadata into the SQLite canonical bookmark while another process is
    /// still enriching/saving through the app path.
    @discardableResult
    func reconcileLegacyIndexCacheIntoCanonicalBookmarks() -> Bool {
        guard let cached = loadFromIndexCache(), !cached.isEmpty else { return false }
        return mergeLegacyIndexBookmarks(cached, persistChanges: true)
    }

    /// Merges richer legacy/index-cache bookmark metadata into already-loaded
    /// SQLite bookmarks without adopting the legacy cache row as a second item.
    @discardableResult
    func mergeLegacyIndexBookmarks(_ legacyBookmarks: [Bookmark], persistChanges: Bool = true) -> Bool {
        var changed = false
        for legacy in legacyBookmarks {
            let key = bookmarkURLDedupKey(legacy.urlString)
            guard !key.isEmpty,
                  let index = bookmarks.firstIndex(where: {
                      $0.id != legacy.id && bookmarkURLDedupKey($0.urlString) == key
                  }) else { continue }

            let existing = bookmarks[index]
            var merged = mergeLoadedDuplicateBookmark(existing: existing, duplicate: legacy)
            merged = renameBookmarkArtifactAfterTitleUpgrade(previous: existing, updated: merged)
            if merged != bookmarks[index] {
                bookmarks[index] = merged
                changed = true
            }
        }
        if changed, persistChanges {
            persist()
        }
        return changed
    }

    @discardableResult
    static func mergeLegacySidecarEntry(
        _ entry: BookmarkFileService.BookmarkSidecarEntry,
        into bookmark: inout Bookmark,
        fallbackFilename: String
    ) -> Bool {
        var changed = false
        let fallbackTitle = (fallbackFilename as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)

        let entryTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entryTitle.isEmpty {
            let currentTitle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bookmark.titleManuallySet && (currentTitle.isEmpty || currentTitle == fallbackTitle) {
                if bookmark.title != entryTitle {
                    bookmark.title = entryTitle
                    changed = true
                }
                if bookmark.titleManuallySet == false {
                    bookmark.titleManuallySet = true
                    changed = true
                }
            }
        }

        let entryNotes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookmark.notesManuallySet,
           bookmark.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !entryNotes.isEmpty {
            bookmark.notes = entryNotes
            bookmark.notesManuallySet = true
            changed = true
        }

        let mergedTags: [String]
        if bookmark.tags.isEmpty {
            var seen = Set<String>()
            mergedTags = entry.tags.compactMap { rawTag in
                let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let key = trimmed.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return trimmed
            }
        } else {
            mergedTags = bookmark.tags
        }
        if mergedTags != bookmark.tags {
            bookmark.tags = mergedTags
            changed = true
        }

        if bookmark.labelIDs.isEmpty, !entry.labelIDs.isEmpty {
            bookmark.labelIDs = entry.labelIDs
            changed = true
        }
        if bookmark.dismissedLabelIDs.isEmpty, !entry.dismissedLabelIDs.isEmpty {
            bookmark.dismissedLabelIDs = entry.dismissedLabelIDs
            changed = true
        }
        if bookmark.thumbnailRemoteURLString == nil, let thumbnailRemoteURLString = entry.thumbnailRemoteURLString {
            bookmark.thumbnailRemoteURLString = thumbnailRemoteURLString
            changed = true
        }
        if bookmark.thumbnailRelativePath == nil, let thumbnailFilename = entry.thumbnailFilename, !thumbnailFilename.isEmpty {
            bookmark.thumbnailRelativePath = "\(BookmarkFileService.thumbnailsDir)/\(thumbnailFilename)"
            changed = true
        }
        if bookmark.originalImageRelativePath == nil, let originalImageFilename = entry.originalImageFilename, !originalImageFilename.isEmpty {
            bookmark.originalImageRelativePath = "\(BookmarkFileService.originalsDir)/\(originalImageFilename)"
            changed = true
        }
        if bookmark.metadataUpdatedAt == nil, let metadataUpdatedAt = entry.metadataUpdatedAt {
            bookmark.metadataUpdatedAt = metadataUpdatedAt
            changed = true
        }
        if bookmark.aiSummary == nil, let aiSummary = entry.aiSummary, !aiSummary.isEmpty {
            bookmark.aiSummary = aiSummary
            changed = true
        }
        if bookmark.ocrText == nil, let ocrText = entry.ocrText, !ocrText.isEmpty {
            bookmark.ocrText = ocrText
            changed = true
        }
        if bookmark.dominantColors == nil, let dominantColors = entry.dominantColors, !dominantColors.isEmpty {
            bookmark.dominantColors = dominantColors
            changed = true
        }
        if bookmark.mediaType == nil, let mediaType = entry.mediaType {
            bookmark.mediaType = mediaType
            changed = true
        }
        if bookmark.carouselImagePaths == nil,
           let carouselImageFilenames = entry.carouselImageFilenames,
           !carouselImageFilenames.isEmpty {
            bookmark.carouselImagePaths = carouselImageFilenames.map { "\(BookmarkFileService.originalsDir)/\($0)" }
            changed = true
        }
        if bookmark.readerUnavailable == nil, let readerUnavailable = entry.readerUnavailable {
            bookmark.readerUnavailable = readerUnavailable
            changed = true
        }
        if bookmark.preferredHeroMode == nil, let preferredHeroMode = entry.preferredHeroMode, !preferredHeroMode.isEmpty {
            bookmark.preferredHeroMode = preferredHeroMode
            changed = true
        }
        if entry.createdAt < bookmark.createdAt {
            bookmark.createdAt = entry.createdAt
            changed = true
        }
        if entry.updatedAt > bookmark.updatedAt {
            bookmark.updatedAt = entry.updatedAt
            changed = true
        }

        return changed
    }

    // MARK: - Directory Resolution

    /// Maps a folderID to a vault directory URL and its relative path.
    private func resolveBookmarkDirectory(_ folderID: UUID?) -> (URL, String) {
        if let folderID,
           let vaultFolder = VaultFolderService.shared.folder(for: folderID) {
            let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
            return (dirURL, vaultFolder.relativePath)
        }
        // Default: Inbox/Bookmarks/
        return (inboxBookmarksDir, inboxRelativePath)
    }

    // MARK: - CRUD

    @discardableResult
    func add(urlString: String, title: String?, folderID: UUID? = nil) -> Bookmark? {
        guard let normalizedURL = normalizedURL(from: urlString) else { return nil }
        let canonical = normalizedURL.absoluteString

        let canonicalDedupKey = bookmarkURLDedupKey(canonical)

        // Check for existing bookmark with the same canonical URL. This must use
        // the same canonicalization as Vault Doctor so tracking params / `www.`
        // variants don't create a second live bookmark that the auditor will
        // immediately flag as a duplicate.
        if let existingIndex = bookmarks.firstIndex(where: {
            bookmarkURLDedupKey($0.urlString) == canonicalDedupKey
        }) {
            var existing = bookmarks.remove(at: existingIndex)
            let previous = existing
            if let title = duplicateCaptureTitleToApply(title, to: existing, sourceURL: normalizedURL) {
                existing.title = title
            }
            existing.updatedAt = Date()
            existing.urlString = canonical
            existing.isEnriching = false
            existing = renameBookmarkArtifactAfterTitleUpgrade(previous: previous, updated: existing)
            bookmarks.insert(existing, at: 0)
            persist()
            MutationAuditService(database: resolvedDatabase).record(
                action: "deduplicate_url_capture",
                itemType: "bookmark",
                itemID: existing.id,
                before: MutationAuditSnapshots.bookmark(previous),
                after: MutationAuditSnapshots.bookmark(existing),
                metadata: [
                    "incomingURL": urlString,
                    "canonicalURL": canonical,
                ]
            )
            SecondBrainItemMutationIndexer.rebuildAfterMutation(
                database: resolvedDatabase,
                ownerType: "bookmark",
                ownerID: existing.id
            )
            if let folderID, existing.folderID != folderID {
                _ = assignBookmark(existing.id, toFolder: folderID)
            }
            startEnrichmentIfNeeded(for: existing.id)
            return bookmarks.first(where: { $0.id == existing.id }) ?? existing
        }

        let resolvedTitle = resolvedTitle(for: normalizedURL, override: title)
        var bookmark = Bookmark(title: resolvedTitle, urlString: canonical)
        bookmark.folderID = folderID

        // Write .webloc file to the selected folder, falling back to Inbox/Bookmarks.
        let (dirURL, dirRelativePath) = resolveBookmarkDirectory(folderID)
        do {
            let relativePath = try BookmarkFileService.shared.write(
                bookmark: bookmark,
                toDirectory: dirURL,
                dirRelativePath: dirRelativePath
            )
            bookmark.relativePath = relativePath
        } catch {
            logger.error("Failed to write .webloc for new bookmark: \(error.localizedDescription)")
        }

        bookmarks.insert(bookmark, at: 0)
        persist()
        MutationAuditService.shared.record(
            action: "create",
            itemType: "bookmark",
            itemID: bookmark.id,
            after: MutationAuditSnapshots.bookmark(bookmark)
        )
        startEnrichmentIfNeeded(for: bookmark.id)
        return bookmark
    }

    /// Creates a bookmark for a saved image (no URL required).
    func addImageBookmark(title: String) -> Bookmark {
        var bookmark = Bookmark(title: title, urlString: "")

        // Write .webloc (will be empty since no URL)
        let (dirURL, dirRelativePath) = resolveBookmarkDirectory(nil)
        do {
            let relativePath = try BookmarkFileService.shared.write(
                bookmark: bookmark,
                toDirectory: dirURL,
                dirRelativePath: dirRelativePath
            )
            bookmark.relativePath = relativePath
        } catch {
            logger.error("Failed to write .webloc for image bookmark: \(error.localizedDescription)")
        }

        bookmarks.insert(bookmark, at: 0)
        persist()
        MutationAuditService.shared.record(
            action: "create",
            itemType: "bookmark",
            itemID: bookmark.id,
            after: MutationAuditSnapshots.bookmark(bookmark)
        )
        return bookmark
    }

    /// Sets the URL on an existing bookmark.
    func updateURL(for bookmarkID: UUID, urlString: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].urlString = urlString

        // Rewrite the .webloc plist on disk with the updated URL
        if let relativePath = bookmarks[index].relativePath {
            let fileURL = vaultRoot.appendingPathComponent(relativePath)
            if let url = URL(string: urlString) {
                let plist: [String: String] = ["URL": url.absoluteString]
                if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }

        persist()
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "bookmark",
            ownerID: bookmarkID
        )
    }

    @discardableResult
    func remove(_ bookmark: Bookmark) -> TrashItem {
        let before = MutationAuditSnapshots.bookmark(bookmark)
        cancelEnrichment(for: bookmark.id)
        SyncService.shared.trackDeletion(of: bookmark.id)
        // Track deleted URL so adoption doesn't re-adopt duplicate files
        if !bookmark.urlString.isEmpty {
            recentlyDeletedURLs[bookmarkURLDedupKey(bookmark.urlString)] = Date()
        }
        let (bookmarkDir, _) = resolveBookmarkDirectory(bookmark.folderID)
        let trashItem = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: bookmarkDir, bookmarksMetaDir: bookmarksMetaDir)
        deleteWeblocFileOnly(for: bookmark)
        bookmarks.removeAll { $0.id == bookmark.id }
        deleteBookmarkFromDatabase(bookmark.id)
        persist()
        MutationAuditService.shared.record(
            action: "delete",
            itemType: "bookmark",
            itemID: bookmark.id,
            before: before,
            after: MutationAuditSnapshots.trashItem(trashItem)
        )
        return trashItem
    }

    @discardableResult
    func removeAll(_ bookmarksToDelete: [Bookmark]) -> [TrashItem] {
        var trashItems: [TrashItem] = []
        var deletedPairs: [(Bookmark, TrashItem)] = []
        for bookmark in bookmarksToDelete {
            cancelEnrichment(for: bookmark.id)
            SyncService.shared.trackDeletion(of: bookmark.id)
            if !bookmark.urlString.isEmpty {
                recentlyDeletedURLs[bookmarkURLDedupKey(bookmark.urlString)] = Date()
            }
            let (bookmarkDir, _) = resolveBookmarkDirectory(bookmark.folderID)
            let item = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: bookmarkDir, bookmarksMetaDir: bookmarksMetaDir)
            deleteWeblocFileOnly(for: bookmark)
            trashItems.append(item)
            deletedPairs.append((bookmark, item))
        }
        let ids = Set(bookmarksToDelete.map(\.id))
        bookmarks.removeAll { ids.contains($0.id) }
        for id in ids {
            deleteBookmarkFromDatabase(id)
        }
        persist()
        for (bookmark, trashItem) in deletedPairs {
            MutationAuditService.shared.record(
                action: "delete",
                itemType: "bookmark",
                itemID: bookmark.id,
                before: MutationAuditSnapshots.bookmark(bookmark),
                after: MutationAuditSnapshots.trashItem(trashItem)
            )
        }
        return trashItems
    }

    /// Deletes the `.webloc` file and prunes any leftover legacy sidecar entry
    /// (not assets — TrashStorage handles those).
    private func deleteWeblocFileOnly(for bookmark: Bookmark) {
        guard let relativePath = bookmark.relativePath, !relativePath.isEmpty else { return }
        let fileURL = vaultRoot.appendingPathComponent(relativePath)
        let filename = fileURL.lastPathComponent
        let dirURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: fileURL)
        BookmarkFileService.shared.removeSidecarEntry(at: dirURL, filename: filename)
    }

    /// Deletes the .webloc file, assets, and sidecar entry from disk (full cleanup).
    private func deleteWeblocFile(for bookmark: Bookmark) {
        guard let relativePath = bookmark.relativePath, !relativePath.isEmpty else { return }
        let fileURL = vaultRoot.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let filename = fileURL.lastPathComponent
            let dirURL = fileURL.deletingLastPathComponent()
            BookmarkFileService.shared.delete(bookmark: bookmark, filename: filename, from: dirURL)
        }
    }

    func restoreFromTrash(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        var restored = bookmark
        restored.isEnriching = false
        restored.updatedAt = Date()
        SyncService.shared.cancelDeletion(of: bookmark.id)

        // Write a new .webloc file
        let (dirURL, dirRelativePath) = resolveBookmarkDirectory(restored.folderID)
        do {
            let relativePath = try BookmarkFileService.shared.write(
                bookmark: restored,
                toDirectory: dirURL,
                dirRelativePath: dirRelativePath
            )
            restored.relativePath = relativePath
        } catch {
            logger.error("Failed to write .webloc for restored bookmark: \(error.localizedDescription)")
        }

        bookmarks.insert(restored, at: 0)
        persist()
        MutationAuditService.shared.record(
            action: "restore",
            itemType: "bookmark",
            itemID: restored.id,
            before: MutationAuditSnapshots.trashItem(
                TrashItem(
                    itemID: restored.id,
                    itemType: .bookmark,
                    title: restored.title,
                    originalFolderID: restored.folderID
                )
            ),
            after: MutationAuditSnapshots.bookmark(restored)
        )
    }

    // MARK: - Update Details

    @discardableResult
    func updateDetails(
        for bookmarkID: UUID,
        title: String,
        notes: String,
        tags: [String],
        labelIDs: [UUID]? = nil,
        urlString: String? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        var bookmark = bookmarks[index]
        let before = MutationAuditSnapshots.bookmark(bookmark)
        let oldTitle = bookmark.title
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
            bookmark.titleManuallySet = true
            changed = true
        }
        if bookmark.notes != normalizedNotes {
            bookmark.notes = normalizedNotes
            bookmark.notesManuallySet = true
            changed = true
        }
        if bookmark.tags != normalizedTags { bookmark.tags = normalizedTags; changed = true }
        if let labelIDs, bookmark.labelIDs != labelIDs { bookmark.labelIDs = labelIDs; changed = true }
        if let urlString {
            let normalizedSource = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if bookmark.urlString != normalizedSource { bookmark.urlString = normalizedSource; changed = true }
        }

        if changed {
            bookmark.updatedAt = Date()
            bookmarks[index] = bookmark
            persist()
            SecondBrainItemMutationIndexer.rebuildAfterMutation(
                database: resolvedDatabase,
                ownerType: "bookmark",
                ownerID: bookmarkID
            )
            if oldTitle != bookmark.title {
                MutationAuditService.shared.record(
                    action: "rename",
                    itemType: "bookmark",
                    itemID: bookmarkID,
                    before: before,
                    after: MutationAuditSnapshots.bookmark(bookmark)
                )
            }
        }

        return true
    }

    /// Updates AI-owned enrichment fields without touching user-owned notes.
    @discardableResult
    func updateEnrichment(
        for bookmarkID: UUID,
        aiSummary: String? = nil,
        clearAISummary: Bool = false,
        enrichmentStatus: String? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        var changed = false
        if clearAISummary, bookmarks[index].aiSummary != nil {
            bookmarks[index].aiSummary = nil
            changed = true
        } else if let aiSummary, bookmarks[index].aiSummary != aiSummary {
            bookmarks[index].aiSummary = aiSummary
            changed = true
        }
        if let enrichmentStatus, bookmarks[index].enrichmentStatus != enrichmentStatus {
            bookmarks[index].enrichmentStatus = enrichmentStatus
            changed = true
        }
        if changed {
            bookmarks[index].lastEnrichedAt = Date()
            bookmarks[index].updatedAt = Date()
            persist()
            SecondBrainItemMutationIndexer.rebuildAfterMutation(
                database: resolvedDatabase,
                ownerType: "bookmark",
                ownerID: bookmarkID
            )
        }
        return changed
    }

    func previewNormalizedURLString(from rawValue: String) -> String? {
        normalizedURL(from: rawValue)?.absoluteString
    }

    // MARK: - Folder Assignment

    @discardableResult
    func assignBookmark(
        _ bookmarkID: UUID,
        toFolder folderID: UUID?,
        auditMetadata: [String: String]? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        if let folderID, VaultFolderService.shared.folder(for: folderID) == nil {
            return false
        }

        if bookmarks[index].folderID == folderID {
            return true
        }

        let bookmark = bookmarks[index]
        let before = MutationAuditSnapshots.bookmark(bookmark)

        // PHYSICALLY MOVE the .webloc file
        if let relativePath = bookmark.relativePath, !relativePath.isEmpty {
            let sourceFileURL = vaultRoot.appendingPathComponent(relativePath)
            let filename = sourceFileURL.lastPathComponent
            let sourceDirURL = sourceFileURL.deletingLastPathComponent()
            let (destDirURL, destDirRelativePath) = resolveBookmarkDirectory(folderID)

            if sourceDirURL.path != destDirURL.path {
                do {
                    let newRelativePath = try BookmarkFileService.shared.move(
                        bookmark: bookmark,
                        filename: filename,
                        from: sourceDirURL,
                        to: destDirURL,
                        destDirRelativePath: destDirRelativePath
                    )
                    bookmarks[index].relativePath = newRelativePath
                } catch {
                    logger.error("Failed to move .webloc file: \(error.localizedDescription)")
                    return false
                }
            }
        }

        bookmarks[index].folderID = folderID
        bookmarks[index].updatedAt = Date()
        persist()
        MutationAuditService.shared.record(
            action: "reassign_folder",
            itemType: "bookmark",
            itemID: bookmarkID,
            before: before,
            after: MutationAuditSnapshots.bookmark(bookmarks[index]),
            metadata: auditMetadata ?? [
                "classification": "manual_organization",
                "routingSource": "none",
            ]
        )
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "bookmark",
            ownerID: bookmarkID
        )
        return true
    }

    // MARK: - Labels

    @discardableResult
    func assignLabel(_ bookmarkID: UUID, labelID: UUID) -> Bool {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        guard !bookmarks[idx].labelIDs.contains(labelID) else { return true }
        let before = MutationAuditSnapshots.bookmark(bookmarks[idx])
        bookmarks[idx].labelIDs.append(labelID)
        persist()
        MutationAuditService.shared.record(
            action: "assign_label",
            itemType: "bookmark",
            itemID: bookmarkID,
            before: before,
            after: MutationAuditSnapshots.bookmark(bookmarks[idx]),
            metadata: ["labelID": labelID.uuidString]
        )
        return true
    }

    @discardableResult
    func removeLabel(_ bookmarkID: UUID, labelID: UUID) -> Bool {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        guard bookmarks[idx].labelIDs.contains(labelID) else { return true }
        let before = MutationAuditSnapshots.bookmark(bookmarks[idx])
        bookmarks[idx].labelIDs.removeAll { $0 == labelID }
        if !bookmarks[idx].dismissedLabelIDs.contains(labelID) {
            bookmarks[idx].dismissedLabelIDs.append(labelID)
        }
        persist()
        MutationAuditService.shared.record(
            action: "remove_label",
            itemType: "bookmark",
            itemID: bookmarkID,
            before: before,
            after: MutationAuditSnapshots.bookmark(bookmarks[idx]),
            metadata: ["labelID": labelID.uuidString]
        )
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

    // MARK: - Sync Helpers

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

        let incomingDedupKey = bookmarkURLDedupKey(urlString)
        if !incomingDedupKey.isEmpty,
           let existingIndex = bookmarks.firstIndex(where: { bookmarkURLDedupKey($0.urlString) == incomingDedupKey }) {
            var existing = bookmarks.remove(at: existingIndex)
            let merged = mergeSyncedDuplicateBookmark(
                existing: existing,
                incomingTitle: title,
                incomingURLString: urlString,
                incomingNotes: notes,
                incomingTags: tags,
                incomingThumbnailRemoteURLString: thumbnailRemoteURLString,
                incomingAISummary: aiSummary,
                incomingDominantColors: dominantColors,
                incomingUpdatedAt: updatedAt,
                incomingFolderID: folderID
            )
            existing = merged
            bookmarks.insert(existing, at: 0)
            bookmarks.sort { $0.createdAt > $1.createdAt }
            persist()
            if existing.thumbnailRelativePath == nil {
                startEnrichmentIfNeeded(for: existing.id)
            }
            logger.warning("Skipped synced duplicate bookmark URL \(urlString, privacy: .public); merged metadata into existing bookmark \(existing.id.uuidString, privacy: .public)")
            return
        }

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

        // Write .webloc file
        let (dirURL, dirRelativePath) = resolveBookmarkDirectory(folderID)
        do {
            let relativePath = try BookmarkFileService.shared.write(
                bookmark: bookmark,
                toDirectory: dirURL,
                dirRelativePath: dirRelativePath
            )
            bookmark.relativePath = relativePath
        } catch {
            logger.error("Failed to write .webloc for sync bookmark: \(error.localizedDescription)")
        }

        bookmarks.insert(bookmark, at: 0)
        bookmarks.sort { $0.createdAt > $1.createdAt }
        persist()
        startEnrichmentIfNeeded(for: id)
    }

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
        if let aiSummary { bookmarks[index].aiSummary = aiSummary }
        if let dominantColors { bookmarks[index].dominantColors = dominantColors }
        // If folderID changed, physically move the .webloc file to the new folder
        let oldFolderID = bookmarks[index].folderID
        bookmarks[index].folderID = folderID
        if oldFolderID != folderID,
           let relativePath = bookmarks[index].relativePath, !relativePath.isEmpty {
            let sourceFileURL = vaultRoot.appendingPathComponent(relativePath)
            let filename = sourceFileURL.lastPathComponent
            let sourceDirURL = sourceFileURL.deletingLastPathComponent()
            let (destDirURL, destDirRelativePath) = resolveBookmarkDirectory(folderID)
            if sourceDirURL.path != destDirURL.path {
                do {
                    let newRelativePath = try BookmarkFileService.shared.move(
                        bookmark: bookmarks[index],
                        filename: filename,
                        from: sourceDirURL,
                        to: destDirURL,
                        destDirRelativePath: destDirRelativePath
                    )
                    bookmarks[index].relativePath = newRelativePath
                } catch {
                    logger.error("updateFromSync: failed to move .webloc file: \(error.localizedDescription)")
                }
            }
        }
        bookmarks[index].updatedAt = remoteUpdatedAt
        persist()

        if bookmarks[index].thumbnailRelativePath == nil {
            startEnrichmentIfNeeded(for: bookmarkID)
        }
    }

    func removeSynced(_ bookmark: Bookmark) {
        MutationAuditContext.withSource(.cleanup) {
            let before = MutationAuditSnapshots.bookmark(bookmark)
            cancelEnrichment(for: bookmark.id)
            deleteWeblocFile(for: bookmark)
            bookmarks.removeAll { $0.id == bookmark.id }
            deleteBookmarkFromDatabase(bookmark.id)
            persist()
            MutationAuditService.shared.record(
                action: "delete",
                itemType: "bookmark",
                itemID: bookmark.id,
                before: before,
                after: ["state": "removed_by_sync"],
                metadata: ["reason": "sync_remove"]
            )
        }
    }

    func trashFromSync(_ bookmark: Bookmark) {
        MutationAuditContext.withSource(.cleanup) {
            cancelEnrichment(for: bookmark.id)
            let (bookmarkDir, _) = resolveBookmarkDirectory(bookmark.folderID)
            let trashItem = TrashStorage.shared.trashBookmark(bookmark, bookmarksDir: bookmarkDir, bookmarksMetaDir: bookmarksMetaDir)
            deleteWeblocFile(for: bookmark)
            bookmarks.removeAll { $0.id == bookmark.id }
            deleteBookmarkFromDatabase(bookmark.id)
            persist()
            MutationAuditService.shared.record(
                action: "delete",
                itemType: "bookmark",
                itemID: bookmark.id,
                before: MutationAuditSnapshots.bookmark(bookmark),
                after: MutationAuditSnapshots.trashItem(trashItem),
                metadata: ["reason": "sync_trash"]
            )
        }
    }

    // MARK: - Import/Export

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

    // MARK: - Pasteboard

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

    // MARK: - Vault File Adoption

    /// Scans all vault folders for `.webloc` files not already tracked.
    /// Adopts them as new bookmarks and reassigns moved ones.
    func adoptOrphanedVaultFiles() {
        guard !isAdopting else { return }
        guard Date().timeIntervalSince(lastAdoptionScan) >= adoptionDebounceInterval else { return }
        isAdopting = true
        defer {
            isAdopting = false
            lastAdoptionScan = Date()
        }

        // Purge expired entries from recentlyDeletedURLs
        let now = Date()
        recentlyDeletedURLs = recentlyDeletedURLs.filter { now.timeIntervalSince($0.value) < recentlyDeletedTTL }

        let fileService = BookmarkFileService.shared
        let fm = FileManager.default

        var existingIDByURL: [String: UUID] = [:]
        var existingIDByRelativePath: [String: UUID] = [:]
        var existingIDs = Set<UUID>()
        for bm in bookmarks {
            let url = bookmarkURLDedupKey(bm.urlString)
            if !url.isEmpty { existingIDByURL[url] = bm.id }
            if let relativePath = bm.relativePath {
                existingIDByRelativePath[relativePath] = bm.id
            }
            existingIDs.insert(bm.id)
        }

        var adopted: [Bookmark] = []
        var reassigned = 0
        var externalURLUpdates = 0

        func processDirectory(dirURL: URL, dirRelativePath: String, folderID: UUID?) {
            guard fm.fileExists(atPath: dirURL.path) else { return }
            let found = fileService.readAll(
                from: dirURL,
                dirRelativePath: dirRelativePath,
                includeLegacySidecarMetadata: false
            )
            for var bookmark in found {
                let url = bookmarkURLDedupKey(bookmark.urlString)

                // Image-only bookmarks (no URL): match by sidecar UUID
                if url.isEmpty {
                    if existingIDs.contains(bookmark.id) {
                        // Known bookmark — update folderID/relativePath if moved
                        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }),
                           bookmarks[idx].folderID != folderID {
                            bookmarks[idx].folderID = folderID
                            bookmarks[idx].relativePath = bookmark.relativePath
                            reassigned += 1
                        }
                    } else {
                        // New image bookmark from disk
                        bookmark.folderID = folderID
                        adopted.append(bookmark)
                        existingIDs.insert(bookmark.id)
                    }
                    continue
                }

                // Skip URLs that were recently deleted (prevents zombie re-adoption from duplicate files)
                if recentlyDeletedURLs[url] != nil {
                    continue
                }

                // Same file, changed `.webloc` URL: treat the visible file as the
                // content artifact and update SQLite metadata in place.
                if let relativePath = bookmark.relativePath,
                   let existingID = existingIDByRelativePath[relativePath],
                   let idx = bookmarks.firstIndex(where: { $0.id == existingID }) {
                    let oldURL = bookmarkURLDedupKey(bookmarks[idx].urlString)
                    if oldURL != url {
                        bookmarks[idx].urlString = bookmark.urlString
                        bookmarks[idx].updatedAt = Date()
                        if !bookmarks[idx].titleManuallySet {
                            bookmarks[idx].title = bookmark.title
                        }
                        if !oldURL.isEmpty {
                            existingIDByURL.removeValue(forKey: oldURL)
                        }
                        existingIDByURL[url] = existingID
                        externalURLUpdates += 1
                    }
                    if bookmarks[idx].folderID != folderID {
                        bookmarks[idx].folderID = folderID
                        reassigned += 1
                    }
                    continue
                }

                if let existingID = existingIDByURL[url] {
                    if let idx = bookmarks.firstIndex(where: { $0.id == existingID }) {
                        let existingPath = bookmarks[idx].relativePath
                        let existingFileExists = existingPath
                            .map { fm.fileExists(atPath: vaultRoot.appendingPathComponent($0).path) }
                            ?? false
                        if existingFileExists {
                            let merged = mergeLoadedDuplicateBookmark(existing: bookmarks[idx], duplicate: bookmark)
                            if merged != bookmarks[idx] {
                                bookmarks[idx] = merged
                                externalURLUpdates += 1
                            }
                            // Preserve the second .webloc by adopting as separate duplicate candidate.
                            // The duplicate auditor/review queue can then surface both artifacts for
                            // human review instead of the scanner silently deleting user-visible data.
                            bookmark.folderID = folderID
                            adopted.append(bookmark)
                            existingIDs.insert(bookmark.id)
                            if let relativePath = bookmark.relativePath {
                                existingIDByRelativePath[relativePath] = bookmark.id
                            }
                            logger.warning("Adopted duplicate bookmark URL artifact at \(bookmark.relativePath ?? "?", privacy: .public) as a reviewable duplicate candidate alongside canonical bookmark \(existingID.uuidString, privacy: .public)")
                        } else if bookmarks[idx].folderID != folderID || bookmarks[idx].relativePath != bookmark.relativePath {
                            bookmarks[idx].folderID = folderID
                            bookmarks[idx].relativePath = bookmark.relativePath
                            if let relativePath = bookmark.relativePath {
                                existingIDByRelativePath[relativePath] = existingID
                            }
                            reassigned += 1
                        }
                    }
                } else {
                    bookmark.folderID = folderID
                    adopted.append(bookmark)
                    existingIDByURL[url] = bookmark.id
                    if let relativePath = bookmark.relativePath {
                        existingIDByRelativePath[relativePath] = bookmark.id
                    }
                    existingIDs.insert(bookmark.id)
                }
            }
        }

        // Scan vault folders FIRST — they are authoritative for folder assignment
        for folder in VaultFolderService.shared.folders {
            let dirURL = vaultRoot.appendingPathComponent(folder.relativePath)
            processDirectory(dirURL: dirURL, dirRelativePath: folder.relativePath, folderID: folder.id)
        }

        // Scan Inbox/Bookmarks — files whose URL is already claimed by a vault folder
        // are skipped (not deleted) so the user never loses data silently.
        processDirectory(dirURL: inboxBookmarksDir, dirRelativePath: inboxRelativePath, folderID: nil)

        if !adopted.isEmpty || reassigned > 0 || externalURLUpdates > 0 {
            if !adopted.isEmpty {
                logger.info("Adopted \(adopted.count) orphaned .webloc files from vault folders")
                bookmarks.append(contentsOf: adopted)
            }
            if reassigned > 0 {
                logger.info("Reassigned \(reassigned) bookmarks to match filesystem folders")
            }
            if externalURLUpdates > 0 {
                logger.info("Updated \(externalURLUpdates) bookmarks from externally edited .webloc files")
            }
            persist()
            if !adopted.isEmpty {
                scheduleEnrichmentForIncompleteBookmarks()
            }
        }
    }

    // MARK: - Reload

    /// Re-scans vault folders and rebuilds the bookmarks array from disk.
    func reloadFromDisk() {
        cancelAllEnrichmentTasks()
        if let db = resolvedDatabase {
            loadBookmarksFromDatabase(db)
            pruneMissingBookmarksFromDisk(db)
            adoptOrphanedVaultFiles()
            scheduleEnrichmentForIncompleteBookmarks()
            return
        }

        let scanned = scanAllVaultFolders()
        bookmarks = scanned
        writeIndexCache()
        persistAllBookmarksToDatabase()
        scheduleEnrichmentForIncompleteBookmarks()
    }

    func updateDirectory(to newPath: String) {
        StoragePaths.invalidateCachedDirectory()
        reloadFromDisk()
    }

    // MARK: - Thumbnails/Media

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
              scheme == "http" || scheme == "https" else { return false }

        guard let assets = await cacheImageAssets(from: sourceURL, for: bookmarkID) else { return false }

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
        ) else { return false }

        return applyManualThumbnail(
            for: bookmarkID,
            assets: assets,
            remoteURLString: nil
        )
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

    // MARK: - AI Results

    func applyAIResults(
        for bookmarkID: UUID,
        tags: [String],
        ocrText: String?,
        dominantColors: [String]?,
        title: String? = nil
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        let previous = bookmarks[index]
        var bookmark = bookmarks[index]
        var changed = false
        if bookmark.tags != tags { bookmark.tags = tags; changed = true }
        if bookmark.ocrText != ocrText { bookmark.ocrText = ocrText; changed = true }
        if bookmark.dominantColors != dominantColors { bookmark.dominantColors = dominantColors; changed = true }
        if let title, !title.isEmpty, bookmark.title != title, !bookmark.titleManuallySet { bookmark.title = title; changed = true }
        changed = markEnrichmentComplete(&bookmark) || changed
        guard changed else { return }
        bookmark = renameBookmarkArtifactAfterTitleUpgrade(previous: previous, updated: bookmark)
        bookmarks[index] = bookmark
        persist()
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "bookmark",
            ownerID: bookmarkID
        )
    }

    @discardableResult
    func applyStoredOCRTitleCandidateIfNeeded(for bookmarkID: UUID) -> Bookmark? {
        guard let bookmark = bookmarks.first(where: { $0.id == bookmarkID }),
              let ocrText = bookmark.ocrText,
              let title = BookmarkAIEnrichment.suggestedTitleFromOCR(
                  ocrText,
                  currentTitle: bookmark.title,
                  urlString: bookmark.urlString,
                  titleManuallySet: bookmark.titleManuallySet
              )
        else { return nil }

        applyAIResults(
            for: bookmarkID,
            tags: bookmark.tags,
            ocrText: bookmark.ocrText,
            dominantColors: bookmark.dominantColors,
            title: title
        )
        return bookmarks.first(where: { $0.id == bookmarkID })
    }

    @discardableResult
    func applyStoredSemanticTitleCandidateIfNeeded(for bookmarkID: UUID) -> Bookmark? {
        if let updated = applyStoredOCRTitleCandidateIfNeeded(for: bookmarkID) {
            return updated
        }
        guard let bookmark = bookmarks.first(where: { $0.id == bookmarkID }),
              let title = BookmarkAIEnrichment.suggestedTitleFromNotes(
                  bookmark.notes,
                  currentTitle: bookmark.title,
                  urlString: bookmark.urlString,
                  titleManuallySet: bookmark.titleManuallySet
              )
        else { return nil }

        applyAIResults(
            for: bookmarkID,
            tags: bookmark.tags,
            ocrText: bookmark.ocrText,
            dominantColors: bookmark.dominantColors,
            title: title
        )
        return bookmarks.first(where: { $0.id == bookmarkID })
    }

    func applyOEmbedResults(
        for bookmarkID: UUID,
        title: String?,
        notes: String?
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        let previous = bookmarks[index]
        var bookmark = bookmarks[index]
        var changed = false
        if let title, !title.isEmpty,
           let sourceURL = URL(string: bookmark.urlString),
           shouldApplyEnrichedTitle(title, to: bookmark, sourceURL: sourceURL) {
            bookmark.title = title; changed = true
        }
        // Only set notes if the bookmark doesn't already have user-written notes
        if let notes, !notes.isEmpty, bookmark.notes.isEmpty, !bookmark.notesManuallySet {
            bookmark.notes = notes; changed = true
        }
        changed = markEnrichmentComplete(&bookmark) || changed
        guard changed else { return }
        bookmark = renameBookmarkArtifactAfterTitleUpgrade(previous: previous, updated: bookmark)
        bookmarks[index] = bookmark
        persist()
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "bookmark",
            ownerID: bookmarkID
        )
    }

    func applyAISummary(_ summary: String, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].aiSummary != summary else { return }
        bookmarks[index].aiSummary = summary
        persist()
        SecondBrainItemMutationIndexer.rebuildAfterMutation(
            database: resolvedDatabase,
            ownerType: "bookmark",
            ownerID: bookmarkID
        )
    }

    /// Force re-fetch metadata and thumbnail from the web for a bookmark.
    func refetchMetadata(for bookmarkID: UUID) {
        cancelEnrichment(for: bookmarkID)
        startEnrichmentIfNeeded(for: bookmarkID, force: true)
    }

    // MARK: - Carousel Image Management

    private static let maxCarouselImages = 10

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
            let existingURL = bookmarksMetaDir.appendingPathComponent(existingOriginal)
            if fm.fileExists(atPath: existingURL.path) {
                let ext = existingURL.pathExtension
                let newName = "\(originalImagesDirectoryName)/\(bookmarkID.uuidString)_0.\(ext)"
                let newURL = bookmarksMetaDir.appendingPathComponent(newName)
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
        let fileURL = bookmarksMetaDir.appendingPathComponent(relativePath)

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

    @discardableResult
    func replaceCarouselImagesForEnrichment(
        for bookmarkID: UUID,
        imageDataList: [Data],
        preferredFileExtension: String? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        let validImageData = imageDataList.filter { data in
            data.count > 128 && data.count < 12_000_000 && NSImage(data: data) != nil
        }

        var bookmark = bookmarks[index]
        let existingOriginalPath = bookmark.originalImageRelativePath?.isEmpty == false
            ? bookmark.originalImageRelativePath
            : nil
        let existingOriginalURL = existingOriginalPath.map {
            bookmarksMetaDir.appendingPathComponent($0)
        }
        let hasExistingOriginal = existingOriginalURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false

        guard hasExistingOriginal || !validImageData.isEmpty else { return false }

        let previousCarouselPaths = bookmark.carouselImagePaths ?? []
        for path in previousCarouselPaths where path != existingOriginalPath {
            removeImageIfPresent(relativePath: path)
        }

        var replacementPaths: [String] = []
        if let existingOriginalPath, let existingOriginalURL, hasExistingOriginal {
            let ext = normalizedImageFileExtension(existingOriginalURL.pathExtension)
            let promotedPath = "\(originalImagesDirectoryName)/\(bookmarkID.uuidString)_0.\(ext)"
            let promotedURL = bookmarksMetaDir.appendingPathComponent(promotedPath)
            if existingOriginalURL.path != promotedURL.path {
                try? FileManager.default.removeItem(at: promotedURL)
                do {
                    try FileManager.default.moveItem(at: existingOriginalURL, to: promotedURL)
                    bookmark.originalImageRelativePath = promotedPath
                    replacementPaths.append(promotedPath)
                } catch {
                    bookmark.originalImageRelativePath = existingOriginalPath
                    replacementPaths.append(existingOriginalPath)
                }
            } else {
                bookmark.originalImageRelativePath = promotedPath
                replacementPaths.append(promotedPath)
            }
        }

        do {
            try FileManager.default.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
            let availableSlots = max(0, Self.maxCarouselImages - replacementPaths.count)
            for data in validImageData.prefix(availableSlots) {
                let nextIndex = replacementPaths.count
                let ext = normalizedImageFileExtension(preferredFileExtension)
                let relativePath = "\(originalImagesDirectoryName)/\(bookmarkID.uuidString)_\(nextIndex).\(ext)"
                let fileURL = bookmarksMetaDir.appendingPathComponent(relativePath)
                try data.write(to: fileURL, options: .atomic)
                replacementPaths.append(relativePath)
            }
        } catch {
            return false
        }

        bookmark.originalImageRelativePath = replacementPaths.first
        bookmark.carouselImagePaths = replacementPaths.count > 1 ? replacementPaths : nil
        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

    @discardableResult
    func removeCarouselImage(for bookmarkID: UUID, at imageIndex: Int) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }
        var bookmark = bookmarks[index]
        guard var paths = bookmark.carouselImagePaths, paths.indices.contains(imageIndex) else { return false }

        let removedPath = paths.remove(at: imageIndex)
        removeImageIfPresent(relativePath: removedPath)

        if paths.count <= 1 {
            bookmark.carouselImagePaths = nil
            if let remaining = paths.first {
                bookmark.originalImageRelativePath = remaining
                regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: remaining)
            }
        } else {
            bookmark.carouselImagePaths = paths
            if imageIndex == 0 {
                regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: paths[0])
            }
        }

        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

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

        let firstChanged = fromIndex == 0 || toIndex == 0
        if firstChanged {
            regenerateThumbnail(for: bookmarkID, fromOriginalRelativePath: paths[0])
        }

        bookmark.updatedAt = Date()
        bookmarks[index] = bookmark
        persist()
        return true
    }

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

    // MARK: - Enrichment Pipeline

    private func cancelAllEnrichmentTasks() {
        for task in enrichmentTasks.values { task.cancel() }
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

    private func recoverMissingThumbnails() {
        let candidates = bookmarks.filter { bookmark in
            guard let remoteURLString = bookmark.thumbnailRemoteURLString,
                  let remoteURL = URL(string: remoteURLString),
                  !Self.isLowConfidenceThumbnailURL(remoteURL) else { return false }
            return !localThumbnailExists(relativePath: bookmark.thumbnailRelativePath)
        }

        guard !candidates.isEmpty else { return }
        logger.info("Recovering missing thumbnails for \(candidates.count) bookmark(s)")

        for bookmark in candidates {
            guard enrichmentTasks[bookmark.id] == nil,
                  let remoteURLString = bookmark.thumbnailRemoteURLString,
                  let remoteURL = URL(string: remoteURLString) else { continue }

            let bookmarkID = bookmark.id
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                let imageAssets = await self.cacheImageAssets(from: remoteURL, for: bookmarkID)
                await self.applyRecoveredThumbnail(bookmarkID: bookmarkID, imageAssets: imageAssets)
            }
            enrichmentTasks[bookmarkID] = task
        }
    }

    private func applyRecoveredThumbnail(bookmarkID: UUID, imageAssets: BookmarkImageAssets?) async {
        defer { enrichmentTasks.removeValue(forKey: bookmarkID) }

        guard let imageAssets,
              let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }

        removeImageIfPresent(relativePath: bookmarks[index].thumbnailRelativePath)
        removeImageIfPresent(relativePath: bookmarks[index].originalImageRelativePath)

        bookmarks[index].thumbnailRelativePath = imageAssets.thumbnailRelativePath
        bookmarks[index].originalImageRelativePath = imageAssets.originalImageRelativePath

        if let remoteURL = bookmarks[index].thumbnailRemoteURLString,
           remoteURL.hasPrefix("http://") {
            bookmarks[index].thumbnailRemoteURLString = "https://" + remoteURL.dropFirst(7)
        }

        bookmarks[index].updatedAt = Date()
        persist()
        logger.info("Recovered thumbnail for bookmark \(bookmarkID)")
    }

    private func startEnrichmentIfNeeded(for bookmarkID: UUID, force: Bool = false) {
        guard schedulesEnrichment else { return }
        guard enrichmentTasks[bookmarkID] == nil else { return }
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard let url = URL(string: bookmarks[index].urlString) else { return }

        let bookmark = bookmarks[index]
        guard force || shouldEnrich(bookmark, for: url) else { return }

        bookmarks[index].isEnriching = true
        objectWillChange.send()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            // Direct image URL
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
            let trustedThumbnailURL = payload?.thumbnailURL.flatMap { candidate in
                Self.isLowConfidenceThumbnailURL(candidate) ? nil : candidate
            }

            var imageAssets: BookmarkImageAssets?
            if let thumbnailURL = trustedThumbnailURL {
                imageAssets = await self.cacheImageAssets(from: thumbnailURL, for: bookmarkID, pageURL: url)
            }

            if imageAssets == nil,
               let fallbackData = payload?.thumbnailFallbackData {
                imageAssets = self.cacheImageAssets(
                    from: fallbackData,
                    for: bookmarkID,
                    preferredFileExtension: "png"
                )
            }

            // Screenshot fallback only when native metadata did not find a provider
            // thumbnail. If a provider thumbnail URL exists but downloading it fails,
            // keep the remote URL for retry instead of locking in a generic page shell.
            if imageAssets == nil,
               BookmarkNativeCapturePolicy.allowsScreenshotFallback(thumbnailURL: trustedThumbnailURL),
               let screenshotData = payload?.screenshotData {
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

    func completeMetadataEnrichment(
        for bookmarkID: UUID,
        sourceURL: URL,
        payload: BookmarkEnrichmentPayload?
    ) async {
        await completeEnrichment(
            for: bookmarkID,
            sourceURL: sourceURL,
            payload: payload,
            imageAssets: nil
        )
    }

    private func completeEnrichment(
        for bookmarkID: UUID,
        sourceURL: URL,
        payload: BookmarkEnrichmentPayload?,
        imageAssets: BookmarkImageAssets?
    ) async {
        defer { enrichmentTasks.removeValue(forKey: bookmarkID) }

        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }

        let previous = bookmarks[index]
        var bookmark = bookmarks[index]
        var changed = false

        if let enrichedTitle = payload?.title,
           shouldApplyEnrichedTitle(enrichedTitle, to: bookmark, sourceURL: sourceURL) {
            bookmark.title = enrichedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            changed = true
        }

        if let recipeExtractionText = payload?.recipeExtractionText,
           !recipeExtractionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           shouldApplyRecipeExtractionText(recipeExtractionText, to: bookmark) {
            bookmark.aiSummary = mergedRecipeExtractionSummary(
                existing: bookmark.aiSummary,
                recipeExtractionText: recipeExtractionText
            )
            bookmark.enrichmentStatus = "partial"
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
            if let remoteURL = payload?.thumbnailURL,
               !Self.isLowConfidenceThumbnailURL(remoteURL),
               bookmark.thumbnailRemoteURLString != remoteURL.absoluteString {
                bookmark.thumbnailRemoteURLString = remoteURL.absoluteString
                changed = true
            }
        } else if let remoteURL = payload?.thumbnailURL,
                  !Self.isLowConfidenceThumbnailURL(remoteURL) {
            if bookmark.thumbnailRemoteURLString != remoteURL.absoluteString {
                bookmark.thumbnailRemoteURLString = remoteURL.absoluteString
                changed = true
            }

            if !localThumbnailExists(relativePath: bookmark.thumbnailRelativePath) {
                if let path = bookmark.thumbnailRelativePath, !path.isEmpty {
                    removeImageIfPresent(relativePath: path)
                    bookmark.thumbnailRelativePath = nil
                    changed = true
                }
                if let path = bookmark.originalImageRelativePath, !path.isEmpty {
                    removeImageIfPresent(relativePath: path)
                    bookmark.originalImageRelativePath = nil
                    changed = true
                }
            }
        } else {
            // Failed/noisy refetches should not erase an existing good thumbnail.
            if let remoteURLString = bookmark.thumbnailRemoteURLString,
               let remoteURL = URL(string: remoteURLString),
               Self.isLowConfidenceThumbnailURL(remoteURL) {
                if let path = bookmark.thumbnailRelativePath, !path.isEmpty {
                    removeImageIfPresent(relativePath: path)
                    bookmark.thumbnailRelativePath = nil
                    changed = true
                }
                if let path = bookmark.originalImageRelativePath, !path.isEmpty {
                    removeImageIfPresent(relativePath: path)
                    bookmark.originalImageRelativePath = nil
                    changed = true
                }
                bookmark.thumbnailRemoteURLString = nil
                changed = true
            }
        }

        bookmark.isEnriching = false
        bookmark.metadataUpdatedAt = Date()
        changed = markEnrichmentComplete(&bookmark) || changed
        if changed { bookmark.updatedAt = Date() }

        bookmark = renameBookmarkArtifactAfterTitleUpgrade(previous: previous, updated: bookmark)
        bookmarks[index] = bookmark

        if changed {
            persist()
            SecondBrainItemMutationIndexer.rebuildAfterMutation(
                database: resolvedDatabase,
                ownerType: "bookmark",
                ownerID: bookmarkID
            )
        } else {
            objectWillChange.send()
        }

        // Download additional carousel images (e.g. Reddit gallery)
        if let carouselURLs = payload?.carouselImageURLs, !carouselURLs.isEmpty {
            var seenCarouselURLs = Set<String>()
            var downloadedCarouselImageData: [Data] = []
            for carouselURL in carouselURLs {
                guard !Task.isCancelled else { break }
                guard seenCarouselURLs.insert(carouselURL.absoluteString).inserted else { continue }
                // Only fetch HTTPS URLs from known Reddit CDN hosts (SSRF prevention)
                guard let scheme = carouselURL.scheme?.lowercased(), scheme == "https",
                      let host = carouselURL.host?.lowercased(),
                      host.hasSuffix("redd.it") || host.hasSuffix("reddit.com") || host.hasSuffix("redditmedia.com") else { continue }
                do {
                    var request = URLRequest(url: carouselURL)
                    request.timeoutInterval = 8
                    let (imageData, _) = try await URLSession.shared.data(for: request)
                    guard imageData.count <= 12_000_000 else { continue } // Align with addCarouselImage's internal limit
                    downloadedCarouselImageData.append(imageData)
                } catch {
                    // Skip failed downloads silently
                }
            }
            if !downloadedCarouselImageData.isEmpty {
                _ = replaceCarouselImagesForEnrichment(
                    for: bookmarkID,
                    imageDataList: downloadedCarouselImageData
                )
            }
        }

        // Re-fetch bookmark safely — index may have shifted during carousel await loop
        if let current = bookmarks.first(where: { $0.id == bookmarkID }) {
            BookmarkAIEnrichment.shared.schedule(for: current)
        }
    }

    private static let recipeExtractionMarker = "Cider native recipe extraction source:"

    @discardableResult
    private func markEnrichmentComplete(_ bookmark: inout Bookmark, now: Date = Date()) -> Bool {
        var changed = false
        if bookmark.enrichmentStatus != "complete" {
            bookmark.enrichmentStatus = "complete"
            changed = true
        }
        if bookmark.lastEnrichedAt == nil {
            bookmark.lastEnrichedAt = now
            changed = true
        }
        return changed
    }

    private func shouldApplyRecipeExtractionText(_ recipeExtractionText: String, to bookmark: Bookmark) -> Bool {
        let trimmed = recipeExtractionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let aiSummary = bookmark.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !aiSummary.isEmpty else {
            return true
        }
        return !aiSummary.contains(Self.recipeExtractionMarker)
    }

    private func mergedRecipeExtractionSummary(existing: String?, recipeExtractionText: String) -> String {
        let trimmedRecipeText = recipeExtractionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let existing = existing?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty else {
            return trimmedRecipeText
        }
        return """
        \(existing)

        \(trimmedRecipeText)
        """
    }

    private func shouldEnrich(_ bookmark: Bookmark, for url: URL) -> Bool {
        let needsTitle = isHostDerivedTitle(bookmark, sourceURL: url)
            || bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLocalThumbnail = localThumbnailExists(relativePath: bookmark.thumbnailRelativePath)
        let needsThumbnail = !hasLocalThumbnail
        guard needsTitle || needsThumbnail else { return false }

        guard let metadataUpdatedAt = bookmark.metadataUpdatedAt else { return true }
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

    // MARK: - Image Helpers

    private struct BookmarkImageAssets {
        let thumbnailRelativePath: String
        let originalImageRelativePath: String
    }

    private func localThumbnailExists(relativePath: String?) -> Bool {
        localImageExists(relativePath: relativePath)
    }

    private func localImageExists(relativePath: String?) -> Bool {
        guard let relativePath, !relativePath.isEmpty else { return false }
        let url = bookmarksMetaDir.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func removeImageIfPresent(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        let fileURL = bookmarksMetaDir.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func cacheImageAssets(from remoteURL: URL, for bookmarkID: UUID, pageURL: URL? = nil) async -> BookmarkImageAssets? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")

        // If .webp, try .gif variant first
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
        if let pageURL, let scheme = pageURL.scheme, let host = pageURL.host {
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
            enrichLog.info("Image download \(remoteURL.host ?? "?", privacy: .public): HTTP \(code), \(data.count) bytes")
            let fileExtension = inferredImageFileExtension(response: response, remoteURL: remoteURL)
            return cacheImageAssets(from: data, for: bookmarkID, preferredFileExtension: fileExtension)
        } catch {
            enrichLog.warning("Image download error \(remoteURL.host ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
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

    private func persistImageAssets(
        for bookmarkID: UUID,
        sourceData: Data,
        preferredFileExtension: String?
    ) -> BookmarkImageAssets? {
        guard let thumbnailData = Self.downsampledThumbnailData(
            from: sourceData,
            maxDimension: thumbnailMaxPixelDimension
        ) else { return nil }

        let originalFileExtension = normalizedImageFileExtension(preferredFileExtension)
        let originalFilename = "\(bookmarkID.uuidString).\(originalFileExtension)"
        let originalRelativePath = "\(originalImagesDirectoryName)/\(originalFilename)"
        let originalFileURL = bookmarksMetaDir.appendingPathComponent(originalRelativePath)

        let thumbnailRelativePath = "\(thumbnailsDirectoryName)/\(bookmarkID.uuidString).png"
        let thumbnailFileURL = bookmarksMetaDir.appendingPathComponent(thumbnailRelativePath)

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
        BookmarkAIEnrichment.shared.schedule(for: bookmarks[index])
        return true
    }

    private func regenerateThumbnail(for bookmarkID: UUID, fromOriginalRelativePath relativePath: String) {
        let fileURL = bookmarksMetaDir.appendingPathComponent(relativePath)
        guard let sourceData = try? Data(contentsOf: fileURL),
              let thumbnailData = Self.downsampledThumbnailData(from: sourceData, maxDimension: thumbnailMaxPixelDimension) else {
            return
        }

        let thumbnailRelativePath = "\(thumbnailsDirectoryName)/\(bookmarkID.uuidString).png"
        let thumbnailFileURL = bookmarksMetaDir.appendingPathComponent(thumbnailRelativePath)
        try? thumbnailData.write(to: thumbnailFileURL, options: .atomic)

        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        bookmarks[index].thumbnailRelativePath = thumbnailRelativePath
    }

    private func deleteExistingThumbnailFiles(for bookmarkID: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: thumbnailsDirectoryURL, includingPropertiesForKeys: nil) else { return }
        let prefix = bookmarkID.uuidString + "."
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? fm.removeItem(at: file)
        }
    }

    private func deleteExistingOriginalImageFiles(for bookmarkID: UUID) {
        let fm = FileManager.default
        let prefix = bookmarkID.uuidString + "."

        // Clean central meta dir (.cider/bookmarks/.originals/)
        if let files = try? fm.contentsOfDirectory(at: originalImagesDirectoryURL, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix(prefix) {
                try? fm.removeItem(at: file)
            }
        }

        // Also clean per-folder .originals/ dir if bookmark is filed in a vault folder
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }) {
            let (folderDir, _) = resolveBookmarkDirectory(bookmarks[idx].folderID)
            let folderOriginalsDir = folderDir.appendingPathComponent(originalImagesDirectoryName)
            if let folderFiles = try? fm.contentsOfDirectory(at: folderOriginalsDir, includingPropertiesForKeys: nil) {
                for file in folderFiles where file.lastPathComponent.hasPrefix(prefix) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - Static Enrichment Helpers

    private static func fetchEnrichmentPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")
        let host = pageURL.host?.lowercased() ?? ""

        // Reddit
        if host.contains("reddit.com") {
            if let redditResult = await fetchRedditJSONPayload(for: pageURL) {
                enrichLog.info("Reddit JSON enrichment succeeded for \(pageURL.host ?? "?", privacy: .public)")
                return redditResult
            }
        }

        // Amazon — extract ASIN and product title from URL (page scraping is blocked)
        if host.contains("amazon.com") || host.contains("amazon.co") {
            if let amazonResult = Self.extractAmazonPayload(from: pageURL) {
                enrichLog.info("Amazon URL extraction succeeded for \(pageURL.host ?? "?", privacy: .public)")
                return amazonResult
            }
        }

        // YouTube
        if host.contains("youtube.com") || host.contains("youtu.be") {
            if let videoID = extractYouTubeVideoID(from: pageURL) {
                let thumbURL = URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")
                let htmlResult = await fetchHTMLEnrichmentPayload(for: pageURL)
                return BookmarkEnrichmentPayload(
                    title: htmlResult?.title,
                    thumbnailURL: thumbURL ?? htmlResult?.thumbnailURL,
                    screenshotData: nil,
                    recipeExtractionText: htmlResult?.recipeExtractionText
                )
            }
        }

        let htmlResult = await fetchHTMLEnrichmentPayload(for: pageURL)
        let githubFallbackData = githubRepositoryFallbackCardData(for: pageURL, title: htmlResult?.title)

        let hasRealThumbnail = htmlResult?.thumbnailURL != nil
            && !isFaviconURL(htmlResult?.thumbnailURL)
        let needsWebView = shouldAttemptRenderedMetadataFallback(
            pageURL: pageURL,
            htmlTitle: htmlResult?.title,
            hasRealThumbnail: hasRealThumbnail
        )
        if let htmlResult, hasRealThumbnail {
            if !needsWebView {
                return BookmarkEnrichmentPayload(
                    title: htmlResult.title,
                    thumbnailURL: htmlResult.thumbnailURL,
                    screenshotData: htmlResult.screenshotData,
                    thumbnailFallbackData: githubFallbackData,
                    recipeExtractionText: htmlResult.recipeExtractionText,
                    carouselImageURLs: htmlResult.carouselImageURLs
                )
            }
        }

        // oEmbed fallback
        if let oembedResult = await BookmarkMetadataParser.fetchOEmbedPayload(for: pageURL) {
            return BookmarkEnrichmentPayload(
                title: htmlResult?.title ?? oembedResult.title,
                thumbnailURL: oembedResult.thumbnailURL,
                screenshotData: nil,
                recipeExtractionText: htmlResult?.recipeExtractionText
            )
        }

        // WebView fallback
        if needsWebView {
            enrichLog.info("Trying WebView fallback for \(pageURL.host ?? "?", privacy: .public)")
            let extracted = await WebViewMetadataExtractor.extract(from: pageURL)
            let hasResult = extracted.title != nil || extracted.imageURL != nil
            if hasResult || extracted.screenshotData != nil {
                return BookmarkEnrichmentPayload(
                    title: extracted.title ?? htmlResult?.title,
                    thumbnailURL: extracted.imageURL ?? htmlResult?.thumbnailURL,
                    screenshotData: extracted.screenshotData,
                    thumbnailFallbackData: githubFallbackData,
                    recipeExtractionText: htmlResult?.recipeExtractionText
                )
            }
        }

        if let htmlResult, githubFallbackData != nil {
            return BookmarkEnrichmentPayload(
                title: htmlResult.title,
                thumbnailURL: htmlResult.thumbnailURL,
                screenshotData: htmlResult.screenshotData,
                thumbnailFallbackData: githubFallbackData,
                recipeExtractionText: htmlResult.recipeExtractionText,
                carouselImageURLs: htmlResult.carouselImageURLs
            )
        }

        return htmlResult
    }

    static func shouldAttemptRenderedMetadataFallback(
        pageURL: URL,
        htmlTitle: String?,
        hasRealThumbnail: Bool
    ) -> Bool {
        if htmlTitle == nil || !hasRealThumbnail { return true }
        guard isRenderedMetadataPreferredHost(pageURL.host),
              let htmlTitle else { return false }
        return isProviderGenericRenderedTitle(htmlTitle, sourceURL: pageURL)
    }

    private static func isRenderedMetadataPreferredHost(_ host: String?) -> Bool {
        let normalized = host?.lowercased() ?? ""
        return normalized == "x.com"
            || normalized == "twitter.com"
            || normalized.hasSuffix(".x.com")
            || normalized.hasSuffix(".twitter.com")
    }

    private static func isProviderGenericRenderedTitle(_ title: String, sourceURL: URL) -> Bool {
        let normalized = duplicateSuffixStrippedStaticTitle(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        let host = sourceURL.host?.lowercased() ?? ""
        if host.contains("x.com") || host.contains("twitter.com") {
            return ["x", "x.com", "twitter", "twitter.com", "post / x"].contains(normalized)
        }
        return false
    }

    private static func duplicateSuffixStrippedStaticTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #" \(\d+\)$"#, options: .regularExpression) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func githubRepositoryFallbackCardData(for pageURL: URL, title: String?) -> Data? {
        guard let repo = githubRepositoryIdentity(for: pageURL) else { return nil }

        let width = 1200
        let height = 630
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let size = NSSize(width: width, height: height)

        let rect = NSRect(origin: .zero, size: size)
        NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
        rect.fill()

        NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.94, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size.width, height: 14).fill()

        let markRect = NSRect(x: 72, y: 430, width: 86, height: 86)
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        NSBezierPath(ovalIn: markRect).fill()
        ("GH" as NSString).draw(
            in: markRect.insetBy(dx: 11, dy: 25),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 25, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.84),
            ]
        )

        (repo.owner as NSString).draw(
            in: NSRect(x: 184, y: 474, width: 880, height: 40),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.62),
            ]
        )

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        (repo.name as NSString).draw(
            in: NSRect(x: 184, y: 372, width: 880, height: 98),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 74, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: titleParagraph,
            ]
        )

        if let description = githubRepositoryDescription(from: title, owner: repo.owner, repo: repo.name) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (description as NSString).draw(
                in: NSRect(x: 74, y: 222, width: 990, height: 86),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 30, weight: .regular),
                    .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.78),
                    .paragraphStyle: paragraph,
                ]
            )
        }

        ("github.com/\(repo.owner)/\(repo.name)" as NSString).draw(
            in: NSRect(x: 74, y: 82, width: 990, height: 36),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.58),
            ]
        )

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func githubRepositoryIdentity(for pageURL: URL) -> (owner: String, name: String)? {
        let host = pageURL.host?.lowercased() ?? ""
        guard host == "github.com" || host == "www.github.com" else { return nil }
        let components = pageURL.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }

        let owner = components[0]
        let name = components[1]
        let reservedOwners = [
            "about", "apps", "blog", "collections", "contact", "customer-stories",
            "enterprise", "events", "explore", "features", "marketplace", "new",
            "notifications", "organizations", "pricing", "search", "settings", "topics",
        ]
        guard !reservedOwners.contains(owner.lowercased()),
              !owner.isEmpty,
              !name.isEmpty,
              !name.hasPrefix(".") else {
            return nil
        }
        return (owner, name)
    }

    private static func githubRepositoryDescription(from title: String?, owner: String, repo: String) -> String? {
        guard let title else { return nil }
        let prefix = "GitHub - \(owner)/\(repo):"
        guard title.hasPrefix(prefix) else { return nil }
        let description = title.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    /// Extracts product info directly from an Amazon URL without scraping.
    /// Amazon URLs contain the ASIN and often the product title in the path slug.
    /// Product images are available at a predictable URL based on ASIN.
    private static func extractAmazonPayload(from pageURL: URL) -> BookmarkEnrichmentPayload? {
        let path = pageURL.path

        // Extract ASIN — 10-character alphanumeric code after /dp/ or /gp/product/
        let asinPattern = #"/(?:dp|gp/product)/([A-Za-z0-9]{10})"#
        guard let asinMatch = path.range(of: asinPattern, options: .regularExpression),
              let asinCapture = path[asinMatch].split(separator: "/").last else { return nil }
        let asin = String(asinCapture).uppercased()

        // Extract product title from URL slug (the human-readable part before /dp/)
        var title: String?
        if let dpRange = path.range(of: "/dp/") {
            let beforeDP = path[path.startIndex..<dpRange.lowerBound]
            let slug = beforeDP.split(separator: "/").last.map(String.init) ?? ""
            if !slug.isEmpty {
                // Convert URL slug to title: "Samsung-Galaxy-Buds-Pro" → "Samsung Galaxy Buds Pro"
                title = slug.replacingOccurrences(of: "-", with: " ")
            }
        }

        // Amazon product images are available via their CDN
        let thumbnailURL = URL(string: "https://images-na.ssl-images-amazon.com/images/P/\(asin).jpg")

        return BookmarkEnrichmentPayload(
            title: title,
            thumbnailURL: thumbnailURL,
            screenshotData: nil
        )
    }

    private static func fetchRedditJSONPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")

        guard pageURL.path.contains("/comments/") else { return nil }

        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        var cleanPath = components?.path ?? pageURL.path
        if cleanPath.hasSuffix("/") { cleanPath = String(cleanPath.dropLast()) }
        components?.path = cleanPath + ".json"
        components?.host = "old.reddit.com"
        guard let jsonURL = components?.url else { return nil }

        var request = URLRequest(url: jsonURL)
        request.timeoutInterval = 8
        request.setValue("Cider/1.0 (macOS bookmark manager)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            enrichLog.warning("Reddit JSON: network error: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let listing = json.first?["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]],
              let postData = children.first?["data"] as? [String: Any] else {
            return nil
        }

        let title = postData["title"] as? String

        var thumbnailURL: URL?
        if let preview = postData["preview"] as? [String: Any],
           let images = preview["images"] as? [[String: Any]],
           let source = images.first?["source"] as? [String: Any],
           let urlString = source["url"] as? String {
            thumbnailURL = URL(string: urlString.replacingOccurrences(of: "&amp;", with: "&"))
        }

        // Reddit gallery — extract ALL image URLs for carousel
        var carouselURLs: [URL] = []
        if postData["is_gallery"] as? Bool == true,
           let mediaMetadata = postData["media_metadata"] as? [String: [String: Any]] {
            // Use gallery_data items order if available (preserves author's ordering)
            var orderedMediaIDs: [String] = []
            if let galleryData = postData["gallery_data"] as? [String: Any],
               let items = galleryData["items"] as? [[String: Any]] {
                orderedMediaIDs = items.compactMap { $0["media_id"] as? String }
            }
            if orderedMediaIDs.isEmpty {
                orderedMediaIDs = Array(mediaMetadata.keys)
            }

            for mediaID in orderedMediaIDs {
                if let meta = mediaMetadata[mediaID],
                   let source = meta["s"] as? [String: Any],
                   let urlString = source["u"] as? String,
                   let url = URL(string: urlString.replacingOccurrences(of: "&amp;", with: "&")) {
                    carouselURLs.append(url)
                }
            }

            // First gallery image becomes the thumbnail
            if thumbnailURL == nil, let first = carouselURLs.first {
                thumbnailURL = first
            }
        }

        if thumbnailURL == nil {
            if let thumb = postData["thumbnail"] as? String, thumb.hasPrefix("http") {
                thumbnailURL = URL(string: thumb.replacingOccurrences(of: "&amp;", with: "&"))
            }
        }

        if thumbnailURL == nil {
            if let destURL = postData["url_overridden_by_dest"] as? String,
               let url = URL(string: destURL), isDirectImageURL(url) {
                thumbnailURL = url
            }
        }

        guard title != nil || thumbnailURL != nil else { return nil }
        // Include carousel URLs (skip the first since it's already the thumbnail)
        let extraCarouselURLs = carouselURLs.count > 1 ? Array(carouselURLs.dropFirst()) : nil
        return BookmarkEnrichmentPayload(
            title: title,
            thumbnailURL: thumbnailURL,
            screenshotData: nil,
            carouselImageURLs: extraCarouselURLs
        )
    }

    private static func extractYouTubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        if host.contains("youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !vParam.isEmpty {
                return vParam
            }
            let pathComponents = url.pathComponents
            if pathComponents.count >= 3,
               (pathComponents[1] == "embed" || pathComponents[1] == "shorts") {
                return pathComponents[2]
            }
        }
        return nil
    }

    private static func isFaviconURL(_ url: URL?) -> Bool {
        isLowConfidenceThumbnailURL(url)
    }

    private static func isLowConfidenceThumbnailURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let fingerprint = [
            url.host ?? "",
            url.path,
            url.query ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        return fingerprint.contains("favicon")
            || fingerprint.contains("apple-touch-icon")
            || fingerprint.contains("touch-icon")
            || fingerprint.contains("mask-icon")
            || fingerprint.contains("/site-icon")
            || fingerprint.contains("/app-icon")
            || fingerprint.contains("%22")
            || fingerprint.contains("\"")
            || fingerprint.contains("created_time")
    }

    private static func fetchHTMLEnrichmentPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        guard let scheme = pageURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 10
        applyBrowserHeaders(&request)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else { return nil }
            guard let html = decodeHTML(data: data) else { return nil }
            return BookmarkMetadataParser.parse(html: html, pageURL: pageURL)
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

    private static func applyBrowserHeaders(_ request: inout URLRequest) {
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
    }

    private static func isDirectImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["gif", "png", "jpg", "jpeg", "webp", "heic", "avif", "bmp", "tiff", "ico"].contains(ext)
    }

    private static func isGIFData(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let header = data.prefix(6)
        return header.elementsEqual([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
            || header.elementsEqual([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
    }

    private static func isAnimatedImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private static func downsampledThumbnailData(from sourceData: Data, maxDimension: CGFloat) -> Data? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, sourceOptions as CFDictionary) else { return nil }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else { return nil }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    // MARK: - URL Helpers

    private func bookmarkURLDedupKey(_ rawValue: String) -> String {
        if let canonical = VaultDuplicateAuditor.canonicalBookmarkURL(rawValue) {
            return canonical
        }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func mergeSyncedDuplicateBookmark(
        existing: Bookmark,
        incomingTitle: String,
        incomingURLString: String,
        incomingNotes: String,
        incomingTags: [String],
        incomingThumbnailRemoteURLString: String?,
        incomingAISummary: String?,
        incomingDominantColors: [String]?,
        incomingUpdatedAt: Date,
        incomingFolderID: UUID?
    ) -> Bookmark {
        var merged = existing
        if incomingUpdatedAt > merged.updatedAt {
            merged.updatedAt = incomingUpdatedAt
        }

        if !merged.titleManuallySet,
           let incomingURL = URL(string: incomingURLString),
           shouldApplyEnrichedTitle(incomingTitle, to: merged, sourceURL: incomingURL) {
            merged.title = incomingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if merged.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !incomingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !merged.notesManuallySet {
            merged.notes = incomingNotes
        }

        if merged.thumbnailRemoteURLString == nil {
            merged.thumbnailRemoteURLString = incomingThumbnailRemoteURLString
        }
        if merged.aiSummary == nil {
            merged.aiSummary = incomingAISummary
        }
        if merged.dominantColors == nil {
            merged.dominantColors = incomingDominantColors
        }
        if !incomingTags.isEmpty {
            merged.tags = deduplicatedTags(from: merged.tags + incomingTags)
        }
        if merged.folderID == nil {
            merged.folderID = incomingFolderID
        }
        return merged
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
              isLikelyWebHost(host) else { return nil }

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
        if host.hasPrefix("[") && host.contains(":") { return true }
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

    private func duplicateCaptureTitleToApply(_ title: String?, to bookmark: Bookmark, sourceURL: URL) -> String? {
        guard let title else { return nil }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if bookmark.title.caseInsensitiveCompare(normalized) == .orderedSame { return nil }

        let incomingBookmark = Bookmark(title: normalized, urlString: sourceURL.absoluteString)
        let incomingIsGeneric =
            isHostDerivedTitle(incomingBookmark, sourceURL: sourceURL)
            || isProviderGenericTitle(normalized, sourceURL: sourceURL)
        guard incomingIsGeneric else { return normalized }

        if isHostDerivedTitle(bookmark, sourceURL: sourceURL)
            || isProviderGenericTitle(bookmark.title, sourceURL: sourceURL) {
            return normalized
        }

        return nil
    }

    private func shouldApplyEnrichedTitle(_ title: String, to bookmark: Bookmark, sourceURL: URL) -> Bool {
        if bookmark.titleManuallySet,
           !isProviderGenericTitle(bookmark.title, sourceURL: sourceURL),
           !isHostDerivedTitle(bookmark, sourceURL: sourceURL) {
            return false
        }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if bookmark.title.caseInsensitiveCompare(normalized) == .orderedSame { return false }
        let currentTitle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentTitle.isEmpty { return true }
        if currentTitle.caseInsensitiveCompare(bookmark.urlString) == .orderedSame { return true }
        return isHostDerivedTitle(bookmark, sourceURL: sourceURL)
            || isProviderGenericTitle(bookmark.title, sourceURL: sourceURL)
    }

    private func isHostDerivedTitle(_ bookmark: Bookmark, sourceURL: URL) -> Bool {
        let current = duplicateSuffixStrippedTitle(bookmark.title)
        guard !current.isEmpty else { return true }
        let hostTitle = resolvedTitle(for: sourceURL, override: nil)
        return current.caseInsensitiveCompare(hostTitle) == .orderedSame
    }

    private func isProviderGenericTitle(_ title: String, sourceURL: URL) -> Bool {
        let normalized = duplicateSuffixStrippedTitle(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }

        let host = sourceURL.host?.lowercased() ?? ""
        let genericTitles: [String]
        if host.contains("tiktok.com") {
            genericTitles = ["tiktok - make your day"]
        } else if host.contains("instagram.com") {
            genericTitles = ["instagram"]
        } else if host.contains("reddit.com") {
            genericTitles = [
                "reddit - dive into anything",
                "reddit - the heart of the internet",
            ]
        } else if host.contains("x.com") || host.contains("twitter.com") {
            genericTitles = ["x", "x.com", "twitter", "twitter.com"]
        } else {
            genericTitles = []
        }

        return genericTitles.contains(normalized)
            || normalized == "just a moment..."
            || normalized == "attention required!"
    }

    private func duplicateSuffixStrippedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #" \(\d+\)$"#, options: .regularExpression) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedHost(from url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { return String(host.dropFirst(2)) }
        return host
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
        let normalized = rawExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "jpg", "jpeg": return "jpg"
        case "png", "webp", "gif", "heic", "avif", "bmp", "tif", "tiff", "ico":
            return normalized == "tif" ? "tiff" : normalized
        default: return "png"
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

    // MARK: - Setup

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: bookmarksMetaDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: originalImagesDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: inboxBookmarksDir, withIntermediateDirectories: true)
    }

    // MARK: - Database Persistence

    /// Resolve which database instance to use: explicit (testing) or shared (production).
    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    /// Returns the encoded folder_id TEXT if the folder exists in the target
    /// database, otherwise nil. Used to defuse FK violations during persists
    /// when the in-memory folder reference has drifted from SQLite state.
    private func resolveSafeFolderID(_ db: CiderDatabase, folderID: UUID?) throws -> String? {
        guard let id = folderID else { return nil }
        let encoded = DatabaseHelpers.encode(id)
        let stmt = try db.prepare("SELECT 1 FROM folders WHERE id = ? LIMIT 1;")
        stmt.bind(encoded, at: 1)
        let exists = try stmt.step()
        return exists ? encoded : nil
    }

    // Internal for testing
    /// SELECT all bookmarks from the database (items JOIN bookmarks), loading
    /// labels, dismissed labels, and tags from join tables.
    func loadBookmarksFromDatabase(_ db: CiderDatabase) {
        do {
            _ = repairAdoptionCreatedBookmarkDatesFromFilesystem(db)
            let stmt = try db.prepare("""
                SELECT i.id, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                       b.url, b.notes, b.notes_manually_set, b.title_manually_set,
                       b.ai_summary, b.ocr_text, b.dominant_colors, b.media_type,
                       b.thumbnail_relative_path, b.thumbnail_remote_url, b.original_image_path,
                       b.carousel_image_paths, b.reader_unavailable, b.preferred_hero_mode,
                       b.enrichment_status, b.last_enriched_at
                FROM items i
                JOIN bookmarks b ON b.item_id = i.id
                WHERE i.type = 'bookmark'
                ORDER BY i.created_at DESC;
                """)
            var loaded: [Bookmark] = []
            while try stmt.step() {
                guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let folderID = DatabaseHelpers.decodeUUID(stmt.optionalString(at: 4) ?? "")

                // Decode JSON-encoded array fields
                let dominantColors = DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 12))
                let carouselPaths = DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 17))
                let mediaTypeRaw = stmt.optionalString(at: 13)
                let mediaType = mediaTypeRaw.flatMap { BookmarkMediaType(rawValue: $0) }

                let readerUnavailable = stmt.optionalBool(at: 18)

                var bookmark = Bookmark(
                    id: id,
                    title: stmt.string(at: 1),
                    urlString: stmt.string(at: 6),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 2)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
                    notes: stmt.string(at: 7),
                    tags: [],
                    labelIDs: [],
                    dismissedLabelIDs: [],
                    folderID: folderID,
                    thumbnailRemoteURLString: stmt.optionalString(at: 15),
                    thumbnailRelativePath: stmt.optionalString(at: 14),
                    originalImageRelativePath: stmt.optionalString(at: 16),
                    aiSummary: stmt.optionalString(at: 10),
                    ocrText: stmt.optionalString(at: 11),
                    dominantColors: dominantColors.isEmpty ? nil : dominantColors,
                    mediaType: mediaType,
                    carouselImagePaths: carouselPaths.isEmpty ? nil : carouselPaths,
                    readerUnavailable: readerUnavailable,
                    preferredHeroMode: stmt.optionalString(at: 19),
                    relativePath: stmt.optionalString(at: 5),
                    titleManuallySet: stmt.bool(at: 9),
                    notesManuallySet: stmt.bool(at: 8),
                    enrichmentStatus: stmt.optionalString(at: 20),
                    lastEnrichedAt: stmt.optionalDouble(at: 21).map { DatabaseHelpers.decodeDate($0) }
                )

                // Load labels from join table
                bookmark.labelIDs = try loadLabelIDs(db, itemID: id)
                bookmark.dismissedLabelIDs = try loadDismissedLabelIDs(db, itemID: id)
                bookmark.tags = try loadTags(db, itemID: id)

                loaded.append(bookmark)
            }
            bookmarks = repairNumericSuffixBookmarkArtifacts(
                canonicalizedLoadedBookmarks(loaded, repairing: db),
                repairing: db
            )
        } catch {
            logger.error("Failed to load bookmarks from database: \(error.localizedDescription)")
            bookmarks = []
        }
    }

    @discardableResult
    func repairAdoptionCreatedBookmarkDatesFromFilesystem(_ db: CiderDatabase) -> Int {
        do {
            let candidates = try bookmarkCreationDateRepairCandidates(db)
            guard !candidates.isEmpty else { return 0 }

            var repairs: [(id: UUID, createdAt: Date)] = []
            for candidate in candidates {
                guard let relativePath = candidate.relativePath,
                      relativePath.lowercased().hasSuffix(".webloc") else { continue }

                let fileURL = vaultRoot.appendingPathComponent(relativePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                let filesystemDates = BookmarkFileService.filesystemDates(for: fileURL)
                guard let fileCreatedAt = filesystemDates.creationDate ?? filesystemDates.modificationDate,
                      fileCreatedAt < candidate.createdAt.addingTimeInterval(-1),
                      Self.looksLikeAdoptionCreatedBookmarkRow(candidate) else { continue }

                repairs.append((candidate.id, fileCreatedAt))
            }

            guard !repairs.isEmpty else { return 0 }
            try db.withTransaction {
                let stmt = try db.prepare("UPDATE items SET created_at = ? WHERE id = ? AND type = 'bookmark';")
                for repair in repairs {
                    stmt.reset()
                    stmt.bind(DatabaseHelpers.encode(repair.createdAt), at: 1)
                        .bind(DatabaseHelpers.encode(repair.id), at: 2)
                    try stmt.step()
                }
            }
            logger.info("Repaired \(repairs.count) adoption-created bookmark date(s) from .webloc filesystem metadata")
            return repairs.count
        } catch {
            logger.error("Failed to repair adoption-created bookmark dates: \(error.localizedDescription)")
            return 0
        }
    }

    private struct BookmarkCreationDateRepairCandidate {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let relativePath: String?
        let notes: String
        let notesManuallySet: Bool
    }

    private func bookmarkCreationDateRepairCandidates(_ db: CiderDatabase) throws -> [BookmarkCreationDateRepairCandidate] {
        let stmt = try db.prepare("""
            SELECT i.id, i.title, i.created_at, i.updated_at, i.relative_path,
                   b.notes, b.notes_manually_set
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.type = 'bookmark'
              AND i.relative_path IS NOT NULL;
            """)
        var candidates: [BookmarkCreationDateRepairCandidate] = []
        while try stmt.step() {
            guard let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
            candidates.append(
                BookmarkCreationDateRepairCandidate(
                    id: id,
                    title: stmt.string(at: 1),
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 2)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
                    relativePath: stmt.optionalString(at: 4),
                    notes: stmt.string(at: 5),
                    notesManuallySet: stmt.bool(at: 6)
                )
            )
        }
        return candidates
    }

    private static func looksLikeAdoptionCreatedBookmarkRow(_ candidate: BookmarkCreationDateRepairCandidate) -> Bool {
        let createdUpdatedClose = abs(candidate.updatedAt.timeIntervalSince(candidate.createdAt)) <= 10
        let notesEmpty = candidate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let filenameTitleMatches = candidate.relativePath.map { relativePath in
            let filenameTitle = ((relativePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return filenameTitle.caseInsensitiveCompare(
                candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
        } ?? false

        return createdUpdatedClose || (filenameTitleMatches && notesEmpty && !candidate.notesManuallySet)
    }

    private func canonicalizedLoadedBookmarks(_ loaded: [Bookmark], repairing db: CiderDatabase) -> [Bookmark] {
        var groups: [String: [Bookmark]] = [:]
        var orderedKeys: [String] = []
        for bookmark in loaded {
            let key = bookmarkURLDedupKey(bookmark.urlString)
            guard !key.isEmpty else {
                let uniqueKey = "id:\(bookmark.id.uuidString)"
                orderedKeys.append(uniqueKey)
                groups[uniqueKey] = [bookmark]
                continue
            }
            if groups[key] == nil {
                orderedKeys.append(key)
                groups[key] = []
            }
            groups[key]?.append(bookmark)
        }

        var repaired: [Bookmark] = []
        var mergedBookmarks: [Bookmark] = []
        var removedRowBookmarks: [Bookmark] = []
        var artifactDeletionCandidates: [Bookmark] = []

        for key in orderedKeys {
            guard let group = groups[key], !group.isEmpty else { continue }
            if group.count == 1 {
                repaired.append(group[0])
                continue
            }

            let winner = group.max { lhs, rhs in
                bookmarkCanonicalScore(lhs) < bookmarkCanonicalScore(rhs)
            } ?? group[0]
            var merged = winner
            for duplicate in group where duplicate.id != winner.id {
                merged = mergeLoadedDuplicateBookmark(existing: merged, duplicate: duplicate)
                removedRowBookmarks.append(duplicate)
            }
            if let preferredPath = preferredCanonicalBookmarkPath(in: group, currentPath: merged.relativePath) {
                merged.relativePath = preferredPath
            }
            for candidate in group where candidate.relativePath != merged.relativePath {
                artifactDeletionCandidates.append(candidate)
            }
            repaired.append(merged)
            mergedBookmarks.append(merged)
        }

        repairCanonicalDuplicateBookmarks(
            db,
            mergedBookmarks: mergedBookmarks,
            removedRowBookmarks: removedRowBookmarks,
            artifactDeletionCandidates: artifactDeletionCandidates
        )
        return repaired
    }

    private func repairCanonicalDuplicateBookmarks(
        _ db: CiderDatabase,
        mergedBookmarks: [Bookmark],
        removedRowBookmarks: [Bookmark],
        artifactDeletionCandidates: [Bookmark]
    ) {
        guard !removedRowBookmarks.isEmpty else { return }
        do {
            try db.withTransaction {
                let deleteStmt = try db.prepare("DELETE FROM items WHERE id = ?;")
                for bookmark in removedRowBookmarks {
                    deleteStmt.reset()
                    deleteStmt.bind(DatabaseHelpers.encode(bookmark.id), at: 1)
                    try deleteStmt.step()
                }

                for bookmark in mergedBookmarks {
                    try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
                }
            }
            for bookmark in artifactDeletionCandidates {
                deleteDuplicateBookmarkArtifact(bookmark)
            }
            logger.info("Repaired \(removedRowBookmarks.count) duplicate canonical bookmark row(s)")
        } catch {
            logger.error("Failed to repair duplicate canonical bookmark rows: \(error.localizedDescription)")
        }
    }

    private func repairNumericSuffixBookmarkArtifacts(
        _ loaded: [Bookmark],
        repairing db: CiderDatabase
    ) -> [Bookmark] {
        var repaired = loaded
        var occupiedPaths = Set(loaded.compactMap(\.relativePath))
        var repairedBookmarks: [Bookmark] = []
        let fm = FileManager.default

        for index in repaired.indices {
            guard let relativePath = repaired[index].relativePath,
                  relativePath.lowercased().hasSuffix(".webloc"),
                  let cleanRelativePath = Self.pathByRemovingNumericDuplicateSuffix(relativePath),
                  !occupiedPaths.contains(cleanRelativePath) else { continue }

            let sourceURL = vaultRoot.appendingPathComponent(relativePath)
            let destinationURL = vaultRoot.appendingPathComponent(cleanRelativePath)
            guard fm.fileExists(atPath: sourceURL.path),
                  !fm.fileExists(atPath: destinationURL.path) else { continue }

            do {
                try fm.moveItem(at: sourceURL, to: destinationURL)
                BookmarkFileService.shared.removeSidecarEntry(
                    at: sourceURL.deletingLastPathComponent(),
                    filename: sourceURL.lastPathComponent
                )
                BookmarkFileService.shared.removeSidecarEntry(
                    at: destinationURL.deletingLastPathComponent(),
                    filename: destinationURL.lastPathComponent
                )
                occupiedPaths.remove(relativePath)
                occupiedPaths.insert(cleanRelativePath)
                repaired[index].relativePath = cleanRelativePath
                repairedBookmarks.append(repaired[index])
            } catch {
                logger.error("Failed to repair numeric suffix bookmark artifact \(relativePath, privacy: .public): \(error.localizedDescription)")
            }
        }

        guard !repairedBookmarks.isEmpty else { return repaired }
        do {
            try db.withTransaction {
                for bookmark in repairedBookmarks {
                    try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
                }
            }
            logger.info("Renamed \(repairedBookmarks.count) numeric suffix bookmark artifact(s) back to canonical paths")
        } catch {
            logger.error("Failed to persist numeric suffix bookmark artifact repair: \(error.localizedDescription)")
        }
        return repaired
    }

    private func bookmarkCanonicalScore(_ bookmark: Bookmark) -> Int {
        var score = 0
        if bookmark.titleManuallySet { score += 1_000 }
        if let sourceURL = URL(string: bookmark.urlString), !isHostDerivedTitle(bookmark, sourceURL: sourceURL) {
            score += 200
        }
        if !bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 50
        }
        if bookmark.relativePath != nil { score += 30 }
        if bookmark.relativePath.map({ Self.pathHasNumericDuplicateSuffix($0) }) == true { score -= 10_000 }
        if bookmark.folderID != nil { score += 20 }
        if !bookmark.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 15 }
        if bookmark.aiSummary != nil { score += 10 }
        if bookmark.thumbnailRemoteURLString != nil || bookmark.thumbnailRelativePath != nil { score += 8 }
        if bookmark.lastEnrichedAt != nil { score += 5 }
        if bookmark.title.localizedCaseInsensitiveContains(" (2)") { score -= 25 }
        if bookmark.title.localizedCaseInsensitiveContains(" copy") { score -= 25 }
        return score
    }

    private func preferredCanonicalBookmarkPath(in group: [Bookmark], currentPath: String?) -> String? {
        if let currentPath,
           !Self.pathHasNumericDuplicateSuffix(currentPath) {
            return currentPath
        }

        return group
            .compactMap(\.relativePath)
            .filter { $0.lowercased().hasSuffix(".webloc") }
            .filter { !Self.pathHasNumericDuplicateSuffix($0) }
            .sorted { lhs, rhs in
                let lhsExists = FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(lhs).path)
                let rhsExists = FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(rhs).path)
                if lhsExists != rhsExists { return lhsExists }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .first
    }

    private func deleteDuplicateBookmarkArtifact(_ bookmark: Bookmark) {
        guard let relativePath = bookmark.relativePath,
              relativePath.lowercased().hasSuffix(".webloc") else { return }
        deleteWeblocFileOnly(for: bookmark)
    }

    private static func pathHasNumericDuplicateSuffix(_ relativePath: String) -> Bool {
        let filename = (relativePath as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        return stem.range(of: #" \([0-9]+\)$"#, options: .regularExpression) != nil
            || stem.range(of: #" [0-9]+$"#, options: .regularExpression) != nil
    }

    private static func pathByRemovingNumericDuplicateSuffix(_ relativePath: String) -> String? {
        let filename = (relativePath as NSString).lastPathComponent
        let directory = (relativePath as NSString).deletingLastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let cleanedStem = stem
            .replacingOccurrences(of: #" \([0-9]+\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" [0-9]+$"#, with: "", options: .regularExpression)
        guard cleanedStem != stem, !cleanedStem.isEmpty else { return nil }
        let cleanFilename = ext.isEmpty ? cleanedStem : "\(cleanedStem).\(ext)"
        return directory == "." || directory.isEmpty ? cleanFilename : "\(directory)/\(cleanFilename)"
    }

    private func mergeLoadedDuplicateBookmark(existing: Bookmark, duplicate: Bookmark) -> Bookmark {
        var merged = existing
        if duplicate.updatedAt > merged.updatedAt {
            merged.updatedAt = duplicate.updatedAt
        }

        if shouldApplyDuplicateBookmarkTitle(duplicate.title, from: duplicate, to: merged) {
            merged.title = duplicate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            merged.titleManuallySet = duplicate.titleManuallySet
        }

        if merged.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !duplicate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !merged.notesManuallySet {
            merged.notes = duplicate.notes
            merged.notesManuallySet = duplicate.notesManuallySet
        }

        merged.tags = deduplicatedTags(from: merged.tags + duplicate.tags)
        merged.labelIDs = deduplicatedUUIDs(from: merged.labelIDs + duplicate.labelIDs)
        merged.dismissedLabelIDs = deduplicatedUUIDs(from: merged.dismissedLabelIDs + duplicate.dismissedLabelIDs)

        if merged.folderID == nil { merged.folderID = duplicate.folderID }
        if merged.relativePath == nil { merged.relativePath = duplicate.relativePath }
        if merged.thumbnailRemoteURLString == nil { merged.thumbnailRemoteURLString = duplicate.thumbnailRemoteURLString }
        if merged.thumbnailRelativePath == nil { merged.thumbnailRelativePath = duplicate.thumbnailRelativePath }
        if merged.originalImageRelativePath == nil { merged.originalImageRelativePath = duplicate.originalImageRelativePath }
        if merged.metadataUpdatedAt == nil { merged.metadataUpdatedAt = duplicate.metadataUpdatedAt }
        if merged.aiSummary == nil { merged.aiSummary = duplicate.aiSummary }
        if merged.ocrText == nil { merged.ocrText = duplicate.ocrText }
        if merged.dominantColors == nil { merged.dominantColors = duplicate.dominantColors }
        if merged.mediaType == nil { merged.mediaType = duplicate.mediaType }
        if merged.carouselImagePaths == nil { merged.carouselImagePaths = duplicate.carouselImagePaths }
        if merged.readerUnavailable == nil { merged.readerUnavailable = duplicate.readerUnavailable }
        if merged.preferredHeroMode == nil { merged.preferredHeroMode = duplicate.preferredHeroMode }
        if merged.enrichmentStatus == nil { merged.enrichmentStatus = duplicate.enrichmentStatus }
        if merged.lastEnrichedAt == nil || (duplicate.lastEnrichedAt ?? .distantPast) > (merged.lastEnrichedAt ?? .distantPast) {
            merged.lastEnrichedAt = duplicate.lastEnrichedAt
        }
        return merged
    }

    private func renameBookmarkArtifactAfterTitleUpgrade(previous: Bookmark, updated: Bookmark) -> Bookmark {
        guard previous.title != updated.title,
              !previous.titleManuallySet,
              let relativePath = previous.relativePath,
              relativePath.hasSuffix(".webloc"),
              let sourceURL = URL(string: previous.urlString),
              !isHostDerivedTitle(Bookmark(title: updated.title, urlString: sourceURL.absoluteString), sourceURL: sourceURL),
              !isProviderGenericTitle(updated.title, sourceURL: sourceURL),
              shouldRenameArtifactForTitleUpgrade(relativePath: relativePath, oldTitle: previous.title, sourceURL: sourceURL)
        else { return updated }

        let sourceFileURL = vaultRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: sourceFileURL.path) else { return updated }

        let dirURL = sourceFileURL.deletingLastPathComponent()
        let filename = sourceFileURL.lastPathComponent
        let dirRelativePath = (relativePath as NSString).deletingLastPathComponent
        let normalizedDirRelativePath = dirRelativePath == "." ? "" : dirRelativePath

        do {
            var renamed = updated
            let newRelativePath = try BookmarkFileService.shared.renameInPlace(
                bookmark: updated,
                filename: filename,
                in: dirURL,
                dirRelativePath: normalizedDirRelativePath
            )
            renamed.relativePath = newRelativePath
            return renamed
        } catch {
            logger.error("Failed to rename bookmark artifact after title upgrade: \(error.localizedDescription)")
            return updated
        }
    }

    private func shouldRenameArtifactForTitleUpgrade(relativePath: String, oldTitle: String, sourceURL: URL) -> Bool {
        let filename = (relativePath as NSString).lastPathComponent
        let fileTitle = ((filename as NSString).deletingPathExtension)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedFileTitle = duplicateSuffixStrippedTitle(fileTitle)
        let strippedOldTitle = duplicateSuffixStrippedTitle(oldTitle)
        guard !strippedFileTitle.isEmpty, !strippedOldTitle.isEmpty else { return false }

        if strippedFileTitle.caseInsensitiveCompare(strippedOldTitle) == .orderedSame {
            return isHostDerivedTitle(Bookmark(title: oldTitle, urlString: sourceURL.absoluteString), sourceURL: sourceURL)
                || isProviderGenericTitle(oldTitle, sourceURL: sourceURL)
        }

        let hostTitle = resolvedTitle(for: sourceURL, override: nil)
        return strippedFileTitle.caseInsensitiveCompare(hostTitle) == .orderedSame
            || isProviderGenericTitle(strippedFileTitle, sourceURL: sourceURL)
    }

    private func shouldApplyDuplicateBookmarkTitle(
        _ title: String,
        from duplicate: Bookmark,
        to bookmark: Bookmark
    ) -> Bool {
        if bookmark.titleManuallySet { return false }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if bookmark.title.caseInsensitiveCompare(normalized) == .orderedSame { return false }
        guard let duplicateURL = URL(string: duplicate.urlString) else { return false }
        if isHostDerivedTitle(duplicate, sourceURL: duplicateURL) { return false }

        if shouldApplyEnrichedTitle(normalized, to: bookmark, sourceURL: duplicateURL) {
            return true
        }
        if duplicate.titleManuallySet {
            return true
        }
        if isProviderGenericTitle(bookmark.title, sourceURL: duplicateURL) {
            return true
        }

        let duplicateHasRicherContext =
            !duplicate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || duplicate.thumbnailRemoteURLString != nil
            || duplicate.thumbnailRelativePath != nil
            || duplicate.aiSummary != nil
        return duplicateHasRicherContext
            && bookmarkCanonicalScore(duplicate) > bookmarkCanonicalScore(bookmark)
    }

    private func deduplicatedUUIDs(from rawIDs: [UUID]) -> [UUID] {
        var result: [UUID] = []
        result.reserveCapacity(rawIDs.count)
        var seen = Set<UUID>()
        for id in rawIDs where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
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

    /// Load dismissed label IDs from the dismissed_labels join table for a given item.
    private func loadDismissedLabelIDs(_ db: CiderDatabase, itemID: UUID) throws -> [UUID] {
        let stmt = try db.prepare("SELECT label_id FROM dismissed_labels WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
        var ids: [UUID] = []
        while try stmt.step() {
            if let id = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Load tag names from item_tags JOIN tags for a given item.
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
    /// Persist a single bookmark to the database (items + bookmarks + join tables) in a transaction.
    func persistBookmarkToDatabase(_ bookmark: Bookmark) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite persist for bookmark \(bookmark.id)")
            return
        }
        persistBookmarkToDatabase(db, bookmark: bookmark)
    }

    // Internal for testing
    /// Persist a single bookmark to the given database inside its own transaction.
    func persistBookmarkToDatabase(_ db: CiderDatabase, bookmark: Bookmark) {
        do {
            try db.withTransaction {
                try persistBookmarkToDatabaseInner(db, bookmark: bookmark)
            }
        } catch {
            logger.error("Failed to persist bookmark \(bookmark.id) to database: \(error.localizedDescription)")
        }
    }

    /// Core persist logic for a single bookmark — must be called inside a transaction.
    private func persistBookmarkToDatabaseInner(_ db: CiderDatabase, bookmark: Bookmark) throws {
        // 1. UPSERT into items (ON CONFLICT avoids DELETE+INSERT that triggers CASCADE)
        //
        // Scrub folder_id against the target database: if the referenced
        // folder doesn't exist in SQLite (first-run migration, mid-session
        // drift, etc.), fall back to NULL so the FK doesn't abort the whole
        // transaction. The webloc file on disk is the source of truth for
        // the folder, so downstream reassignment will put it back in place.
        let folderIDText = try resolveSafeFolderID(db, folderID: bookmark.folderID)
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                updated_at = excluded.updated_at,
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path;
            """)
        let itemID = DatabaseHelpers.encode(bookmark.id)
        itemStmt.bind(itemID, at: 1)
            .bind(bookmark.title, at: 2)
            .bind(DatabaseHelpers.encode(bookmark.createdAt), at: 3)
            .bind(DatabaseHelpers.encode(bookmark.updatedAt), at: 4)
            .bind(folderIDText, at: 5)
            .bind(bookmark.relativePath, at: 6)
        try itemStmt.step()

        // 2. UPSERT into bookmarks (item_id is PK; safe since bookmarks has no CASCADE children,
        //    but consistent with the items pattern above)
        let bkStmt = try db.prepare("""
            INSERT INTO bookmarks (
                item_id, url, notes, notes_manually_set, title_manually_set,
                ai_summary, ocr_text, dominant_colors, media_type,
                thumbnail_relative_path, thumbnail_remote_url, original_image_path,
                carousel_image_paths, reader_unavailable, preferred_hero_mode,
                enrichment_status, last_enriched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id) DO UPDATE SET
                url = excluded.url,
                notes = excluded.notes,
                notes_manually_set = excluded.notes_manually_set,
                title_manually_set = excluded.title_manually_set,
                ai_summary = excluded.ai_summary,
                ocr_text = excluded.ocr_text,
                dominant_colors = excluded.dominant_colors,
                media_type = excluded.media_type,
                thumbnail_relative_path = excluded.thumbnail_relative_path,
                thumbnail_remote_url = excluded.thumbnail_remote_url,
                original_image_path = excluded.original_image_path,
                carousel_image_paths = excluded.carousel_image_paths,
                reader_unavailable = excluded.reader_unavailable,
                preferred_hero_mode = excluded.preferred_hero_mode,
                enrichment_status = excluded.enrichment_status,
                last_enriched_at = excluded.last_enriched_at;
            """)
        let dominantColorsJSON: String? = bookmark.dominantColors.map { DatabaseHelpers.encode($0) }
        let carouselJSON: String? = bookmark.carouselImagePaths.map { DatabaseHelpers.encode($0) }
        let readerUnavailableInt: Int64? = bookmark.readerUnavailable.map { $0 ? 1 : 0 }

        bkStmt.bind(itemID, at: 1)
            .bind(bookmark.urlString, at: 2)
            .bind(bookmark.notes, at: 3)
            .bind(bookmark.notesManuallySet ? Int64(1) : Int64(0), at: 4)
            .bind(bookmark.titleManuallySet ? Int64(1) : Int64(0), at: 5)
            .bind(bookmark.aiSummary, at: 6)
            .bind(bookmark.ocrText, at: 7)
            .bind(dominantColorsJSON, at: 8)
            .bind(bookmark.mediaType?.rawValue, at: 9)
            .bind(bookmark.thumbnailRelativePath, at: 10)
            .bind(bookmark.thumbnailRemoteURLString, at: 11)
            .bind(bookmark.originalImageRelativePath, at: 12)
            .bind(carouselJSON, at: 13)
            .bind(readerUnavailableInt, at: 14)
            .bind(bookmark.preferredHeroMode, at: 15)
            .bind(bookmark.enrichmentStatus, at: 16)
            .bind(bookmark.lastEnrichedAt.map { DatabaseHelpers.encode($0) }, at: 17)
        try bkStmt.step()

        // 3. Sync item_labels: delete all, re-insert current.
        //    Use an EXISTS subquery so a dangling label_id (label not yet in
        //    SQLite, mid-migration race, partial backup recovery) is silently
        //    dropped instead of rolling back the whole bookmark transaction.
        //    SQLite's OR IGNORE does NOT swallow FK violations — they still
        //    throw — so we have to pre-check via a subquery.
        let delLabels = try db.prepare("DELETE FROM item_labels WHERE item_id = ?;")
        delLabels.bind(itemID, at: 1)
        try delLabels.step()

        if !bookmark.labelIDs.isEmpty {
            let insLabel = try db.prepare("""
                INSERT INTO item_labels (item_id, label_id)
                SELECT ?, ? WHERE EXISTS (SELECT 1 FROM labels WHERE id = ?);
                """)
            for labelID in bookmark.labelIDs {
                insLabel.reset()
                let labelText = DatabaseHelpers.encode(labelID)
                insLabel.bind(itemID, at: 1)
                    .bind(labelText, at: 2)
                    .bind(labelText, at: 3)
                try insLabel.step()
            }
        }

        // 4. Sync dismissed_labels: same EXISTS guard
        let delDismissed = try db.prepare("DELETE FROM dismissed_labels WHERE item_id = ?;")
        delDismissed.bind(itemID, at: 1)
        try delDismissed.step()

        if !bookmark.dismissedLabelIDs.isEmpty {
            let insDismissed = try db.prepare("""
                INSERT INTO dismissed_labels (item_id, label_id)
                SELECT ?, ? WHERE EXISTS (SELECT 1 FROM labels WHERE id = ?);
                """)
            for labelID in bookmark.dismissedLabelIDs {
                insDismissed.reset()
                let labelText = DatabaseHelpers.encode(labelID)
                insDismissed.bind(itemID, at: 1)
                    .bind(labelText, at: 2)
                    .bind(labelText, at: 3)
                try insDismissed.step()
            }
        }

        // 5. Sync item_tags: find-or-create tags, delete all item_tags, re-insert
        let delTags = try db.prepare("DELETE FROM item_tags WHERE item_id = ?;")
        delTags.bind(itemID, at: 1)
        try delTags.step()

        if !bookmark.tags.isEmpty {
            let findTag = try db.prepare("SELECT id FROM tags WHERE name = ?;")
            let createTag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
            let insItemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")

            for tagName in bookmark.tags {
                // Find or create tag
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

                // Insert item_tag
                insItemTag.reset()
                insItemTag.bind(itemID, at: 1).bind(tagID, at: 2)
                try insItemTag.step()
            }
        }
    }

    /// Delete a bookmark from the database by ID. CASCADE handles detail + join tables.
    func deleteBookmarkFromDatabase(_ bookmarkID: UUID) {
        guard let db = resolvedDatabase else {
            logger.warning("No database available, skipping SQLite delete for bookmark \(bookmarkID)")
            return
        }
        deleteBookmarkFromDatabase(db, bookmarkID: bookmarkID)
    }

    // Internal for testing
    /// DELETE a bookmark from the given database by ID.
    func deleteBookmarkFromDatabase(_ db: CiderDatabase, bookmarkID: UUID) {
        do {
            try SecondBrainStore(database: db).deleteOwnerFootprint(
                for: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmarkID.uuidString)
            )
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(bookmarkID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete bookmark \(bookmarkID) from database: \(error.localizedDescription)")
        }
    }

}
