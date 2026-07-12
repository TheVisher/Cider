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
    struct LegacyConversationPreviewDirectories: Equatable {
        let registry: URL
        let conversations: URL
    }

    enum VaultStructureOperation: String, Equatable {
        case createDirectory = "create directory"
        case writeCompatibilityTemplate = "write compatibility template"
    }

    struct VaultStructureFailure: Equatable {
        let operation: VaultStructureOperation
        let path: String
        let underlyingError: String
    }

    struct VaultStructureInitializationReport: Equatable {
        let failures: [VaultStructureFailure]

        var isFullyInitialized: Bool { failures.isEmpty }
    }

    struct VaultStructureFileSystem: Sendable {
        let createDirectory: @Sendable (URL) throws -> Void
        let fileExists: @Sendable (URL) -> Bool
        let writeUTF8Atomically: @Sendable (String, URL) throws -> Void

        static let live = VaultStructureFileSystem(
            createDirectory: {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            writeUTF8Atomically: { content, url in
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        )
    }

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
    static func vaultDirectoryURL(
        config: CiderConfig? = nil,
        isolationConfiguration: IsolationConfiguration? = nil
    ) -> URL {
        IsolationRuntime.recordPathAccess("StoragePaths.vaultDirectoryURL")
        if let isolatedVault = (isolationConfiguration ?? IsolationRuntime.configuration).vaultRoot {
            return isolatedVault
        }
        if let override = vaultOverride { return override }
        let effectiveConfig = config ?? CiderConfig.load()
        let expanded = NSString(string: effectiveConfig.vaultDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Resolves the established legacy conversation locations without touching the file system.
    /// Preview readers must use these URLs directly rather than constructing writer-backed stores.
    static func legacyConversationPreviewDirectories(
        config: CiderConfig? = nil
    ) -> LegacyConversationPreviewDirectories {
        let internalDirectory = vaultDirectoryURL(config: config)
            .appendingPathComponent(ciderInternalDir, isDirectory: true)
        return LegacyConversationPreviewDirectories(
            registry: internalDirectory.appendingPathComponent("agent-chats", isDirectory: true),
            conversations: internalDirectory.appendingPathComponent("ai-conversations", isDirectory: true)
        )
    }

    /// Cached vault root URL.
    static var cachedVaultDirectoryURL: URL {
        IsolationRuntime.recordPathAccess("StoragePaths.cachedVaultDirectoryURL")
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
    static func directoryURL(for type: StorageType, config: CiderConfig? = nil) -> URL {
        IsolationRuntime.recordPathAccess("StoragePaths.directoryURL")
        if let isolatedVault = IsolationRuntime.configuration.vaultRoot {
            return isolatedVault
                .appendingPathComponent(ciderInternalDir)
                .appendingPathComponent(type.ciderSubpath)
        }
        let effectiveConfig = config ?? CiderConfig.load()
        if vaultOverride == nil,
           let override = effectiveConfig.directoryOverrides[type.rawValue],
           !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return vaultDirectoryURL(config: effectiveConfig)
            .appendingPathComponent(ciderInternalDir)
            .appendingPathComponent(type.ciderSubpath)
    }

    /// Cached per-type directory URL — avoids repeated config loads in render paths.
    /// Thread-safe: called from background threads (NoteCardData, image loading).
    static func cachedDirectoryURL(for type: StorageType) -> URL {
        IsolationRuntime.recordPathAccess("StoragePaths.cachedDirectoryURL")
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
    static func inboxSubdirectoryURL(for type: StorageType, config: CiderConfig? = nil) -> URL {
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

    /// Ensures all vault subdirectories exist (called on launch), returning every
    /// operation that failed so callers never mistake partial initialization for success.
    @discardableResult
    static func ensureVaultStructure(
        config: CiderConfig? = nil,
        fileSystem: VaultStructureFileSystem = .live
    ) -> VaultStructureInitializationReport {
        var failures: [VaultStructureFailure] = []
        let vaultRoot = vaultDirectoryURL(config: config)
        // Create .cider/ parent first
        createVaultDirectory(
            vaultRoot.appendingPathComponent(ciderInternalDir),
            fileSystem: fileSystem,
            failures: &failures
        )
        for type in StorageType.allCases {
            createVaultDirectory(
                directoryURL(for: type, config: config),
                fileSystem: fileSystem,
                failures: &failures
            )
        }
        // Create Inbox/ and its subfolders
        let inboxRoot = vaultRoot.appendingPathComponent(inboxDir)
        createVaultDirectory(inboxRoot, fileSystem: fileSystem, failures: &failures)
        for type in StorageType.allCases {
            if type.inboxSubfolderName != nil {
                createVaultDirectory(
                    inboxSubdirectoryURL(for: type, config: config),
                    fileSystem: fileSystem,
                    failures: &failures
                )
            }
        }
        // Create Spaces/ so user-owned contexts are Finder-visible even before the first Space is created.
        createVaultDirectory(
            vaultRoot.appendingPathComponent(spacesDir),
            fileSystem: fileSystem,
            failures: &failures
        )
        // Create agent memory directories
        let memoryDir = vaultRoot.appendingPathComponent(ciderInternalDir).appendingPathComponent("memory")
        createVaultDirectory(memoryDir, fileSystem: fileSystem, failures: &failures)
        createVaultDirectory(
            memoryDir.appendingPathComponent("daily"),
            fileSystem: fileSystem,
            failures: &failures
        )
        createVaultDirectory(
            memoryDir.appendingPathComponent("concepts"),
            fileSystem: fileSystem,
            failures: &failures
        )
        createVaultDirectory(
            memoryDir.appendingPathComponent("reviews"),
            fileSystem: fileSystem,
            failures: &failures
        )
        seedMemoryTemplates(memoryDir: memoryDir, fileSystem: fileSystem, failures: &failures)
        return VaultStructureInitializationReport(failures: failures)
    }

    private static func createVaultDirectory(
        _ directoryURL: URL,
        fileSystem: VaultStructureFileSystem,
        failures: inout [VaultStructureFailure]
    ) {
        do {
            try fileSystem.createDirectory(directoryURL)
        } catch {
            failures.append(VaultStructureFailure(
                operation: .createDirectory,
                path: directoryURL.path,
                underlyingError: error.localizedDescription
            ))
        }
    }

    /// Seeds default memory template files if they don't already exist.
    private static func seedMemoryTemplates(
        memoryDir: URL,
        fileSystem: VaultStructureFileSystem,
        failures: inout [VaultStructureFailure]
    ) {
        let indexURL = memoryDir.appendingPathComponent("index.md")
        if !fileSystem.fileExists(indexURL) {
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
            writeCompatibilityTemplate(
                content,
                to: indexURL,
                fileSystem: fileSystem,
                failures: &failures
            )
        }

        let openLoopsURL = memoryDir.appendingPathComponent("open_loops.md")
        if !fileSystem.fileExists(openLoopsURL) {
            let content = """
            ---
            type: open-loops
            updated: '\(Self.todayString())'
            ---

            # Open Loops

            *(No obvious open loops detected yet.)*
            """
            writeCompatibilityTemplate(
                content,
                to: openLoopsURL,
                fileSystem: fileSystem,
                failures: &failures
            )
        }

        let userURL = memoryDir.appendingPathComponent("user.md")
        if !fileSystem.fileExists(userURL) {
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
            writeCompatibilityTemplate(
                content,
                to: userURL,
                fileSystem: fileSystem,
                failures: &failures
            )
        }

        let agentURL = memoryDir.appendingPathComponent("agent.md")
        if !fileSystem.fileExists(agentURL) {
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
            writeCompatibilityTemplate(
                content,
                to: agentURL,
                fileSystem: fileSystem,
                failures: &failures
            )
        }
    }

    private static func writeCompatibilityTemplate(
        _ content: String,
        to url: URL,
        fileSystem: VaultStructureFileSystem,
        failures: inout [VaultStructureFailure]
    ) {
        do {
            try fileSystem.writeUTF8Atomically(content, url)
        } catch {
            failures.append(VaultStructureFailure(
                operation: .writeCompatibilityTemplate,
                path: url.path,
                underlyingError: error.localizedDescription
            ))
        }
    }

    private static func todayString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }
}
