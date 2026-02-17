import SwiftUI

struct NotesTabContent: View {
    @ObservedObject var viewModel: NotesViewModel
    let searchText: String
    var folders: [Folder] = []
    var selectedFolderID: UUID?
    @State private var selectedNoteID: UUID?
    @State private var isEditing = false
    @State private var isEditingTitle = false

    private var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results = viewModel.notes
        if let selectedFolderID {
            results = results.filter { $0.folderID == selectedFolderID }
        }
        guard !query.isEmpty else { return results }
        return results.filter {
            $0.title.lowercased().contains(query)
        }
    }

    private var isExpandMode: Bool {
        CiderConfig.load().detailModalMode == .expand
    }

    var body: some View {
        ZStack {
            if filteredNotes.isEmpty {
                emptyState
            } else {
                NotesBrowserView(
                    notes: filteredNotes,
                    folders: folders,
                    displayMode: Binding(
                        get: { viewModel.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    ),
                    cardSizeScale: Binding(
                        get: { viewModel.cardSizeScale },
                        set: { viewModel.setCardSizeScale($0) }
                    ),
                    searchText: searchText,
                    selectedNoteID: selectedNoteID,
                    onOpenNote: { openNote($0) },
                    onRenameNote: { note, newTitle in
                        NotesStorage.shared.rename(note: note, to: newTitle)
                    },
                    onDeleteNote: { note in
                        viewModel.deleteNotes([note])
                    },
                    onMoveNoteToFolder: { note, folderID in
                        viewModel.assignNote(note, toFolder: folderID)
                    }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }

            if isExpandMode, isEditing, let noteID = selectedNoteID,
               viewModel.notes.contains(where: { $0.id == noteID }) {
                noteEditorOverlay
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerNewNoteInTab)) { _ in
            viewModel.createNewNote()
            if let note = viewModel.selectedNote {
                openNote(note)
            }
        }
        .task(id: viewModel.pendingNoteToOpen) {
            guard let noteID = viewModel.pendingNoteToOpen,
                  let note = viewModel.notes.first(where: { $0.id == noteID }) else { return }
            viewModel.pendingNoteToOpen = nil
            openNote(note)
        }
    }

    private func openNote(_ note: Note) {
        selectedNoteID = note.id
        viewModel.selectNote(note)
        isEditing = true
        isEditingTitle = false

        if !isExpandMode {
            showNotePopover(note)
        }
    }

    private func showNotePopover(_ note: Note) {
        let popoverContent = AnyView(
            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    Text(note.title)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel.flushSave()
                        isEditing = false
                        isEditingTitle = false
                        NotificationCenter.default.post(name: .dismissDetailPopover, object: nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Divider()
                    .background(CiderColors.separator)

                TipTapEditorView(viewModel: viewModel)
            }
        )

        NotificationCenter.default.post(
            name: .showDetailPopover,
            object: nil,
            userInfo: ["view": popoverContent]
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        if searchText.isEmpty {
            EmptyStateView(
                icon: "note.text",
                title: "No notes yet",
                actionLabel: "Create New Note",
                action: {
                    viewModel.createNewNote()
                    if let note = viewModel.selectedNote {
                        openNote(note)
                    }
                }
            )
        } else {
            EmptyStateView(icon: "note.text", title: "No matching notes")
        }
    }

    // MARK: - Editor Overlay

    @ViewBuilder
    private var noteEditorOverlay: some View {
        ZStack {
            CiderColors.backdropSubtle
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.flushSave()
                    isEditing = false
                }

            VStack(spacing: 0) {
                HStack(spacing: Spacing.sm) {
                    if isEditingTitle {
                        TextField("Note title", text: $viewModel.editingTitle)
                            .textFieldStyle(.plain)
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .onSubmit {
                                viewModel.renameCurrentNote(to: viewModel.editingTitle)
                                isEditingTitle = false
                            }
                            .onExitCommand { isEditingTitle = false }
                    } else {
                        Text(viewModel.selectedNote?.title ?? "Note")
                            .font(CiderFont.subheadingSemibold)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                if viewModel.selectedNote != nil {
                                    isEditingTitle = true
                                }
                            }
                    }

                    Spacer()

                    Button {
                        viewModel.flushSave()
                        isEditing = false
                        isEditingTitle = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(CiderFont.bodySemibold)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Divider()
                    .background(CiderColors.separator)

                TipTapEditorView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                    CiderColors.acrylicOverlayTint
                    CiderColors.surfaceSubtle
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
            .padding(Spacing.xl)
        }
        .transition(.opacity)
    }
}
