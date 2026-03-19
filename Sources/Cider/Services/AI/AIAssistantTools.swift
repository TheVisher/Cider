import Foundation
import FoundationModels

// MARK: - Count Items Tool

/// Counts items across all Cider entity types.
struct CountItemsTool: Tool {
    let name = "countItems"
    let description = """
    Count the user's items in Cider. Can count bookmarks, notes, events, \
    todos, contacts, folders, tags, clipboard items, or browser sessions. \
    Use itemType "all" for a summary of everything.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Type of item to count: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, sessions, or all")
        var itemType: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let type = arguments.itemType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case "bookmarks", "bookmark":
            let count = BookmarksStorage.shared.bookmarks.count
            return ("The user has \(count) bookmarks.")

        case "notes", "note":
            let count = NotesStorage.shared.notes.count
            return ("The user has \(count) notes.")

        case "events", "event", "datecards", "datecard", "date cards":
            let count = DateCardStorage.shared.dateCards.count
            let upcoming = DateCardStorage.shared.dateCards.filter { $0.startAt > Date() && !$0.isCompleted }.count
            return ("The user has \(count) events (\(upcoming) upcoming).")

        case "todos", "todo", "tasks", "task":
            let all = TodoCardStorage.shared.todoCards
            let incomplete = all.filter { !$0.isCompleted }.count
            return ("The user has \(all.count) todos (\(incomplete) incomplete).")

        case "contacts", "contact":
            let count = ContactStorage.shared.contacts.count
            return ("The user has \(count) contacts.")

        case "folders", "folder":
            let count = VaultFolderService.shared.folders.count
            return ("The user has \(count) folders.")

        case "tags", "tag", "labels", "label":
            let count = CardLabelStorage.shared.labels.count
            return ("The user has \(count) tags/labels.")

        case "clipboard":
            let count = ClipboardStorage.shared.items.count
            return ("The clipboard history has \(count) items.")

        case "sessions", "session", "browser sessions":
            let count = BrowserSessionStorage.shared.sessions.count
            return ("The user has \(count) saved browser sessions.")

        case "all", "everything", "summary":
            let bookmarks = BookmarksStorage.shared.bookmarks.count
            let notes = NotesStorage.shared.notes.count
            let events = DateCardStorage.shared.dateCards.count
            let todos = TodoCardStorage.shared.todoCards.count
            let contacts = ContactStorage.shared.contacts.count
            let folders = VaultFolderService.shared.folders.count
            let tags = CardLabelStorage.shared.labels.count
            let sessions = BrowserSessionStorage.shared.sessions.count
            return ("""
            Library summary: \(bookmarks) bookmarks, \(notes) notes, \
            \(events) events, \(todos) todos, \(contacts) contacts, \
            \(folders) folders, \(tags) tags, \(sessions) browser sessions.
            """)

        default:
            return ("Unknown item type '\(type)'. Valid types: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, sessions, all.")
        }
    } }
}

// MARK: - Search Items Tool

/// Searches across all Cider entity types by keyword.
struct SearchItemsTool: Tool {
    let name = "searchItems"
    let description = """
    Search the user's bookmarks, notes, events, todos, and contacts by keyword. \
    Returns matching items with titles and details. Use this when the user asks \
    about specific topics, items, or content in their library.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Search query — keywords to search for across titles, URLs, content, and tags")
        var query: String

        @Guide(description: "Optional: limit to a specific type (bookmarks, notes, events, todos, contacts). Leave empty to search all.")
        var itemType: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let query = arguments.query.lowercased()
        var results: [String] = []

        let typeFilter = arguments.itemType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let searchAll = typeFilter == nil || typeFilter == "" || typeFilter == "all"

        // Search bookmarks
        if searchAll || typeFilter == "bookmarks" || typeFilter == "bookmark" {
            let matches = BookmarksStorage.shared.bookmarks.filter { bookmark in
                bookmark.title.localizedStandardContains(query) ||
                bookmark.urlString.localizedStandardContains(query) ||
                bookmark.notes.localizedStandardContains(query) ||
                bookmark.tags.contains(where: { $0.localizedStandardContains(query) }) ||
                (bookmark.aiSummary?.localizedStandardContains(query) ?? false)
            }
            for b in matches.prefix(10) {
                var desc = "Bookmark: \"\(b.title)\" (\(b.urlString))"
                if let summary = b.aiSummary { desc += " — \(summary)" }
                results.append(desc)
            }
            if matches.count > 10 { results.append("...and \(matches.count - 10) more bookmarks") }
        }

        // Search notes
        if searchAll || typeFilter == "notes" || typeFilter == "note" {
            let matches = NotesStorage.shared.notes.filter { note in
                note.title.localizedStandardContains(query)
            }
            for n in matches.prefix(10) {
                results.append("Note: \"\(n.title)\"")
            }
            if matches.count > 10 { results.append("...and \(matches.count - 10) more notes") }
        }

        // Search events
        if searchAll || typeFilter == "events" || typeFilter == "event" {
            let matches = DateCardStorage.shared.dateCards.filter { card in
                card.title.localizedStandardContains(query) ||
                card.details.localizedStandardContains(query) ||
                card.location.localizedStandardContains(query)
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            for e in matches.prefix(10) {
                results.append("Event: \"\(e.title)\" on \(formatter.string(from: e.startAt))")
            }
            if matches.count > 10 { results.append("...and \(matches.count - 10) more events") }
        }

        // Search todos
        if searchAll || typeFilter == "todos" || typeFilter == "todo" {
            let matches = TodoCardStorage.shared.todoCards.filter { todo in
                todo.title.localizedStandardContains(query) ||
                todo.details.localizedStandardContains(query)
            }
            for t in matches.prefix(10) {
                let status = t.isCompleted ? "✓" : "○"
                results.append("Todo: \(status) \"\(t.title)\"")
            }
            if matches.count > 10 { results.append("...and \(matches.count - 10) more todos") }
        }

        // Search contacts
        if searchAll || typeFilter == "contacts" || typeFilter == "contact" {
            let matches = ContactStorage.shared.contacts.filter { contact in
                contact.displayName.localizedStandardContains(query) ||
                contact.email.localizedStandardContains(query) ||
                contact.notes.localizedStandardContains(query)
            }
            for c in matches.prefix(10) {
                var desc = "Contact: \"\(c.displayName)\""
                if !c.email.isEmpty { desc += " (\(c.email))" }
                results.append(desc)
            }
            if matches.count > 10 { results.append("...and \(matches.count - 10) more contacts") }
        }

        if results.isEmpty {
            return ("No items found matching \"\(arguments.query)\".")
        }
        return ("Found \(results.count) results:\n" + results.joined(separator: "\n"))
    } }
}

// MARK: - List Folders Tool

/// Lists all folders with item counts.
struct ListFoldersTool: Tool {
    let name = "listFolders"
    let description = """
    List all folders in the user's vault with the number of items in each. \
    Shows the folder hierarchy.
    """

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let folders = VaultFolderService.shared.folders
        if folders.isEmpty {
            return ("No folders exist yet.")
        }

        let bookmarks = BookmarksStorage.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let events = DateCardStorage.shared.dateCards
        let todos = TodoCardStorage.shared.todoCards
        let contacts = ContactStorage.shared.contacts

        var lines: [String] = []
        for folder in folders.sorted(by: { $0.relativePath < $1.relativePath }) {
            let fid = folder.id
            let bCount = bookmarks.filter { $0.folderID == fid }.count
            let nCount = notes.filter { $0.folderID == fid }.count
            let eCount = events.filter { $0.folderID == fid }.count
            let tCount = todos.filter { $0.folderID == fid }.count
            let cCount = contacts.filter { $0.folderID == fid }.count
            let total = bCount + nCount + eCount + tCount + cCount

            let indent = folder.relativePath.components(separatedBy: "/").count - 1
            let prefix = String(repeating: "  ", count: indent)
            lines.append("\(prefix)📁 \(folder.name) (\(total) items: \(bCount) bookmarks, \(nCount) notes, \(eCount) events, \(tCount) todos, \(cCount) contacts)")
        }
        return ("Folders:\n" + lines.joined(separator: "\n"))
    } }
}

// MARK: - List Tags Tool

/// Lists all tags/labels with usage counts.
struct ListTagsTool: Tool {
    let name = "listTags"
    let description = "List all tags/labels the user has created, with how many items use each tag."

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let labels = CardLabelStorage.shared.labels
        if labels.isEmpty {
            return ("No tags/labels exist yet.")
        }

        var lines: [String] = []
        for label in labels.sorted(by: { $0.name < $1.name }) {
            let count = CardLabelStorage.shared.itemCount(for: label.id)
            lines.append("🏷 \(label.name) (\(count) items)")
        }
        return ("Tags:\n" + lines.joined(separator: "\n"))
    } }
}

// MARK: - Get Recent Items Tool

/// Returns recently created or modified items.
struct GetRecentItemsTool: Tool {
    let name = "getRecentItems"
    let description = """
    Get items the user recently created or modified. \
    Shows the most recent bookmarks, notes, events, todos, and contacts.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Number of days to look back (e.g. 1 for today, 7 for this week)", .range(1...365))
        var days: Int
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let threshold = Date().addingTimeInterval(-Double(arguments.days) * 86400)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var results: [String] = []

        let recentBookmarks = BookmarksStorage.shared.bookmarks
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for b in recentBookmarks.prefix(10) {
            results.append("Bookmark: \"\(b.title)\" — \(formatter.string(from: b.createdAt))")
        }
        if recentBookmarks.count > 10 { results.append("...and \(recentBookmarks.count - 10) more bookmarks") }

        let recentNotes = NotesStorage.shared.notes
            .filter { $0.modifiedAt >= threshold }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        for n in recentNotes.prefix(10) {
            results.append("Note: \"\(n.title)\" — \(formatter.string(from: n.modifiedAt))")
        }
        if recentNotes.count > 10 { results.append("...and \(recentNotes.count - 10) more notes") }

        let recentEvents = DateCardStorage.shared.dateCards
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for e in recentEvents.prefix(5) {
            results.append("Event: \"\(e.title)\" — \(formatter.string(from: e.startAt))")
        }

        let recentTodos = TodoCardStorage.shared.todoCards
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for t in recentTodos.prefix(5) {
            let status = t.isCompleted ? "✓" : "○"
            results.append("Todo: \(status) \"\(t.title)\"")
        }

        if results.isEmpty {
            return ("No items created or modified in the last \(arguments.days) day(s).")
        }
        return ("Items from the last \(arguments.days) day(s):\n" + results.joined(separator: "\n"))
    } }
}

// MARK: - Get Items By Tag Tool

/// Finds all items tagged with a specific label.
struct GetItemsByTagTool: Tool {
    let name = "getItemsByTag"
    let description = "Find all items (bookmarks, notes, events, todos, contacts) that have a specific tag/label."

    @Generable
    struct Arguments {
        @Guide(description: "The tag/label name to search for")
        var tagName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let tagName = arguments.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label = CardLabelStorage.shared.labels.first(where: {
            $0.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
        }) else {
            // Try partial match
            let partial = CardLabelStorage.shared.labels.filter {
                $0.name.localizedStandardContains(tagName)
            }
            if partial.isEmpty {
                return ("No tag named \"\(tagName)\" found. Available tags: \(CardLabelStorage.shared.labels.map(\.name).joined(separator: ", "))")
            }
            let names = partial.map(\.name).joined(separator: ", ")
            return ("No exact match for \"\(tagName)\". Did you mean: \(names)?")
        }

        var results: [String] = []
        let lid = label.id

        let bookmarks = BookmarksStorage.shared.bookmarks.filter { $0.labelIDs.contains(lid) }
        for b in bookmarks.prefix(10) {
            results.append("Bookmark: \"\(b.title)\"")
        }
        if bookmarks.count > 10 { results.append("...and \(bookmarks.count - 10) more bookmarks") }

        let notes = NotesStorage.shared.notes.filter { $0.labelIDs.contains(lid) }
        for n in notes.prefix(10) {
            results.append("Note: \"\(n.title)\"")
        }

        let events = DateCardStorage.shared.dateCards.filter { $0.labelIDs.contains(lid) }
        for e in events.prefix(5) {
            results.append("Event: \"\(e.title)\"")
        }

        let todos = TodoCardStorage.shared.todoCards.filter { $0.labelIDs.contains(lid) }
        for t in todos.prefix(5) {
            results.append("Todo: \"\(t.title)\"")
        }

        let contacts = ContactStorage.shared.contacts.filter { $0.labelIDs.contains(lid) }
        for c in contacts.prefix(5) {
            results.append("Contact: \"\(c.displayName)\"")
        }

        let total = bookmarks.count + notes.count + events.count + todos.count + contacts.count
        if total == 0 {
            return ("Tag \"\(label.name)\" exists but has no items.")
        }
        return ("\(total) items tagged \"\(label.name)\":\n" + results.joined(separator: "\n"))
    } }
}

// MARK: - Get Upcoming Events Tool

/// Returns upcoming events/date cards.
struct GetUpcomingEventsTool: Tool {
    let name = "getUpcomingEvents"
    let description = "Get upcoming events and date cards. Shows events happening soon."

    @Generable
    struct Arguments {
        @Guide(description: "Number of days ahead to look (e.g. 7 for this week, 30 for this month)", .range(1...365))
        var days: Int
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let now = Date()
        let end = now.addingTimeInterval(Double(arguments.days) * 86400)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let upcoming = DateCardStorage.shared.dateCards
            .filter { $0.startAt >= now && $0.startAt <= end && !$0.isCompleted }
            .sorted { $0.startAt < $1.startAt }

        if upcoming.isEmpty {
            return ("No upcoming events in the next \(arguments.days) day(s).")
        }

        var lines: [String] = []
        for e in upcoming.prefix(20) {
            var desc = "\"\(e.title)\" — \(formatter.string(from: e.startAt))"
            if !e.location.isEmpty { desc += " at \(e.location)" }
            if e.allDay { desc += " (all day)" }
            lines.append(desc)
        }
        if upcoming.count > 20 { lines.append("...and \(upcoming.count - 20) more") }

        return ("Upcoming events (\(upcoming.count) total):\n" + lines.joined(separator: "\n"))
    } }
}

// MARK: - Get Overdue Todos Tool

/// Returns incomplete todos that are past their due date.
struct GetOverdueTodosTool: Tool {
    let name = "getOverdueTodos"
    let description = "Get incomplete todos that are past their due date, plus any high-priority tasks."

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let todos = TodoCardStorage.shared.todoCards.filter { !$0.isCompleted }

        let overdue = todos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due < now
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let highPriority = todos.filter { $0.priority == .high && $0.dueDate == nil }

        var results: [String] = []

        if !overdue.isEmpty {
            results.append("Overdue:")
            for t in overdue.prefix(15) {
                results.append("  ⚠️ \"\(t.title)\" — due \(formatter.string(from: t.dueDate!))")
            }
        }

        if !highPriority.isEmpty {
            results.append("High priority (no due date):")
            for t in highPriority.prefix(10) {
                results.append("  🔴 \"\(t.title)\"")
            }
        }

        let incomplete = todos.count
        if overdue.isEmpty && highPriority.isEmpty {
            return ("No overdue or high-priority todos. \(incomplete) incomplete todo(s) total.")
        }
        return ("\(overdue.count) overdue, \(highPriority.count) high-priority, \(incomplete) incomplete total:\n" + results.joined(separator: "\n"))
    } }
}

// MARK: - Get Folder Contents Tool

/// Returns the contents of a specific folder.
struct GetFolderContentsTool: Tool {
    let name = "getFolderContents"
    let description = "Get the contents of a specific folder — lists all bookmarks, notes, events, todos, and contacts inside it."

    @Generable
    struct Arguments {
        @Guide(description: "The folder name to look inside")
        var folderName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let name = arguments.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = VaultFolderService.shared.folders

        guard let folder = folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) ?? folders.first(where: {
            $0.name.localizedStandardContains(name)
        }) else {
            let available = folders.map(\.name).joined(separator: ", ")
            return ("No folder named \"\(name)\". Available folders: \(available)")
        }

        let fid = folder.id
        var results: [String] = []

        let bookmarks = BookmarksStorage.shared.bookmarks.filter { $0.folderID == fid }
        for b in bookmarks.prefix(15) {
            results.append("Bookmark: \"\(b.title)\"")
        }
        if bookmarks.count > 15 { results.append("...and \(bookmarks.count - 15) more bookmarks") }

        let notes = NotesStorage.shared.notes.filter { $0.folderID == fid }
        for n in notes.prefix(10) {
            results.append("Note: \"\(n.title)\"")
        }

        let events = DateCardStorage.shared.dateCards.filter { $0.folderID == fid }
        for e in events.prefix(5) {
            results.append("Event: \"\(e.title)\"")
        }

        let todos = TodoCardStorage.shared.todoCards.filter { $0.folderID == fid }
        for t in todos.prefix(5) {
            let status = t.isCompleted ? "✓" : "○"
            results.append("Todo: \(status) \"\(t.title)\"")
        }

        let contacts = ContactStorage.shared.contacts.filter { $0.folderID == fid }
        for c in contacts.prefix(5) {
            results.append("Contact: \"\(c.displayName)\"")
        }

        let total = bookmarks.count + notes.count + events.count + todos.count + contacts.count
        if total == 0 {
            return ("Folder \"\(folder.name)\" is empty.")
        }
        return ("Folder \"\(folder.name)\" (\(total) items):\n" + results.joined(separator: "\n"))
    } }
}

// MARK: - Get Browser Sessions Tool

/// Returns saved browser sessions.
struct GetBrowserSessionsTool: Tool {
    let name = "getBrowserSessions"
    let description = "Get the user's saved browser sessions — groups of tabs saved from their browser."

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let sessions = BrowserSessionStorage.shared.sessions
        if sessions.isEmpty {
            return ("No saved browser sessions.")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var lines: [String] = []
        for s in sessions.sorted(by: { $0.createdAt > $1.createdAt }).prefix(10) {
            let tabCount = s.tabs.count
            let browser = s.sourceBrowserName ?? "Unknown"
            lines.append("\"\(s.name)\" — \(tabCount) tabs from \(browser) (\(formatter.string(from: s.createdAt)))")
        }
        if sessions.count > 10 { lines.append("...and \(sessions.count - 10) more sessions") }

        return ("Saved browser sessions (\(sessions.count) total):\n" + lines.joined(separator: "\n"))
    } }
}

// MARK: - Create Folder Tool

/// Creates a new folder in the vault.
struct CreateFolderTool: Tool {
    let name = "createFolder"
    let description = """
    Create a new folder in the user's vault. Can create root-level folders \
    or sub-folders inside an existing folder.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Name of the folder to create")
        var folderName: String

        @Guide(description: "Optional: name of the parent folder to create this inside. Leave empty for root level.")
        var parentFolderName: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let name = arguments.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Folder name cannot be empty." }

        var parentID: UUID?
        if let parentName = arguments.parentFolderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parentName.isEmpty {
            guard let parent = VaultFolderService.shared.folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(parentName) == .orderedSame
            }) else {
                let available = VaultFolderService.shared.folders.map(\.name).joined(separator: ", ")
                return "Parent folder \"\(parentName)\" not found. Available folders: \(available)"
            }
            parentID = parent.id
        }

        guard let folder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) else {
            return "Failed to create folder \"\(name)\". It may already exist."
        }

        let location = parentID != nil ? "inside \"\(arguments.parentFolderName ?? "")\"" : "at root level"
        return "Created folder \"\(folder.name)\" \(location)."
    } }
}

// MARK: - Move To Folder Tool

/// Moves items to a folder.
struct MoveToFolderTool: Tool {
    let name = "moveToFolder"
    let description = """
    Move bookmarks or notes into a folder. Search for items by title keyword, \
    then move matching items to the specified folder.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Keyword to find items to move (searches bookmark and note titles)")
        var searchQuery: String

        @Guide(description: "Name of the destination folder")
        var folderName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = arguments.folderName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let folder = VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }) ?? VaultFolderService.shared.folders.first(where: {
            $0.name.localizedStandardContains(folderName)
        }) else {
            let available = VaultFolderService.shared.folders.map(\.name).joined(separator: ", ")
            return "Folder \"\(folderName)\" not found. Available folders: \(available)"
        }

        var moved: [String] = []

        let matchingBookmarks = BookmarksStorage.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query) ||
            $0.urlString.localizedStandardContains(query)
        }
        for bookmark in matchingBookmarks {
            _ = BookmarksStorage.shared.assignBookmark(bookmark.id, toFolder: folder.id)
            moved.append("Bookmark: \"\(bookmark.title)\"")
        }

        let matchingNotes = NotesStorage.shared.notes.filter {
            $0.title.localizedStandardContains(query)
        }
        for note in matchingNotes {
            _ = NotesStorage.shared.assignNote(note.id, toFolder: folder.id)
            moved.append("Note: \"\(note.title)\"")
        }

        if moved.isEmpty {
            return "No items found matching \"\(query)\" to move."
        }
        return "Moved \(moved.count) item(s) to \"\(folder.name)\":\n" + moved.joined(separator: "\n")
    } }
}

// MARK: - Apply Tag Tool

/// Tags items with a label.
struct ApplyTagTool: Tool {
    let name = "applyTag"
    let description = """
    Apply a tag/label to items. Searches for items by keyword and applies \
    the specified tag. Creates the tag if it doesn't exist.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Keyword to find items to tag (searches titles)")
        var searchQuery: String

        @Guide(description: "Tag name to apply (will be created if it doesn't exist)")
        var tagName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagName = arguments.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tagName.isEmpty else { return "Tag name cannot be empty." }

        let label = CardLabelStorage.shared.findOrCreate(name: tagName)
        var tagged: [String] = []

        let matchingBookmarks = BookmarksStorage.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query) ||
            $0.urlString.localizedStandardContains(query)
        }
        for bookmark in matchingBookmarks {
            if !bookmark.labelIDs.contains(label.id) {
                _ = BookmarksStorage.shared.assignLabel(bookmark.id, labelID: label.id)
                tagged.append("Bookmark: \"\(bookmark.title)\"")
            }
        }

        let matchingNotes = NotesStorage.shared.notes.filter {
            $0.title.localizedStandardContains(query)
        }
        for note in matchingNotes {
            if !note.labelIDs.contains(label.id) {
                _ = NotesStorage.shared.assignLabel(note.id, labelID: label.id)
                tagged.append("Note: \"\(note.title)\"")
            }
        }

        if tagged.isEmpty {
            return "No untagged items found matching \"\(query)\"."
        }
        return "Tagged \(tagged.count) item(s) with \"\(label.name)\":\n" + tagged.joined(separator: "\n")
    } }
}

// MARK: - Rename Bookmark Tool

/// Renames a bookmark.
struct RenameBookmarkTool: Tool {
    let name = "renameBookmark"
    let description = "Rename a bookmark. Searches by current title and sets a new title."

    @Generable
    struct Arguments {
        @Guide(description: "Current title (or part of it) to find the bookmark")
        var currentTitle: String

        @Guide(description: "The new title to set")
        var newTitle: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let query = arguments.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = arguments.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return "New title cannot be empty." }

        let matches = BookmarksStorage.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query)
        }

        guard let bookmark = matches.first else {
            return "No bookmark found matching \"\(query)\"."
        }

        if matches.count > 1 {
            let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
            return "Multiple bookmarks match \"\(query)\": \(titles). Please be more specific."
        }

        let oldTitle = bookmark.title
        _ = BookmarksStorage.shared.updateDetails(
            for: bookmark.id,
            title: newTitle,
            notes: bookmark.notes,
            tags: bookmark.tags,
            labelIDs: bookmark.labelIDs
        )
        return "Renamed \"\(oldTitle)\" → \"\(newTitle)\"."
    } }
}

// MARK: - Find Similar Tool

/// Finds bookmarks similar to a given one using embeddings.
struct FindSimilarTool: Tool {
    let name = "findSimilar"
    let description = """
    Find bookmarks that are similar to a specific bookmark, using AI embeddings. \
    Searches by title keyword to identify the source bookmark, then finds related ones.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Title (or part of it) of the bookmark to find similar items for")
        var bookmarkTitle: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let query = arguments.bookmarkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmarks = BookmarksStorage.shared.bookmarks

        guard let bookmark = bookmarks.first(where: {
            $0.title.localizedStandardContains(query)
        }) else {
            return "No bookmark found matching \"\(query)\"."
        }

        let similarIDs = SimilarItemsService.findSimilar(
            to: bookmark.id,
            in: EmbeddingStore.shared,
            limit: 5
        )

        if similarIDs.isEmpty {
            return "No similar bookmarks found for \"\(bookmark.title)\". Embeddings may not be computed yet."
        }

        var results: [String] = []
        for id in similarIDs {
            if let similar = bookmarks.first(where: { $0.id == id }) {
                results.append("\"\(similar.title)\" (\(similar.urlString))")
            }
        }
        return "Bookmarks similar to \"\(bookmark.title)\":\n" + results.joined(separator: "\n")
    } }
}

// MARK: - Create Note Tool

/// Creates a new note with optional content.
struct CreateNoteTool: Tool {
    let name = "createNote"
    let description = """
    Create a new note in the user's vault. Can include title and content. \
    Optionally place it in a specific folder.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Title for the note")
        var title: String

        @Guide(description: "Content/body text for the note")
        var content: String

        @Guide(description: "Optional: folder name to place the note in")
        var folderName: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = arguments.content.trimmingCharacters(in: .whitespacesAndNewlines)

        var note = NotesStorage.shared.createNew(initialContent: content)
        // Update the title (createNew uses a default title)
        note.title = title.isEmpty ? "Untitled" : title
        NotesStorage.shared.save(note: note)

        // Move to folder if specified
        if let folderName = arguments.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folderName.isEmpty {
            if let folder = VaultFolderService.shared.folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
            }) {
                _ = NotesStorage.shared.assignNote(note.id, toFolder: folder.id)
                return "Created note \"\(note.title)\" in folder \"\(folder.name)\"."
            } else {
                return "Created note \"\(note.title)\" (folder \"\(folderName)\" not found — saved to root)."
            }
        }

        return "Created note \"\(note.title)\"."
    } }
}

// MARK: - Summarize Text Tool

/// Summarizes text and optionally saves it as a note.
struct SummarizeTextTool: Tool {
    let name = "summarizeText"
    let description = """
    Summarize a piece of text. Can optionally save the summary as a new note \
    in a specified folder. Use this when the user pastes text and asks for a summary.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The text to summarize")
        var text: String

        @Guide(description: "Optional: if true, save the summary as a new note")
        var saveAsNote: Bool?

        @Guide(description: "Optional: title for the note (if saving)")
        var noteTitle: String?

        @Guide(description: "Optional: folder name to save the note in")
        var folderName: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String {
        let text = arguments.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "No text provided to summarize." }

        let summary = await SummaryService.shared.summarize(articleText: text)
        guard let summary, !summary.isEmpty else {
            return "Could not generate a summary. The text may be too short or Apple Intelligence may be unavailable."
        }

        if arguments.saveAsNote == true {
            return await MainActor.run {
                let title = arguments.noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Summary"
                var note = NotesStorage.shared.createNew(initialContent: summary)
                note.title = title
                NotesStorage.shared.save(note: note)

                if let folderName = arguments.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !folderName.isEmpty,
                   let folder = VaultFolderService.shared.folders.first(where: {
                       $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
                   }) {
                    _ = NotesStorage.shared.assignNote(note.id, toFolder: folder.id)
                    return "Summary saved as note \"\(title)\" in folder \"\(folder.name)\":\n\n\(summary)"
                }
                return "Summary saved as note \"\(title)\":\n\n\(summary)"
            }
        }

        return "Summary:\n\n\(summary)"
    }
}

// MARK: - Add Bookmark Tool

/// Saves a new bookmark from a URL.
struct AddBookmarkTool: Tool {
    let name = "addBookmark"
    let description = """
    Save a new bookmark from a URL. Can optionally set a title, folder, and tags.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The URL to bookmark")
        var url: String

        @Guide(description: "Optional: title for the bookmark")
        var title: String?

        @Guide(description: "Optional: folder name to save the bookmark in")
        var folderName: String?

        @Guide(description: "Optional: tag name to apply to the bookmark")
        var tagName: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run {
        let urlString = arguments.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return "URL cannot be empty." }

        let title = arguments.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookmark = BookmarksStorage.shared.add(urlString: urlString, title: title) else {
            return "Failed to create bookmark for \"\(urlString)\"."
        }

        var actions: [String] = ["Saved bookmark \"\(bookmark.title)\""]

        // Move to folder
        if let folderName = arguments.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folderName.isEmpty,
           let folder = VaultFolderService.shared.folders.first(where: {
               $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
           }) {
            _ = BookmarksStorage.shared.assignBookmark(bookmark.id, toFolder: folder.id)
            actions.append("moved to folder \"\(folder.name)\"")
        }

        // Apply tag
        if let tagName = arguments.tagName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tagName.isEmpty {
            let label = CardLabelStorage.shared.findOrCreate(name: tagName)
            _ = BookmarksStorage.shared.assignLabel(bookmark.id, labelID: label.id)
            actions.append("tagged \"\(label.name)\"")
        }

        return actions.joined(separator: ", ") + "."
    } }
}
