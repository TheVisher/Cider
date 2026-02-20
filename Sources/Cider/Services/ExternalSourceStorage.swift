import Foundation
import Combine

private struct ExternalSourcesSnapshot: Codable {
    var sources: [ExternalSource]
}

@MainActor
final class ExternalSourceStorage: ObservableObject {
    static let shared = ExternalSourceStorage()

    @Published private(set) var sources: [ExternalSource] = []

    private let fileName = "_cider_sources.json"
    private var fileURL: URL

    private init() {
        let directoryURL = StoragePaths.ciderDataDirectoryURL()
        fileURL = StoragePaths.jsonFileURL(fileName: fileName, in: directoryURL)
        StoragePaths.ensureDirectory(directoryURL)
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func addSource(path: String, displayName: String) -> ExternalSource {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed
        let source = ExternalSource(path: path, displayName: finalName)
        sources.append(source)
        sortSources()
        persist()
        return source
    }

    @discardableResult
    func updateSource(_ updated: ExternalSource) -> Bool {
        guard let idx = sources.firstIndex(where: { $0.id == updated.id }) else { return false }
        sources[idx] = updated
        sortSources()
        persist()
        return true
    }

    @discardableResult
    func removeSource(_ id: UUID) -> Bool {
        let oldCount = sources.count
        sources.removeAll { $0.id == id }
        guard sources.count != oldCount else { return false }
        persist()
        return true
    }

    func source(for id: UUID) -> ExternalSource? {
        sources.first { $0.id == id }
    }

    func pinnedSources() -> [ExternalSource] {
        sources.filter(\.isTabPinned)
    }

    func librarySources() -> [ExternalSource] {
        sources.filter(\.showInLibrary)
    }

    // MARK: - Sorting

    private func sortSources() {
        sources.sort { $0.createdAt > $1.createdAt }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ExternalSourcesSnapshot.self, from: data)
            sources = snapshot.sources
            sortSources()
        } catch {
            sources = []
        }
    }

    private func persist() {
        let snapshot = ExternalSourcesSnapshot(sources: sources)
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
