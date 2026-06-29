import Foundation
import Testing
@testable import Cider

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
}
