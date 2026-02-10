import SwiftUI
import Combine
import WebKit
import AppKit

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var selectedNote: Note?
    @Published var editingContent: String = ""
    @Published var searchText: String = ""
    @Published var isCollapsed: Bool = false
    @Published var isVisible: Bool = false
    @Published var editingTitle: String = ""
    @Published var charCount: Int = 0
    @Published var isFormattingToolbarPinned: Bool {
        didSet {
            UserDefaults.standard.set(
                isFormattingToolbarPinned,
                forKey: Self.formattingToolbarPinnedStorageKey
            )
        }
    }

    /// Reference to the WKWebView for Swift → JS calls
    var editorWebView: WKWebView?
    private var editorIsReady = false

    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private static let formattingToolbarPinnedStorageKey = "cider.notes.formattingToolbarPinned"

    var notes: [Note] {
        NotesStorage.shared.notes
    }

    var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return notes }
        let query = searchText.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(query) ||
            NotesStorage.shared.loadContent(for: $0).lowercased().contains(query)
        }
    }

    init() {
        self.isFormattingToolbarPinned = UserDefaults.standard.bool(
            forKey: Self.formattingToolbarPinnedStorageKey
        )

        // Observe storage changes
        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileSelectedNote()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Editor Bridge

    /// Called when the TipTap editor signals it is ready.
    func editorDidBecomeReady() {
        editorIsReady = true
        // If a note is already selected, push its content to the editor
        if let note = selectedNote {
            let content = NotesStorage.shared.loadContent(for: note)
            editingContent = content
            pushContentToEditor(content)
        }
    }

    /// Push markdown content to the TipTap editor via JS.
    private func pushContentToEditor(_ markdown: String) {
        guard editorIsReady, let webView = editorWebView else { return }
        // Use JSON encoding for safe string transport — handles all special
        // characters (newlines, quotes, backslashes, unicode) correctly.
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: markdown, options: .fragmentsAllowed
        ), let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.editorAPI.setContent(\(jsonString))")
    }

    /// Focus the TipTap editor.
    func focusEditor() {
        guard editorIsReady, let webView = editorWebView else { return }
        webView.evaluateJavaScript("window.editorAPI.focus()")
    }

    // MARK: - Image Handling

    func handleImageDrop(data: Data, filename: String) {
        guard let note = selectedNote else { return }
        let imageURL = NotesStorage.shared.saveImage(data: data, filename: filename, for: note)
        guard let webView = editorWebView else { return }
        let src = imageURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? imageURL.path
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

        var loaded = note
        loaded.content = NotesStorage.shared.loadContent(for: note)
        selectedNote = loaded
        editingContent = loaded.content
        editingTitle = loaded.title
        charCount = loaded.content.count

        pushContentToEditor(loaded.content)
    }

    // MARK: - CRUD

    func createNewNote() {
        flushSave()
        let note = NotesStorage.shared.createNew()
        selectedNote = note
        editingContent = ""
        editingTitle = note.title
        charCount = 0

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

        for note in notes {
            NotesStorage.shared.delete(note: note)
            NotesPanelPositionStore.shared.removeFrame(for: note.id)
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
        editingContent = newContent
        charCount = newContent.count
        guard var note = selectedNote else { return }
        note.content = newContent

        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, var current = self.selectedNote else { return }
                current.content = self.editingContent
                NotesStorage.shared.save(note: current)
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

        // Save the latest known content immediately.
        note.content = editingContent
        NotesStorage.shared.save(note: note)

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

                editingContent = markdown
                charCount = markdown.count
                current.content = markdown
                NotesStorage.shared.save(note: current)
            }
        }
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

    // MARK: - Panel State

    func show() {
        isVisible = true
        // If no note selected and notes exist, select the most recent
        if selectedNote == nil, let first = notes.first {
            selectNote(first)
        }
    }

    func dismiss() {
        flushSave()
        isVisible = false
        NotificationCenter.default.post(name: .dismissNotes, object: nil)
    }

    func toggleCollapsed() {
        NotificationCenter.default.post(name: .toggleNotesCollapse, object: nil)
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }

    func moveToNextDisplay() {
        NotificationCenter.default.post(name: .moveNotesToNextDisplay, object: nil)
    }

    private func clearSelectedNote() {
        selectedNote = nil
        editingContent = ""
        editingTitle = ""
        charCount = 0

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

        if selected.title != updated.title || selected.relativePath != updated.relativePath {
            var refreshed = selected
            refreshed.title = updated.title
            refreshed.relativePath = updated.relativePath
            refreshed.modifiedAt = updated.modifiedAt
            selectedNote = refreshed
            editingTitle = refreshed.title
        }
    }
}
