import SwiftUI
import os

enum CiderDetailSurfaceKind: CaseIterable, Hashable {
    case bookmark
    case note
    case dateCard
    case contact
    case todo
    case vaultFile
    case kanban
}

enum CiderDetailNavigationPolicy {
    static func surfacesToClear(whenOpening target: CiderDetailSurfaceKind) -> Set<CiderDetailSurfaceKind> {
        Set(CiderDetailSurfaceKind.allCases.filter { $0 != target })
    }
}

enum CiderReanchorSurfaceResolver {
    static func canOpenInMainWindow(_ surface: CiderFloatableSurface) -> Bool {
        switch surface {
        case .note, .bookmark, .bookmarkMetadata, .contact, .dateCard, .todo, .vaultFile, .aiAssistant:
            true
        case .clipboard, .dropZone:
            false
        }
    }
}

extension CiderPanelView {
    private static let detailLogger = Logger(subsystem: "com.cider.app", category: "DetailManagement")


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
        isDetailOpen || isGenericDetailOpen || isNoteDetailOpen || isKanbanDetailOpen
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

    var selectedKanbanDetail: (board: KanbanBoard, column: KanbanColumn, card: KanbanCard)? {
        guard let selectedKanbanBoardID, let selectedKanbanCardID else { return nil }
        guard let found = KanbanStorage.shared.findCard(id: selectedKanbanCardID) else { return nil }
        guard found.board.id == selectedKanbanBoardID else { return nil }
        return found
    }

    var isKanbanDetailOpen: Bool {
        selectedKanbanDetail != nil
    }

    var isKanbanDetailSlideOut: Bool {
        isKanbanDetailOpen
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

    func floatVaultFileDetail() {
        guard let vaultFile = selectedVaultFile else { return }
        requestFloat(.vaultFile(vaultFile.id))
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
        } else if selectedVaultFile != nil {
            floatVaultFileDetail()
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
        case .vaultFile(let id):
            if let vaultFile = VaultFileService.shared.file(for: id) {
                openVaultFileDetail(vaultFile)
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
            guard let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == ref.entityID }) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openBookmarkDetails(bookmark)
        case .note:
            guard let note = notesViewModel.notes.first(where: { $0.id == ref.entityID }) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openNoteDetail(note)
        case .dateCard:
            guard let dateCard = DateCardStorage.shared.dateCard(for: ref.entityID) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openDateCardDetail(dateCard)
        case .contact:
            guard let contact = ContactStorage.shared.contact(for: ref.entityID) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openContactDetail(contact)
        case .todo:
            guard let todo = TodoCardStorage.shared.todoCard(for: ref.entityID) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openTodoDetail(todo)
        case .vaultFile:
            guard let file = VaultFileService.shared.file(for: ref.entityID) else { return }
            clearDetailStateBeforeOpeningLinkedRef()
            openVaultFileDetail(file)
        case .externalFile, .session:
            break
        }
    }

    private func clearDetailStateBeforeOpeningLinkedRef() {
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
        selectedKanbanBoardID = nil
        selectedKanbanCardID = nil
        selectedNote = nil
        isEditingNoteTitle = false
        AIAssistantViewModel.shared.clearContext()
    }

    func openBookmarkDetails(_ bookmark: Bookmark) {
        if isSearchPaletteVisible {
            isSearchPaletteVisible = false
        }
        if isDetailOpen { saveBookmarkDetails() }
        if isNoteDetailOpen { notesViewModel.flushSave() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .bookmark)
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
        if !wasExpanded, detailViewMode == .slideOut {
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
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .dateCard)
        genericMetadataVisible = true

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
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .contact)
        genericMetadataVisible = true

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
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .todo)
        genericMetadataVisible = true

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
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isDetailOpen { saveBookmarkDetails() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .vaultFile)
        genericMetadataVisible = true

        selectedVaultFile = file
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func openKanbanCardDetail(boardID: String, cardID: String) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isDetailOpen { saveBookmarkDetails() }

        guard let found = KanbanStorage.shared.findCard(id: cardID), found.board.id == boardID else { return }

        if isKanbanDetailOpen { saveKanbanCardDraft() }

        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .kanban)
        kanbanMetadataVisible = true
        kanbanSourceNotesVisible = false
        selectedKanbanBoardID = boardID
        selectedKanbanCardID = cardID
        kanbanCardDraft = KanbanCardDraft(card: found.card)

        if !wasExpanded {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }

        AIAssistantViewModel.shared.updateContext(
            todo: (title: found.card.title, status: found.column.name)
        )
    }

    func clearDetailSelectionState(except target: CiderDetailSurfaceKind) {
        let surfacesToClear = CiderDetailNavigationPolicy.surfacesToClear(whenOpening: target)

        if surfacesToClear.contains(.bookmark) {
            detailBookmarkID = nil
            detailsDraft = nil
            detailsErrorMessage = nil
            detailWebViewStore.reset()
        }

        if surfacesToClear.contains(.note) {
            selectedNote = nil
            isEditingNoteTitle = false
        }

        if surfacesToClear.contains(.dateCard) {
            selectedDateCard = nil
        }

        if surfacesToClear.contains(.contact) {
            selectedContact = nil
        }

        if surfacesToClear.contains(.todo) {
            selectedTodoCard = nil
        }

        if surfacesToClear.contains(.vaultFile) {
            selectedVaultFile = nil
        }

        if surfacesToClear.contains(.kanban) {
            saveKanbanCardDraft()
            selectedKanbanBoardID = nil
            selectedKanbanCardID = nil
            kanbanCardDraft = nil
        }
    }

    func closeGenericDetail() {
        guard isGenericDetailOpen else { return }
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil
        selectedKanbanBoardID = nil
        selectedKanbanCardID = nil
        kanbanCardDraft = nil

        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func closeKanbanDetail() {
        saveKanbanCardDraft()
        selectedKanbanBoardID = nil
        selectedKanbanCardID = nil
        kanbanCardDraft = nil
        AIAssistantViewModel.shared.clearContext()
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func closeAllDetails() {
        let anyOpen = isAnyDetailOpen
        if isDetailOpen { saveBookmarkDetails() }
        if isNoteDetailOpen { notesViewModel.flushSave() }
        if isKanbanDetailOpen { saveKanbanCardDraft() }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        detailWebViewStore.reset()
        selectedDateCard = nil
        selectedContact = nil
        selectedTodoCard = nil
        selectedVaultFile = nil
        selectedKanbanBoardID = nil
        selectedKanbanCardID = nil
        kanbanCardDraft = nil

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

    func deleteDetailVaultFile() {
        guard let file = selectedVaultFile else { return }
        closeGenericDetail()
        let trashItem = TrashStorage.shared.trashVaultFile(file)
        CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFile, trashItem: trashItem))
    }

    func deleteDetailDateCard() {
        guard let dateCard = selectedDateCard else { return }
        closeGenericDetail()
        if let trashItem = DateCardStorage.shared.deleteDateCard(dateCard.id) {
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
        }
    }

    func deleteDetailContact() {
        guard let contact = selectedContact else { return }
        closeGenericDetail()
        if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
        }
    }

    func deleteDetailTodo() {
        guard let todo = selectedTodoCard else { return }
        closeGenericDetail()
        if let trashItem = TodoCardStorage.shared.deleteTodoCard(todo.id) {
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
        }
    }

    func currentKanbanDraftCard(from detail: (board: KanbanBoard, column: KanbanColumn, card: KanbanCard)) -> KanbanCard {
        let draft = kanbanCardDraft ?? KanbanCardDraft(card: detail.card)
        return draft.updatedCard(from: detail.card)
    }

    func saveKanbanCardDraft() {
        guard let detail = selectedKanbanDetail else { return }
        let updated = currentKanbanDraftCard(from: detail)
        KanbanStorage.shared.updateCard(boardID: detail.board.id, card: updated)
        selectedKanbanCardID = updated.id
    }

    func addChildKanbanCard(title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let boardID = selectedKanbanBoardID, let parentID = selectedKanbanCardID else { return }

        saveKanbanCardDraft()

        guard let parentDetail = KanbanStorage.shared.findCard(id: parentID),
              parentDetail.board.id == boardID else { return }

        let targetColumnID = parentDetail.board.columns.first(where: {
            $0.name.localizedCaseInsensitiveCompare("Backlog") == .orderedSame
        })?.id ?? parentDetail.column.id

        guard let child = KanbanStorage.shared.addCard(
            boardID: boardID,
            columnID: targetColumnID,
            title: trimmedTitle,
            parentCardID: parentID
        ) else { return }

        openKanbanCardDetail(boardID: boardID, cardID: child.id)
    }

    func moveSelectedKanbanCard(to columnID: String) {
        guard let detail = selectedKanbanDetail else { return }
        saveKanbanCardDraft()

        guard let refreshed = KanbanStorage.shared.findCard(id: detail.card.id), refreshed.board.id == detail.board.id else {
            return
        }

        let targetCount = refreshed.board.columns.first(where: { $0.id == columnID })?.cards.count ?? 0
        KanbanStorage.shared.moveCard(
            boardID: refreshed.board.id,
            cardID: refreshed.card.id,
            toColumnID: columnID,
            toIndex: targetCount
        )

        let statusName = refreshed.board.columns.first(where: { $0.id == columnID })?.name ?? refreshed.column.name
        AIAssistantViewModel.shared.updateContext(
            todo: (title: currentKanbanDraftCard(from: refreshed).title, status: statusName)
        )
    }

    func deleteSelectedKanbanCard() {
        guard let boardID = selectedKanbanBoardID, let cardID = selectedKanbanCardID else {
            closeKanbanDetail()
            return
        }

        KanbanStorage.shared.deleteCard(boardID: boardID, cardID: cardID)
        selectedKanbanBoardID = nil
        selectedKanbanCardID = nil
        kanbanCardDraft = nil
        AIAssistantViewModel.shared.clearContext()
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    func exportKanbanCardMarkdown(board: KanbanBoard, column: KanbanColumn, card: KanbanCard) {
        let card = kanbanCardDraft?.updatedCard(from: card) ?? card
        let linkedReferenceSummaries = ItemLinkService.shared.summaries(for: card.linkedEntities)
        let markdown = KanbanCardMarkdownExporter.markdown(
            for: card,
            boardName: board.name,
            columnName: column.name,
            linkedReferenceSummaries: linkedReferenceSummaries
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        do {
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            CiderFileExporter.exportFile(
                sourceURL: tempURL,
                suggestedFileName: KanbanCardMarkdownExporter.suggestedFileName(for: card),
                helpText: "Export this Kanban card as a Markdown file."
            )
        } catch {
            Self.detailLogger.error("Kanban Markdown export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func assignDetailBookmarkToFolder(_ folderID: UUID?) {
        guard let bookmark = selectedDetailsBookmark else { return }
        _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
    }

    func assignDetailVaultFileToFolder(_ folderID: UUID?) {
        guard let file = selectedVaultFile else { return }
        let oldFolderID = file.folderID
        guard oldFolderID != folderID else { return }
        VaultFileService.shared.assignFile(file.id, toFolder: folderID)
        let folderName = VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
        CiderUndoManager.shared.record(.movedToFolder(
            itemType: .vaultFile,
            itemID: file.id,
            title: file.displayTitle,
            fromFolderID: oldFolderID,
            toFolderID: folderID,
            folderName: folderName
        ))
        if let updatedFile = VaultFileService.shared.file(for: file.id) {
            selectedVaultFile = updatedFile
        }
    }

    func assignDetailDateCardToFolder(_ folderID: UUID?) {
        guard let dateCard = selectedDateCard else { return }
        let oldFolderID = dateCard.folderID
        guard oldFolderID != folderID else { return }
        guard DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID) else { return }
        let folderName = VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
        CiderUndoManager.shared.record(.movedToFolder(
            itemType: .dateCard,
            itemID: dateCard.id,
            title: dateCard.title,
            fromFolderID: oldFolderID,
            toFolderID: folderID,
            folderName: folderName
        ))
        if let updated = DateCardStorage.shared.dateCard(for: dateCard.id) {
            selectedDateCard = updated
        }
    }

    func assignDetailContactToFolder(_ folderID: UUID?) {
        guard let contact = selectedContact else { return }
        let oldFolderID = contact.folderID
        guard oldFolderID != folderID else { return }
        guard ContactStorage.shared.assignContact(contact.id, toFolder: folderID) else { return }
        let folderName = VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
        CiderUndoManager.shared.record(.movedToFolder(
            itemType: .contact,
            itemID: contact.id,
            title: contact.displayName,
            fromFolderID: oldFolderID,
            toFolderID: folderID,
            folderName: folderName
        ))
        if let updated = ContactStorage.shared.contact(for: contact.id) {
            selectedContact = updated
        }
    }

    func assignDetailTodoToFolder(_ folderID: UUID?) {
        guard let todo = selectedTodoCard else { return }
        let oldFolderID = todo.folderID
        guard oldFolderID != folderID else { return }
        guard TodoCardStorage.shared.assignTodoCard(todo.id, toFolder: folderID) else { return }
        let folderName = VaultFolderService.shared.legacyFolders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
        CiderUndoManager.shared.record(.movedToFolder(
            itemType: .todo,
            itemID: todo.id,
            title: todo.title,
            fromFolderID: oldFolderID,
            toFolderID: folderID,
            folderName: folderName
        ))
        if let updated = TodoCardStorage.shared.todoCard(for: todo.id) {
            selectedTodoCard = updated
        }
    }

    func toggleDetailDateCardLabel(_ labelID: UUID) {
        guard var dateCard = selectedDateCard else { return }
        if dateCard.labelIDs.contains(labelID) {
            dateCard.labelIDs.removeAll { $0 == labelID }
        } else {
            dateCard.labelIDs.append(labelID)
        }
        guard DateCardStorage.shared.updateDateCard(dateCard) else { return }
        selectedDateCard = DateCardStorage.shared.dateCard(for: dateCard.id) ?? dateCard
    }

    func toggleDetailTodoLabel(_ labelID: UUID) {
        guard var todo = selectedTodoCard else { return }
        if todo.labelIDs.contains(labelID) {
            todo.labelIDs.removeAll { $0 == labelID }
        } else {
            todo.labelIDs.append(labelID)
        }
        guard TodoCardStorage.shared.updateTodoCard(todo) else { return }
        selectedTodoCard = TodoCardStorage.shared.todoCard(for: todo.id) ?? todo
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
