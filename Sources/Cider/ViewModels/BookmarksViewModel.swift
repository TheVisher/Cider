import AppKit
import Combine
import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var displayMode: BookmarkDisplayMode
    @Published var isVisible = false
    @Published var isCollapsed = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.displayMode = CiderConfig.load().bookmarksDefaultViewMode

        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.displayMode = CiderConfig.load().bookmarksDefaultViewMode
            }
            .store(in: &cancellables)
    }

    var bookmarks: [Bookmark] {
        BookmarksStorage.shared.bookmarks
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
        BookmarksStorage.shared.remove(bookmark)
    }

    func deleteBookmarks(_ bookmarks: [Bookmark]) {
        BookmarksStorage.shared.removeAll(bookmarks)
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
