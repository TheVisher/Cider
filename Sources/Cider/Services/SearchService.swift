import Foundation

enum SearchResultType {
    case bookmark
    case note
}

struct SearchResult: Identifiable {
    let id: UUID
    let type: SearchResultType
    let title: String
    let subtitle: String
    let date: Date

    var bookmark: Bookmark?
    var note: Note?
}

@MainActor
enum SearchService {
    static func search(query: String, bookmarks: [Bookmark], notes: [Note]) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        let bookmarkResults = searchBookmarks(trimmed, in: bookmarks)
        let noteResults = searchNotes(trimmed, in: notes)

        return bookmarkResults + noteResults
    }

    static func searchBookmarks(_ query: String, in bookmarks: [Bookmark]) -> [SearchResult] {
        bookmarks.compactMap { bookmark in
            let titleMatch = bookmark.title.lowercased().contains(query)
            let urlMatch = bookmark.urlString.lowercased().contains(query)
            let hostMatch = bookmark.hostDisplay.lowercased().contains(query)
            let tagMatch = bookmark.tags.contains { $0.lowercased().contains(query) }
            let notesMatch = bookmark.notes.lowercased().contains(query)

            guard titleMatch || urlMatch || hostMatch || tagMatch || notesMatch else {
                return nil
            }

            return SearchResult(
                id: bookmark.id,
                type: .bookmark,
                title: bookmark.title,
                subtitle: bookmark.hostDisplay,
                date: bookmark.updatedAt,
                bookmark: bookmark
            )
        }
    }

    static func searchNotes(_ query: String, in notes: [Note]) -> [SearchResult] {
        notes.compactMap { note in
            let titleMatch = note.title.lowercased().contains(query)
            let strippedContent = noteStrippedContent(for: note)
            let contentMatch = strippedContent.lowercased().contains(query)

            guard titleMatch || contentMatch else { return nil }

            return SearchResult(
                id: note.id,
                type: .note,
                title: note.title,
                subtitle: String(strippedContent.prefix(120)),
                date: note.modifiedAt,
                note: note
            )
        }
    }

    private static func noteStrippedContent(for note: Note) -> String {
        let content = NotesStorage.shared.loadContent(for: note)
        return content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
