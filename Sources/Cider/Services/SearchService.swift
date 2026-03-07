import Foundation

enum SearchResultType {
    case bookmark
    case note
    case dateCard
    case contact
    case todo
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
    var todoCard: TodoCard?
}

// MARK: - Search Scope

struct SearchScope: Equatable {
    var entityTypes: Set<SearchResultType>?  // nil = all types
    var folderIDs: Set<UUID> = []            // empty = no folder filter (unless showAllFolders)
    var folderNames: [String] = []           // display names for matched folders
    var showAllFolders: Bool = false         // true when `@folder:` typed with no name
    var labelID: UUID?
    var labelName: String?                   // raw name from query, for display
    var cleanQuery: String                   // query with scope modifiers removed

    /// Human-readable description of active scopes.
    var activeScopeDescriptions: [String] {
        var descs: [String] = []
        if let types = entityTypes {
            let names = types.map { type -> String in
                switch type {
                case .bookmark:  return "Bookmarks"
                case .note:      return "Notes"
                case .dateCard:  return "Events"
                case .contact:   return "Contacts"
                case .todo:      return "Todos"
                }
            }.sorted()
            descs.append(contentsOf: names)
        }
        if showAllFolders {
            descs.append("All Folders")
        } else {
            for name in folderNames { descs.append("Folder: \(name)") }
        }
        if let name = labelName { descs.append("Tag: \(name)") }
        return descs
    }

    var hasActiveScopes: Bool {
        entityTypes != nil || !folderIDs.isEmpty || showAllFolders || labelID != nil
    }

    var hasFolderScope: Bool {
        !folderIDs.isEmpty || showAllFolders
    }
}

@MainActor
enum SearchService {

    // MARK: - Scope Parsing

    /// Parse `@scope` modifiers from a raw query string.
    /// Recognized: `@bookmarks`, `@notes`, `@events`/`@datecards`, `@contacts`,
    ///             `@folder:Name With Spaces`, `@tag:Name With Spaces`
    /// Entity type scopes support prefix matching: `@b` → bookmarks, `@no` → notes.
    /// Folder/tag names support spaces — all tokens after `@folder:` until the next `@`
    /// modifier are consumed as part of the name.
    static func parseScope(from rawQuery: String) -> SearchScope {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchScope(cleanQuery: "")
        }

        var entityTypes: Set<SearchResultType>? = nil
        var folderIDs: Set<UUID> = []
        var folderNames: [String] = []
        var showAllFolders = false
        var labelID: UUID? = nil
        var labelName: String? = nil
        var remainingParts: [String] = []

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        let entityKeywords: [(names: [String], type: SearchResultType)] = [
            (["bookmarks", "bookmark"], .bookmark),
            (["notes", "note"], .note),
            (["events", "event", "datecards", "datecard"], .dateCard),
            (["contacts", "contact"], .contact),
            (["todos", "todo", "tasks", "task"], .todo),
        ]

        var i = 0
        while i < parts.count {
            let part = parts[i]

            guard part.hasPrefix("@") else {
                remainingParts.append(part)
                i += 1
                continue
            }

            let modifier = String(part.dropFirst()).lowercased()

            // Folder scope: @folder:Name or @f:Name (prefix match on "folder")
            // @folder: with no name → show all folders
            if let colonIdx = modifier.firstIndex(of: ":"),
               "folder".hasPrefix(String(modifier[modifier.startIndex..<colonIdx])),
               modifier[modifier.startIndex..<colonIdx].count >= 1 {
                let afterColon = String(modifier[modifier.index(after: colonIdx)...])
                var nameParts: [String] = []
                if !afterColon.isEmpty { nameParts.append(afterColon) }
                i += 1
                while i < parts.count, !parts[i].hasPrefix("@") {
                    nameParts.append(parts[i])
                    i += 1
                }
                let name = nameParts.joined(separator: " ")
                if name.isEmpty {
                    showAllFolders = true
                    continue
                }
                // Look up folder: exact match first, then prefix match
                if let folder = BookmarksStorage.shared.folders.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }) {
                    folderIDs.insert(folder.id)
                    folderNames.append(folder.name)
                } else if let folder = BookmarksStorage.shared.folders.first(where: {
                    $0.name.lowercased().hasPrefix(name.lowercased())
                }) {
                    folderIDs.insert(folder.id)
                    folderNames.append(folder.name)
                } else {
                    folderNames.append(name)  // Unresolved name, show in pills
                }
                continue
            }

            // Tag scope: @tag:Name or @t:Name (prefix match on "tag")
            if let colonIdx = modifier.firstIndex(of: ":"),
               "tag".hasPrefix(String(modifier[modifier.startIndex..<colonIdx])),
               modifier[modifier.startIndex..<colonIdx].count >= 1 {
                let afterColon = String(modifier[modifier.index(after: colonIdx)...])
                var nameParts: [String] = []
                if !afterColon.isEmpty { nameParts.append(afterColon) }
                i += 1
                while i < parts.count, !parts[i].hasPrefix("@") {
                    nameParts.append(parts[i])
                    i += 1
                }
                let name = nameParts.joined(separator: " ")
                guard !name.isEmpty else { continue }
                labelName = name
                if let label = CardLabelStorage.shared.labels.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }) {
                    labelID = label.id
                } else if let label = CardLabelStorage.shared.labels.first(where: {
                    $0.name.lowercased().hasPrefix(name.lowercased())
                }) {
                    labelID = label.id
                    labelName = label.name
                }
                continue
            }

            // Entity type scopes with prefix matching
            var matched = false
            for keyword in entityKeywords {
                if keyword.names.contains(where: { $0.hasPrefix(modifier) }) && !modifier.isEmpty {
                    if entityTypes == nil { entityTypes = [] }
                    entityTypes?.insert(keyword.type)
                    matched = true
                    break
                }
            }

            if !matched {
                remainingParts.append(part)
            }

            i += 1
        }

        return SearchScope(
            entityTypes: entityTypes,
            folderIDs: folderIDs,
            folderNames: folderNames,
            showAllFolders: showAllFolders,
            labelID: labelID,
            labelName: labelName,
            cleanQuery: remainingParts.joined(separator: " ")
        )
    }

    // MARK: - Search

    static func search(query: String, bookmarks: [Bookmark], notes: [Note]) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scope = parseScope(from: trimmed)

        let dateCards = DateCardStorage.shared.dateCards
        let contacts  = ContactStorage.shared.contacts

        // If clean query is empty but we have scopes, show all items matching scope
        let tokens: [String]
        if scope.cleanQuery.isEmpty {
            tokens = []
        } else {
            tokens = scope.cleanQuery.split(separator: " ").map(String.init)
        }

        var results: [SearchResult] = []

        let shouldSearchType: (SearchResultType) -> Bool = { type in
            guard let allowed = scope.entityTypes else { return true }
            return allowed.contains(type)
        }

        if shouldSearchType(.bookmark) {
            let filtered = applyFolderAndTagScope(bookmarks: bookmarks, scope: scope)
            if tokens.isEmpty {
                results += filtered.map { bookmark in
                    SearchResult(
                        id: bookmark.id, type: .bookmark, title: bookmark.title,
                        subtitle: bookmark.hostDisplay, snippet: nil,
                        date: bookmark.updatedAt, bookmark: bookmark
                    )
                }
            } else {
                results += searchBookmarks(tokens, in: filtered)
            }
        }

        if shouldSearchType(.note) {
            let filtered = applyFolderAndTagScope(notes: notes, scope: scope)
            if tokens.isEmpty {
                results += filtered.map { note in
                    SearchResult(
                        id: note.id, type: .note, title: note.title,
                        subtitle: nil, snippet: nil,
                        date: note.modifiedAt, note: note
                    )
                }
            } else {
                results += await searchNotes(tokens, in: filtered)
            }
        }

        if shouldSearchType(.dateCard) {
            let filtered = applyTagScope(dateCards: dateCards, scope: scope)
            if tokens.isEmpty {
                results += filtered.map { card in
                    SearchResult(
                        id: card.id, type: .dateCard, title: card.title,
                        subtitle: card.startAt.formatted(.dateTime.month().day().year()),
                        snippet: nil, date: card.updatedAt, dateCard: card
                    )
                }
            } else {
                results += searchDateCards(tokens, in: filtered)
            }
        }

        if shouldSearchType(.contact) {
            let filtered = applyTagScope(contacts: contacts, scope: scope)
            if tokens.isEmpty {
                results += filtered.map { contact in
                    SearchResult(
                        id: contact.id, type: .contact, title: contact.displayName,
                        subtitle: contact.relationshipLabel.isEmpty ? nil : contact.relationshipLabel,
                        snippet: nil, date: contact.updatedAt, contact: contact
                    )
                }
            } else {
                results += searchContacts(tokens, in: filtered)
            }
        }

        if shouldSearchType(.todo) {
            let todos = TodoCardStorage.shared.todoCards
            let filtered = applyTagScope(todos: todos, scope: scope)
            if tokens.isEmpty {
                results += filtered.map { todo in
                    SearchResult(
                        id: todo.id, type: .todo, title: todo.title,
                        subtitle: todo.isCompleted ? "Completed" : (todo.dueDate.map { "Due \($0.formatted(.dateTime.month().day()))" }),
                        snippet: nil, date: todo.updatedAt, todoCard: todo
                    )
                }
            } else {
                results += searchTodos(tokens, in: filtered)
            }
        }

        return results
    }

    // MARK: - Scope Filtering Helpers

    /// Apply folder scope: if specific folders are set, filter to those.
    /// If showAllFolders, filter to items that have ANY folder assigned.
    private static func applyFolderFilter<T>(_ items: [T], scope: SearchScope, folderID: (T) -> UUID?) -> [T] {
        if !scope.folderIDs.isEmpty {
            return items.filter { item in
                guard let fID = folderID(item) else { return false }
                return scope.folderIDs.contains(fID)
            }
        } else if scope.showAllFolders {
            return items.filter { folderID($0) != nil }
        }
        return items
    }

    private static func applyFolderAndTagScope(bookmarks: [Bookmark], scope: SearchScope) -> [Bookmark] {
        var result = applyFolderFilter(bookmarks, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private static func applyFolderAndTagScope(notes: [Note], scope: SearchScope) -> [Note] {
        var result = applyFolderFilter(notes, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private static func applyTagScope(dateCards: [DateCard], scope: SearchScope) -> [DateCard] {
        var result = applyFolderFilter(dateCards, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private static func applyTagScope(contacts: [ContactCard], scope: SearchScope) -> [ContactCard] {
        var result = applyFolderFilter(contacts, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
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

    private static func applyTagScope(todos: [TodoCard], scope: SearchScope) -> [TodoCard] {
        var result = applyFolderFilter(todos, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    static func searchTodos(_ tokens: [String], in todos: [TodoCard]) -> [SearchResult] {
        todos.compactMap { todo in
            var fields = [todo.title, todo.details]
            fields.append(contentsOf: todo.checklist.map(\.title))
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let headerMatch = fieldsMatch(tokens, in: [todo.title])

            let snippet: SearchSnippet?
            let subtitle: String?
            if headerMatch {
                subtitle = todo.isCompleted ? "Completed" : (todo.dueDate.map { "Due \($0.formatted(.dateTime.month().day()))" })
                snippet  = nil
            } else {
                subtitle = nil
                snippet  = extractSnippet(tokens: tokens, from: todo.details)
            }

            return SearchResult(
                id: todo.id,
                type: .todo,
                title: todo.title,
                subtitle: subtitle,
                snippet: snippet,
                date: todo.updatedAt,
                todoCard: todo
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
