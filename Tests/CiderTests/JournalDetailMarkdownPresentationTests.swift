import Foundation
import Testing

@Suite("Journal Detail Markdown Presentation Tests")
struct JournalDetailMarkdownPresentationTests {
    @Test("journal detail reuses regular note markdown toolbar and editor")
    func journalDetailReusesRegularNoteMarkdownToolbarAndEditor() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let detailViewsURL = repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailViews.swift")
        let journalViewsURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift")
        let detailViews = try String(contentsOf: detailViewsURL, encoding: .utf8)
        let journalViews = try String(contentsOf: journalViewsURL, encoding: .utf8)

        let journalBranches = detailViews.components(separatedBy: "isJournalDetailOpen").dropFirst().joined(separator: "isJournalDetailOpen")
        #expect(
            journalBranches.contains("toolbarExtra: { NotesCompactToolbar(viewModel: notesViewModel) }"),
            "Journal detail should expose the same top Markdown/rich mode control used by regular notes."
        )
        #expect(
            journalViews.contains("InlineNoteEditorView(viewModel: notesViewModel"),
            "Journal detail should render and edit the selected journal note with the regular note Markdown editor stack."
        )
    }

    @Test("journal entry selection drives notes view model without source mutation on mode changes")
    func journalEntrySelectionDrivesNotesViewModelWithoutSourceMutationOnModeChanges() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let detailManagementURL = repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailManagement.swift")
        let journalViewsURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift")
        let detailManagement = try String(contentsOf: detailManagementURL, encoding: .utf8)
        let journalViews = try String(contentsOf: journalViewsURL, encoding: .utf8)

        #expect(
            detailManagement.contains("notesViewModel.selectNote(defaultEntry.note)"),
            "Opening Journal should load the default daily note through NotesViewModel without rewriting its source."
        )
        #expect(
            journalViews.contains("notesViewModel.selectNote(entry.note)"),
            "Changing journal navigation selection should load that daily note through NotesViewModel."
        )
        #expect(
            detailManagement.contains("notesViewModel.flushSave()"),
            "Closing or leaving Journal should flush only real pending note edits, so render-mode changes do not rewrite journal prose."
        )
    }
}
