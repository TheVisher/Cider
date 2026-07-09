import Testing
@testable import Cider

@MainActor
@Suite("Notes View Model Journal Display Tests")
struct NotesViewModelJournalDisplayTests {
    @Test("journal selection keeps raw source content while Rich mode uses display override")
    func journalSelectionKeepsRawSourceContentWhileRichModeUsesDisplayOverride() {
        let raw = """
        # Journal 07-08-2026
        ## Entries
        ## 15:16
        Source: capture.add
        Body text.
        """
        let display = """
        # Journal 07-08-2026
        ## Entries
        - 3:16 PM - Captured by Cider agent
        Body text.
        """
        let note = Note(title: "Journal 07-08-2026", content: raw)
        let viewModel = NotesViewModel()

        viewModel.selectNote(note, richDisplayContentOverride: display)

        #expect(viewModel.selectedNote?.content == raw)
        #expect(viewModel.editingContent == raw)
        #expect(viewModel.richEditorMarkdownForCurrentSelection == display)
        #expect(!viewModel.richEditorMarkdownForCurrentSelection.contains("Source: capture.add"))
        #expect(viewModel.richEditorMarkdownForCurrentSelection.contains("Captured by Cider agent"))

        viewModel.contentChanged(display + "\nRich editor normalization")

        #expect(viewModel.editingContent == raw)
        #expect(viewModel.hasPendingSave == false)
    }
}
