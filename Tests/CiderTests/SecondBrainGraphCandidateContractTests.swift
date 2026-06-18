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

    @Test("contract trims stored string array metadata")
    func contractTrimsStoredStringArrayMetadata() throws {
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)

        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .object,
            mentionText: " Cactus ",
            sourceQuote: " We went to Cactus. ",
            objectTypeGuesses: [.restaurant],
            actionGuesses: [" visited ", "   ", "liked"],
            safeActions: [.inspectSource, .reject]
        )

        #expect(DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.actionGuesses]) == ["visited", "liked"])
        #expect(DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.safeActions]) == ["inspect_source", "reject"])
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

    @Test("journal extractor ignores Cider feature example prose")
    func journalExtractorIgnoresCiderFeatureExampleProse() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Cider should surface source-backed memory_candidate and graph_candidate rows in the Review Queue.
            Examples it should show during review:
            - Watched The Way Way Back last night.
            - Jami loved that pineapple coconut drink.
            - Baine liked the tacos.
            - We stopped at Cactus.
            """
        )

        #expect(result.outputs.isEmpty)
    }

    @Test("journal extractor ignores Cider feature example blocks without losing later real notes")
    func journalExtractorIgnoresCiderFeatureExampleBlocksWithoutLosingLaterRealNotes() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Cider Review Queue planning:
            Examples the app should capture and show:
            Watched The Way Way Back last night.
            Jami loved that pineapple coconut drink.
            Baine liked the tacos.
            We stopped at Cactus.

            Family notes:
            Baine liked tacos at dinner.
            """
        )

        #expect(result.outputs.map(\.value) == ["tacos"])
        #expect(result.outputs.first?.evidence == "Baine liked tacos at dinner")
    }

    @Test("journal extractor keeps ordinary journal memories")
    func journalExtractorKeepsOrdinaryJournalMemories() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Family notes:
            Jami loved that pineapple coconut drink.
            Baine liked the tacos.
            """
        )

        #expect(result.outputs.map(\.value) == ["pineapple coconut drink", "tacos"])
    }

    @Test("journal extractor suppresses noisy dogfood false positives")
    func journalExtractorSuppressesNoisyDogfoodFalsePositives() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            - Jami and Visher watched Reminders of Him while eating.
            - Later I watched The Way Way Back and thought about Reminders of Him while eating.
            - Visher did not really want to watch it because it seemed like a chick-flick type movie, but watched it with her and thought it was actually pretty decent.
            - After the movie, they went to bed.
            - Ryker said his throat felt like “saw blades” or something similar and did not eat all of it.
            - They went to the Marysville outlet mall, and Bane wanted the Nike store.
            """
        )

        let graphOutputs = result.outputs.filter { $0.kind == "graph_candidate" }
        #expect(graphOutputs.map(\.value) == ["Reminders of Him", "The Way Way Back", "the Marysville outlet mall", "Nike store"])
        #expect(graphOutputs.map(\.evidence).contains("- Jami and Visher watched Reminders of Him while eating"))
        #expect(graphOutputs.first { $0.value == "The Way Way Back" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"watched\"]")
        #expect(graphOutputs.first { $0.value == "the Marysville outlet mall" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"visited\"]")
        #expect(graphOutputs.first { $0.value == "Nike store" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.subjectText] == "Bane")
        #expect(graphOutputs.first { $0.value == "Nike store" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"wants\"]")
        #expect(!graphOutputs.map(\.value).contains("it"))
        #expect(!graphOutputs.map(\.value).contains("bed"))
        #expect(!graphOutputs.contains { $0.value.localizedCaseInsensitiveContains("saw blades") })
    }

    @Test("journal extractor suppresses schooling background as place visits")
    func journalExtractorSuppressesSchoolingBackgroundAsPlaceVisits() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: "Jami went to beauty school and doesn’t do hair professionally anymore, but she still does hair consistently for her mom, her sisters, and her mom’s friend Darcy"
        )

        let graphOutputs = result.outputs.filter { $0.kind == "graph_candidate" }
        #expect(!graphOutputs.contains { candidate in
            candidate.evidence == "Jami went to beauty school and doesn’t do hair professionally anymore, but she still does hair consistently for her mom, her sisters, and her mom’s friend Darcy"
                && (candidate.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses]?.contains("visited") == true
                    || candidate.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses]?.contains("restaurant") == true
                    || candidate.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses]?.contains("place") == true)
        })
        #expect(!graphOutputs.contains { $0.value.localizedCaseInsensitiveContains("beauty school") })
        #expect(result.outputs.allSatisfy { $0.reviewState == "suggested" })
    }

    @Test("journal extractor keeps real restaurant place visits")
    func journalExtractorKeepsRealRestaurantPlaceVisits() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: "After work, we went to Cactus for dinner."
        )

        let graphOutputs = result.outputs.filter { $0.kind == "graph_candidate" }
        let cactus = try #require(graphOutputs.first { $0.value == "Cactus" })
        #expect(cactus.evidence == "After work, we went to Cactus for dinner")
        #expect(cactus.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"visited\"]")
        #expect(cactus.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses] == "[\"restaurant\",\"place\"]")
        #expect(cactus.reviewState == "suggested")
    }

    @Test("journal extractor keeps fresh live journal retest candidates bounded")
    func journalExtractorKeepsFreshLiveJournalRetestCandidatesBounded() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            After Visher got home, it was just him and Jami for the day. Visher ate some food and watched a Netflix movie, a Sacha Baron Cohen movie where his misogynistic character hits his head and the world is run by women. Visher thought it might be called "Ladies First" or something similar and found it pretty funny.
            After that, Jami and Visher hung out for a while, then went to Din Tai Fung in Bellevue. They had not been there in a while. Visher had a sea salt foam black tea that he thought was delicious; Jami had a Diet Coke.
            Visher noticed several restaurants there that he wants to try later: a sushi place, Seoul Bowl / Korean barbecue bowl place, a bubble tea/tea place, a coffee stand, and a steakhouse. He had not realized that area had so many restaurants and wants to go back.
            Visher thinks they watched the New York Knicks beat the Spurs for the championship. Visher has not watched much basketball since the Sonics left Seattle almost two decades ago, but he enjoyed it.
            """
        )

        let graphOutputs = result.outputs.filter { $0.kind == "graph_candidate" }
        let values = graphOutputs.map(\.value)
        #expect(values.contains("Din Tai Fung in Bellevue"))
        #expect(values.contains("sea salt foam black tea"))
        #expect(values.contains("Diet Coke"))
        #expect(values.contains("sushi place"))
        #expect(values.contains("Seoul Bowl / Korean barbecue bowl place"))
        #expect(values.contains("bubble tea/tea place"))
        #expect(values.contains("coffee stand"))
        #expect(values.contains("steakhouse"))

        #expect(!values.contains("much basketball since the Sonics left Seattle almost two decades ago"))
        #expect(!values.contains("the New York Knicks beat the Spurs for the championship"))
        #expect(!values.contains("to go back"))
        #expect(!values.contains("not realized that area had so many restaurants and wants to go back"))
        #expect(!values.contains("not been there in a while"))
        #expect(!values.contains { $0.localizedCaseInsensitiveContains("sea salt foam black tea that he thought was delicious; Jami had a Diet Coke") })
        #expect(!values.contains { $0.localizedCaseInsensitiveContains("Sacha Baron Cohen movie") })

        #expect(graphOutputs.first { $0.value == "Din Tai Fung in Bellevue" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"visited\"]")
        #expect(graphOutputs.first { $0.value == "sea salt foam black tea" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"drank\"]")
        #expect(graphOutputs.first { $0.value == "Diet Coke" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.subjectText] == "Jami")
        #expect(graphOutputs.first { $0.value == "Diet Coke" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"drank\"]")
        #expect(graphOutputs.first { $0.value == "sushi place" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"wants\"]")
    }

    @Test("journal extractor proposes useful source backed memory candidates")
    func journalExtractorProposesUsefulSourceBackedMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            - This is Visher’s first weekend overtime in five years or more.
            - The reason he asked about hourly wages was motivation: knowing today is about $82.26/hr and Sunday is about $109.68/hr makes it easier to get up and do the overtime.
            - Visher said the overtime-heavy first hourly paycheck matters because his budget normally depends on one full paycheck for bills and one full paycheck for rent.
            - Consider an overnight oats reminder on nights before early weekend overtime.
            """,
            date: "2026-06-13",
            time: "03:16"
        )

        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        #expect(memoryOutputs.map(\.value) == [
            "Visher has returned to weekend overtime after five years or more.",
            "Overtime pay calculations help Visher motivate himself to get up for early weekend overtime.",
            "Visher's budget normally depends on one full paycheck for bills and one full paycheck for rent.",
            "Consider an overnight oats reminder on nights before early weekend overtime.",
        ])
        #expect(memoryOutputs.allSatisfy { $0.reviewState == "suggested" })
        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "overtime-pay-motivation" }?.evidence.contains("$109.68/hr") == true)
        #expect(memoryOutputs.allSatisfy { $0.metadata["requires_review"] == "true" })
        #expect(memoryOutputs.allSatisfy { $0.metadata["journal_date"] == "2026-06-13" })
        #expect(memoryOutputs.map { $0.metadata["memory_kind"] } == ["pattern", "pattern", "pattern", "pattern"])
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
