import Foundation
import os

/// Types of data stored in the Cider Vault, each in its own subdirectory.
enum StorageType: String, CaseIterable {
    case bookmarks = "Bookmarks"
    case notes = "Notes"
    case contacts = "Contacts"
    case dateCards = "DateCards"
    case tags = "Tags"
    case stacks = "Stacks"
    case labels = "Labels"
    case retiredViewCompatibility = "SavedViews"
    case sources = "Sources"
    case todos = "Todos"
    case clipboard = "Clipboard"
    case whiteboards = "Whiteboards"
    case sessions = "Sessions"
    case kanbanBoards = "KanbanBoards"
    case folderKanban = "FolderKanban"
    case dashboard = "Dashboard"

    /// Lowercase/hyphenated subdirectory name inside `.cider/`.
    var ciderSubpath: String {
        switch self {
        case .bookmarks: return "bookmarks"
        case .notes: return "notes"
        case .contacts: return "contacts"
        case .dateCards: return "date-cards"
        case .tags: return "tags"
        case .stacks: return "stacks"
        case .labels: return "labels"
        case .retiredViewCompatibility: return "saved-views"
        case .sources: return "sources"
        case .todos: return "todos"
        case .clipboard: return "clipboard"
        case .whiteboards: return "whiteboards"
        case .sessions: return "sessions"
        case .kanbanBoards: return "boards"
        case .folderKanban: return "folder-kanban"
        case .dashboard: return "dashboard"
        }
    }

    /// User-facing subfolder name inside `Inbox/` for content files.
    /// Only types with per-file content have inbox subfolders.
    var inboxSubfolderName: String? {
        switch self {
        case .bookmarks: return "Bookmarks"
        case .notes: return "Notes"
        case .contacts: return "Contacts"
        case .todos: return "Todos"
        case .dateCards: return "Date Cards"
        default: return nil
        }
    }
}

enum StoragePaths {
    /// Hidden directory inside the vault root that holds all app-internal data.
    static let ciderInternalDir = ".cider"

    /// Visible directory for unfiled content files (bookmarks, notes, etc.).
    static let inboxDir = "Inbox"

    /// Visible directory for user-owned rich Spaces.
    static let spacesDir = "Spaces"

    /// Lock protecting the mutable cache dictionary from concurrent access.
    /// `cachedDirectoryURL(for:)` is called from background threads (e.g., NoteCardData.load),
    /// so the dictionary needs synchronization. Simple `URL?` optionals are practically atomic
    /// on 64-bit, but `Dictionary` mutation during a concurrent read crashes with EXC_BAD_ACCESS.
    /// Uses OSAllocatedUnfairLock per codebase convention (faster than NSLock, no ObjC overhead).
    private static let _lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _cachedVaultURL: URL?
    nonisolated(unsafe) private static var _cachedTypeURLs: [StorageType: URL] = [:]

    /// Process-local vault root override. When non-nil, takes precedence over
    /// `CiderConfig.vaultDirectory` and bypasses per-type `directoryOverrides`.
    /// Used by `cider-cli --vault <path>` to point at a sandbox vault without
    /// touching the user's saved config. Must be set BEFORE any service touches
    /// `cachedVaultDirectoryURL` (which memoizes on first read).
    nonisolated(unsafe) static var vaultOverride: URL?

    // MARK: - Vault Root

    /// Returns the vault root directory URL, expanding tildes.
    static func vaultDirectoryURL(config: CiderConfig = CiderConfig.load()) -> URL {
        if let override = vaultOverride { return override }
        let expanded = NSString(string: config.vaultDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Cached vault root URL.
    static var cachedVaultDirectoryURL: URL {
        _lock.lock()
        defer { _lock.unlock() }
        if let cached = _cachedVaultURL { return cached }
        let url = vaultDirectoryURL()
        _cachedVaultURL = url
        return url
    }

    // MARK: - Per-Type Directory

    /// Returns the directory URL for a specific storage type.
    /// Checks for a user override first, then falls back to vault subdirectory.
    /// When `vaultOverride` is set (sandbox mode), per-type overrides are ignored
    /// so that all storage stays inside the sandbox vault.
    static func directoryURL(for type: StorageType, config: CiderConfig = CiderConfig.load()) -> URL {
        if vaultOverride == nil,
           let override = config.directoryOverrides[type.rawValue],
           !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return vaultDirectoryURL(config: config)
            .appendingPathComponent(ciderInternalDir)
            .appendingPathComponent(type.ciderSubpath)
    }

    /// Cached per-type directory URL — avoids repeated config loads in render paths.
    /// Thread-safe: called from background threads (NoteCardData, image loading).
    static func cachedDirectoryURL(for type: StorageType) -> URL {
        _lock.lock()
        if let cached = _cachedTypeURLs[type] {
            _lock.unlock()
            return cached
        }
        _lock.unlock()
        let url = directoryURL(for: type)
        _lock.lock()
        _cachedTypeURLs[type] = url
        _lock.unlock()
        return url
    }

    // MARK: - Cache Invalidation

    static func invalidateCachedDirectory() {
        _lock.lock()
        _cachedVaultURL = nil
        _cachedTypeURLs.removeAll()
        _lock.unlock()
    }

    // MARK: - Inbox

    /// Returns the Inbox subdirectory URL for a given storage type (e.g. `~/CiderVault/Inbox/Bookmarks/`).
    static func inboxSubdirectoryURL(for type: StorageType, config: CiderConfig = CiderConfig.load()) -> URL {
        let name = type.inboxSubfolderName ?? type.rawValue
        return vaultDirectoryURL(config: config)
            .appendingPathComponent(inboxDir)
            .appendingPathComponent(name)
    }

    /// Cached Inbox subdirectory URL for a storage type.
    static func cachedInboxSubdirectoryURL(for type: StorageType) -> URL {
        let name = type.inboxSubfolderName ?? type.rawValue
        return cachedVaultDirectoryURL
            .appendingPathComponent(inboxDir)
            .appendingPathComponent(name)
    }

    // MARK: - Helpers

    static func jsonFileURL(fileName: String, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func ensureDirectory(_ directoryURL: URL) {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    /// Ensures all vault subdirectories exist (called on launch).
    static func ensureVaultStructure(config: CiderConfig = CiderConfig.load()) {
        let vaultRoot = vaultDirectoryURL(config: config)
        // Create .cider/ parent first
        ensureDirectory(vaultRoot.appendingPathComponent(ciderInternalDir))
        for type in StorageType.allCases {
            ensureDirectory(directoryURL(for: type, config: config))
        }
        // Create Inbox/ and its subfolders
        let inboxRoot = vaultRoot.appendingPathComponent(inboxDir)
        ensureDirectory(inboxRoot)
        for type in StorageType.allCases {
            if type.inboxSubfolderName != nil {
                ensureDirectory(inboxSubdirectoryURL(for: type, config: config))
            }
        }
        // Create Spaces/ so user-owned contexts are Finder-visible even before the first Space is created.
        ensureDirectory(vaultRoot.appendingPathComponent(spacesDir))
        // Create agent memory directories
        let memoryDir = vaultRoot.appendingPathComponent(ciderInternalDir).appendingPathComponent("memory")
        ensureDirectory(memoryDir)
        ensureDirectory(memoryDir.appendingPathComponent("daily"))
        ensureDirectory(memoryDir.appendingPathComponent("concepts"))
        ensureDirectory(memoryDir.appendingPathComponent("reviews"))
        seedMemoryTemplates(memoryDir: memoryDir)
    }

    /// Seeds default memory template files if they don't already exist.
    private static func seedMemoryTemplates(memoryDir: URL) {
        let fm = FileManager.default

        let indexURL = memoryDir.appendingPathComponent("index.md")
        if !fm.fileExists(atPath: indexURL.path) {
            let content = """
            ---
            type: index
            updated: '\(Self.todayString())'
            ---

            # Memory Index

            ## Core (loaded every session)
            - [user.md](user.md) — user preferences, patterns, context
            - [agent.md](agent.md) — agent conventions, workflows, learnings

            ## Daily Notes
            - `daily/YYYY-MM-DD.md` — raw observations from interactions
            - `reviews/YYYY-W##.md` — weekly memory reviews and synthesis

            ## Working State
            - [open_loops.md](open_loops.md) — active follow-ups and unfinished threads

            ## Concepts (load on-demand when relevant)
            - *(none yet — add when synthesis needs emerge)*
            """
            try? content.write(to: indexURL, atomically: true, encoding: .utf8)
        }

        let openLoopsURL = memoryDir.appendingPathComponent("open_loops.md")
        if !fm.fileExists(atPath: openLoopsURL.path) {
            let content = """
            ---
            type: open-loops
            updated: '\(Self.todayString())'
            ---

            # Open Loops

            *(No obvious open loops detected yet.)*
            """
            try? content.write(to: openLoopsURL, atomically: true, encoding: .utf8)
        }

        let userURL = memoryDir.appendingPathComponent("user.md")
        if !fm.fileExists(atPath: userURL.path) {
            let content = """
            ---
            type: user
            updated: '\(Self.todayString())'
            ---

            ## Identity

            - Name:
            - Location:

            ## Preferences

            *(Agent will fill this in as it learns about you)*
            """
            try? content.write(to: userURL, atomically: true, encoding: .utf8)
        }

        let agentURL = memoryDir.appendingPathComponent("agent.md")
        if !fm.fileExists(atPath: agentURL.path) {
            let content = """
            ---
            type: agent
            updated: '\(Self.todayString())'
            ---

            ## Retrieval Order

            1. Query Cider CLI first for facts
            2. Consult memory files for personal context or prior conclusions
            3. Never trust memory over current vault state

            ## Conventions

            *(Agent will fill this in as it learns your workflows)*
            """
            try? content.write(to: agentURL, atomically: true, encoding: .utf8)
        }
    }

    private static func todayString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
