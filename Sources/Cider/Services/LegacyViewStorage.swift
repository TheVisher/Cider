import Foundation
import Combine

private struct LegacyViewSnapshot: Codable {
    var views: [LegacyView]

    private enum CodingKeys: String, CodingKey {
        case views = "savedViews"
    }
}

@MainActor
final class LegacyViewStorage: ObservableObject {
    static let shared = LegacyViewStorage()

    @Published private(set) var views: [LegacyView] = []

    private let fileName = "_cider_saved_views.json"
    private let storageFileURL: URL?
    private var fileURL: URL {
        if let storageFileURL {
            return storageFileURL
        }
        let dir = StoragePaths.directoryURL(for: .retiredViewCompatibility)
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

    func kanbanView(for boardID: String) -> LegacyView? {
        views.first { view in
            if case .kanban(let candidateBoardID) = view.kind {
                return candidateBoardID == boardID
            }
            return false
        }
    }

    @discardableResult
    func deleteLegacyView(_ id: UUID) -> Bool {
        let oldCount = views.count
        views.removeAll { $0.id == id }
        guard views.count != oldCount else { return false }
        persist()
        return true
    }

    func legacyView(for id: UUID) -> LegacyView? {
        views.first { $0.id == id }
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LegacyViewSnapshot.self, from: data)
            views = snapshot.views
            normalizeCanonicalInboxSavedViews()
        } catch {
            views = []
        }
    }

    private func normalizeCanonicalInboxSavedViews() {
        for index in views.indices {
            guard views[index].kind == .library,
                  views[index].filterSpec.onlyUnassigned,
                  views[index].name.localizedCaseInsensitiveCompare("Inbox") == .orderedSame,
                  views[index].filterSpec.entityTypes != LibraryEntityType.activeCases else {
                continue
            }
            views[index].filterSpec.entityTypes = LibraryEntityType.activeCases
        }
    }

    private func persist() {
        let snapshot = LegacyViewSnapshot(views: views)
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
