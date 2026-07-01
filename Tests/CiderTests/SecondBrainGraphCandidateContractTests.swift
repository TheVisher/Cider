import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

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

    @Test("journal extractor preserves occurrence-exact spans for duplicate identical lines")
    func journalExtractorPreservesOccurrenceExactSpansForDuplicateIdenticalLines() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let duplicatedLine = "- Jami loved that pineapple coconut drink"
        let rawContent = """
        Breakfast notes.
        \(duplicatedLine)
        Later notes.
        \(duplicatedLine)
        """

        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: rawContent
        )

        let candidates = result.outputs.filter {
            $0.kind == "graph_candidate" && $0.value == "pineapple coconut drink"
        }
        #expect(candidates.count == 2)

        var expectedStarts: [Int] = []
        var searchStart = rawContent.startIndex
        while let range = rawContent.range(of: duplicatedLine, range: searchStart..<rawContent.endIndex) {
            expectedStarts.append(rawContent.distance(from: rawContent.startIndex, to: range.lowerBound))
            searchStart = range.upperBound
        }
        let actualStarts = candidates.compactMap { $0.metadata["source_span_start"].flatMap(Int.init) }
        #expect(actualStarts == expectedStarts)

        for candidate in candidates {
            let start = try #require(candidate.metadata["source_span_start"].flatMap(Int.init))
            let end = try #require(candidate.metadata["source_span_end"].flatMap(Int.init))
            #expect(String(rawContent[rawContent.index(rawContent.startIndex, offsetBy: start)..<rawContent.index(rawContent.startIndex, offsetBy: end)]) == duplicatedLine)
            #expect(candidate.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote] == candidate.evidence)
            #expect(candidate.metadata["truth_boundary"] == "reviewable_candidate_not_truth")
        }
    }

    @Test("CLI graph candidate JSON promotes source spans beside source quote")
    func cliGraphCandidateJSONPromotesSourceSpansBesideSourceQuote() throws {
        let sourceOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        var output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: .object,
            mentionText: "pineapple coconut drink",
            sourceQuote: "- Jami loved that pineapple coconut drink",
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            safeActions: [.inspectSource, .accept, .reject],
            source: "graph_candidate.test"
        )
        output.metadata["source_span_start"] = "17"
        output.metadata["source_span_end"] = "55"

        let listCandidate = CiderCLI.graphCandidateToDict(output)
        #expect(listCandidate["sourceQuote"] as? String == "- Jami loved that pineapple coconut drink")
        #expect(listCandidate["sourceSpanStart"] as? Int == 17)
        #expect(listCandidate["sourceSpanEnd"] as? Int == 55)
        #expect((listCandidate["metadata"] as? [String: String])?["source_span_start"] == "17")
        #expect((listCandidate["metadata"] as? [String: String])?["source_span_end"] == "55")
        #expect((listCandidate["sourceEvidenceRecord"] as? [String: Any])?["spanStart"] as? Int == 17)
        #expect((listCandidate["sourceEvidenceRecord"] as? [String: Any])?["spanEnd"] as? Int == 55)
        #expect(listCandidate["truthState"] as? String == "reviewable_candidate_not_truth")

        let inspectPayload: [String: Any] = [
            "ok": true,
            "command": "item.graph-candidate",
            "readOnly": true,
            "changed": false,
            "exists": true,
            "candidate": CiderCLI.graphCandidateToDict(output),
        ]
        let inspectedCandidate = try #require(inspectPayload["candidate"] as? [String: Any])
        #expect(inspectedCandidate["sourceSpanStart"] as? Int == 17)
        #expect(inspectedCandidate["sourceSpanEnd"] as? Int == 55)

        let sourceEvidence = try #require(CiderCLI.graphObjectSourceEvidence(from: [output]).first)
        #expect(sourceEvidence["sourceQuote"] as? String == "- Jami loved that pineapple coconut drink")
        #expect(sourceEvidence["sourceSpanStart"] as? Int == 17)
        #expect(sourceEvidence["sourceSpanEnd"] as? Int == 55)
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
            - Ryland wanted Starbucks, so Visher took her to Starbucks for her birthday.
            - Visher got Buffalo Wild Wings hot honey sauce and liked it.
            - Visher finished watching season 2 of the live-action Avatar: The Last Airbender on Netflix, or at least watched through seven episodes.
            - Visher saw on r/Boeing that the CMS/outage left about 40 systems down during the shift.
            - Visher took PTO for Ryland's birthday and worked overtime around it.
            - They went to the mall and she was buying random things; money seemed more useful than guessing a gift.
            """
        )

        let graphOutputs = result.outputs.filter { $0.kind == "graph_candidate" }
        let graphValues = graphOutputs.map(\.value)
        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        let allValues = result.outputs.map(\.value)
        #expect(graphValues.contains("Reminders of Him"))
        #expect(graphValues.contains("The Way Way Back"))
        #expect(graphValues.contains("the Marysville outlet mall"))
        #expect(graphValues.contains("Nike store"))
        #expect(graphValues.contains("Starbucks"))
        #expect(graphValues.contains("Buffalo Wild Wings hot honey sauce"))
        #expect(graphValues.contains("Avatar: The Last Airbender"))
        #expect(allValues.contains { $0.localizedCaseInsensitiveContains("CMS/outage") || $0.localizedCaseInsensitiveContains("40 systems down") })
        #expect(allValues.contains { $0.localizedCaseInsensitiveContains("PTO") || $0.localizedCaseInsensitiveContains("overtime") })
        #expect(allValues.contains { $0.localizedCaseInsensitiveContains("money") && $0.localizedCaseInsensitiveContains("gift") })
        #expect(graphOutputs.map(\.evidence).contains("- Jami and Visher watched Reminders of Him while eating"))
        #expect(graphOutputs.first { $0.value == "The Way Way Back" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"watched\"]")
        #expect(graphOutputs.first { $0.value == "the Marysville outlet mall" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"visited\"]")
        #expect(graphOutputs.first { $0.value == "Nike store" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.subjectText] == "Bane")
        #expect(graphOutputs.first { $0.value == "Nike store" }?.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"wants\"]")
        let avatar = try #require(graphOutputs.first { $0.value == "Avatar: The Last Airbender" })
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] == "[\"watched\"]")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaTitle] == "Avatar: The Last Airbender")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaType] == "show")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaProgressKind] == "season_episode_progress")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaSeasonNumber] == "2")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaEpisodeProgress] == "through 7 episodes")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaPlatform] == "Netflix")
        #expect(avatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote] == avatar.evidence)
        #expect(avatar.evidence.contains("Avatar: The Last Airbender"))
        #expect(avatar.evidence.contains("through seven episodes"))
        #expect(avatar.metadata["truth_boundary"] == "reviewable_candidate_not_truth")
        #expect(avatar.reviewState == "suggested")
        #expect(graphOutputs.allSatisfy { $0.reviewState == "suggested" })
        #expect(memoryOutputs.allSatisfy { $0.reviewState == "suggested" })
        #expect(result.outputs.allSatisfy { $0.metadata["source_owner_ref"] == owner.canonicalRef || $0.owner == owner })
        #expect(!graphValues.contains("it"))
        #expect(!graphValues.contains("bed"))
        #expect(!graphValues.contains("through seven episodes"))
        #expect(!graphValues.contains { $0.localizedCaseInsensitiveContains("on r/Boeing") })
        #expect(!graphValues.contains("the mall and she was buying random things; money seemed more useful than guessing a gift"))
        #expect(!graphValues.contains { $0.localizedCaseInsensitiveContains("money seemed more useful than guessing a gift") })
        #expect(!graphOutputs.contains { $0.value.localizedCaseInsensitiveContains("saw blades") })
    }

    @Test("journal extractor creates drive home daily life memory candidates")
    func journalExtractorCreatesDriveHomeDailyLifeMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: "4D9CEEB1-3182-4699-822D-FEEF626B2417")
        let rawContent = """
        Drive-home journal, 2026-06-19.
        I had my dental appointment at 12:30 today where they placed the dental implant post in my jaw. Later I need the crown or veneer or tooth put on, and I was a little worried about recovery, so I decided to be lazy and rest after.
        At work I practiced riveting for the first time in 5+ years. I shot size 8 rivets through the skin with a narrow bucking bar, damaged the stringer a little, but it is probably not serious and the other rivets came out fine.
        For breakfast I had a Costco meat stick and a Costco chocolate-chip granola bar. Around 8:00 I got the cafeteria chicken-fried-steak burrito, liked it, and want to know if they have it every Friday so I can get it more often.
        I decided not to work this weekend.
        My best friend Chris has a son Jacob and Jacob's birthday party is today with Alfie's pizza and maybe a movie, but I will probably skip it because of the dental appointment.
        """

        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: rawContent,
            date: "2026-06-19"
        )
        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        func candidate(_ key: String) throws -> SecondBrainEnrichmentOutput {
            try #require(memoryOutputs.first { $0.metadata["memory_key"] == key })
        }

        let dental = try candidate("dental-implant-post-placed-2026-06-19")
        #expect(dental.metadata["memory_kind"] == "medical_event")
        #expect(dental.metadata["event_time"] == "12:30")
        #expect(dental.metadata["date_context"] == "2026-06-19")
        #expect(dental.metadata["procedure"] == "dental implant post placed in jaw")
        #expect(dental.metadata["follow_up"]?.contains("crown") == true)
        #expect(dental.metadata["recovery_context"]?.contains("rest") == true)
        #expect(dental.metadata["source_owner_ref"] == owner.canonicalRef)
        #expect(dental.metadata["source_span_start"].flatMap(Int.init) != nil)
        #expect(dental.metadata["source_span_end"].flatMap(Int.init) != nil)
        #expect(dental.evidence.contains("12:30"))

        let riveting = try candidate("riveting-practice-stringer-incident-2026-06-19")
        #expect(riveting.metadata["memory_kind"] == "work_incident")
        #expect(riveting.metadata["rivet_size"] == "8")
        #expect(riveting.metadata["tool"] == "narrow bucking bar")
        #expect(riveting.metadata["damage"]?.contains("stringer") == true)
        #expect(riveting.metadata["severity"] == "probably_not_serious")
        #expect(riveting.metadata["recency_context"] == "first time in 5+ years")

        let breakfast = try candidate("breakfast-costco-meat-stick-granola-bar-2026-06-19")
        #expect(breakfast.metadata["memory_kind"] == "food_routine")
        #expect(breakfast.metadata["meal"] == "breakfast")
        #expect(breakfast.metadata["food_items"]?.contains("Costco") == true)
        #expect(breakfast.metadata["food_items"]?.contains("chocolate") == true)

        let burrito = try candidate("cafeteria-chicken-fried-steak-burrito-friday-2026-06-19")
        #expect(burrito.metadata["memory_kind"] == "food_preference")
        #expect(burrito.metadata["event_time"] == "8:00")
        #expect(burrito.metadata["merchant"] == "cafeteria")
        #expect(burrito.metadata["food_item"] == "chicken-fried-steak burrito")
        #expect(burrito.metadata["preference"] == "liked")
        #expect(burrito.metadata["availability_question"]?.contains("every Friday") == true)
        #expect(!burrito.value.localizedCaseInsensitiveContains("to get it more often"))

        let weekend = try candidate("no-weekend-work-plan-2026-06-19")
        #expect(weekend.metadata["memory_kind"] == "schedule_plan")
        #expect(weekend.metadata["plan_status"] == "not_working")
        #expect(weekend.metadata["date_context"] == "2026-06-19")

        let birthday = try candidate("chris-son-jacob-birthday-party-2026-06-19")
        #expect(birthday.metadata["memory_kind"] == "relationship_event")
        #expect(birthday.metadata["person"] == "Chris")
        #expect(birthday.metadata["related_person"] == "Jacob")
        #expect(birthday.metadata["relationship"] == "best friend Chris has son Jacob")
        #expect(birthday.metadata["event_type"] == "birthday_party")
        #expect(birthday.metadata["attendance_status"] == "likely_skipping")
        #expect(birthday.metadata["reason"]?.contains("dental appointment") == true)

        #expect(!result.outputs.contains { $0.value == "to get it more often" })
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
            "Visher's time-and-a-half overtime rate is $82.26/hr.",
            "Visher's double-time overtime rate is $109.68/hr.",
            "Visher has returned to weekend overtime after five years or more.",
            "Overtime pay calculations help Visher motivate himself to get up for early weekend overtime.",
            "Visher's budget normally depends on one full paycheck for bills and one full paycheck for rent.",
            "Consider an overnight oats reminder on nights before early weekend overtime.",
        ])
        #expect(memoryOutputs.allSatisfy { $0.reviewState == "suggested" })
        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-time-and-a-half-2026-06-13-82.26" }?.metadata["rate_kind"] == "time_and_a_half")
        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-double-time-2026-06-13-109.68" }?.metadata["rate_kind"] == "double_time")
        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "overtime-pay-motivation" }?.evidence.contains("$109.68/hr") == true)
        #expect(memoryOutputs.allSatisfy { $0.metadata["requires_review"] == "true" })
        #expect(memoryOutputs.allSatisfy { $0.metadata["journal_date"] == "2026-06-13" })
        #expect(memoryOutputs.map { $0.metadata["memory_kind"] } == ["payroll_rate_fact", "payroll_rate_fact", "pattern", "pattern", "pattern", "pattern"])
    }

    @Test("journal extractor proposes structured payroll rate memory candidates")
    func journalExtractorProposesStructuredPayrollRateMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Current Wage Card note:
            IAM Grade 5 max at Boeing has straight-time hourly rate $54.84/hr.
            Time-and-a-half overtime rate is $82.26/hr.
            Double-time Sunday rate is $109.68/hr.
            """,
            date: "2026-06-13",
            time: "03:16"
        )

        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        let straight = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-straight-time-2026-06-13-54.84" })
        #expect(straight.reviewState == "suggested")
        #expect(straight.value == "Visher's straight-time hourly rate is $54.84/hr.")
        #expect(straight.evidence == "IAM Grade 5 max at Boeing has straight-time hourly rate $54.84/hr")
        #expect(straight.metadata["memory_kind"] == "payroll_rate_fact")
        #expect(straight.metadata["fact_type"] == "pay_rate")
        #expect(straight.metadata["rate_kind"] == "straight_time")
        #expect(straight.metadata["rate_multiplier"] == "1.0")
        #expect(straight.metadata["hourly_rate"] == "54.84")
        #expect(straight.metadata["currency"] == "USD")
        #expect(straight.metadata["rate_unit"] == "hour")
        #expect(straight.metadata["employer"] == "Boeing")
        #expect(straight.metadata["union_or_grade"] == "IAM Grade 5 max")
        #expect(straight.metadata["date_context"] == "2026-06-13")
        #expect(straight.metadata["time_context"] == "03:16")
        #expect(straight.metadata["source_owner_ref"] == owner.canonicalRef)
        #expect(straight.metadata["review_query_terms"]?.contains("what is my hourly rate") == true)

        let overtime = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-time-and-a-half-2026-06-13-82.26" })
        #expect(overtime.value == "Visher's time-and-a-half overtime rate is $82.26/hr.")
        #expect(overtime.metadata["rate_kind"] == "time_and_a_half")
        #expect(overtime.metadata["rate_multiplier"] == "1.5")
        #expect(overtime.metadata["hourly_rate"] == "82.26")
        #expect(overtime.metadata["review_query_terms"]?.contains("time and a half rate") == true)

        let doubleTime = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-double-time-2026-06-13-109.68" })
        #expect(doubleTime.value == "Visher's double-time overtime rate is $109.68/hr.")
        #expect(doubleTime.metadata["rate_kind"] == "double_time")
        #expect(doubleTime.metadata["rate_multiplier"] == "2.0")
        #expect(doubleTime.metadata["hourly_rate"] == "109.68")
        #expect(doubleTime.metadata["review_query_terms"]?.contains("double time rate") == true)
    }

    @Test("journal extractor pairs live payroll rates with the right overtime kind")
    func journalExtractorPairsLivePayrollRatesWithTheRightOvertimeKind() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            The reason he asked about hourly wages was motivation: knowing today is about $82.26/hr and Sunday is about $109.68/hr makes it easier to get up and do the overtime.
            Visher said it is hard to justify sleeping longer when Sunday overtime is over $100/hr.
            At the saved Grade 5 max rate ($54.84/hr): 40 straight hours = $2,193.60; 16 total time-and-a-half hours = $1,316.16; 8 double-time hours = $877.44; total gross = $4,387.20 before taxes/deductions.
            """,
            date: "2026-06-13",
            time: "03:45"
        )

        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        let straight = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-straight-time-2026-06-13-54.84" })
        #expect(straight.metadata["rate_kind"] == "straight_time")
        #expect(straight.metadata["hourly_rate"] == "54.84")
        #expect(straight.evidence.contains("saved Grade 5 max rate") == true)

        let overtime = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-time-and-a-half-2026-06-13-82.26" })
        #expect(overtime.metadata["rate_kind"] == "time_and_a_half")
        #expect(overtime.metadata["hourly_rate"] == "82.26")
        #expect(overtime.evidence.contains("today is about $82.26/hr") == true)

        let doubleTime = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-double-time-2026-06-13-109.68" })
        #expect(doubleTime.metadata["rate_kind"] == "double_time")
        #expect(doubleTime.metadata["hourly_rate"] == "109.68")
        #expect(doubleTime.evidence.contains("Sunday is about $109.68/hr") == true)

        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-time-and-a-half-2026-06-13-54.84" } == nil)
        #expect(memoryOutputs.first { $0.metadata["memory_key"] == "payroll-rate-double-time-2026-06-13-100" } == nil)
    }

    @Test("journal extractor proposes structured gas spending memory candidates")
    func journalExtractorProposesStructuredGasSpendingMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: "47A5C67B-5D99-4A75-A2FC-D88034661FE1")
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Retroactive recovered journal entry — 2026-06-11 morning gas fill-up / commute

            Recovered from Hermes Discord session search after Visher clarified this was the later morning fill-up after the Duvall trip.

            Gas/fuel spending:
            - Filled up while driving to work in the morning.
            - Total: $81.07.
            - Fuel amount: 12.87 gallons.
            - Effective price: about $6.30/gallon.
            - Fuel grade: mid-grade / 89 octane.
            - Vehicle context: Visher said he should be getting premium because of the turbo in his Mazda CX-5, but premium would be even more expensive, so he has been using mid-grade.
            - Reaction: gas was "fricking ridiculous" / "too fucking expensive."
            """,
            date: "2026-06-11",
            time: "03:50"
        )

        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        let gasFact = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "spending-gas-fill-up-2026-06-11-81.07" })
        #expect(gasFact.reviewState == "suggested")
        #expect(gasFact.value.contains("$81.07"))
        #expect(gasFact.value.contains("12.87 gallons"))
        #expect(gasFact.value.contains("$6.30/gal"))
        #expect(gasFact.value.contains("mid-grade / 89 octane"))
        #expect(gasFact.evidence.contains("Gas/fuel spending:"))
        #expect(gasFact.evidence.contains("Total: $81.07"))
        #expect(gasFact.metadata["memory_kind"] == "spending_fact")
        #expect(gasFact.metadata["fact_type"] == "fuel_purchase")
        #expect(gasFact.metadata["spending_category"] == "gas")
        #expect(gasFact.metadata["amount"] == "81.07")
        #expect(gasFact.metadata["currency"] == "USD")
        #expect(gasFact.metadata["quantity"] == "12.87")
        #expect(gasFact.metadata["quantity_unit"] == "gallons")
        #expect(gasFact.metadata["unit_price"] == "6.30")
        #expect(gasFact.metadata["unit_price_unit"] == "USD_per_gallon")
        #expect(gasFact.metadata["fuel_grade"] == "mid-grade / 89 octane")
        #expect(gasFact.metadata["date_context"] == "2026-06-11")
        #expect(gasFact.metadata["time_context"] == "03:50")
        #expect(gasFact.metadata["source_owner_ref"] == owner.canonicalRef)
        #expect(gasFact.metadata["candidate_ref"] == "memory_candidate:\(gasFact.id)")
        #expect(gasFact.metadata["source_kind"] == "journal")
        #expect(gasFact.metadata["source_quote"]?.contains("Gas/fuel spending:") == true)
        #expect(gasFact.metadata["source_span_start"].flatMap(Int.init) != nil)
        #expect(gasFact.metadata["source_span_end"].flatMap(Int.init) != nil)
        #expect(gasFact.metadata["related_entities"]?.contains("Duvall") == true)
        #expect(gasFact.metadata["related_entities"]?.contains("Mazda CX-5") == true)
        #expect(gasFact.metadata["review_query_terms"]?.contains("last time I filled up") == true)
    }

    @Test("journal extractor proposes structured prose spending memory candidates")
    func journalExtractorProposesStructuredProseSpendingMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: """
            Lunch and errand spending:
            Visher grabbed Panda Express for lunch and spent $17.42 on orange chicken and chow mein.
            At the gas station, he also bought a Monster and a protein bar for about $9.58.
            """,
            date: "2026-06-13",
            time: "12:25"
        )

        let memoryOutputs = result.outputs.filter { $0.kind == "memory_candidate" }
        let lunch = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "spending-food-2026-06-13-17.42" })
        #expect(lunch.reviewState == "suggested")
        #expect(lunch.value == "Visher spent $17.42 on food at Panda Express on 2026-06-13.")
        #expect(lunch.evidence == "Visher grabbed Panda Express for lunch and spent $17.42 on orange chicken and chow mein")
        #expect(lunch.metadata["memory_kind"] == "spending_fact")
        #expect(lunch.metadata["fact_type"] == "food_purchase")
        #expect(lunch.metadata["spending_category"] == "food")
        #expect(lunch.metadata["merchant"] == "Panda Express")
        #expect(lunch.metadata["amount"] == "17.42")
        #expect(lunch.metadata["currency"] == "USD")
        #expect(lunch.metadata["date_context"] == "2026-06-13")
        #expect(lunch.metadata["time_context"] == "12:25")
        #expect(lunch.metadata["source_owner_ref"] == owner.canonicalRef)
        #expect(lunch.metadata["source_quote"] == lunch.evidence)
        #expect(lunch.metadata["source_span_start"].flatMap(Int.init) != nil)
        #expect(lunch.metadata["source_span_end"].flatMap(Int.init) != nil)
        #expect(lunch.metadata["review_query_terms"]?.contains("what did I spend on food") == true)

        let gasStation = try #require(memoryOutputs.first { $0.metadata["memory_key"] == "spending-gas-station-2026-06-13-9.58" })
        #expect(gasStation.value == "Visher spent about $9.58 at a gas station on 2026-06-13.")
        #expect(gasStation.metadata["fact_type"] == "gas_station_purchase")
        #expect(gasStation.metadata["spending_category"] == "gas_station")
        #expect(gasStation.metadata["amount_qualifier"] == "about")
        #expect(gasStation.metadata["related_entities"]?.contains("Monster") == true)
        #expect(gasStation.metadata["related_entities"]?.contains("protein bar") == true)
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
