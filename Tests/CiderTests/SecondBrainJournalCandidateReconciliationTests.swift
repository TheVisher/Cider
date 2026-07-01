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
}
