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
            detailManagement.contains("notesViewModel.selectNote(\n                defaultEntry.note,\n                richDisplayContentOverride: defaultEntry.preparedDisplayContent"),
            "Opening Journal should load the default daily note and its rich-only display override through NotesViewModel without rewriting its source."
        )
        #expect(
            journalViews.contains("notesViewModel.selectNote(entry.note, richDisplayContentOverride: displayContent)"),
            "Changing journal navigation selection should load that daily note with its rich-only display override."
        )
        #expect(
            detailManagement.contains("notesViewModel.flushSave()"),
            "Closing or leaving Journal should flush only real pending note edits, so render-mode changes do not rewrite journal prose."
        )
    }

    @Test("journal rich mode uses prepared display content while markdown mode remains raw")
    func journalRichModeUsesPreparedDisplayContentWhileMarkdownModeRemainsRaw() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let notesViewModelURL = repoRoot.appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let journalViewsURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift")
        let nativeMarkdownURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Notes/NativeMarkdownEditorView.swift")
        let notesViewModel = try String(contentsOf: notesViewModelURL, encoding: .utf8)
        let journalViews = try String(contentsOf: journalViewsURL, encoding: .utf8)
        let nativeMarkdown = try String(contentsOf: nativeMarkdownURL, encoding: .utf8)

        #expect(
            journalViews.contains("let displayContent = entry.preparedDisplayContent(timestampFormat: CiderConfig.load().journalTimestampFormat)")
                && journalViews.contains("selectNote(entry.note, richDisplayContentOverride: displayContent)"),
            "Journal rich display should use the read-model's cached/prepared presentation string, including timestamp preferences."
        )
        #expect(
            notesViewModel.contains("richDisplayContentOverride"),
            "NotesViewModel should keep journal rich presentation separate from raw editing content."
        )
        #expect(
            notesViewModel.contains("richEditorMarkdownForCurrentSelection"),
            "NotesViewModel should route Rich editor pushes through the rich-only override when one exists."
        )
        #expect(
            nativeMarkdown.contains("viewModel.editingContent"),
            "Markdown/source mode should continue to show raw stored note content."
        )
    }

    @Test("journal rich markdown toggle avoids source rewrite and can reuse pushed rich content")
    func journalRichMarkdownToggleAvoidsSourceRewriteAndCanReusePushedRichContent() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let notesViewModelURL = repoRoot.appendingPathComponent("Sources/Cider/ViewModels/NotesViewModel.swift")
        let detailManagementURL = repoRoot.appendingPathComponent("Sources/Cider/Views/CiderPanelView+DetailManagement.swift")
        let notesViewModel = try String(contentsOf: notesViewModelURL, encoding: .utf8)
        let detailManagement = try String(contentsOf: detailManagementURL, encoding: .utf8)

        #expect(
            notesViewModel.contains("if mode == .source, richDisplayContentOverride == nil, let noteID = selectedNote?.id"),
            "Switching a journal rich presentation to Markdown should not sync transformed display markdown back into the source note."
        )
        #expect(
            notesViewModel.contains("lastRichEditorPushedMarkdown"),
            "Switching Markdown back to Rich should be able to skip reparsing when the desired rich markdown is already loaded."
        )
        #expect(
            detailManagement.contains("notesViewModel.setRichDisplayContentOverride(nil)"),
            "Leaving Journal should clear the rich-only presentation override so normal notes are unaffected."
        )
    }

    @Test("journal capture card links use safe external and resolved internal navigation policies")
    func journalCaptureCardLinksUseScopedNavigationPolicies() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let journalViewsURL = repoRoot.appendingPathComponent("Sources/Cider/Views/Journal/JournalLibraryViews.swift")
        let journalViews = try String(contentsOf: journalViewsURL, encoding: .utf8)

        #expect(journalViews.contains(".environment(\\.openURL, OpenURLAction"))
        #expect(journalViews.contains("CiderOpenPolicy.shared.openIfAllowed(.untrustedWeb(url))"))
        #expect(journalViews.contains("isCanonicalItemResolvable: isCanonicalItemResolvable"))
        #expect(journalViews.contains("onOpenCanonicalItem(ref)"))
        #expect(journalViews.contains("return .discarded"))
    }
}
