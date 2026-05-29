import SwiftUI

extension CiderPanelView {

    // MARK: - Bookmark Detail Views

    func makeDetailDraftBinding(fallback: BookmarkDetailsDraft) -> Binding<BookmarkDetailsDraft> {
        Binding(
            get: { self.detailsDraft ?? fallback },
            set: { next in
                self.detailsDraft = next
                self.detailsErrorMessage = nil
            }
        )
    }

    @ViewBuilder
    var detailSlideOutContainer: some View {
        if let draft = detailsDraft {
        DetailSlideOutView(
            draft: makeDetailDraftBinding(fallback: draft),
            bookmark: selectedDetailsBookmark,
            errorMessage: detailsErrorMessage,
            folders: bookmarksViewModel.folders,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            detailViewMode: detailViewMode,
            isMetadataVisible: $bookmarkMetadataVisible,
            heroMode: $bookmarkHeroMode,

            webViewStore: detailWebViewStore,
            onResize: { newWidth in
                let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                detailSlideOutWidth = clamped
                detailWidthSaveTask?.cancel()
                detailWidthSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    var config = CiderConfig.load()
                    config.detailSlideOutWidth = clamped
                    config.save()
                }
            },
            onDelete: deleteDetailBookmark,
            onFolderChanged: assignDetailBookmarkToFolder,
            onOpenURL: openDetailURL,
            onCopyURL: copyDetailURL,
            onSave: saveBookmarkDetails,
            onFloat: floatBookmarkDetails,
            onCancel: closeBookmarkDetails,
            onOpenLinkedRef: openLinkedRef,
            onOpenKanbanCard: openKanbanCardDetail,
            onModeChange: changeDetailViewMode
        )
        }
    }

    @ViewBuilder
    var detailFullPanelOverlay: some View {
        if let draft = detailsDraft {
            DetailSlideOutView(
                draft: makeDetailDraftBinding(fallback: draft),
                bookmark: selectedDetailsBookmark,
                errorMessage: detailsErrorMessage,
                folders: bookmarksViewModel.folders,
                detailViewMode: detailViewMode,
                isMetadataVisible: $bookmarkMetadataVisible,
                heroMode: $bookmarkHeroMode,

                webViewStore: detailWebViewStore,
                onDelete: deleteDetailBookmark,
                onFolderChanged: assignDetailBookmarkToFolder,
                onOpenURL: openDetailURL,
                onCopyURL: copyDetailURL,
                onSave: saveBookmarkDetails,
                onFloat: floatBookmarkDetails,
                onCancel: closeBookmarkDetails,
                onOpenLinkedRef: openLinkedRef,
                onOpenKanbanCard: openKanbanCardDetail,
                onModeChange: changeDetailViewMode,
                showDragHandle: false
            )
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: - Generic Item Detail Views (Date Cards, Contacts)

    @ViewBuilder
    var genericDetailSlideOutContainer: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                metadataVisible: $genericMetadataVisible,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onFloat: floatDateCardDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { AIDetailActionsButton(eventTitle: dateCard.title) },
                metadata: {
                    BasicItemMetadataInspectorView(
                        dateCard: dateCard,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailDateCardToFolder,
                        onToggleLabel: toggleDetailDateCardLabel,
                        onDelete: deleteDetailDateCard
                    )
                }
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                metadataVisible: $genericMetadataVisible,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onFloat: floatContactDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { AIDetailActionsButton(contactName: contact.displayName) },
                metadata: {
                    ContactMetadataInspectorView(
                        contact: contact,
                        onOpenLinkedRef: openLinkedRef,
                        onSaveContact: { selectedContact = $0 },
                        onFolderChanged: assignDetailContactToFolder,
                        onDelete: deleteDetailContact
                    )
                }
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        genericMetadataVisible = true
                    },
                    onDismiss: closeGenericDetail
                )
            }
        } else if let todoCard = selectedTodoCard {
            // Todos always use slide-out at fixed min width — no full panel or page modes
            GenericItemDetailPanel(
                title: todoCard.title,
                detailViewMode: .slideOut,
                width: BookmarksDesign.detailsSlideOutMinWidth,
                maxWidth: BookmarksDesign.detailsSlideOutMinWidth,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatTodoDetail,
                onClose: closeGenericDetail,
                onModeChange: { _ in },
                trailingExtra: { AIDetailActionsButton(todoTitle: todoCard.title) },
                metadata: {
                    BasicItemMetadataInspectorView(
                        todo: todoCard,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailTodoToFolder,
                        onToggleLabel: toggleDetailTodoLabel,
                        onDelete: deleteDetailTodo
                    )
                }
            ) {
                TodoDetailView(
                    todoCard: todoCard,
                    onEdit: {
                        closeGenericDetail()
                        newTodoEditorContext = TodoEditorContext(existingCard: todoCard)
                    },
                    onDismiss: closeGenericDetail
                )
            }
        } else if let vaultFile = selectedVaultFile {
            GenericItemDetailPanel(
                title: vaultFile.filename,
                detailViewMode: detailViewMode,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                scrollsContent: false,
                metadataVisible: $genericMetadataVisible,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onFloat: floatVaultFileDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    VaultFileMetadataInspectorView(
                        file: vaultFile,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailVaultFileToFolder,
                        onDelete: deleteDetailVaultFile
                    )
                }
            ) {
                VaultFileDetailView(file: vaultFile, onDismiss: closeGenericDetail)
            }
        }
    }

    @ViewBuilder
    var kanbanDetailSlideOutContainer: some View {
        if let detail = selectedKanbanDetail {
            let draftBinding = Binding<KanbanCardDraft>(
                get: { kanbanCardDraft ?? KanbanCardDraft(card: detail.card) },
                set: { kanbanCardDraft = $0 }
            )
            let draftCard = currentKanbanDraftCard(from: detail)
            let currentWidth = min(detailSlideOutWidth, maxSlideOutWidth)
            let metadataBinding = Binding<Bool>(
                get: { kanbanMetadataVisible },
                set: { isVisible in
                    withAnimation(reduceMotion ? .none : .snappy) {
                        kanbanMetadataVisible = isVisible
                        if isVisible {
                            detailSlideOutWidth = KanbanDetailSlideOutLayoutPolicy.expandedWidth(
                                currentWidth: currentWidth,
                                maxWidth: maxSlideOutWidth,
                                sourceNotesVisible: kanbanSourceNotesVisible,
                                metadataVisible: true
                            )
                        }
                    }
                }
            )
            let sourceNotesBinding = Binding<Bool>(
                get: { kanbanSourceNotesVisible },
                set: { isVisible in
                    withAnimation(reduceMotion ? .none : .snappy) {
                        kanbanSourceNotesVisible = isVisible
                        if isVisible {
                            detailSlideOutWidth = KanbanDetailSlideOutLayoutPolicy.expandedWidth(
                                currentWidth: currentWidth,
                                maxWidth: maxSlideOutWidth,
                                sourceNotesVisible: true,
                                metadataVisible: kanbanMetadataVisible
                            )
                        }
                    }
                }
            )

            GenericItemDetailPanel(
                title: draftCard.title,
                detailViewMode: .slideOut,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                showTitle: false,
                scrollsContent: false,
                metadataVisible: metadataBinding,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    let fittingState = KanbanDetailSlideOutLayoutPolicy.fittingState(
                        for: clamped,
                        sourceNotesVisible: kanbanSourceNotesVisible,
                        metadataVisible: kanbanMetadataVisible
                    )
                    kanbanSourceNotesVisible = fittingState.sourceNotesVisible
                    kanbanMetadataVisible = fittingState.metadataVisible
                    detailSlideOutWidth = min(fittingState.width, maxSlideOutWidth)
                },
                onClose: closeKanbanDetail,
                onModeChange: { _ in },
                trailingExtra: {
                    KanbanSourceNotesToggleButton(isVisible: sourceNotesBinding)
                },
                metadata: {
                    KanbanCardMetadataInspectorView(
                        board: detail.board,
                        column: detail.column,
                        card: detail.card,
                        draft: draftBinding,
                        onSave: saveKanbanCardDraft,
                        onMove: { columnID in
                            moveSelectedKanbanCard(to: columnID)
                        },
                        onDelete: deleteSelectedKanbanCard,
                        onExportMarkdown: {
                            exportKanbanCardMarkdown(board: detail.board, column: detail.column, card: detail.card)
                        },
                        onOpenKanbanCard: { cardID in
                            openKanbanCardDetail(boardID: detail.board.id, cardID: cardID)
                        },
                        onAddChildCard: { title in
                            addChildKanbanCard(title: title)
                        },
                        onOpenLinkedRef: openLinkedRef
                    )
                }
            ) {
                KanbanCardDetailView(
                    boardID: detail.board.id,
                    boardName: detail.board.name,
                    cardID: detail.card.id,
                    draft: draftBinding,
                    sourceNotesVisible: sourceNotesBinding,
                    onSave: saveKanbanCardDraft,
                    onOpenKanbanCard: { cardID in
                        openKanbanCardDetail(boardID: detail.board.id, cardID: cardID)
                    }
                )
            }
        }
    }

    @ViewBuilder
    var genericDetailFullPanelOverlay: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatDateCardDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    BasicItemMetadataInspectorView(
                        dateCard: dateCard,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailDateCardToFolder,
                        onToggleLabel: toggleDetailDateCardLabel,
                        onDelete: deleteDetailDateCard
                    )
                }
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatContactDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    ContactMetadataInspectorView(
                        contact: contact,
                        onOpenLinkedRef: openLinkedRef,
                        onSaveContact: { selectedContact = $0 },
                        onFolderChanged: assignDetailContactToFolder,
                        onDelete: deleteDetailContact
                    )
                }
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        genericMetadataVisible = true
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        } else if let vaultFile = selectedVaultFile {
            GenericItemDetailPanel(
                title: vaultFile.filename,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                scrollsContent: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatVaultFileDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    VaultFileMetadataInspectorView(
                        file: vaultFile,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailVaultFileToFolder,
                        onDelete: deleteDetailVaultFile
                    )
                }
            ) {
                VaultFileDetailView(file: vaultFile, onDismiss: closeGenericDetail)
            }
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    var detailPageView: some View {
        if let draft = detailsDraft {
            bookmarkDetailPageView(draft: draft)
        } else if selectedDateCard != nil || selectedContact != nil || selectedVaultFile != nil {
            genericDetailPageView
        } else if isNoteDetailPageMode {
            noteDetailPageView
        }
    }

    @ViewBuilder
    var detailPageTitleBar: some View {
        Button {
            closeCurrentDetailForPageMode()
        } label: {
            Image(systemName: "chevron.left")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back")

        if isNoteDetailPageMode {
            EditablePageTitle(
                title: currentDetailPageTitle,
                onRename: renameCurrentNote
            )
        } else {
            Text(currentDetailPageTitle)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }

        Spacer(minLength: Spacing.sm)

        if isNoteDetailPageMode {
            NotesCompactToolbar(viewModel: notesViewModel)
            Spacer(minLength: Spacing.sm)
            NotesInfoToggleButton(viewModel: notesViewModel)
        }

        if isDetailPageMode {
            BookmarkPageToolbar(
                hasURL: detailsDraft?.hasURL == true,
                readerFailed: detailWebViewStore.readerFailed,
                readerReady: detailWebViewStore.readerReady,
                webViewReady: detailWebViewStore.webViewReady,
                heroMode: $bookmarkHeroMode,
                isMetadataVisible: $bookmarkMetadataVisible,
                onFloat: floatBookmarkDetails
            )
        }

        Button(action: floatCurrentDetailForPageMode) {
            Image(systemName: "rectangle.on.rectangle")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Float")

        DetailViewModePicker(currentMode: detailViewMode, onChange: changeDetailViewMode)
    }

    var currentDetailPageTitle: String {
        if let draft = detailsDraft { return draft.title }
        if let dateCard = selectedDateCard { return dateCard.title }
        if let contact = selectedContact { return contact.displayName }
        if let todoCard = selectedTodoCard { return todoCard.title }
        if let vaultFile = selectedVaultFile { return vaultFile.filename }
        if isNoteDetailPageMode {
            return notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
        }
        return "Details"
    }

    func closeCurrentDetailForPageMode() {
        if isDetailPageMode {
            closeBookmarkDetails()
        } else if isGenericDetailPageMode {
            closeGenericDetail()
        } else if isNoteDetailPageMode {
            closeNoteDetail()
        }
    }

    @ViewBuilder
    func bookmarkDetailPageView(draft: BookmarkDetailsDraft) -> some View {
        DetailSlideOutView(
            draft: makeDetailDraftBinding(fallback: draft),
            bookmark: selectedDetailsBookmark,
            errorMessage: detailsErrorMessage,
            folders: bookmarksViewModel.folders,
            detailViewMode: detailViewMode,
            isMetadataVisible: $bookmarkMetadataVisible,
            heroMode: $bookmarkHeroMode,

            webViewStore: detailWebViewStore,
            onDelete: deleteDetailBookmark,
            onFolderChanged: assignDetailBookmarkToFolder,
            onOpenURL: openDetailURL,
            onCopyURL: copyDetailURL,
            onSave: saveBookmarkDetails,
            onFloat: floatBookmarkDetails,
            onCancel: closeBookmarkDetails,
            onOpenLinkedRef: openLinkedRef,
            onOpenKanbanCard: openKanbanCardDetail,
            onModeChange: changeDetailViewMode,
            showDragHandle: false
        )
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    @ViewBuilder
    var genericDetailPageView: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatDateCardDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    BasicItemMetadataInspectorView(
                        dateCard: dateCard,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailDateCardToFolder,
                        onToggleLabel: toggleDetailDateCardLabel,
                        onDelete: deleteDetailDateCard
                    )
                }
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatContactDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    ContactMetadataInspectorView(
                        contact: contact,
                        onOpenLinkedRef: openLinkedRef,
                        onSaveContact: { selectedContact = $0 },
                        onFolderChanged: assignDetailContactToFolder,
                        onDelete: deleteDetailContact
                    )
                }
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        genericMetadataVisible = true
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        } else if let vaultFile = selectedVaultFile {
            GenericItemDetailPanel(
                title: vaultFile.filename,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                scrollsContent: false,
                metadataVisible: $genericMetadataVisible,
                onFloat: floatVaultFileDetail,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode,
                trailingExtra: { EmptyView() },
                metadata: {
                    VaultFileMetadataInspectorView(
                        file: vaultFile,
                        onOpenLinkedRef: openLinkedRef,
                        onFolderChanged: assignDetailVaultFileToFolder,
                        onDelete: deleteDetailVaultFile
                    )
                }
            ) {
                VaultFileDetailView(file: vaultFile, onDismiss: closeGenericDetail)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    var noteDetailPageView: some View {
        InlineNoteEditorView(viewModel: notesViewModel, onOpenLinkedRef: openLinkedRef)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
    }

    // MARK: - Note Detail Views

    @ViewBuilder
    var noteDetailSlideOutContainer: some View {
        GenericItemDetailPanel(
            title: noteDetailTitle,
            detailViewMode: detailViewMode,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            scrollsContent: false,
            onRenameTitle: renameCurrentNote,
            isEditingTitle: $isEditingNoteTitle,
            onResize: { newWidth in
                let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                detailSlideOutWidth = clamped
            },
            onFloat: floatNoteDetail,
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode,
            toolbarExtra: { NotesCompactToolbar(viewModel: notesViewModel) },
            trailingExtra: { NotesInfoToggleButton(viewModel: notesViewModel) }
        ) {
            InlineNoteEditorView(viewModel: notesViewModel, onOpenLinkedRef: openLinkedRef)
        }
    }

    @ViewBuilder
    var noteDetailFullPanelOverlay: some View {
        GenericItemDetailPanel(
            title: noteDetailTitle,
            detailViewMode: detailViewMode,
            showDragHandle: false,
            scrollsContent: false,
            onRenameTitle: renameCurrentNote,
            isEditingTitle: $isEditingNoteTitle,
            onFloat: floatNoteDetail,
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode,
            toolbarExtra: { NotesCompactToolbar(viewModel: notesViewModel) },
            trailingExtra: { NotesInfoToggleButton(viewModel: notesViewModel) }
        ) {
            InlineNoteEditorView(viewModel: notesViewModel, onOpenLinkedRef: openLinkedRef)
        }
        .padding(BookmarksDesign.detailsSlideOutFloatInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .transition(.opacity)
    }

    private var noteDetailTitle: String {
        notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
    }

    private func renameCurrentNote(_ newTitle: String) {
        guard let note = notesViewModel.selectedNote ?? selectedNote else { return }
        NotesStorage.shared.rename(note: note, to: newTitle)
    }
}

// MARK: - Editable Page Title

/// Double-click to rename inline in the page view title bar.
private struct EditablePageTitle: View {
    let title: String
    var onRename: ((String) -> Void)?

    @State private var isEditing = false
    @State private var draftName = ""

    var body: some View {
        if isEditing {
            TextField("Title", text: $draftName, onCommit: commit)
                .textFieldStyle(.plain)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .onExitCommand { isEditing = false }
                .lineLimit(1)
        } else {
            Text(title)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    guard onRename != nil else { return }
                    draftName = title
                    isEditing = true
                }
                .help("Double-click to rename")
        }
    }

    private func commit() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != title {
            onRename?(trimmed)
        }
        isEditing = false
    }
}
