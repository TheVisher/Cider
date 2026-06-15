import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Second Brain Canonical Entity Inspection Tests")
@MainActor
struct SecondBrainCanonicalEntityInspectionTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-canonical-entity-inspection-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, SecondBrainStore, SecondBrainEnrichmentOutputService, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, SecondBrainStore(database: db), SecondBrainEnrichmentOutputService(database: db), url)
    }

    private func acceptedOutput(
        id: String = UUID().uuidString,
        sourceOwner: SecondBrainOwnerRef,
        targetOwner: SecondBrainOwnerRef,
        mention: String,
        quote: String,
        aliases: [String] = [],
        relation: SecondBrainGraphCandidateContract.RelationType = .wants
    ) throws -> SecondBrainEnrichmentOutput {
        var output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: [.object],
            relationGuesses: [relation],
            safeActions: [.inspectSource, .accept, .correct, .reject],
            confidence: 0.87,
            source: "graph_candidate.test"
        )
        output.id = id
        output.reviewState = SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] = targetOwner.ownerType
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] = targetOwner.ownerID
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType] = relation.rawValue
        output.metadata["canonical_stable_key"] = CiderCLI.graphObjectStableKey(for: mention)
        output.metadata["canonical_display_name"] = CiderCLI.graphObjectDisplayName(for: mention)
        output.metadata["canonical_owner_ref"] = targetOwner.canonicalRef
        output.metadata["canonical_aliases"] = DatabaseHelpers.encode(aliases)
        output.metadata["reviewed_by"] = "test"
        return output
    }

    private func suggestedOutput(
        sourceOwner: SecondBrainOwnerRef,
        mention: String,
        quote: String
    ) throws -> SecondBrainEnrichmentOutput {
        try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: [.object],
            relationGuesses: [.wants],
            safeActions: [.inspectSource, .accept, .correct, .reject],
            confidence: 0.61,
            source: "graph_candidate.test"
        )
    }

    @Test("entity list exposes accepted canonical graph truth with counts and safe inspect command")
    func entityListExposesAcceptedCanonicalTruth() throws {
        let (db, store, outputs, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let targetOwner = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "graph_object:e-bike")
        let accepted = try acceptedOutput(
            sourceOwner: sourceOwner,
            targetOwner: targetOwner,
            mention: "e-bike",
            quote: "Visher wants to try an e-bike someday.",
            aliases: ["Electric Bike"]
        )
        try outputs.record(accepted)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: sourceOwner,
            targetOwner: targetOwner,
            relationType: "wants",
            evidence: "Visher wants to try an e-bike someday.",
            source: "graph_candidate.accept",
            actor: "test",
            confidence: 0.87,
            metadata: [
                "candidate_id": accepted.id,
                "candidate_ref": "graph_candidate:\(accepted.id)",
                "source_quote": "Visher wants to try an e-bike someday.",
                "source_owner_ref": sourceOwner.canonicalRef,
                "mention_text": "e-bike",
            ]
        ))

        let payload = try CiderCLI.entityListPayload(service: SecondBrainCanonicalEntityService(database: db, store: store))
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["command"] as? String == "item.entity.list")
        let entities = try #require(payload["entities"] as? [[String: Any]])
        #expect(entities.count == 1)
        let entity = try #require(entities.first)
        #expect(entity["truthState"] as? String == "accepted_graph_truth")
        #expect(entity["displayName"] as? String == "E-bike")
        #expect(entity["ref"] as? String == targetOwner.canonicalRef)
        #expect((entity["aliases"] as? [String])?.contains("Electric Bike") == true)
        #expect(entity["sourceEvidenceCount"] as? Int == 1)
        #expect(entity["acceptedRelationCount"] as? Int == 1)
        #expect(entity["reviewableCandidateCount"] as? Int == 0)
        #expect((entity["safeInspectCommand"] as? String)?.contains("cider-cli item entity inspect") == true)
    }

    @Test("entity inspect separates accepted evidence from reviewable candidates")
    func entityInspectSeparatesAcceptedEvidenceFromReviewableCandidates() throws {
        let (db, store, outputs, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let otherSource = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let targetOwner = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "graph_object:seoul-bowl")
        let accepted = try acceptedOutput(
            sourceOwner: sourceOwner,
            targetOwner: targetOwner,
            mention: "Seoul Bowl",
            quote: "Visher wants to try Seoul Bowl later.",
            aliases: ["Seoul Bowl / Korean barbecue bowl place"]
        )
        let suggested = try suggestedOutput(
            sourceOwner: otherSource,
            mention: "Seoul Bowl",
            quote: "Maybe Seoul Bowl is a restaurant to review."
        )
        try outputs.record(accepted)
        try outputs.record(suggested)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: sourceOwner,
            targetOwner: targetOwner,
            relationType: "wants",
            evidence: "Visher wants to try Seoul Bowl later.",
            source: "graph_candidate.accept",
            actor: "test",
            confidence: 0.87,
            metadata: [
                "candidate_id": accepted.id,
                "candidate_ref": "graph_candidate:\(accepted.id)",
                "source_quote": "Visher wants to try Seoul Bowl later.",
                "source_owner_ref": sourceOwner.canonicalRef,
                "mention_text": "Seoul Bowl",
            ]
        ))

        let payload = try CiderCLI.entityInspectPayload(
            selector: targetOwner.canonicalRef,
            service: SecondBrainCanonicalEntityService(database: db, store: store)
        )
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["truthState"] as? String == "accepted_graph_truth")
        let acceptedState = try #require(payload["acceptedCanonicalState"] as? [String: Any])
        #expect(acceptedState["acceptedAsTruth"] as? Bool == true)
        let sourceEvidence = try #require(payload["sourceEvidence"] as? [[String: Any]])
        #expect(sourceEvidence.count == 1)
        let firstEvidence = try #require(sourceEvidence.first)
        #expect(firstEvidence["sourceQuote"] as? String == "Visher wants to try Seoul Bowl later.")
        let reviewable = try #require(payload["reviewableCandidates"] as? [[String: Any]])
        #expect(reviewable.count == 1)
        let firstReviewable = try #require(reviewable.first)
        #expect(firstReviewable["truthState"] as? String == "reviewable_candidate_not_truth")
        #expect(firstReviewable["sourceQuote"] as? String == "Maybe Seoul Bowl is a restaurant to review.")
        #expect((payload["safeNextCommands"] as? [String])?.contains("cider-cli item graph-candidate \(suggested.id) --json") == true)
    }

    @Test("entity lookup returns structured ambiguity and no match errors")
    func entityLookupReturnsStructuredAmbiguityAndNoMatchErrors() throws {
        let (db, store, outputs, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let otherSourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let first = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "graph_object:cactus-restaurant")
        let second = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "graph_object:cactus-plant")
        try outputs.record(try acceptedOutput(sourceOwner: sourceOwner, targetOwner: first, mention: "Cactus", quote: "We ate at Cactus."))
        try outputs.record(try acceptedOutput(sourceOwner: otherSourceOwner, targetOwner: second, mention: "Cactus", quote: "We bought a cactus plant."))

        let service = SecondBrainCanonicalEntityService(database: db, store: store)
        let ambiguous = CiderCLI.entityInspectErrorPayload(selector: "Cactus", error: SecondBrainCanonicalEntityLookupError.ambiguous(selector: "Cactus", matches: try service.listEntities()))
        #expect(ambiguous["ok"] as? Bool == false)
        #expect(ambiguous["errorCode"] as? String == "entity_lookup_ambiguous")
        #expect((ambiguous["candidates"] as? [[String: Any]])?.count == 2)
        #expect(ambiguous["changed"] as? Bool == false)

        let missing = CiderCLI.entityInspectErrorPayload(selector: "Missing", error: SecondBrainCanonicalEntityLookupError.notFound(selector: "Missing"))
        #expect(missing["ok"] as? Bool == false)
        #expect(missing["errorCode"] as? String == "entity_not_found")
        #expect((missing["safeNextCommands"] as? [String])?.contains("cider-cli item entity list --json") == true)
    }
}
