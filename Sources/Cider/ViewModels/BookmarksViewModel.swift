import AppKit
import Combine
import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var displayMode: BookmarkDisplayMode
    @Published var cardSize: BookmarkCardSize
    @Published var cardSizeScale: Double
    @Published var isVisible = false
    @Published var isCollapsed = false

    /// Pre-computed folder lookup — rebuilt when folders change.
    private(set) var foldersByID: [UUID: Folder] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        let config = CiderConfig.load()
        self.displayMode = config.bookmarksDefaultViewMode
        self.cardSize = config.bookmarksCardSize
        self.cardSizeScale = config.bookmarksCardSizeScale ?? config.bookmarksCardSize.sliderValue

        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        VaultFolderService.shared.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let legacy = VaultFolderService.shared.legacyFolders
                self.foldersByID = Dictionary(uniqueKeysWithValues: legacy.map { ($0.id, $0) })
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Initialize foldersByID from current state
        let initialFolders = VaultFolderService.shared.legacyFolders
        foldersByID = Dictionary(uniqueKeysWithValues: initialFolders.map { ($0.id, $0) })

        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let config = CiderConfig.load()
                let newMode = config.bookmarksDefaultViewMode
                let newCardSize = config.bookmarksCardSize
                let newScale = config.bookmarksCardSizeScale ?? newCardSize.sliderValue
                if self.displayMode != newMode { self.displayMode = newMode }
                if self.cardSize != newCardSize { self.cardSize = newCardSize }
                if self.cardSizeScale != newScale { self.cardSizeScale = newScale }
            }
            .store(in: &cancellables)
    }

    var bookmarks: [Bookmark] {
        BookmarksStorage.shared.bookmarks
    }

    var folders: [Folder] {
        VaultFolderService.shared.legacyFolders
    }

    var filteredBookmarks: [Bookmark] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return bookmarks }

        return bookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(trimmed) ||
            bookmark.urlString.lowercased().contains(trimmed) ||
            bookmark.hostDisplay.lowercased().contains(trimmed)
        }
    }

    @discardableResult
    func addBookmark(urlString: String, title: String?) -> Bool {
        BookmarksStorage.shared.add(urlString: urlString, title: title) != nil
    }

    @discardableResult
    func addBookmarkFromPasteboard() -> Bool {
        BookmarksStorage.shared.addFromPasteboard() != nil
    }

    @discardableResult
    func captureBookmarkFromActiveBrowserOrClipboard() -> Bool {
        if let capture = ActiveBrowserCaptureService.captureFromFrontmostBrowser() {
            let saved = addBookmark(urlString: capture.urlString, title: capture.title)
            postCaptureToast(
                message: saved ? "Saved from active browser" : "Unable to save active browser tab",
                isSuccess: saved
            )
            return saved
        }

        let failureHint = ActiveBrowserCaptureService.consumeFailureHint()
        postCaptureToast(
            message: failureHint ?? "Could not capture active browser tab",
            isSuccess: false
        )
        return false
    }

    func delete(_ bookmark: Bookmark) {
        let trashItem = BookmarksStorage.shared.remove(bookmark)
        CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: trashItem))
    }

    @discardableResult
    func assign(_ bookmark: Bookmark, toFolder folderID: UUID?) -> Bool {
        let oldFolderID = bookmark.folderID
        let result = BookmarksStorage.shared.assignBookmark(bookmark.id, toFolder: folderID)
        if result {
            let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
            CiderUndoManager.shared.record(.movedToFolder(
                itemType: .bookmark,
                itemID: bookmark.id,
                title: bookmark.title,
                fromFolderID: oldFolderID,
                toFolderID: folderID,
                folderName: folderName
            ))
        }
        return result
    }

    @discardableResult
    func createFolder(name: String, parentID: UUID?) -> Folder? {
        guard let vaultFolder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) else {
            return nil
        }
        return VaultFolderService.shared.toLegacyFolder(vaultFolder)
    }

    @discardableResult
    func renameFolder(_ folderID: UUID, to name: String) -> Bool {
        VaultFolderService.shared.renameFolder(folderID, to: name)
    }

    @discardableResult
    func deleteFolder(_ folderID: UUID) -> Bool {
        // Collect all folder IDs being deleted (this folder + descendants)
        let deletedIDs: Set<UUID> = {
            var ids: Set<UUID> = [folderID]
            for folder in VaultFolderService.shared.folders {
                if let vf = VaultFolderService.shared.folder(for: folderID),
                   folder.relativePath.hasPrefix(vf.relativePath + "/") {
                    ids.insert(folder.id)
                }
            }
            return ids
        }()

        // Unassign items BEFORE deleting the folder — notes need to move
        // their files out of the folder directory before it gets trashed.
        for id in deletedIDs {
            for note in NotesStorage.shared.notes where note.folderID == id {
                NotesStorage.shared.assignNote(note.id, toFolder: nil)
            }
            for bookmark in bookmarks where bookmark.folderID == id {
                BookmarksStorage.shared.assignBookmark(bookmark.id, toFolder: nil)
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
        }

        guard let trashItem = VaultFolderService.shared.deleteFolder(folderID) else {
            return false
        }

        CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFolder, trashItem: trashItem))
        return true
    }

    @discardableResult
    func setFolderCover(_ folderID: UUID, imageData: Data) -> Bool {
        VaultFolderService.shared.setCoverImage(imageData, for: folderID)
    }

    func setFolderCoverOffset(_ folderID: UUID, offsetY: Double) {
        VaultFolderService.shared.setCoverImageOffsetY(offsetY, for: folderID)
    }

    func removeFolderCover(_ folderID: UUID) {
        VaultFolderService.shared.removeCoverImage(for: folderID)
    }

    func folderCoverURL(for folder: Folder) -> URL? {
        guard let vaultFolder = VaultFolderService.shared.folder(for: folder.id) else { return nil }
        return VaultFolderService.shared.coverImageURL(for: vaultFolder)
    }

    func folder(for bookmark: Bookmark) -> Folder? {
        guard let folderID = bookmark.folderID else { return nil }
        return folders.first(where: { $0.id == folderID })
    }

    func folderPath(to folderID: UUID?) -> [Folder] {
        guard let folderID else { return [] }
        return VaultFolderService.shared.path(to: folderID).map {
            VaultFolderService.shared.toLegacyFolder($0)
        }
    }

    func childFolders(of parentID: UUID?) -> [Folder] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    @discardableResult
    func updateDetails(for bookmark: Bookmark, title: String, notes: String, tags: [String], labelIDs: [UUID]? = nil, urlString: String? = nil) -> Bool {
        BookmarksStorage.shared.updateDetails(
            for: bookmark.id,
            title: title,
            notes: notes,
            tags: tags,
            labelIDs: labelIDs,
            urlString: urlString
        )
    }

    @discardableResult
    func assignThumbnail(for bookmark: Bookmark, droppedString: String) -> Bool {
        let trimmed = droppedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let bookmarkID = bookmark.id
        Task { @MainActor [weak self] in
            let saved = await BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromDroppedString: trimmed)
            self?.postCaptureToast(
                message: saved ? "Updated bookmark thumbnail" : "Could not use dropped thumbnail URL",
                isSuccess: saved
            )
        }
        return true
    }

    @discardableResult
    func assignThumbnail(for bookmark: Bookmark, fileURL: URL) -> Bool {
        let bookmarkID = bookmark.id
        Task { @MainActor [weak self] in
            let saved = BookmarksStorage.shared.assignThumbnail(for: bookmarkID, fromLocalFileURL: fileURL)
            self?.postCaptureToast(
                message: saved ? "Updated bookmark thumbnail" : "Could not use dropped image file",
                isSuccess: saved
            )
        }
        return true
    }

    @discardableResult
    func assignThumbnail(for bookmark: Bookmark, imageData: Data, preferredFileExtension: String?) -> Bool {
        guard !imageData.isEmpty else { return false }

        let bookmarkID = bookmark.id
        Task { @MainActor [weak self] in
            let saved = BookmarksStorage.shared.assignThumbnail(
                for: bookmarkID,
                imageData: imageData,
                preferredFileExtension: preferredFileExtension
            )
            self?.postCaptureToast(
                message: saved ? "Updated bookmark thumbnail" : "Dropped content is not a valid image",
                isSuccess: saved
            )
        }
        return true
    }

    func deleteBookmarks(_ bookmarks: [Bookmark]) {
        let trashItems = BookmarksStorage.shared.removeAll(bookmarks)
        if !trashItems.isEmpty {
            CiderUndoManager.shared.record(.bulkDeletedToTrash(trashItems))
        }
    }

    func open(_ bookmark: Bookmark) {
        guard let url = bookmark.url else { return }
        NSWorkspace.shared.open(url)
    }

    func setDisplayMode(_ mode: BookmarkDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode

        var config = CiderConfig.load()
        config.bookmarksDefaultViewMode = mode
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    func setCardSize(_ size: BookmarkCardSize) {
        guard cardSize != size else { return }
        cardSize = size
        cardSizeScale = size.sliderValue

        var config = CiderConfig.load()
        config.bookmarksCardSize = size
        config.bookmarksCardSizeScale = size.sliderValue
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    func setCardSizeScale(_ scale: Double) {
        let clamped = min(max(scale, 0), 3)
        cardSizeScale = clamped
        let nearest = BookmarkCardSize(sliderValue: clamped)
        if cardSize != nearest { cardSize = nearest }

        var config = CiderConfig.load()
        config.bookmarksCardSizeScale = clamped
        config.bookmarksCardSize = nearest
        config.save()
    }

    func show() {
        isVisible = true
        isCollapsed = false
        searchText = ""
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }

    private func postCaptureToast(message: String, isSuccess: Bool) {
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "message": message,
                "isSuccess": isSuccess,
            ]
        )
    }
}
