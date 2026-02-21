import Foundation

enum SearchResultType {
    case bookmark
    case note
    case dateCard
    case contact
}

struct SearchSnippet {
    let prefix: String   // text before match (leading "…" if truncated)
    let match: String    // query-matched portion, original case
    let suffix: String   // text after match (trailing "…" if truncated)
}

struct SearchResult: Identifiable {
    let id: UUID
    let type: SearchResultType
    let title: String
    let subtitle: String?
    let snippet: SearchSnippet?
    let date: Date

    var bookmark: Bookmark?
    var note: Note?
    var dateCard: DateCard?
    var contact: ContactCard?
}

@MainActor
enum SearchService {
    static func search(query: String, bookmarks: [Bookmark], notes: [Note]) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        let dateCards = DateCardStorage.shared.dateCards
        let contacts  = ContactStorage.shared.contacts

        let bookmarkResults  = searchBookmarks(trimmed, in: bookmarks)
        let noteResults      = await searchNotes(trimmed, in: notes)
        let dateCardResults  = searchDateCards(trimmed, in: dateCards)
        let contactResults   = searchContacts(trimmed, in: contacts)

        return bookmarkResults + noteResults + dateCardResults + contactResults
    }

    static func searchBookmarks(_ query: String, in bookmarks: [Bookmark]) -> [SearchResult] {
        bookmarks.compactMap { bookmark in
            let titleMatch  = bookmark.title.lowercased().contains(query)
            let urlMatch    = bookmark.urlString.lowercased().contains(query)
            let hostMatch   = bookmark.hostDisplay.lowercased().contains(query)
            let tagMatch    = bookmark.tags.contains { $0.lowercased().contains(query) }
            let notesMatch  = bookmark.notes.lowercased().contains(query)

            guard titleMatch || urlMatch || hostMatch || tagMatch || notesMatch else {
                return nil
            }

            let snippet: SearchSnippet?
            let subtitle: String?
            if !notesMatch || titleMatch || urlMatch || hostMatch || tagMatch {
                subtitle = bookmark.hostDisplay
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(query: query, from: bookmark.notes)
            }

            return SearchResult(
                id: bookmark.id,
                type: .bookmark,
                title: bookmark.title,
                subtitle: subtitle,
                snippet: snippet,
                date: bookmark.updatedAt,
                bookmark: bookmark
            )
        }
    }

    // Note content is loaded off the main actor to avoid blocking the UI.
    static func searchNotes(_ query: String, in notes: [Note]) async -> [SearchResult] {
        let directoryURL = NotesStorage.shared.notesDirectoryURL
        return await fetchNoteResults(query: query, notes: notes, directoryURL: directoryURL)
    }

    static func searchDateCards(_ query: String, in dateCards: [DateCard]) -> [SearchResult] {
        dateCards.compactMap { card in
            let titleMatch    = card.title.lowercased().contains(query)
            let detailsMatch  = card.details.lowercased().contains(query)
            let locationMatch = card.location.lowercased().contains(query)

            guard titleMatch || detailsMatch || locationMatch else { return nil }

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = card.startAt.formatted(.dateTime.month().day().year())
                snippet  = nil
            } else {
                subtitle = nil
                let bodyText = card.details.isEmpty ? card.location : card.details
                snippet  = extractSnippet(query: query, from: bodyText)
            }

            return SearchResult(
                id: card.id,
                type: .dateCard,
                title: card.title,
                subtitle: subtitle,
                snippet: snippet,
                date: card.updatedAt,
                dateCard: card
            )
        }
    }

    static func searchContacts(_ query: String, in contacts: [ContactCard]) -> [SearchResult] {
        contacts.compactMap { contact in
            let nameMatch  = contact.displayName.lowercased().contains(query)
            let labelMatch = contact.relationshipLabel.lowercased().contains(query)
            let notesMatch = contact.notes.lowercased().contains(query)

            guard nameMatch || labelMatch || notesMatch else { return nil }

            let snippet: SearchSnippet?
            let subtitle: String?
            if nameMatch || labelMatch {
                subtitle = contact.relationshipLabel.isEmpty ? nil : contact.relationshipLabel
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(query: query, from: contact.notes)
            }

            return SearchResult(
                id: contact.id,
                type: .contact,
                title: contact.displayName,
                subtitle: subtitle,
                snippet: snippet,
                date: contact.updatedAt,
                contact: contact
            )
        }
    }

    // Runs off the main actor — safe to do synchronous disk reads here.
    private nonisolated static func fetchNoteResults(
        query: String,
        notes: [Note],
        directoryURL: URL
    ) async -> [SearchResult] {
        notes.compactMap { note in
            let titleMatch = note.title.lowercased().contains(query)
            let fileURL = directoryURL.appendingPathComponent(note.relativePath)
            let rawContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let strippedContent = rawContent
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let contentMatch = strippedContent.lowercased().contains(query)

            guard titleMatch || contentMatch else { return nil }

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = String(strippedContent.prefix(80))
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(query: query, from: strippedContent)
            }

            return SearchResult(
                id: note.id,
                type: .note,
                title: note.title,
                subtitle: subtitle,
                snippet: snippet,
                date: note.modifiedAt,
                note: note
            )
        }
    }

    nonisolated static func extractSnippet(query: String, from text: String, windowSize: Int = 60) -> SearchSnippet? {
        guard let range = text.range(of: query, options: .caseInsensitive) else { return nil }
        let contextStart = text.index(range.lowerBound, offsetBy: -windowSize, limitedBy: text.startIndex) ?? text.startIndex
        let contextEnd   = text.index(range.upperBound, offsetBy:  windowSize, limitedBy: text.endIndex)   ?? text.endIndex
        let prefix = (contextStart > text.startIndex ? "…" : "") + String(text[contextStart..<range.lowerBound])
        let match  = String(text[range])
        let suffix = String(text[range.upperBound..<contextEnd]) + (contextEnd < text.endIndex ? "…" : "")
        return SearchSnippet(prefix: prefix, match: match, suffix: suffix)
    }
}
