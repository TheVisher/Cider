import Foundation
import os

/// An entry in the vault index — tracks where an item lives on disk and its key metadata.
struct VaultIndexEntry: Codable {
    var type: String          // "bookmark", "note", "todo", "dateCard", "contact"
    var path: String          // relative to vault root, e.g. "Work/meeting-notes.md"
    var title: String
    var url: String?          // bookmarks only
    var tags: [String]?
    var labelIDs: [UUID]?
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

/// Wrapper for the JSON file on disk.
private struct VaultIndexFile: Codable {
    var version: Int = 1
    var items: [String: VaultIndexEntry]  // UUID string → entry
}

/// Maintains a fast-lookup index of all items in the vault and their file paths.
/// This is the "table of contents" — one JSON file at the vault root that AI tools
/// and Cider both read for instant access without scanning every folder.
///
/// The actual files on disk are the source of truth. The index is a cache that can
/// be rebuilt from a full scan if it ever gets out of sync.
@MainActor
final class VaultIndexService {
    static let shared = VaultIndexService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultIndexService"
    )

    /// All indexed items.
    private(set) var entries: [UUID: VaultIndexEntry] = [:]

    private let indexFileName = ".cider-index.json"

    private var indexFileURL: URL {
        StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(indexFileName)
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private init() {
        loadIndex()
    }

    // MARK: - CRUD

    /// Registers or updates an item in the index.
    func upsert(id: UUID, entry: VaultIndexEntry) {
        entries[id] = entry
        saveIndex()
    }

    /// Updates just the path for an item (e.g. when moved to a different folder).
    func updatePath(id: UUID, newPath: String) {
        guard var entry = entries[id] else { return }
        entry.path = newPath
        entry.updatedAt = Date()
        entries[id] = entry
        saveIndex()
    }

    /// Updates the folder ID for an item.
    func updateFolder(id: UUID, folderID: UUID?) {
        guard var entry = entries[id] else { return }
        entry.folderID = folderID
        entry.updatedAt = Date()
        entries[id] = entry
        saveIndex()
    }

    /// Removes an item from the index.
    func remove(id: UUID) {
        entries.removeValue(forKey: id)
        saveIndex()
    }

    // MARK: - Queries

    /// Returns the entry for a given item ID.
    func entry(for id: UUID) -> VaultIndexEntry? {
        entries[id]
    }

    /// Returns the absolute file URL for an indexed item.
    func fileURL(for id: UUID) -> URL? {
        guard let entry = entries[id] else { return nil }
        return vaultRoot.appendingPathComponent(entry.path)
    }

    /// Returns all entries of a given type.
    func entries(ofType type: String) -> [(UUID, VaultIndexEntry)] {
        entries.filter { $0.value.type == type }.map { ($0.key, $0.value) }
    }

    /// Returns all entries in a given folder.
    func entries(inFolder folderID: UUID) -> [(UUID, VaultIndexEntry)] {
        entries.filter { $0.value.folderID == folderID }.map { ($0.key, $0.value) }
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let file = try? JSONDecoder().decode(VaultIndexFile.self, from: data) else {
            entries = [:]
            return
        }

        // Convert string keys to UUIDs
        var loaded: [UUID: VaultIndexEntry] = [:]
        for (key, value) in file.items {
            if let uuid = UUID(uuidString: key) {
                loaded[uuid] = value
            }
        }
        entries = loaded
        logger.info("Loaded vault index: \(self.entries.count) items")
    }

    func saveIndex() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, $0.value) })
        let file = VaultIndexFile(items: stringKeyed)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }

    /// Rebuilds the index from existing storage services.
    /// Called as a fallback if the index is missing or corrupt.
    func rebuildFromCurrentState() {
        var rebuilt: [UUID: VaultIndexEntry] = [:]

        // Notes
        for note in NotesStorage.shared.notes {
            rebuilt[note.id] = VaultIndexEntry(
                type: "note",
                path: note.relativePath,
                title: note.title,
                labelIDs: note.labelIDs.isEmpty ? nil : note.labelIDs,
                folderID: note.folderID,
                createdAt: note.createdAt,
                updatedAt: note.modifiedAt
            )
        }

        // Bookmarks
        for bookmark in BookmarksStorage.shared.bookmarks {
            rebuilt[bookmark.id] = VaultIndexEntry(
                type: "bookmark",
                path: "Bookmarks/\(bookmark.id.uuidString).json",
                title: bookmark.title,
                url: bookmark.urlString,
                tags: bookmark.tags.isEmpty ? nil : bookmark.tags,
                labelIDs: bookmark.labelIDs.isEmpty ? nil : bookmark.labelIDs,
                folderID: bookmark.folderID,
                createdAt: bookmark.createdAt,
                updatedAt: bookmark.updatedAt
            )
        }

        // Todos
        for todo in TodoCardStorage.shared.todoCards {
            rebuilt[todo.id] = VaultIndexEntry(
                type: "todo",
                path: "Todos/\(todo.id.uuidString).json",
                title: todo.title,
                labelIDs: todo.labelIDs.isEmpty ? nil : todo.labelIDs,
                folderID: todo.folderID,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt
            )
        }

        // Date Cards
        for dc in DateCardStorage.shared.dateCards {
            rebuilt[dc.id] = VaultIndexEntry(
                type: "dateCard",
                path: "DateCards/\(dc.id.uuidString).json",
                title: dc.title,
                labelIDs: dc.labelIDs.isEmpty ? nil : dc.labelIDs,
                folderID: dc.folderID,
                createdAt: dc.createdAt,
                updatedAt: dc.updatedAt
            )
        }

        // Contacts
        for contact in ContactStorage.shared.contacts {
            rebuilt[contact.id] = VaultIndexEntry(
                type: "contact",
                path: "Contacts/\(contact.id.uuidString).json",
                title: contact.displayName,
                labelIDs: contact.labelIDs.isEmpty ? nil : contact.labelIDs,
                folderID: contact.folderID,
                createdAt: contact.createdAt,
                updatedAt: contact.updatedAt
            )
        }

        entries = rebuilt
        saveIndex()
        logger.info("Rebuilt vault index: \(rebuilt.count) items")
    }

    /// Called when the vault root changes.
    func updateVaultRoot() {
        loadIndex()
    }
}
