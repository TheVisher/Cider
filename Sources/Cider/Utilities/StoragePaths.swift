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
    case savedViews = "SavedViews"
    case sources = "Sources"
    case todos = "Todos"
    case clipboard = "Clipboard"
    case whiteboards = "Whiteboards"
    case sessions = "Sessions"

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
        case .savedViews: return "saved-views"
        case .sources: return "sources"
        case .todos: return "todos"
        case .clipboard: return "clipboard"
        case .whiteboards: return "whiteboards"
        case .sessions: return "sessions"
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

    /// Lock protecting the mutable cache dictionary from concurrent access.
    /// `cachedDirectoryURL(for:)` is called from background threads (e.g., NoteCardData.load),
    /// so the dictionary needs synchronization. Simple `URL?` optionals are practically atomic
    /// on 64-bit, but `Dictionary` mutation during a concurrent read crashes with EXC_BAD_ACCESS.
    private static let _lock = NSLock()
    nonisolated(unsafe) private static var _cachedVaultURL: URL?
    nonisolated(unsafe) private static var _cachedTypeURLs: [StorageType: URL] = [:]

    // MARK: - Vault Root

    /// Returns the vault root directory URL, expanding tildes.
    static func vaultDirectoryURL(config: CiderConfig = CiderConfig.load()) -> URL {
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
    static func directoryURL(for type: StorageType, config: CiderConfig = CiderConfig.load()) -> URL {
        if let override = config.directoryOverrides[type.rawValue], !override.isEmpty {
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
    }
}
