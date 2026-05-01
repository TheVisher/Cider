import SwiftUI

enum CiderReanchorSurfaceResolver {
    static func canOpenInMainWindow(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo, .aiAssistant:
            true
        case .clipboard, .dropZone:
            false
        }
    }
}

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

    func requestFloat(_ surface: CiderFloatableSurface) {
        NotificationCenter.default.post(
            name: .floatCiderSurface,
            object: surface,
            userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
        )
    }

    func floatBookmarkDetails() {
        guard let bookmark = selectedDetailsBookmark else { return }
        saveBookmarkDetails()
        requestFloat(.bookmarkMetadata(bookmark.id))
    }

    func floatDateCardDetail() {
        guard let dateCard = selectedDateCard else { return }
        requestFloat(.dateCard(dateCard.id))
    }

    func floatContactDetail() {
        guard let contact = selectedContact else { return }
        requestFloat(.contact(contact.id))
    }

    func floatTodoDetail() {
        guard let todoCard = selectedTodoCard else { return }
        requestFloat(.todo(todoCard.id))
    }

    func floatNoteDetail() {
        guard let note = notesViewModel.selectedNote ?? selectedNote else { return }
        notesViewModel.flushSave()
        requestFloat(.note(note.id))
    }

    func floatCurrentDetailForPageMode() {
        if isDetailPageMode {
            floatBookmarkDetails()
        } else if selectedDateCard != nil {
            floatDateCardDetail()
        } else if selectedContact != nil {
            floatContactDetail()
        } else if selectedTodoCard != nil {
            floatTodoDetail()
        } else if isNoteDetailPageMode {
            floatNoteDetail()
        }
    }

    func openSurfaceInMainWindow(_ surface: CiderFloatableSurface) {
        guard CiderReanchorSurfaceResolver.canOpenInMainWindow(surface) else { return }
        closeAllDetails()

        switch surface {
        case .note(let id):
            if let note = notesViewModel.notes.first(where: { $0.id == id }) {
                openNoteDetail(note)
            }
        case .bookmark(let id), .bookmarkMetadata(let id):
            if let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == id }) {
                openBookmarkDetails(bookmark)
            }
        case .contact(let id):
            if let contact = ContactStorage.shared.contacts.first(where: { $0.id == id }) {
                openContactDetail(contact)
            }
        case .dateCard(let id):
            if let dateCard = DateCardStorage.shared.dateCards.first(where: { $0.id == id }) {
                openDateCardDetail(dateCard)
            }
        case .todo(let id):
            if let todoCard = TodoCardStorage.shared.todoCards.first(where: { $0.id == id }) {
                openTodoDetail(todoCard)
            }
        case .aiAssistant:
            openOrSelectAIAssistantTab()
        case .clipboard, .dropZone:
            break
        }
    }

    func openLinkedRef(_ ref: LibraryEntityRef) {
        switch ref.type {
        case .bookmark:
            if let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == ref.entityID }) {
                openBookmarkDetails(bookmark)
            }
        case .note:
            if let note = notesViewModel.notes.first(where: { $0.id == ref.entityID }) {
                openNoteDetail(note)
            }
        case .dateCard:
            if let dateCard = DateCardStorage.shared.dateCard(for: ref.entityID) {
                openDateCardDetail(dateCard)
            }
        case .contact:
            if let contact = ContactStorage.shared.contact(for: ref.entityID) {
                openContactDetail(contact)
            }
        case .todo:
            if let todo = TodoCardStorage.shared.todoCard(for: ref.entityID) {
                openTodoDetail(todo)
            }
        case .vaultFile:
            if let file = VaultFileService.shared.file(for: ref.entityID) {
                openVaultFileDetail(file)
            }
        case .externalFile, .session:
            break
        }
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
        // Reset stale web state immediately (cheap — just nils properties).
        // Preload is deferred — DetailSlideOutView.onChange handles it after animation settles.
        detailWebViewStore.reset()
        if detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }

        // Update AI context
        AIAssistantViewModel.shared.updateContext(
            bookmark: (title: bookmark.title, url: bookmark.urlString, summary: bookmark.aiSummary)
        )
    }

    func closeBookmarkDetails() {
        guard isDetailOpen else { return }
        saveBookmarkDetails() // Flush any pending edits before closing
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
        AIAssistantViewModel.shared.clearContext()
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func openDateCardDetail(_ dateCard: DateCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        if isDetailOpen { saveBookmarkDetails() } // Flush pending bookmark edits
        let wasExpanded = isAnyDetailOpen
        // Clear all detail state silently (no restore notification — we're about to show a new detail)
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
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

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        AIAssistantViewModel.shared.updateContext(
            event: (title: dateCard.title, date: formatter.string(from: dateCard.startAt), location: dateCard.location)
        )
    }

    func openContactDetail(_ contact: ContactCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
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

        AIAssistantViewModel.shared.updateContext(
            contact: (name: contact.displayName, email: contact.email)
        )
    }

    func openTodoDetail(_ todoCard: TodoCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
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

        let status = todoCard.isCompleted ? "completed" : "incomplete"
        AIAssistantViewModel.shared.updateContext(
            todo: (title: todoCard.title, status: status)
        )
    }

    func openVaultFileDetail(_ file: VaultFile) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
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
        if isDetailOpen { saveBookmarkDetails() }
        if isNoteDetailOpen { notesViewModel.flushSave() }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil

        selectedNote = nil
        isEditingNoteTitle = false
        AIAssistantViewModel.shared.clearContext()
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
