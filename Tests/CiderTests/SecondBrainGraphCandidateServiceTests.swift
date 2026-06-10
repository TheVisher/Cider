import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Graph Candidate Service Tests")
@MainActor
struct SecondBrainGraphCandidateServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-graph-candidate-\(UUID().uuidString).db")
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

    @Test("journal drink preference becomes reviewable source-backed graph candidate")
    func journalDrinkPreferenceCandidate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertItem(owner: owner, title: "Daily Journal 2026-06-09", into: db)

        let result = try SecondBrainGraphCandidateService(database: db).extract(
            owner: owner,
            sourceText: "I gave Jami that pineapple coconut drink and she loved it.",
            sourceKind: "journal",
            date: "2026-06-09"
        )

        #expect(result.candidates.count == 1)
        let candidate = try #require(result.candidates.first)
        #expect(candidate.kind == "graph_candidate")
        #expect(candidate.reviewState == "suggested")
        #expect(candidate.metadata["subject_text"] == "Jami")
        #expect(candidate.metadata["object_text"] == "pineapple coconut drink")
        #expect(candidate.metadata["accepted_relation_type"] == "likes_drink")
        #expect(candidate.metadata["source_quote"]?.contains("pineapple coconut drink") == true)

        let context = try CiderItemContextService(database: db).context(
            for: LibraryEntityRef(type: .note, entityID: UUID(uuidString: owner.ownerID)!)
        )
        #expect(context.enrichmentOutputs.contains { $0.id == candidate.id })

        let reviewItems = try CiderReviewQueueService(database: db).list(kind: "graph_candidate").items
        #expect(reviewItems.contains { $0.graphCandidateID == candidate.id })
    }

    @Test("journal media and ambiguous place mentions land in review queue")
    func journalMediaAndAmbiguousPlaceCandidates() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertItem(owner: owner, title: "Daily Journal 2026-06-09", into: db)

        let result = try SecondBrainGraphCandidateService(database: db).extract(
            owner: owner,
            sourceText: "I watched The Way Way Back last night. We went to Cactus and Jami liked the margarita.",
            sourceKind: "journal",
            date: "2026-06-09"
        )

        #expect(result.candidates.contains { candidate in
            candidate.metadata["object_text"] == "The Way Way Back"
                && (DatabaseHelpers.decodeJSON([String].self, from: candidate.metadata["type_guesses"]) ?? []).contains("movie")
        })
        #expect(result.candidates.contains { candidate in
            candidate.metadata["object_text"] == "Cactus"
                && (DatabaseHelpers.decodeJSON([String].self, from: candidate.metadata["review_choices"]) ?? []).contains("Restaurant/place")
        })
        #expect(result.candidates.contains { $0.metadata["object_text"] == "margarita" && $0.metadata["subject_text"] == "Jami" })

        let review = try CiderReviewQueueService(database: db).captureReviewWorklist(limit: 10)
        #expect(review.countsByReasonCode["graph_candidate_review", default: 0] >= 3)
        #expect(review.items.contains { $0.reasonCodes.contains("graph_candidate_ambiguous_type") })
    }

    @Test("IMDb URL capture proposes represented media object candidate")
    func imdbURLCandidate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertItem(owner: owner, title: "The Way Way Back - IMDb", into: db)

        let result = try SecondBrainGraphCandidateService(database: db).extract(
            owner: owner,
            sourceText: nil,
            sourceURL: "https://www.imdb.com/title/tt1727388/",
            sourceKind: "url",
            title: "The Way Way Back"
        )

        let candidate = try #require(result.candidates.first)
        #expect(candidate.metadata["source_url"] == "https://www.imdb.com/title/tt1727388/")
        #expect(candidate.metadata["accepted_relation_type"] == "represents")
        #expect((DatabaseHelpers.decodeJSON([String].self, from: candidate.metadata["type_guesses"]) ?? []).contains("media_item"))
    }

    @Test("accepting candidate creates source-backed relation and rejecting does not")
    func acceptAndRejectCandidates() throws {
        let (acceptDB, acceptURL) = try makeTestDB()
        defer { acceptDB.close(); cleanup(acceptURL) }

        let acceptOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertItem(owner: acceptOwner, title: "Daily Journal 2026-06-09", into: acceptDB)
        let acceptService = SecondBrainGraphCandidateService(database: acceptDB)
        let acceptCandidate = try #require(try acceptService.extract(
            owner: acceptOwner,
            sourceText: "I gave Jami that pineapple coconut drink and she loved it.",
            sourceKind: "journal"
        ).candidates.first)

        let accepted = try acceptService.accept(candidateID: acceptCandidate.id, actor: "test")
        #expect(accepted.status == "accepted")
        #expect(accepted.relations.contains { $0.relationType == "likes_drink" && $0.evidence.contains("pineapple coconut drink") })
        #expect(try SecondBrainEnrichmentOutputService(database: acceptDB).output(id: acceptCandidate.id)?.reviewState == "accepted")
        #expect(try SecondBrainStore(database: acceptDB).outgoingRelations(for: acceptOwner).contains { $0.metadata["candidate_id"] == acceptCandidate.id })

        let (rejectDB, rejectURL) = try makeTestDB()
        defer { rejectDB.close(); cleanup(rejectURL) }

        let rejectOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertItem(owner: rejectOwner, title: "Daily Journal 2026-06-09", into: rejectDB)
        let rejectService = SecondBrainGraphCandidateService(database: rejectDB)
        let rejectCandidate = try #require(try rejectService.extract(
            owner: rejectOwner,
            sourceText: "I watched The Way Way Back last night.",
            sourceKind: "journal"
        ).candidates.first)

        let rejected = try rejectService.reject(candidateID: rejectCandidate.id, actor: "test", reason: "Wrong extraction")
        #expect(rejected.status == "rejected")
        #expect(try SecondBrainStore(database: rejectDB).outgoingRelations(for: rejectOwner).isEmpty)
        #expect(try SecondBrainEnrichmentOutputService(database: rejectDB).output(id: rejectCandidate.id)?.reviewState == "rejected")
    }

    private func insertItem(owner: SecondBrainOwnerRef, title: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(owner.ownerType, at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind("Inbox/\(title)", at: 6)
        try itemStmt.step()

        if owner.ownerType == "note" {
            let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, '', NULL, 0);")
            noteStmt.bind(owner.ownerID, at: 1)
            try noteStmt.step()
        }
        if owner.ownerType == "bookmark" {
            let bookmarkStmt = try db.prepare("INSERT INTO bookmarks (item_id, url) VALUES (?, 'https://example.com');")
            bookmarkStmt.bind(owner.ownerID, at: 1)
            try bookmarkStmt.step()
        }
    }
}
