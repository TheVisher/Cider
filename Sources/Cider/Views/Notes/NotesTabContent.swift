import SwiftUI

struct NotesTabContent: View {
    @ObservedObject var viewModel: NotesViewModel
    let searchText: String
    var folders: [Folder] = []
    var selectedFolderID: UUID?
    @Binding var selectedItemIDs: Set<String>
    var onOpenNote: ((Note) -> Void)?

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

    var body: some View {
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
                selectedItemIDs: $selectedItemIDs,
                searchText: searchText,
                selectedNoteID: nil,
                onOpenNote: { note in onOpenNote?(note) },
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
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            EmptyStateView(
                icon: "note.text",
                title: "No notes yet",
                actionLabel: "Create New Note",
                action: {
                    viewModel.createNewNote()
                    if let note = viewModel.selectedNote {
                        onOpenNote?(note)
                    }
                }
            )
        } else {
            EmptyStateView(icon: "note.text", title: "No matching notes")
        }
    }
}
