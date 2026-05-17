import SwiftUI
import Combine
import WebKit
import AppKit
import os

private let logger = Logger(subsystem: "com.cider.app", category: "NotesViewModel")

struct EditorFormatState: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var highlight = false
    var highlightColor: String? = nil
    var code = false
    var link = false
    var bulletList = false
    var orderedList = false
    var taskList = false
    var blockquote = false
    var codeBlock = false
    var inTable = false
    var heading: Int = 0       // 0=paragraph, 1=H1, 2=H2, 3=H3
    var textAlign: String = "left"
}

struct NotesExternalChangeState: Equatable {
    let modifiedAt: Date
}

enum NotesEditorRenderRefreshPlan {
    static let delays: [TimeInterval] = [0, 0.15, 0.35]
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
    @Published var editingContent: String = ""
    @Published var searchText: String = ""
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
    @Published private(set) var noteEditorMode: NoteEditorMode
    @Published var editorFormatState = EditorFormatState()
    @Published var isMetadataPanelVisible: Bool = false
    @Published private(set) var hasSnapshots: Bool = false

    /// The singleton editor WebView, created on first access via `ensureEditorWebView()`.
    private(set) var editorWebView: WKWebView?
    private var editorCoordinator: TipTapEditorCoordinator?
    private var editorIsReady = false

    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncedDiskContent: String = ""
    /// True while waiting for TipTap's first `contentChanged` after loading a note.
    /// TipTap normalizes markdown on parse; we absorb that round-trip without writing to disk.
    private var isLoadingNote = false
    private var pendingExternalDiskContent: String?
    private var ignoredExternalDiskContent: String?
    var notes: [Note] {
        NotesStorage.shared.notes
    }

    @discardableResult
    func assignNote(_ note: Note, toFolder folderID: UUID?) -> Bool {
        let oldFolderID = note.folderID
        let result = NotesStorage.shared.assignNote(note.id, toFolder: folderID)
        if result {
            let folderName = VaultFolderService.shared.folder(for: folderID ?? UUID())?.name ?? "Unfiled"
            CiderUndoManager.shared.record(.movedToFolder(
                itemType: .note,
                itemID: note.id,
                title: note.title,
                fromFolderID: oldFolderID,
                toFolderID: folderID,
                folderName: folderName
            ))
        }
        return result
    }

    @discardableResult
    func toggleNotePinned(_ note: Note) -> Bool {
        NotesStorage.shared.togglePin(note.id)
    }

    var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        let query = searchText.lowercased()
        // Filter by title only — content search requires disk I/O (loadContent reads from disk)
        // which must not run synchronously on @MainActor in a frequently-rendered computed
        // property. Full-text search across note content is handled by LibraryViewModel
        // (which caches reads) in the library/search tab.
        return notes.filter {
            $0.title.lowercased().contains(query)
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
        self.noteEditorMode = config.noteEditorMode

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
                if self.noteEditorMode != config.noteEditorMode {
                    self.noteEditorMode = config.noteEditorMode
                }
                if self.notesEditorTextSize != config.notesEditorTextSize {
                    self.notesEditorTextSize = config.notesEditorTextSize
                    self.applyNotesEditorTextSize()
                }
            }
            .store(in: &cancellables)

        // Cache snapshot availability so toolbar .disabled() doesn't hit disk on every render
        $selectedNote
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let note {
                    self.hasSnapshots = !NotesStorage.shared.snapshots(for: note).isEmpty
                } else {
                    self.hasSnapshots = false
                }
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
        config.setURLSchemeHandler(CiderVaultSchemeHandler(), forURLScheme: "cider-vault")
        let contentController = config.userContentController
        contentController.add(coordinator, name: "contentChanged")
        contentController.add(coordinator, name: "editorReady")
        contentController.add(coordinator, name: "imageDropped")
        contentController.add(coordinator, name: "slashCommandImage")
        contentController.add(coordinator, name: "slashPopupState")
        contentController.add(coordinator, name: "editorFormatState")
        contentController.add(coordinator, name: "editorError")
        contentController.add(coordinator, name: "editorRequestClose")
        contentController.add(coordinator, name: "linkClicked")

        let webView = TipTapWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.viewModel = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.onFindRequested = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFindShortcut()
            }
        }

        if let resourceURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "TipTapEditor") {
            // Grant read access to the TipTapEditor bundle directory (for JS/CSS).
            // Vault images are served via the cider-vault:// custom URL scheme instead,
            // which avoids the constraint that allowingReadAccessTo must cover both
            // the app bundle and the vault simultaneously.
            let readAccessRoot = resourceURL.deletingLastPathComponent()
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
            isLoadingNote = true
            pushContentToEditor(content)
        }
    }

    /// Push markdown content to the TipTap editor via JS.
    private func pushContentToEditor(_ markdown: String) {
        guard editorIsReady, let webView = editorWebView else {
            logger.warning("pushContentToEditor: editor not ready or webView nil")
            return
        }
        let editorMarkdown: String
        if let note = selectedNote {
            editorMarkdown = NotesStorage.shared.markdownForEditor(markdown, note: note)
        } else {
            editorMarkdown = NotesStorage.shared.markdownForEditor(markdown)
        }
        // Use JSON encoding for safe string transport — handles all special
        // characters (newlines, quotes, backslashes, unicode) correctly.
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: editorMarkdown, options: .fragmentsAllowed
        ), let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("pushContentToEditor: JSON encoding failed")
            return
        }
        webView.evaluateJavaScript("window.editorAPI.setContent(\(jsonString))") { _, error in
            if let error {
                logger.error("pushContentToEditor JS failed: \(error.localizedDescription)")
            }
        }
    }

    func pushCurrentContentToEditorIfReady() {
        guard let selectedNote else { return }
        pushContentToEditor(selectedNote.content)
    }

    /// Focus the TipTap editor.
    /// In a non-activating NSPanel, JavaScript focus alone isn't enough —
    /// the WKWebView must also become the window's first responder.
    func focusEditor() {
        guard editorIsReady, let webView = editorWebView else { return }
        // Make the WKWebView the first responder at the AppKit level.
        // Delay is required for non-activating panels (see CLAUDE.md).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard let window = webView.window else { return }
            window.makeKey()
            window.makeFirstResponder(webView)
            _ = try? await webView.evaluateJavaScript("window.editorAPI.focus()")
        }
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
        guard noteEditorMode == .rich else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        handleImageDrop(data: data, filename: url.lastPathComponent)
    }

    // MARK: - Note Selection

    func selectNote(_ note: Note) {
        // Save current note before switching
        flushSave()
        isLoadingNote = false

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
        isLoadingNote = true

        pushContentToEditor(loaded.content)
        scheduleEditorRenderRefresh(for: loaded.id)
    }

    private func scheduleEditorRenderRefresh(for noteID: UUID) {
        for delay in NotesEditorRenderRefreshPlan.delays {
            Task { @MainActor [weak self] in
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard let self, self.selectedNote?.id == noteID else { return }
                self.pushCurrentContentToEditorIfReady()
                self.forceEditorDisplayRefresh()
            }
        }
    }

    private func forceEditorDisplayRefresh() {
        guard let webView = editorWebView else { return }
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()
        webView.setNeedsDisplay(webView.bounds)
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
            // Delay + AppKit first responder needed for non-activating panel
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard let window = webView.window else { return }
                window.makeKey()
                window.makeFirstResponder(webView)
                _ = try? await webView.evaluateJavaScript("window.editorAPI.focus()")
            }
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
        let persistedContent: String
        if let note = selectedNote {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent, note: note)
        } else {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent)
        }
        applyEditedContent(persistedContent)
    }

    func sourceContentChanged(_ newContent: String) {
        let persistedContent: String
        if let note = selectedNote {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent, note: note)
        } else {
            persistedContent = NotesStorage.shared.markdownForPersistence(newContent)
        }
        applyEditedContent(persistedContent)
    }

    private func applyEditedContent(_ persistedContent: String) {
        editingContent = persistedContent
        charCount = persistedContent.count
        hasPendingSave = true

        // Absorb the TipTap normalization round-trip on initial note load.
        // TipTap re-serializes on parse; we update the reference to the normalized
        // content without writing to avoid overwriting disk content (e.g. centered
        // images losing their <p style="text-align: center"> wrapper).
        if isLoadingNote {
            isLoadingNote = false
            lastSyncedDiskContent = persistedContent
            hasPendingSave = false
            return
        }

        guard var note = selectedNote else { return }
        note.content = persistedContent

        // Don't save if content hasn't changed from what we loaded from disk
        guard persistedContent != lastSyncedDiskContent else {
            hasPendingSave = false
            return
        }

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
                SyncService.shared.pushAfterLocalChange()
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

        guard var note = selectedNote else { return }

        // Safety: don't save if the editor never confirmed loading the note.
        // isLoadingNote stays true until the first contentChanged round-trip
        // completes. If JS crashes, this prevents overwriting disk content.
        guard !isLoadingNote else {
            hasPendingSave = false
            return
        }

        // Save the latest known content immediately.
        note.content = editingContent
        lastSyncedDiskContent = editingContent
        pendingExternalDiskContent = nil
        ignoredExternalDiskContent = nil
        externalChangeState = nil
        NotesStorage.shared.save(note: note)
        SyncService.shared.pushAfterLocalChange()
        hasPendingSave = false

        // Then ask the editor for current content to catch any final keystrokes
        // that haven't crossed the JS->Swift bridge yet.
        syncContentFromEditor(noteID: note.id)
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
                pendingExternalDiskContent = nil
                ignoredExternalDiskContent = nil
                externalChangeState = nil
                guard persistedMarkdown != self.lastSyncedDiskContent else {
                    hasPendingSave = false
                    return
                }
                current.content = persistedMarkdown
                lastSyncedDiskContent = persistedMarkdown
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

        isLoadingNote = true
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
        guard noteEditorMode == .rich else { return }
        runEditorCommand("undo")
    }

    func editorRedo() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("redo")
    }

    func editorToggleBold() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBold")
    }

    func editorToggleItalic() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleItalic")
    }

    func editorToggleUnderline() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleUnderline")
    }

    func editorSetTextSizeSmall() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "12px")
    }

    func editorSetTextSizeNormal() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "14px")
    }

    func editorSetTextSizeLarge() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "18px")
    }

    func editorSetTextSizeExtraLarge() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setFontSize", stringArgument: "24px")
    }

    func editorResetTextSize() {
        guard noteEditorMode == .rich else { return }
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

    func setNoteEditorMode(_ mode: NoteEditorMode) {
        guard noteEditorMode != mode else { return }

        if mode == .source, let noteID = selectedNote?.id {
            syncContentFromEditor(noteID: noteID)
        }

        noteEditorMode = mode

        var config = CiderConfig.load()
        config.noteEditorMode = mode
        config.save()
        NotificationCenter.default.post(name: .ciderConfigChanged, object: nil)

        if mode == .rich {
            isLoadingNote = true
            pushContentToEditor(editingContent)
            focusEditor()
        }
    }

    func editorAlignLeft() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "left")
    }

    func editorAlignCenter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "center")
    }

    func editorAlignRight() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setTextAlign", stringArgument: "right")
    }

    func editorToggleBulletList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBulletList")
    }

    func editorToggleOrderedList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleOrderedList")
    }

    func editorToggleTaskList() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleTaskList")
    }

    func editorInsertTable(rows: Int = 3, cols: Int = 3) {
        guard noteEditorMode == .rich else { return }
        guard editorIsReady, let webView = editorWebView else { return }
        webView.evaluateJavaScript("window.editorAPI.insertTable(\(rows), \(cols));")
    }

    func editorAddRowBefore() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addRowBefore")
    }

    func editorAddRowAfter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addRowAfter")
    }

    func editorDeleteRow() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteRow")
    }

    func editorAddColumnBefore() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addColumnBefore")
    }

    func editorAddColumnAfter() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("addColumnAfter")
    }

    func editorDeleteColumn() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteColumn")
    }

    func editorMergeCells() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("mergeCells")
    }

    func editorSplitCell() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("splitCell")
    }

    func editorToggleHeaderRow() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleHeaderRow")
    }

    func editorToggleHeaderColumn() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleHeaderColumn")
    }

    func editorDeleteTable() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("deleteTable")
    }

    func editorPromptForLink() {
        guard noteEditorMode == .rich else { return }
        guard let rawValue = promptForLinkURL() else { return }
        runEditorCommand("setLink", stringArgument: normalizeLinkURL(rawValue))
    }

    func editorRemoveLink() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("unsetLink")
    }

    func editorToggleStrike() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleStrike")
    }

    func editorToggleBlockquote() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleBlockquote")
    }

    func editorInsertHorizontalRule() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setHorizontalRule")
    }

    func editorToggleHighlight(color: String? = nil) {
        guard noteEditorMode == .rich else { return }
        if let color {
            runEditorCommand("toggleHighlight", stringArgument: color)
        } else {
            runEditorCommand("toggleHighlight")
        }
    }

    func editorToggleCode() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleCode")
    }

    func editorIndent() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("indent")
    }

    func editorOutdent() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("outdent")
    }

    func editorClearFormatting() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("clearFormatting")
    }

    func editorSetHeading(_ level: Int) {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setHeading", intArgument: level)
    }

    func editorSetParagraph() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("setParagraph")
    }

    func editorToggleCodeBlock() {
        guard noteEditorMode == .rich else { return }
        runEditorCommand("toggleCodeBlock")
    }

    func updateEditorFormatState(_ payload: [String: Any]) {
        var state = EditorFormatState()
        state.bold = payload["bold"] as? Bool ?? false
        state.italic = payload["italic"] as? Bool ?? false
        state.underline = payload["underline"] as? Bool ?? false
        state.strike = payload["strike"] as? Bool ?? false
        state.highlight = payload["highlight"] as? Bool ?? false
        state.highlightColor = payload["highlightColor"] as? String
        state.code = payload["code"] as? Bool ?? false
        state.link = payload["link"] as? Bool ?? false
        state.bulletList = payload["bulletList"] as? Bool ?? false
        state.orderedList = payload["orderedList"] as? Bool ?? false
        state.taskList = payload["taskList"] as? Bool ?? false
        state.blockquote = payload["blockquote"] as? Bool ?? false
        state.codeBlock = payload["codeBlock"] as? Bool ?? false
        state.inTable = payload["inTable"] as? Bool ?? false
        state.heading = payload["heading"] as? Int ?? 0
        state.textAlign = payload["textAlign"] as? String ?? "left"
        editorFormatState = state
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
        NotesStorage.shared.save(note: current, createSnapshot: false)

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
            isLoadingNote = true
            pushContentToEditor(persistedContent)
        }

        return true
    }

    private func runEditorCommand(_ command: String, stringArgument: String? = nil, intArgument: Int? = nil) {
        guard editorIsReady, let webView = editorWebView else { return }

        if let stringArgument {
            guard let argumentData = try? JSONSerialization.data(
                withJSONObject: stringArgument, options: .fragmentsAllowed
            ), let argumentJSON = String(data: argumentData, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.editorAPI.\(command)(\(argumentJSON));")
            return
        }

        if let intArgument {
            webView.evaluateJavaScript("window.editorAPI.\(command)(\(intArgument));")
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
        alert.informativeText = "Enter a URL to insert or apply to the selected text."
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

    // MARK: - Metadata Sidebar Actions

    func updateNoteTitle(_ newTitle: String) {
        guard let note = selectedNote, !newTitle.isEmpty else { return }
        NotesStorage.shared.rename(note: note, to: newTitle)
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            selectedNote = updated
            editingTitle = updated.title
        }
    }

    func updateNoteFolder(_ folderID: UUID?) {
        guard let note = selectedNote else { return }
        guard NotesStorage.shared.assignNote(note.id, toFolder: folderID) else { return }
        if var updated = selectedNote {
            updated.folderID = folderID
            selectedNote = updated
        }
    }

    func toggleNoteLabel(_ labelID: UUID) {
        guard let note = selectedNote else { return }
        if note.labelIDs.contains(labelID) {
            NotesStorage.shared.removeLabel(note.id, labelID: labelID)
        } else {
            NotesStorage.shared.assignLabel(note.id, labelID: labelID)
        }
        if let updated = NotesStorage.shared.notes.first(where: { $0.id == note.id }) {
            var refreshed = selectedNote ?? updated
            refreshed.labelIDs = updated.labelIDs
            selectedNote = refreshed
        }
    }

    func toggleNotePin() {
        guard let note = selectedNote else { return }
        NotesStorage.shared.togglePin(note.id)
        if var updated = selectedNote {
            updated.isPinned.toggle()
            selectedNote = updated
        }
    }

    var extractedLinks: [URL] {
        let content = editingContent
        guard !content.isEmpty else { return [] }
        var urls: [URL] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(content.startIndex..., in: content)
        detector?.enumerateMatches(in: content, range: range) { result, _, _ in
            guard let url = result?.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return }
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
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

    func clearSelectedNote() {
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
