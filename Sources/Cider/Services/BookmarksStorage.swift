import AppKit
import Combine
import Foundation
import ImageIO
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
        let config = CiderConfig.load()
        let expanded = NSString(string: config.ciderDataDirectory).expandingTildeInPath
        directoryURL = URL(fileURLWithPath: expanded)
        ensureDirectory()
        load()
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

    @discardableResult
    func remove(_ bookmark: Bookmark) -> TrashItem {
        cancelEnrichment(for: bookmark.id)
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
        bookmarks.insert(restored, at: 0)
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
        tags: [String]
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
    func deleteFolder(_ folderID: UUID) -> Bool {
        guard folders.contains(where: { $0.id == folderID }) else { return false }

        let subtree = folderSubtreeIDs(rootID: folderID)
        guard !subtree.isEmpty else { return false }

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

        if let folderID, folders.first(where: { $0.id == folderID }) == nil {
            return false
        }

        if bookmarks[index].folderID == folderID {
            return true
        }

        bookmarks[index].folderID = folderID
        persist()
        return true
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
        let metadataByURL = Dictionary(uniqueKeysWithValues: metadataBookmarks.map { ($0.urlString.lowercased(), $0) })

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

        var loadedBookmarks: [Bookmark] = []
        loadedBookmarks.reserveCapacity(entries.count)

        for entry in entries {
            guard let normalized = normalizedURL(from: entry.urlString) else { continue }
            let canonical = normalized.absoluteString

            var bookmark = metadataByURL[canonical.lowercased()] ?? Bookmark(
                title: resolvedTitle(for: normalized, override: entry.title),
                urlString: canonical
            )
            bookmark.urlString = canonical

            if let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                bookmark.title = title
            } else if bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bookmark.title = resolvedTitle(for: normalized, override: nil)
            }

            if let addDate = entry.addDate {
                bookmark.createdAt = addDate
            }
            if let modifiedDate = entry.lastModified {
                bookmark.updatedAt = max(bookmark.updatedAt, modifiedDate)
            }

            loadedBookmarks.append(bookmark)
        }

        let sanitizedLoaded = sanitizedBookmarks(
            from: loadedBookmarks,
            validFolderIDs: Set(metadataFolders.map(\.id))
        )
        return BookmarksDiskSnapshot(
            bookmarks: sanitizedLoaded,
            folders: metadataFolders
        )
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
            let payload = await Self.fetchEnrichmentPayload(for: url)

            let imageAssets: BookmarkImageAssets?
            if let thumbnailURL = payload?.thumbnailURL {
                imageAssets = await self.cacheImageAssets(from: thumbnailURL, for: bookmarkID)
            } else {
                imageAssets = nil
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
    }

    private func cacheImageAssets(from remoteURL: URL, for bookmarkID: UUID) async -> BookmarkImageAssets? {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Cider/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            let fileExtension = inferredImageFileExtension(response: response, remoteURL: remoteURL)
            return cacheImageAssets(
                from: data,
                for: bookmarkID,
                preferredFileExtension: fileExtension
            )
        } catch {
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

        return persistImageAssets(
            for: bookmarkID,
            sourceData: data,
            preferredFileExtension: preferredFileExtension
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
    }

    private static func fetchEnrichmentPayload(for pageURL: URL) async -> BookmarkEnrichmentPayload? {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Cider/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                return nil
            }
            guard let html = decodeHTML(data: data) else { return nil }
            return BookmarkMetadataParser.parse(html: html, pageURL: pageURL)
        } catch {
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
}

private struct BookmarkEnrichmentPayload {
    let title: String?
    let thumbnailURL: URL?
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
        return BookmarkEnrichmentPayload(title: title, thumbnailURL: thumbnailURL)
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
            || host.contains("digg.com") {
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

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NetscapeBookmarksCodec {
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
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
