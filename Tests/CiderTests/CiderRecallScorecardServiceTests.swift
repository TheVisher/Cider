import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Recall Scorecard Service Tests")
@MainActor
struct CiderRecallScorecardServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-recall-scorecard-\(UUID().uuidString).db")
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

    private func insertItem(
        _ ref: LibraryEntityRef,
        title: String,
        relativePath: String?,
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        let now = DatabaseHelpers.encode(Date())
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    @Test("explicit recall probes score lookup context related and reminder surfacing")
    func explicitProbesScoreLookupContextRelatedAndReminderSurfacing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 16, hour: 9))!

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let todoRef = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(note, title: "Moonstone soup recipe", relativePath: "Recipes/Moonstone soup.md", into: db)
        try insertItem(bookmark, title: "Farmer market preorder", relativePath: "Bookmarks/Farmer market preorder.url", into: db)
        try insertItem(todoRef, title: "Renew passport", relativePath: "Todos/Renew passport.md", into: db)

        let store = SecondBrainStore(database: db)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.replaceChunks(owner: noteOwner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Recipe body",
                body: "The moonstone recipe needs farmer market preorder pickup notes.",
                chunkIndex: 0
            )
        ])

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let todo = TodoCard(id: todoRef.entityID, title: "Renew passport", dueDate: now)
        let service = CiderRecallScorecardService(
            database: db,
            linkService: linkService,
            secondBrainStore: store,
            todoProvider: { [todo] },
            dateCardProvider: { [] },
            nowProvider: { now },
            calendar: calendar
        )

        let scorecard = try service.evaluate(probes: [
            CiderRecallProbe(
                id: "recipe",
                title: "Find recipe and its source link",
                query: "moonstone preorder",
                expectedRef: note,
                expectedRelatedRefs: [bookmark]
            ),
            CiderRecallProbe(
                id: "passport",
                title: "Find surfaced passport reminder",
                query: "passport",
                expectedRef: todoRef,
                expectsSurfaceToday: true
            )
        ])

        #expect(scorecard.totalProbeCount == 2)
        #expect(scorecard.passedProbeCount == 2)
        #expect(scorecard.capabilityScores[.lookup]?.passed == 2)
        #expect(scorecard.capabilityScores[.context]?.passed == 2)
        #expect(scorecard.capabilityScores[.related]?.passed == 1)
        #expect(scorecard.capabilityScores[.reminderSurfacing]?.passed == 1)
        #expect(scorecard.results.allSatisfy { $0.passed })
        #expect(scorecard.results[0].topResults.first?.matchedExpected == true)
        #expect(scorecard.results[0].topResults.first?.stage != nil)
        #expect(scorecard.results[0].topResults.first?.matchedQuery != nil)
        #expect(scorecard.results[0].topResults.first?.rankFactors.isEmpty == false)
        #expect(scorecard.results[1].checks.contains {
            $0.capability == .reminderSurfacing && $0.passed && $0.detail == "surfaceToday=true"
        })
    }

    @Test("scorecard JSON exposes totals capabilities and actionable failed checks")
    func scorecardJSONExposesTotalsCapabilitiesAndFailures() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let missing = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Trip packing list", relativePath: "Notes/Trip packing list.md", into: db)

        let service = CiderRecallScorecardService(database: db)
        let scorecard = try service.evaluate(probes: [
            CiderRecallProbe(
                id: "missing-related",
                title: "Find packing list with related booking",
                query: "packing",
                expectedRef: note,
                expectedRelatedRefs: [missing]
            )
        ])

        #expect(scorecard.passedProbeCount == 0)
        #expect(scorecard.failedProbeCount == 1)

        let dict = recallScorecardToDict(scorecard)
        #expect(dict["totalProbeCount"] as? Int == 1)
        #expect(dict["passedProbeCount"] as? Int == 0)
        let capabilities = try #require(dict["capabilityScores"] as? [[String: Any]])
        #expect(capabilities.contains {
            $0["capability"] as? String == "related" && $0["passed"] as? Int == 0 && $0["failed"] as? Int == 1
        })
        let results = try #require(dict["results"] as? [[String: Any]])
        let checks = try #require(results[0]["checks"] as? [[String: Any]])
        #expect(checks.contains {
            $0["capability"] as? String == "related" &&
            $0["passed"] as? Bool == false &&
            ($0["detail"] as? String)?.contains(missing.entityID.uuidString) == true
        })
    }

    @Test("scorecard context tolerates vaults missing second brain routing decisions table")
    func scorecardContextToleratesMissingRoutingDecisionTable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        try db.runSQL("DROP TABLE second_brain_routing_decisions;")

        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            bookmark,
            title: "Local-first retrieval notes",
            relativePath: "Inbox/Bookmarks/Local-first retrieval notes.webloc",
            into: db
        )

        let service = CiderRecallScorecardService(database: db)
        let scorecard = try service.evaluate(probes: [
            CiderRecallProbe(
                id: "legacy-vault-context",
                title: "Find legacy vault item",
                query: "Local-first retrieval",
                expectedRef: bookmark
            )
        ])

        #expect(scorecard.passedProbeCount == 1)
        #expect(scorecard.capabilityScores[.context]?.passed == 1)
    }
}
