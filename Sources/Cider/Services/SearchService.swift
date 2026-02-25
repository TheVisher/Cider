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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        let dateCards = DateCardStorage.shared.dateCards
        let contacts  = ContactStorage.shared.contacts

        let bookmarkResults  = searchBookmarks(tokens, in: bookmarks)
        let noteResults      = await searchNotes(tokens, in: notes)
        let dateCardResults  = searchDateCards(tokens, in: dateCards)
        let contactResults   = searchContacts(tokens, in: contacts)

        return bookmarkResults + noteResults + dateCardResults + contactResults
    }

    static func searchBookmarks(_ tokens: [String], in bookmarks: [Bookmark]) -> [SearchResult] {
        bookmarks.compactMap { bookmark in
            var fields = [bookmark.title, bookmark.urlString, bookmark.hostDisplay, bookmark.notes] + bookmark.tags
            if let ocr = bookmark.ocrText { fields.append(ocr) }
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let titleMatch = fieldsMatch(tokens, in: [bookmark.title, bookmark.urlString, bookmark.hostDisplay] + bookmark.tags)

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = bookmark.hostDisplay
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(tokens: tokens, from: bookmark.notes)
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
    static func searchNotes(_ tokens: [String], in notes: [Note]) async -> [SearchResult] {
        let directoryURL = NotesStorage.shared.notesDirectoryURL
        return await fetchNoteResults(tokens: tokens, notes: notes, directoryURL: directoryURL)
    }

    static func searchDateCards(_ tokens: [String], in dateCards: [DateCard]) -> [SearchResult] {
        dateCards.compactMap { card in
            let fields = [card.title, card.details, card.location]
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let titleMatch = card.title.localizedStandardContains(tokens.first ?? "")

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = card.startAt.formatted(.dateTime.month().day().year())
                snippet  = nil
            } else {
                subtitle = nil
                let bodyText = card.details.isEmpty ? card.location : card.details
                snippet  = extractSnippet(tokens: tokens, from: bodyText)
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

    static func searchContacts(_ tokens: [String], in contacts: [ContactCard]) -> [SearchResult] {
        contacts.compactMap { contact in
            let fields = [contact.displayName, contact.relationshipLabel, contact.notes]
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let headerMatch = fieldsMatch(tokens, in: [contact.displayName, contact.relationshipLabel])

            let snippet: SearchSnippet?
            let subtitle: String?
            if headerMatch {
                subtitle = contact.relationshipLabel.isEmpty ? nil : contact.relationshipLabel
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(tokens: tokens, from: contact.notes)
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
        tokens: [String],
        notes: [Note],
        directoryURL: URL
    ) async -> [SearchResult] {
        notes.compactMap { note in
            let fileURL = directoryURL.appendingPathComponent(note.relativePath)
            let rawContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let strippedContent = rawContent
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let fields = [note.title, strippedContent]
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let titleMatch = fieldsMatch(tokens, in: [note.title])

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = String(strippedContent.prefix(80))
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(tokens: tokens, from: strippedContent)
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

    // MARK: - Token Matching Helpers

    /// Returns true if every token matches in at least one field.
    nonisolated static func matchesAllTokens(_ tokens: [String], in fields: [String]) -> Bool {
        tokens.allSatisfy { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    /// Returns true if all tokens can be satisfied by the given subset of fields.
    private nonisolated static func fieldsMatch(_ tokens: [String], in fields: [String]) -> Bool {
        matchesAllTokens(tokens, in: fields)
    }

    /// Extract a snippet around the first token match found in the text.
    nonisolated static func extractSnippet(tokens: [String], from text: String, windowSize: Int = 60) -> SearchSnippet? {
        // Find the first token that has a match range in the text
        for token in tokens {
            if let range = text.range(of: token, options: .caseInsensitive) {
                let contextStart = text.index(range.lowerBound, offsetBy: -windowSize, limitedBy: text.startIndex) ?? text.startIndex
                let contextEnd   = text.index(range.upperBound, offsetBy:  windowSize, limitedBy: text.endIndex)   ?? text.endIndex
                let prefix = (contextStart > text.startIndex ? "…" : "") + String(text[contextStart..<range.lowerBound])
                let match  = String(text[range])
                let suffix = String(text[range.upperBound..<contextEnd]) + (contextEnd < text.endIndex ? "…" : "")
                return SearchSnippet(prefix: prefix, match: match, suffix: suffix)
            }
        }
        return nil
    }
}
