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
            onCancel: closeBookmarkDetails,
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
                onCancel: closeBookmarkDetails,
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
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
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
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
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
                onClose: closeGenericDetail,
                onModeChange: { _ in }
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
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                VaultFileDetailView(file: vaultFile, onDismiss: closeGenericDetail)
            }
        } else if let session = selectedSession {
            GenericItemDetailPanel(
                title: session.name,
                detailViewMode: .slideOut,
                width: BookmarksDesign.detailsSlideOutMinWidth,
                maxWidth: BookmarksDesign.detailsSlideOutMinWidth,
                onClose: closeGenericDetail,
                onModeChange: { _ in }
            ) {
                SessionDetailView(
                    session: session,
                    onDismiss: closeGenericDetail
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
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

        Text(currentDetailPageTitle)
            .font(CiderFont.subheadingSemibold)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

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
                isMetadataVisible: $bookmarkMetadataVisible
            )
        }

        DetailViewModePicker(currentMode: detailViewMode, onChange: changeDetailViewMode)
    }

    var currentDetailPageTitle: String {
        if let draft = detailsDraft { return draft.title }
        if let dateCard = selectedDateCard { return dateCard.title }
        if let contact = selectedContact { return contact.displayName }
        if let todoCard = selectedTodoCard { return todoCard.title }
        if let vaultFile = selectedVaultFile { return vaultFile.filename }
        if let session = selectedSession { return session.name }
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
            onCancel: closeBookmarkDetails,
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
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
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                VaultFileDetailView(file: vaultFile, onDismiss: closeGenericDetail)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    var noteDetailPageView: some View {
        InlineNoteEditorView(viewModel: notesViewModel)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
    }

    // MARK: - Note Detail Views

    @ViewBuilder
    var noteDetailSlideOutContainer: some View {
        GenericItemDetailPanel(
            title: "",
            detailViewMode: detailViewMode,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            showTitle: false,
            scrollsContent: false,
            onResize: { newWidth in
                let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                detailSlideOutWidth = clamped
            },
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode,
            toolbarExtra: { NotesCompactToolbar(viewModel: notesViewModel) },
            trailingExtra: { NotesInfoToggleButton(viewModel: notesViewModel) }
        ) {
            InlineNoteEditorView(viewModel: notesViewModel)
        }
    }

    @ViewBuilder
    var noteDetailFullPanelOverlay: some View {
        GenericItemDetailPanel(
            title: "",
            detailViewMode: detailViewMode,
            showDragHandle: false,
            showTitle: false,
            scrollsContent: false,
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode,
            toolbarExtra: { NotesCompactToolbar(viewModel: notesViewModel) },
            trailingExtra: { NotesInfoToggleButton(viewModel: notesViewModel) }
        ) {
            InlineNoteEditorView(viewModel: notesViewModel)
        }
        .padding(BookmarksDesign.detailsSlideOutFloatInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .transition(.opacity)
    }
}
