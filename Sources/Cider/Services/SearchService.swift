import Foundation

enum SearchResultType {
    case bookmark
    case note
    case dateCard
    case contact
    case todo
    case vaultFile
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
    var vaultFile: VaultFile?
}

// MARK: - Search Scope

struct SearchScope: Equatable {
    var entityTypes: Set<SearchResultType>?  // nil = all types
    var folderIDs: Set<UUID> = []            // empty = no folder filter (unless showAllFolders)
    var folderNames: [String] = []           // display names for matched folders
    var showAllFolders: Bool = false         // true when `@folder:` typed with no name
    var labelID: UUID?
    var labelName: String?                   // raw name from query, for display
    var resolutionFailures: [String] = []    // unsupported/unresolved modifiers; search must fail closed
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
                case .vaultFile: return "Files"
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

    var isResolved: Bool {
        resolutionFailures.isEmpty
    }
}

@MainActor
enum SearchService {
    private struct GenericTypeIntent {
        var type: SearchResultType
        var contentTokens: [String]
    }

    struct Snapshot {
        var query: String
        var bookmarks: [Bookmark]
        var notes: [Note]
        var dateCards: [DateCard]
        var contacts: [ContactCard]
        var todos: [TodoCard]
        var vaultFiles: [VaultFile]
        var folders: [Folder]
        var labels: [CardLabel]
    }

    // MARK: - Scope Parsing

    /// Parse `@scope` modifiers from a raw query string.
    /// Recognized: `@bookmarks`, `@notes`, `@events`/`@datecards`, `@contacts`,
    ///             `@folder:Name With Spaces`, `@tag:Name With Spaces`
    /// Entity type scopes support prefix matching: `@b` → bookmarks, `@no` → notes.
    /// Folder/tag names support spaces — all tokens after `@folder:` until the next `@`
    /// modifier are consumed as part of the name.
    static func parseScope(from rawQuery: String) -> SearchScope {
        parseScope(
            from: rawQuery,
            folders: VaultFolderService.shared.legacyFolders,
            labels: CardLabelStorage.shared.labels
        )
    }

    nonisolated static func parseScope(
        from rawQuery: String,
        folders: [Folder],
        labels: [CardLabel]
    ) -> SearchScope {
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
        var resolutionFailures: [String] = []
        var remainingParts: [String] = []

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        let entityKeywords: [(names: [String], type: SearchResultType)] = [
            (["bookmarks", "bookmark"], .bookmark),
            (["notes", "note"], .note),
            (["events", "event", "datecards", "datecard"], .dateCard),
            (["contacts", "contact"], .contact),
            (["todos", "todo", "tasks", "task"], .todo),
            (["files", "file", "images", "image", "vaultfiles", "vaultfile"], .vaultFile),
        ]

        var i = 0
        while i < parts.count {
            let part = parts[i]

            guard part.hasPrefix("@") else {
                remainingParts.append(part)
                i += 1
                continue
            }

            let rawModifier = String(part.dropFirst())
            let modifier = rawModifier.lowercased()

            // Folder scope: @folder:Name or @f:Name (prefix match on "folder")
            // @folder: with no name → show all folders
            if let colonIdx = modifier.firstIndex(of: ":"),
               "folder".hasPrefix(String(modifier[modifier.startIndex..<colonIdx])),
               modifier[modifier.startIndex..<colonIdx].count >= 1,
               let rawColonIdx = rawModifier.firstIndex(of: ":") {
                let afterColon = String(rawModifier[rawModifier.index(after: rawColonIdx)...])
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
                if let folder = folders.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }) {
                    folderIDs.insert(folder.id)
                    folderNames.append(folder.name)
                } else {
                    let prefixMatches = folders.filter {
                        $0.name.lowercased().hasPrefix(name.lowercased())
                    }
                    if prefixMatches.count == 1, let folder = prefixMatches.first {
                        folderIDs.insert(folder.id)
                        folderNames.append(folder.name)
                    } else if prefixMatches.count > 1 {
                        resolutionFailures.append("Folder '\(name)' is ambiguous.")
                    } else {
                        resolutionFailures.append("Folder '\(name)' was not found.")
                        remainingParts.append(contentsOf: nameParts)
                    }
                }
                continue
            }

            // Tag scope: @tag:Name or @t:Name (prefix match on "tag")
            if let colonIdx = modifier.firstIndex(of: ":"),
               "tag".hasPrefix(String(modifier[modifier.startIndex..<colonIdx])),
               modifier[modifier.startIndex..<colonIdx].count >= 1,
               let rawColonIdx = rawModifier.firstIndex(of: ":") {
                let afterColon = String(rawModifier[rawModifier.index(after: rawColonIdx)...])
                var nameParts: [String] = []
                if !afterColon.isEmpty { nameParts.append(afterColon) }
                i += 1
                while i < parts.count, !parts[i].hasPrefix("@") {
                    nameParts.append(parts[i])
                    i += 1
                }
                let name = nameParts.joined(separator: " ")
                guard !name.isEmpty else {
                    resolutionFailures.append("Tag scope needs a tag name.")
                    continue
                }
                if labelName != nil {
                    resolutionFailures.append("Multiple tag scopes are not supported by Search Palette yet.")
                }
                labelName = name
                if let label = labels.first(where: {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }) {
                    labelID = label.id
                } else {
                    let prefixMatches = labels.filter {
                        $0.name.lowercased().hasPrefix(name.lowercased())
                    }
                    if prefixMatches.count == 1, let label = prefixMatches.first {
                        labelID = label.id
                        labelName = label.name
                    } else if prefixMatches.count > 1 {
                        resolutionFailures.append("Tag '\(name)' is ambiguous.")
                    } else {
                        resolutionFailures.append("Tag '\(name)' was not found.")
                    }
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
                resolutionFailures.append("Unsupported scope modifier '\(part)'.")
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
            resolutionFailures: resolutionFailures,
            cleanQuery: remainingParts.joined(separator: " ")
        )
    }

    // MARK: - Search

    static func search(query: String, bookmarks: [Bookmark], notes: [Note]) async -> [SearchResult] {
        let snapshot = Snapshot(
            query: query,
            bookmarks: bookmarks,
            notes: notes,
            dateCards: DateCardStorage.shared.dateCards,
            contacts: ContactStorage.shared.contacts,
            todos: TodoCardStorage.shared.todoCards,
            vaultFiles: VaultFileService.shared.files,
            folders: VaultFolderService.shared.legacyFolders,
            labels: CardLabelStorage.shared.labels
        )
        return await search(snapshot: snapshot)
    }

    nonisolated static func search(snapshot: Snapshot) async -> [SearchResult] {
        await search(
            query: snapshot.query,
            bookmarks: snapshot.bookmarks,
            notes: snapshot.notes,
            dateCards: snapshot.dateCards,
            contacts: snapshot.contacts,
            todos: snapshot.todos,
            vaultFiles: snapshot.vaultFiles,
            folders: snapshot.folders,
            labels: snapshot.labels
        )
    }

    private nonisolated static func search(
        query: String,
        bookmarks: [Bookmark],
        notes: [Note],
        dateCards: [DateCard],
        contacts: [ContactCard],
        todos: [TodoCard],
        vaultFiles: [VaultFile],
        folders: [Folder],
        labels: [CardLabel]
    ) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var scope = parseScope(from: trimmed, folders: folders, labels: labels)
        guard scope.isResolved else { return [] }
        let genericTypeIntent = scope.entityTypes == nil ? parseGenericTypeIntent(from: scope.cleanQuery) : nil
        if let genericTypeIntent {
            scope.entityTypes = [genericTypeIntent.type]
            scope.cleanQuery = genericTypeIntent.contentTokens.joined(separator: " ")
        }

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
                        subtitle: note.journalCaptureSubtitle, snippet: nil,
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

        if shouldSearchType(.vaultFile) {
            var filtered = applyFolderFilter(vaultFiles, scope: scope) { $0.folderID }
            if let labelID = scope.labelID {
                filtered = filtered.filter { $0.labelIDs.contains(labelID) }
            }
            if tokens.isEmpty {
                results += filtered.map { file in
                    SearchResult(
                        id: file.id, type: .vaultFile, title: file.displayTitle,
                        subtitle: file.fileType.displayName,
                        snippet: nil, date: file.modifiedAt, vaultFile: file
                    )
                }
            } else {
                results += searchVaultFiles(tokens, in: filtered)
            }
        }

        return results
    }

    private nonisolated static func parseGenericTypeIntent(from query: String) -> GenericTypeIntent? {
        let tokens = query
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
        guard !tokens.isEmpty else { return nil }
        let aliases: [(type: SearchResultType, names: Set<String>)] = [
            (.dateCard, ["event", "events", "date", "dates", "calendar"]),
            (.todo, ["todo", "todos", "task", "tasks"]),
            (.contact, ["contact", "contacts", "person", "people"]),
            (.vaultFile, ["file", "files", "document", "documents", "doc", "docs", "pdf", "docx"]),
            (.bookmark, ["bookmark", "bookmarks", "link", "links"]),
            (.note, ["note", "notes", "journal", "journals"]),
        ]
        for alias in aliases {
            guard tokens.contains(where: alias.names.contains) else { continue }
            return GenericTypeIntent(
                type: alias.type,
                contentTokens: tokens.filter { !alias.names.contains($0) }
            )
        }
        return nil
    }

    // MARK: - Scope Filtering Helpers

    /// Apply folder scope: if specific folders are set, filter to those.
    /// If showAllFolders, filter to items that have ANY folder assigned.
    private nonisolated static func applyFolderFilter<T>(_ items: [T], scope: SearchScope, folderID: (T) -> UUID?) -> [T] {
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

    private nonisolated static func applyFolderAndTagScope(bookmarks: [Bookmark], scope: SearchScope) -> [Bookmark] {
        var result = applyFolderFilter(bookmarks, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private nonisolated static func applyFolderAndTagScope(notes: [Note], scope: SearchScope) -> [Note] {
        var result = applyFolderFilter(notes, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private nonisolated static func applyTagScope(dateCards: [DateCard], scope: SearchScope) -> [DateCard] {
        var result = applyFolderFilter(dateCards, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    private nonisolated static func applyTagScope(contacts: [ContactCard], scope: SearchScope) -> [ContactCard] {
        var result = applyFolderFilter(contacts, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    nonisolated static func searchBookmarks(_ tokens: [String], in bookmarks: [Bookmark]) -> [SearchResult] {
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
    nonisolated static func searchNotes(_ tokens: [String], in notes: [Note]) async -> [SearchResult] {
        await fetchNoteResults(tokens: tokens, notes: notes)
    }

    nonisolated static func searchDateCards(_ tokens: [String], in dateCards: [DateCard]) -> [SearchResult] {
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

    nonisolated static func searchContacts(_ tokens: [String], in contacts: [ContactCard]) -> [SearchResult] {
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

    nonisolated static func searchVaultFiles(_ tokens: [String], in files: [VaultFile]) -> [SearchResult] {
        files.compactMap { file in
            let fields = [file.filename, file.displayTitle, file.notes, file.ocrText ?? ""]
                .filter { !$0.isEmpty }
            guard matchesAllTokens(tokens, in: fields) else { return nil }
            return SearchResult(
                id: file.id, type: .vaultFile, title: file.displayTitle,
                subtitle: file.fileType.displayName,
                snippet: nil, date: file.modifiedAt, vaultFile: file
            )
        }
    }

    private nonisolated static func applyTagScope(todos: [TodoCard], scope: SearchScope) -> [TodoCard] {
        var result = applyFolderFilter(todos, scope: scope) { $0.folderID }
        if let labelID = scope.labelID {
            result = result.filter { $0.labelIDs.contains(labelID) }
        }
        return result
    }

    nonisolated static func searchTodos(_ tokens: [String], in todos: [TodoCard]) -> [SearchResult] {
        todos.compactMap { todo in
            var fields = [todo.title, todo.details]
            fields.append(contentsOf: todo.checklist.map(\.title))
            fields.append(contentsOf: todo.checklist.flatMap { $0.subtasks.map(\.title) })
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
        notes: [Note]
    ) async -> [SearchResult] {
        notes.compactMap { note in
            let fileURL = note.absoluteFileURL
            let rawContent = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? note.content
            let strippedContent = rawContent
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let tagsString = note.tags.joined(separator: " ")
            let fields = [note.title, strippedContent, tagsString]
            guard matchesAllTokens(tokens, in: fields) else { return nil }

            let titleMatch = fieldsMatch(tokens, in: [note.title])

            let snippet: SearchSnippet?
            let subtitle: String?
            if titleMatch {
                subtitle = note.journalCaptureSubtitle ?? String(strippedContent.prefix(80))
                snippet  = nil
            } else {
                subtitle = note.journalCaptureSubtitle
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

enum SearchPaletteCanonicalSearchStatus: Equatable {
    case ready
    case failedClosed([String])
    case unavailable(String)
    case cancelled
}

struct SearchPaletteCanonicalSearchResponse {
    var results: [SearchResult]
    var canonical: CiderQueryResponse?
    var status: SearchPaletteCanonicalSearchStatus
    var unprojectedCanonicalItemIDs: [UUID]

    var statusMessage: String? {
        switch status {
        case .cancelled:
            return nil
        case .failedClosed(let reasons):
            return (reasons.first ?? "The requested scope is unsupported.") + " Search was not broadened."
        case .unavailable:
            return "Indexed search is currently unavailable. No complete no-match conclusion was made."
        case .ready:
            if !unprojectedCanonicalItemIDs.isEmpty {
                return "Some indexed matches cannot be presented from the current Search Palette snapshot."
            }
            guard let canonical else {
                return "Indexed search state is unavailable."
            }
            if canonical.fallbackState == .canonicalFieldsOnly {
                return "Showing canonical title and path fallback; indexed body search is unavailable."
            }
            if canonical.indexState.status == .lagging {
                return "The search index is lagging; results may be incomplete."
            }
            if canonical.indexState.status == .incomplete {
                return "The search index is incomplete; results may be incomplete."
            }
            if canonical.indexState.status == .unavailable {
                return "Index freshness is unavailable; results may be incomplete."
            }
            if canonical.resultWindowIsBounded {
                return "Showing a bounded canonical result window."
            }
            return nil
        }
    }

    var emptyStateMessage: String? {
        guard results.isEmpty else { return nil }
        if let statusMessage { return statusMessage }
        switch status {
        case .cancelled:
            return nil
        case .failedClosed, .unavailable:
            return statusMessage
        case .ready:
            guard let canonical else {
                return "Indexed search state is unavailable."
            }
            switch canonical.classification {
            case .matches:
                return "Indexed matches exist, but they could not be presented here."
            case .noMatches:
                return nil
            case .indeterminate:
                return "Search coverage was bounded. No complete no-match conclusion was made."
            }
        }
    }
}

@MainActor
struct SearchPaletteCanonicalSearchAdapter {
    private let contextService: CiderItemContextService
    private let resultLimit: Int

    init(
        contextService: CiderItemContextService = CiderItemContextService(),
        resultLimit: Int = 100
    ) {
        self.contextService = contextService
        self.resultLimit = max(1, resultLimit)
    }

    func search(snapshot: SearchService.Snapshot) async -> SearchPaletteCanonicalSearchResponse {
        if Task.isCancelled {
            return cancelledResponse()
        }
        let scope = SearchService.parseScope(
            from: snapshot.query,
            folders: snapshot.folders,
            labels: snapshot.labels
        )
        guard scope.isResolved else {
            return SearchPaletteCanonicalSearchResponse(
                results: [],
                canonical: nil,
                status: .failedClosed(scope.resolutionFailures),
                unprojectedCanonicalItemIDs: []
            )
        }
        guard !(scope.showAllFolders && !scope.folderIDs.isEmpty) else {
            return SearchPaletteCanonicalSearchResponse(
                results: [],
                canonical: nil,
                status: .failedClosed(["All-folders scope cannot be combined with a specific folder scope."]),
                unprojectedCanonicalItemIDs: []
            )
        }

        let folderFacet: CiderQueryFolderFacet
        if !scope.folderIDs.isEmpty {
            folderFacet = .folderIDs(scope.folderIDs)
        } else if scope.showAllFolders {
            folderFacet = .anyAssignedFolder
        } else {
            folderFacet = .none
        }
        let entityTypes = scope.entityTypes.map { Set($0.map(libraryEntityType)) }
            ?? LibraryEntityType.activeCases
        let tagIDs = scope.labelID.map { Set([$0]) } ?? []
        let query = CiderQuery(
            text: scope.cleanQuery,
            facets: CiderQueryFacets(
                entityTypes: entityTypes,
                folder: folderFacet,
                tagIDs: tagIDs
            ),
            limit: resultLimit
        )

        do {
            let canonical = try contextService.query(query)
            if Task.isCancelled {
                return cancelledResponse()
            }
            let projected = project(canonical.results, query: query.text, snapshot: snapshot)
            return SearchPaletteCanonicalSearchResponse(
                results: projected.results,
                canonical: canonical,
                status: .ready,
                unprojectedCanonicalItemIDs: projected.unprojectedIDs
            )
        } catch {
            return SearchPaletteCanonicalSearchResponse(
                results: [],
                canonical: nil,
                status: .unavailable(error.localizedDescription),
                unprojectedCanonicalItemIDs: []
            )
        }
    }

    private func cancelledResponse() -> SearchPaletteCanonicalSearchResponse {
        SearchPaletteCanonicalSearchResponse(
            results: [],
            canonical: nil,
            status: .cancelled,
            unprojectedCanonicalItemIDs: []
        )
    }

    private func libraryEntityType(_ type: SearchResultType) -> LibraryEntityType {
        switch type {
        case .bookmark: return .bookmark
        case .note: return .note
        case .dateCard: return .dateCard
        case .contact: return .contact
        case .todo: return .todo
        case .vaultFile: return .vaultFile
        }
    }

    private func project(
        _ canonicalResults: [CiderItemSearchResult],
        query: String,
        snapshot: SearchService.Snapshot
    ) -> (results: [SearchResult], unprojectedIDs: [UUID]) {
        let bookmarks = Dictionary(uniqueKeysWithValues: snapshot.bookmarks.map { ($0.id, $0) })
        let notes = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.id, $0) })
        let dateCards = Dictionary(uniqueKeysWithValues: snapshot.dateCards.map { ($0.id, $0) })
        let contacts = Dictionary(uniqueKeysWithValues: snapshot.contacts.map { ($0.id, $0) })
        let todos = Dictionary(uniqueKeysWithValues: snapshot.todos.map { ($0.id, $0) })
        let files = Dictionary(uniqueKeysWithValues: snapshot.vaultFiles.map { ($0.id, $0) })
        var projected: [(result: SearchResult, canonical: CiderItemSearchResult)] = []
        var unprojectedIDs: [UUID] = []

        for canonical in canonicalResults {
            guard let item = canonical.item else { continue }
            let snippet = presentationSnippet(for: canonical, query: query)
            let result: SearchResult?
            switch item.type {
            case .bookmark:
                result = bookmarks[item.id].map { bookmark in
                    SearchResult(
                        id: item.id, type: .bookmark, title: bookmark.title,
                        subtitle: snippet == nil ? bookmark.hostDisplay : nil,
                        snippet: snippet, date: bookmark.updatedAt, bookmark: bookmark
                    )
                }
            case .note:
                result = notes[item.id].map { note in
                    SearchResult(
                        id: item.id, type: .note, title: note.title,
                        subtitle: note.journalCaptureSubtitle,
                        snippet: snippet, date: note.modifiedAt, note: note
                    )
                }
            case .dateCard:
                result = dateCards[item.id].map { dateCard in
                    SearchResult(
                        id: item.id, type: .dateCard, title: dateCard.title,
                        subtitle: snippet == nil ? dateCard.startAt.formatted(.dateTime.month().day().year()) : nil,
                        snippet: snippet, date: dateCard.updatedAt, dateCard: dateCard
                    )
                }
            case .contact:
                result = contacts[item.id].map { contact in
                    SearchResult(
                        id: item.id, type: .contact, title: contact.displayName,
                        subtitle: snippet == nil && !contact.relationshipLabel.isEmpty ? contact.relationshipLabel : nil,
                        snippet: snippet, date: contact.updatedAt, contact: contact
                    )
                }
            case .todo:
                result = todos[item.id].map { todo in
                    SearchResult(
                        id: item.id, type: .todo, title: todo.title,
                        subtitle: snippet == nil ? todoSubtitle(todo) : nil,
                        snippet: snippet, date: todo.updatedAt, todoCard: todo
                    )
                }
            case .vaultFile:
                result = files[item.id].map { file in
                    SearchResult(
                        id: item.id, type: .vaultFile, title: file.displayTitle,
                        subtitle: file.fileType.displayName,
                        snippet: snippet, date: file.modifiedAt, vaultFile: file
                    )
                }
            case .externalFile, .session:
                result = nil
            }
            if let result {
                projected.append((result, canonical))
            } else {
                unprojectedIDs.append(item.id)
            }
        }

        projected.sort { lhs, rhs in
            let lhsScore = presentationRank(for: lhs.result, canonical: lhs.canonical, query: query)
            let rhsScore = presentationRank(for: rhs.result, canonical: rhs.canonical, query: query)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.result.date != rhs.result.date { return lhs.result.date > rhs.result.date }
            return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
        }
        return (projected.map(\.result), unprojectedIDs)
    }

    private func todoSubtitle(_ todo: TodoCard) -> String? {
        if todo.isCompleted { return "Completed" }
        return todo.dueDate.map { "Due \($0.formatted(.dateTime.month().day()))" }
    }

    private func presentationSnippet(
        for canonical: CiderItemSearchResult,
        query: String
    ) -> SearchSnippet? {
        guard canonical.kind == .chunk || canonical.matchProvenance.isHistoricalOnly else { return nil }
        let raw = canonical.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let open = raw.firstIndex(of: "["),
           let close = raw[raw.index(after: open)...].firstIndex(of: "]") {
            return SearchSnippet(
                prefix: String(raw[..<open]),
                match: String(raw[raw.index(after: open)..<close]),
                suffix: String(raw[raw.index(after: close)...])
            )
        }
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return SearchService.extractSnippet(tokens: tokens, from: raw)
            ?? SearchSnippet(prefix: "", match: String(raw.prefix(120)), suffix: raw.count > 120 ? "…" : "")
    }

    private func presentationRank(
        for result: SearchResult,
        canonical: CiderItemSearchResult,
        query: String
    ) -> Double {
        var score = canonical.rank
        if !query.isEmpty, result.title.localizedStandardContains(query) {
            score += 1_000
        }
        if canonical.matchProvenance.currentContentMatched {
            score += 100
        }
        if canonical.matchProvenance.isHistoricalOnly {
            score -= 100
        }
        return score
    }
}
