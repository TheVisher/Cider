import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Natural Preference Recall Tests")
@MainActor
struct NaturalPreferenceRecallTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-natural-preference-recall-\(UUID().uuidString).db")
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

    private func insertJournal(
        id: UUID,
        title: String,
        body: String,
        createdAt: Date,
        into db: CiderDatabase,
        store: SecondBrainStore
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(ItemLinkService.databaseItemType(for: .note), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(createdAt), at: 4)
            .bind(DatabaseHelpers.encode(createdAt), at: 5)
            .bind("Inbox/Notes/\(title).md", at: 6)
        try stmt.step()

        try store.replaceChunks(owner: SecondBrainOwnerRef(ownerType: "note", ownerID: id.uuidString), chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: id.uuidString,
                source: "item_index.note",
                title: title,
                body: body,
                chunkIndex: 0
            )
        ])
    }

    @Test("subject preference question returns cited journal observations without promoting truth")
    func subjectPreferenceQuestionReturnsCitedJournalObservations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let tasteJournalID = UUID()
        try insertJournal(
            id: tasteJournalID,
            title: "Daily Journal 2026-06-27",
            body: """
            Taste Of Aloha DoorDash order:
            - Hamburger Steak Loco Moco was okay.
            - Kimchee cucumbers were great.
            - Fried Spam Musubi was great and worth ordering again.
            """,
            createdAt: Date(timeIntervalSince1970: 1_782_528_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answer("what did I like at Taste Of Aloha?", limit: 5)

        #expect(response.command == "item.preference-recall")
        #expect(response.readOnly == true)
        #expect(response.changed == false)
        #expect(response.intent.subject == "Taste Of Aloha")
        #expect(response.intent.questionKind == .liked)
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(response.summary.contains("Kimchee cucumbers"))
        #expect(response.summary.contains("Fried Spam Musubi"))
        #expect(response.summary.contains("not accepted memory truth"))
        #expect(response.citations.contains { citation in
            citation.owner.ownerID == tasteJournalID.uuidString
                && citation.title == "Daily Journal 2026-06-27"
                && citation.quote.contains("Fried Spam Musubi")
        })
        #expect(response.candidates.count == 1)
        let candidate = try #require(response.candidates.first)
        #expect(candidate.owner.ownerID == tasteJournalID.uuidString)
        #expect(candidate.title == "Daily Journal 2026-06-27")
        #expect(candidate.itemType == "note")
        #expect(candidate.itemID == tasteJournalID.uuidString)
        #expect(candidate.evidenceKind == "source_backed_observation")
        #expect(candidate.claim.contains("Kimchee cucumbers"))
        #expect(candidate.claim.contains("Fried Spam Musubi"))
        #expect(candidate.citationRefs.count == 1)
        #expect(candidate.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(candidate.rankReason.contains("specific"))
        #expect(response.safeNextCommands.contains("cider-cli item search \"Taste Of Aloha\" --scope personalMemory --sort newest --limit 5 --json"))
        #expect(response.safeNextCommands.contains("cider-cli item context note \(tasteJournalID.uuidString) --json"))
    }

    @Test("repeated evidence from the same item dedupes to one structured candidate")
    func repeatedEvidenceFromSameItemDedupesToOneStructuredCandidate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let tasteJournalID = UUID()
        try insertJournal(
            id: tasteJournalID,
            title: "Daily Journal 2026-06-27",
            body: """
            Taste Of Aloha DoorDash order:
            - Fried Spam Musubi was great and worth ordering again.

            Later note: Taste Of Aloha Fried Spam Musubi still seems worth ordering again.
            """,
            createdAt: Date(timeIntervalSince1970: 1_782_528_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answer("what did I like at Taste Of Aloha?", limit: 5)

        #expect(response.citations.map(\.owner.ownerID) == [tasteJournalID.uuidString])
        #expect(response.candidates.map(\.owner.ownerID) == [tasteJournalID.uuidString])
        let candidate = try #require(response.candidates.first)
        #expect(candidate.claim.contains("Fried Spam Musubi"))
        #expect(candidate.citationRefs.count == 1)
        #expect(candidate.score > 0)
    }

    @Test("saved place to try surfaces as candidate without becoming accepted preference truth")
    func savedPlaceToTrySurfacesAsCandidateWithoutBecomingTruth() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let tokuniID = UUID()
        try insertJournal(
            id: tokuniID,
            title: "Saved Places To Try",
            body: "Tokuni in Lynnwood was saved to try for Asian food. Source was a shared place note, not a visit or accepted preference.",
            createdAt: Date(timeIntervalSince1970: 1_782_528_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answer("what Lynnwood Asian food places did I save to try?", limit: 5)

        #expect(response.summary.contains("Tokuni"))
        let candidate = try #require(response.candidates.first { $0.claim.contains("Tokuni") })
        #expect(candidate.evidenceKind == "source_backed_candidate")
        #expect(candidate.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(candidate.rankReason.contains("saved-to-try"))
        #expect(!candidate.rankReason.contains("accepted preference"))
    }

    @Test("broad liked lately question combines multiple source backed item observations")
    func broadLikedLatelyQuestionCombinesMultipleJournalObservations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let burritoJournalID = UUID()
        let tasteJournalID = UUID()
        try insertJournal(
            id: burritoJournalID,
            title: "Daily Journal 2026-06-19",
            body: "For breakfast I had the cafeteria chicken-fried-steak burrito, liked it, and want to know if they have it every Friday so I can get it more often.",
            createdAt: Date(timeIntervalSince1970: 1_781_837_200),
            into: db,
            store: store
        )
        try insertJournal(
            id: tasteJournalID,
            title: "Daily Journal 2026-06-27",
            body: "Taste Of Aloha: Fried Spam Musubi was great and worth ordering again. Kimchee cucumbers were great.",
            createdAt: Date(timeIntervalSince1970: 1_782_528_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answer("what food have I liked lately?", limit: 6)

        #expect(response.intent.subject == nil)
        #expect(response.intent.questionKind == .recentLiked)
        #expect(response.summary.contains("chicken-fried-steak burrito"))
        #expect(response.summary.contains("Fried Spam Musubi"))
        #expect(response.citations.map(\.owner.ownerID).contains(burritoJournalID.uuidString))
        #expect(response.citations.map(\.owner.ownerID).contains(tasteJournalID.uuidString))
        #expect(response.reviewStatus.needsReview == false)
        #expect(response.searchPlan.contains { $0.query == "liked great worth ordering again food" })
    }

    @Test("general memory recall returns non food work fact with cited source boundary")
    func generalMemoryRecallReturnsNonFoodWorkFactWithCitedSourceBoundary() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let coverallsNoteID = UUID()
        try insertJournal(
            id: coverallsNoteID,
            title: "Work coveralls size",
            body: "Visher is 6'3, and Red Kap size 60-RG / 60 regular navy coveralls fit well for work.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what size coveralls fit me at work?", limit: 5)

        #expect(response.command == "item.memory-recall")
        #expect(response.readOnly == true)
        #expect(response.changed == false)
        #expect(response.intent.questionKind == .general)
        #expect(response.summary.contains("Red Kap size 60-RG"))
        #expect(response.summary.contains("not accepted memory truth"))
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
        let candidate = try #require(response.candidates.first)
        #expect(candidate.owner.ownerID == coverallsNoteID.uuidString)
        #expect(candidate.title == "Work coveralls size")
        #expect(candidate.evidenceKind == "source_backed_memory_observation")
        #expect(candidate.claim.contains("60 regular navy coveralls"))
        #expect(candidate.rankReason.contains("query fact match"))
        #expect(candidate.citationRefs == ["note:\(coverallsNoteID.uuidString)"])
        #expect(response.safeNextCommands.contains("cider-cli item memory-recall \"what size coveralls fit me at work?\" --limit 5 --json"))
        #expect(response.safeNextCommands.contains("cider-cli item context note \(coverallsNoteID.uuidString) --json"))
        #expect(response.verificationCommands.contains("cider-cli item context note \(coverallsNoteID.uuidString) --json"))
        let provenance = try #require(candidate.provenance)
        #expect(provenance.sourceRef == "note:\(coverallsNoteID.uuidString)")
        #expect(provenance.sourceType == "note")
        #expect(provenance.sourceID == coverallsNoteID.uuidString)
        #expect(provenance.sourceTitle == "Work coveralls size")
        #expect(provenance.sourceLocation == "Inbox/Notes/Work coveralls size.md")
        #expect(provenance.evidenceKind == "source_backed_memory_observation")
        #expect(provenance.evidenceExcerpt.contains("60 regular navy coveralls"))
        #expect(provenance.citationRefs == ["note:\(coverallsNoteID.uuidString)"])
        #expect(provenance.contextCommands.contains("cider-cli item context note \(coverallsNoteID.uuidString) --json"))
        #expect(provenance.verificationCommands.contains("cider-cli item get note \(coverallsNoteID.uuidString) --json"))
    }

    @Test("memory recall today intent ranks newest strong journal evidence before older vague Boeing notes")
    func memoryRecallTodayIntentRanksNewestJournalEvidenceFirst() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let olderBoeingNoteID = UUID()
        let todayJournalID = UUID()
        try insertJournal(
            id: olderBoeingNoteID,
            title: "OneNote Boeing systems background",
            body: "Background note: what happened with Boeing systems being down was discussed as a generic work risk, with no 40-system outage details.",
            createdAt: Date(timeIntervalSince1970: 1_782_086_400),
            into: db,
            store: store
        )
        try insertJournal(
            id: todayJournalID,
            title: "Daily Journal 2026-06-30",
            body: """
            Today is Ryland's birthday; remember to wish her happy birthday.
            Voice journal: Boeing had about 40 systems down today, so the outage was the thing I wanted to remember from the shift.
            """,
            createdAt: Date(timeIntervalSince1970: 1_782_950_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what happened with Boeing systems being down today?", limit: 3)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let intent = try #require(payload["intent"] as? [String: Any])

        #expect(response.candidates.first?.owner.ownerID == todayJournalID.uuidString)
        #expect(response.citations.first?.owner.ownerID == todayJournalID.uuidString)
        #expect(response.summary.contains("40 systems down today"))
        #expect(response.summary.contains("not accepted memory truth"))
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(response.candidates.first?.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(response.candidates.first?.citationRefs == ["note:\(todayJournalID.uuidString)"])
        #expect(response.candidates.first?.rankReason.contains("explicit temporal intent") == true)
        #expect(response.candidates.contains { $0.owner.ownerID == olderBoeingNoteID.uuidString })
        #expect(response.searchPlan.allSatisfy { $0.sort == .newest })
        #expect(intent["temporalIntent"] as? String == "today")
        #expect(response.safeNextCommands.contains("cider-cli item search \"boeing systems down today\" --scope personalMemory --sort newest --limit 3 --json"))
    }

    @Test("generic today memory recall ranks current source date before stale today word matches")
    func genericTodayMemoryRecallRanksCurrentSourceDateFirst() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let olderTodayWordNoteID = UUID()
        let currentJournalID = UUID()
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let older = Calendar(identifier: .gregorian).date(byAdding: .day, value: -12, to: now) ?? Date(timeIntervalSince1970: 1_782_086_400)
        try insertJournal(
            id: olderTodayWordNoteID,
            title: "Daily Journal stale today wording",
            body: """
            I said today was messy. Today I said the team should keep a generic today checklist.
            This older note keeps saying today today today, but it is not from the current source date.
            """,
            createdAt: older,
            into: db,
            store: store
        )
        try insertJournal(
            id: currentJournalID,
            title: "Daily Journal \(dayFormatter.string(from: now))",
            body: "Voice journal capture: Boeing had about 40 systems down during the shift, and Ryland's birthday came up.",
            createdAt: now,
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what did I say today?", limit: 3)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let intent = try #require(payload["intent"] as? [String: Any])
        let candidates = try #require(payload["candidates"] as? [[String: Any]])
        let firstCandidate = try #require(candidates.first)

        #expect(intent["temporalIntent"] as? String == "today")
        #expect(response.intent.semanticQueryTerms == ["say", "today"])
        #expect(response.candidates.first?.owner.ownerID == currentJournalID.uuidString)
        #expect(response.citations.first?.owner.ownerID == currentJournalID.uuidString)
        #expect(response.candidates.contains { $0.owner.ownerID == olderTodayWordNoteID.uuidString })
        #expect(response.candidates.first?.rankReason.contains("generic explicit-date source-date match") == true)
        #expect(response.candidates.first?.matchExplanation.contains("generic explicit-date recall anchored to source date") == true)
        #expect(firstCandidate["rankReason"] as? String == response.candidates.first?.rankReason)
        #expect((firstCandidate["matchExplanation"] as? String)?.contains("generic explicit-date recall anchored to source date") == true)
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
        #expect(response.changed == false)
    }

    @Test("latest journal thing wording ranks newest Daily Journal source date before older stronger word hits")
    func latestJournalThingWordingRanksNewestJournalSourceDateFirst() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let olderStrongJournalID = UUID()
        let newestJournalID = UUID()
        try insertJournal(
            id: olderStrongJournalID,
            title: "Daily Journal 2026-06-28",
            body: """
            Older journal wording trap: latest journal thing I said, latest journal thing I said, latest journal thing I said.
            I said this older entry has many body-word hits, but it is not the newest Daily Journal source date.
            """,
            createdAt: Date(timeIntervalSince1970: 1_782_086_400),
            into: db,
            store: store
        )
        try insertJournal(
            id: newestJournalID,
            title: "Daily Journal 2026-06-30",
            body: "Morning drive journal entry: source-backed note from the newest Daily Journal.",
            createdAt: Date(timeIntervalSince1970: 1_782_950_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what is the latest journal thing I said?", limit: 5)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let intent = try #require(payload["intent"] as? [String: Any])
        let firstCandidate = try #require(response.candidates.first)

        #expect(intent["temporalIntent"] as? String == "latest")
        #expect(response.intent.searchQueries.first == "Daily Journal")
        #expect(firstCandidate.owner.ownerID == newestJournalID.uuidString)
        #expect(response.citations.first?.owner.ownerID == newestJournalID.uuidString)
        #expect(response.candidates.contains { $0.owner.ownerID == olderStrongJournalID.uuidString })
        #expect(firstCandidate.rankReason.contains("latest journal source-date match"))
        #expect(firstCandidate.matchExplanation.contains("latest journal recall anchored to Daily Journal source date"))
        #expect(response.rankingExplanation.contains("latest journal source date first"))
        #expect(response.summary.contains("Daily Journal 2026-06-30"))
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
    }

    @Test("latest DCC recall can use recency but plain DCC recall keeps semantic ranking")
    func latestDCCRecallCanUseRecencyWhilePlainDCCKeepsSemanticRanking() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let olderSemanticJournalID = UUID()
        let newerMentionJournalID = UUID()
        try insertJournal(
            id: olderSemanticJournalID,
            title: "Daily Journal 2026-06-28",
            body: "I say Dungeon Crawler Carl is a funny, kinetic audiobook. Dungeon Crawler Carl keeps working because Carl and Donut make the dungeon premise feel specific.",
            createdAt: Date(timeIntervalSince1970: 1_782_086_400),
            into: db,
            store: store
        )
        try insertJournal(
            id: newerMentionJournalID,
            title: "Daily Journal 2026-06-30",
            body: "Latest drive note: still listening to Dungeon Crawler Carl.",
            createdAt: Date(timeIntervalSince1970: 1_782_950_400),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let latestResponse = try service.answerMemory("what is the latest thing I said about Dungeon Crawler Carl?", limit: 5)
        let plainResponse = try service.answerMemory("what did I say about Dungeon Crawler Carl?", limit: 5)

        #expect(latestResponse.intent.temporalIntent == "latest")
        #expect(latestResponse.candidates.first?.owner.ownerID == newerMentionJournalID.uuidString)
        #expect(!latestResponse.candidates.first!.rankReason.contains("latest journal source-date match"))
        #expect(plainResponse.intent.temporalIntent == nil)
        #expect(plainResponse.candidates.first?.owner.ownerID == olderSemanticJournalID.uuidString)
        #expect(plainResponse.rankingExplanation.contains("semantic term overlap"))
    }

    @Test("CLI JSON formatter exposes natural memory recall contract")
    func cliJSONFormatterExposesNaturalMemoryRecallContract() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let lockerNoteID = UUID()
        try insertJournal(
            id: lockerNoteID,
            title: "Work locker code",
            body: "The work locker uses code 2468 for the temporary supply cage.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what is the work locker code?", limit: 5)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)

        #expect(payload["command"] as? String == "item.memory-recall")
        let actionReceipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(actionReceipt["command"] as? String == "item.memory-recall")
        #expect(actionReceipt["commandFamily"] as? String == "item")
        #expect(actionReceipt["subcommand"] as? String == "memory-recall")
        #expect(actionReceipt["readOnly"] as? Bool == true)
        #expect(actionReceipt["changed"] as? Bool == false)
        #expect(actionReceipt["status"] as? String == "succeeded")
        #expect(actionReceipt["matchedCount"] as? Int == 1)
        #expect((actionReceipt["matchedSourceRefs"] as? [String])?.contains("note:\(lockerNoteID.uuidString)") == true)
        #expect((actionReceipt["safeCommandRefs"] as? [String])?.contains("cider-cli item context note \(lockerNoteID.uuidString) --json") == true)
        #expect(actionReceipt["verificationHint"] as? String == "verify_with_safe_commands_and_source_refs")
        #expect(actionReceipt["truthBoundary"] as? String == "receipt_proves_command_execution_not_memory_truth")
        let answer = try #require(payload["answer"] as? [String: Any])
        #expect(answer["kind"] as? String == "natural_memory_recall")
        #expect(answer["truthBoundary"] as? String == "source_backed_observations_not_accepted_truth")
        let candidates = try #require(payload["candidates"] as? [[String: Any]])
        let candidate = try #require(candidates.first)
        #expect(candidate["evidenceKind"] as? String == "source_backed_memory_observation")
        #expect((candidate["claim"] as? String)?.contains("2468") == true)
        let provenance = try #require(candidate["provenance"] as? [String: Any])
        #expect(provenance["sourceRef"] as? String == "note:\(lockerNoteID.uuidString)")
        #expect(provenance["sourceType"] as? String == "note")
        #expect(provenance["sourceID"] as? String == lockerNoteID.uuidString)
        #expect(provenance["sourceTitle"] as? String == "Work locker code")
        #expect(provenance["sourceLocation"] as? String == "Inbox/Notes/Work locker code.md")
        #expect((provenance["evidenceExcerpt"] as? String)?.contains("2468") == true)
        #expect((provenance["contextCommands"] as? [String])?.contains("cider-cli item context note \(lockerNoteID.uuidString) --json") == true)
        #expect((provenance["verificationCommands"] as? [String])?.contains("cider-cli item get note \(lockerNoteID.uuidString) --json") == true)
        let verificationCommands = try #require(payload["verificationCommands"] as? [String])
        #expect(verificationCommands.contains("cider-cli item context note \(lockerNoteID.uuidString) --json"))
        let citations = try #require(payload["citations"] as? [[String: Any]])
        #expect((citations.first?["quote"] as? String)?.contains("temporary supply cage") == true)
        let safeNextCommands = try #require(payload["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item memory-recall \"what is the work locker code?\" --limit 5 --json"))
    }

    @Test("memory recall misses do not use preference wording")
    func memoryRecallMissesDoNotUsePreferenceWording() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what size coveralls fit me at work?", limit: 5)

        #expect(response.command == "item.memory-recall")
        #expect(response.summary.contains("memory recall question"))
        #expect(response.warnings == ["No source-backed item or chunk matches were found for this natural memory recall query."])
        #expect(response.safeNextCommands.contains("cider-cli item memory-recall \"what size coveralls fit me at work?\" --limit 5 --json"))
    }

    @Test("memory recall synthesizes concise fact answer from source evidence")
    func memoryRecallSynthesizesConciseFactAnswer() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let coverallsNoteID = UUID()
        try insertJournal(
            id: coverallsNoteID,
            title: "Work coveralls size",
            body: """
            Context: older PPE note, not all of it is relevant to size recall.
            Visher is 6'3, and Red Kap size 60-RG / 60 regular navy coveralls fit well for work.
            Unrelated: ask facilities about replacement gloves next quarter.
            """,
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what size coveralls fit me at work?", limit: 5)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let answer = try #require(payload["answer"] as? [String: Any])

        #expect(response.summary.contains("Red Kap size 60-RG / 60 regular navy coveralls fit well for work."))
        #expect(!response.summary.contains("replacement gloves"))
        #expect(answer["text"] as? String == response.summary)
        #expect(response.candidates.first?.owner.ownerID == coverallsNoteID.uuidString)
    }

    @Test("memory recall coveralls variants use semantic query terms and keep source boundary")
    func memoryRecallCoverallsVariantsUseSemanticQueryTerms() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let coverallsNoteID = UUID()
        try insertJournal(
            id: coverallsNoteID,
            title: "Work coveralls size",
            body: "Visher is 6'3, and Red Kap size 60-RG / 60 regular navy coveralls fit well for work.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what did I save about work coveralls?", limit: 5)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let intent = try #require(payload["intent"] as? [String: Any])

        #expect(response.candidates.first?.owner.ownerID == coverallsNoteID.uuidString)
        #expect(response.summary.contains("Red Kap size 60-RG"))
        #expect(response.intent.factTarget == "work_coveralls_size")
        #expect(response.intent.semanticQueryTerms.contains("size"))
        #expect(response.intent.semanticQueryTerms.contains("fit"))
        #expect(intent["factTarget"] as? String == "work_coveralls_size")
        #expect((intent["semanticQueryTerms"] as? [String])?.contains("coveralls") == true)
        #expect(payload["rankingExplanation"] as? String == response.rankingExplanation)
    }

    @Test("memory recall detects clothing size fact family beyond coveralls")
    func memoryRecallDetectsClothingSizeFactFamilyBeyondCoveralls() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let bootNoteID = UUID()
        try insertJournal(
            id: bootNoteID,
            title: "Workshop boot fit",
            body: "For workshop boots, size 13 wide fit best with the thicker work socks.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what boot size did I save for workshop boots?", limit: 5)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)
        let intent = try #require(payload["intent"] as? [String: Any])
        let candidates = try #require(payload["candidates"] as? [[String: Any]])
        let candidate = try #require(candidates.first)

        #expect(response.intent.factFamily == "clothing_size_fit")
        #expect(response.intent.factTarget == "workshop_boot_size")
        #expect(response.intent.semanticQueryTerms.contains("wide"))
        #expect(intent["factFamily"] as? String == "clothing_size_fit")
        #expect(intent["factTarget"] as? String == "workshop_boot_size")
        #expect(response.candidates.first?.owner.ownerID == bootNoteID.uuidString)
        #expect((candidate["matchedSemanticTerms"] as? [String])?.contains("workshop") == true)
        #expect((candidate["matchExplanation"] as? String)?.contains("clothing_size_fit") == true)
        #expect(response.summary.contains("size 13 wide fit best"))
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
    }

    @Test("memory recall detects tool preference fact family")
    func memoryRecallDetectsToolPreferenceFactFamily() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let toolNoteID = UUID()
        try insertJournal(
            id: toolNoteID,
            title: "Desk tool notes",
            body: "For precise desk work, the Wera micro screwdriver kit is the preferred tool because the bits do not strip tiny screws.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what screwdriver kit do I prefer for desk work?", limit: 5)

        #expect(response.intent.factFamily == "tool_gadget_preference")
        #expect(response.intent.factTarget == "desk_screwdriver_kit_preference")
        #expect(response.candidates.first?.owner.ownerID == toolNoteID.uuidString)
        #expect(response.candidates.first?.matchedSemanticTerms.contains("screwdriver") == true)
        #expect(response.candidates.first?.matchExplanation.contains("tool_gadget_preference") == true)
        #expect(response.summary.contains("Wera micro screwdriver kit"))
    }

    @Test("memory recall detects health care note fact family without accepted truth promotion")
    func memoryRecallDetectsHealthCareNoteFactFamily() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let dentalNoteID = UUID()
        try insertJournal(
            id: dentalNoteID,
            title: "Dental care note",
            body: "Dental care note: use the sensitive toothpaste at night after flossing, according to the saved care reminder.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what dental care note did I save about toothpaste?", limit: 5)

        #expect(response.intent.factFamily == "health_care_note")
        #expect(response.intent.factTarget == "dental_toothpaste_care_note")
        #expect(response.candidates.first?.owner.ownerID == dentalNoteID.uuidString)
        #expect(response.candidates.first?.matchedSemanticTerms.contains("dental") == true)
        #expect(response.candidates.first?.matchExplanation.contains("source-backed terms") == true)
        #expect(response.summary.contains("sensitive toothpaste"))
        #expect(response.truthBoundary == "source_backed_observations_not_accepted_truth")
    }

    @Test("memory recall bounded fact families avoid false positive matches")
    func memoryRecallBoundedFactFamiliesAvoidFalsePositiveMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        try insertJournal(
            id: UUID(),
            title: "Dental care note",
            body: "Dental care note: use the sensitive toothpaste at night after flossing.",
            createdAt: Date(timeIntervalSince1970: 1_782_701_200),
            into: db,
            store: store
        )

        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what work tool did I save for night shift?", limit: 5)

        #expect(response.candidates.isEmpty)
        #expect(response.intent.factFamily == "work_schedule_fact")
        #expect(response.broaderSearchCommand == "cider-cli item search \"work tool night shift schedule\" --scope personalMemory --sort newest --limit 10 --json")
        #expect(response.safeNextCommands.contains(response.broaderSearchCommand!))
    }

    @Test("memory recall miss includes broader search fallback metadata")
    func memoryRecallMissIncludesBroaderSearchFallbackMetadata() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let service = CiderNaturalPreferenceRecallService(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        )

        let response = try service.answerMemory("what did I save about lunar hiking boots?", limit: 3)
        let payload = CiderCLI.naturalPreferenceRecallResponseToDict(response)

        #expect(response.candidates.isEmpty)
        #expect(response.intent.factFamily == nil)
        #expect(response.summary.contains("Try the broader source search fallback"))
        #expect(response.broaderSearchCommand == "cider-cli item search \"lunar hiking boots\" --scope personalMemory --sort newest --limit 10 --json")
        #expect(response.safeNextCommands.contains(response.broaderSearchCommand!))
        #expect(response.verificationCommands.contains(response.broaderSearchCommand!))
        #expect(payload["broaderSearchCommand"] as? String == response.broaderSearchCommand)
        let fallback = try #require(payload["fallback"] as? [String: Any])
        #expect(fallback["truthBoundary"] as? String == "source_lookup_not_memory_truth")
        #expect(fallback["safeNextCommand"] as? String == response.broaderSearchCommand)
        #expect(fallback["nextContextCommandShape"] as? String == "cider-cli item context <type> <id-or-ref> --json")
        #expect((fallback["safeNextCommands"] as? [String])?.contains(response.broaderSearchCommand!) == true)
    }
}
