import SwiftUI

struct NotesTabContent: View {
    @ObservedObject var viewModel: NotesViewModel
    let searchText: String
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
            VStack(spacing: 0) {
                notesToolbar
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)

                if filteredNotes.isEmpty {
                    emptyState
                } else {
                    notesList
                }
            }

            if isExpandMode, isEditing, let noteID = selectedNoteID,
               viewModel.notes.contains(where: { $0.id == noteID }) {
                noteEditorOverlay
            }
        }
    }

    // MARK: - Toolbar

    private var notesToolbar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: 0)

            Button {
                viewModel.createNewNote()
                if let note = viewModel.selectedNote {
                    openNote(note)
                }
            } label: {
                Label("New Note", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(filteredNotes) { note in
                    noteRow(note)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
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
                        .font(.system(size: 13, weight: .semibold))
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
                            .font(.system(size: 11, weight: .semibold))
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

    private func noteRow(_ note: Note) -> some View {
        Button {
            openNote(note)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundColor(CiderColors.tertiary)

                    Text(notePreview(for: note))
                        .font(.system(size: 11))
                        .foregroundColor(CiderColors.quaternary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separator.opacity(selectedNoteID == note.id ? 0.3 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func notePreview(for note: Note) -> String {
        let content = NotesStorage.shared.loadContent(for: note)
        let stripped = content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(80))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)

            if searchText.isEmpty {
                Text("No notes yet")
                    .font(.system(size: 13))
                    .foregroundColor(CiderColors.secondary)
                Button("Create New Note") {
                    viewModel.createNewNote()
                    if let note = viewModel.selectedNote {
                        openNote(note)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(CiderColors.controlAccent)
            } else {
                Text("No matching notes")
                    .font(.system(size: 13))
                    .foregroundColor(CiderColors.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor Overlay

    @ViewBuilder
    private var noteEditorOverlay: some View {
        ZStack {
            Color.black.opacity(BookmarksDesign.detailsBackdropOpacity)
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CiderColors.primary)
                            .onSubmit {
                                viewModel.renameCurrentNote(to: viewModel.editingTitle)
                                isEditingTitle = false
                            }
                            .onExitCommand { isEditingTitle = false }
                    } else {
                        Text(viewModel.selectedNote?.title ?? "Note")
                            .font(.system(size: 13, weight: .semibold))
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
                            .font(.system(size: 11, weight: .semibold))
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
                    Color.black.opacity(0.38)
                    Color.white.opacity(0.04)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
            .padding(Spacing.xl)
        }
        .transition(.opacity)
    }
}
