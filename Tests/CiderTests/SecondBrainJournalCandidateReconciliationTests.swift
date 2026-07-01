import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

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

    @Test("dry run previews no-key replacements when source quote proximity bounds the pair")
    func dryRunPreviewsNoKeyReplacementsWhenSourceQuoteProximityBoundsThePair() throws {
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
            label: "Memory candidate: stale nearby gift context",
            evidence: "- She was buying random things at the mall.",
            source: "memory_candidate.journal_capture.v0",
            confidence: 0.32,
            reviewState: "suggested",
            metadata: [
                "candidate_kind": "stale_nearby_gift_context",
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
        let preview = try #require(report.currentExtractionReplacementPreviews.first)
        #expect(report.currentExtractionReplacementPreviewCount == 1)
        #expect(preview.replacementForCandidateIDs == [stale.id])
        #expect(preview.value == "Money seemed more useful than guessing a gift.")
        #expect(preview.metadata["replacement_pairing_basis"] == "source_quote_proximity")
        #expect(preview.metadata["replacement_pairing_owner_ref"] == owner.canonicalRef)
        #expect(preview.metadata["replacement_pairing_stale_source_quote"] == "- She was buying random things at the mall.")
        #expect(preview.metadata["replacement_pairing_current_source_quote"] == "- Money seemed more useful than guessing a gift")
        #expect(preview.metadata["replacement_pairing_source_quote_distance"] == "1")
        #expect(preview.metadata["replacement_preview"] == "true")
        #expect(preview.truthBoundary == "reviewable_candidate_not_truth")
        #expect(!preview.acceptedAsTruth)

        let stored = try outputService.output(id: stale.id)
        #expect(stored?.reviewState == "suggested")
    }

    @Test("journal extraction persists source spans for graph and memory candidates")
    func journalExtractionPersistsSourceSpansForGraphAndMemoryCandidates() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - Jami loved the pineapple coconut drink.
        - Money seemed more useful than guessing a gift.
        """

        let outputs = SecondBrainJournalGraphCandidateExtractor()
            .extract(sourceOwner: owner, rawContent: rawContent)
            .outputs
        let graph = try #require(outputs.first { $0.kind == SecondBrainGraphCandidateContract.outputKind && $0.value == "pineapple coconut drink" })
        let memory = try #require(outputs.first { $0.kind == "memory_candidate" && $0.metadata["memory_key"] == "money-more-useful-than-guessing-gift" })

        for output in [graph, memory] {
            let start = try #require(output.metadata["source_span_start"].flatMap(Int.init))
            let end = try #require(output.metadata["source_span_end"].flatMap(Int.init))
            #expect(start >= 0)
            #expect(end > start)
            #expect(end <= rawContent.count)
            let lower = rawContent.index(rawContent.startIndex, offsetBy: start)
            let upper = rawContent.index(rawContent.startIndex, offsetBy: end)
            #expect(String(rawContent[lower..<upper]) == output.metadata["source_quote"])
            #expect(output.metadata["source_owner_ref"] == owner.canonicalRef)
            #expect(output.metadata["source_kind"] == "journal")
        }
    }

    @Test("dry run prefers explicit source spans for no-key replacement pairing")
    func dryRunPrefersExplicitSourceSpansForNoKeyReplacementPairing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - She was buying random things at the mall.
        - Money seemed more useful than guessing a gift.
        """
        let staleQuote = "- She was buying random things at the mall."
        let staleStart = try #require(rawContent.range(of: staleQuote)).lowerBound
        let staleSpanStart = rawContent.distance(from: rawContent.startIndex, to: staleStart)
        var stale = SecondBrainEnrichmentOutput(
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: "She was buying random things at the mall.",
            normalizedValue: "she was buying random things at the mall.",
            label: "Memory candidate: stale nearby gift context",
            evidence: staleQuote,
            source: "memory_candidate.journal_capture.v0",
            confidence: 0.32,
            reviewState: "suggested",
            metadata: [
                "candidate_kind": "stale_nearby_gift_context",
                "source_kind": "journal",
                "source_owner_ref": owner.canonicalRef,
                "source_quote": staleQuote,
                "source_span_start": "\(staleSpanStart)",
                "source_span_end": "\(staleSpanStart + staleQuote.count)",
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
        let preview = try #require(report.currentExtractionReplacementPreviews.first)
        #expect(report.currentExtractionReplacementPreviewCount == 1)
        #expect(preview.replacementForCandidateIDs == [stale.id])
        #expect(preview.value == "Money seemed more useful than guessing a gift.")
        #expect(preview.metadata["replacement_pairing_basis"] == "source_span_proximity")
        #expect(preview.metadata["replacement_pairing_owner_ref"] == owner.canonicalRef)
        #expect(preview.metadata["replacement_pairing_stale_source_quote"] == staleQuote)
        #expect(preview.metadata["replacement_pairing_current_source_quote"] == "- Money seemed more useful than guessing a gift")
        #expect(preview.metadata["replacement_pairing_stale_source_span_start"] == "\(staleSpanStart)")
        #expect(preview.metadata["replacement_pairing_stale_source_span_end"] == "\(staleSpanStart + staleQuote.count)")
        #expect(preview.metadata["replacement_pairing_current_source_span_start"] != nil)
        #expect(preview.metadata["replacement_pairing_current_source_span_end"] != nil)
        #expect(preview.metadata["replacement_pairing_source_span_line_distance"] == "1")
        #expect(preview.metadata["replacement_pairing_source_quote_distance"] == nil)
        #expect(preview.truthBoundary == "reviewable_candidate_not_truth")
        #expect(!preview.acceptedAsTruth)

        let previewDict = CiderCLI.journalCandidateReplacementPreviewToDict(preview)
        #expect(previewDict["sourceSpanStart"] as? Int != nil)
        #expect(previewDict["sourceSpanEnd"] as? Int != nil)
        #expect(previewDict["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(previewDict["acceptedAsTruth"] as? Bool == false)
    }

    @Test("dry run does not add proximity targets when an output already has an exact replacement")
    func dryRunDoesNotAddProximityTargetsWhenOutputAlreadyHasExactReplacement() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - Visher saw on r/Boeing that the CMS/outage stopped around 5 PM, meaning the outage lasted more than 24 hours.
        - Visher finished watching season 2 of the live-action Avatar: The Last Airbender on Netflix, or at least watched through seven episodes.
        """
        let outage = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "on r/Boeing that the CMS/outage stopped around 5 PM, meaning the outage lasted more than 24 hours",
            sourceQuote: "- Visher saw on r/Boeing that the CMS/outage stopped around 5 PM, meaning the outage lasted more than 24 hours.",
            sourceKind: "journal",
            objectTypeGuesses: [.topic],
            relationGuesses: [.mentions],
            safeActions: [.inspectSource, .correct, .reject, .delegateEnrichment],
            confidence: 0.34,
            confidenceReason: "Historical extractor over-captured a community support/outage report.",
            source: "journal_graph_candidate.v0"
        )
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
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(outage)
        try outputService.record(bareProgress)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .diagnose(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(Set(report.candidates.map(\.candidateID)) == Set([outage.id, bareProgress.id]))
        let avatarPreview = try #require(report.currentExtractionReplacementPreviews.first { $0.value == "Avatar: The Last Airbender" })
        #expect(avatarPreview.replacementForCandidateIDs == [bareProgress.id])
        #expect(avatarPreview.metadata["replacement_pairing_basis"] == nil)
        #expect(avatarPreview.truthBoundary == "reviewable_candidate_not_truth")
        #expect(!avatarPreview.acceptedAsTruth)
    }

    @Test("dry run fails closed for ambiguous non-overlap candidates without metadata links")
    func dryRunFailsClosedForAmbiguousNonOverlapCandidatesWithoutMetadataLinks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let rawContent = """
        - Money seemed more useful than guessing a gift.
        - She was buying random things at the mall.
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

    @Test("span audit recovers a missing graph candidate span when source quote is unique")
    func spanAuditRecoversMissingGraphCandidateSpanWhenSourceQuoteIsUnique() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceQuote = "- Visher watched Avatar: The Last Airbender on Netflix."
        let rawContent = """
        - Visher drank coffee before work.
        \(sourceQuote)
        - Visher logged a reminder about lunch.
        """
        let candidate = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Avatar: The Last Airbender",
            sourceQuote: sourceQuote,
            sourceKind: "journal",
            objectTypeGuesses: [.show, .media],
            relationGuesses: [.watched],
            confidence: 0.78,
            confidenceReason: "Pre-span stored candidate fixture.",
            source: "journal_graph_candidate.v0"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(candidate)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .auditMissingSourceSpans(owner: owner, rawContent: rawContent)

        #expect(report.readOnly)
        #expect(!report.changed)
        #expect(report.truthBoundary == "reviewable_candidate_not_truth")
        #expect(report.auditCount == 1)
        let audit = try #require(report.audits.first)
        let expected = try #require(rawContent.range(of: sourceQuote))
        #expect(audit.candidateID == candidate.id)
        #expect(audit.candidateRef == "graph_candidate:\(candidate.id)")
        #expect(audit.sourceOwnerRef == owner.canonicalRef)
        #expect(audit.sourceQuote == sourceQuote)
        #expect(audit.currentSpanState == "missing")
        #expect(audit.recoveryStatus == "recoverable")
        #expect(audit.recoveredSpanStart == rawContent.distance(from: rawContent.startIndex, to: expected.lowerBound))
        #expect(audit.recoveredSpanEnd == rawContent.distance(from: rawContent.startIndex, to: expected.upperBound))
        #expect(audit.ambiguityReason == nil)
        #expect(audit.truthBoundary == "reviewable_candidate_not_truth")
    }

    @Test("span audit fails closed when the source quote is duplicated")
    func spanAuditFailsClosedWhenSourceQuoteIsDuplicated() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceQuote = "- Visher bought a Diet Coke."
        let rawContent = """
        \(sourceQuote)
        - Visher bought sparkling water.
        \(sourceQuote)
        """
        let candidate = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Diet Coke",
            sourceQuote: sourceQuote,
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.drank],
            confidence: 0.72,
            confidenceReason: "Duplicate quote fixture.",
            source: "journal_graph_candidate.v0"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(candidate)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .auditMissingSourceSpans(owner: owner, rawContent: rawContent)

        let audit = try #require(report.audits.first)
        #expect(audit.currentSpanState == "missing")
        #expect(audit.recoveryStatus == "ambiguous")
        #expect(audit.recoveredSpanStart == nil)
        #expect(audit.recoveredSpanEnd == nil)
        #expect(audit.ambiguityReason == "source_quote_occurs_2_times")
        #expect(report.safeNextCommands.contains("cider-cli item graph-candidate \(candidate.id) --json"))
    }

    @Test("span audit leaves graph candidates with existing valid spans unchanged")
    func spanAuditLeavesGraphCandidatesWithExistingValidSpansUnchanged() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceQuote = "- Visher liked the sea salt foam black tea."
        let rawContent = """
        - Visher ordered dumplings.
        \(sourceQuote)
        """
        var candidate = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "sea salt foam black tea",
            sourceQuote: sourceQuote,
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            confidence: 0.74,
            confidenceReason: "Already-spanned fixture.",
            source: "journal_graph_candidate.v1"
        )
        let expected = try #require(rawContent.range(of: sourceQuote))
        candidate.metadata["source_span_start"] = "\(rawContent.distance(from: rawContent.startIndex, to: expected.lowerBound))"
        candidate.metadata["source_span_end"] = "\(rawContent.distance(from: rawContent.startIndex, to: expected.upperBound))"
        try SecondBrainEnrichmentOutputService(database: db).record(candidate)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .auditMissingSourceSpans(owner: owner, rawContent: rawContent)

        let audit = try #require(report.audits.first)
        #expect(audit.currentSpanState == "present")
        #expect(audit.recoveryStatus == "unchanged")
        #expect(audit.recoveredSpanStart == nil)
        #expect(audit.recoveredSpanEnd == nil)
        #expect(audit.currentSpanStart == rawContent.distance(from: rawContent.startIndex, to: expected.lowerBound))
        #expect(audit.currentSpanEnd == rawContent.distance(from: rawContent.startIndex, to: expected.upperBound))
        #expect(!report.changed)
    }

    @Test("span audit CLI dictionary keeps candidates reviewable and exposes safe commands")
    func spanAuditCLIDictionaryKeepsCandidatesReviewableAndExposesSafeCommands() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let audit = SecondBrainJournalCandidateSourceSpanAudit(
            candidateID: "candidate-1",
            candidateRef: "graph_candidate:candidate-1",
            sourceOwnerRef: owner.canonicalRef,
            sourceQuote: "- Visher watched Avatar.",
            currentSpanState: "missing",
            currentSpanStart: nil,
            currentSpanEnd: nil,
            recoveredSpanStart: 12,
            recoveredSpanEnd: 36,
            recoveryStatus: "recoverable",
            ambiguityReason: nil,
            readOnly: true,
            changed: false,
            truthBoundary: "reviewable_candidate_not_truth",
            safeNextCommands: ["cider-cli item graph-candidate candidate-1 --json"]
        )

        let dict = CiderCLI.journalCandidateSourceSpanAuditToDict(audit)

        #expect(dict["candidateID"] as? String == "candidate-1")
        #expect(dict["candidateRef"] as? String == "graph_candidate:candidate-1")
        #expect(dict["sourceOwnerRef"] as? String == owner.canonicalRef)
        #expect(dict["sourceQuote"] as? String == "- Visher watched Avatar.")
        #expect(dict["currentSpanState"] as? String == "missing")
        #expect(dict["recoveredSpanStart"] as? Int == 12)
        #expect(dict["recoveredSpanEnd"] as? Int == 36)
        #expect(dict["recoveryStatus"] as? String == "recoverable")
        #expect(dict["readOnly"] as? Bool == true)
        #expect(dict["changed"] as? Bool == false)
        #expect(dict["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect((dict["safeNextCommands"] as? [String]) == ["cider-cli item graph-candidate candidate-1 --json"])
    }

    @Test("source span backfill applies only selected recoverable candidates without accepting truth")
    func sourceSpanBackfillAppliesOnlySelectedRecoverableCandidatesWithoutAcceptingTruth() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let selectedQuote = "- Visher finished Avatar season 2."
        let untouchedQuote = "- Visher liked the sea salt foam black tea."
        let rawContent = """
        \(selectedQuote)
        \(untouchedQuote)
        """
        var selected = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Avatar season 2",
            sourceQuote: selectedQuote,
            sourceKind: "journal",
            objectTypeGuesses: [.media],
            relationGuesses: [.watched],
            confidence: 0.72,
            confidenceReason: "Legacy pre-span fixture.",
            source: "journal_graph_candidate.v0"
        )
        selected.metadata.removeValue(forKey: "source_span_start")
        selected.metadata.removeValue(forKey: "source_span_end")
        selected.metadata["truth_boundary"] = "reviewable_candidate_not_truth"
        selected.metadata["accepted_as_truth"] = "false"
        var untouched = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "sea salt foam black tea",
            sourceQuote: untouchedQuote,
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            confidence: 0.74,
            confidenceReason: "Legacy pre-span fixture.",
            source: "journal_graph_candidate.v0.untouched"
        )
        untouched.metadata.removeValue(forKey: "source_span_start")
        untouched.metadata.removeValue(forKey: "source_span_end")
        untouched.metadata["truth_boundary"] = "reviewable_candidate_not_truth"
        untouched.metadata["accepted_as_truth"] = "false"

        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(selected)
        try outputService.record(untouched)

        let expected = try #require(rawContent.range(of: selectedQuote))
        let expectedStart = rawContent.distance(from: rawContent.startIndex, to: expected.lowerBound)
        let expectedEnd = rawContent.distance(from: rawContent.startIndex, to: expected.upperBound)

        let report = try SecondBrainJournalCandidateReconciliationService(database: db)
            .applyMissingSourceSpans(
                owner: owner,
                rawContent: rawContent,
                selectedCandidateRefs: [selected.id],
                actor: "codex-test",
                reason: "Approved source span backfill test."
            )

        #expect(!report.readOnly)
        #expect(report.changed)
        #expect(report.selectedCandidateRefs == [selected.id])
        #expect(report.changedCandidateIDs == [selected.id])
        #expect(report.truthBoundary == "reviewable_candidate_not_truth")
        let applied = try #require(report.candidates.first)
        #expect(applied.candidateID == selected.id)
        #expect(applied.beforeSpanStart == nil)
        #expect(applied.beforeSpanEnd == nil)
        #expect(applied.afterSpanStart == expectedStart)
        #expect(applied.afterSpanEnd == expectedEnd)
        #expect(applied.status == "applied")
        #expect(applied.changed)

        let storedSelected = try #require(try outputService.output(id: selected.id))
        #expect(storedSelected.metadata["source_span_start"] == "\(expectedStart)")
        #expect(storedSelected.metadata["source_span_end"] == "\(expectedEnd)")
        #expect(storedSelected.reviewState == "suggested")
        #expect(storedSelected.metadata["truth_boundary"] == "reviewable_candidate_not_truth")
        #expect(storedSelected.metadata["accepted_as_truth"] == "false")

        let evidenceRecord = try #require(try SecondBrainSourceEvidenceService(database: db)
            .record(derivedOwner: SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: selected.id)))
        #expect(evidenceRecord.spanStart == expectedStart)
        #expect(evidenceRecord.spanEnd == expectedEnd)

        let storedUntouched = try #require(try outputService.output(id: untouched.id))
        #expect(storedUntouched.metadata["source_span_start"] == nil)
        #expect(storedUntouched.metadata["source_span_end"] == nil)
    }

    @Test("source span backfill fails closed when selected quote is ambiguous")
    func sourceSpanBackfillFailsClosedWhenSelectedQuoteIsAmbiguous() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let quote = "- Visher watched Avatar."
        let rawContent = """
        \(quote)
        \(quote)
        """
        var candidate = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "Avatar",
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: [.media],
            relationGuesses: [.watched],
            source: "journal_graph_candidate.v0"
        )
        candidate.metadata.removeValue(forKey: "source_span_start")
        candidate.metadata.removeValue(forKey: "source_span_end")
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(candidate)

        #expect(throws: SecondBrainJournalCandidateReconciliationService.SourceSpanBackfillError.selectedCandidateNotRecoverable(candidate.id, "ambiguous")) {
            _ = try SecondBrainJournalCandidateReconciliationService(database: db)
                .applyMissingSourceSpans(
                    owner: owner,
                    rawContent: rawContent,
                    selectedCandidateRefs: [candidate.id],
                    actor: "codex-test",
                    reason: nil
                )
        }

        let stored = try #require(try outputService.output(id: candidate.id))
        #expect(stored.metadata["source_span_start"] == nil)
        #expect(stored.metadata["source_span_end"] == nil)
    }

    @Test("source span backfill leaves already spanned candidates unchanged and idempotent")
    func sourceSpanBackfillLeavesAlreadySpannedCandidatesUnchangedAndIdempotent() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let quote = "- Visher liked the sea salt foam black tea."
        let rawContent = quote
        let range = try #require(rawContent.range(of: quote))
        let start = rawContent.distance(from: rawContent.startIndex, to: range.lowerBound)
        let end = rawContent.distance(from: rawContent.startIndex, to: range.upperBound)
        var candidate = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "sea salt foam black tea",
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: [.drink],
            relationGuesses: [.likesDrink],
            source: "journal_graph_candidate.v1"
        )
        candidate.metadata["source_span_start"] = "\(start)"
        candidate.metadata["source_span_end"] = "\(end)"
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        try outputService.record(candidate)

        let first = try SecondBrainJournalCandidateReconciliationService(database: db)
            .applyMissingSourceSpans(
                owner: owner,
                rawContent: rawContent,
                selectedCandidateRefs: [candidate.id],
                actor: "codex-test",
                reason: nil
            )
        let second = try SecondBrainJournalCandidateReconciliationService(database: db)
            .applyMissingSourceSpans(
                owner: owner,
                rawContent: rawContent,
                selectedCandidateRefs: [candidate.id],
                actor: "codex-test",
                reason: nil
            )

        #expect(!first.readOnly)
        #expect(!first.changed)
        #expect(first.candidates.first?.status == "unchanged")
        #expect(first.candidates.first?.beforeSpanStart == start)
        #expect(first.candidates.first?.afterSpanStart == start)
        #expect(!second.changed)
        let stored = try #require(try outputService.output(id: candidate.id))
        #expect(stored.metadata["source_span_start"] == "\(start)")
        #expect(stored.metadata["source_span_end"] == "\(end)")
    }

    @Test("source span backfill CLI dictionary exposes provenance receipt inputs")
    func sourceSpanBackfillCLIDictionaryExposesProvenanceReceiptInputs() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let result = SecondBrainJournalCandidateSourceSpanBackfillCandidate(
            candidateID: "candidate-1",
            candidateRef: "graph_candidate:candidate-1",
            sourceOwnerRef: owner.canonicalRef,
            sourceQuote: "- Visher watched Avatar.",
            status: "applied",
            beforeSpanStart: nil,
            beforeSpanEnd: nil,
            afterSpanStart: 12,
            afterSpanEnd: 36,
            recoveryStatus: "recoverable",
            ambiguityReason: nil,
            sourceEvidenceRef: "source_evidence:evidence-1",
            readOnly: false,
            changed: true,
            truthBoundary: "reviewable_candidate_not_truth",
            safeNextCommands: ["cider-cli item graph-candidate candidate-1 --json"]
        )

        let dict = CiderCLI.journalCandidateSourceSpanBackfillCandidateToDict(result)

        #expect(dict["candidateID"] as? String == "candidate-1")
        #expect(dict["candidateRef"] as? String == "graph_candidate:candidate-1")
        #expect(dict["status"] as? String == "applied")
        #expect(dict["afterSpanStart"] as? Int == 12)
        #expect(dict["afterSpanEnd"] as? Int == 36)
        #expect(dict["sourceEvidenceRef"] as? String == "source_evidence:evidence-1")
        #expect(dict["readOnly"] as? Bool == false)
        #expect(dict["changed"] as? Bool == true)
        #expect(dict["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect((dict["safeNextCommands"] as? [String]) == ["cider-cli item graph-candidate candidate-1 --json"])
    }
}
