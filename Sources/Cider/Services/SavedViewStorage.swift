import Foundation
import Combine

private struct SavedViewsSnapshot: Codable {
    var savedViews: [SavedView]
}

@MainActor
final class SavedViewStorage: ObservableObject {
    static let shared = SavedViewStorage()

    @Published private(set) var savedViews: [SavedView] = []

    private let fileName = "_cider_saved_views.json"
    private var fileURL: URL {
        let dir = StoragePaths.directoryURL(for: .savedViews)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func createSavedView(
        name: String,
        filterSpec: SavedViewFilterSpec = SavedViewFilterSpec(),
        sortSpec: SavedViewSortSpec = SavedViewSortSpec(),
        layoutSpec: SavedViewLayoutSpec = SavedViewLayoutSpec()
    ) -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled View" : trimmed
        let savedView = SavedView(
            name: finalName,
            filterSpec: filterSpec,
            sortSpec: sortSpec,
            layoutSpec: layoutSpec
        )
        savedViews.append(savedView)
        sortSavedViews()
        persist()
        return savedView
    }

    @discardableResult
    func updateSavedView(_ updated: SavedView) -> Bool {
        guard let idx = savedViews.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        savedViews[idx] = copy
        sortSavedViews()
        persist()
        return true
    }

    @discardableResult
    func deleteSavedView(_ id: UUID) -> Bool {
        let oldCount = savedViews.count
        savedViews.removeAll { $0.id == id }
        guard savedViews.count != oldCount else { return false }
        persist()
        return true
    }

    func savedView(for id: UUID) -> SavedView? {
        savedViews.first { $0.id == id }
    }

    func pinnedSavedViews() -> [SavedView] {
        savedViews
            .filter(\.isTabPinned)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func sortSavedViews() {
        savedViews.sort { lhs, rhs in
            if lhs.isTabPinned != rhs.isTabPinned {
                return lhs.isTabPinned && !rhs.isTabPinned
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(SavedViewsSnapshot.self, from: data)
            savedViews = snapshot.savedViews
            sortSavedViews()
        } catch {
            savedViews = []
        }
    }

    private func persist() {
        let snapshot = SavedViewsSnapshot(savedViews: savedViews)
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
