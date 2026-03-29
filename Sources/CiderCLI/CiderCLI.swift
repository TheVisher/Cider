@testable import Cider
import Foundation

/// CiderCLI — Command-line interface to Cider's storage layer.
///
/// Usage:
///   cider-cli bookmark list [--folder <name>]
///   cider-cli bookmark add <url> [--title <title>] [--folder <name>]
///   cider-cli bookmark search <query>
///   cider-cli note list [--folder <name>]
///   cider-cli note create <title> [--content <text>] [--folder <name>]
///   cider-cli todo list
///   cider-cli todo create <title> [--due <yyyy-MM-dd>] [--priority high|medium|low]
///   cider-cli file list [--type image|pdf|video|audio|document|archive]
///   cider-cli folder list
///   cider-cli folder create <name> [--parent <name>]
///   cider-cli search <query>
///   cider-cli trash list
///   cider-cli trash restore <id>
///   cider-cli trash empty
///   cider-cli status
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

        // Wait for async storage initialization to complete
        // (NotesStorage, TodoCardStorage, etc. use Task { @MainActor } in init)
        try? await Task.sleep(for: .milliseconds(500))

        let subcommand = args.count > 1 ? args[1] : nil
        let remaining = Array(args.dropFirst(2))

        switch command {
        case "bookmark":
            await handleBookmark(subcommand: subcommand, args: remaining, service: bookmarkService)
        case "note":
            await handleNote(subcommand: subcommand, args: remaining, storage: notesStorage)
        case "todo":
            await handleTodo(subcommand: subcommand, args: remaining, storage: todoStorage)
        case "file":
            handleFile(subcommand: subcommand, args: remaining, service: vaultFileService)
        case "folder":
            handleFolder(subcommand: subcommand, args: remaining)
        case "search":
            await handleSearch(args: Array(args.dropFirst()))
        case "trash":
            handleTrash(subcommand: subcommand, args: remaining)
        case "status":
            handleStatus(bookmarkService: bookmarkService, notesStorage: notesStorage,
                         todoStorage: todoStorage, vaultFileService: vaultFileService)
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    // MARK: - Bookmark Commands

    static func handleBookmark(subcommand: String?, args: [String], service: VaultBookmarkService) async {
        switch subcommand {
        case "list":
            let folderName = parseFlag("--folder", from: args)
            let bookmarks: [Bookmark]
            if let folderName {
                let folder = VaultFolderService.shared.folders.first {
                    $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
                }
                bookmarks = service.bookmarks.filter { $0.folderID == folder?.id }
            } else {
                bookmarks = service.bookmarks
            }
            print("Bookmarks (\(bookmarks.count)):")
            for bm in bookmarks {
                let folder = bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) — \(bm.hostDisplay) (\(folder))")
            }

        case "add":
            guard let url = args.first else {
                print("Error: URL required. Usage: cider-cli bookmark add <url>")
                return
            }
            let title = parseFlag("--title", from: args)
            let folderName = parseFlag("--folder", from: args)
            let folderID = folderName.flatMap { name in
                VaultFolderService.shared.folders.first {
                    $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                }?.id
            }
            let bookmark = service.add(urlString: url, title: title)
            if var bookmark {
                if let folderID {
                    _ = service.assignBookmark(bookmark.id, toFolder: folderID)
                }
                print("Created bookmark: \(bookmark.title) (\(bookmark.id.uuidString.prefix(8)))")
            } else {
                print("Error: Could not create bookmark for URL: \(url)")
            }

        case "search":
            let query = args.joined(separator: " ")
            let results = service.bookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.urlString.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query)
            }
            print("Bookmark search for '\(query)' (\(results.count) results):")
            for bm in results {
                print("  [\(bm.id.uuidString.prefix(8))] \(bm.title) — \(bm.urlString)")
            }

        case "delete":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli bookmark delete <id-prefix>")
                return
            }
            if let bm = service.bookmarks.first(where: { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }) {
                let items = service.removeAll([bm])
                if let item = items.first {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .bookmark, trashItem: item))
                    print("Deleted: \(bm.title) (moved to trash)")
                }
            } else {
                print("Error: No bookmark found with ID prefix: \(idPrefix)")
            }

        default:
            print("Unknown bookmark command: \(subcommand ?? "nil")")
            print("Usage: cider-cli bookmark [list|add|search|delete]")
        }
    }

    // MARK: - Note Commands

    static func handleNote(subcommand: String?, args: [String], storage: NotesStorage) async {
        switch subcommand {
        case "list":
            let folderName = parseFlag("--folder", from: args)
            let notes: [Note]
            if let folderName {
                let folder = VaultFolderService.shared.folders.first {
                    $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
                }
                notes = storage.notes.filter { $0.folderID == folder?.id }
            } else {
                notes = storage.notes
            }
            print("Notes (\(notes.count)):")
            for note in notes {
                let folder = note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let pinned = note.isPinned ? " 📌" : ""
                print("  [\(note.id.uuidString.prefix(8))] \(note.title)\(pinned) (\(folder))")
            }

        case "create":
            let title = args.first ?? "Untitled"
            let content = parseFlag("--content", from: args) ?? ""
            let note = storage.createNew(initialContent: content)
            if !title.isEmpty, title != "Untitled" {
                storage.rename(note: note, to: title)
            }
            print("Created note: \(note.title) (\(note.id.uuidString.prefix(8)))")

        default:
            print("Unknown note command: \(subcommand ?? "nil")")
            print("Usage: cider-cli note [list|create]")
        }
    }

    // MARK: - Todo Commands

    static func handleTodo(subcommand: String?, args: [String], storage: TodoCardStorage) async {
        switch subcommand {
        case "list":
            let todos = storage.todoCards
            print("Todos (\(todos.count)):")
            for todo in todos {
                let status = todo.isCompleted ? "✅" : "⬜"
                let due = todo.dueDate.map { " due: \(ISO8601DateFormatter().string(from: $0))" } ?? ""
                let priority = todo.priority.map { " [\($0.rawValue)]" } ?? ""
                print("  \(status) [\(todo.id.uuidString.prefix(8))] \(todo.title)\(priority)\(due)")
            }

        case "create":
            let title = args.first ?? "Untitled Todo"
            let dueString = parseFlag("--due", from: args)
            let priorityString = parseFlag("--priority", from: args)

            var dueDate: Date?
            if let dueString {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                dueDate = f.date(from: dueString)
            }

            let priority: TodoPriority?
            switch priorityString?.lowercased() {
            case "high": priority = .high
            case "medium": priority = .medium
            case "low": priority = .low
            default: priority = nil
            }

            let todo = storage.createTodoCard(
                title: title,
                dueDate: dueDate,
                priority: priority
            )
            print("Created todo: \(todo.title) (\(todo.id.uuidString.prefix(8)))")

        default:
            print("Unknown todo command: \(subcommand ?? "nil")")
            print("Usage: cider-cli todo [list|create]")
        }
    }

    // MARK: - File Commands

    static func handleFile(subcommand: String?, args: [String], service: VaultFileService) {
        switch subcommand {
        case "list":
            let typeFilter = parseFlag("--type", from: args)
            var files = service.files
            if let typeFilter {
                let fileType = VaultFileType(rawValue: typeFilter)
                if let fileType {
                    files = files.filter { $0.fileType == fileType }
                }
            }
            print("Vault files (\(files.count)):")
            for file in files {
                let folder = file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox"
                let size = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                print("  [\(file.id.uuidString.prefix(8))] \(file.displayTitle) — \(file.fileType.displayName), \(size) (\(folder))")
            }

        default:
            print("Unknown file command: \(subcommand ?? "nil")")
            print("Usage: cider-cli file [list]")
        }
    }

    // MARK: - Folder Commands

    static func handleFolder(subcommand: String?, args: [String]) {
        switch subcommand {
        case "list":
            let folders = VaultFolderService.shared.folders
            print("Folders (\(folders.count)):")
            for folder in folders {
                let indent = folder.relativePath.components(separatedBy: "/").count - 1
                let prefix = String(repeating: "  ", count: indent)
                print("  \(prefix)📁 \(folder.name) (\(folder.id.uuidString.prefix(8)))")
            }

        case "create":
            let name = args.first ?? "New Folder"
            let parentName = parseFlag("--parent", from: args)
            let parentID: UUID?
            if let parentName {
                parentID = VaultFolderService.shared.folders.first {
                    $0.name.localizedCaseInsensitiveCompare(parentName) == .orderedSame
                }?.id
            } else {
                parentID = nil
            }
            if let folder = VaultFolderService.shared.createFolder(name: name, parentID: parentID) {
                print("Created folder: \(folder.name) (\(folder.id.uuidString.prefix(8)))")
            } else {
                print("Error: Could not create folder: \(name)")
            }

        default:
            print("Unknown folder command: \(subcommand ?? "nil")")
            print("Usage: cider-cli folder [list|create]")
        }
    }

    // MARK: - Search

    static func handleSearch(args: [String]) async {
        let query = args.joined(separator: " ")
        guard !query.isEmpty else {
            print("Usage: cider-cli search <query>")
            return
        }

        let results = await SearchService.search(
            query: query,
            bookmarks: VaultBookmarkService.shared.bookmarks,
            notes: NotesStorage.shared.notes
        )

        print("Search results for '\(query)' (\(results.count)):")
        for result in results {
            let typeIcon: String
            switch result.type {
            case .bookmark: typeIcon = "🔖"
            case .note: typeIcon = "📝"
            case .dateCard: typeIcon = "📅"
            case .contact: typeIcon = "👤"
            case .todo: typeIcon = "☑️"
            case .session: typeIcon = "🌐"
            case .vaultFile: typeIcon = "📎"
            }
            print("  \(typeIcon) [\(result.id.uuidString.prefix(8))] \(result.title)")
        }
    }

    // MARK: - Trash Commands

    static func handleTrash(subcommand: String?, args: [String]) {
        switch subcommand {
        case "list":
            let items = TrashStorage.shared.allTrashItems()
            print("Trash (\(items.count) items):")
            for item in items {
                let age = item.deletedAt.formatted(.relative(presentation: .named))
                print("  [\(item.id.uuidString.prefix(8))] \(item.title) (\(item.itemType.rawValue)) — deleted \(age)")
            }

        case "restore":
            guard let idPrefix = args.first else {
                print("Error: ID prefix required. Usage: cider-cli trash restore <id-prefix>")
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
            TrashStorage.shared.emptyTrash()
            print("Trash emptied.")

        default:
            print("Unknown trash command: \(subcommand ?? "nil")")
            print("Usage: cider-cli trash [list|restore|empty]")
        }
    }

    // MARK: - Status

    static func handleStatus(bookmarkService: VaultBookmarkService, notesStorage: NotesStorage,
                              todoStorage: TodoCardStorage, vaultFileService: VaultFileService) {
        let folders = VaultFolderService.shared.folders
        let trash = TrashStorage.shared.allTrashItems()
        let labels = CardLabelStorage.shared.labels

        print("Cider Vault Status")
        print("──────────────────")
        print("  Bookmarks:    \(bookmarkService.bookmarks.count)")
        print("  Notes:        \(notesStorage.notes.count)")
        print("  Todos:        \(todoStorage.todoCards.count)")
        print("  Date Cards:   \(DateCardStorage.shared.dateCards.count)")
        print("  Contacts:     \(ContactStorage.shared.contacts.count)")
        print("  Vault Files:  \(vaultFileService.files.count)")
        print("  Sessions:     \(BrowserSessionStorage.shared.sessions.count)")
        print("  Folders:      \(folders.count)")
        print("  Labels:       \(labels.count)")
        print("  Trash:        \(trash.count) items")
        print("  Vault Root:   \(StoragePaths.cachedVaultDirectoryURL.path)")
    }

    // MARK: - Helpers

    static func parseFlag(_ flag: String, from args: [String]) -> String? {
        guard let flagIndex = args.firstIndex(of: flag),
              flagIndex + 1 < args.count else { return nil }
        return args[flagIndex + 1]
    }

    static func printUsage() {
        print("""
        CiderCLI — Command-line interface to Cider's vault

        Usage:
          cider-cli bookmark list [--folder <name>]
          cider-cli bookmark add <url> [--title <title>] [--folder <name>]
          cider-cli bookmark search <query>
          cider-cli bookmark delete <id-prefix>
          cider-cli note list [--folder <name>]
          cider-cli note create <title> [--content <text>]
          cider-cli todo list
          cider-cli todo create <title> [--due <yyyy-MM-dd>] [--priority high|medium|low]
          cider-cli file list [--type image|pdf|video|audio|document|archive]
          cider-cli folder list
          cider-cli folder create <name> [--parent <name>]
          cider-cli search <query>
          cider-cli trash list
          cider-cli trash restore <id-prefix>
          cider-cli trash empty
          cider-cli status
        """)
    }
}
