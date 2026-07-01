import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Journal Candidate Reconciliation Tests")
@MainActor
struct SecondBrainJournalCandidateReconciliationTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-candidate-reconciliation-\(UUID().uuidString).db")
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

    @Test("dry run detects stored noisy journal graph candidates without hiding useful fresh candidates")
    func dryRunDetectsStoredNoisyJournalGraphCandidatesWithoutHidingUsefulFreshCandidates() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: "8A83CB50-4AFF-4DD0-9FDC-D95E2E2D494A")
        let rawContent = """
        - They went to the Marysville outlet mall, and Bane wanted the Nike store.
        - They went to the mall and she was buying random things; money seemed more useful than guessing a gift.
        """
        let noisy = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "the mall and she was buying random things; money seemed more useful than guessing a gift",
            sourceQuote: "- They went to the mall and she was buying random things; money seemed more useful than guessing a gift.",
            sourceKind: "journal",
            objectTypeGuesses: [.place],
            relationGuesses: [.visited],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.31,
            confidenceReason: "Historical extractor over-captured a noisy clause.",
            source: "journal_graph_candidate.v0"
        )
        let useful = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "the Marysville outlet mall",
            sourceQuote: "- They went to the Marysville outlet mall, and Bane wanted the Nike store.",
            sourceKind: "journal",
            objectTypeGuesses: [.restaurant, .place],
            relationGuesses: [.visited],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject],
            confidence: 0.74,
            confidenceReason: "Journal sentence uses a visit/location phrase.",
            source: "journal_graph_candidate.v1"
        )
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(noisy)
        try outputService.record(useful)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.candidates.map(\.candidateID) == [noisy.id])
        let candidate = try #require(report.candidates.first)
        #expect(candidate.candidateRef == "graph_candidate:\(noisy.id)")
        #expect(candidate.previousReviewState == "suggested")
        #expect(candidate.proposedReviewState == "superseded")
        #expect(candidate.reasonCodes.contains("not_emitted_by_current_extractor"))
        #expect(candidate.reasonCodes.contains("noisy_clause_span"))
        #expect(candidate.sourceRefs.contains(owner.canonicalRef))
        #expect(candidate.sourceRefs.contains("graph_candidate:\(noisy.id)"))

        let stored = try outputService.outputs(for: owner)
        #expect(stored.first { $0.id == useful.id }?.reviewState == "suggested")
        #expect(stored.first { $0.id == noisy.id }?.reviewState == "suggested")
    }

    @Test("apply supersedes selected noisy candidates without deleting provenance or accepting truth")
    func applySupersedesSelectedNoisyCandidatesWithoutDeletingProvenanceOrAcceptingTruth() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - They went to the Marysville outlet mall, and Bane wanted the Nike store.
        - They went to the mall and she was buying random things; money seemed more useful than guessing a gift.
        """
        let noisy = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "the mall and she was buying random things; money seemed more useful than guessing a gift",
            sourceQuote: "- They went to the mall and she was buying random things; money seemed more useful than guessing a gift.",
            sourceKind: "journal",
            objectTypeGuesses: [.place],
            relationGuesses: [.visited],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.31,
            confidenceReason: "Historical extractor over-captured a noisy clause.",
            source: "journal_graph_candidate.v0"
        )
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(noisy)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .apply(
                owner: owner,
                rawContent: rawContent,
                selectedCandidateIDs: [noisy.id],
                actor: "codex-test",
                reason: "Superseded by current journal extraction."
            )

        #expect(!report.readOnly)
        #expect(report.changed)
        #expect(report.appliedCandidateIDs == [noisy.id])

        let storedOutput = try outputService.output(id: noisy.id)
        let stored = try #require(storedOutput)
        #expect(stored.reviewState == "superseded")
        #expect(stored.metadata["reconciliation_state"] == "superseded")
        #expect(stored.metadata["review_boundary"] == "reviewable_candidate_not_truth")
        #expect(stored.metadata["source_owner_ref"] == owner.canonicalRef)
        #expect(stored.metadata["source_quote"] == noisy.evidence)
        #expect(stored.metadata["source_evidence_ref"]?.hasPrefix("source_evidence:") == true)
        #expect(stored.metadata["accepted_target_owner_type"] == nil)

        let visible = try outputService.outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: ["suggested", "needs_review", "deferred"]
        )
        #expect(!visible.contains { $0.id == noisy.id })

        let events = try SecondBrainReviewLifecycleService(database: db).events(candidateRef: "graph_candidate:\(noisy.id)")
        #expect(events.contains { $0.eventKind == "superseded" && $0.lifecycleState == "superseded" })
    }

    @Test("dry run diagnoses community outage spans without superseding real work life facts")
    func dryRunDiagnosesCommunityOutageSpansWithoutSupersedingRealWorkLifeFacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - Visher saw on r/Boeing that the CMS/outage left about 40 systems down during the shift.
        - Visher took PTO for Ryland's birthday and worked overtime around it.
        """
        let outage = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "r/Boeing that the CMS/outage left about 40 systems down during the shift",
            sourceQuote: "- Visher saw on r/Boeing that the CMS/outage left about 40 systems down during the shift.",
            sourceKind: "journal",
            objectTypeGuesses: [.topic],
            relationGuesses: [.mentions],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.34,
            confidenceReason: "Historical extractor over-captured a community support/outage report.",
            source: "journal_graph_candidate.v0"
        )
        let work = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "PTO for Ryland's birthday and worked overtime",
            sourceQuote: "- Visher took PTO for Ryland's birthday and worked overtime around it.",
            sourceKind: "journal",
            objectTypeGuesses: [.event],
            relationGuesses: [.mentions],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.72,
            confidenceReason: "Journal sentence records concrete PTO/overtime life context.",
            source: "journal_graph_candidate.v1"
        )
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(outage)
        try outputService.record(work)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.candidates.map(\.candidateID) == [outage.id])
        let candidate = try #require(report.candidates.first)
        #expect(candidate.reasonCodes.contains("not_emitted_by_current_extractor"))
        #expect(candidate.reasonCodes.contains("community_support_outage_span"))
        #expect(candidate.sourceRefs.contains(owner.canonicalRef))

        let stored = try outputService.outputs(for: owner)
        #expect(stored.first { $0.id == outage.id }?.reviewState == "suggested")
        #expect(stored.first { $0.id == work.id }?.reviewState == "suggested")
    }

    @Test("dry run diagnoses bare media progress spans without superseding consumed media or preferences")
    func dryRunDiagnosesBareMediaProgressSpansWithoutSupersedingConsumedMediaOrPreferences() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - Visher finished watching season 2 of the live-action Avatar: The Last Airbender on Netflix, or at least watched through seven episodes.
        - Visher did not really want to watch The Way Way Back because it seemed like a chick-flick type movie, but watched it with her and thought it was actually pretty decent.
        """
        let bareProgress = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "through seven episodes",
            sourceQuote: "- Visher finished watching season 2 of the live-action Avatar: The Last Airbender on Netflix, or at least watched through seven episodes.",
            sourceKind: "journal",
            objectTypeGuesses: [.media],
            relationGuesses: [.watched],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.36,
            confidenceReason: "Historical extractor emitted a fragment without the canonical media title.",
            source: "journal_graph_candidate.v0"
        )
        let avatar = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Avatar: The Last Airbender",
            sourceQuote: "- Visher finished watching season 2 of the live-action Avatar: The Last Airbender on Netflix, or at least watched through seven episodes.",
            sourceKind: "journal",
            objectTypeGuesses: [.show, .media],
            relationGuesses: [.watched],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject],
            confidence: 0.78,
            confidenceReason: "Journal sentence names the show and watch progress.",
            source: "journal_graph_candidate.v1"
        )
        let preference = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "- Visher did not really want to watch The Way Way Back because it seemed like a chick-flick type movie, but watched it with her and thought it was actually pretty decent.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.watched, .likes],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject],
            confidence: 0.8,
            confidenceReason: "Journal sentence names the movie and a positive reaction.",
            source: "journal_graph_candidate.v1"
        )
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(bareProgress)
        try outputService.record(avatar)
        try outputService.record(preference)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        let currentOutputs = SecondBrainJournalGraphCandidateExtractor()
            .extract(sourceOwner: owner, rawContent: rawContent)
            .outputs
            .filter { $0.kind == SecondBrainGraphCandidateContract.outputKind }
        let currentAvatar = try #require(currentOutputs.first { $0.value == "Avatar: The Last Airbender" })
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaTitle] == "Avatar: The Last Airbender")
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaType] == "show")
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaSeasonNumber] == "2")
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaEpisodeProgress] == "through 7 episodes")
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaPlatform] == "Netflix")
        #expect(currentAvatar.metadata[SecondBrainGraphCandidateContract.MetadataKey.truthBoundary] == "reviewable_candidate_not_truth")
        #expect(!currentOutputs.map(\.value).contains("through seven episodes"))

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.candidates.map(\.candidateID) == [bareProgress.id])
        let candidate = try #require(report.candidates.first)
        #expect(candidate.reasonCodes.contains("not_emitted_by_current_extractor"))
        #expect(candidate.reasonCodes.contains("bare_media_progress_span"))
        #expect(candidate.reasonCodes.contains("episode_count_span"))

        let preview = try #require(report.currentExtractionReplacementPreviews.first)
        #expect(preview.replacementForCandidateIDs == [bareProgress.id])
        #expect(preview.previewRef.hasPrefix("current_extraction_preview:"))
        #expect(preview.kind == SecondBrainGraphCandidateContract.outputKind)
        #expect(preview.value == "Avatar: The Last Airbender")
        #expect(preview.evidence.contains("through seven episodes"))
        #expect(preview.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaTitle] == "Avatar: The Last Airbender")
        #expect(preview.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaType] == "show")
        #expect(preview.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaSeasonNumber] == "2")
        #expect(preview.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaEpisodeProgress] == "through 7 episodes")
        #expect(preview.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaPlatform] == "Netflix")
        #expect(preview.truthBoundary == "reviewable_candidate_not_truth")
        #expect(!preview.acceptedAsTruth)
        #expect(preview.sourceRefs.contains(owner.canonicalRef))

        let stored = try outputService.outputs(for: owner)
        #expect(stored.first { $0.id == bareProgress.id }?.reviewState == "suggested")
        #expect(stored.first { $0.id == avatar.id }?.reviewState == "suggested")
        #expect(stored.first { $0.id == preference.id }?.reviewState == "suggested")
    }

    @Test("dry run previews bounded non-overlap replacements when metadata links stale and current candidates")
    func dryRunPreviewsBoundedNonOverlapReplacementsWhenMetadataLinksStaleAndCurrentCandidates() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - She was buying random things at the mall.
        - Money seemed more useful than guessing a gift.
        """
        var stale = SecondBrainEnrichmentOutput(
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: "She was buying random things at the mall.",
            normalizedValue: "she was buying random things at the mall.",
            label: "Memory candidate: gift preference",
            evidence: "- She was buying random things at the mall.",
            source: "memory_candidate.journal_capture.v0",
            confidence: 0.32,
            reviewState: "suggested",
            metadata: [
                "candidate_kind": "gift_preference",
                "memory_kind": "gift_preference",
                "memory_key": "money-more-useful-than-guessing-gift",
                "source_kind": "journal",
                "source_owner_ref": owner.canonicalRef,
                "source_quote": "- She was buying random things at the mall.",
                "truth_boundary": "reviewable_candidate_not_truth",
            ]
        )
        stale.metadata["candidate_ref"] = "memory_candidate:\(stale.id)"
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(stale)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.candidates.map(\.candidateID) == [stale.id])
        let candidate = try #require(report.candidates.first)
        #expect(candidate.reasonCodes.contains("not_emitted_by_current_extractor"))
        #expect(candidate.reasonCodes.contains("noisy_clause_span"))
        #expect(candidate.reasonCodes.contains("low_confidence_stored_candidate"))

        let preview = try #require(report.currentExtractionReplacementPreviews.first)
        #expect(report.currentExtractionReplacementPreviewCount == 1)
        #expect(preview.replacementForCandidateIDs == [stale.id])
        #expect(preview.kind == "memory_candidate")
        #expect(preview.value == "Money seemed more useful than guessing a gift.")
        #expect(preview.evidence == "- Money seemed more useful than guessing a gift")
        #expect(preview.metadata["memory_key"] == "money-more-useful-than-guessing-gift")
        #expect(preview.truthBoundary == "reviewable_candidate_not_truth")
        #expect(!preview.acceptedAsTruth)
        #expect(preview.sourceRefs.contains(owner.canonicalRef))

        let stored = try outputService.output(id: stale.id)
        #expect(stored?.reviewState == "suggested")
    }

    @Test("dry run fails closed for ambiguous non-overlap candidates without metadata links")
    func dryRunFailsClosedForAmbiguousNonOverlapCandidatesWithoutMetadataLinks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - She was buying random things at the mall.
        - Money seemed more useful than guessing a gift.
        - Visher took PTO for Ryland's birthday and worked overtime around it.
        """
        var stale = SecondBrainEnrichmentOutput(
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: "She was buying random things at the mall.",
            normalizedValue: "she was buying random things at the mall.",
            label: "Memory candidate: stale noisy span",
            evidence: "- She was buying random things at the mall.",
            source: "memory_candidate.journal_capture.v0",
            confidence: 0.32,
            reviewState: "suggested",
            metadata: [
                "candidate_kind": "stale_noisy_span",
                "source_kind": "journal",
                "source_owner_ref": owner.canonicalRef,
                "source_quote": "- She was buying random things at the mall.",
                "truth_boundary": "reviewable_candidate_not_truth",
            ]
        )
        stale.metadata["candidate_ref"] = "memory_candidate:\(stale.id)"
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(stale)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.candidates.map(\.candidateID) == [stale.id])
        #expect(report.currentExtractionReplacementPreviewCount == 0)
        #expect(report.currentExtractionReplacementPreviews.isEmpty)

        let stored = try outputService.output(id: stale.id)
        #expect(stored?.reviewState == "suggested")
    }
}
