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

    @Test("preview inspects live-inspired restaurant saves without admitting noisy food media")
    func previewInspectsLiveInspiredRestaurantSavesWithoutAdmittingNoisyFoodMedia() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let journal = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let titleOnlyRamen = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let toastRestaurant = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let socialRestaurant = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let noisySocialClip = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let recipe = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let product = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(owner: journal, title: "Daily Journal - 2026-07-07", into: db)
        try insertBookmarkItem(
            owner: titleOnlyRamen,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )
        try insertBookmarkItem(
            owner: toastRestaurant,
            title: "Nom Nom Sando | Toast",
            url: "https://www.toasttab.com/local/order/nom-nom-sando",
            ocrText: "Nom Nom Sando 4744 University Way Northeast Seattle, WA 98105 Udon Fried Chicken Wings",
            into: db
        )
        try insertBookmarkItem(
            owner: socialRestaurant,
            title: "Seattle day place to try from TikTok",
            url: "https://www.tiktok.com/@foodfinder/video/123",
            ocrText: "Trying viral pop up sushi in Seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: noisySocialClip,
            title: "funny ramen reaction clip",
            url: "https://www.tiktok.com/@memes/video/456",
            into: db
        )
        try insertBookmarkItem(
            owner: recipe,
            title: "Homemade ramen recipe for rainy days",
            url: "https://example.com/recipes/homemade-ramen",
            into: db
        )
        try insertBookmarkItem(
            owner: product,
            title: "Ceramic ramen bowl set",
            url: "https://example.com/products/ceramic-ramen-bowl-set",
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

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(after == before)
        #expect(report.diagnostics.inspectedBookmarkCount == 6)
        #expect(report.diagnostics.savedPlaceBookmarkCount == 3)
        #expect(report.candidates.contains { $0.savedItem.owner == titleOnlyRamen })
        #expect(report.candidates.contains { $0.savedItem.owner == toastRestaurant })
        #expect(report.candidates.contains { $0.savedItem.owner == socialRestaurant })
        #expect(report.candidates.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(report.diagnostics.noMatchSamples.allSatisfy { $0.owner != titleOnlyRamen && $0.owner != toastRestaurant && $0.owner != socialRestaurant })
        #expect(report.diagnostics.skippedBookmarkSamples.contains {
            $0.owner == noisySocialClip && $0.reasonCode == "not_saved_place_candidate"
        })
        #expect(report.diagnostics.skippedBookmarkSamples.contains {
            $0.owner == recipe && $0.reasonCode == "not_saved_place_candidate"
        })
        #expect(report.diagnostics.skippedBookmarkSamples.contains {
            $0.owner == product && $0.reasonCode == "not_saved_place_candidate"
        })
    }

    @Test("preview discovers source-backed food preference note language with false-positive guards")
    func previewDiscoversFoodPreferenceNoteLanguageWithFalsePositiveGuards() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let ramenNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let koreanNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let negativeNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let koreanPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: ramenNote,
            title: "Daily Journal - 2026-07-04",
            content: "I have been craving ramen and Japanese food lately.",
            into: db
        )
        try insertNoteItem(
            owner: koreanNote,
            title: "Daily Journal - 2026-07-05",
            content: "Korean BBQ chicken is one of my favorite quick dinner ideas.",
            into: db
        )
        try insertNoteItem(
            owner: negativeNote,
            title: "Recipe Clip Notes",
            content: "Funny ramen recipe clip. Do not save this as a preference; it was just a meme.",
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )
        try insertBookmarkItem(
            owner: koreanPlace,
            title: "Bb.Q Chicken Lynnwood",
            url: "https://example.com/saved/bbq-chicken-lynnwood",
            into: db
        )

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(report.truthBoundary == "reviewable_candidate_not_truth")
        #expect(after == before)
        #expect(report.diagnostics.preferenceEvidenceCount == 2)
        #expect(report.candidates.contains { $0.savedItem.owner == ramenPlace && $0.evidenceItem.owner == ramenNote })
        #expect(report.candidates.contains { $0.savedItem.owner == koreanPlace && $0.evidenceItem.owner == koreanNote })
        #expect(report.candidates.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(report.candidates.allSatisfy { !$0.sourceRefs.contains(negativeNote.canonicalRef) })
        #expect(report.diagnostics.evidenceSamples.contains {
            $0.owner == ramenNote && $0.reasonCode == "usable_food_preference_evidence" && $0.matchedTerms.contains("ramen")
        })
        #expect(report.diagnostics.evidenceSamples.contains {
            $0.owner == koreanNote && $0.reasonCode == "usable_food_preference_evidence" && $0.matchedTerms.contains("korean")
        })
        #expect(report.diagnostics.evidenceRejectedSamples.contains {
            $0.owner == negativeNote && $0.reasonCode == "negative_or_non_preference_food_mention"
        })

        let payload = CiderCLI.savedPlacePreferenceLinkPreviewPayload(report)
        let diagnostics = try #require(payload["diagnostics"] as? [String: Any])
        let evidenceSamples = try #require(diagnostics["evidenceSamples"] as? [[String: Any]])
        #expect(evidenceSamples.contains { ($0["matchedTerms"] as? [String])?.contains("ramen") == true })
        let evidenceRejectedSamples = try #require(diagnostics["evidenceRejectedSamples"] as? [[String: Any]])
        #expect(evidenceRejectedSamples.contains { $0["reasonCode"] as? String == "negative_or_non_preference_food_mention" })
    }

    @Test("preview requires token boundaries for short cuisine aliases in raw notes")
    func previewRequiresTokenBoundariesForShortCuisineAliasesInRawNotes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let planningNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let phoNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let phoPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: planningNote,
            title: "Agent-native capture contract v1 audit",
            content: "Problem: I love that Telegram currently converts inbound messages/photos into prompt text. Phone metadata, Photoshop edits, and graph sync logs are infrastructure details.",
            into: db
        )
        try insertNoteItem(
            owner: phoNote,
            title: "Daily Journal - 2026-07-07",
            content: "I love pho for cold rainy evenings.",
            into: db
        )
        try insertBookmarkItem(
            owner: phoPlace,
            title: "Lotus Pho Restaurant",
            url: "https://example.com/saved/lotus-pho-seattle",
            into: db
        )

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(after == before)
        #expect(report.diagnostics.preferenceEvidenceCount == 1)
        #expect(report.diagnostics.evidenceSamples.contains {
            $0.owner == phoNote
                && $0.reasonCode == "usable_food_preference_evidence"
                && $0.matchedTerms == ["pho"]
        })
        #expect(report.diagnostics.evidenceSamples.allSatisfy { $0.owner != planningNote })
        #expect(report.candidates.contains { $0.savedItem.owner == phoPlace && $0.evidenceItem.owner == phoNote })
        #expect(report.candidates.allSatisfy { $0.evidenceItem.owner != planningNote })
    }

    @Test("preview rejects audit table food mentions unless they clearly describe a user preference")
    func previewRejectsAuditTableFoodMentionsUnlessTheyClearlyDescribeUserPreference() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let auditNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let koreanPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: auditNote,
            title: "2026-06-07-memory-trust-audit",
            content: "| Existing bookmark | `favorite Korean restaurant Bobae noodle` | Bookmarks / Food | Other favorite bookmarks | Open bookmark; optionally route to food/places |",
            into: db
        )
        try insertNoteItem(
            owner: preferenceNote,
            title: "Tokuni — Lynnwood Asian food place to try",
            content: "This fits Visher’s preference for Korean BBQ food and the current Alderwood food-planning thread.",
            into: db
        )
        try insertBookmarkItem(
            owner: koreanPlace,
            title: "Bb.Q Chicken Lynnwood",
            url: "https://example.com/saved/bbq-chicken-lynnwood",
            into: db
        )

        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)

        #expect(report.diagnostics.preferenceEvidenceCount == 1)
        #expect(report.diagnostics.evidenceSamples.contains {
            $0.owner == preferenceNote
                && $0.reasonCode == "usable_food_preference_evidence"
                && $0.matchedTerms.contains("korean")
        })
        #expect(report.diagnostics.evidenceSamples.allSatisfy { $0.owner != auditNote })
        #expect(report.diagnostics.evidenceRejectedSamples.contains {
            $0.owner == auditNote && $0.reasonCode == "planning_or_audit_food_mention"
        })
        #expect(report.candidates.contains { $0.savedItem.owner == koreanPlace && $0.evidenceItem.owner == preferenceNote })
        #expect(report.candidates.allSatisfy { $0.evidenceItem.owner != auditNote })
    }

    @Test("reciprocal preview groups source-backed preference evidence to related saved places")
    func reciprocalPreviewGroupsSourceBackedPreferenceEvidenceToRelatedSavedPlaces() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let planningNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let auditNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let phoPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let koreanPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let product = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let preferenceContent = "Dinner notes. I love pho, ramen, and Korean BBQ for rainy weeks. End."
        let preferencePhrase = "I love pho, ramen, and Korean BBQ for rainy weeks"
        try insertNoteItem(
            owner: preferenceNote,
            title: "Daily Journal - 2026-07-07",
            content: preferenceContent,
            into: db
        )
        try insertNoteItem(
            owner: planningNote,
            title: "Agent-native capture contract v1 audit",
            content: "Problem: I love that Telegram currently converts inbound messages/photos into prompt text. Phone metadata and Photoshop edits are infrastructure details.",
            into: db
        )
        try insertNoteItem(
            owner: auditNote,
            title: "2026-06-07-memory-trust-audit",
            content: "| Existing bookmark | `favorite Korean restaurant Bobae noodle` | Bookmarks / Food | Other favorite bookmarks | Open bookmark |",
            into: db
        )
        try insertBookmarkItem(
            owner: phoPlace,
            title: "Lotus Pho Restaurant",
            url: "https://example.com/saved/lotus-pho-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )
        try insertBookmarkItem(
            owner: koreanPlace,
            title: "Bb.Q Chicken Lynnwood",
            url: "https://example.com/saved/bbq-chicken-lynnwood",
            into: db
        )
        try insertBookmarkItem(
            owner: product,
            title: "Ceramic phone photo ramen bowl set",
            url: "https://example.com/products/phone-photo-ramen-bowl-set",
            into: db
        )

        let before = try mutationCounts(in: db)
        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .reciprocalPreview(ownerSelector: preferenceNote.ownerID.prefix(8).description, limit: 10)
        let after = try mutationCounts(in: db)

        #expect(report.readOnly == true)
        #expect(report.changed == false)
        #expect(report.truthBoundary == "reviewable_candidate_not_truth")
        #expect(after == before)
        #expect(report.groups.count == 1)

        let group = try #require(report.groups.first)
        #expect(group.evidenceItem.owner == preferenceNote)
        #expect(group.evidenceItem.sourceSpan?.sourceItemRef == preferenceNote.canonicalRef)
        #expect(group.evidenceItem.sourceSpan?.matchedText == preferencePhrase)
        #expect(group.evidenceItem.sourceSpan?.selector == "char:\(preferenceContent.characterOffset(of: preferencePhrase))..\(preferenceContent.characterOffset(of: preferencePhrase) + preferencePhrase.count)")
        #expect(group.sourceRefs.contains(preferenceNote.canonicalRef))
        #expect(group.candidates.count == 3)
        #expect(group.candidates.contains { $0.savedItem.owner == phoPlace })
        #expect(group.candidates.contains { $0.savedItem.owner == ramenPlace })
        #expect(group.candidates.contains { $0.savedItem.owner == koreanPlace })
        #expect(group.candidates.allSatisfy { $0.evidenceItem.owner == preferenceNote })
        #expect(group.candidates.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(group.candidates.allSatisfy { !$0.sourceRefs.contains(planningNote.canonicalRef) && !$0.sourceRefs.contains(auditNote.canonicalRef) })
        #expect(group.candidates.allSatisfy { $0.savedItem.owner != product })
        #expect(group.safeVerificationCommands.contains("cider-cli item context note \(preferenceNote.ownerID) --json"))
        #expect(group.safeNextCommands.allSatisfy { !$0.contains("accept") && !$0.contains("reconcile") })
        #expect(report.diagnostics.evidenceSamples.allSatisfy { $0.owner != planningNote && $0.owner != auditNote })
        #expect(report.diagnostics.evidenceRejectedSamples.contains { $0.owner == auditNote && $0.reasonCode == "planning_or_audit_food_mention" })

        let payload = CiderCLI.savedPlacePreferenceReciprocalLinkPreviewPayload(report)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(payload["command"] as? String == "item.preference-saved-place-links")
        let groups = try #require(payload["groups"] as? [[String: Any]])
        #expect(groups.count == 1)
        let groupDict = groups[0]
        #expect(groupDict["evidenceItemRef"] as? String == preferenceNote.canonicalRef)
        let evidenceItem = try #require(groupDict["evidenceItem"] as? [String: Any])
        let sourceSpan = try #require(evidenceItem["sourceSpan"] as? [String: Any])
        #expect(sourceSpan["matchedText"] as? String == preferencePhrase)
        let candidates = try #require(groupDict["candidates"] as? [[String: Any]])
        #expect(candidates.count == 3)
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["readOnly"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == false)
        let safeCommands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item preference-saved-place-links --owner \(preferenceNote.ownerID.prefix(8)) --json"))
    }

    @Test("item context surfaces compact reciprocal saved places for source-backed preference notes")
    func itemContextSurfacesCompactReciprocalSavedPlacesForPreferenceNotes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let unrelatedNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let phoPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let preferenceContent = "Dinner log. I love Asian food, especially pho and ramen when it is cold. Done."
        try insertNoteItem(
            owner: preferenceNote,
            title: "Daily Journal - 2026-07-06",
            content: preferenceContent,
            into: db
        )
        try insertNoteItem(
            owner: unrelatedNote,
            title: "Daily Journal - 2026-07-07",
            content: "Quiet day. I fixed a layout bug and took a walk.",
            into: db
        )
        try insertBookmarkItem(
            owner: phoPlace,
            title: "Lotus Pho Restaurant",
            url: "https://example.com/saved/lotus-pho-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )

        let before = try mutationCounts(in: db)
        let service = CiderItemContextService(database: db)
        let packet = try service.agentContext(for: LibraryEntityRef(type: .note, entityID: UUID(uuidString: preferenceNote.ownerID)!))
        let payload = CiderCLI.itemAgentContextPacketToDict(packet)
        let unrelatedPacket = try service.agentContext(for: LibraryEntityRef(type: .note, entityID: UUID(uuidString: unrelatedNote.ownerID)!))
        let unrelatedPayload = CiderCLI.itemAgentContextPacketToDict(unrelatedPacket)
        let after = try mutationCounts(in: db)

        #expect(after == before)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let relatedSavedPlaces = try #require(payload["relatedSavedPlaces"] as? [String: Any])
        #expect(relatedSavedPlaces["readOnly"] as? Bool == true)
        #expect(relatedSavedPlaces["changed"] as? Bool == false)
        #expect(relatedSavedPlaces["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(relatedSavedPlaces["acceptedAsTruth"] as? Bool == false)
        #expect(relatedSavedPlaces["groupCount"] as? Int == 1)
        #expect(relatedSavedPlaces["candidateCount"] as? Int == 2)
        let safeCommands = try #require(relatedSavedPlaces["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item preference-saved-place-links --owner \(preferenceNote.ownerID) --json"))
        #expect(safeCommands.contains("cider-cli item context note \(preferenceNote.ownerID) --json"))
        let topPlaces = try #require(relatedSavedPlaces["topRelatedSavedPlaces"] as? [[String: Any]])
        #expect(topPlaces.count == 2)
        #expect(topPlaces.contains { $0["savedItemRef"] as? String == phoPlace.canonicalRef })
        #expect(topPlaces.contains { $0["savedItemRef"] as? String == ramenPlace.canonicalRef })
        #expect(topPlaces.allSatisfy { $0["truthBoundary"] as? String == "reviewable_candidate_not_truth" })
        #expect(topPlaces.allSatisfy { $0["acceptedAsTruth"] as? Bool == false })
        let evidenceRefs = try #require(relatedSavedPlaces["evidenceRefs"] as? [String])
        #expect(evidenceRefs.contains(preferenceNote.canonicalRef))

        #expect(unrelatedPayload["relatedSavedPlaces"] == nil)
    }

    @Test("item search hints compact related saved places for source-backed preference notes")
    func itemSearchHintsCompactRelatedSavedPlacesForPreferenceNotes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let unrelatedNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let phoPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: preferenceNote,
            title: "Daily Journal - 2026-07-08",
            content: "Dinner log. I love Asian food, especially pho and ramen after long work days.",
            into: db
        )
        try insertNoteItem(
            owner: unrelatedNote,
            title: "Daily Journal - 2026-07-09",
            content: "Dinner log. Refactored item search and did not mention food preferences.",
            into: db
        )
        try insertBookmarkItem(
            owner: phoPlace,
            title: "Lotus Pho Restaurant",
            url: "https://example.com/saved/lotus-pho-seattle",
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )

        let before = try mutationCounts(in: db)
        let service = CiderItemContextService(database: db)
        let results = try service.search("Daily Journal", limit: 10, scope: .personalMemory)
        let after = try mutationCounts(in: db)

        #expect(after == before)
        let preferenceResult = try #require(results.first { $0.owner == preferenceNote })
        let preferencePayload = CiderCLI.itemSearchResultToDict(preferenceResult)
        let relatedSavedPlaces = try #require(preferencePayload["relatedSavedPlacesHint"] as? [String: Any])
        #expect(relatedSavedPlaces["readOnly"] as? Bool == true)
        #expect(relatedSavedPlaces["changed"] as? Bool == false)
        #expect(relatedSavedPlaces["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(relatedSavedPlaces["acceptedAsTruth"] as? Bool == false)
        #expect(relatedSavedPlaces["groupCount"] as? Int == 1)
        #expect(relatedSavedPlaces["relatedSavedPlaceCandidateCount"] as? Int == 2)
        #expect(relatedSavedPlaces["candidateCount"] as? Int == 2)
        let safeNextCommands = try #require(relatedSavedPlaces["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item context note \(preferenceNote.ownerID) --json"))
        #expect(safeNextCommands.contains("cider-cli item preference-saved-place-links --owner \(preferenceNote.ownerID) --json"))
        let safeVerificationCommands = try #require(relatedSavedPlaces["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item context note \(preferenceNote.ownerID) --json"))
        #expect(safeVerificationCommands.contains("cider-cli item preference-saved-place-links --owner \(preferenceNote.ownerID) --json"))

        let unrelatedResult = try #require(results.first { $0.owner == unrelatedNote })
        let unrelatedPayload = CiderCLI.itemSearchResultToDict(unrelatedResult)
        #expect(unrelatedPayload["relatedSavedPlacesHint"] == nil)
    }

    @Test("item context surfaces compact preference evidence for saved place bookmarks")
    func itemContextSurfacesCompactPreferenceEvidenceForSavedPlaceBookmarks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let savedPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let unrelatedBookmark = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: preferenceNote,
            title: "Daily Journal - 2026-07-10",
            content: "Dinner note. I love ramen and keep looking for cozy noodle shops after work.",
            into: db
        )
        try insertBookmarkItem(
            owner: savedPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )
        try insertBookmarkItem(
            owner: unrelatedBookmark,
            title: "Trail running backpack",
            url: "https://example.com/products/trail-running-backpack",
            into: db
        )

        let before = try mutationCounts(in: db)
        let service = CiderItemContextService(database: db)
        let packet = try service.agentContext(for: LibraryEntityRef(type: .bookmark, entityID: UUID(uuidString: savedPlace.ownerID)!))
        let payload = CiderCLI.itemAgentContextPacketToDict(packet)
        let unrelatedPacket = try service.agentContext(for: LibraryEntityRef(type: .bookmark, entityID: UUID(uuidString: unrelatedBookmark.ownerID)!))
        let unrelatedPayload = CiderCLI.itemAgentContextPacketToDict(unrelatedPacket)
        let after = try mutationCounts(in: db)

        #expect(after == before)
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        let evidence = try #require(payload["savedPlacePreferenceEvidence"] as? [String: Any])
        #expect(evidence["readOnly"] as? Bool == true)
        #expect(evidence["changed"] as? Bool == false)
        #expect(evidence["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(evidence["acceptedAsTruth"] as? Bool == false)
        #expect(evidence["candidateCount"] as? Int == 1)
        #expect(evidence["evidenceCount"] as? Int == 1)
        let topEvidence = try #require(evidence["topEvidence"] as? [[String: Any]])
        #expect(topEvidence.count == 1)
        #expect(topEvidence[0]["evidenceItemRef"] as? String == preferenceNote.canonicalRef)
        #expect((topEvidence[0]["snippet"] as? String)?.contains("ramen") == true)
        #expect(topEvidence[0]["savedItemRef"] as? String == savedPlace.canonicalRef)
        #expect(topEvidence[0]["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(topEvidence[0]["acceptedAsTruth"] as? Bool == false)
        let evidenceRefs = try #require(evidence["evidenceRefs"] as? [String])
        #expect(evidenceRefs.contains(preferenceNote.canonicalRef))
        let safeNextCommands = try #require(evidence["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item saved-place-preference-links --owner \(savedPlace.ownerID) --json"))
        #expect(safeNextCommands.contains("cider-cli item context bookmark \(savedPlace.ownerID) --json"))
        #expect(safeNextCommands.contains("cider-cli item context note \(preferenceNote.ownerID) --json"))
        let safeVerificationCommands = try #require(evidence["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item saved-place-preference-links --owner \(savedPlace.ownerID) --json"))

        #expect(unrelatedPayload["savedPlacePreferenceEvidence"] == nil)
    }

    @Test("item search hints compact preference evidence for saved place bookmarks")
    func itemSearchHintsCompactPreferenceEvidenceForSavedPlaceBookmarks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let preferenceNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let savedPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let unrelatedBookmark = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertNoteItem(
            owner: preferenceNote,
            title: "Daily Journal - 2026-07-11",
            content: "Dinner note. I love ramen and cozy noodle shops after long work days.",
            into: db
        )
        try insertBookmarkItem(
            owner: savedPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )
        try insertBookmarkItem(
            owner: unrelatedBookmark,
            title: "Trail running backpack",
            url: "https://example.com/products/trail-running-backpack",
            into: db
        )

        let before = try mutationCounts(in: db)
        let service = CiderItemContextService(database: db)
        let results = try service.search("Botan Trail", limit: 10, scope: .personalMemory)
        let after = try mutationCounts(in: db)

        #expect(after == before)
        let savedPlaceResult = try #require(results.first { $0.owner == savedPlace })
        let savedPlacePayload = CiderCLI.itemSearchResultToDict(savedPlaceResult)
        let preferenceEvidenceHint = try #require(savedPlacePayload["savedPlacePreferenceEvidenceHint"] as? [String: Any])
        #expect(preferenceEvidenceHint["readOnly"] as? Bool == true)
        #expect(preferenceEvidenceHint["changed"] as? Bool == false)
        #expect(preferenceEvidenceHint["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(preferenceEvidenceHint["acceptedAsTruth"] as? Bool == false)
        #expect(preferenceEvidenceHint["candidateCount"] as? Int == 1)
        #expect(preferenceEvidenceHint["evidenceCount"] as? Int == 1)
        let safeNextCommands = try #require(preferenceEvidenceHint["safeNextCommands"] as? [String])
        #expect(safeNextCommands.contains("cider-cli item context bookmark \(savedPlace.ownerID) --json"))
        #expect(safeNextCommands.contains("cider-cli item saved-place-preference-links --owner \(savedPlace.ownerID) --json"))
        let safeVerificationCommands = try #require(preferenceEvidenceHint["safeVerificationCommands"] as? [String])
        #expect(safeVerificationCommands.contains("cider-cli item context bookmark \(savedPlace.ownerID) --json"))
        #expect(safeVerificationCommands.contains("cider-cli item saved-place-preference-links --owner \(savedPlace.ownerID) --json"))

        let unrelatedResult = try #require(results.first { $0.owner == unrelatedBookmark })
        let unrelatedPayload = CiderCLI.itemSearchResultToDict(unrelatedResult)
        #expect(unrelatedPayload["savedPlacePreferenceEvidenceHint"] == nil)
    }

    @Test("preview emits replayable source span diagnostics for accepted and rejected raw note evidence")
    func previewEmitsReplayableSourceSpanDiagnosticsForRawNoteEvidence() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let acceptedNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rejectedNote = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let ramenPlace = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        let acceptedContent = "Lunch notes. I love ramen for rainy weeknight dinners. End."
        let acceptedPhrase = "I love ramen for rainy weeknight dinners"
        let rejectedContent = "Queue triage. Funny ramen recipe clip, not a preference. End."
        let rejectedPhrase = "Funny ramen recipe clip, not a preference"
        try insertNoteItem(
            owner: acceptedNote,
            title: "Daily Journal - 2026-07-06",
            content: acceptedContent,
            into: db
        )
        try insertNoteItem(
            owner: rejectedNote,
            title: "Recipe Clip Notes",
            content: rejectedContent,
            into: db
        )
        try insertBookmarkItem(
            owner: ramenPlace,
            title: "Botan Ramen & Bar",
            url: "https://example.com/saved/botan-ramen-bar",
            into: db
        )

        let report = try SecondBrainSavedPlacePreferenceLinkPreviewService(database: db)
            .preview(limit: 10)

        let acceptedRow = try #require(report.diagnostics.evidenceSamples.first {
            $0.owner == acceptedNote && $0.reasonCode == "usable_food_preference_evidence"
        })
        let acceptedSpan = try #require(acceptedRow.sourceSpan)
        #expect(acceptedSpan.sourceItemRef == acceptedNote.canonicalRef)
        #expect(acceptedSpan.sourceField == "notes.content")
        #expect(acceptedSpan.matchedText == acceptedPhrase)
        #expect(acceptedSpan.snippet.contains(acceptedPhrase))
        #expect(acceptedSpan.startOffset == acceptedContent.characterOffset(of: acceptedPhrase))
        #expect(acceptedSpan.endOffset == acceptedSpan.startOffset + acceptedPhrase.count)
        #expect(acceptedContent.substring(characterStart: acceptedSpan.startOffset, characterEnd: acceptedSpan.endOffset) == acceptedPhrase)
        #expect(acceptedSpan.selector == "char:\(acceptedSpan.startOffset)..\(acceptedSpan.endOffset)")
        #expect(acceptedSpan.sourceEvidenceRef == nil)
        #expect(acceptedSpan.syntheticSourceEvidenceRef == "synthetic_source_span:note:\(acceptedNote.ownerID):\(acceptedSpan.startOffset)-\(acceptedSpan.endOffset)")
        #expect(acceptedSpan.truthBoundary == "read_only_source_selector_not_accepted_truth")
        #expect(acceptedRow.safeVerificationCommands.contains("cider-cli item context note \(acceptedNote.ownerID) --json"))

        let rejectedRow = try #require(report.diagnostics.evidenceRejectedSamples.first {
            $0.owner == rejectedNote && $0.reasonCode == "negative_or_non_preference_food_mention"
        })
        let rejectedSpan = try #require(rejectedRow.sourceSpan)
        #expect(rejectedSpan.sourceItemRef == rejectedNote.canonicalRef)
        #expect(rejectedSpan.sourceField == "notes.content")
        #expect(rejectedSpan.matchedText == rejectedPhrase)
        #expect(rejectedSpan.snippet.contains(rejectedPhrase))
        #expect(rejectedContent.substring(characterStart: rejectedSpan.startOffset, characterEnd: rejectedSpan.endOffset) == rejectedPhrase)
        #expect(rejectedSpan.selector == "char:\(rejectedSpan.startOffset)..\(rejectedSpan.endOffset)")
        #expect(rejectedSpan.truthBoundary == "read_only_source_selector_not_accepted_truth")
        #expect(rejectedRow.safeVerificationCommands.contains("cider-cli item context note \(rejectedNote.ownerID) --json"))

        let payload = CiderCLI.savedPlacePreferenceLinkPreviewPayload(report)
        let diagnostics = try #require(payload["diagnostics"] as? [String: Any])
        let evidenceSamples = try #require(diagnostics["evidenceSamples"] as? [[String: Any]])
        let acceptedDict = try #require(evidenceSamples.first { $0["ownerRef"] as? String == acceptedNote.canonicalRef })
        let acceptedSpanDict = try #require(acceptedDict["sourceSpan"] as? [String: Any])
        #expect(acceptedSpanDict["sourceItemRef"] as? String == acceptedNote.canonicalRef)
        #expect(acceptedSpanDict["matchedText"] as? String == acceptedPhrase)
        #expect(acceptedSpanDict["selector"] as? String == "char:\(acceptedSpan.startOffset)..\(acceptedSpan.endOffset)")
        #expect((acceptedDict["safeVerificationCommands"] as? [String])?.contains("cider-cli item context note \(acceptedNote.ownerID) --json") == true)

        let rejectedSamples = try #require(diagnostics["evidenceRejectedSamples"] as? [[String: Any]])
        let rejectedDict = try #require(rejectedSamples.first { $0["ownerRef"] as? String == rejectedNote.canonicalRef })
        let rejectedSpanDict = try #require(rejectedDict["sourceSpan"] as? [String: Any])
        #expect(rejectedSpanDict["matchedText"] as? String == rejectedPhrase)
        #expect(rejectedSpanDict["truthBoundary"] as? String == "read_only_source_selector_not_accepted_truth")
    }

    private func insertNoteItem(
        owner: SecondBrainOwnerRef,
        title: String,
        content: String = "",
        into db: CiderDatabase
    ) throws {
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

        let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        noteStmt.bind(owner.ownerID, at: 1)
            .bind(content, at: 2)
        try noteStmt.step()
    }

    private func insertBookmarkItem(
        owner: SecondBrainOwnerRef,
        title: String,
        url: String,
        ocrText: String? = nil,
        into db: CiderDatabase
    ) throws {
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

        let bookmarkStmt = try db.prepare("INSERT INTO bookmarks (item_id, url, notes, ocr_text) VALUES (?, ?, '', ?);")
        bookmarkStmt.bind(owner.ownerID, at: 1)
            .bind(url, at: 2)
            .bind(ocrText, at: 3)
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

private extension String {
    func characterOffset(of needle: String) -> Int {
        guard let range = range(of: needle) else { return -1 }
        return distance(from: startIndex, to: range.lowerBound)
    }

    func substring(characterStart: Int, characterEnd: Int) -> String {
        let start = index(startIndex, offsetBy: characterStart)
        let end = index(startIndex, offsetBy: characterEnd)
        return String(self[start..<end])
    }
}
