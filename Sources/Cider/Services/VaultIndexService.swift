import Combine
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

    private var cancellables = Set<AnyCancellable>()
    private var rebuildWorkItem: DispatchWorkItem?

    private var indexFileURL: URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("index.json")
    }

    private var vaultRoot: URL {
        StoragePaths.cachedVaultDirectoryURL
    }

    private init() {
        loadIndex()
        observeStorageChanges()
    }

    // MARK: - Auto-sync with storage services

    /// Observes all storage services and rebuilds the index when any of them change.
    /// Debounced to 2 seconds so rapid edits don't thrash the disk.
    private func observeStorageChanges() {
        let rebuild = { [weak self] in
            self?.scheduleRebuild()
        }

        NotesStorage.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in rebuild() }
            .store(in: &cancellables)

        VaultBookmarkService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in rebuild() }
            .store(in: &cancellables)

        TodoCardStorage.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in rebuild() }
            .store(in: &cancellables)

        DateCardStorage.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in rebuild() }
            .store(in: &cancellables)

        ContactStorage.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in rebuild() }
            .store(in: &cancellables)
    }

    /// Debounced rebuild — coalesces rapid changes into a single index update.
    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildFromCurrentState()
            }
        }
        rebuildWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexFileURL),
              let file = try? decoder.decode(VaultIndexFile.self, from: data) else {
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

        // Bookmarks — use the bookmark's actual relativePath when available
        for bookmark in VaultBookmarkService.shared.bookmarks {
            let path: String
            if let rp = bookmark.relativePath, !rp.isEmpty {
                // Drop the .webloc filename to get the directory, then add the JSON sidecar path
                let dirPath = (rp as NSString).deletingLastPathComponent
                path = "\(dirPath)/\(bookmark.id.uuidString).json"
            } else {
                path = "\(StoragePaths.inboxDir)/Bookmarks/\(bookmark.id.uuidString).json"
            }
            rebuilt[bookmark.id] = VaultIndexEntry(
                type: "bookmark",
                path: path,
                title: bookmark.title,
                url: bookmark.urlString,
                tags: bookmark.tags.isEmpty ? nil : bookmark.tags,
                labelIDs: bookmark.labelIDs.isEmpty ? nil : bookmark.labelIDs,
                folderID: bookmark.folderID,
                createdAt: bookmark.createdAt,
                updatedAt: bookmark.updatedAt
            )
        }

        // Todos — use actual .ics file path from TodoCardStorage
        for todo in TodoCardStorage.shared.todoCards {
            let path: String
            if let fileURL = TodoCardStorage.shared.resolveFileURL(for: todo.id) {
                path = fileURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            } else {
                path = "\(StoragePaths.inboxDir)/Todos/\(todo.id.uuidString).ics"
            }
            rebuilt[todo.id] = VaultIndexEntry(
                type: "todo",
                path: path,
                title: todo.title,
                labelIDs: todo.labelIDs.isEmpty ? nil : todo.labelIDs,
                folderID: todo.folderID,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt
            )
        }

        // Date Cards — use actual .ics file path from DateCardStorage
        for dc in DateCardStorage.shared.dateCards {
            let path: String
            if let fileURL = DateCardStorage.shared.resolveFileURL(for: dc.id) {
                path = fileURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            } else {
                path = "\(StoragePaths.inboxDir)/Date Cards/\(dc.id.uuidString).ics"
            }
            rebuilt[dc.id] = VaultIndexEntry(
                type: "dateCard",
                path: path,
                title: dc.title,
                labelIDs: dc.labelIDs.isEmpty ? nil : dc.labelIDs,
                folderID: dc.folderID,
                createdAt: dc.createdAt,
                updatedAt: dc.updatedAt
            )
        }

        // Contacts — use actual .vcf file path from ContactStorage
        for contact in ContactStorage.shared.contacts {
            let path: String
            if let fileURL = ContactStorage.shared.resolveFileURL(for: contact.id) {
                path = fileURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            } else {
                path = "\(StoragePaths.inboxDir)/Contacts/\(contact.id.uuidString).vcf"
            }
            rebuilt[contact.id] = VaultIndexEntry(
                type: "contact",
                path: path,
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
