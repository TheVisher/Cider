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
    @Published var pendingDetailBookmarkID: UUID?

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

        BookmarksStorage.shared.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folders in
                self?.foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Initialize foldersByID from current state
        foldersByID = Dictionary(uniqueKeysWithValues: BookmarksStorage.shared.folders.map { ($0.id, $0) })

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
        BookmarksStorage.shared.folders
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
        BookmarksStorage.shared.createFolder(name: name, parentID: parentID)
    }

    @discardableResult
    func renameFolder(_ folderID: UUID, to name: String) -> Bool {
        BookmarksStorage.shared.renameFolder(folderID, to: name)
    }

    @discardableResult
    func deleteFolder(_ folderID: UUID) -> Bool {
        BookmarksStorage.shared.deleteFolder(folderID)
    }

    @discardableResult
    func setFolderCover(_ folderID: UUID, imageData: Data) -> Bool {
        BookmarksStorage.shared.setFolderCoverImage(folderID, imageData: imageData)
    }

    func setFolderCoverOffset(_ folderID: UUID, offsetY: Double) {
        BookmarksStorage.shared.setFolderCoverOffset(folderID, offsetY: offsetY)
    }

    func removeFolderCover(_ folderID: UUID) {
        BookmarksStorage.shared.removeFolderCoverImage(folderID)
    }

    func folderCoverURL(for folder: Folder) -> URL? {
        BookmarksStorage.shared.folderCoverImageURL(for: folder)
    }

    func folder(for bookmark: Bookmark) -> Folder? {
        guard let folderID = bookmark.folderID else { return nil }
        return folders.first(where: { $0.id == folderID })
    }

    func folderPath(to folderID: UUID?) -> [Folder] {
        guard let folderID else { return [] }
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var path: [Folder] = []
        var cursorID: UUID? = folderID
        var visited = Set<UUID>()

        while let currentID = cursorID,
              !visited.contains(currentID),
              let folder = folderByID[currentID] {
            visited.insert(currentID)
            path.append(folder)
            cursorID = folder.parentID
        }

        return path.reversed()
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
    func updateDetails(for bookmark: Bookmark, title: String, notes: String, tags: [String]) -> Bool {
        BookmarksStorage.shared.updateDetails(
            for: bookmark.id,
            title: title,
            notes: notes,
            tags: tags
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
