import SwiftUI
import Combine

@MainActor
final class NotesViewModel: ObservableObject {
    @Published var selectedNote: Note?
    @Published var editingContent: String = ""
    @Published var searchText: String = ""
    @Published var isMarkdownMode: Bool = false
    @Published var isPreviewMode: Bool = false
    @Published var isPinned: Bool = true
    @Published var isVisible: Bool = false
    @Published var editingTitle: String = ""

    private var saveWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

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
        // Observe storage changes
        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
    }

    // MARK: - CRUD

    func createNewNote() {
        flushSave()
        let note = NotesStorage.shared.createNew()
        selectedNote = note
        editingContent = ""
        editingTitle = note.title
    }

    func deleteCurrentNote() {
        guard let note = selectedNote else { return }
        NotesStorage.shared.delete(note: note)
        selectedNote = nil
        editingContent = ""
        editingTitle = ""
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

    /// Immediately save any pending content.
    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard var note = selectedNote else { return }
        note.content = editingContent
        NotesStorage.shared.save(note: note)
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

    func togglePin() {
        isPinned.toggle()
    }

    // MARK: - Markdown Toolbar Actions

    func insertBold() {
        editingContent += "**bold**"
        syncContent()
    }

    func insertItalic() {
        editingContent += "*italic*"
        syncContent()
    }

    func insertHeading() {
        editingContent += "\n## Heading\n"
        syncContent()
    }

    func insertCode() {
        editingContent += "\n```\ncode\n```\n"
        syncContent()
    }

    func insertList() {
        editingContent += "\n- Item\n"
        syncContent()
    }

    func insertLink() {
        editingContent += "[text](url)"
        syncContent()
    }

    private func syncContent() {
        contentChanged(editingContent)
    }
}
