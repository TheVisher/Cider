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

    // MARK: - External Edit Watching

    /// Watches `.cider/bookmarks/` for external edits to the index file (e.g. from Claude via iMessage).
    private var indexWatcher: FSEventsWatcher?
    /// Monotonic generation counter — incremented on every write, used to suppress reload from own writes.
    private var writeGeneration: UInt64 = 0
    private var isWritingIndex = false
    /// Timestamp of last external index edit — adoption is suppressed for a few seconds after.
    private var lastExternalEditAt: Date = .distantPast
    private let externalEditCooldown: TimeInterval = 10

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

    // MARK: - Init

    private init() {
        ensureDirectories()
        loadBookmarks()
        startIndexWatcher()
    }

    /// Testing-only initializer with an explicit database.
    /// Does NOT call loadBookmarks() — tests call loadBookmarksFromDatabase() directly.
    init(database: CiderDatabase) {
        self.database = database
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
                if importedLegacySidecars {
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
        writeGeneration += 1
        let gen = writeGeneration
        isWritingIndex = true
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(bookmarks)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            logger.error("Failed to write index cache: \(error.localizedDescription)")
        }
        // Reset after delay — only if no newer write has occurred (generation check prevents race)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.writeGeneration == gen else { return }
            self.isWritingIndex = false
        }
    }

    // MARK: - Index File Watching

    /// Watches the bookmarks metadata directory for external edits to the index file.
    private func startIndexWatcher() {
        indexWatcher = FSEventsWatcher(path: bookmarksMetaDir.path, latency: 0.5) { [weak self] paths in
            MainActor.assumeIsolated {
                guard let self, !self.isWritingIndex else { return }
                let indexPath = self.indexFileURL.path
                guard paths.contains(where: { $0 == indexPath }) else { return }
                self.reloadFromExternalEdit()
            }
        }
        indexWatcher?.start()
    }

    /// Reloads the bookmarks array from the index file after an external edit.
    /// Detects title/notes changes and marks them as manually set so enrichment won't overwrite.
    private func reloadFromExternalEdit() {
        guard var updated = loadFromIndexCache() else { return }
        let oldCount = bookmarks.count

        // Build lookup of current bookmarks by ID
        let oldByID = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })

        // Detect externally changed titles/notes and mark as manually set.
        // Accept external edits as authoritative (CLI, iMessage bot, etc. write the index).
        for i in updated.indices {
            guard let old = oldByID[updated[i].id] else { continue }
            // Preserve in-memory manual flags — don't let external file clear them
            if old.titleManuallySet { updated[i].titleManuallySet = true }
            if old.notesManuallySet { updated[i].notesManuallySet = true }
            // Detect new external changes and mark as manually set
            if updated[i].title != old.title && !updated[i].titleManuallySet {
                updated[i].titleManuallySet = true
            }
            if updated[i].notes != old.notes && !updated[i].notesManuallySet {
                updated[i].notesManuallySet = true
            }
            // Note: we intentionally accept the on-disk title/notes as authoritative.
            // External processes (CLI, iMessage bot) write the index through proper code
            // paths that set titleManuallySet. Reverting to old in-memory values would
            // fight those edits.
        }

        bookmarks = updated
        // Suppress adoption for a few seconds — the external agent (Claude) moved files
        // and updated the index simultaneously. Adoption would fight with the new state.
        lastExternalEditAt = Date()
        // Persist the merged state so manual title/notes overrides survive cold restarts
        persist()
        // Schedule enrichment for any new bookmarks added by the external editor
        scheduleEnrichmentForIncompleteBookmarks()
        logger.info("Reloaded \(updated.count) bookmarks from external index edit (was \(oldCount))")
    }

    /// Full scan of all vault folders + Inbox/Bookmarks for .webloc files.
    private func scanAllVaultFolders() -> [Bookmark] {
        let fileService = BookmarkFileService.shared
        var result: [Bookmark] = []
        var seenURLs = Set<String>()

        // TODO: URL-based dedup can flip-flop when the same URL exists in different folders,
        // keeping whichever folder is scanned first. Known issue — matches BookmarksStorage behavior,
        // not a regression. Fix properly with UUID-based dedup in a future pass.

        // Helper to process a single directory
        func processDirectory(dirURL: URL, dirRelativePath: String, folderID: UUID?) {
            let found = fileService.readAll(
                from: dirURL,
                dirRelativePath: dirRelativePath,
                includeLegacySidecarMetadata: false
            )
            for var bookmark in found {
                let urlKey = bookmark.urlString.lowercased()
                // Skip duplicates by URL
                guard urlKey.isEmpty || seenURLs.insert(urlKey).inserted else { continue }
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
        let removedIDs: [UUID] = bookmarks.compactMap { bookmark in
            guard let relativePath = bookmark.relativePath else { return nil }
            let fileURL = vaultRoot.appendingPathComponent(relativePath)
            return FileManager.default.fileExists(atPath: fileURL.path) ? nil : bookmark.id
        }
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
        SyncService.shared.pushAfterLocalChange()
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
    func add(urlString: String, title: String?) -> Bookmark? {
        guard let normalizedURL = normalizedURL(from: urlString) else { return nil }
        let canonical = normalizedURL.absoluteString

        // Check for existing bookmark with same URL
        if let existingIndex = bookmarks.firstIndex(where: {
            $0.urlString.caseInsensitiveCompare(canonical) == .orderedSame
        }) {
            var existing = bookmarks.remove(at: existingIndex)
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // TODO: Cosmetic issue — the .webloc filename on disk still reflects the old title.
            // The SQLite-backed bookmark title is correct, so the UI still renders the curated title.
            existing.updatedAt = Date()
            existing.urlString = canonical
            existing.isEnriching = false
            bookmarks.insert(existing, at: 0)
            persist()
            startEnrichmentIfNeeded(for: existing.id)
            return existing
        }

        let resolvedTitle = resolvedTitle(for: normalizedURL, override: title)
        var bookmark = Bookmark(title: resolvedTitle, urlString: canonical)

        // Write .webloc file to Inbox/Bookmarks/
        let (dirURL, dirRelativePath) = resolveBookmarkDirectory(nil)
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
    }

    @discardableResult
    func remove(_ bookmark: Bookmark) -> TrashItem {
        let before = MutationAuditSnapshots.bookmark(bookmark)
        cancelEnrichment(for: bookmark.id)
        SyncService.shared.trackDeletion(of: bookmark.id)
        // Track deleted URL so adoption doesn't re-adopt duplicate files
        if !bookmark.urlString.isEmpty {
            recentlyDeletedURLs[bookmark.urlString.lowercased()] = Date()
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
                recentlyDeletedURLs[bookmark.urlString.lowercased()] = Date()
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
        enrichmentStatus: String? = nil
    ) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return false }

        var changed = false
        if let aiSummary, bookmarks[index].aiSummary != aiSummary {
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
        }
        return changed
    }

    func previewNormalizedURLString(from rawValue: String) -> String? {
        normalizedURL(from: rawValue)?.absoluteString
    }

    // MARK: - Folder Assignment

    @discardableResult
    func assignBookmark(_ bookmarkID: UUID, toFolder folderID: UUID?) -> Bool {
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
            after: MutationAuditSnapshots.bookmark(bookmarks[index])
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
        // Skip adoption if index was recently edited externally (e.g. Claude moved files + updated index).
        // The external edit is authoritative; adoption would fight it.
        guard Date().timeIntervalSince(lastExternalEditAt) >= externalEditCooldown else { return }
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
        var existingIDs = Set<UUID>()
        for bm in bookmarks {
            let url = bm.urlString.lowercased()
            if !url.isEmpty { existingIDByURL[url] = bm.id }
            existingIDs.insert(bm.id)
        }

        var adopted: [Bookmark] = []
        var reassigned = 0
        // URLs already claimed by a folder — first folder wins, later copies are kept as-is.
        // We intentionally do NOT delete duplicate .webloc files here: enrichment and file
        // moves can briefly leave two files with the same URL on disk, and a previous version
        // of this function hard-deleted the "loser" with no trash, causing silent data loss.
        var claimedURLs = Set<String>()

        func processDirectory(dirURL: URL, dirRelativePath: String, folderID: UUID?) {
            guard fm.fileExists(atPath: dirURL.path) else { return }
            let found = fileService.readAll(
                from: dirURL,
                dirRelativePath: dirRelativePath,
                includeLegacySidecarMetadata: false
            )
            for var bookmark in found {
                let url = bookmark.urlString.lowercased()

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

                // Duplicate URL detected: skip adopting this copy so it doesn't overwrite
                // the already-claimed bookmark's folder assignment, but leave the file on
                // disk. Hard-deleting duplicates here previously caused silent data loss.
                if claimedURLs.contains(url) {
                    logger.warning("Duplicate URL at \(bookmark.relativePath ?? "?"); leaving file in place")
                    continue
                }
                claimedURLs.insert(url)

                if let existingID = existingIDByURL[url] {
                    if let idx = bookmarks.firstIndex(where: { $0.id == existingID }),
                       bookmarks[idx].folderID != folderID {
                        bookmarks[idx].folderID = folderID
                        bookmarks[idx].relativePath = bookmark.relativePath
                        reassigned += 1
                    }
                } else {
                    bookmark.folderID = folderID
                    adopted.append(bookmark)
                    existingIDByURL[url] = bookmark.id
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

        if !adopted.isEmpty || reassigned > 0 {
            if !adopted.isEmpty {
                logger.info("Adopted \(adopted.count) orphaned .webloc files from vault folders")
                bookmarks.append(contentsOf: adopted)
            }
            if reassigned > 0 {
                logger.info("Reassigned \(reassigned) bookmarks to match filesystem folders")
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
        let scanned = scanAllVaultFolders()
        bookmarks = scanned
        writeIndexCache()
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
        var bookmark = bookmarks[index]
        var changed = false
        if bookmark.tags != tags { bookmark.tags = tags; changed = true }
        if bookmark.ocrText != ocrText { bookmark.ocrText = ocrText; changed = true }
        if bookmark.dominantColors != dominantColors { bookmark.dominantColors = dominantColors; changed = true }
        if let title, !title.isEmpty, bookmark.title != title, !bookmark.titleManuallySet { bookmark.title = title; changed = true }
        guard changed else { return }
        bookmarks[index] = bookmark
        persist()
    }

    func applyOEmbedResults(
        for bookmarkID: UUID,
        title: String?,
        notes: String?
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        var bookmark = bookmarks[index]
        var changed = false
        if let title, !title.isEmpty, bookmark.title != title, !bookmark.titleManuallySet {
            bookmark.title = title; changed = true
        }
        // Only set notes if the bookmark doesn't already have user-written notes
        if let notes, !notes.isEmpty, bookmark.notes.isEmpty, !bookmark.notesManuallySet {
            bookmark.notes = notes; changed = true
        }
        guard changed else { return }
        bookmarks[index] = bookmark
        persist()
    }

    func applyAISummary(_ summary: String, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        guard bookmarks[index].aiSummary != summary else { return }
        bookmarks[index].aiSummary = summary
        persist()
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
                  URL(string: remoteURLString) != nil else { return false }
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

            var imageAssets: BookmarkImageAssets?
            if let thumbnailURL = payload?.thumbnailURL {
                imageAssets = await self.cacheImageAssets(from: thumbnailURL, for: bookmarkID, pageURL: url)
            }

            // Screenshot fallback
            if imageAssets == nil, let screenshotData = payload?.screenshotData {
                imageAssets = self.cacheImageAssets(
                    from: screenshotData,
                    for: bookmarkID,
                    preferredFileExtension: "jpg"
                )
            }

            // WebView screenshot fallback
            if imageAssets == nil, payload?.thumbnailURL != nil {
                let enrichLog = Logger(subsystem: "com.cider.app", category: "Enrichment")
                enrichLog.info("Thumbnail download failed, trying WebView screenshot for \(url.host ?? "?", privacy: .public)")
                let extracted = await WebViewMetadataExtractor.extract(from: url)
                if let screenshotData = extracted.screenshotData {
                    imageAssets = self.cacheImageAssets(
                        from: screenshotData,
                        for: bookmarkID,
                        preferredFileExtension: "jpg"
                    )
                }
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
        } else {
            // New URL has no thumbnail — clear stale references and files
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
            if bookmark.thumbnailRemoteURLString != nil {
                bookmark.thumbnailRemoteURLString = nil
                changed = true
            }
        }

        bookmark.isEnriching = false
        bookmark.metadataUpdatedAt = Date()
        if changed { bookmark.updatedAt = Date() }

        bookmarks[index] = bookmark

        if changed {
            persist()
        } else {
            objectWillChange.send()
        }

        // Download additional carousel images (e.g. Reddit gallery)
        if let carouselURLs = payload?.carouselImageURLs, !carouselURLs.isEmpty {
            for carouselURL in carouselURLs {
                guard !Task.isCancelled else { break }
                // Only fetch HTTPS URLs from known Reddit CDN hosts (SSRF prevention)
                guard let scheme = carouselURL.scheme?.lowercased(), scheme == "https",
                      let host = carouselURL.host?.lowercased(),
                      host.hasSuffix("redd.it") || host.hasSuffix("reddit.com") || host.hasSuffix("redditmedia.com") else { continue }
                do {
                    var request = URLRequest(url: carouselURL)
                    request.timeoutInterval = 8
                    let (imageData, _) = try await URLSession.shared.data(for: request)
                    guard imageData.count <= 12_000_000 else { continue } // Align with addCarouselImage's internal limit
                    _ = addCarouselImage(for: bookmarkID, imageData: imageData)
                } catch {
                    // Skip failed downloads silently
                }
            }
        }

        // Re-fetch bookmark safely — index may have shifted during carousel await loop
        if let current = bookmarks.first(where: { $0.id == bookmarkID }) {
            BookmarkAIEnrichment.shared.schedule(for: current)
        }
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
                    screenshotData: nil
                )
            }
        }

        let htmlResult = await fetchHTMLEnrichmentPayload(for: pageURL)

        let hasRealThumbnail = htmlResult?.thumbnailURL != nil
            && !isFaviconURL(htmlResult?.thumbnailURL)
        if let htmlResult, hasRealThumbnail {
            return htmlResult
        }

        // oEmbed fallback
        if let oembedResult = await BookmarkMetadataParser.fetchOEmbedPayload(for: pageURL) {
            return BookmarkEnrichmentPayload(
                title: htmlResult?.title ?? oembedResult.title,
                thumbnailURL: oembedResult.thumbnailURL,
                screenshotData: nil
            )
        }

        // WebView fallback
        let needsWebView = htmlResult?.title == nil || !hasRealThumbnail
        if needsWebView {
            enrichLog.info("Trying WebView fallback for \(pageURL.host ?? "?", privacy: .public)")
            let extracted = await WebViewMetadataExtractor.extract(from: pageURL)
            let hasResult = extracted.title != nil || extracted.imageURL != nil
            if hasResult || extracted.screenshotData != nil {
                return BookmarkEnrichmentPayload(
                    title: extracted.title ?? htmlResult?.title,
                    thumbnailURL: extracted.imageURL ?? htmlResult?.thumbnailURL,
                    screenshotData: extracted.screenshotData
                )
            }
        }

        return htmlResult
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
        guard let path = url?.path.lowercased() else { return false }
        return path.contains("favicon") || path.contains("apple-touch-icon")
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

    private func shouldApplyEnrichedTitle(_ title: String, to bookmark: Bookmark, sourceURL: URL) -> Bool {
        if bookmark.titleManuallySet { return false }
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
            bookmarks = loaded
        } catch {
            logger.error("Failed to load bookmarks from database: \(error.localizedDescription)")
            bookmarks = []
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
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(bookmarkID), at: 1)
            try stmt.step()
        } catch {
            logger.error("Failed to delete bookmark \(bookmarkID) from database: \(error.localizedDescription)")
        }
    }

}
