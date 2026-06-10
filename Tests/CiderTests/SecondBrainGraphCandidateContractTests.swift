import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Graph Candidate Contract Tests")
@MainActor
struct SecondBrainGraphCandidateContractTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-graph-candidate-contract-\(UUID().uuidString).db")
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

    @Test("object relation candidate maps onto graph candidate enrichment output")
    func objectRelationCandidateMapsOntoEnrichmentOutput() throws {
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let subjectOwner = SecondBrainOwnerRef(ownerType: "contact", ownerID: UUID().uuidString)

        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .objectRelation,
            mentionText: "pineapple coconut drink",
            sourceQuote: "I gave Jami that pineapple coconut drink and she loved it.",
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            actionGuesses: ["liked"],
            safeActions: [.inspectSource, .accept, .correct, .reject, .delegateEnrichment],
            confidence: 0.88,
            confidenceReason: "Sentence explicitly says Jami loved the drink.",
            subjectText: "Jami",
            subjectOwner: subjectOwner,
            source: "graph_candidate.test"
        )

        #expect(output.owner == sourceOwner)
        #expect(output.kind == "graph_candidate")
        #expect(output.value == "pineapple coconut drink")
        #expect(output.normalizedValue == "pineapple coconut drink")
        #expect(output.evidence == "I gave Jami that pineapple coconut drink and she loved it.")
        #expect(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceOwnerRef] == sourceOwner.canonicalRef)
        #expect(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote] == output.evidence)

        let candidate = try SecondBrainGraphCandidateContract.validate(output)
        #expect(candidate.kind == .objectRelation)
        #expect(candidate.sourceOwner == sourceOwner)
        #expect(candidate.mentionText == "pineapple coconut drink")
        #expect(candidate.sourceQuote.contains("Jami"))
        #expect(candidate.sourceKind == "journal")
        #expect(candidate.objectTypeGuesses == [.drink])
        #expect(candidate.relationGuesses == [.likesDrink])
        #expect(candidate.actionGuesses == ["liked"])
        #expect(candidate.safeActions.contains(.delegateEnrichment))
        #expect(candidate.confidence == 0.88)
        #expect(candidate.subjectText == "Jami")
        #expect(candidate.subjectOwner == subjectOwner)
        #expect(candidate.reviewState == .suggested)
        #expect(candidate.reviewState.isReviewable)
    }

    @Test("contract covers source object relation and accepted graph truth states")
    func contractCoversSourceCandidateAndAcceptedGraphTruthStates() throws {
        let bookmark = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let media = SecondBrainOwnerRef(ownerType: "media_item", ownerID: "the-way-way-back-2013")

        let suggested = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: bookmark,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "https://www.imdb.com/title/tt1727388/",
            sourceKind: "bookmark",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.represents, .sourceFor],
            safeActions: [.inspectSource, .linkExisting, .createObject, .reject],
            confidence: 0.84
        )
        let suggestedCandidate = try SecondBrainGraphCandidateContract.validate(suggested)

        #expect(suggestedCandidate.reviewState == .suggested)
        #expect(suggestedCandidate.objectTypeGuesses == [.movie, .media])
        #expect(suggestedCandidate.relationGuesses == [.represents, .sourceFor])
        #expect(SecondBrainGraphCandidateContract.canTransition(from: .suggested, to: .accepted))
        #expect(SecondBrainGraphCandidateContract.canTransition(from: .suggested, to: .rejected))

        var accepted = suggested
        accepted.reviewState = SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] = media.ownerType
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] = media.ownerID
        accepted.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType] = SecondBrainGraphCandidateContract.RelationType.represents.rawValue

        let acceptedCandidate = try SecondBrainGraphCandidateContract.validate(accepted)
        #expect(acceptedCandidate.reviewState == .accepted)
        #expect(acceptedCandidate.acceptedTargetOwner == media)
        #expect(acceptedCandidate.acceptedRelationType == .represents)
        #expect(!acceptedCandidate.reviewState.isReviewable)
        #expect(!SecondBrainGraphCandidateContract.canTransition(from: .accepted, to: .suggested))
    }

    @Test("graph candidate persists through enrichment outputs table")
    func graphCandidatePersistsThroughEnrichmentOutputsTable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: UUID().uuidString)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .object,
            mentionText: "Cactus",
            sourceQuote: "We went to Cactus and Jami liked the margarita.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant, .place, .topic, .object],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject],
            confidence: 0.48,
            confidenceReason: "Mention is ambiguous and needs triage.",
            reviewState: .needsReview,
            source: "graph_candidate.test"
        )

        let service = SecondBrainEnrichmentOutputService(database: db)
        try service.record(output)

        let stored = try #require(service.outputs(for: owner).first)
        let candidate = try SecondBrainGraphCandidateContract.validate(stored)
        #expect(candidate.id == output.id)
        #expect(candidate.sourceOwner == owner)
        #expect(candidate.reviewState == .needsReview)
        #expect(candidate.objectTypeGuesses == [.restaurant, .place, .topic, .object])
        #expect(candidate.confidenceReason == "Mention is ambiguous and needs triage.")
    }

    @Test("validation enforces source evidence review state and candidate type invariants")
    func validationEnforcesContractInvariants() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)

        #expect(throws: SecondBrainGraphCandidateContract.ValidationError.self) {
            _ = try SecondBrainGraphCandidateContract.makeOutput(
                sourceOwner: owner,
                candidateKind: .object,
                mentionText: "   ",
                sourceQuote: "Cactus was fun.",
                objectTypeGuesses: [.restaurant]
            )
        }

        #expect(throws: SecondBrainGraphCandidateContract.ValidationError.self) {
            _ = try SecondBrainGraphCandidateContract.makeOutput(
                sourceOwner: owner,
                candidateKind: .relation,
                mentionText: "visited Cactus",
                sourceQuote: "   ",
                relationGuesses: [.visited]
            )
        }

        var relationWithoutGuess = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .object,
            mentionText: "Cactus",
            sourceQuote: "We went to Cactus.",
            objectTypeGuesses: [.restaurant]
        )
        relationWithoutGuess.metadata[SecondBrainGraphCandidateContract.MetadataKey.candidateKind] = SecondBrainGraphCandidateContract.CandidateKind.relation.rawValue
        relationWithoutGuess.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] = "[]"
        #expect(throws: SecondBrainGraphCandidateContract.ValidationError.self) {
            _ = try SecondBrainGraphCandidateContract.validate(relationWithoutGuess)
        }

        var acceptedWithoutTarget = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .object,
            mentionText: "Cactus",
            sourceQuote: "We went to Cactus.",
            objectTypeGuesses: [.restaurant]
        )
        acceptedWithoutTarget.reviewState = SecondBrainGraphCandidateContract.ReviewState.accepted.rawValue
        #expect(throws: SecondBrainGraphCandidateContract.ValidationError.self) {
            _ = try SecondBrainGraphCandidateContract.validate(acceptedWithoutTarget)
        }

        var invalidState = acceptedWithoutTarget
        invalidState.reviewState = "done-ish"
        #expect(throws: SecondBrainGraphCandidateContract.ValidationError.self) {
            _ = try SecondBrainGraphCandidateContract.validate(invalidState)
        }
    }
}
