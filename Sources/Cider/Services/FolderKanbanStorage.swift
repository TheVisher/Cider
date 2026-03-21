import Foundation
import Yams
import os.log

/// Per-folder kanban column configuration stored as YAML in `.cider/folder-kanban/`.
/// Each folder with kanban columns gets a `{folderID}.yaml` file.
///
/// Columns contain references to library item IDs (e.g. "bookmark-{uuid}").
/// Items not assigned to any column appear in an "Uncategorized" bucket in the UI.
@MainActor
final class FolderKanbanStorage: ObservableObject {
    static let shared = FolderKanbanStorage()

    @Published private var configs: [UUID: FolderKanbanConfig] = [:]

    private let logger = Logger(subsystem: "com.cider.app", category: "FolderKanbanStorage")

    private var storageDir: URL {
        StoragePaths.directoryURL(for: .folderKanban)
    }

    init() {
        ensureDirectory()
        loadAll()
    }

    // MARK: - Directory

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Load

    private func loadAll() {
        ensureDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for file in files where file.pathExtension == "yaml" {
            let stem = file.deletingPathExtension().lastPathComponent
            guard let folderID = UUID(uuidString: stem) else { continue }
            if let config = loadFile(file) {
                configs[folderID] = config
            }
        }
    }

    private func loadFile(_ url: URL) -> FolderKanbanConfig? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(FolderKanbanConfig.self, from: content)
        } catch {
            logger.error("Failed to decode \(url.lastPathComponent): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Save

    private func save(folderID: UUID) {
        guard let config = configs[folderID] else { return }
        do {
            let encoder = YAMLEncoder()
            let yaml = try encoder.encode(config)
            let url = storageDir.appendingPathComponent("\(folderID.uuidString).yaml")
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to save folder kanban \(folderID): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mutate(folderID: UUID, _ body: (inout FolderKanbanConfig) -> Void) {
        if configs[folderID] == nil {
            configs[folderID] = FolderKanbanConfig(columns: [])
        }
        body(&configs[folderID]!)
        save(folderID: folderID)
    }

    // MARK: - Public API

    func config(for folderID: UUID) -> FolderKanbanConfig? {
        configs[folderID]
    }

    func columns(for folderID: UUID) -> [FolderKanbanColumn] {
        configs[folderID]?.columns ?? []
    }

    /// All item IDs assigned to any column for this folder.
    func assignedItemIDs(for folderID: UUID) -> Set<String> {
        guard let config = configs[folderID] else { return [] }
        return config.columns.reduce(into: Set<String>()) { result, col in
            result.formUnion(col.itemIDs)
        }
    }

    // MARK: - Column Operations

    @discardableResult
    func addColumn(folderID: UUID, name: String) -> FolderKanbanColumn {
        let column = FolderKanbanColumn(
            id: KanbanID.generate(),
            name: name
        )
        mutate(folderID: folderID) { config in
            config.columns.append(column)
        }
        return column
    }

    func renameColumn(folderID: UUID, columnID: String, name: String) {
        mutate(folderID: folderID) { config in
            guard let i = config.columns.firstIndex(where: { $0.id == columnID }) else { return }
            config.columns[i].name = name
        }
    }

    func deleteColumn(folderID: UUID, columnID: String) {
        mutate(folderID: folderID) { config in
            config.columns.removeAll { $0.id == columnID }
        }
    }

    func moveColumn(folderID: UUID, columnID: String, toIndex: Int) {
        mutate(folderID: folderID) { config in
            guard let fromIndex = config.columns.firstIndex(where: { $0.id == columnID }) else { return }
            let column = config.columns.remove(at: fromIndex)
            let insertAt = min(toIndex, config.columns.count)
            config.columns.insert(column, at: insertAt)
        }
    }

    // MARK: - Item Assignment

    func assignItem(folderID: UUID, itemID: String, toColumnID: String, atIndex: Int? = nil) {
        mutate(folderID: folderID) { config in
            // Remove from any existing column
            for i in config.columns.indices {
                config.columns[i].itemIDs.removeAll { $0 == itemID }
            }
            // Add to target column
            guard let colIdx = config.columns.firstIndex(where: { $0.id == toColumnID }) else { return }
            let insertAt = min(atIndex ?? config.columns[colIdx].itemIDs.count, config.columns[colIdx].itemIDs.count)
            config.columns[colIdx].itemIDs.insert(itemID, at: insertAt)
        }
    }

    func unassignItem(folderID: UUID, itemID: String) {
        mutate(folderID: folderID) { config in
            for i in config.columns.indices {
                config.columns[i].itemIDs.removeAll { $0 == itemID }
            }
        }
    }

    func moveItem(folderID: UUID, itemID: String, toColumnID: String, toIndex: Int) {
        assignItem(folderID: folderID, itemID: itemID, toColumnID: toColumnID, atIndex: toIndex)
    }

    // MARK: - Cleanup

    /// Remove item IDs that no longer exist in the folder's items.
    func pruneStaleItems(folderID: UUID, validItemIDs: Set<String>) {
        guard let config = configs[folderID] else { return }
        let hasStale = config.columns.contains { col in
            col.itemIDs.contains { !validItemIDs.contains($0) }
        }
        guard hasStale else { return }
        mutate(folderID: folderID) { config in
            for i in config.columns.indices {
                config.columns[i].itemIDs.removeAll { !validItemIDs.contains($0) }
            }
        }
    }
}

// MARK: - Model

struct FolderKanbanConfig: Codable, Equatable {
    var columns: [FolderKanbanColumn]
}

struct FolderKanbanColumn: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var itemIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case itemIDs = "items"
    }

    init(id: String, name: String, itemIDs: [String] = []) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
    }
}
