import Foundation

/// Finds similar bookmarks using cosine similarity over stored NLEmbedding vectors.
struct SimilarItemsService {

    /// Returns IDs of bookmarks most similar to the given bookmark ID.
    /// - Parameters:
    ///   - id: The source bookmark to find matches for
    ///   - store: The embedding store to query
    ///   - excluding: Additional IDs to exclude (e.g. same-folder items)
    ///   - limit: Maximum number of results
    @MainActor
    static func findSimilar(
        to id: UUID,
        in store: EmbeddingStore,
        excluding: Set<UUID> = [],
        limit: Int = 3
    ) -> [UUID] {
        guard let target = store.vector(for: id) else { return [] }
        let candidates = store.allEmbeddings()
            .filter { $0.id != id && !excluding.contains($0.id) }

        return candidates
            .compactMap { item -> (UUID, Double)? in
                let sim = cosineSimilarity(target, item.vector)
                guard sim > 0.5 else { return nil } // minimum threshold
                return (item.id, sim)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Math

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in a.indices {
            dot  += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = magA.squareRoot() * magB.squareRoot()
        return denom > 0 ? dot / denom : 0
    }
}
