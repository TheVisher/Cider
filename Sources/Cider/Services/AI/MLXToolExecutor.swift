import Foundation
import os.log

/// Executes Cider tools by name, reusing the same storage queries as the
/// Foundation Models tool structs in `AIAssistantTools.swift`.
@MainActor
enum MLXToolExecutor {

    private static let logger = Logger(subsystem: "com.cider.app", category: "MLXToolExecutor")

    /// Execute a tool and return its string result.
    static func execute(name: String, arguments: [String: Any]) -> String {
        logger.info("Executing tool: \(name, privacy: .public)")

        switch name {

        // MARK: - Read-only tools

        case "countItems":
            return countItems(arguments)
        case "searchItems":
            return searchItems(arguments)
        case "listFolders":
            return listFolders()
        case "listTags":
            return listTags()
        case "getRecentItems":
            return getRecentItems(arguments)
        case "getItemsByTag":
            return getItemsByTag(arguments)
        case "getUpcomingEvents":
            return getUpcomingEvents(arguments)
        case "getOverdueTodos":
            return getOverdueTodos()
        case "getFolderContents":
            return getFolderContents(arguments)
        case "getCurrentItem":
            return getCurrentItem()
        case "findSimilar":
            return findSimilar(arguments)

        // MARK: - Mutating tools

        case "createFolder":
            return createFolder(arguments)
        case "moveToFolder":
            return moveToFolder(arguments)
        case "applyTag":
            return applyTag(arguments)
        case "removeTag":
            return removeTag(arguments)
        case "renameBookmark":
            return renameBookmark(arguments)
        case "createNote":
            return createNote(arguments)
        case "addBookmark":
            return addBookmark(arguments)
        case "deleteItem":
            return deleteItem(arguments)
        case "renameFolder":
            return renameFolder(arguments)
        case "unfileItems":
            return unfileItems(arguments)
        case "createReminder":
            return createReminder(arguments)
        case "cancelReminder":
            return cancelReminder(arguments)

        // MARK: - Special

        case "summarizeText":
            return "Summarization requires Apple Intelligence and is not available with the local model."

        default:
            logger.warning("Unknown tool: \(name, privacy: .public)")
            return "Unknown tool \"\(name)\"."
        }
    }

    // MARK: - Argument helpers

    private static func string(_ key: String, from args: [String: Any]) -> String {
        (args[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func optString(_ key: String, from args: [String: Any]) -> String? {
        guard let val = args[key] as? String else { return nil }
        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ key: String, from args: [String: Any], default fallback: Int) -> Int {
        if let n = args[key] as? Int { return n }
        if let n = args[key] as? Double { return Int(n) }
        if let s = args[key] as? String, let n = Int(s) { return n }
        return fallback
    }

    // MARK: - Tool implementations

    private static func countItems(_ args: [String: Any]) -> String {
        let type = string("itemType", from: args).lowercased()

        switch type {
        case "bookmarks", "bookmark":
            return "The user has \(VaultBookmarkService.shared.bookmarks.count) bookmarks."
        case "notes", "note":
            return "The user has \(NotesStorage.shared.notes.count) notes."
        case "events", "event", "datecards", "datecard", "date cards":
            let count = DateCardStorage.shared.dateCards.count
            let upcoming = DateCardStorage.shared.dateCards.filter { $0.startAt > Date() && !$0.isCompleted }.count
            return "The user has \(count) events (\(upcoming) upcoming)."
        case "todos", "todo", "tasks", "task":
            let all = TodoCardStorage.shared.todoCards
            let incomplete = all.filter { !$0.isCompleted }.count
            return "The user has \(all.count) todos (\(incomplete) incomplete)."
        case "contacts", "contact":
            return "The user has \(ContactStorage.shared.contacts.count) contacts."
        case "folders", "folder":
            return "The user has \(VaultFolderService.shared.folders.count) folders."
        case "tags", "tag", "labels", "label":
            return "The user has \(CardLabelStorage.shared.labels.count) tags/labels."
        case "clipboard":
            return "The clipboard history has \(ClipboardStorage.shared.items.count) items."
        case "all", "everything", "summary":
            let b = VaultBookmarkService.shared.bookmarks.count
            let n = NotesStorage.shared.notes.count
            let e = DateCardStorage.shared.dateCards.count
            let t = TodoCardStorage.shared.todoCards.count
            let c = ContactStorage.shared.contacts.count
            let f = VaultFolderService.shared.folders.count
            let l = CardLabelStorage.shared.labels.count
            return "Library summary: \(b) bookmarks, \(n) notes, \(e) events, \(t) todos, \(c) contacts, \(f) folders, \(l) tags."
        default:
            return "Unknown item type '\(type)'. Valid types: bookmarks, notes, events, todos, contacts, folders, tags, clipboard, all."
        }
    }

    private static func searchItems(_ args: [String: Any]) -> String {
        CiderAgentItemSearchFormatter.searchResponseOrMessage(
            query: string("query", from: args),
            itemType: optString("itemType", from: args)
        )
    }

    private static func listFolders() -> String {
        let folders = VaultFolderService.shared.folders
        if folders.isEmpty { return "No folders exist yet." }

        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let events = DateCardStorage.shared.dateCards
        let todos = TodoCardStorage.shared.todoCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files

        var lines: [String] = []
        for folder in folders.sorted(by: { $0.relativePath < $1.relativePath }) {
            let fid = folder.id
            let bCount = bookmarks.filter { $0.folderID == fid }.count
            let nCount = notes.filter { $0.folderID == fid }.count
            let eCount = events.filter { $0.folderID == fid }.count
            let tCount = todos.filter { $0.folderID == fid }.count
            let cCount = contacts.filter { $0.folderID == fid }.count
            let fCount = files.filter { $0.folderID == fid }.count
            let childFolderCount = folders.filter { $0.parentRelativePath == folder.relativePath }.count
            let summary = FolderCardSummary.build(
                directItemCount: bCount + nCount + eCount + tCount + cCount + fCount,
                childFolderCount: childFolderCount
            )
            lines.append("\(folder.name) (\(summary.contentDescription))")
        }
        return "Folders:\n" + lines.joined(separator: "\n")
    }

    private static func listTags() -> String {
        let labels = CardLabelStorage.shared.labels
        if labels.isEmpty { return "No tags/labels exist yet." }

        var lines: [String] = []
        for label in labels.sorted(by: { $0.name < $1.name }) {
            let count = CardLabelStorage.shared.itemCount(for: label.id)
            lines.append("\(label.name) (\(count) items)")
        }
        return "Tags:\n" + lines.joined(separator: "\n")
    }

    private static func getRecentItems(_ args: [String: Any]) -> String {
        let days = integer("days", from: args, default: 7)
        let threshold = Date().addingTimeInterval(-Double(days) * 86400)
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        var results: [String] = []

        let recentBookmarks = VaultBookmarkService.shared.bookmarks
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for b in recentBookmarks.prefix(10) {
            results.append("Bookmark: \"\(b.title)\" — \(fmt.string(from: b.createdAt))")
        }
        if recentBookmarks.count > 10 { results.append("...and \(recentBookmarks.count - 10) more bookmarks") }

        let recentNotes = NotesStorage.shared.notes
            .filter { $0.modifiedAt >= threshold }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        for n in recentNotes.prefix(10) {
            results.append("Note: \"\(n.title)\" — \(fmt.string(from: n.modifiedAt))")
        }
        if recentNotes.count > 10 { results.append("...and \(recentNotes.count - 10) more notes") }

        let recentEvents = DateCardStorage.shared.dateCards
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for e in recentEvents.prefix(5) {
            results.append("Event: \"\(e.title)\" — \(fmt.string(from: e.startAt))")
        }

        let recentTodos = TodoCardStorage.shared.todoCards
            .filter { $0.createdAt >= threshold }
            .sorted { $0.createdAt > $1.createdAt }
        for t in recentTodos.prefix(5) {
            let status = t.isCompleted ? "done" : "incomplete"
            results.append("Todo: \"\(t.title)\" (\(status))")
        }

        if results.isEmpty {
            return "No items created or modified in the last \(days) day(s)."
        }
        return "Items from the last \(days) day(s):\n" + results.joined(separator: "\n")
    }

    private static func getItemsByTag(_ args: [String: Any]) -> String {
        let tagName = string("tagName", from: args)
        guard let label = CardLabelStorage.shared.labels.first(where: {
            $0.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
        }) else {
            let partial = CardLabelStorage.shared.labels.filter {
                $0.name.localizedStandardContains(tagName)
            }
            if partial.isEmpty {
                return "No tag named \"\(tagName)\" found. Available tags: \(CardLabelStorage.shared.labels.map(\.name).joined(separator: ", "))"
            }
            return "No exact match for \"\(tagName)\". Did you mean: \(partial.map(\.name).joined(separator: ", "))?"
        }

        let lid = label.id
        var results: [String] = []

        let bookmarks = VaultBookmarkService.shared.bookmarks.filter { $0.labelIDs.contains(lid) }
        for b in bookmarks.prefix(10) { results.append("Bookmark: \"\(b.title)\"") }
        if bookmarks.count > 10 { results.append("...and \(bookmarks.count - 10) more bookmarks") }

        let notes = NotesStorage.shared.notes.filter { $0.labelIDs.contains(lid) }
        for n in notes.prefix(10) { results.append("Note: \"\(n.title)\"") }

        let events = DateCardStorage.shared.dateCards.filter { $0.labelIDs.contains(lid) }
        for e in events.prefix(5) { results.append("Event: \"\(e.title)\"") }

        let todos = TodoCardStorage.shared.todoCards.filter { $0.labelIDs.contains(lid) }
        for t in todos.prefix(5) { results.append("Todo: \"\(t.title)\"") }

        let contacts = ContactStorage.shared.contacts.filter { $0.labelIDs.contains(lid) }
        for c in contacts.prefix(5) { results.append("Contact: \"\(c.displayName)\"") }

        let total = bookmarks.count + notes.count + events.count + todos.count + contacts.count
        if total == 0 {
            return "Tag \"\(label.name)\" exists but has no items."
        }
        return "\(total) items tagged \"\(label.name)\":\n" + results.joined(separator: "\n")
    }

    private static func getUpcomingEvents(_ args: [String: Any]) -> String {
        let days = integer("days", from: args, default: 7)
        let now = Date()
        let end = now.addingTimeInterval(Double(days) * 86400)
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short

        let upcoming = DateCardStorage.shared.dateCards
            .filter { $0.startAt >= now && $0.startAt <= end && !$0.isCompleted }
            .sorted { $0.startAt < $1.startAt }

        if upcoming.isEmpty {
            return "No upcoming events in the next \(days) day(s)."
        }

        var lines: [String] = []
        for e in upcoming.prefix(20) {
            var desc = "\"\(e.title)\" — \(fmt.string(from: e.startAt))"
            if !e.location.isEmpty { desc += " at \(e.location)" }
            if e.allDay { desc += " (all day)" }
            lines.append(desc)
        }
        if upcoming.count > 20 { lines.append("...and \(upcoming.count - 20) more") }
        return "Upcoming events (\(upcoming.count) total):\n" + lines.joined(separator: "\n")
    }

    private static func getOverdueTodos() -> String {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateStyle = .medium

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
                results.append("  \"\(t.title)\" — due \(fmt.string(from: t.dueDate!))")
            }
        }
        if !highPriority.isEmpty {
            results.append("High priority (no due date):")
            for t in highPriority.prefix(10) {
                results.append("  \"\(t.title)\"")
            }
        }

        if overdue.isEmpty && highPriority.isEmpty {
            return "No overdue or high-priority todos. \(todos.count) incomplete todo(s) total."
        }
        return "\(overdue.count) overdue, \(highPriority.count) high-priority, \(todos.count) incomplete total:\n" + results.joined(separator: "\n")
    }

    private static func getFolderContents(_ args: [String: Any]) -> String {
        let name = string("folderName", from: args)
        let folders = VaultFolderService.shared.folders

        guard let folder = folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) ?? folders.first(where: {
            $0.name.localizedStandardContains(name)
        }) else {
            return "No folder named \"\(name)\". Available folders: \(folders.map(\.name).joined(separator: ", "))"
        }

        let fid = folder.id
        var results: [String] = []

        let bookmarks = VaultBookmarkService.shared.bookmarks.filter { $0.folderID == fid }
        for b in bookmarks.prefix(15) { results.append("Bookmark: \"\(b.title)\"") }
        if bookmarks.count > 15 { results.append("...and \(bookmarks.count - 15) more bookmarks") }

        let notes = NotesStorage.shared.notes.filter { $0.folderID == fid }
        for n in notes.prefix(10) { results.append("Note: \"\(n.title)\"") }

        let events = DateCardStorage.shared.dateCards.filter { $0.folderID == fid }
        for e in events.prefix(5) { results.append("Event: \"\(e.title)\"") }

        let todos = TodoCardStorage.shared.todoCards.filter { $0.folderID == fid }
        for t in todos.prefix(5) {
            let status = t.isCompleted ? "done" : "incomplete"
            results.append("Todo: \"\(t.title)\" (\(status))")
        }

        let contacts = ContactStorage.shared.contacts.filter { $0.folderID == fid }
        for c in contacts.prefix(5) { results.append("Contact: \"\(c.displayName)\"") }

        let total = bookmarks.count + notes.count + events.count + todos.count + contacts.count
        if total == 0 { return "Folder \"\(folder.name)\" is empty." }
        return "Folder \"\(folder.name)\" (\(total) items):\n" + results.joined(separator: "\n")
    }

    private static func getCurrentItem() -> String {
        let context = AIAssistantViewModel.shared.context

        if let bookmark = context.currentBookmark {
            if let full = VaultBookmarkService.shared.bookmarks.first(where: { $0.urlString == bookmark.url }) {
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
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                details += "\n  Saved: \(fmt.string(from: full.createdAt))"
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
            let summary = FolderCardSummary.build(
                directItemCount: folder.directItemCount,
                childFolderCount: folder.childFolderCount
            )
            return "Currently browsing folder: \"\(folder.name)\" containing \(summary.contentDescription)."
        }
        return "The user is not currently viewing any specific item."
    }

    private static func findSimilar(_ args: [String: Any]) -> String {
        let query = string("bookmarkTitle", from: args)
        let bookmarks = VaultBookmarkService.shared.bookmarks

        guard let bookmark = bookmarks.first(where: { $0.title.localizedStandardContains(query) }) else {
            return "No bookmark found matching \"\(query)\"."
        }

        let similarIDs = SimilarItemsService.findSimilar(to: bookmark.id, in: EmbeddingStore.shared, limit: 5)
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
    }

    // MARK: - Mutating tools

    private static func createFolder(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let name = string("folderName", from: args)
        guard !name.isEmpty else { return "Folder name cannot be empty." }

        var parentID: UUID?
        if let parentName = optString("parentFolderName", from: args) {
            guard let parent = VaultFolderService.shared.folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(parentName) == .orderedSame
            }) else {
                return "Parent folder \"\(parentName)\" not found. Available folders: \(VaultFolderService.shared.folders.map(\.name).joined(separator: ", "))"
            }
            parentID = parent.id
        }

        guard let folder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) else {
            return "Failed to create folder \"\(name)\". It may already exist."
        }
        let location = parentID != nil ? "inside \"\(optString("parentFolderName", from: args) ?? "")\"" : "at root level"
        return "Created folder \"\(folder.name)\" \(location)."
        }
    }

    private static func moveToFolder(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("searchQuery", from: args)
        let folderName = string("folderName", from: args)

        guard let folder = VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
        }) ?? VaultFolderService.shared.folders.first(where: {
            $0.name.localizedStandardContains(folderName)
        }) else {
            return "Folder \"\(folderName)\" not found. Available folders: \(VaultFolderService.shared.folders.map(\.name).joined(separator: ", "))"
        }

        var moved: [String] = []
        var movedCount = 0

        for bookmark in VaultBookmarkService.shared.bookmarks.filter({
            $0.title.localizedStandardContains(query) || $0.urlString.localizedStandardContains(query)
        }) {
            do {
                _ = try CiderRoutingDecisionService().moveBookmarkManually(
                    itemID: bookmark.id,
                    target: CiderRoutingDecisionTarget(
                        kind: "folder",
                        name: folder.name,
                        relativePath: folder.relativePath,
                        folderID: folder.id
                    ),
                    reason: "Moved by agent tool.",
                    actor: "agent",
                    source: "agent.move_to_folder",
                    bookmarkService: VaultBookmarkService.shared
                )
                moved.append("Bookmark: \"\(bookmark.title)\"")
                movedCount += 1
            } catch {
                moved.append("Bookmark failed: \"\(bookmark.title)\" (\(error.localizedDescription))")
            }
        }
        for note in NotesStorage.shared.notes.filter({ $0.title.localizedStandardContains(query) }) {
            if NotesStorage.shared.assignNote(note.id, toFolder: folder.id) {
                moved.append("Note: \"\(note.title)\"")
                movedCount += 1
            } else {
                moved.append("Note failed: \"\(note.title)\" (assignment failed)")
            }
        }

        if moved.isEmpty { return "No items found matching \"\(query)\" to move." }
        return "Moved \(movedCount) item(s) to \"\(folder.name)\":\n" + moved.joined(separator: "\n")
        }
    }

    private static func applyTag(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("searchQuery", from: args)
        let tagName = string("tagName", from: args)
        guard !tagName.isEmpty else { return "Tag name cannot be empty." }

        let label = CardLabelStorage.shared.findOrCreate(name: tagName)
        var tagged: [String] = []

        for bookmark in VaultBookmarkService.shared.bookmarks.filter({
            $0.title.localizedStandardContains(query) || $0.urlString.localizedStandardContains(query)
        }) {
            if !bookmark.labelIDs.contains(label.id) {
                _ = VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: label.id)
                tagged.append("Bookmark: \"\(bookmark.title)\"")
            }
        }
        for note in NotesStorage.shared.notes.filter({ $0.title.localizedStandardContains(query) }) {
            if !note.labelIDs.contains(label.id) {
                _ = NotesStorage.shared.assignLabel(note.id, labelID: label.id)
                tagged.append("Note: \"\(note.title)\"")
            }
        }

        if tagged.isEmpty { return "No untagged items found matching \"\(query)\"." }
        return "Tagged \(tagged.count) item(s) with \"\(label.name)\":\n" + tagged.joined(separator: "\n")
        }
    }

    private static func removeTag(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("searchQuery", from: args)
        let tagName = string("tagName", from: args)

        guard let label = CardLabelStorage.shared.labels.first(where: {
            $0.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame
        }) else {
            return "No tag named \"\(tagName)\" found."
        }

        let lid = label.id
        var untagged: [String] = []

        for bookmark in VaultBookmarkService.shared.bookmarks.filter({
            ($0.title.localizedStandardContains(query) || $0.urlString.localizedStandardContains(query))
            && $0.labelIDs.contains(lid)
        }) {
            _ = VaultBookmarkService.shared.removeLabel(bookmark.id, labelID: lid)
            untagged.append("Bookmark: \"\(bookmark.title)\"")
        }
        for note in NotesStorage.shared.notes.filter({
            $0.title.localizedStandardContains(query) && $0.labelIDs.contains(lid)
        }) {
            _ = NotesStorage.shared.removeLabel(note.id, labelID: lid)
            untagged.append("Note: \"\(note.title)\"")
        }

        if untagged.isEmpty { return "No items matching \"\(query)\" have the tag \"\(label.name)\"." }
        return "Removed tag \"\(label.name)\" from \(untagged.count) item(s):\n" + untagged.joined(separator: "\n")
        }
    }

    private static func renameBookmark(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("currentTitle", from: args)
        let newTitle = string("newTitle", from: args)
        guard !newTitle.isEmpty else { return "New title cannot be empty." }

        let matches = VaultBookmarkService.shared.bookmarks.filter { $0.title.localizedStandardContains(query) }
        guard let bookmark = matches.first else { return "No bookmark found matching \"\(query)\"." }
        if matches.count > 1 {
            let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
            return "Multiple bookmarks match \"\(query)\": \(titles). Please be more specific."
        }

        let oldTitle = bookmark.title
        _ = VaultBookmarkService.shared.updateDetails(
            for: bookmark.id, title: newTitle, notes: bookmark.notes,
            tags: bookmark.tags, labelIDs: bookmark.labelIDs
        )
        return "Renamed \"\(oldTitle)\" to \"\(newTitle)\"."
        }
    }

    private static func createNote(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let title = string("title", from: args)
        let content = string("content", from: args)
        let requestedFolderName = optString("folderName", from: args)
        let targetFolder = optString("folderName", from: args).flatMap { folderName in
            VaultFolderService.shared.folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
            })
        }

        do {
            let result = try CiderCaptureService().addNoteCapture(
                title: title,
                content: content,
                folderID: targetFolder?.id,
                sourceContext: CaptureSourceContext(
                    surface: "mlx_tool",
                    originalText: content,
                    metadata: [
                        "tool": "createNote",
                        "requested_title": title,
                    ]
                )
            )
            let finalTitle = result.item.title
            if let folderName = requestedFolderName, targetFolder == nil {
                return AgentCaptureToolResultFormatter.jsonString(
                    message: "Created note \"\(finalTitle)\" (folder \"\(folderName)\" not found, saved for review).",
                    captureResult: result,
                    additionalPartialFailures: [
                        AgentCaptureToolResultFormatter.partialFailure(
                            status: "requested_folder_not_found",
                            reason: "Folder \"\(folderName)\" was not found, so the note stayed in its capture destination."
                        )
                    ]
                )
            }
            if let targetFolder {
                if result.partialSuccess?.status == "assignment_failed" {
                    return AgentCaptureToolResultFormatter.jsonString(
                        message: "Created note \"\(finalTitle)\" but failed to move it to folder \"\(targetFolder.name)\".",
                        captureResult: result
                    )
                }
                return AgentCaptureToolResultFormatter.jsonString(
                    message: "Created note \"\(finalTitle)\" in folder \"\(targetFolder.name)\".",
                    captureResult: result
                )
            }
            return AgentCaptureToolResultFormatter.jsonString(
                message: "Created note \"\(finalTitle)\".",
                captureResult: result
            )
        } catch {
            return "Failed to create note: \(error.localizedDescription)"
        }
        }
    }

    private static func addBookmark(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let urlString = string("url", from: args)
        guard !urlString.isEmpty else { return "URL cannot be empty." }

        let title = optString("title", from: args)
        let requestedFolderName = optString("folderName", from: args)
        let targetFolder = requestedFolderName.flatMap { folderName in
            VaultFolderService.shared.folders.first {
                $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
            }
        }
        guard let adapterResult = try? CiderBookmarkCaptureAdapter()
            .addURLBookmark(
                urlString: urlString,
                title: title,
                folderID: targetFolder?.id,
                sourceContext: CaptureSourceContext(
                    surface: "mlx_tool",
                    originalText: urlString,
                    metadata: ["tool": "createBookmark"]
                )
            ) else {
            return "Failed to create bookmark for \"\(urlString)\"."
        }
        let bookmark = adapterResult.bookmark

        var actions: [String] = ["Saved bookmark \"\(bookmark.title)\""]
        var partialFailures: [[String: Any]] = []

        if let targetFolder {
            actions.append("moved to folder \"\(targetFolder.name)\"")
        } else if let requestedFolderName {
            actions.append("folder \"\(requestedFolderName)\" not found")
            partialFailures.append(
                AgentCaptureToolResultFormatter.partialFailure(
                    status: "requested_folder_not_found",
                    reason: "Folder \"\(requestedFolderName)\" was not found, so the bookmark stayed in its capture destination."
                )
            )
        }
        if let tagName = optString("tagName", from: args) {
            let label = CardLabelStorage.shared.findOrCreate(name: tagName)
            if VaultBookmarkService.shared.assignLabel(bookmark.id, labelID: label.id) {
                actions.append("tagged \"\(label.name)\"")
            } else {
                partialFailures.append(
                    AgentCaptureToolResultFormatter.partialFailure(
                        status: "tag_assignment_failed",
                        reason: "Tag \"\(label.name)\" could not be assigned to the bookmark."
                    )
                )
            }
        }

        return AgentCaptureToolResultFormatter.jsonString(
            message: actions.joined(separator: ", ") + ".",
            captureResult: adapterResult.captureResult,
            finalBookmark: bookmark,
            additionalPartialFailures: partialFailures
        )
        }
    }

    private static func deleteItem(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("searchQuery", from: args)
        let type = string("itemType", from: args).lowercased()

        if type == "bookmark" || type == "bookmarks" {
            let matches = VaultBookmarkService.shared.bookmarks.filter { $0.title.localizedStandardContains(query) }
            guard let bookmark = matches.first else { return "No bookmark found matching \"\(query)\"." }
            if matches.count > 1 {
                let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
                return "Multiple bookmarks match \"\(query)\": \(titles). Please be more specific."
            }
            let trashItem = VaultBookmarkService.shared.remove(bookmark)
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: trashItem))
            return "Moved bookmark \"\(bookmark.title)\" to trash."
        }

        if type == "note" || type == "notes" {
            let matches = NotesStorage.shared.notes.filter { $0.title.localizedStandardContains(query) }
            guard let note = matches.first else { return "No note found matching \"\(query)\"." }
            if matches.count > 1 {
                let titles = matches.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
                return "Multiple notes match \"\(query)\": \(titles). Please be more specific."
            }
            let trashItem = NotesStorage.shared.delete(note: note)
            CiderUndoManager.shared.record(.deletedToTrash(itemType: .note, trashItem: trashItem))
            return "Moved note \"\(note.title)\" to trash."
        }

        return "Unknown item type '\(type)'. Use 'bookmark' or 'note'."
        }
    }

    private static func renameFolder(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let current = string("currentName", from: args)
        let newName = string("newName", from: args)
        guard !newName.isEmpty else { return "New name cannot be empty." }

        guard let folder = VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(current) == .orderedSame
        }) else {
            return "No folder named \"\(current)\". Available folders: \(VaultFolderService.shared.folders.map(\.name).joined(separator: ", "))"
        }

        let success = VaultFolderService.shared.renameFolder(folder.id, to: newName)
        if success { return "Renamed folder \"\(current)\" to \"\(newName)\"." }
        return "Failed to rename folder \"\(current)\". The name \"\(newName)\" may already be taken."
        }
    }

    private static func unfileItems(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("searchQuery", from: args)
        var unfiled: [String] = []
        var unfiledCount = 0

        for bookmark in VaultBookmarkService.shared.bookmarks.filter({
            $0.title.localizedStandardContains(query) && $0.folderID != nil
        }) {
            do {
                _ = try CiderRoutingDecisionService().moveBookmarkManually(
                    itemID: bookmark.id,
                    target: CiderRoutingDecisionTarget(
                        kind: "inbox",
                        name: "Inbox/Bookmarks",
                        relativePath: "Inbox/Bookmarks",
                        folderID: nil
                    ),
                    reason: "Unfiled by agent tool.",
                    actor: "agent",
                    source: "agent.unfile",
                    bookmarkService: VaultBookmarkService.shared
                )
                unfiled.append("Bookmark: \"\(bookmark.title)\"")
                unfiledCount += 1
            } catch {
                unfiled.append("Bookmark failed: \"\(bookmark.title)\" (\(error.localizedDescription))")
            }
        }
        for note in NotesStorage.shared.notes.filter({
            $0.title.localizedStandardContains(query) && $0.folderID != nil
        }) {
            if NotesStorage.shared.assignNote(note.id, toFolder: nil) {
                unfiled.append("Note: \"\(note.title)\"")
                unfiledCount += 1
            } else {
                unfiled.append("Note failed: \"\(note.title)\" (assignment failed)")
            }
        }

        if unfiled.isEmpty { return "No filed items found matching \"\(query)\"." }
        return "Unfiled \(unfiledCount) item(s) (moved to root):\n" + unfiled.joined(separator: "\n")
        }
    }

    // MARK: - Create Reminder

    private static func createReminder(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let title = string("title", from: args)
        guard !title.isEmpty else {
            return AgentCaptureToolResultFormatter.failureJsonString(
                message: "Reminder title is required.",
                code: "missing_reminder_title"
            )
        }
        let dateStr = string("date", from: args)
        guard !dateStr.isEmpty else {
            return AgentCaptureToolResultFormatter.failureJsonString(
                message: "Date is required (yyyy-MM-dd format).",
                code: "missing_reminder_date"
            )
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        guard let date = df.date(from: dateStr) else {
            return AgentCaptureToolResultFormatter.failureJsonString(
                message: "Invalid date format. Use yyyy-MM-dd (e.g. '2026-05-01').",
                code: "invalid_reminder_date"
            )
        }

        let loc = string("location", from: args)
        let det = string("details", from: args)
        let recurrenceFrequency: DateCardRecurrenceFrequency?
        switch AgentReminderToolSupport.recurrenceFrequency(from: string("frequency", from: args)) {
        case .valid(let parsed):
            recurrenceFrequency = parsed
        case .invalid(let invalid):
            return AgentCaptureToolResultFormatter.failureJsonString(
                message: "Invalid frequency '\(invalid)'. Use daily, weekly, monthly, or yearly.",
                code: "invalid_reminder_frequency"
            )
        }

        let captureService = CiderCaptureService()
        guard var result = try? captureService.addDateCardCapture(
            title: title,
            sourceText: det.isEmpty ? title : det,
            startAt: date,
            endAt: nil,
            allDay: true,
            location: loc.isEmpty ? nil : loc,
            folderID: nil,
            sourceContext: CaptureSourceContext(
                surface: "mlx_tool",
                originalText: det.isEmpty ? nil : det,
                metadata: ["tool": "createReminder"]
            )
        ),
              var card = DateCardStorage.shared.dateCard(for: result.item.id)
        else {
            return AgentCaptureToolResultFormatter.failureJsonString(
                message: "Failed to create reminder (disk write failed).",
                code: "reminder_capture_failed"
            )
        }

        // Recurrence
        if let recurrenceFrequency {
            card.recurrenceRule = DateCardRecurrenceRule(frequency: recurrenceFrequency)
        }

        // Reminder offsets
        let firstOffset = integer("remindMinutesBefore", from: args, default: 15)
        card.rules.append(SurfacingRule(type: .remindBeforeMinutes, integerValue: firstOffset))
        if let second = args["secondRemindMinutesBefore"] as? Int {
            card.rules.append(SurfacingRule(type: .remindBeforeMinutes, integerValue: second))
        }

        guard AgentReminderToolSupport.updateDateCard(card) else {
            return AgentCaptureToolResultFormatter.jsonString(
                message: "Created reminder \"\(title)\" but failed to persist reminder recurrence/rules.",
                captureResult: result,
                additionalPartialFailures: [
                    AgentCaptureToolResultFormatter.partialFailure(
                        status: "reminder_update_failed",
                        reason: "The date card was captured, but Cider could not persist the recurrence or reminder rules."
                    )
                ]
            )
        }
        result = captureService.refreshItemIndexing(result)
        ReminderReconciler.shared.reconcile()

        let recurring = card.recurrenceRule != nil ? " (recurring \(card.recurrenceRule!.frequency.rawValue))" : ""
        return AgentCaptureToolResultFormatter.jsonString(
            message: "Created reminder: \"\(title)\" on \(dateStr)\(recurring).",
            captureResult: result
        )
        }
    }

    // MARK: - Cancel Reminder

    private static func cancelReminder(_ args: [String: Any]) -> String {
        MutationAuditContext.withSource(.agent) {
        let query = string("title", from: args).lowercased()
        guard !query.isEmpty else {
            return "Reminder title is required."
        }

        let storage = DateCardStorage.shared
        guard var card = storage.dateCards.first(where: {
            $0.title.lowercased().contains(query)
        }) else {
            return "No reminder found matching \"\(query)\"."
        }

        let deleteEntirely = args["deleteEntirely"] as? Bool ?? false

        if deleteEntirely {
            if let trashItem = storage.deleteDateCard(card.id) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                DateCardNotificationService.shared.cancelNotification(for: card.id)
                return "Deleted reminder: \"\(card.title)\" (moved to trash)."
            }
            return "Failed to delete reminder."
        }

        for i in card.rules.indices where card.rules[i].type == .remindBeforeMinutes {
            card.rules[i].isEnabled = false
        }
        _ = storage.updateDateCard(card)
        DateCardNotificationService.shared.cancelNotification(for: card.id)
        return "Disabled reminders for \"\(card.title)\". The event still exists but won't send notifications."
        }
    }
}
