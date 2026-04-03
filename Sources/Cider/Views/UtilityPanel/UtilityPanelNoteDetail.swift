import SwiftUI

struct UtilityPanelNoteDetail: View {
    let noteID: UUID
    @ObservedObject var notesViewModel: NotesViewModel

    var body: some View {
        InlineNoteEditorView(viewModel: notesViewModel)
            .onAppear {
                if let note = NotesStorage.shared.notes.first(where: { $0.id == noteID }) {
                    if notesViewModel.selectedNote?.id != noteID {
                        notesViewModel.selectNote(note)
                    }
                }
            }
            .onChange(of: noteID) { _, newID in
                if let note = NotesStorage.shared.notes.first(where: { $0.id == newID }) {
                    notesViewModel.selectNote(note)
                }
            }
    }
}
