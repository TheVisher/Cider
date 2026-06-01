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

    // MARK: - Legacy Read/Delete Compatibility

    func kanbanView(for boardID: String) -> SavedView? {
        savedViews.first { view in
            if case .kanban(let candidateBoardID) = view.kind {
                return candidateBoardID == boardID
            }
            return false
        }
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

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(SavedViewsSnapshot.self, from: data)
            savedViews = snapshot.savedViews
            normalizeCanonicalInboxSavedViews()
        } catch {
            savedViews = []
        }
    }

    private func normalizeCanonicalInboxSavedViews() {
        for index in savedViews.indices {
            guard savedViews[index].kind == .library,
                  savedViews[index].filterSpec.onlyUnassigned,
                  savedViews[index].name.localizedCaseInsensitiveCompare("Inbox") == .orderedSame,
                  savedViews[index].filterSpec.entityTypes != LibraryEntityType.activeCases else {
                continue
            }
            savedViews[index].filterSpec.entityTypes = LibraryEntityType.activeCases
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
