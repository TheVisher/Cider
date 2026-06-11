import SwiftUI
import os

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
            if let intent = WorkspaceRouteIntentPolicy.intent(
                forQuickAction: action,
                selectedProjectID: selectedProjectWorkspaceID,
                createdBoardID: nil
            ) {
                applyWorkspaceRouteIntent(intent)
            }
        case .newLibraryView:
            if let intent = WorkspaceRouteIntentPolicy.intent(
                forQuickAction: action,
                selectedProjectID: selectedProjectWorkspaceID,
                createdBoardID: nil
            ) {
                applyWorkspaceRouteIntent(intent)
            }
        case .newKanban:
            let board = KanbanStorage.shared.createBoard(name: "Untitled Board")
            ProjectBoardRegistrationService.register(
                board: board,
                projectID: selectedProjectWorkspaceID,
                associationStore: projectAssociationStore
            )
            if let intent = WorkspaceRouteIntentPolicy.intent(
                forQuickAction: action,
                selectedProjectID: selectedProjectWorkspaceID,
                createdBoardID: board.id
            ) {
                applyWorkspaceRouteIntent(intent)
            }
        case .openSettings:
            NotificationCenter.default.post(name: .openCiderSettings, object: nil)
        }
    }

    // MARK: - Note Creation

    func createNoteAndOpen(title: String, content: String) {
        do {
            let result = try CiderCaptureService().addNoteCapture(
                title: title,
                content: content,
                folderID: selectedFolderID
            )
            postCaptureToast(result: result, successMessage: "Created note")
            if let note = NotesStorage.shared.notes.first(where: { $0.id == result.item.id }) {
                openNoteDetail(note)
            }
        } catch {
            Logger(subsystem: "com.cider.app", category: "QuickActions")
                .error("Failed to capture note from quick action: \(error.localizedDescription, privacy: .public)")
        }
    }

    func postCaptureToast(result: CiderCaptureResult, successMessage: String) {
        NotificationCenter.default.post(
            name: .showBookmarkCaptureToast,
            object: nil,
            userInfo: [
                "receipt": UICaptureReceipt(result: result),
                "successMessage": successMessage,
            ]
        )
    }

    // MARK: - Note Detail

    func openNoteDetail(_ note: Note, sourceEvidenceFindQuery: String? = nil) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isDetailOpen { saveBookmarkDetails() }
        if isNoteDetailOpen { notesViewModel.flushSave() }
        let wasExpanded = isAnyDetailOpen
        clearDetailSelectionState(except: .note)
        notesViewModel.selectNote(note)
        selectedNote = note
        isEditingNoteTitle = false
        if let sourceEvidenceFindQuery {
            notesViewModel.showFindBar()
            notesViewModel.updateFindQuery(sourceEvidenceFindQuery)
        } else {
            DispatchQueue.main.async { notesViewModel.focusEditorIfFindBarHidden() }
        }
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }

        let excerpt = String(note.contentPreview.prefix(200))
        AIAssistantViewModel.shared.updateContext(
            note: (title: note.title, excerpt: excerpt),
            itemRef: LibraryEntityRef(type: .note, entityID: note.id)
        )
    }

    func closeNoteDetail() {
        guard isNoteDetailOpen else { return }
        notesViewModel.flushSave()
        selectedNote = nil
        isEditingNoteTitle = false
        AIAssistantViewModel.shared.clearContext()
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }
}
