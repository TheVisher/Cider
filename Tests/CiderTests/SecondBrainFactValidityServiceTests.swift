import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Fact Validity Service Tests")
@MainActor
struct SecondBrainFactValidityServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-fact-validity-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("accepted invalidation preserves original fact and explains stale state")
    func acceptedInvalidationPreservesOriginalFactAndExplainsStaleState() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let source = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let oldTarget = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "pine-house")
        let newTarget = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "lotus-garden")
        let oldRelation = SecondBrainRelation(
            sourceOwner: source,
            targetOwner: oldTarget,
            relationType: "favorite_restaurant",
            evidence: "Jami's favorite restaurant is Pine House.",
            source: "graph_candidate.accept",
            actor: "test",
            confidence: 0.9,
            metadata: [
                "candidate_ref": "graph_candidate:old-favorite",
                "source_quote": "Jami's favorite restaurant is Pine House.",
                "source_owner_ref": source.canonicalRef,
            ]
        )
        try SecondBrainStore(database: db).recordRelation(oldRelation)

        let service = SecondBrainFactValidityService(database: db)
        let candidate = try service.propose(
            targetRef: "owner_relation:\(oldRelation.id)",
            proposedState: "superseded",
            sourceOwner: source,
            sourceQuote: "Jami said Lotus Garden is her favorite restaurant now.",
            actor: "test",
            reason: "Newer journal entry supersedes the prior favorite restaurant fact.",
            supersededByRef: "owner_relation:new-favorite",
            validAt: ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z"),
            invalidAt: ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z"),
            metadata: ["new_target_ref": newTarget.canonicalRef]
        )

        #expect(candidate.reviewState == "suggested")
        #expect(candidate.truthBoundary == "reviewable_candidate_not_truth")
        #expect(candidate.targetRef == "owner_relation:\(oldRelation.id)")
        #expect(candidate.sourceEvidenceRecord != nil)
        #expect(candidate.lifecycleHistory.map(\.eventKind).contains("suggested"))

        let accepted = try service.accept(candidateID: candidate.id, actor: "reviewer", decisionNote: "Confirmed newer source supersedes the old favorite.")
        #expect(accepted.reviewState == "accepted")
        #expect(accepted.truthBoundary == "accepted_fact_validity")
        #expect(accepted.lifecycleHistory.map(\.eventKind).contains("accepted"))

        let maybeState = try service.validityState(targetRef: "owner_relation:\(oldRelation.id)")
        let state = try #require(maybeState)
        #expect(state.currentState == "superseded")
        #expect(state.isCurrent == false)
        #expect(state.supersededByRef == "owner_relation:new-favorite")
        #expect(state.sourceEvidenceRecord?.sourceQuote == "Jami said Lotus Garden is her favorite restaurant now.")

        let storedRelations = try SecondBrainStore(database: db).outgoingRelations(for: source)
        let storedOld = try #require(storedRelations.first { $0.id == oldRelation.id })
        #expect(storedOld.evidence == oldRelation.evidence)
        #expect(storedOld.targetOwner == oldTarget)
    }

    @Test("rejected invalidation remains historical and does not stale accepted fact")
    func rejectedInvalidationRemainsHistoricalAndDoesNotStaleAcceptedFact() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let source = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let target = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "cactus")
        let relation = SecondBrainRelation(
            sourceOwner: source,
            targetOwner: target,
            relationType: "visited",
            evidence: "Avery visited Cactus for dinner.",
            source: "graph_candidate.accept",
            actor: "test",
            metadata: ["source_quote": "Avery visited Cactus for dinner."]
        )
        try SecondBrainStore(database: db).recordRelation(relation)

        let service = SecondBrainFactValidityService(database: db)
        let candidate = try service.propose(
            targetRef: "owner_relation:\(relation.id)",
            proposedState: "invalidated",
            sourceOwner: source,
            sourceQuote: "Maybe Avery did not go to Cactus after all.",
            actor: "test",
            reason: "Uncertain correction requires review."
        )
        let rejected = try service.reject(candidateID: candidate.id, actor: "reviewer", reason: "The correction was ambiguous.")

        #expect(rejected.reviewState == "rejected")
        #expect(rejected.truthBoundary == "reviewable_candidate_not_truth")
        #expect(try service.validityState(targetRef: "owner_relation:\(relation.id)") == nil)
        #expect(try service.candidates(reviewStates: ["rejected"]).contains { $0.id == candidate.id })
    }
}
