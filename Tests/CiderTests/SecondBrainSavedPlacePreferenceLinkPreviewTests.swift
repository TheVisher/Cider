import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Second Brain Saved Place Preference Link Preview Tests")
@MainActor
struct SecondBrainSavedPlacePreferenceLinkPreviewTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-saved-place-preference-preview-\(UUID().uuidString).db")
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

    @Test("preview proposes saved restaurant link to source-backed journal food preference")
    func previewProposesSavedRestaurantLinkToJournalFoodPreference() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let journal = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let restaurant = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let unrelated = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(owner: journal, title: "Daily Journal - 2026-07-01", into: db)
        try insertBookmarkItem(
            owner: restaurant,
            title: "Bangkok Garden Thai Restaurant",
            url: "https://www.yelp.com/biz/bangkok-garden-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: unrelated,
            title: "Trail running backpack",
            url: "https://example.com/products/trail-running-backpack",
            into: db
        )

        var preference = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: journal,
            candidateKind: .objectRelation,
            mentionText: "Asian food",
            sourceQuote: "I keep gravitating toward Asian food for weeknight dinners.",
            sourceKind: "journal",
            objectTypeGuesses: [.food],
            relationGuesses: [.likesFood],
            actionGuesses: ["likes"],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.87,
            confidenceReason: "Journal sentence explicitly states a food preference.",
            source: "graph_candidate.journal_capture"
        )
        preference.createdAt = Date(timeIntervalSince1970: 1_782_950_400)
        preference.updatedAt = preference.createdAt
        try SecondBrainEnrichmentOutputService(database: db).record(preference)

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(report.truthBoundary == "reviewable_candidate_not_truth")
        #expect(report.candidates.count == 1)
        #expect(after == before)

        let candidate = try #require(report.candidates.first)
        #expect(candidate.savedItem.owner == restaurant)
        #expect(candidate.evidenceItem.owner == journal)
        #expect(candidate.savedItem.snippet.contains("Bangkok Garden"))
        #expect(candidate.evidenceItem.snippet.contains("Asian food"))
        #expect(candidate.preferenceValue == "Asian food")
        #expect(candidate.confidence >= 0.70)
        #expect(candidate.reasonCodes.contains("saved_restaurant_matches_food_preference"))
        #expect(candidate.reason.contains("Thai"))
        #expect(candidate.truthBoundary == "reviewable_candidate_not_truth")
        #expect(candidate.sourceRefs.contains(restaurant.canonicalRef))
        #expect(candidate.sourceRefs.contains(journal.canonicalRef))
        #expect(candidate.safeVerificationCommands.contains("cider-cli item context bookmark \(restaurant.ownerID) --json"))
        #expect(candidate.safeVerificationCommands.contains("cider-cli item context note \(journal.ownerID) --json"))
        #expect(candidate.safeNextCommands.allSatisfy { !$0.contains("accept") && !$0.contains("reconcile") })

        let payload = CiderCLI.savedPlacePreferenceLinkPreviewPayload(report)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect((payload["safeVerificationCommands"] as? [String])?.contains("cider-cli item saved-place-preference-links --json") == true)
        let payloadCandidates = try #require(payload["candidates"] as? [[String: Any]])
        #expect(payloadCandidates.count == 1)
        #expect(payloadCandidates[0]["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect((payloadCandidates[0]["sourceRefs"] as? [String])?.contains(journal.canonicalRef) == true)
        #expect((payloadCandidates[0]["sourceRefs"] as? [String])?.contains(restaurant.canonicalRef) == true)
    }

    @Test("preview ignores unrelated noisy saves")
    func previewIgnoresUnrelatedNoisySaves() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let journal = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let unrelated = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(owner: journal, title: "Daily Journal - 2026-07-02", into: db)
        try insertBookmarkItem(
            owner: unrelated,
            title: "Compact camera bag",
            url: "https://example.com/products/compact-camera-bag",
            into: db
        )

        let preference = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: journal,
            candidateKind: .objectRelation,
            mentionText: "Asian food",
            sourceQuote: "Asian food is usually the easiest dinner win for me.",
            sourceKind: "journal",
            objectTypeGuesses: [.food],
            relationGuesses: [.likesFood],
            confidence: 0.84,
            confidenceReason: "Journal sentence explicitly states a food preference.",
            source: "graph_candidate.journal_capture"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(preference)

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.candidates.isEmpty)
        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(after == before)
    }

    @Test("preview matches obvious cuisine aliases and reports compact diagnostics")
    func previewMatchesCuisineAliasesAndReportsDiagnostics() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let journal = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let tacoPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let noisySave = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(owner: journal, title: "Daily Journal - 2026-07-03", into: db)
        try insertBookmarkItem(
            owner: tacoPlace,
            title: "El Camino Tacos Restaurant",
            url: "https://www.yelp.com/biz/el-camino-tacos-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Rainy Day Ramen Restaurant",
            url: "https://www.yelp.com/biz/rainy-day-ramen-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: noisySave,
            title: "Compact camera bag",
            url: "https://example.com/products/compact-camera-bag",
            into: db
        )

        let preference = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: journal,
            candidateKind: .objectRelation,
            mentionText: "Mexican food",
            sourceQuote: "I want more Mexican food in the weeknight rotation.",
            sourceKind: "journal",
            objectTypeGuesses: [.food],
            relationGuesses: [.likesFood],
            confidence: 0.88,
            confidenceReason: "Journal sentence explicitly states a food preference.",
            source: "graph_candidate.journal_capture"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(preference)

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(after == before)
        #expect(report.candidates.count == 1)

        let candidate = try #require(report.candidates.first)
        #expect(candidate.savedItem.owner == tacoPlace)
        #expect(candidate.preferenceValue == "Mexican food")
        #expect(candidate.reasonCodes.contains("cuisine_alias_family_match"))
        #expect(candidate.reason.contains("Mexican"))
        #expect(candidate.sourceRefs.contains(tacoPlace.canonicalRef))
        #expect(candidate.sourceRefs.contains(journal.canonicalRef))

        #expect(report.diagnostics.inspectedBookmarkCount == 3)
        #expect(report.diagnostics.savedPlaceBookmarkCount == 2)
        #expect(report.diagnostics.preferenceEvidenceCount == 1)
        #expect(report.diagnostics.candidateCount == 1)
        #expect(report.diagnostics.skippedBookmarkSamples.contains {
            $0.owner == noisySave && $0.reasonCode == "not_saved_place_candidate"
        })
        #expect(report.diagnostics.noMatchSamples.contains {
            $0.owner == ramenPlace && $0.reasonCode == "no_shared_cuisine_alias"
        })

        let payload = CiderCLI.savedPlacePreferenceLinkPreviewPayload(report)
        let diagnostics = try #require(payload["diagnostics"] as? [String: Any])
        #expect(diagnostics["inspectedBookmarkCount"] as? Int == 3)
        #expect(diagnostics["preferenceEvidenceCount"] as? Int == 1)
        let skipped = try #require(diagnostics["skippedBookmarkSamples"] as? [[String: Any]])
        #expect(skipped.contains { $0["reasonCode"] as? String == "not_saved_place_candidate" })
        let noMatches = try #require(diagnostics["noMatchSamples"] as? [[String: Any]])
        #expect(noMatches.contains { $0["reasonCode"] as? String == "no_shared_cuisine_alias" })
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        let afterReceipt = try #require(receipt["after"] as? [String: Any])
        #expect(afterReceipt["candidateCount"] as? Int == 1)
        #expect((afterReceipt["diagnostics"] as? [String: Any])?["inspectedBookmarkCount"] as? Int == 3)
    }

    private func insertNoteItem(owner: SecondBrainOwnerRef, title: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(title, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind("Journal/\(owner.ownerID).md", at: 5)
        try itemStmt.step()

        let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, '', NULL, 0);")
        noteStmt.bind(owner.ownerID, at: 1)
        try noteStmt.step()
    }

    private func insertBookmarkItem(owner: SecondBrainOwnerRef, title: String, url: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(title, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind("Bookmarks/\(owner.ownerID).md", at: 5)
        try itemStmt.step()

        let bookmarkStmt = try db.prepare("INSERT INTO bookmarks (item_id, url, notes) VALUES (?, ?, '');")
        bookmarkStmt.bind(owner.ownerID, at: 1)
            .bind(url, at: 2)
        try bookmarkStmt.step()
    }

    private func mutationCounts(in db: CiderDatabase) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["owner_relations", "similarity_candidates", "source_evidence", "enrichment_outputs"] {
            let stmt = try db.prepare("SELECT COUNT(*) FROM \(table);")
            _ = try stmt.step()
            counts[table] = stmt.int(at: 0)
        }
        return counts
    }
}
