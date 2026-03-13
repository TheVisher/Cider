import SwiftUI

extension CiderPanelView {

    // MARK: - Quick Actions

    func handleQuickAction(_ action: QuickAction) {
        isSearchPaletteVisible = false
        switch action {
        case .newBookmark:
            _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
        case .newNote:
            createNoteAndOpen(title: "", content: "")
        case .newEvent:
            newEventEditorContext = DateCardEditorContext(existingCard: nil, defaultDate: Date())
        case .newContact:
            newContactEditorContext = ContactEditorContext(existingContact: nil)
        case .newTodo:
            newTodoEditorContext = TodoEditorContext(existingCard: nil)
        case .newFolder:
            NotificationCenter.default.post(name: .showFolderCreationField, object: nil)
        case .newTag:
            openOrSelectTagTab()
        case .newTab:
            createSavedViewFromCurrentState()
        case .newWhiteboard:
            let canvas = WhiteboardStorage.shared.createCanvas(name: "Untitled Whiteboard")
            let savedView = savedViewStorage.createWhiteboardView(name: canvas.name, canvasID: canvas.id)
            savedViewStorage.addToTabOrder(savedView.id)
            selectedFolderID = nil
            selectedTab = .savedView(id: savedView.id, name: savedView.name)
        case .openSettings:
            NotificationCenter.default.post(name: .openCiderSettings, object: nil)
        }
    }

    // MARK: - Note Creation

    func createNoteAndOpen(title: String, content: String) {
        // Create on disk first so selectNote picks up the right path/content
        var note = NotesStorage.shared.createNew()

        if !title.isEmpty {
            NotesStorage.shared.rename(note: note, to: title)
            // Refresh from storage so we have the updated filename/title
            note = NotesStorage.shared.notes.first(where: { $0.id == note.id }) ?? note
        }

        if !content.isEmpty {
            note.content = content
            NotesStorage.shared.save(note: note)
        }

        openNoteDetail(note)
    }

    // MARK: - Note Detail

    func openNoteDetail(_ note: Note) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        let wasExpanded = isAnyDetailOpen
        // Clear other detail state silently
        detailBookmarkID = nil; detailsDraft = nil; detailsErrorMessage = nil
        selectedDateCard = nil; selectedContact = nil
        // Open note
        notesViewModel.selectNote(note)
        selectedNote = note
        isEditingNoteTitle = false
        DispatchQueue.main.async { notesViewModel.focusEditorIfFindBarHidden() }
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    func closeNoteDetail() {
        guard isNoteDetailOpen else { return }
        notesViewModel.flushSave()
        selectedNote = nil
        notesViewModel.activeExternalFile = nil
        isEditingNoteTitle = false
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }
}
