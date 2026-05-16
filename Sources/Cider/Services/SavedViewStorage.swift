import Foundation
import Combine

private struct SavedViewsSnapshot: Codable {
    var savedViews: [SavedView]
    var tabOrder: [UUID]?
}

@MainActor
final class SavedViewStorage: ObservableObject {
    static let shared = SavedViewStorage()

    @Published private(set) var savedViews: [SavedView] = []
    @Published private(set) var tabOrder: [UUID] = []

    private let fileName = "_cider_saved_views.json"
    private let storageFileURL: URL?
    private var fileURL: URL {
        if let storageFileURL {
            return storageFileURL
        }
        let dir = StoragePaths.directoryURL(for: .savedViews)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    init(storageFileURL: URL? = nil) {
        self.storageFileURL = storageFileURL
        load()
    }

    func reload() {
        load()
    }

    // MARK: - Tab Order API

    /// Returns saved views in tab order.
    func tabOrderedViews() -> [SavedView] {
        tabOrder.compactMap { id in savedViews.first { $0.id == id } }
    }

    func addToTabOrder(_ id: UUID) {
        guard !tabOrder.contains(id) else { return }
        tabOrder.append(id)
        if let idx = savedViews.firstIndex(where: { $0.id == id }) {
            savedViews[idx].isTabPinned = true
        }
        persist()
    }

    func insertInTabOrder(_ id: UUID, at index: Int) {
        tabOrder.removeAll { $0 == id }
        let clampedIndex = min(max(index, 0), tabOrder.count)
        tabOrder.insert(id, at: clampedIndex)
        persist()
    }

    func removeFromTabOrder(_ id: UUID) {
        tabOrder.removeAll { $0 == id }
        if let idx = savedViews.firstIndex(where: { $0.id == id }) {
            savedViews[idx].isTabPinned = false
        }
        persist()
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabOrder.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabOrder.count else { return }
        let id = tabOrder.remove(at: sourceIndex)
        let insertAt = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabOrder.insert(id, at: min(insertAt, tabOrder.count))
        persist()
    }

    func renameSavedView(_ id: UUID, to name: String) {
        guard let idx = savedViews.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedViews[idx].name = trimmed
        savedViews[idx].updatedAt = Date()
        persist()
    }

    // MARK: - CRUD

    @discardableResult
    func createSavedView(
        name: String,
        filterSpec: SavedViewFilterSpec = SavedViewFilterSpec(),
        sortSpec: SavedViewSortSpec = SavedViewSortSpec(),
        layoutSpec: SavedViewLayoutSpec = SavedViewLayoutSpec(),
        isBlank: Bool = false,
        isOnboarding: Bool = false
    ) -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled View" : trimmed
        let savedView = SavedView(
            name: finalName,
            filterSpec: filterSpec,
            sortSpec: sortSpec,
            layoutSpec: layoutSpec,
            isBlank: isBlank,
            isOnboarding: isOnboarding
        )
        savedViews.append(savedView)
        tabOrder.append(savedView.id)
        persist()
        return savedView
    }

    @discardableResult
    func createDashboardView(name: String = "Dashboard") -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Dashboard" : trimmed
        let savedView = SavedView(
            name: finalName,
            kind: .dashboard
        )
        savedViews.append(savedView)
        tabOrder.append(savedView.id)
        persist()
        return savedView
    }

    @discardableResult
    func createKanbanView(name: String, boardID: String) -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Board" : trimmed
        let savedView = SavedView(
            name: finalName,
            kind: .kanban(boardID: boardID)
        )
        savedViews.append(savedView)
        tabOrder.append(savedView.id)
        persist()
        return savedView
    }

    func kanbanView(for boardID: String) -> SavedView? {
        savedViews.first { view in
            if case .kanban(let candidateBoardID) = view.kind {
                return candidateBoardID == boardID
            }
            return false
        }
    }

    @discardableResult
    func ensureKanbanView(name: String, boardID: String) -> SavedView {
        if let existing = kanbanView(for: boardID) {
            if !tabOrder.contains(existing.id) {
                addToTabOrder(existing.id)
            }
            return existing
        }
        return createKanbanView(name: name, boardID: boardID)
    }

    @discardableResult
    func updateSavedView(_ updated: SavedView) -> Bool {
        guard let idx = savedViews.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        savedViews[idx] = copy
        persist()
        return true
    }

    @discardableResult
    func deleteSavedView(_ id: UUID) -> Bool {
        let oldCount = savedViews.count
        savedViews.removeAll { $0.id == id }
        tabOrder.removeAll { $0 == id }
        guard savedViews.count != oldCount else { return false }
        persist()
        return true
    }

    func savedView(for id: UUID) -> SavedView? {
        savedViews.first { $0.id == id }
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(SavedViewsSnapshot.self, from: data)
            savedViews = snapshot.savedViews

            // Backward compat: if tabOrder is nil, derive from isTabPinned views
            if let order = snapshot.tabOrder {
                // Filter out stale IDs
                let validIDs = Set(savedViews.map(\.id))
                tabOrder = order.filter { validIDs.contains($0) }
            } else {
                tabOrder = savedViews
                    .filter(\.isTabPinned)
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .map(\.id)
            }
        } catch {
            savedViews = []
            tabOrder = []
        }
    }

    private func persist() {
        let snapshot = SavedViewsSnapshot(savedViews: savedViews, tabOrder: tabOrder)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence.
        }
    }
}
