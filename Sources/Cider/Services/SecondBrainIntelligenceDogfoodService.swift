import Foundation

struct SecondBrainIntelligenceDogfoodOwnerResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var chunkCount: Int
    var enrichmentOutputCount: Int
    var enrichmentKindCounts: [String: Int]
    var enrichmentReviewStates: [String: Int]
    var similarityCandidateCount: Int
    var similarityReviewStates: [String: Int]
}

struct SecondBrainIntelligenceDogfoodResult: Codable, Equatable {
    var ownerCount: Int
    var limit: Int
    var threshold: Double
    var candidateLimit: Int
    var enrichmentOutputCount: Int
    var similarityCandidateCount: Int
    var reviewRequired: Bool
    var owners: [SecondBrainIntelligenceDogfoodOwnerResult]
}

@MainActor
final class SecondBrainIntelligenceDogfoodService {
    private let database: CiderDatabase
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
    }

    func rebuild(
        limit: Int = 5,
        threshold: Double = 0.34,
        candidateLimit: Int = 10
    ) throws -> SecondBrainIntelligenceDogfoodResult {
        let boundedLimit = max(0, limit)
        let boundedCandidateLimit = max(0, candidateLimit)
        let owners = try chunkedOwners(limit: boundedLimit)
        let enrichmentService = SecondBrainEnrichmentOutputService(database: database)
        let similarityService = SecondBrainSimilarityCandidateService(database: database, store: store)

        var ownerResults: [SecondBrainIntelligenceDogfoodOwnerResult] = []
        for chunkedOwner in owners {
            let enrichment = try enrichmentService.rebuildFromChunks(owner: chunkedOwner.owner)
            let outputs = try enrichmentService.outputs(for: chunkedOwner.owner)
            let similarity = try similarityService.rebuildChunkOverlapCandidates(
                for: chunkedOwner.owner,
                threshold: threshold,
                limit: boundedCandidateLimit
            )
            let entityRelations = try similarityService.rebuildEntityRelationCandidates(
                for: chunkedOwner.owner,
                targetTypes: ["contact"],
                limit: boundedCandidateLimit
            )
            let candidates = try similarityService.candidates(for: chunkedOwner.owner)

            ownerResults.append(SecondBrainIntelligenceDogfoodOwnerResult(
                owner: chunkedOwner.owner,
                chunkCount: chunkedOwner.chunkCount,
                enrichmentOutputCount: enrichment.outputCount,
                enrichmentKindCounts: enrichment.kindCounts,
                enrichmentReviewStates: Dictionary(grouping: outputs, by: \.reviewState).mapValues(\.count),
                similarityCandidateCount: similarity.candidateCount + entityRelations.candidateCount,
                similarityReviewStates: Dictionary(grouping: candidates, by: \.reviewState).mapValues(\.count)
            ))
        }

        let enrichmentOutputCount = ownerResults.reduce(0) { $0 + $1.enrichmentOutputCount }
        let similarityCandidateCount = ownerResults.reduce(0) { $0 + $1.similarityCandidateCount }
        return SecondBrainIntelligenceDogfoodResult(
            ownerCount: ownerResults.count,
            limit: boundedLimit,
            threshold: threshold,
            candidateLimit: boundedCandidateLimit,
            enrichmentOutputCount: enrichmentOutputCount,
            similarityCandidateCount: similarityCandidateCount,
            reviewRequired: enrichmentOutputCount > 0 || similarityCandidateCount > 0,
            owners: ownerResults
        )
    }

    private struct ChunkedOwner {
        var owner: SecondBrainOwnerRef
        var chunkCount: Int
    }

    private func chunkedOwners(limit: Int) throws -> [ChunkedOwner] {
        guard limit > 0 else { return [] }
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, count(*)
            FROM content_chunks
            GROUP BY owner_type, owner_id
            ORDER BY max(updated_at) DESC, owner_type COLLATE NOCASE ASC, owner_id COLLATE NOCASE ASC
            LIMIT ?;
            """)
        stmt.bind(Int64(limit), at: 1)

        var owners: [ChunkedOwner] = []
        while try stmt.step() {
            owners.append(ChunkedOwner(
                owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1)),
                chunkCount: stmt.int(at: 2)
            ))
        }
        return owners
    }
}
