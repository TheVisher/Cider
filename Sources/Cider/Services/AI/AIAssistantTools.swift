import Foundation
import FoundationModels

// MARK: - Count Items Tool

/// Counts items across all Cider entity types.
struct CountItemsTool: Tool {
    let name = "countItems"
    let description = """
    Count the user's items in Cider. Can count bookmarks, notes, events, \
    todos, contacts, folders, tags, or clipboard items. \
    Use itemType "all" for a summary of everything.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Type of item to count: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, or all")
        var itemType: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let type = arguments.itemType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case "bookmarks", "bookmark":
            let count = VaultBookmarkService.shared.bookmarks.count
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

        case "all", "everything", "summary":
            let bookmarks = VaultBookmarkService.shared.bookmarks.count
            let notes = NotesStorage.shared.notes.count
            let events = DateCardStorage.shared.dateCards.count
            let todos = TodoCardStorage.shared.todoCards.count
            let contacts = ContactStorage.shared.contacts.count
            let folders = VaultFolderService.shared.folders.count
            let tags = CardLabelStorage.shared.labels.count
            return ("""
            Library summary: \(bookmarks) bookmarks, \(notes) notes, \
            \(events) events, \(todos) todos, \(contacts) contacts, \
            \(folders) folders, \(tags) tags.
            """)

        default:
            return ("Unknown item type '\(type)'. Valid types: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, all.")
        }
    } } }
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

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.query.lowercased()
        var results: [String] = []

        let typeFilter = arguments.itemType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let searchAll = typeFilter == nil || typeFilter == "" || typeFilter == "all"

        // Search bookmarks
        if searchAll || typeFilter == "bookmarks" || typeFilter == "bookmark" {
            let matches = VaultBookmarkService.shared.bookmarks.filter { bookmark in
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

        // Search notes (title + content preview)
        if searchAll || typeFilter == "notes" || typeFilter == "note" {
            let matches = NotesStorage.shared.notes.filter { note in
                note.title.localizedStandardContains(query) ||
                note.contentPreview.localizedStandardContains(query)
            }
            for n in matches.prefix(10) {
                var desc = "Note: \"\(n.title)\""
                let preview = String(n.contentPreview.prefix(80))
                if !preview.isEmpty { desc += " — \(preview)" }
                results.append(desc)
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
    } } }
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

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let folders = VaultFolderService.shared.folders
        if folders.isEmpty {
            return ("No folders exist yet.")
        }

        let bookmarks = VaultBookmarkService.shared.bookmarks
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
    } } }
}

// MARK: - List Tags Tool

/// Lists all tags/labels with usage counts.
struct ListTagsTool: Tool {
    let name = "listTags"
    let description = "List all tags/labels the user has created, with how many items use each tag."

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
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
    } } }
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

        let recentBookmarks = VaultBookmarkService.shared.bookmarks
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

        let bookmarks = VaultBookmarkService.shared.bookmarks.filter { $0.labelIDs.contains(lid) }
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

        let bookmarks = VaultBookmarkService.shared.bookmarks.filter { $0.folderID == fid }
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

        let matchingBookmarks = VaultBookmarkService.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query) ||
            $0.urlString.localizedStandardContains(query)
        }
        for bookmark in matchingBookmarks {
            _ = VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: folder.id)
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

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagName = arguments.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tagName.isEmpty else { return "Tag name cannot be empty." }

        let label = CardLabelStorage.shared.findOrCreate(name: tagName)
        var tagged: [String] = []

        let matchingBookmarks = VaultBookmarkService.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query) ||
            $0.urlString.localizedStandardContains(query)
        }
        for bookmark in matchingBookmarks {
            if !bookmark.labelIDs.contains(label.id) {
                _ = VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: label.id)
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
    } } }
}

// MARK: - Remove Tag Tool

/// Removes a tag from items.
struct RemoveTagTool: Tool {
    let name = "removeTag"
    let description = "Remove a tag/label from items. Searches for items by keyword and removes the specified tag."

    @Generable
    struct Arguments {
        @Guide(description: "Keyword to find items to untag (searches titles)")
        var searchQuery: String

        @Guide(description: "Tag name to remove")
        var tagName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagName = arguments.tagName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let label = CardLabelStorage.shared.labels.first(where: {
            $0.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
        }) else {
            return "No tag named \"\(tagName)\" found."
        }

        var untagged: [String] = []
        let lid = label.id

        let matchingBookmarks = VaultBookmarkService.shared.bookmarks.filter {
            ($0.title.localizedStandardContains(query) || $0.urlString.localizedStandardContains(query))
            && $0.labelIDs.contains(lid)
        }
        for bookmark in matchingBookmarks {
            _ = VaultBookmarkService.shared.removeLabel(bookmark.id, labelID: lid)
            untagged.append("Bookmark: \"\(bookmark.title)\"")
        }

        let matchingNotes = NotesStorage.shared.notes.filter {
            $0.title.localizedStandardContains(query) && $0.labelIDs.contains(lid)
        }
        for note in matchingNotes {
            _ = NotesStorage.shared.removeLabel(note.id, labelID: lid)
            untagged.append("Note: \"\(note.title)\"")
        }

        if untagged.isEmpty {
            return "No items matching \"\(query)\" have the tag \"\(label.name)\"."
        }
        return "Removed tag \"\(label.name)\" from \(untagged.count) item(s):\n" + untagged.joined(separator: "\n")
    } } }
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

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = arguments.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return "New title cannot be empty." }

        let matches = VaultBookmarkService.shared.bookmarks.filter {
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
        _ = VaultBookmarkService.shared.updateDetails(
            for: bookmark.id,
            title: newTitle,
            notes: bookmark.notes,
            tags: bookmark.tags,
            labelIDs: bookmark.labelIDs
        )
        return "Renamed \"\(oldTitle)\" → \"\(newTitle)\"."
    } } }
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
        let bookmarks = VaultBookmarkService.shared.bookmarks

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

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
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
    } } }
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
            return await MainActor.run { MutationAuditContext.withSource(.agent) {
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
            } }
        }

        return "Summary:\n\n\(summary)"
    }
}

// MARK: - Add Bookmark Tool

/// Saves a new bookmark from a URL.
struct AddBookmarkTool: Tool {
    let name = "addBookmark"
    let description = """
    Save a new bookmark from a URL. Can optionally set a folder and tags. Only provide a title when the user explicitly gave the final title to preserve; otherwise omit it so Cider can enrich the bookmark title natively.
    """

    @Generable
    struct Arguments {
        @Guide(description: "The URL to bookmark")
        var url: String

        @Guide(description: "Optional: final title to preserve verbatim, only when the user explicitly supplied it")
        var title: String?

        @Guide(description: "Optional: folder name to save the bookmark in")
        var folderName: String?

        @Guide(description: "Optional: tag name to apply to the bookmark")
        var tagName: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let urlString = arguments.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return "URL cannot be empty." }

        let title = arguments.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bookmark = VaultBookmarkService.shared.add(urlString: urlString, title: title) else {
            return "Failed to create bookmark for \"\(urlString)\"."
        }

        var actions: [String] = ["Saved bookmark \"\(bookmark.title)\""]

        // Move to folder
        if let folderName = arguments.folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !folderName.isEmpty,
           let folder = VaultFolderService.shared.folders.first(where: {
               $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
           }) {
            _ = VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: folder.id)
            actions.append("moved to folder \"\(folder.name)\"")
        }

        // Apply tag
        if let tagName = arguments.tagName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tagName.isEmpty {
            let label = CardLabelStorage.shared.findOrCreate(name: tagName)
            _ = VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: label.id)
            actions.append("tagged \"\(label.name)\"")
        }

        return actions.joined(separator: ", ") + "."
    } } }
}

// MARK: - Get Current Item Tool

/// Returns details about whatever the user is currently viewing in Cider.
struct GetCurrentItemTool: Tool {
    let name = "getCurrentItem"
    let description = """
    Get full details about the item the user is currently viewing in Cider. \
    Use this when the user says "this bookmark", "this note", "summarize this", \
    "tell me about this", etc. without specifying which item.
    """

    @Generable
    struct Arguments {}

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let context = AIAssistantViewModel.shared.context

        if let bookmark = context.currentBookmark {
            // Find full bookmark data
            if let full = VaultBookmarkService.shared.bookmarks.first(where: {
                $0.urlString == bookmark.url
            }) {
                var details = "Currently viewing bookmark:"
                details += "\n  Title: \"\(full.title)\""
                details += "\n  URL: \(full.urlString)"
                if let summary = full.aiSummary { details += "\n  Summary: \(summary)" }
                if !full.notes.isEmpty { details += "\n  Notes: \(full.notes)" }
                if !full.tags.isEmpty { details += "\n  Tags: \(full.tags.joined(separator: ", "))" }
                let labels = full.labelIDs.compactMap { CardLabelStorage.shared.label(for: $0)?.name }
                if !labels.isEmpty { details += "\n  Labels: \(labels.joined(separator: ", "))" }
                if let folderID = full.folderID, let folder = VaultFolderService.shared.folder(for: folderID) {
                    details += "\n  Folder: \(folder.name)"
                }
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                details += "\n  Saved: \(formatter.string(from: full.createdAt))"
                return details
            }
            return "Currently viewing bookmark: \"\(bookmark.title)\" (\(bookmark.url))"
        }

        if let note = context.currentNote {
            return "Currently viewing note: \"\(note.title)\"\n  Content preview: \(note.excerpt)"
        }

        if let event = context.currentEvent {
            var details = "Currently viewing event: \"\(event.title)\" on \(event.date)"
            if !event.location.isEmpty { details += " at \(event.location)" }
            return details
        }

        if let contact = context.currentContact {
            var details = "Currently viewing contact: \"\(contact.name)\""
            if !contact.email.isEmpty { details += " (\(contact.email))" }
            return details
        }

        if let todo = context.currentTodo {
            return "Currently viewing todo: \"\(todo.title)\" (\(todo.status))"
        }

        if let folder = context.currentFolder {
            return "Currently browsing folder: \"\(folder.name)\" containing \(folder.itemCount) items."
        }

        return "The user is not currently viewing any specific item. They may be on the home screen or library view."
    } } }
}

// MARK: - Delete Item Tool

/// Deletes (trashes) a bookmark or note by title.
struct DeleteItemTool: Tool {
    let name = "deleteItem"
    let description = """
    Delete a bookmark or note by moving it to the trash. Searches by title keyword. \
    Items can be recovered from trash later.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Title (or part of it) of the item to delete")
        var searchQuery: String

        @Guide(description: "Type of item to delete: bookmark or note")
        var itemType: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = arguments.itemType.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if type == "bookmark" || type == "bookmarks" {
            let matches = VaultBookmarkService.shared.bookmarks.filter {
                $0.title.localizedStandardContains(query)
            }
            guard let bookmark = matches.first else {
                return "No bookmark found matching \"\(query)\"."
            }
            if matches.count > 1 {
                let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
                return "Multiple bookmarks match \"\(query)\": \(titles). Please be more specific."
            }
            let trashItem = VaultBookmarkService.shared.remove(bookmark)
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: trashItem))
            return "Moved bookmark \"\(bookmark.title)\" to trash. It can be recovered from the trash."
        }

        if type == "note" || type == "notes" {
            let matches = NotesStorage.shared.notes.filter {
                $0.title.localizedStandardContains(query)
            }
            guard let note = matches.first else {
                return "No note found matching \"\(query)\"."
            }
            if matches.count > 1 {
                let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
                return "Multiple notes match \"\(query)\": \(titles). Please be more specific."
            }
            let trashItem = NotesStorage.shared.delete(note: note)
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .note, trashItem: trashItem))
            return "Moved note \"\(note.title)\" to trash. It can be recovered from the trash."
        }

        return "Unknown item type '\(type)'. Use 'bookmark' or 'note'."
    } } }
}

// MARK: - Rename Folder Tool

/// Renames an existing folder.
struct RenameFolderTool: Tool {
    let name = "renameFolder"
    let description = "Rename an existing folder."

    @Generable
    struct Arguments {
        @Guide(description: "Current name of the folder to rename")
        var currentName: String

        @Guide(description: "New name for the folder")
        var newName: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let current = arguments.currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = arguments.newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return "New name cannot be empty." }

        guard let folder = VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(current) == .orderedSame
        }) else {
            let available = VaultFolderService.shared.folders.map(\.name).joined(separator: ", ")
            return "No folder named \"\(current)\". Available folders: \(available)"
        }

        let success = VaultFolderService.shared.renameFolder(folder.id, to: newName)
        if success {
            return "Renamed folder \"\(current)\" → \"\(newName)\"."
        }
        return "Failed to rename folder \"\(current)\". The name \"\(newName)\" may already be taken."
    } } }
}

// MARK: - Unfile Items Tool

/// Moves items out of a folder back to root (unfiled).
struct UnfileItemsTool: Tool {
    let name = "unfileItems"
    let description = """
    Remove items from their folder, making them unfiled (root level). \
    Searches by keyword and removes folder assignment.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Keyword to find items to unfile (searches titles)")
        var searchQuery: String
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var unfiled: [String] = []

        let matchingBookmarks = VaultBookmarkService.shared.bookmarks.filter {
            $0.title.localizedStandardContains(query) && $0.folderID != nil
        }
        for bookmark in matchingBookmarks {
            _ = VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: nil)
            unfiled.append("Bookmark: \"\(bookmark.title)\"")
        }

        let matchingNotes = NotesStorage.shared.notes.filter {
            $0.title.localizedStandardContains(query) && $0.folderID != nil
        }
        for note in matchingNotes {
            _ = NotesStorage.shared.assignNote(note.id, toFolder: nil)
            unfiled.append("Note: \"\(note.title)\"")
        }

        if unfiled.isEmpty {
            return "No filed items found matching \"\(query)\"."
        }
        return "Unfiled \(unfiled.count) item(s) (moved to root):\n" + unfiled.joined(separator: "\n")
    } } }
}

// MARK: - Create Reminder Tool

/// Creates a recurring or one-time reminder as a DateCard with surfacing rules.
struct CreateReminderTool: Tool {
    let name = "createReminder"
    let description = """
    Create a reminder or recurring event. Can be one-time or recurring \
    (daily, weekly, monthly, yearly). Specify when to be reminded with \
    minute offsets (e.g. 1440 = 1 day before, 60 = 1 hour before, 0 = at time).
    """

    @Generable
    struct Arguments {
        @Guide(description: "Title of the reminder (e.g. 'Pay Rent', 'Team Meeting')")
        var title: String

        @Guide(description: "Date in yyyy-MM-dd format (e.g. '2026-05-01')")
        var date: String

        @Guide(description: "Recurrence: 'daily', 'weekly', 'monthly', 'yearly', or empty for one-time")
        var frequency: String?

        @Guide(description: "How many minutes before the event to send the first reminder (e.g. 1440 for 1 day, 60 for 1 hour, 0 for at-time). Default 15.")
        var remindMinutesBefore: Int?

        @Guide(description: "Optional second reminder offset in minutes (e.g. 0 for at-time if first reminder is day-before)")
        var secondRemindMinutesBefore: Int?

        @Guide(description: "Whether the event lasts all day. Default true for date-only events.")
        var allDay: Bool?

        @Guide(description: "Optional location")
        var location: String?

        @Guide(description: "Optional notes or details")
        var details: String?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "Reminder title cannot be empty." }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        guard let date = df.date(from: arguments.date) else {
            return "Invalid date format. Use yyyy-MM-dd (e.g. '2026-05-01')."
        }

        let storage = DateCardStorage.shared
        var card = storage.createDateCard(title: title, startAt: date)
        guard storage.dateCards.contains(where: { $0.id == card.id }) else {
            return "Failed to create reminder (disk write failed)."
        }

        card.allDay = arguments.allDay ?? true

        if let loc = arguments.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            card.location = loc
        }
        if let det = arguments.details?.trimmingCharacters(in: .whitespacesAndNewlines), !det.isEmpty {
            card.details = det
        }

        // Recurrence
        if let freqStr = arguments.frequency?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !freqStr.isEmpty {
            let freq: DateCardRecurrenceFrequency
            switch freqStr {
            case "daily": freq = .daily
            case "weekly": freq = .weekly
            case "monthly": freq = .monthly
            case "yearly": freq = .yearly
            default: return "Invalid frequency '\(freqStr)'. Use daily, weekly, monthly, or yearly."
            }
            card.recurrenceRule = DateCardRecurrenceRule(frequency: freq)
        }

        // Reminder offsets
        let firstOffset = arguments.remindMinutesBefore ?? 15
        card.rules.append(SurfacingRule(type: .remindBeforeMinutes, integerValue: firstOffset))
        if let second = arguments.secondRemindMinutesBefore {
            card.rules.append(SurfacingRule(type: .remindBeforeMinutes, integerValue: second))
        }

        _ = storage.updateDateCard(card)

        // Trigger reconciliation so notifications are scheduled immediately
        ReminderReconciler.shared.reconcile()

        let recurring = card.recurrenceRule != nil ? " (recurring \(card.recurrenceRule!.frequency.rawValue))" : ""
        let remindDesc = card.rules
            .filter { $0.type == .remindBeforeMinutes }
            .compactMap(\.integerValue)
            .map { $0 == 0 ? "at time" : "\($0) min before" }
            .joined(separator: ", ")
        return "Created reminder: \"\(title)\" on \(arguments.date)\(recurring). Reminders: \(remindDesc)."
    } } }
}

// MARK: - Cancel Reminder Tool

/// Cancels or disables reminders on a DateCard.
struct CancelReminderTool: Tool {
    let name = "cancelReminder"
    let description = """
    Cancel a reminder by title. Can either delete the entire event/reminder \
    or just disable its notification rules.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Title or partial title of the reminder to cancel")
        var title: String

        @Guide(description: "If true, delete the entire event. If false, just disable reminder notifications. Default false.")
        var deleteEntirely: Bool?
    }

    nonisolated func call(arguments: Arguments) async throws -> String { await MainActor.run { MutationAuditContext.withSource(.agent) {
        let query = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return "Reminder title cannot be empty." }

        let storage = DateCardStorage.shared
        guard var card = storage.dateCards.first(where: {
            $0.title.lowercased().contains(query)
        }) else {
            return "No reminder found matching \"\(arguments.title)\"."
        }

        if arguments.deleteEntirely == true {
            if let trashItem = storage.deleteDateCard(card.id) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                DateCardNotificationService.shared.cancelNotification(for: card.id)
                return "Deleted reminder: \"\(card.title)\" (moved to trash)."
            }
            return "Failed to delete reminder."
        }

        // Disable all reminder rules
        for i in card.rules.indices where card.rules[i].type == .remindBeforeMinutes {
            card.rules[i].isEnabled = false
        }
        _ = storage.updateDateCard(card)
        DateCardNotificationService.shared.cancelNotification(for: card.id)
        return "Disabled reminders for \"\(card.title)\". The event still exists but won't send notifications."
    } } }
}
