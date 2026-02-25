import Foundation

// MARK: - ItemEmbedding

struct ItemEmbedding: Codable {
    let id: UUID
    let vector: [Double]
    let modifiedAt: Date
}

// MARK: - EmbeddingStore

/// Persists NLEmbedding vectors for all bookmarks.
/// Stored as JSON at `{ciderDataDirectory}/.ai/embeddings.json`.
/// Thread safety: @MainActor for reads/writes; computation runs on detached tasks.
@MainActor
final class EmbeddingStore {
    static let shared = EmbeddingStore()

    private var cache: [UUID: ItemEmbedding] = [:]
    private var isDirty = false
    private var saveTask: Task<Void, Never>?

    private var storeFileURL: URL {
        let dir = StoragePaths.ciderDataDirectoryURL()
        let aiDir = dir.appendingPathComponent(".ai", isDirectory: true)
        StoragePaths.ensureDirectory(aiDir)
        return aiDir.appendingPathComponent("embeddings.json")
    }

    // MARK: - Public API

    func vector(for id: UUID) -> [Double]? {
        cache[id]?.vector
    }

    func allEmbeddings() -> [ItemEmbedding] {
        Array(cache.values)
    }

    /// Compute and store an embedding for a bookmark.
    /// - Parameters:
    ///   - id: Bookmark UUID
    ///   - text: Combined text to embed (title + host + notes)
    ///   - modifiedAt: Used to detect stale embeddings
    func computeAndStore(id: UUID, text: String, modifiedAt: Date) {
        // Skip if up-to-date
        if let existing = cache[id], existing.modifiedAt >= modifiedAt { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let vector = NLPipeline.embedding(for: text) else { return }
            let item = ItemEmbedding(id: id, vector: vector, modifiedAt: modifiedAt)
            await MainActor.run { [weak self] in
                self?.cache[id] = item
                self?.scheduleSave()
            }
        }
    }

    func remove(id: UUID) {
        cache.removeValue(forKey: id)
        scheduleSave()
    }

    /// Backfill embeddings for bookmarks that have no stored vector.
    /// Called once at startup after `load()` completes. Runs in background with
    /// 100 ms yields between batches of 20 to avoid blocking the main thread.
    func backfillMissing(bookmarks: [Bookmark]) {
        Task.detached(priority: .background) { [weak self] in
            // Wait for load() to finish populating the cache before filtering.
            try? await Task.sleep(for: .milliseconds(500))

            let missing: [Bookmark] = await MainActor.run { [weak self] in
                guard let self else { return [] }
                return bookmarks.filter { self.cache[$0.id] == nil }
            }
            guard !missing.isEmpty else { return }

            let batchSize = 20
            var idx = 0
            while idx < missing.count {
                guard !Task.isCancelled else { return }
                let batch = Array(missing[idx..<min(idx + batchSize, missing.count)])
                idx += batchSize

                for bookmark in batch {
                    let text = [bookmark.title, bookmark.hostDisplay, bookmark.notes]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard let vector = NLPipeline.embedding(for: text) else { continue }
                    let item = ItemEmbedding(id: bookmark.id, vector: vector, modifiedAt: bookmark.updatedAt)
                    await MainActor.run { [weak self] in
                        guard let self, self.cache[bookmark.id] == nil else { return }
                        self.cache[bookmark.id] = item
                        self.isDirty = true
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }

            await MainActor.run { [weak self] in
                self?.scheduleSave()
            }
        }
    }

    // MARK: - Persistence

    func load() {
        let url = storeFileURL
        Task.detached(priority: .background) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let items = try? JSONDecoder().decode([ItemEmbedding].self, from: data)
            else { return }
            let dict = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            await MainActor.run { [weak self] in
                self?.cache = dict
            }
        }
    }

    private func scheduleSave() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    private func flushSave() {
        guard isDirty else { return }
        isDirty = false
        let snapshot = Array(cache.values)
        let url = storeFileURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
