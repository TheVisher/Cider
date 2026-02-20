import Foundation
import Combine

/// Maintains an in-memory index of note content to enable high-performance
/// full-text search without hitting the disk on every keystroke.
@MainActor
final class SearchIndexService: ObservableObject {
    static let shared = SearchIndexService()

    /// Map of Note ID -> Plain text content (stripped of markdown)
    private var noteContentIndex: [UUID: String] = [:]
    
    /// Map of Note ID -> Cached preview text
    private var notePreviewCache: [UUID: String] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let indexQueue = DispatchQueue(label: "com.cider.searchIndex", qos: .utility)
    
    private init() {
        // Observe notes for changes
        NotesStorage.shared.$notes
            .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
            .sink { [weak self] notes in
                self?.rebuildIndex(from: notes)
            }
            .store(in: &cancellables)
    }
    
    /// Warm up the index. Call this on app launch.
    func warmUp() {
        rebuildIndex(from: NotesStorage.shared.notes)
    }
    
    /// Returns matching notes without reading from disk.
    func searchNotes(_ query: String, in notes: [Note]) -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return [] }
        
        return notes.compactMap { note in
            let titleMatch = note.title.lowercased().contains(trimmedQuery)
            
            // Check in-memory index for content match
            let contentText = noteContentIndex[note.id] ?? ""
            let contentMatch = contentText.contains(trimmedQuery)
            
            guard titleMatch || contentMatch else { return nil }
            
            let preview = notePreviewCache[note.id] ?? ""
            
            return SearchResult(
                id: note.id,
                type: .note,
                title: note.title,
                subtitle: preview,
                date: note.modifiedAt,
                note: note
            )
        }
    }
    
    private func rebuildIndex(from notes: [Note]) {
        // Snapshot the notes to pass to the background queue
        let notesSnapshot = notes
        
        indexQueue.async { [weak self] in
            var newIndex: [UUID: String] = [:]
            var newPreviews: [UUID: String] = [:]
            
            for note in notesSnapshot {
                // Determine path for this note
                let config = CiderConfig.load()
                let expanded = NSString(string: config.notesDirectory).expandingTildeInPath
                let fileURL = URL(fileURLWithPath: expanded).appendingPathComponent(note.relativePath)
                
                // Read content - this is slow, so we do it in background
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                
                // Strip markdown/HTML for searchability
                let stripped = content
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"[#*_~`>]+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .lowercased()
                
                newIndex[note.id] = stripped
                newPreviews[note.id] = String(stripped.prefix(120))
            }
            
            // Update the main actor state
            Task { @MainActor [weak self] in
                self?.noteContentIndex = newIndex
                self?.notePreviewCache = newPreviews
            }
        }
    }
}
