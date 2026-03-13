import SwiftUI

extension CiderPanelView {

    // MARK: - Bookmark Details (Centralized)

    var isDetailOpen: Bool {
        detailBookmarkID != nil && detailsDraft != nil
    }

    var isDetailSlideOut: Bool {
        isDetailOpen && detailViewMode == .slideOut
    }

    var maxSlideOutWidth: CGFloat {
        let inset = BookmarksDesign.detailsSlideOutFloatInset
        return max(
            BookmarksDesign.detailsSlideOutMinWidth,
            contentAreaWidth - inset * 2
        )
    }

    var isDetailFullPanel: Bool {
        isDetailOpen && detailViewMode == .fullPanel
    }

    var isDetailPageMode: Bool {
        isDetailOpen && detailViewMode == .page
    }

    var isTodoDetailOpen: Bool {
        selectedTodoCard != nil
    }

    var isGenericDetailOpen: Bool {
        selectedDateCard != nil || selectedContact != nil || isTodoDetailOpen || selectedVaultFile != nil
    }

    var isAnyDetailOpen: Bool {
        isDetailOpen || isGenericDetailOpen || isNoteDetailOpen
    }

    var isGenericDetailSlideOut: Bool {
        // Todos always use slide-out regardless of detailViewMode
        isTodoDetailOpen || ((selectedDateCard != nil || selectedContact != nil || selectedVaultFile != nil) && detailViewMode == .slideOut)
    }

    var isGenericDetailFullPanel: Bool {
        !isTodoDetailOpen && (selectedDateCard != nil || selectedContact != nil || selectedVaultFile != nil) && detailViewMode == .fullPanel
    }

    var isGenericDetailPageMode: Bool {
        !isTodoDetailOpen && (selectedDateCard != nil || selectedContact != nil || selectedVaultFile != nil) && detailViewMode == .page
    }

    var isAnyDetailPageMode: Bool {
        isDetailPageMode || isGenericDetailPageMode || isNoteDetailPageMode
    }

    var selectedDetailsBookmark: Bookmark? {
        guard let detailBookmarkID else { return nil }
        return bookmarksViewModel.bookmarks.first(where: { $0.id == detailBookmarkID })
    }

    func openBookmarkDetails(_ bookmark: Bookmark) {
        if isSearchPaletteVisible {
            isSearchPaletteVisible = false
        }
        if isNoteDetailOpen { closeNoteDetail() }
        detailBookmarkID = bookmark.id
        detailsDraft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsErrorMessage = nil
        // Restore per-bookmark hero mode, falling back to thumbnail
        let isReaderUnavailable = bookmark.readerUnavailable == true
        let restored = bookmark.preferredHeroMode.flatMap(BookmarkHeroMode.init(rawValue:)) ?? .thumbnail
        bookmarkHeroMode = (restored == .reader && isReaderUnavailable) ? .thumbnail : restored
        detailWebViewStore.reset()
        // Eagerly preload web + reader content
        if bookmark.hasURL, let url = bookmark.url {
            detailWebViewStore.preload(url: url, bookmarkID: bookmark.id)
        }
        if detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func closeBookmarkDetails() {
        guard isDetailOpen else { return }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func openDateCardDetail(_ dateCard: DateCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        // Clear all detail state silently (no restore notification — we're about to show a new detail)
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedContact = nil
        selectedVaultFile = nil
        selectedDateCard = dateCard
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func openContactDetail(_ contact: ContactCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedTodoCard = nil
        selectedVaultFile = nil
        selectedContact = contact
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func openTodoDetail(_ todoCard: TodoCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = nil
        selectedVaultFile = nil
        selectedTodoCard = todoCard
        if !wasExpanded {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func openVaultFileDetail(_ file: VaultFile) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = file
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func closeGenericDetail() {
        guard isGenericDetailOpen else { return }
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func closeAllDetails() {
        let anyOpen = isAnyDetailOpen
        if isNoteDetailOpen { notesViewModel.flushSave() }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil
        selectedNote = nil
        notesViewModel.activeExternalFile = nil
        isEditingNoteTitle = false
        if anyOpen {
            NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
        }
    }

    func saveBookmarkDetails() {
        guard let detailsDraft else { return }
        guard let selectedBookmark = selectedDetailsBookmark else {
            detailsErrorMessage = "This bookmark is no longer available."
            return
        }

        let parsedTags = detailsDraft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = detailsDraft.sourceURL != detailsDraft.originalURLString
            ? detailsDraft.sourceURL
            : nil

        let didSave = bookmarksViewModel.updateDetails(
            for: selectedBookmark,
            title: detailsDraft.title,
            notes: detailsDraft.notes,
            tags: parsedTags,
            labelIDs: detailsDraft.labelIDs,
            urlString: sourceURL
        )

        if !didSave {
            detailsErrorMessage = "Could not save bookmark details."
        }
    }

    func deleteDetailBookmark() {
        guard let bookmark = selectedDetailsBookmark else { return }
        closeBookmarkDetails()
        bookmarksViewModel.deleteBookmarks([bookmark])
    }

    func assignDetailBookmarkToFolder(_ folderID: UUID?) {
        guard let bookmark = selectedDetailsBookmark else { return }
        _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
    }

    func copyDetailURL() {
        guard let detailsDraft else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detailsDraft.sourceURL, forType: .string)
    }

    func openDetailURL() {
        guard let detailsDraft,
              let url = URL(string: detailsDraft.sourceURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func changeDetailViewMode(_ mode: DetailViewMode) {
        withAnimation(reduceMotion ? .none : .snappy) {
            if isNoteDetailOpen {
                noteDetailViewMode = mode
            } else {
                bookmarkDetailViewMode = mode
            }
        }
        var config = CiderConfig.load()
        if isNoteDetailOpen {
            config.noteDetailViewMode = mode
        } else {
            config.bookmarkDetailViewMode = mode
        }
        config.save()
    }
}
