@testable import Cider
import Foundation

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
                print("Error: URL required. Usage: cider-cli bookmark add <url> [--title <title>] [--folder <name>]")
                return
            }
            let title = parseFlag("--title", from: args)
            let folderName = parseFlag("--folder", from: args)
            let bookmark = service.add(urlString: url, title: title)
            if let bookmark {
                if let folderName, let folder = findFolder(named: folderName) {
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
                    print("  ID:       \(bm.id.uuidString)")
                    print("  URL:      \(bm.urlString)")
                    print("  Folder:   \(folder)")
                    print("  Tags:     \(bm.tags.joined(separator: ", "))")
                    print("  Labels:   \(bm.labelIDs.count)")
                    print("  Notes:    \(bm.notes.isEmpty ? "(none)" : bm.notes)")
                    print("  Created:  \(bm.createdAt.formatted())")
                    print("  Updated:  \(bm.updatedAt.formatted())")
                    print("  Manual:   title=\(bm.titleManuallySet) notes=\(bm.notesManuallySet)")
                    if let ocr = bm.ocrText { print("  OCR:      \(ocr.prefix(100))") }
                    if let colors = bm.dominantColors { print("  Colors:   \(colors.joined(separator: ", "))") }
                    if let summary = bm.aiSummary { print("  Summary:  \(summary.prefix(100))") }
                }
            }

        case "search":
            let query = args.joined(separator: " ")
            let results = service.bookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.urlString.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query) ||
                ($0.ocrText ?? "").localizedCaseInsensitiveContains(query)
            }
            print("Bookmark search '\(query)' (\(results.count)):")
            for bm in results {
                print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) — \(bm.urlString)")
            }

        case "move":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark move <id> --folder <name>")
                return
            }
            let folderName = parseFlag("--folder", from: args)
            if let bm = findBookmark(idPrefix, in: service) {
                let folderID = folderName.flatMap { findFolder(named: $0)?.id }
                let oldFolder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                _ = service.assignBookmark(bm.id, toFolder: folderID)
                let newFolder = folderName ?? "Inbox"
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

        default:
            print("Unknown bookmark command: \(subcommand ?? "nil")")
            print("Commands: list, add, get, search, move, tag, untag, delete, enrich")
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
            print("Created note: \(title) (\(note.id.uuidString.prefix(8)))")

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let note = findNote(idPrefix, in: storage) {
                let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let content = storage.loadContent(for: note) ?? "(could not load)"
                print("Note: \(note.title)")
                print("  ID:      \(note.id.uuidString)")
                print("  Folder:  \(folder)")
                print("  Pinned:  \(note.isPinned)")
                print("  Labels:  \(note.labelIDs.count)")
                print("  Created: \(note.createdAt.formatted())")
                print("  Path:    \(note.relativePath)")
                print("  Content:")
                print(content.prefix(500))
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
                let folderID = folderName.flatMap { findFolder(named: $0)?.id }
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

        default:
            print("Unknown note command: \(subcommand ?? "nil")")
            print("Commands: list, create, get, pin, move, delete")
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
            let todo = storage.createTodoCard(title: title, dueDate: dueDate, priority: priority)
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

        default:
            print("Unknown todo command: \(subcommand ?? "nil")")
            print("Commands: list, create, complete, delete")
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
            print("Events (\(cards.count)):")
            for card in cards {
                let date = dateFormatter.string(from: card.startAt)
                let completed = card.isCompleted ? " ✅" : ""
                print("  [\(card.id.uuidString.prefix(8))] \(card.title) — \(date)\(completed)")
            }

        case "create":
            let title = args.first ?? "Untitled Event"
            let dateString = parseFlag("--date", from: args) ?? dateFormatter.string(from: Date())
            let date = dateFormatter.date(from: dateString) ?? Date()
            let card = storage.createDateCard(title: title, startAt: date)
            print("Created event: \(card.title) (\(card.id.uuidString.prefix(8)))")

        default:
            print("Unknown event command: \(subcommand ?? "nil")")
            print("Commands: list, create")
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
            print("Contacts (\(contacts.count)):")
            for contact in contacts {
                let email = contact.email.isEmpty ? "" : " — \(contact.email)"
                print("  [\(contact.id.uuidString.prefix(8))] \(contact.displayName)\(email)")
            }

        case "create":
            let name = args.first ?? "New Contact"
            let email = parseFlag("--email", from: args) ?? ""
            let phone = parseFlag("--phone", from: args) ?? ""
            let contact = storage.createContact(displayName: name)
            print("Created contact: \(contact.displayName) (\(contact.id.uuidString.prefix(8)))")

        default:
            print("Unknown contact command: \(subcommand ?? "nil")")
            print("Commands: list, create")
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
            print("Vault files (\(files.count)):")
            for file in files {
                let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                print("  [\(file.id.uuidString.prefix(8))] \(file.displayTitle) — \(file.fileType.displayName), \(size) (\(folder))")
            }

        case "get", "show":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required.")
                return
            }
            if let file = service.files.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
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
                print("  Labels:   \(file.labelIDs.count)")
                if let ocr = file.ocrText, !ocr.isEmpty { print("  OCR:      \(ocr.prefix(100))") }
                if let colors = file.dominantColors { print("  Colors:   \(colors.joined(separator: ", "))") }
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
                let folderID = folderName.flatMap { findFolder(named: $0)?.id }
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

        default:
            print("Unknown file command: \(subcommand ?? "nil")")
            print("Commands: list, get, move, delete")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Folder Commands
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static func handleFolder(subcommand: String?, args: [String]) {
        switch subcommand {
        case "list", "ls":
            let folders = VaultFolderService.shared.folders
            print("Folders (\(folders.count)):")
            for folder in folders {
                let depth = folder.relativePath.components(separatedBy: "/").count - 1
                let indent = String(repeating: "  ", count: depth)
                print("  \(indent)📁 \(folder.name) (\(folder.id.uuidString.prefix(8)))")
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
            print("Commands: list, create, rename, delete")
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
            print("Labels (\(labels.count)):")
            for label in labels {
                print("  [\(label.id.uuidString.prefix(8))] \(label.name) (\(label.colorHex))")
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
            guard let name = args.first else {
                print("Error: Label name required.")
                return
            }
            if let label = storage.labels.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                storage.deleteLabel(label.id)
                print("Deleted label: \(name)")
            } else {
                print("Error: Label '\(name)' not found")
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
        let query = args.joined(separator: " ")
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
            print("Trash (\(items.count) items):")
            for item in items {
                let age = item.deletedAt.formatted(.relative(presentation: .named))
                print("  [\(item.id.uuidString.prefix(8))] \(item.title) (\(item.itemType.rawValue)) — deleted \(age)")
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

    static func findFolder(named name: String) -> VaultFolder? {
        VaultFolderService.shared.folders.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
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

        NOTES
          cider-cli note list [--folder <name>]
          cider-cli note create <title> [--content <text>]
          cider-cli note get <id-prefix>
          cider-cli note pin <id-prefix>
          cider-cli note move <id-prefix> --folder <name>
          cider-cli note delete <id-prefix>

        TODOS
          cider-cli todo list [--completed]
          cider-cli todo create <title> [--due yyyy-MM-dd] [--priority high|medium|low]
          cider-cli todo complete <id-prefix>
          cider-cli todo delete <id-prefix>

        EVENTS
          cider-cli event list
          cider-cli event create <title> [--date yyyy-MM-dd]

        CONTACTS
          cider-cli contact list
          cider-cli contact create <name> [--email <email>] [--phone <phone>]

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
          cider-cli label delete <name>

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
        """)
    }
}
