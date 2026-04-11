@testable import Cider
import Foundation
import OSLog

/// CiderCLI — Full command-line interface to Cider's storage layer.
/// Anything you can do in Cider, you can do here.
@main
@MainActor
struct CiderCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printUsage()
            return
        }

        // Initialize storage services
        _ = StoragePaths.ensureVaultStructure()

        // Open SQLite before any storage service is touched — services check
        // CiderDatabase.shared.isOpen and use it as the primary store when available.
        // Without this, CLI writes skip the SQLite persist path and only hit the
        // filesystem, leaving the DB out of sync with the app.
        do {
            let vaultRoot = StoragePaths.cachedVaultDirectoryURL
            let dbPath = vaultRoot.appendingPathComponent(".cider/cider.db")
            try FileManager.default.createDirectory(
                at: dbPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try CiderDatabase.shared.open(at: dbPath)
        } catch {
            Logger(subsystem: "Cider", category: "CLI")
                .error("Failed to open SQLite database: \(error.localizedDescription). Falling back to JSON.")
        }

        let bookmarkService = VaultBookmarkService.shared
        let notesStorage = NotesStorage.shared
        let todoStorage = TodoCardStorage.shared
        let vaultFileService = VaultFileService.shared
        vaultFileService.ensureInboxDirectories()
        vaultFileService.scan()

        // Wait for async storage initialization — poll until notes are loaded
        // (NotesStorage uses Task { @MainActor } in init which needs actor time)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if !notesStorage.notes.isEmpty { break }
        }

        let subcommand = args.count > 1 ? args[1] : nil
        let remaining = Array(args.dropFirst(2))

        switch command {
        case "bookmark", "bm":
            await handleBookmark(subcommand: subcommand, args: remaining, service: bookmarkService)
        case "note":
            await handleNote(subcommand: subcommand, args: remaining, storage: notesStorage)
        case "todo":
            await handleTodo(subcommand: subcommand, args: remaining, storage: todoStorage)
        case "event", "datecard":
            handleEvent(subcommand: subcommand, args: remaining)
        case "contact":
            handleContact(subcommand: subcommand, args: remaining)
        case "file":
            handleFile(subcommand: subcommand, args: remaining, service: vaultFileService)
        case "folder":
            handleFolder(subcommand: subcommand, args: remaining)
        case "board":
            handleBoard(subcommand: subcommand, args: remaining)
        case "label", "tag":
            handleLabel(subcommand: subcommand, args: remaining)
        case "search":
            await handleSearch(args: Array(args.dropFirst()))
        case "trash":
            handleTrash(subcommand: subcommand, args: remaining)
        case "status":
            handleStatus()
        case "recent":
            handleRecent(args: Array(args.dropFirst()))
        case "snapshot":
            handleSnapshot()
        case "query":
            await handleQuery(args: Array(args.dropFirst()))
        case "duplicate-check", "dupecheck":
            handleDuplicateCheck(args: Array(args.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command). Run 'cider-cli help' for usage.")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Bookmark Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleBookmark(subcommand: String?, args: [String], service: VaultBookmarkService) async {
        switch subcommand {
        case "list", "ls":
            let folderName = parseFlag("--folder", from: args)
            let bookmarks: [Bookmark]
            if let folderName {
                let folder = findFolder(named: folderName)
                bookmarks = service.bookmarks.filter { $0.folderID == folder?.id }
            } else {
                bookmarks = service.bookmarks
            }
            let limit = Int(parseFlag("--limit", from: args) ?? "") ?? bookmarks.count
            if jsonOutput {
                outputJSON(Array(bookmarks.prefix(limit)).map(bookmarkToDict))
            } else {
                print("Bookmarks (\(bookmarks.count)):")
                for bm in bookmarks.prefix(limit) {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let manual = bm.titleManuallySet ? " 🔒" : ""
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title)\(manual) — \(bm.hostDisplay) (\(folder))")
                }
            }

        case "add", "create":
            guard let url = args.first else {
                print("Error: URL required. Usage: cider-cli bookmark add <url> [--title <title>] [--path <vault-relative-path>] [--folder <name>]")
                return
            }
            let title = parseFlag("--title", from: args)
            let bookmark = service.add(urlString: url, title: title)
            if let bookmark {
                if let folder = resolveFolder(from: args) {
                    _ = service.assignBookmark(bookmark.id, toFolder: folder.id)
                }
                print("Created bookmark: \(bookmark.title) (\(bookmark.id.uuidString.prefix(8)))")
            } else {
                print("Error: Could not create bookmark for URL: \(url)")
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                if jsonOutput {
                    outputJSON(bookmarkToDict(bm))
                } else {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("Bookmark: \(bm.title)")
                    print("  ID:        \(bm.id.uuidString)")
                    print("  URL:       \(bm.urlString)")
                    print("  Folder:    \(folder)")
                    print("  Tags:      \(bm.tags.isEmpty ? "(none)" : bm.tags.joined(separator: ", "))")
                    print("  Labels:    \(bm.labelIDs.count)")
                    print("  Notes:     \(bm.notes.isEmpty ? "(none)" : bm.notes)")
                    print("  Created:   \(bm.createdAt.formatted())")
                    print("  Updated:   \(bm.updatedAt.formatted())")
                    print("  Manual:    title=\(bm.titleManuallySet) notes=\(bm.notesManuallySet)")
                    if let ocr = bm.ocrText, !ocr.isEmpty { print("  OCR:       \(ocr.prefix(200))") }
                    if let colors = bm.dominantColors { print("  Colors:    \(colors.joined(separator: ", "))") }
                    if let summary = bm.aiSummary, !summary.isEmpty {
                        // Show aiSummary in full — this is where the agent writes
                        // its enrichment output and needs to be able to read it back.
                        print("  AI Summary:")
                        print(summary)
                    }
                }
            }

        case "search":
            let query = args.filter { $0 != "--json" }.joined(separator: " ")
            let results = service.bookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.urlString.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query) ||
                ($0.ocrText ?? "").localizedCaseInsensitiveContains(query)
            }
            if jsonOutput {
                outputJSON(results.map(bookmarkToDict))
            } else {
                print("Bookmark search '\(query)' (\(results.count)):")
                for bm in results {
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) — \(bm.urlString)")
                }
            }

        case "move":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark move <id> --path <vault-relative-path> | --folder <name>")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let folder = resolveFolder(from: args)
                let oldFolder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                _ = service.assignBookmark(bm.id, toFolder: folder?.id)
                let newFolder = folder?.name ?? "Inbox"
                print("Moved '\(bm.title)' from \(oldFolder) → \(newFolder)")
            }

        case "tag":
            guard let idPrefix = args.first, args.count > 1 else {
                print("Error: Usage: cider-cli bookmark tag <id> <label-name>")
                return
            }
            let labelName = args.dropFirst().joined(separator: " ")
            if let bm = findBookmark(idPrefix, in: service) {
                let label = CardLabelStorage.shared.findOrCreate(name: labelName, colorHex: nil)
                _ = service.assignLabel(bm.id, labelID: label.id)
                print("Tagged '\(bm.title)' with '\(label.name)'")
            }

        case "untag":
            guard let idPrefix = args.first, args.count > 1 else {
                print("Error: Usage: cider-cli bookmark untag <id> <label-name>")
                return
            }
            let labelName = args.dropFirst().joined(separator: " ")
            if let bm = findBookmark(idPrefix, in: service) {
                if let label = CardLabelStorage.shared.labels.first(where: { $0.name.localizedCaseInsensitiveCompare(labelName) == .orderedSame }) {
                    service.removeLabel(bm.id, labelID: label.id)
                    print("Removed tag '\(label.name)' from '\(bm.title)'")
                } else {
                    print("Error: Label '\(labelName)' not found")
                }
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let items = service.removeAll([bm])
                if let item = items.first {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: item))
                    print("Deleted: \(bm.title) (moved to trash)")
                }
            }

        case "enrich":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                print("Scheduling enrichment for '\(bm.title)'...")
                service.refetchMetadata(for: bm.id)
                try? await Task.sleep(for: .seconds(5))
                if let updated = service.bookmarks.first(where: { $0.id == bm.id }) {
                    print("  Title: \(updated.title)")
                    print("  Thumbnail: \(updated.thumbnailRelativePath ?? "none")")
                    print("  OCR: \(updated.ocrText?.prefix(80) ?? "none")")
                    print("  Colors: \(updated.dominantColors?.joined(separator: ", ") ?? "none")")
                }
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark update <id> [--title <title>] [--notes <notes>] [--url <url>] [--ai-summary <text>] [--enrichment-status none|partial|complete]")
                return
            }
            if let bm = findBookmark(idPrefix, in: service) {
                let newTitle = parseFlag("--title", from: args) ?? bm.title
                let newNotes = parseFlag("--notes", from: args) ?? bm.notes
                let newURL = parseFlag("--url", from: args)
                let newAISummary = parseFlag("--ai-summary", from: args)
                let newEnrichmentStatus = parseFlag("--enrichment-status", from: args)
                let updated = service.updateDetails(
                    for: bm.id,
                    title: newTitle,
                    notes: newNotes,
                    tags: bm.tags,
                    urlString: newURL
                )
                // Update AI-owned enrichment fields separately
                let enriched = service.updateEnrichment(
                    for: bm.id,
                    aiSummary: newAISummary,
                    enrichmentStatus: newEnrichmentStatus
                )
                if updated || enriched {
                    print("Updated: \(newTitle) (\(bm.id.uuidString.prefix(8)))")
                } else {
                    print("No changes to apply")
                }
            }

        default:
            print("Unknown bookmark command: \(subcommand ?? "nil")")
            print("Commands: list, add, get, search, move, tag, untag, delete, enrich, update")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Note Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleNote(subcommand: String?, args: [String], storage: NotesStorage) async {
        switch subcommand {
        case "list", "ls":
            let folderName = parseFlag("--folder", from: args)
            let notes: [Note]
            if let folderName {
                let folder = findFolder(named: folderName)
                notes = storage.notes.filter { $0.folderID == folder?.id }
            } else {
                notes = storage.notes
            }
            if jsonOutput {
                outputJSON(notes.map(noteToDict))
            } else {
                print("Notes (\(notes.count)):")
                for note in notes {
                    let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let pinned = note.isPinned ? " 📌" : ""
                    print("  [\(note.id.uuidString.prefix(8))] \(note.title)\(pinned) (\(folder))")
                }
            }

        case "create":
            let title = args.first ?? "Untitled"
            let content = parseFlag("--content", from: args) ?? ""
            let note = storage.createNew(initialContent: content)
            if !title.isEmpty, title != "Untitled" {
                storage.rename(note: note, to: title)
            }
            if let folder = resolveFolder(from: args) {
                _ = storage.assignNote(note.id, toFolder: folder.id)
            }
            print("Created note: \(title) (\(note.id.uuidString.prefix(8)))")

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                let content = storage.loadContent(for: note) ?? ""
                if jsonOutput {
                    var dict = noteToDict(note)
                    dict["content"] = content
                    outputJSON(dict)
                } else {
                    let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("Note: \(note.title)")
                    print("  ID:      \(note.id.uuidString)")
                    print("  Folder:  \(folder)")
                    print("  Pinned:  \(note.isPinned)")
                    print("  Tags:    \(note.tags.isEmpty ? "(none)" : note.tags.joined(separator: ", "))")
                    print("  Labels:  \(note.labelIDs.count)")
                    print("  Created: \(note.createdAt.formatted())")
                    print("  Path:    \(note.relativePath)")
                    print("  Content:")
                    print(content.isEmpty ? "(empty)" : content)
                }
            }

        case "pin":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                storage.togglePin(note.id)
                let state = storage.notes.first(where: { $0.id == note.id })?.isPinned ?? false
                print("\(state ? "Pinned" : "Unpinned"): \(note.title)")
            }

        case "move":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            let folderName = parseFlag("--folder", from: args)
            if let note = findNote(idPrefix, in: storage) {
                let folderID: UUID?
                if let name = folderName {
                    guard let folder = findFolder(named: name) else {
                        print("Error: No folder found named '\(name)'")
                        return
                    }
                    folderID = folder.id
                } else {
                    folderID = nil
                }
                _ = storage.assignNote(note.id, toFolder: folderID)
                print("Moved '\(note.title)' → \(folderName ?? "Inbox")")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                let trashItem = storage.delete(note: note)
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .note, trashItem: trashItem))
                print("Deleted: \(note.title) (moved to trash)")
            }

        case "update", "rename":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli note update <id> [--title <title>] [--content <content>]")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                var changed = false
                if let newTitle = parseFlag("--title", from: args) {
                    storage.rename(note: note, to: newTitle)
                    print("Renamed: '\(note.title)' → '\(newTitle)'")
                    changed = true
                }
                if let newContent = parseFlag("--content", from: args) {
                    // Get current note (may have been renamed above), update content, save
                    let current = storage.notes.first(where: { $0.id == note.id }) ?? note
                    var updated = current
                    updated.content = newContent
                    storage.save(note: updated)
                    print("Updated content for: \(current.title)")
                    changed = true
                }
                if !changed {
                    print("No changes specified. Use --title or --content")
                }
            }

        case "tag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli note tag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            var added = 0
            for name in tagNames where storage.addTag(note.id, tag: name) {
                added += 1
            }
            let current = storage.notes.first(where: { $0.id == note.id })?.tags ?? []
            print("Tagged '\(note.title)' with \(tagNames.joined(separator: ", ")) — now: [\(current.joined(separator: ", "))]")

        case "untag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli note untag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let note = findNote(idPrefix, in: storage) else { return }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            var removed = 0
            for name in tagNames where storage.removeTag(note.id, tag: name) {
                removed += 1
            }
            let current = storage.notes.first(where: { $0.id == note.id })?.tags ?? []
            print("Removed \(removed) tag(s) from '\(note.title)' — now: [\(current.joined(separator: ", "))]")

        default:
            print("Unknown note command: \(subcommand ?? "nil")")
            print("Commands: list, create, get, pin, move, delete, update, tag, untag")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Todo Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleTodo(subcommand: String?, args: [String], storage: TodoCardStorage) async {
        switch subcommand {
        case "list", "ls":
            let showCompleted = args.contains("--completed")
            let todos = showCompleted ? storage.todoCards : storage.todoCards.filter { !$0.isCompleted }
            if jsonOutput {
                outputJSON(todos.map(todoToDict))
            } else {
                print("Todos (\(todos.count)):")
                for todo in todos {
                    let status = todo.isCompleted ? "✅" : "⬜"
                    let due = todo.dueDate.map { " due: \(dateFormatter.string(from: $0))" } ?? ""
                    let priority = todo.priority.map { " [\($0.rawValue)]" } ?? ""
                    print("  \(status) [\(todo.id.uuidString.prefix(8))] \(todo.title)\(priority)\(due)")
                }
            }

        case "create":
            let title = args.first ?? "Untitled Todo"
            let dueString = parseFlag("--due", from: args)
            let priorityString = parseFlag("--priority", from: args)
            let dueDate = dueString.flatMap { dateFormatter.date(from: $0) }
            let priority: TodoPriority? = {
                switch priorityString?.lowercased() {
                case "high": return .high
                case "medium": return .medium
                case "low": return .low
                default: return nil
                }
            }()
            var todo = storage.createTodoCard(title: title, dueDate: dueDate, priority: priority)
            if let folder = resolveFolder(from: args) {
                todo.folderID = folder.id
                _ = storage.updateTodoCard(todo)
            }
            print("Created todo: \(todo.title) (\(todo.id.uuidString.prefix(8)))")

        case "complete", "done":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var updated = todo
                updated.isCompleted = true
                updated.completedAt = Date()
                _ = storage.updateTodoCard(updated)
                print("Completed: \(todo.title)")
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteTodoCard(todo.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                    print("Deleted: \(todo.title) (moved to trash)")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli todo update <id> [--title <title>] [--details <details>] [--due yyyy-MM-dd] [--priority high|medium|low]")
                return
            }
            if var todo = storage.todoCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) { todo.title = t; changed = true }
                if let d = parseFlag("--details", from: args) { todo.details = d; changed = true }
                if let ds = parseFlag("--due", from: args), let date = dateFormatter.date(from: ds) {
                    todo.dueDate = date; changed = true
                }
                if let p = parseFlag("--priority", from: args) {
                    switch p.lowercased() {
                    case "high": todo.priority = .high; changed = true
                    case "medium": todo.priority = .medium; changed = true
                    case "low": todo.priority = .low; changed = true
                    default: break
                    }
                }
                if changed {
                    todo.updatedAt = Date()
                    _ = storage.updateTodoCard(todo)
                    print("Updated: \(todo.title) (\(todo.id.uuidString.prefix(8)))")
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No todo found with ID prefix: \(idPrefix)")
            }

        default:
            print("Unknown todo command: \(subcommand ?? "nil")")
            print("Commands: list, create, complete, delete, update")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Event (DateCard) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleEvent(subcommand: String?, args: [String]) {
        let storage = DateCardStorage.shared
        switch subcommand {
        case "list", "ls":
            let cards = storage.dateCards
            if jsonOutput {
                outputJSON(cards.map(eventToDict))
            } else {
                print("Events (\(cards.count)):")
                for card in cards {
                    let date = dateFormatter.string(from: card.startAt)
                    let completed = card.isCompleted ? " ✅" : ""
                    print("  [\(card.id.uuidString.prefix(8))] \(card.title) — \(date)\(completed)")
                }
            }

        case "create":
            let title = args.first ?? "Untitled Event"
            let dateString = parseFlag("--date", from: args) ?? dateFormatter.string(from: Date())
            let date = dateFormatter.date(from: dateString) ?? Date()
            var card = storage.createDateCard(title: title, startAt: date)
            if let folder = resolveFolder(from: args) {
                card.folderID = folder.id
                _ = storage.updateDateCard(card)
            }
            print("Created event: \(card.title) (\(card.id.uuidString.prefix(8)))")

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let card = storage.dateCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteDateCard(card.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    print("Deleted: \(card.title) (moved to trash)")
                }
            } else {
                print("Error: No event found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli event update <id> [--title <title>] [--date yyyy-MM-dd] [--location <location>]")
                return
            }
            if var card = storage.dateCards.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) { card.title = t; changed = true }
                if let ds = parseFlag("--date", from: args), let date = dateFormatter.date(from: ds) {
                    card.startAt = date; changed = true
                }
                if let loc = parseFlag("--location", from: args) { card.location = loc; changed = true }
                if changed {
                    _ = storage.updateDateCard(card)
                    print("Updated: \(card.title) (\(card.id.uuidString.prefix(8)))")
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No event found with ID prefix: \(idPrefix)")
            }

        default:
            print("Unknown event command: \(subcommand ?? "nil")")
            print("Commands: list, create, delete, update")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Contact Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleContact(subcommand: String?, args: [String]) {
        let storage = ContactStorage.shared
        switch subcommand {
        case "list", "ls":
            let contacts = storage.contacts
            if jsonOutput {
                outputJSON(contacts.map(contactToDict))
            } else {
                print("Contacts (\(contacts.count)):")
                for contact in contacts {
                    let email = contact.email.isEmpty ? "" : " — \(contact.email)"
                    print("  [\(contact.id.uuidString.prefix(8))] \(contact.displayName)\(email)")
                }
            }

        case "create":
            let name = args.first ?? "New Contact"
            let email = parseFlag("--email", from: args)
            let phone = parseFlag("--phone", from: args)
            let address = parseFlag("--address", from: args)
            let notes = parseFlag("--notes", from: args)
            let relationship = parseFlag("--relationship", from: args)
            let birthdayStr = parseFlag("--birthday", from: args)
            var contact = storage.createContact(displayName: name)
            var needsUpdate = false
            if let email { contact.email = email; needsUpdate = true }
            if let phone { contact.phone = phone; needsUpdate = true }
            if let address { contact.address = address; needsUpdate = true }
            if let notes { contact.notes = notes; needsUpdate = true }
            if let relationship { contact.relationshipLabel = relationship; needsUpdate = true }
            if let birthdayStr {
                let localDF = DateFormatter()
                localDF.dateFormat = "yyyy-MM-dd"
                localDF.timeZone = .current
                if let birthday = localDF.date(from: birthdayStr) {
                    contact.birthday = birthday; needsUpdate = true
                }
            }
            if let folder = resolveFolder(from: args) {
                contact.folderID = folder.id; needsUpdate = true
            }
            if needsUpdate { _ = storage.updateContact(contact) }
            print("Created contact: \(contact.displayName) (\(contact.id.uuidString.prefix(8)))")

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if let trashItem = storage.deleteContact(contact.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    print("Deleted: \(contact.displayName) (moved to trash)")
                }
            } else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli contact update <id> [--name <n>] [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>]")
                return
            }
            if var contact = storage.contacts.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let n = parseFlag("--name", from: args) { contact.displayName = n; changed = true }
                if let e = parseFlag("--email", from: args) { contact.email = e; changed = true }
                if let p = parseFlag("--phone", from: args) { contact.phone = p; changed = true }
                if let a = parseFlag("--address", from: args) { contact.address = a; changed = true }
                if let r = parseFlag("--relationship", from: args) { contact.relationshipLabel = r; changed = true }
                if let notes = parseFlag("--notes", from: args) { contact.notes = notes; changed = true }
                if let bday = parseFlag("--birthday", from: args) {
                    let localDF = DateFormatter()
                    localDF.dateFormat = "yyyy-MM-dd"
                    localDF.timeZone = .current
                    if let date = localDF.date(from: bday) {
                        contact.birthday = date; changed = true
                    }
                }
                if changed {
                    _ = storage.updateContact(contact)
                    print("Updated: \(contact.displayName) (\(contact.id.uuidString.prefix(8)))")
                } else {
                    print("No changes specified.")
                }
            } else {
                print("Error: No contact found with ID prefix: \(idPrefix)")
            }

        default:
            print("Unknown contact command: \(subcommand ?? "nil")")
            print("Commands: list, create, delete, update")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - File Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleFile(subcommand: String?, args: [String], service: VaultFileService) {
        switch subcommand {
        case "list", "ls":
            let typeFilter = parseFlag("--type", from: args)
            let folderName = parseFlag("--folder", from: args)
            var files = service.files
            if let typeFilter, let fileType = VaultFileType(rawValue: typeFilter) {
                files = files.filter { $0.fileType == fileType }
            }
            if let folderName {
                let folder = findFolder(named: folderName)
                files = files.filter { $0.folderID == folder?.id }
            }
            if jsonOutput {
                outputJSON(files.map(vaultFileToDict))
            } else {
                print("Vault files (\(files.count)):")
                for file in files {
                    let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                    print("  [\(file.id.uuidString.prefix(8))] \(file.displayTitle) — \(file.fileType.displayName), \(size) (\(folder))")
                }
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                if jsonOutput {
                    outputJSON(vaultFileToDict(file))
                } else {
                    let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                    print("File: \(file.displayTitle)")
                    print("  ID:       \(file.id.uuidString)")
                    print("  Filename: \(file.filename)")
                    print("  Type:     \(file.fileType.displayName)")
                    print("  Size:     \(size)")
                    print("  Folder:   \(folder)")
                    print("  Path:     \(file.relativePath)")
                    print("  Notes:    \(file.notes.isEmpty ? "(none)" : file.notes)")
                    print("  Tags:     \(file.tags.isEmpty ? "(none)" : file.tags.joined(separator: ", "))")
                    print("  Labels:   \(file.labelIDs.count)")
                    if let ocr = file.ocrText, !ocr.isEmpty { print("  OCR:      \(ocr.prefix(200))") }
                    if let colors = file.dominantColors { print("  Colors:   \(colors.joined(separator: ", "))") }
                }
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "move":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            let folderName = parseFlag("--folder", from: args)
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let folderID: UUID?
                if let name = folderName {
                    guard let folder = findFolder(named: name) else {
                        print("Error: No folder found named '\(name)'")
                        return
                    }
                    folderID = folder.id
                } else {
                    folderID = nil
                }
                service.assignFile(file.id, toFolder: folderID)
                print("Moved '\(file.displayTitle)' → \(folderName ?? "Inbox")")
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "delete", "rm":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let trashItem = TrashStorage.shared.trashVaultFile(file)
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFile, trashItem: trashItem))
                print("Deleted: \(file.displayTitle) (moved to trash)")
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "update", "set":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli file update <id> [--title <title>] [--notes <notes>]")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                var changed = false
                if let t = parseFlag("--title", from: args) {
                    VaultFileStorage.shared.updateTitle(file, title: t)
                    print("Title set: '\(t)'")
                    changed = true
                }
                if let n = parseFlag("--notes", from: args) {
                    VaultFileStorage.shared.updateNotes(file, notes: n)
                    print("Notes set for: \(file.displayTitle)")
                    changed = true
                }
                if !changed {
                    print("No changes specified. Use --title or --notes")
                }
            } else {
                print("Error: No file found with ID prefix: \(idPrefix)")
            }

        case "tag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli file tag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No file found with ID prefix: \(idPrefix)")
                return
            }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            for name in tagNames { VaultFileStorage.shared.addTag(file, tag: name) }
            let current = VaultFileStorage.shared.metadata(for: file.id)?.tags ?? []
            print("Tagged '\(file.displayTitle)' with \(tagNames.joined(separator: ", ")) — now: [\(current.joined(separator: ", "))]")

        case "untag":
            guard let idPrefix = args.first else {
                print("Error: Usage: cider-cli file untag <id> --tag <name> [--tag <name> ...]")
                return
            }
            guard let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) else {
                print("Error: No file found with ID prefix: \(idPrefix)")
                return
            }
            let tagNames = parseFlagAll("--tag", from: args)
            if tagNames.isEmpty {
                print("Error: At least one --tag <name> is required")
                return
            }
            var removed = 0
            for name in tagNames where VaultFileStorage.shared.removeTag(file, tag: name) {
                removed += 1
            }
            let current = VaultFileStorage.shared.metadata(for: file.id)?.tags ?? []
            print("Removed \(removed) tag(s) from '\(file.displayTitle)' — now: [\(current.joined(separator: ", "))]")

        default:
            print("Unknown file command: \(subcommand ?? "nil")")
            print("Commands: list, get, move, delete, update, tag, untag")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Folder Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleFolder(subcommand: String?, args: [String]) {
        switch subcommand {
        case "list", "ls":
            let folders = VaultFolderService.shared.folders
            if jsonOutput {
                outputJSON(folders.map(folderToDict))
            } else {
                print("Folders (\(folders.count)):")
                for folder in folders {
                    let depth = folder.relativePath.components(separatedBy: "/").count - 1
                    let indent = String(repeating: "  ", count: depth)
                    print("  \(indent)📁 \(folder.name) (\(folder.id.uuidString.prefix(8)))")
                }
            }

        case "create":
            let name = args.first ?? "New Folder"
            let parentName = parseFlag("--parent", from: args)
            let parentID = parentName.flatMap { findFolder(named: $0)?.id }
            if let folder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) {
                print("Created folder: \(folder.name) (\(folder.id.uuidString.prefix(8)))")
            } else {
                print("Error: Could not create folder: \(name)")
            }

        case "rename":
            guard let oldName = args.first, let newName = parseFlag("--to", from: args) else {
                print("Error: Usage: cider-cli folder rename <name> --to <new-name>")
                return
            }
            if let folder = findFolder(named: oldName) {
                let success = VaultFolderService.shared.renameFolder(folder.id, to: newName)
                print(success ? "Renamed: \(oldName) → \(newName)" : "Error: Could not rename folder")
            }

        case "move", "mv":
            guard let nameOrID = args.first else {
                print("Error: Usage: cider-cli folder move <name|id-prefix> --to <parent-path>")
                print("  Use --to \"\" or --to / to move to the vault root.")
                return
            }
            guard let toPath = parseFlag("--to", from: args) else {
                print("Error: Missing --to <parent-path>. Use --to \"\" to move to the root.")
                return
            }
            guard let folder = findFolder(named: nameOrID) else {
                print("Error: No folder found matching '\(nameOrID)'")
                return
            }

            // Resolve the destination parent. Empty string or "/" means root;
            // any other value is a vault-relative path that will be auto-created
            // if it doesn't exist yet.
            let trimmedPath = toPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            let newParentID: UUID?
            if trimmedPath.isEmpty {
                newParentID = nil
            } else {
                guard let parent = findOrCreateFolderByPath(trimmedPath) else {
                    print("Error: Could not resolve or create destination parent '\(toPath)'")
                    return
                }
                newParentID = parent.id
            }

            let success = VaultFolderService.shared.moveFolder(folder.id, toParentID: newParentID)
            if success {
                if let updated = VaultFolderService.shared.folder(for: folder.id) {
                    print("Moved folder: \(folder.name) → \(updated.relativePath)")
                } else {
                    print("Moved folder: \(folder.name)")
                }
            } else {
                print("Error: Could not move folder '\(folder.name)' to '\(toPath)'")
            }

        case "delete", "rm":
            guard let name = args.first else {
                print("Error: Folder name required.")
                return
            }
            if let folder = findFolder(named: name) {
                VaultFolderService.shared.deleteFolder(folder.id)
                print("Deleted folder: \(name) (moved to trash)")
            }

        default:
            print("Unknown folder command: \(subcommand ?? "nil")")
            print("Commands: list, create, rename, move, delete")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Board (Kanban) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleBoard(subcommand: String?, args: [String]) {
        let storage = KanbanStorage.shared
        switch subcommand {
        case "list", "ls":
            let boards = storage.boards
            print("Boards (\(boards.count)):")
            for board in boards {
                let cols = board.columns.map { "\($0.name)(\($0.cards.count))" }.joined(separator: ", ")
                print("  [\(board.id)] \(board.name) — \(cols)")
            }

        case "show", "cards":
            guard let name = args.first else {
                print("Error: Board name required.")
                return
            }
            if let board = storage.boards.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.id == name }) {
                if jsonOutput {
                    outputJSON(boardToDict(board))
                } else {
                    print("Board: \(board.name) (\(board.id))")
                    for col in board.columns {
                        let done = col.isDoneColumn ? " ✅" : ""
                        print("\n  ── \(col.name)\(done) (\(col.cards.count)) ──")
                        for card in col.cards {
                            let priority = card.priority.map { " [\($0.rawValue)]" } ?? ""
                            let completed = card.completed.map { " done:\(dateFormatter.string(from: $0))" } ?? ""
                            print("    [\(card.id)] \(card.title)\(priority)\(completed)")
                            if let notes = card.notes, !notes.isEmpty {
                                print("      \(notes.prefix(80))")
                            }
                        }
                    }
                }
            } else {
                print("Error: Board '\(name)' not found")
            }

        case "add-card":
            guard let boardName = args.first else {
                print("Error: Usage: cider-cli board add-card <board> --column <col> --title <title> [--notes <text>] [--priority low|medium|high]")
                return
            }
            guard let colName = parseFlag("--column", from: args),
                  let title = parseFlag("--title", from: args) else {
                print("Error: --column and --title required")
                return
            }
            if let board = storage.boards.first(where: { $0.name.localizedCaseInsensitiveCompare(boardName) == .orderedSame || $0.id == boardName }) {
                if let col = board.columns.first(where: { $0.name.localizedCaseInsensitiveCompare(colName) == .orderedSame || $0.id == colName }) {
                    if let card = storage.addCard(boardID: board.id, columnID: col.id, title: title) {
                        // Apply optional notes and priority via updateCard
                        var updated = card
                        if let notes = parseFlag("--notes", from: args) { updated.notes = notes }
                        if let priorityStr = parseFlag("--priority", from: args) {
                            switch priorityStr.lowercased() {
                            case "high": updated.priority = .high
                            case "medium": updated.priority = .medium
                            case "low": updated.priority = .low
                            default: break
                            }
                        }
                        storage.updateCard(boardID: board.id, card: updated)
                        print("Added card: \(updated.title) [\(updated.id)] to \(col.name)")
                    } else {
                        print("Error: Could not add card")
                    }
                } else {
                    print("Error: Column '\(colName)' not found. Available: \(board.columns.map(\.name).joined(separator: ", "))")
                }
            } else {
                print("Error: Board '\(boardName)' not found")
            }

        case "move-card":
            guard let boardName = args.first,
                  let cardID = parseFlag("--card", from: args),
                  let toCol = parseFlag("--to", from: args) else {
                print("Error: Usage: cider-cli board move-card <board> --card <id> --to <column>")
                return
            }
            if let board = storage.boards.first(where: { $0.name.localizedCaseInsensitiveCompare(boardName) == .orderedSame || $0.id == boardName }) {
                if let destCol = board.columns.first(where: { $0.name.localizedCaseInsensitiveCompare(toCol) == .orderedSame || $0.id == toCol }) {
                    storage.moveCard(boardID: board.id, cardID: cardID, toColumnID: destCol.id, toIndex: 0)
                    let cardTitle = board.columns.flatMap(\.cards).first(where: { $0.id == cardID })?.title ?? cardID
                    print("Moved '\(cardTitle)' → \(destCol.name)")
                } else {
                    print("Error: Column '\(toCol)' not found")
                }
            } else {
                print("Error: Board '\(boardName)' not found")
            }

        case "delete-card":
            guard let boardName = args.first,
                  let cardID = parseFlag("--card", from: args) else {
                print("Error: Usage: cider-cli board delete-card <board> --card <id>")
                return
            }
            if let board = storage.boards.first(where: { $0.name.localizedCaseInsensitiveCompare(boardName) == .orderedSame || $0.id == boardName }) {
                storage.deleteCard(boardID: board.id, cardID: cardID)
                print("Deleted card: \(cardID)")
            } else {
                print("Error: Board '\(boardName)' not found")
            }

        default:
            print("Unknown board command: \(subcommand ?? "nil")")
            print("Commands: list, show, add-card, move-card, delete-card")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Label (Tag) Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleLabel(subcommand: String?, args: [String]) {
        let storage = CardLabelStorage.shared
        switch subcommand {
        case "list", "ls":
            let labels = storage.labels
            if jsonOutput {
                outputJSON(labels.map(labelToDict))
            } else {
                print("Labels (\(labels.count)):")
                for label in labels {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name) (\(label.colorHex))")
                }
            }

        case "create":
            let name = args.first ?? "New Label"
            let colorHex = parseFlag("--color", from: args)
            let label = storage.createLabel(name: name, colorHex: colorHex ?? CardLabelStorage.randomPresetColor())
            print("Created label: \(label.name) (\(label.id.uuidString.prefix(8)))")

        case "rename":
            guard let oldName = args.first, let newName = parseFlag("--to", from: args) else {
                print("Error: Usage: cider-cli label rename <name> --to <new-name>")
                return
            }
            if let label = storage.labels.first(where: { $0.name.localizedCaseInsensitiveCompare(oldName) == .orderedSame }) {
                var updated = label
                updated.name = newName
                _ = storage.updateLabel(updated)
                print("Renamed: \(oldName) → \(newName)")
            } else {
                print("Error: Label '\(oldName)' not found")
            }

        case "delete", "rm":
            guard let identifier = args.first else {
                print("Error: Usage: cider-cli label delete <id-prefix|name>")
                return
            }
            // Resolve 0/1/many for both the id-prefix and exact-name paths so
            // an ambiguous prefix (or duplicate name) never silently deletes
            // the wrong label.
            let lower = identifier.lowercased()
            let prefixMatches = storage.labels.filter { $0.id.uuidString.lowercased().hasPrefix(lower) }
            let nameMatches = storage.labels.filter { $0.name.localizedCaseInsensitiveCompare(identifier) == .orderedSame }

            let resolved: CardLabel?
            if prefixMatches.count == 1 {
                resolved = prefixMatches[0]
            } else if prefixMatches.count > 1 {
                print("Error: ID prefix '\(identifier)' is ambiguous — matches \(prefixMatches.count) labels:")
                for label in prefixMatches {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name)")
                }
                print("Use a longer id prefix to disambiguate.")
                return
            } else if nameMatches.count == 1 {
                resolved = nameMatches[0]
            } else if nameMatches.count > 1 {
                print("Error: Name '\(identifier)' is ambiguous — matches \(nameMatches.count) labels:")
                for label in nameMatches {
                    print("  [\(label.id.uuidString.prefix(8))] \(label.name)")
                }
                print("Use the id prefix to disambiguate.")
                return
            } else {
                resolved = nil
            }

            if let label = resolved {
                storage.deleteLabel(label.id)
                print("Deleted label: \(label.name) (\(label.id.uuidString.prefix(8)))")
            } else {
                print("Error: No label found matching '\(identifier)'")
            }

        default:
            print("Unknown label command: \(subcommand ?? "nil")")
            print("Commands: list, create, rename, delete")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Search
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleSearch(args: [String]) async {
        let query = args.filter { $0 != "--json" }.joined(separator: " ")
        guard !query.isEmpty else {
            print("Usage: cider-cli search <query>")
            print("Supports scope modifiers: @bookmarks, @notes, @todos, @events, @images, @files, @folder:<name>, @tag:<name>")
            return
        }

        let results = await SearchService.search(
            query: query,
            bookmarks: VaultBookmarkService.shared.bookmarks,
            notes: NotesStorage.shared.notes
        )

        if jsonOutput {
            outputJSON(results.map(searchResultToDict))
        } else {
            print("Search '\(query)' (\(results.count) results):")
            for result in results {
                let icon: String
                switch result.type {
                case .bookmark: icon = "🔖"
                case .note: icon = "📝"
                case .dateCard: icon = "📅"
                case .contact: icon = "👤"
                case .todo: icon = "☑️"
                case .session: icon = "🌐"
                case .vaultFile: icon = "📎"
                }
                let subtitle = result.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(result.id.uuidString.prefix(8))] \(result.title)\(subtitle)")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Trash Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleTrash(subcommand: String?, args: [String]) {
        switch subcommand {
        case "list", "ls":
            let items = TrashStorage.shared.allTrashItems()
            if jsonOutput {
                outputJSON(items.map(trashItemToDict))
            } else {
                print("Trash (\(items.count) items):")
                for item in items {
                    let age = item.deletedAt.formatted(.relative(presentation: .named))
                    print("  [\(item.id.uuidString.prefix(8))] \(item.title) (\(item.itemType.rawValue)) — deleted \(age)")
                }
            }

        case "restore":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            let items = TrashStorage.shared.allTrashItems()
            if let item = items.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                TrashStorage.shared.restore(item)
                print("Restored: \(item.title)")
            } else {
                print("Error: No trash item found with ID prefix: \(idPrefix)")
            }

        case "empty":
            let count = TrashStorage.shared.allTrashItems().count
            TrashStorage.shared.emptyTrash()
            print("Emptied trash (\(count) items permanently deleted)")

        case "purge":
            let days = Int(parseFlag("--days", from: args) ?? "30") ?? 30
            TrashStorage.shared.purgeExpired(olderThan: days)
            print("Purged items older than \(days) days")

        default:
            print("Unknown trash command: \(subcommand ?? "nil")")
            print("Commands: list, restore, empty, purge")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Status
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleStatus() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files
        let sessions = BrowserSessionStorage.shared.sessions
        let folders = VaultFolderService.shared.folders
        let labels = CardLabelStorage.shared.labels
        let boards = KanbanStorage.shared.boards
        let trash = TrashStorage.shared.allTrashItems()

        if jsonOutput {
            outputJSON(statusToDict())
        } else {
            print("Cider Vault Status")
            print("──────────────────")
            print("  Bookmarks:    \(bookmarks.count)")
            print("  Notes:        \(notes.count)")
            print("  Todos:        \(todos.count) (\(todos.filter { !$0.isCompleted }.count) active)")
            print("  Events:       \(events.count)")
            print("  Contacts:     \(contacts.count)")
            print("  Vault Files:  \(files.count) (\(files.filter { $0.fileType == .image }.count) images)")
            print("  Sessions:     \(sessions.count)")
            print("  Folders:      \(folders.count)")
            print("  Labels:       \(labels.count)")
            print("  Boards:       \(boards.count) (\(boards.flatMap(\.columns).flatMap(\.cards).count) cards)")
            print("  Trash:        \(trash.count) items")
            print("  Vault Root:   \(StoragePaths.cachedVaultDirectoryURL.path)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Recent
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleRecent(args: [String]) {
        let hoursStr = parseFlag("--hours", from: args) ?? "24"
        let hours = Double(hoursStr) ?? 24
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let typeFilter = parseFlag("--type", from: args)?.lowercased()
        let limitStr = parseFlag("--limit", from: args)
        let limit = Int(limitStr ?? "") ?? 50

        struct RecentItem {
            let type: String
            let id: String
            let title: String
            let date: Date
            let subtitle: String?
            func toDict() -> [String: Any] {
                var d: [String: Any] = ["type": type, "id": id, "title": title,
                    "date": ISO8601DateFormatter().string(from: date)]
                if let s = subtitle { d["subtitle"] = s }
                return d
            }
        }

        var items: [RecentItem] = []

        if typeFilter == nil || typeFilter == "bookmark" {
            for bm in VaultBookmarkService.shared.bookmarks where bm.createdAt >= cutoff {
                items.append(RecentItem(type: "bookmark", id: bm.id.uuidString,
                    title: bm.title, date: bm.createdAt, subtitle: bm.hostDisplay))
            }
        }
        if typeFilter == nil || typeFilter == "note" {
            for note in NotesStorage.shared.notes where note.createdAt >= cutoff {
                items.append(RecentItem(type: "note", id: note.id.uuidString,
                    title: note.title, date: note.createdAt, subtitle: nil))
            }
        }
        if typeFilter == nil || typeFilter == "todo" {
            for todo in TodoCardStorage.shared.todoCards where todo.createdAt >= cutoff {
                items.append(RecentItem(type: "todo", id: todo.id.uuidString,
                    title: todo.title, date: todo.createdAt,
                    subtitle: todo.isCompleted ? "completed" : "active"))
            }
        }
        if typeFilter == nil || typeFilter == "event" {
            for card in DateCardStorage.shared.dateCards where card.createdAt >= cutoff {
                items.append(RecentItem(type: "event", id: card.id.uuidString,
                    title: card.title, date: card.createdAt,
                    subtitle: dateFormatter.string(from: card.startAt)))
            }
        }
        if typeFilter == nil || typeFilter == "contact" {
            for c in ContactStorage.shared.contacts where c.createdAt >= cutoff {
                items.append(RecentItem(type: "contact", id: c.id.uuidString,
                    title: c.displayName, date: c.createdAt, subtitle: nil))
            }
        }
        if typeFilter == nil || typeFilter == "file" || typeFilter == "image" {
            for f in VaultFileService.shared.files where f.createdAt >= cutoff {
                if typeFilter == "image" && f.fileType != .image { continue }
                items.append(RecentItem(type: "file", id: f.id.uuidString,
                    title: f.displayTitle, date: f.createdAt,
                    subtitle: f.fileType.rawValue))
            }
        }

        items.sort { $0.date > $1.date }
        let results = Array(items.prefix(limit))

        if jsonOutput {
            outputJSON(results.map { $0.toDict() })
        } else {
            let label = hours >= 24 ? "\(Int(hours / 24)) day\(hours >= 48 ? "s" : "")" : "\(Int(hours)) hour\(hours > 1 ? "s" : "")"
            print("Recent items (last \(label), \(results.count) found):")
            let icons = ["bookmark": "🔖", "note": "📝", "todo": "☑️", "event": "📅",
                         "contact": "👤", "file": "📎"]
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            for item in results {
                let icon = icons[item.type] ?? "📦"
                let ago = relFormatter.localizedString(for: item.date, relativeTo: Date())
                let sub = item.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(item.id.prefix(8))] \(item.title)\(sub) (\(ago))")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Snapshot
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleSnapshot() {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files
        let sessions = BrowserSessionStorage.shared.sessions
        let folders = VaultFolderService.shared.folders
        let labels = CardLabelStorage.shared.labels
        let boards = KanbanStorage.shared.boards
        let trash = TrashStorage.shared.allTrashItems()

        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)
        let weekAgo = now.addingTimeInterval(-604800)

        // Count recent items
        let recentBookmarks24h = bookmarks.filter { $0.createdAt >= dayAgo }.count
        let recentBookmarks7d = bookmarks.filter { $0.createdAt >= weekAgo }.count
        let recentNotes24h = notes.filter { $0.createdAt >= dayAgo }.count
        let recentNotes7d = notes.filter { $0.createdAt >= weekAgo }.count

        // Tag frequency
        var tagCounts: [String: Int] = [:]
        for label in labels {
            let count = bookmarks.filter { $0.labelIDs.contains(label.id) }.count
                + notes.filter { $0.labelIDs.contains(label.id) }.count
            if count > 0 { tagCounts[label.name] = count }
        }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(15)

        // Folder item counts
        var folderCounts: [(String, Int)] = []
        let inboxCount = bookmarks.filter { $0.folderID == nil }.count
            + notes.filter { $0.folderID == nil }.count
        folderCounts.append(("Inbox", inboxCount))
        for folder in folders {
            let bmCount = bookmarks.filter { $0.folderID == folder.id }.count
            let noteCount = notes.filter { $0.folderID == folder.id }.count
            let todoCount = todos.filter { $0.folderID == folder.id }.count
            let fileCount = files.filter { $0.folderID == folder.id }.count
            let count = bmCount + noteCount + todoCount + fileCount
            if count > 0 { folderCounts.append((folder.name, count)) }
        }
        folderCounts.sort { $0.1 > $1.1 }

        if jsonOutput {
            var d: [String: Any] = statusToDict()
            d["recentBookmarks24h"] = recentBookmarks24h
            d["recentBookmarks7d"] = recentBookmarks7d
            d["recentNotes24h"] = recentNotes24h
            d["recentNotes7d"] = recentNotes7d
            d["topTags"] = topTags.map { ["name": $0.key, "count": $0.value] as [String: Any] }
            d["folderCounts"] = folderCounts.map { ["name": $0.0, "count": $0.1] as [String: Any] }
            d["activeTodos"] = todos.filter { !$0.isCompleted }.map {
                ["id": $0.id.uuidString, "title": $0.title,
                 "priority": $0.priority?.rawValue ?? "none"] as [String: Any]
            }
            outputJSON(d)
        } else {
            print("Cider Vault Snapshot")
            print("════════════════════════════════════════")
            print("")
            print("  ITEMS")
            print("  ─────")
            print("  Bookmarks:    \(bookmarks.count)  (+\(recentBookmarks24h) today, +\(recentBookmarks7d) this week)")
            print("  Notes:        \(notes.count)  (+\(recentNotes24h) today, +\(recentNotes7d) this week)")
            print("  Todos:        \(todos.filter { !$0.isCompleted }.count) active / \(todos.count) total")
            print("  Events:       \(events.count)")
            print("  Contacts:     \(contacts.count)")
            print("  Files:        \(files.count) (\(files.filter { $0.fileType == .image }.count) images)")
            print("  Sessions:     \(sessions.count)")
            print("  Trash:        \(trash.count)")
            print("")
            print("  FOLDERS (\(folders.count))")
            print("  ───────")
            for (name, count) in folderCounts.prefix(20) {
                print("  📁 \(name): \(count) items")
            }
            if !topTags.isEmpty {
                print("")
                print("  TOP TAGS")
                print("  ────────")
                for (name, count) in topTags {
                    print("  🏷️  \(name): \(count)")
                }
            }
            let activeTodos = todos.filter { !$0.isCompleted }
            if !activeTodos.isEmpty {
                print("")
                print("  ACTIVE TODOS")
                print("  ────────────")
                for todo in activeTodos.prefix(10) {
                    let priority = todo.priority.map { " [\($0.rawValue)]" } ?? ""
                    let due = todo.dueDate.map { " due:\(dateFormatter.string(from: $0))" } ?? ""
                    print("  ☑️  \(todo.title)\(priority)\(due)")
                }
            }
            print("")
            print("  Vault: \(StoragePaths.cachedVaultDirectoryURL.path)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Query (natural language search)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleQuery(args: [String]) async {
        let raw = args.filter { $0 != "--json" }.joined(separator: " ")
        guard !raw.isEmpty else {
            print("Usage: cider-cli query \"restaurants I saved last week\"")
            print("Parses natural language time ranges and searches across all fields.")
            return
        }

        // Parse time expressions from the query
        let (keywords, dateRange) = parseNaturalQuery(raw)

        // Search across all types
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let todos = TodoCardStorage.shared.todoCards
        let events = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts
        let files = VaultFileService.shared.files

        struct QueryResult {
            let type: String; let id: String; let title: String
            let date: Date; let subtitle: String?; let score: Int
            func toDict() -> [String: Any] {
                var d: [String: Any] = ["type": type, "id": id, "title": title,
                    "date": ISO8601DateFormatter().string(from: date), "score": score]
                if let s = subtitle { d["subtitle"] = s }
                return d
            }
        }

        var results: [QueryResult] = []
        let query = keywords.lowercased()

        // Search bookmarks (title, URL, notes, tags, AI summary, OCR)
        for bm in bookmarks {
            if let range = dateRange, bm.createdAt < range.start || bm.createdAt > range.end { continue }
            var score = 0
            if bm.title.lowercased().contains(query) { score += 10 }
            if bm.urlString.lowercased().contains(query) { score += 5 }
            if bm.notes.lowercased().contains(query) { score += 8 }
            if bm.tags.contains(where: { $0.lowercased().contains(query) }) { score += 7 }
            if let summary = bm.aiSummary, summary.lowercased().contains(query) { score += 6 }
            if let ocr = bm.ocrText, ocr.lowercased().contains(query) { score += 3 }
            // Check label names
            let labelNames = bm.labelIDs.compactMap { id in
                CardLabelStorage.shared.labels.first(where: { $0.id == id })?.name.lowercased()
            }
            if labelNames.contains(where: { $0.contains(query) }) { score += 7 }
            // If no keywords but date range matched, include it
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "bookmark", id: bm.id.uuidString,
                    title: bm.title, date: bm.createdAt,
                    subtitle: bm.hostDisplay, score: score))
            }
        }

        // Search notes
        for note in notes {
            if let range = dateRange, note.createdAt < range.start || note.createdAt > range.end { continue }
            var score = 0
            if note.title.lowercased().contains(query) { score += 10 }
            if note.content.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "note", id: note.id.uuidString,
                    title: note.title, date: note.createdAt, subtitle: nil, score: score))
            }
        }

        // Search todos
        for todo in todos {
            if let range = dateRange, todo.createdAt < range.start || todo.createdAt > range.end { continue }
            var score = 0
            if todo.title.lowercased().contains(query) { score += 10 }
            if todo.details.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "todo", id: todo.id.uuidString,
                    title: todo.title, date: todo.createdAt,
                    subtitle: todo.isCompleted ? "completed" : "active", score: score))
            }
        }

        // Search events
        for card in events {
            if let range = dateRange, card.createdAt < range.start || card.createdAt > range.end { continue }
            var score = 0
            if card.title.lowercased().contains(query) { score += 10 }
            if card.details.lowercased().contains(query) { score += 6 }
            if !card.location.isEmpty && card.location.lowercased().contains(query) { score += 8 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "event", id: card.id.uuidString,
                    title: card.title, date: card.createdAt,
                    subtitle: dateFormatter.string(from: card.startAt), score: score))
            }
        }

        // Search contacts
        for c in contacts {
            if let range = dateRange, c.createdAt < range.start || c.createdAt > range.end { continue }
            var score = 0
            if c.displayName.lowercased().contains(query) { score += 10 }
            if c.email.lowercased().contains(query) { score += 8 }
            if c.notes.lowercased().contains(query) { score += 6 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "contact", id: c.id.uuidString,
                    title: c.displayName, date: c.createdAt,
                    subtitle: c.email.isEmpty ? nil : c.email, score: score))
            }
        }

        // Search vault files
        for f in files {
            if let range = dateRange, f.createdAt < range.start || f.createdAt > range.end { continue }
            var score = 0
            if f.displayTitle.lowercased().contains(query) { score += 10 }
            if f.notes.lowercased().contains(query) { score += 6 }
            if let ocr = f.ocrText, ocr.lowercased().contains(query) { score += 3 }
            if query.isEmpty && dateRange != nil { score = 5 }
            if score > 0 {
                results.append(QueryResult(type: "file", id: f.id.uuidString,
                    title: f.displayTitle, date: f.createdAt,
                    subtitle: f.fileType.rawValue, score: score))
            }
        }

        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.date > $1.date }

        if jsonOutput {
            outputJSON(results.map { $0.toDict() })
        } else {
            var desc = "Query: \(raw)"
            if let range = dateRange {
                desc += " (date: \(dateFormatter.string(from: range.start)) to \(dateFormatter.string(from: range.end)))"
            }
            if !keywords.isEmpty { desc += " (keywords: \(keywords))" }
            print("\(desc)")
            print("\(results.count) results:")
            let icons = ["bookmark": "🔖", "note": "📝", "todo": "☑️", "event": "📅",
                         "contact": "👤", "file": "📎"]
            for result in results.prefix(30) {
                let icon = icons[result.type] ?? "📦"
                let sub = result.subtitle.map { " — \($0)" } ?? ""
                print("  \(icon) [\(result.id.prefix(8))] \(result.title)\(sub)")
            }
        }
    }

    /// Parses natural language time expressions from a query string.
    /// Returns (remaining keywords, optional date range).
    static func parseNaturalQuery(_ input: String) -> (String, (start: Date, end: Date)?) {
        let lower = input.lowercased()
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        var dateRange: (start: Date, end: Date)?
        var keywords = input

        // Time patterns — order matters (longest match first)
        let patterns: [(String, (start: Date, end: Date))] = [
            ("last 2 weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("last two weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("past 2 weeks", (calendar.date(byAdding: .day, value: -14, to: startOfToday)!, now)),
            ("last week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("past week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("this week", (calendar.date(byAdding: .day, value: -7, to: startOfToday)!, now)),
            ("last month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("past month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("this month", (calendar.date(byAdding: .month, value: -1, to: startOfToday)!, now)),
            ("last 3 days", (calendar.date(byAdding: .day, value: -3, to: startOfToday)!, now)),
            ("last 3 months", (calendar.date(byAdding: .month, value: -3, to: startOfToday)!, now)),
            ("last 6 months", (calendar.date(byAdding: .month, value: -6, to: startOfToday)!, now)),
            ("last year", (calendar.date(byAdding: .year, value: -1, to: startOfToday)!, now)),
            ("yesterday", (calendar.date(byAdding: .day, value: -1, to: startOfToday)!,
                           startOfToday)),
            ("today", (startOfToday, now)),
            ("this year", (calendar.date(from: calendar.dateComponents([.year], from: now))!, now)),
            ("recently", (calendar.date(byAdding: .day, value: -3, to: startOfToday)!, now)),
        ]

        for (phrase, range) in patterns {
            if lower.contains(phrase) {
                dateRange = range
                // Remove the time phrase from keywords
                let keywordRange = lower.range(of: phrase)!
                var cleaned = input
                cleaned.removeSubrange(keywordRange)
                keywords = cleaned
                break
            }
        }

        // Also match "N days ago", "N weeks ago"
        if dateRange == nil {
            let daysAgoPattern = try? NSRegularExpression(pattern: "(\\d+)\\s+days?\\s+ago", options: .caseInsensitive)
            if let match = daysAgoPattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let numRange = Range(match.range(at: 1), in: input),
               let days = Int(input[numRange]) {
                dateRange = (calendar.date(byAdding: .day, value: -days, to: startOfToday)!, now)
                let fullRange = Range(match.range, in: input)!
                keywords = input.replacingCharacters(in: fullRange, with: "")
            }
            let weeksAgoPattern = try? NSRegularExpression(pattern: "(\\d+)\\s+weeks?\\s+ago", options: .caseInsensitive)
            if dateRange == nil, let match = weeksAgoPattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               let numRange = Range(match.range(at: 1), in: input),
               let weeks = Int(input[numRange]) {
                dateRange = (calendar.date(byAdding: .day, value: -weeks * 7, to: startOfToday)!, now)
                let fullRange = Range(match.range, in: input)!
                keywords = input.replacingCharacters(in: fullRange, with: "")
            }
        }

        // Clean up keywords
        keywords = keywords
            .replacingOccurrences(of: "I saved", with: "")
            .replacingOccurrences(of: "i saved", with: "")
            .replacingOccurrences(of: "I added", with: "")
            .replacingOccurrences(of: "i added", with: "")
            .replacingOccurrences(of: "saved", with: "")
            .replacingOccurrences(of: "from", with: "")
            .replacingOccurrences(of: "about", with: "")
            .replacingOccurrences(of: "related to", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (keywords, dateRange)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Duplicate Check
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleDuplicateCheck(args: [String]) {
        guard let url = args.first else {
            print("Usage: cider-cli duplicate-check <url>")
            return
        }

        let normalized = url.lowercased()
            .replacingOccurrences(of: "https://www.", with: "https://")
            .replacingOccurrences(of: "http://www.", with: "http://")
            .replacingOccurrences(of: "http://", with: "https://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let matches = VaultBookmarkService.shared.bookmarks.filter { bm in
            let bmNorm = bm.urlString.lowercased()
                .replacingOccurrences(of: "https://www.", with: "https://")
                .replacingOccurrences(of: "http://www.", with: "http://")
                .replacingOccurrences(of: "http://", with: "https://")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return bmNorm == normalized || bmNorm.hasPrefix(normalized) || normalized.hasPrefix(bmNorm)
        }

        if jsonOutput {
            outputJSON([
                "url": url,
                "isDuplicate": !matches.isEmpty,
                "matches": matches.map(bookmarkToDict),
            ] as [String: Any])
        } else {
            if matches.isEmpty {
                print("No duplicates found for: \(url)")
            } else {
                print("⚠️  Found \(matches.count) duplicate\(matches.count > 1 ? "s" : ""):")
                for bm in matches {
                    let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                    print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) (\(folder))")
                    print("    \(bm.urlString)")
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parseFlag(_ flag: String, from args: [String]) -> String? {
        guard let flagIndex = args.firstIndex(of: flag),
              flagIndex + 1 < args.count else { return nil }
        return args[flagIndex + 1]
    }

    /// Parse every occurrence of `--flag <value>` in `args`. Used for
    /// subcommands that accept repeated flags (e.g. `--tag a --tag b`).
    static func parseFlagAll(_ flag: String, from args: [String]) -> [String] {
        var values: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == flag, i + 1 < args.count {
                values.append(args[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return values
    }

    static func findFolder(named name: String) -> VaultFolder? {
        // Check registered folders first
        if let existing = VaultFolderService.shared.folders.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }

        // If not registered but directory exists on disk, scan to pick it up
        let vaultURL = StoragePaths.cachedVaultDirectoryURL
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: vaultURL, includingPropertiesForKeys: [URLResourceKey.isDirectoryKey],
                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while let url = enumerator.nextObject() as? URL {
                guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else {
                    enumerator.skipDescendants()
                    continue
                }
                if url.lastPathComponent.localizedCaseInsensitiveCompare(name) == .orderedSame {
                    // Found a matching directory — determine parent
                    let parentName = url.deletingLastPathComponent().lastPathComponent
                    let parentID = VaultFolderService.shared.folders.first(where: {
                        $0.name.localizedCaseInsensitiveCompare(parentName) == .orderedSame
                    })?.id
                    // Register it
                    if let folder = VaultFolderService.shared.createFolder(name: url.lastPathComponent, parentID: parentID) {
                        return folder
                    }
                }
            }
        }
        return nil
    }

    /// Resolves --path or --folder from args to a VaultFolder. Prefers --path.
    static func resolveFolder(from args: [String]) -> VaultFolder? {
        if let path = parseFlag("--path", from: args) {
            return findOrCreateFolderByPath(path)
        }
        if let name = parseFlag("--folder", from: args) {
            return findFolder(named: name)
        }
        return nil
    }

    /// Resolves a vault-relative path (e.g. "People/Baine") to a registered VaultFolder.
    /// Creates the directory and registers each path component if needed.
    static func findOrCreateFolderByPath(_ relativePath: String) -> VaultFolder? {
        let vaultURL = StoragePaths.cachedVaultDirectoryURL

        // Ensure the full directory exists on disk
        let fullURL = vaultURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: fullURL, withIntermediateDirectories: true)

        // Check if this exact path is already registered
        if let existing = VaultFolderService.shared.folders.first(where: {
            $0.relativePath.localizedCaseInsensitiveCompare(relativePath) == .orderedSame
        }) {
            return existing
        }

        // Walk the path and register each component
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }

        var currentPath = ""
        var parentID: UUID?
        var lastFolder: VaultFolder?

        for component in components {
            currentPath = currentPath.isEmpty ? component : currentPath + "/" + component

            let existing = VaultFolderService.shared.folders.first(where: {
                $0.relativePath.localizedCaseInsensitiveCompare(currentPath) == .orderedSame
            })

            if let existing {
                parentID = existing.id
                lastFolder = existing
            } else {
                if let created = VaultFolderService.shared.createFolder(name: component, parentID: parentID) {
                    parentID = created.id
                    lastFolder = created
                } else {
                    return nil
                }
            }
        }
        return lastFolder
    }

    static func findBookmark(_ idPrefix: String, in service: VaultBookmarkService) -> Bookmark? {
        let bm = service.bookmarks.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) })
        if bm == nil { print("Error: No bookmark found with ID prefix: \(idPrefix)") }
        return bm
    }

    static func findNote(_ idPrefix: String, in storage: NotesStorage) -> Note? {
        let note = storage.notes.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) })
        if note == nil { print("Error: No note found with ID prefix: \(idPrefix)") }
        return note
    }

    static func printUsage() {
        print("""
        CiderCLI — Full command-line interface to Cider's vault

        BOOKMARKS (alias: bm)
          cider-cli bookmark list [--folder <name>] [--limit <n>]
          cider-cli bookmark add <url> [--title <title>] [--folder <name>]
          cider-cli bookmark get <id-prefix>
          cider-cli bookmark search <query>
          cider-cli bookmark move <id-prefix> --folder <name>
          cider-cli bookmark tag <id-prefix> <label-name>
          cider-cli bookmark untag <id-prefix> <label-name>
          cider-cli bookmark delete <id-prefix>
          cider-cli bookmark enrich <id-prefix>
          cider-cli bookmark update <id-prefix> [--title <t>] [--notes <n>] [--url <u>]

        NOTES
          cider-cli note list [--folder <name>]
          cider-cli note create <title> [--content <text>] [--folder <name>]
          cider-cli note get <id-prefix>
          cider-cli note pin <id-prefix>
          cider-cli note move <id-prefix> --folder <name>
          cider-cli note delete <id-prefix>
          cider-cli note update <id-prefix> [--title <t>] [--content <c>]

        TODOS
          cider-cli todo list [--completed]
          cider-cli todo create <title> [--due yyyy-MM-dd] [--priority high|medium|low] [--folder <name>]
          cider-cli todo complete <id-prefix>
          cider-cli todo delete <id-prefix>
          cider-cli todo update <id-prefix> [--title <t>] [--details <d>] [--due <date>] [--priority <p>]

        EVENTS
          cider-cli event list
          cider-cli event create <title> [--date yyyy-MM-dd] [--folder <name>]
          cider-cli event delete <id-prefix>
          cider-cli event update <id-prefix> [--title <t>] [--date <d>] [--location <l>]

        CONTACTS
          cider-cli contact list
          cider-cli contact create <name> [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>] [--folder <name>]
          cider-cli contact delete <id-prefix>
          cider-cli contact update <id-prefix> [--name <n>] [--email <e>] [--phone <p>] [--address <a>] [--birthday yyyy-MM-dd] [--relationship <r>] [--notes <n>]

        FILES
          cider-cli file list [--type image|pdf|video|audio|document|archive] [--folder <name>]
          cider-cli file get <id-prefix>
          cider-cli file move <id-prefix> --folder <name>
          cider-cli file delete <id-prefix>

        FOLDERS
          cider-cli folder list
          cider-cli folder create <name> [--parent <name>]
          cider-cli folder rename <name> --to <new-name>
          cider-cli folder delete <name>

        BOARDS (Kanban)
          cider-cli board list
          cider-cli board show <board-name-or-id>
          cider-cli board add-card <board> --column <col> --title <title> [--notes <text>] [--priority low|medium|high]
          cider-cli board move-card <board> --card <id> --to <column>
          cider-cli board delete-card <board> --card <id>

        LABELS (alias: tag)
          cider-cli label list
          cider-cli label create <name> [--color <hex>]
          cider-cli label rename <name> --to <new-name>
          cider-cli label delete <id-prefix|name>

        SEARCH
          cider-cli search <query>
          Supports: @bookmarks @notes @todos @events @images @files @folder:<name> @tag:<name>

        TRASH
          cider-cli trash list
          cider-cli trash restore <id-prefix>
          cider-cli trash empty
          cider-cli trash purge [--days <n>]

        STATUS
          cider-cli status

        RECENT
          cider-cli recent [--hours <n>] [--type bookmark|note|todo|event|contact|file|image] [--limit <n>]

        SNAPSHOT
          cider-cli snapshot

        QUERY (natural language search)
          cider-cli query "restaurants I saved last week"
          cider-cli query "notes from yesterday"
          cider-cli query "bookmarks about AI this month"
          Time: today, yesterday, recently, last week, last month, this year, N days ago, N weeks ago

        DUPLICATE CHECK
          cider-cli duplicate-check <url>
        """)
    }
}
