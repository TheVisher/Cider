import SwiftUI
import Combine
import WebKit
import AppKit

struct NotesExternalChangeState: Equatable {
    let modifiedAt: Date
}

struct NotesRecoverySnapshotChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let snapshotDate: Date
}

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var hasPendingSave: Bool = false
    @Published var displayMode: NoteDisplayMode
    @Published var cardSizeScale: Double
    @Published var selectedNote: Note?
    @Published var activeExternalFile: ExternalFile?
    @Published var editingContent: String = ""
    @Published var searchText: String = ""
    @Published var isCollapsed: Bool = false
    @Published var isVisible: Bool = false
    @Published var pendingNoteToOpen: UUID?
    @Published var editingTitle: String = ""
    @Published var charCount: Int = 0
    @Published var externalChangeState: NotesExternalChangeState?
    @Published var isFindBarVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var findMatchCount: Int = 0
    @Published var findMatchIndex: Int = 0
    @Published var findFocusToken = UUID()
    @Published private(set) var notesEditorTextSize: NotesEditorTextSize
    @Published var isFormattingToolbarPinned: Bool {
        didSet {
            UserDefaults.standard.set(
                isFormattingToolbarPinned,
                forKey: Self.formattingToolbarPinnedStorageKey
            )
        }
    }

    /// The singleton editor WebView, created on first access via `ensureEditorWebView()`.
    private(set) var editorWebView: WKWebView?
    private var editorCoordinator: TipTapEditorCoordinator?
    private var editorIsReady = false

    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncedDiskContent: String = ""
    /// True while waiting for TipTap's first `contentChanged` after loading an external file.
    /// TipTap normalizes markdown on parse; we absorb that round-trip without writing to disk.
    private var isLoadingExternalFile = false
    private var pendingExternalDiskContent: String?
    private var ignoredExternalDiskContent: String?
    private static let formattingToolbarPinnedStorageKey = "cider.notes.formattingToolbarPinned"

    var notes: [Note] {
        NotesStorage.shared.notes
    }

    @discardableResult
    func assignNote(_ note: Note, toFolder folderID: UUID?) -> Bool {
        NotesStorage.shared.assignNote(note.id, toFolder: folderID)
    }

    var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        let query = searchText.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(query) ||
            NotesStorage.shared.loadContent(for: $0).lowercased().contains(query)
        }
    }

    var recoverySnapshotChoices: [NotesRecoverySnapshotChoice] {
        guard let note = selectedNote else { return [] }
        let snapshots = NotesStorage.shared.snapshots(for: note)
        guard !snapshots.isEmpty else { return [] }

        let now = Date()
        let targetAges: [(TimeInterval, String)] = [
            (5 * 60, "5 min"),
            (15 * 60, "15 min"),
            (30 * 60, "30 min"),
            (60 * 60, "1 hour"),
            (24 * 60 * 60, "24 hours"),
        ]

        var choices: [NotesRecoverySnapshotChoice] = []
        var usedSnapshotIDs = Set<String>()

        func appendChoice(from snapshot: NoteSnapshotInfo, title: String) {
            guard usedSnapshotIDs.insert(snapshot.id).inserted else { return }
            choices.append(
                NotesRecoverySnapshotChoice(
                    id: snapshot.id,
                    title: title,
                    snapshotDate: snapshot.modifiedAt
                )
            )
        }

        if let latest = snapshots.first {
            appendChoice(from: latest, title: "Latest")
        }

        for (age, title) in targetAges {
            let cutoff = now.addingTimeInterval(-age)
            if let match = snapshots.first(where: { $0.modifiedAt <= cutoff }) {
                appendChoice(from: match, title: title)
            }
        }

        return choices
    }

    var allRecoverySnapshotChoices: [NotesRecoverySnapshotChoice] {
        guard let note = selectedNote else { return [] }
        return NotesStorage.shared.snapshots(for: note).map { snapshot in
            NotesRecoverySnapshotChoice(
                id: snapshot.id,
                title: snapshot.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                snapshotDate: snapshot.modifiedAt
            )
        }
    }

    init() {
        let config = CiderConfig.load()
        self.displayMode = config.notesDefaultViewMode
        self.cardSizeScale = config.notesCardSizeScale ?? 1.0
        self.notesEditorTextSize = config.notesEditorTextSize
        self.isFormattingToolbarPinned = UserDefaults.standard.bool(
            forKey: Self.formattingToolbarPinnedStorageKey
        )

        // Observe storage changes
        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileSelectedNote()
                self.detectExternalChangeIfNeeded()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ciderConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let config = CiderConfig.load()
                let newMode = config.notesDefaultViewMode
                let newScale = config.notesCardSizeScale ?? 1.0
                if self.displayMode != newMode { self.displayMode = newMode }
                if self.cardSizeScale != newScale { self.cardSizeScale = newScale }
                guard self.notesEditorTextSize != config.notesEditorTextSize else { return }
                self.notesEditorTextSize = config.notesEditorTextSize
                self.applyNotesEditorTextSize()
            }
            .store(in: &cancellables)
    }

    // MARK: - WebView Lifecycle

    /// Creates the singleton WKWebView on first access. Subsequent calls return
    /// the same instance. The WebView is owned by this ViewModel and outlives
    /// any individual TipTapEditorView mount.
    @discardableResult
    func ensureEditorWebView() -> WKWebView {
        if let existing = editorWebView {
            return existing
        }

        let coordinator = TipTapEditorCoordinator(viewModel: self)
        editorCoordinator = coordinator

        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(coordinator, name: "contentChanged")
        contentController.add(coordinator, name: "editorReady")
        contentController.add(coordinator, name: "imageDropped")
        contentController.add(coordinator, name: "slashCommandImage")
        contentController.add(coordinator, name: "slashPopupState")
        contentController.add(coordinator, name: "floatingToolbarState")
        contentController.add(coordinator, name: "editorError")

        let webView = TipTapWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.viewModel = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.onFindRequested = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFindShortcut()
            }
        }

        if let resourceURL = Bundle.module.url(forResource: "editor", withExtension: "html", subdirectory: "TipTapEditor") {
            let readAccessRoot = URL(fileURLWithPath: "/", isDirectory: true)
            webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessRoot)
        }

        editorWebView = webView
        return webView
    }

    /// Called when a .md/.txt file is dropped onto the editor. Reads the content
    /// with correct UTF-8 encoding (bypassing WKWebView's DOM drop handler which
    /// may interpret files as Latin-1).
    func handleDroppedTextFileContent(_ content: String) {
        pushContentToEditor(content)
    }

    // MARK: - Editor Bridge

    /// Called when the TipTap editor signals it is ready.
    func editorDidBecomeReady() {
        editorIsReady = true
        hasPendingSave = false
        applyNotesEditorTextSize()
        // If a note is already selected, push its content to the editor
        if let note = selectedNote {
            let content = loadPersistedContent(for: note)
            editingContent = content
            lastSyncedDiskContent = content
            pushContentToEditor(content)
        } else if activeExternalFile != nil {
            // External file was opened before editor was ready — push its content now
            isLoadingExternalFile = true
            pushContentToEditor(editingContent)
        }
    }

    /// Push markdown content to the TipTap editor via JS.
    private func pushContentToEditor(_ markdown: String) {
        guard editorIsReady, let webView = editorWebView else { return }
        let editorMarkdown = NotesStorage.shared.markdownForEditor(markdown)
        // Use JSON encoding for safe string transport — handles all special
        // characters (newlines, quotes, backslashes, unicode) correctly.
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: editorMarkdown, options: .fragmentsAllowed
        ), let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.editorAPI.setContent(\(jsonString))")
    }

    /// Focus the TipTap editor.
    func focusEditor() {
        guard editorIsReady, let webView = editorWebView else { return }
        webView.evaluateJavaScript("window.editorAPI.focus()")
    }

    /// Focus editor unless the find UI is currently active.
    func focusEditorIfFindBarHidden() {
        guard !isFindBarVisible else { return }
        focusEditor()
    }

    // MARK: - Image Handling

    func handleImageDrop(data: Data, filename: String) {
        guard let note = selectedNote else { return }
        let imageURL = NotesStorage.shared.saveImage(data: data, filename: filename, for: note)
        guard let webView = editorWebView else { return }
        let src = imageURL.absoluteString
        let alt = filename
        guard let srcData = try? JSONSerialization.data(withJSONObject: src, options: .fragmentsAllowed),
              let altData = try? JSONSerialization.data(withJSONObject: alt, options: .fragmentsAllowed),
              let srcJSON = String(data: srcData, encoding: .utf8),
              let altJSON = String(data: altData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.editorAPI.insertImage(\(srcJSON), \(altJSON))")
    }

    func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url else { return }
                if let data = try? Data(contentsOf: url) {
                    self.handleImageDrop(data: data, filename: url.lastPathComponent)
                }
            }
        }
    }

    // MARK: - Note Selection

    func selectNote(_ note: Note) {
        // Save current note before switching
        flushSave()
        activeExternalFile = nil
        isLoadingExternalFile = false

        var loaded = note
        loaded.content = loadPersistedContent(for: note)
        selectedNote = loaded
        editingContent = loaded.content
        editingTitle = loaded.title
        charCount = loaded.content.count
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = loaded.content
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        pushContentToEditor(loaded.content)
    }

    func openExternalFile(_ file: ExternalFile) {
        flushSave()
        activeExternalFile = file
        selectedNote = nil
        let content = (try? String(contentsOf: file.path, encoding: .utf8)) ?? ""
        editingContent = content
        editingTitle = file.title
        charCount = content.count
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = content
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false
        isLoadingExternalFile = true
        pushContentToEditor(content)
    }

    // MARK: - CRUD

    func createNewNote() {
        flushSave()
        let note = NotesStorage.shared.createNew()
        selectedNote = note
        editingContent = ""
        editingTitle = note.title
        charCount = 0
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = ""
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        // Clear editor and focus
        if editorIsReady, let webView = editorWebView {
            webView.evaluateJavaScript("window.editorAPI.clear()")
            webView.evaluateJavaScript("window.editorAPI.focus()")
        }
    }

    func deleteCurrentNote() {
        guard let note = selectedNote else { return }
        deleteNotes([note])
    }

    func deleteNotes(_ notes: [Note]) {
        guard !notes.isEmpty else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil

        let idsToDelete = Set(notes.map(\.id))
        if let selected = selectedNote, idsToDelete.contains(selected.id) {
            clearSelectedNote()
        }

        var trashItems: [TrashItem] = []
        for note in notes {
            let trashItem = NotesStorage.shared.delete(note: note)
            trashItems.append(trashItem)
            NotesPanelPositionStore.shared.removeFrame(for: note.id)
        }
        if !trashItems.isEmpty {
            CiderUndoManager.shared.record(.bulkDeletedToTrash(trashItems))
        }
    }

    func renameCurrentNote(to newTitle: String) {
        guard let note = selectedNote, !newTitle.isEmpty else { return }
        NotesStorage.shared.rename(note: note, to: newTitle)
        // Refresh selected note
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            selectedNote = updated
            editingTitle = updated.title
        }
    }

    // MARK: - Auto-save

    func contentChanged(_ newContent: String) {
        let persistedContent = NotesStorage.shared.markdownForPersistence(newContent)
        editingContent = persistedContent
        charCount = persistedContent.count
        hasPendingSave = true

        if let externalFile = activeExternalFile {
            // Absorb the TipTap normalization round-trip on initial load.
            // Raw disk content ≠ TipTap-serialized markdown, so we update the
            // reference without writing to avoid a spurious mtime bump.
            if isLoadingExternalFile {
                isLoadingExternalFile = false
                lastSyncedDiskContent = persistedContent
                hasPendingSave = false
                return
            }
            // Don't save if content hasn't changed from what we loaded from disk
            guard persistedContent != lastSyncedDiskContent else {
                hasPendingSave = false
                return
            }
            // Auto-save back to the external file path
            saveWorkItem?.cancel()
            let fileURL = externalFile.path
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.activeExternalFile?.path == fileURL else { return }
                    let content = self.editingContent
                    self.lastSyncedDiskContent = content
                    self.pendingExternalDiskContent = nil
                    self.ignoredExternalDiskContent = nil
                    self.externalChangeState = nil
                    try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                    self.hasPendingSave = false
                }
            }
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
            return
        }

        guard var note = selectedNote else { return }
        note.content = persistedContent

        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, var current = self.selectedNote else { return }
                current.content = self.editingContent
                self.lastSyncedDiskContent = self.editingContent
                self.pendingExternalDiskContent = nil
                self.ignoredExternalDiskContent = nil
                self.externalChangeState = nil
                NotesStorage.shared.save(note: current)
                self.hasPendingSave = false
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// Immediately save any pending content by fetching current markdown from editor.
    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        if let externalFile = activeExternalFile {
            let content = editingContent
            guard content != lastSyncedDiskContent else {
                hasPendingSave = false
                syncExternalContentFromEditor(fileURL: externalFile.path)
                return
            }
            lastSyncedDiskContent = content
            pendingExternalDiskContent = nil
            ignoredExternalDiskContent = nil
            externalChangeState = nil
            try? content.write(to: externalFile.path, atomically: true, encoding: .utf8)
            hasPendingSave = false
            syncExternalContentFromEditor(fileURL: externalFile.path)
            return
        }

        guard var note = selectedNote else { return }

        // Save the latest known content immediately.
        note.content = editingContent
        lastSyncedDiskContent = editingContent
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        NotesStorage.shared.save(note: note)
        hasPendingSave = false

        // Then ask the editor for current content to catch any final keystrokes
        // that haven't crossed the JS->Swift bridge yet.
        syncContentFromEditor(noteID: note.id)
    }

    private func syncExternalContentFromEditor(fileURL: URL) {
        guard editorIsReady, let webView = editorWebView else { return }
        webView.evaluateJavaScript("window.editorAPI.getContent()") { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let markdown = result as? String,
                      self.activeExternalFile?.path == fileURL else { return }
                let content = NotesStorage.shared.markdownForPersistence(markdown)
                editingContent = content
                charCount = content.count
                pendingExternalDiskContent = nil
                ignoredExternalDiskContent = nil
                externalChangeState = nil
                guard content != self.lastSyncedDiskContent else {
                    hasPendingSave = false
                    return
                }
                lastSyncedDiskContent = content
                try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                hasPendingSave = false
            }
        }
    }

    private func syncContentFromEditor(noteID: UUID) {
        guard editorIsReady, let webView = editorWebView else { return }

        webView.evaluateJavaScript("window.editorAPI.getContent()") { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let markdown = result as? String,
                      var current = self.selectedNote,
                      current.id == noteID else { return }

                let persistedMarkdown = NotesStorage.shared.markdownForPersistence(markdown)
                editingContent = persistedMarkdown
                charCount = persistedMarkdown.count
                current.content = persistedMarkdown
                lastSyncedDiskContent = persistedMarkdown
                pendingExternalDiskContent = nil
                ignoredExternalDiskContent = nil
                externalChangeState = nil
                NotesStorage.shared.save(note: current)
                hasPendingSave = false
            }
        }
    }

    // MARK: - External Change Handling

    func reloadFromDiskAfterExternalChange() {
        guard let selected = selectedNote,
              let pendingExternalDiskContent,
              let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            return
        }

        applyDiskContent(pendingExternalDiskContent, from: updated)
    }

    func keepMineAfterExternalChange() {
        guard let pendingExternalDiskContent,
              var current = selectedNote else {
            return
        }

        ignoredExternalDiskContent = pendingExternalDiskContent
        self.pendingExternalDiskContent = nil
        externalChangeState = nil

        current.content = editingContent
        lastSyncedDiskContent = editingContent
        NotesStorage.shared.save(note: current)
        hasPendingSave = false
    }

    private func detectExternalChangeIfNeeded() {
        guard let selected = selectedNote,
              let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            return
        }

        let diskContent = loadPersistedContent(for: updated)

        if diskContent == lastSyncedDiskContent {
            if pendingExternalDiskContent == diskContent {
                pendingExternalDiskContent = nil
                externalChangeState = nil
            }
            return
        }

        if diskContent == editingContent {
            lastSyncedDiskContent = diskContent
            pendingExternalDiskContent = nil
            ignoredExternalDiskContent = nil
            externalChangeState = nil
            return
        }

        let hasUnsavedLocalChanges = editingContent != lastSyncedDiskContent
        if hasUnsavedLocalChanges {
            if ignoredExternalDiskContent == diskContent {
                return
            }
            pendingExternalDiskContent = diskContent
            externalChangeState = NotesExternalChangeState(modifiedAt: updated.modifiedAt)
            return
        }

        applyDiskContent(diskContent, from: updated)
    }

    private func applyDiskContent(_ diskContent: String, from note: Note) {
        guard var selected = selectedNote else { return }

        selected.title = note.title
        selected.relativePath = note.relativePath
        selected.modifiedAt = note.modifiedAt
        selected.content = diskContent
        selectedNote = selected

        editingContent = diskContent
        editingTitle = note.title
        charCount = diskContent.count
        lastSyncedDiskContent = diskContent
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        pushContentToEditor(diskContent)

        if isFindBarVisible, !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateFindQuery(findQuery)
        }
    }

    private func loadPersistedContent(for note: Note) -> String {
        NotesStorage.shared.loadContent(for: note)
    }

    // MARK: - In-note Find

    func showFindBar() {
        guard selectedNote != nil else { return }
        isFindBarVisible = true
        findFocusToken = UUID()
        if !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateFindQuery(findQuery)
        }
    }

    func hideFindBar() {
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        runEditorCommand("findClear")
        focusEditor()
    }

    func updateFindQuery(_ query: String) {
        findQuery = query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetFindResults()
            runEditorCommand("findClear")
            return
        }

        runFindCommand("findSetQuery", stringArgument: query)
    }

    func findNextResult() {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runFindCommand("findNext")
    }

    func findPreviousResult() {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runFindCommand("findPrevious")
    }

    func handleFindShortcut() {
        showFindBar()
    }

    // MARK: - Editor Formatting

    func editorUndo() {
        runEditorCommand("undo")
    }

    func editorRedo() {
        runEditorCommand("redo")
    }

    func editorToggleBold() {
        runEditorCommand("toggleBold")
    }

    func editorToggleItalic() {
        runEditorCommand("toggleItalic")
    }

    func editorToggleUnderline() {
        runEditorCommand("toggleUnderline")
    }

    func editorSetTextSizeSmall() {
        runEditorCommand("setFontSize", stringArgument: "12px")
    }

    func editorSetTextSizeNormal() {
        runEditorCommand("setFontSize", stringArgument: "14px")
    }

    func editorSetTextSizeLarge() {
        runEditorCommand("setFontSize", stringArgument: "18px")
    }

    func editorSetTextSizeExtraLarge() {
        runEditorCommand("setFontSize", stringArgument: "24px")
    }

    func editorResetTextSize() {
        runEditorCommand("unsetFontSize")
    }

    func setNotesEditorTextSize(_ textSize: NotesEditorTextSize) {
        guard notesEditorTextSize != textSize else {
            applyNotesEditorTextSize()
            return
        }

        notesEditorTextSize = textSize

        var config = CiderConfig.load()
        config.notesEditorTextSize = textSize
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)

        applyNotesEditorTextSize()
    }

    func editorAlignLeft() {
        runEditorCommand("setTextAlign", stringArgument: "left")
    }

    func editorAlignCenter() {
        runEditorCommand("setTextAlign", stringArgument: "center")
    }

    func editorAlignRight() {
        runEditorCommand("setTextAlign", stringArgument: "right")
    }

    func editorToggleBulletList() {
        runEditorCommand("toggleBulletList")
    }

    func editorToggleOrderedList() {
        runEditorCommand("toggleOrderedList")
    }

    func editorToggleTaskList() {
        runEditorCommand("toggleTaskList")
    }

    func editorInsertTable() {
        runEditorCommand("insertTable")
    }

    func editorAddRowBefore() {
        runEditorCommand("addRowBefore")
    }

    func editorAddRowAfter() {
        runEditorCommand("addRowAfter")
    }

    func editorDeleteRow() {
        runEditorCommand("deleteRow")
    }

    func editorAddColumnBefore() {
        runEditorCommand("addColumnBefore")
    }

    func editorAddColumnAfter() {
        runEditorCommand("addColumnAfter")
    }

    func editorDeleteColumn() {
        runEditorCommand("deleteColumn")
    }

    func editorMergeCells() {
        runEditorCommand("mergeCells")
    }

    func editorSplitCell() {
        runEditorCommand("splitCell")
    }

    func editorToggleHeaderRow() {
        runEditorCommand("toggleHeaderRow")
    }

    func editorToggleHeaderColumn() {
        runEditorCommand("toggleHeaderColumn")
    }

    func editorDeleteTable() {
        runEditorCommand("deleteTable")
    }

    func editorPromptForLink() {
        guard let rawValue = promptForLinkURL() else { return }
        runEditorCommand("setLink", stringArgument: normalizeLinkURL(rawValue))
    }

    func editorRemoveLink() {
        runEditorCommand("unsetLink")
    }

    func toggleFormattingToolbarPinned() {
        isFormattingToolbarPinned.toggle()
    }

    func setFormattingToolbarPinned(_ pinned: Bool) {
        isFormattingToolbarPinned = pinned
    }

    @discardableResult
    func restoreMostRecentSnapshot() -> Bool {
        guard let choice = recoverySnapshotChoices.first else { return false }
        return restoreSnapshot(choice)
    }

    @discardableResult
    func restoreSnapshot(_ choice: NotesRecoverySnapshotChoice) -> Bool {
        guard var current = selectedNote else {
            return false
        }

        guard let snapshot = NotesStorage.shared.snapshots(for: current).first(where: { $0.id == choice.id }),
              let snapshotContent = NotesStorage.shared.loadSnapshotContent(at: snapshot.url) else {
            return false
        }

        saveWorkItem?.cancel()
        saveWorkItem = nil

        let persistedContent = NotesStorage.shared.markdownForPersistence(snapshotContent)
        current.content = persistedContent
        NotesStorage.shared.save(note: current)

        if let updated = NotesStorage.shared.notes.first(where: { $0.id == current.id }) {
            applyDiskContent(loadPersistedContent(for: updated), from: updated)
        } else {
            editingContent = persistedContent
            charCount = persistedContent.count
            lastSyncedDiskContent = persistedContent
            pendingExternalDiskContent = nil
            ignoredExternalDiskContent = nil
            externalChangeState = nil
            selectedNote = current
            hasPendingSave = false
            pushContentToEditor(persistedContent)
        }

        return true
    }

    private func runEditorCommand(_ command: String, stringArgument: String? = nil) {
        guard editorIsReady, let webView = editorWebView else { return }

        if let stringArgument {
            guard let argumentData = try? JSONSerialization.data(
                withJSONObject: stringArgument, options: .fragmentsAllowed
            ), let argumentJSON = String(data: argumentData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.editorAPI.\(command)(\(argumentJSON));")
            return
        }

        webView.evaluateJavaScript("window.editorAPI.\(command)();")
    }

    private func runFindCommand(_ command: String, stringArgument: String? = nil) {
        guard editorIsReady, let webView = editorWebView else { return }

        let script: String
        if let stringArgument {
            guard let argumentData = try? JSONSerialization.data(
                withJSONObject: stringArgument, options: .fragmentsAllowed
            ), let argumentJSON = String(data: argumentData, encoding: .utf8) else { return }
            script = "window.editorAPI.\(command)(\(argumentJSON));"
        } else {
            script = "window.editorAPI.\(command)();"
        }

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                self?.applyFindResult(result)
            }
        }
    }

    private func applyFindResult(_ result: Any?) {
        guard let payload = result as? [String: Any] else {
            return
        }

        findMatchCount = intValue(payload["count"])
        findMatchIndex = intValue(payload["index"])
    }

    private func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return 0
    }

    private func resetFindResults() {
        findMatchCount = 0
        findMatchIndex = 0
    }

    private func promptForLinkURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "Enter a URL for the selected text."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        field.stringValue = "https://"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizeLinkURL(_ value: String) -> String {
        guard !value.contains("://") else { return value }
        return "https://\(value)"
    }

    // MARK: - Display Options

    func setDisplayMode(_ mode: NoteDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode

        var config = CiderConfig.load()
        config.notesDefaultViewMode = mode
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    func setCardSizeScale(_ scale: Double) {
        let clamped = min(max(scale, 0), 3)
        cardSizeScale = clamped

        var config = CiderConfig.load()
        config.notesCardSizeScale = clamped
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)
    }

    // MARK: - Panel State

    func show() {
        isVisible = true
        // If no note selected (and not viewing an external file) and notes exist, select the most recent
        if selectedNote == nil, activeExternalFile == nil, let first = notes.first {
            selectNote(first)
        }
    }

    func dismiss() {
        flushSave()
        isFindBarVisible = false
        isVisible = false
        NotificationCenter.default.post(name: .dismissNotes, object: nil)
    }

    func toggleCollapsed() {
        NotificationCenter.default.post(name: .toggleNotesCollapse, object: nil)
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        if collapsed {
            isFindBarVisible = false
        }
    }

    func moveToNextDisplay() {
        NotificationCenter.default.post(name: .moveNotesToNextDisplay, object: nil)
    }

    private func clearSelectedNote() {
        selectedNote = nil
        editingContent = ""
        editingTitle = ""
        charCount = 0
        isFindBarVisible = false
        findQuery = ""
        resetFindResults()
        lastSyncedDiskContent = ""
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        hasPendingSave = false

        if editorIsReady, let webView = editorWebView {
            webView.evaluateJavaScript("window.editorAPI.clear()")
        }
    }

    private func reconcileSelectedNote() {
        guard let selected = selectedNote else { return }

        guard let updated = NotesStorage.shared.notes.first(where: { $0.id == selected.id }) else {
            clearSelectedNote()
            return
        }

        if selected.title != updated.title || selected.relativePath != updated.relativePath || selected.modifiedAt != updated.modifiedAt {
            var refreshed = selected
            refreshed.title = updated.title
            refreshed.relativePath = updated.relativePath
            refreshed.modifiedAt = updated.modifiedAt
            selectedNote = refreshed
            editingTitle = refreshed.title
        }
    }

    private func applyNotesEditorTextSize() {
        runEditorCommand("setEditorBaseFontSize", stringArgument: notesEditorTextSize.cssFontSize)
    }
}
