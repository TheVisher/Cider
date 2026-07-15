import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import Cider

@Suite("Journal Intelligence Daily Receipt Tests")
@MainActor
struct JournalIntelligenceDailyReceiptTests {
    @Test("representative text and voice corpus exercises production extraction guards")
    func corpusExercisesProductionExtractionGuards() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let morning = JournalIntelligenceCorpus.captures[0]
        let correction = JournalIntelligenceCorpus.captures[2]

        let morningOutputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: morning.text,
            date: JournalIntelligenceCorpus.date,
            time: morning.time
        ).outputs
        #expect(morningOutputs.contains { $0.value == "Discovery Park" })
        #expect(morningOutputs.contains { $0.value == "Arrival" })
        #expect(morningOutputs.contains { $0.value.localizedCaseInsensitiveContains("cedar loop hike") })

        let correctionOutputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: correction.text,
            date: JournalIntelligenceCorpus.date,
            time: correction.time
        ).outputs
        #expect(!correctionOutputs.contains { $0.value.lowercased() == "it" })
        #expect(!correctionOutputs.contains { $0.value.localizedCaseInsensitiveContains("Red Barn") })
    }

    @Test("production extractor fails closed for ambiguous negated corrected and vague intent wording")
    func productionExtractorFailsClosedForGuardWording() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let outputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: JournalIntelligenceCorpus.precisionGuardText,
            date: JournalIntelligenceCorpus.date,
            time: "20:15"
        ).outputs

        let guardedKinds = Set([
            "relationship_event",
            "commitment",
            "task_intent",
            "trip_plan",
            "artifact_intent",
            "durable_memory",
        ])
        #expect(outputs.filter { output in
            guard output.kind == "memory_candidate" else { return false }
            let kind = output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? ""
            return guardedKinds.contains(kind)
        }.isEmpty)
    }

    @Test("daily receipt groups only precise active proposals with complete capture provenance")
    func dailyReceiptGroupsOnlyPreciseActiveProposals() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let service = JournalIntelligenceDailyReceiptService(database: fixture.database)
        let first = try service.receipt(date: JournalIntelligenceCorpus.date)
        let second = try service.receipt(date: JournalIntelligenceCorpus.date)

        #expect(first == second)
        #expect(first.readOnly)
        #expect(!first.changed)
        #expect(first.proposalCount == 9)
        #expect(first.statement == "Cider found 9 things worth reviewing.")
        #expect(first.groups.map(\.category) == JournalIntelligenceCategory.allCases)
        #expect(first.groups.allSatisfy { $0.proposals.count == 1 })
        #expect(first.suppressedCount == 5)
        #expect(first.reviewedCount == 2)
        #expect(Set(first.reviewedGroups.flatMap(\.proposals).map(\.reviewState)) == ["accepted", "rejected"])

        let proposals = first.groups.flatMap(\.proposals)
        #expect(Set(proposals.map(\.category)) == Set(JournalIntelligenceCategory.allCases))
        #expect(proposals.allSatisfy { $0.journalOwner.ref == "note:\(fixture.noteID.uuidString)" })
        #expect(proposals.allSatisfy { !$0.captureEvent.id.isEmpty && $0.captureEvent.ref.hasPrefix("capture_event:") })
        #expect(proposals.allSatisfy { !$0.section.id.isEmpty && $0.section.timestamp24Hour == $0.captureEvent.journalTime })
        #expect(proposals.allSatisfy { !$0.source.quote.isEmpty && $0.source.spanEnd > $0.source.spanStart })
        #expect(proposals.allSatisfy { $0.source.coordinateSpace == "capture_event.source_text" })
        #expect(proposals.allSatisfy { $0.confidence >= 0.70 && !$0.confidenceReason.isEmpty })
        #expect(proposals.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(proposals.contains { $0.category == .tasks && $0.proposalState == "deferred" })

        let reasonCodes = Set(first.suppressions.flatMap(\.reasonCodes))
        #expect(reasonCodes.contains("low_confidence"))
        #expect(reasonCodes.contains("low_quality_candidate"))
        #expect(reasonCodes.contains("corrected_later_in_capture"))
        #expect(reasonCodes.contains("duplicate_within_day"))
        #expect(reasonCodes.contains("missing_capture_event_provenance"))
    }

    @Test("cross-time reconciliation classifies canonical matches and fails closed on ambiguity")
    func crossTimeReconciliationClassifiesCanonicalMatchesAndAmbiguity() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try seedCanonicalReconciliationRecords(in: fixture.database)

        let service = JournalIntelligenceDailyReceiptService(database: fixture.database)
        let receipt = try service.receipt(date: JournalIntelligenceCorpus.date)
        let proposals = receipt.groups.flatMap(\.proposals)
        let byCategory = Dictionary(uniqueKeysWithValues: proposals.map { ($0.category, $0) })
        let reconciliationMatches = proposals.compactMap(\.crossTimeReconciliation).flatMap(\.likelyMatches)
        #expect(reconciliationMatches.allSatisfy {
            !$0.canonicalRef.isEmpty
                && !$0.canonicalKind.isEmpty
                && !$0.canonicalLabel.isEmpty
                && (0...1).contains($0.confidence)
                && !$0.reasonCodes.isEmpty
                && !$0.evidence.isEmpty
        })
        let supported = proposals.filter { ![JournalIntelligenceCategory.activities, .commitments].contains($0.category) }
        #expect(supported.allSatisfy { proposal in
            guard let reconciliation = proposal.crossTimeReconciliation else { return false }
            return !reconciliation.canonicalFamilyScans.isEmpty
                && reconciliation.canonicalFamilyScans.allSatisfy { $0.complete && !$0.truncated }
        })

        let people = try #require(byCategory[.people]?.crossTimeReconciliation)
        #expect(people.status == .matched)
        #expect(people.classification == .newUpdate)
        #expect(people.likelyMatches.contains { $0.canonicalRef == "contact:contact-maya" && $0.canonicalKind == "person" })
        #expect(people.likelyMatches.count <= people.maxLikelyMatches)

        let places = try #require(byCategory[.places]?.crossTimeReconciliation)
        #expect(places.status == .noMatch)
        #expect(places.classification == .genuinelyNew)
        #expect(places.likelyMatches.isEmpty)

        let tasks = try #require(byCategory[.tasks]?.crossTimeReconciliation)
        #expect(tasks.classification == .repeated)
        #expect(tasks.likelyMatches.contains { $0.canonicalRef == "todo:todo-signed-permit" })

        let media = try #require(byCategory[.artifactsMedia]?.crossTimeReconciliation)
        #expect(media.classification == .newUpdate)
        #expect(media.likelyMatches.contains { $0.canonicalRef == "media_item:arrival" })

        let trip = try #require(byCategory[.tripPlans]?.crossTimeReconciliation)
        #expect(trip.classification == .newUpdate)
        #expect(trip.likelyMatches.contains { $0.canonicalRef == "accepted_memory_fact:accepted-trip-kyoto" })

        let preference = try #require(byCategory[.preferences]?.crossTimeReconciliation)
        #expect(preference.classification == .correctionOrConflict)
        #expect(preference.likelyMatches.contains { $0.canonicalRef == "graph_object:cedar-loop-hike" })

        let memory = try #require(byCategory[.durableMemory]?.crossTimeReconciliation)
        #expect(memory.classification == .repeated)
        #expect(memory.likelyMatches.contains { $0.canonicalRef == "accepted_memory_fact:accepted-hiking-mood" })

        for category in [JournalIntelligenceCategory.activities, .commitments] {
            let unsupported = try #require(byCategory[category]?.crossTimeReconciliation)
            #expect(unsupported.status == .unsupported)
            #expect(unsupported.classification == nil)
            #expect(unsupported.likelyMatches.isEmpty)
            #expect(unsupported.truthBoundary == "reviewable_candidate_not_truth")
        }

        try insertContact(id: "contact-maya-ambiguous", title: "Maya", into: fixture.database)
        _ = try SecondBrainOwnerLabelIndexService(database: fixture.database).refreshContact(ownerID: "contact-maya-ambiguous")
        let ambiguousReceipt = try service.receipt(date: JournalIntelligenceCorpus.date)
        let ambiguousPeople = try #require(
            ambiguousReceipt.groups.first { $0.category == .people }?.proposals.first?.crossTimeReconciliation
        )
        #expect(ambiguousPeople.status == .ambiguous)
        #expect(ambiguousPeople.classification == nil)
        #expect(ambiguousPeople.reasonCodes.contains("multiple_exact_canonical_identities"))
        #expect(ambiguousPeople.likelyMatches.count == 2)
        #expect(ambiguousPeople.likelyMatches.count <= ambiguousPeople.maxLikelyMatches)
    }

    @Test("cross-time reconciliation withholds genuinely new when a relevant canonical scan is truncated")
    func crossTimeReconciliationWithholdsGenuinelyNewWhenRelevantScanIsTruncated() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let labels = SecondBrainOwnerLabelIndexService(database: fixture.database)
        for index in 0..<800 {
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: String(format: "place-%04d", index)),
                ownerKind: "place",
                canonicalLabel: "Unrelated place \(index)",
                aliases: [],
                sourceRefs: ["place:filler-\(index)"],
                labelSource: "test.truncated_snapshot",
                confidence: 1
            )
        }
        _ = try labels.upsertLabel(
            owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "place-zzzz-discovery-park"),
            ownerKind: "place",
            canonicalLabel: "Discovery Park",
            aliases: [],
            sourceRefs: ["place:place-zzzz-discovery-park"],
            labelSource: "test.truncated_snapshot",
            confidence: 1
        )
        let outputService = SecondBrainEnrichmentOutputService(database: fixture.database)
        let fillerOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: "canonical-scan-fillers")
        for index in 0...500 {
            try outputService.record(acceptedMemory(
                id: String(format: "accepted-scan-filler-%04d", index),
                owner: fillerOwner,
                value: "Unrelated accepted memory \(index)",
                kind: "scan_filler"
            ))
        }

        let receipt = try JournalIntelligenceDailyReceiptService(database: fixture.database)
            .receipt(date: JournalIntelligenceCorpus.date)
        let proposals = receipt.groups.flatMap(\.proposals)
        let byCategory = Dictionary(uniqueKeysWithValues: proposals.map { ($0.category, $0) })
        let reconciliation = try #require(byCategory[.places]?.crossTimeReconciliation)

        #expect(reconciliation.status.rawValue == "classification_withheld")
        #expect(reconciliation.classification == nil)
        #expect(reconciliation.likelyMatches.isEmpty)
        #expect(reconciliation.reasonCodes.contains("canonical_scan_truncated"))
        #expect(reconciliation.reasonCodes.contains("classification_withheld"))
        #expect(!reconciliation.reasonCodes.contains("no_exact_place_identity"))
        let labelScan = try #require(reconciliation.canonicalFamilyScans.first { $0.family == "owner_labels" })
        #expect(labelScan.limit == 800)
        #expect(labelScan.loadedCount == 800)
        #expect(!labelScan.complete)
        #expect(labelScan.truncated)

        let expectedTruncatedFamilies: [JournalIntelligenceCategory: Set<String>] = [
            .people: ["owner_labels", "accepted_memory_facts"],
            .places: ["owner_labels"],
            .preferences: ["accepted_memory_facts"],
            .tasks: ["accepted_memory_facts"],
            .artifactsMedia: ["owner_labels", "accepted_memory_facts"],
            .tripPlans: ["owner_labels", "accepted_memory_facts"],
            .durableMemory: ["accepted_memory_facts"],
        ]
        for (category, expectedFamilies) in expectedTruncatedFamilies {
            let result = try #require(byCategory[category]?.crossTimeReconciliation)
            #expect(result.status == .classificationWithheld)
            #expect(result.classification == nil)
            #expect(result.reasonCodes.contains("canonical_scan_truncated"))
            #expect(Set(result.canonicalFamilyScans.filter(\.truncated).map(\.family)) == expectedFamilies)
        }
        for category in [JournalIntelligenceCategory.activities, .commitments] {
            let unsupported = try #require(byCategory[category]?.crossTimeReconciliation)
            #expect(unsupported.status == .unsupported)
            #expect(unsupported.classification == nil)
        }
    }

    @Test("Journal day review composes the production receipt into friendly source-backed groups")
    func journalDayReviewComposesProductionReceipt() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        try seedCanonicalReconciliationRecords(in: fixture.database)

        let receipt = try JournalIntelligenceDailyReceiptService(database: fixture.database)
            .receipt(date: JournalIntelligenceCorpus.date)
        let note = Note(
            id: fixture.noteID,
            title: "Daily Journal \(JournalIntelligenceCorpus.date)",
            content: JournalIntelligenceCorpus.journalMarkdown,
            createdAt: Date(timeIntervalSince1970: 1_784_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_784_000_000),
            relativePath: "Inbox/Notes/Daily Journal \(JournalIntelligenceCorpus.date).md"
        )
        let day = try #require(JournalLibraryReadModel.build(from: [note]).defaultDay)

        let model = JournalIntelligenceDayReviewModel.make(receipt: receipt, day: day)

        #expect(model.statement == "Cider found 9 things worth reviewing.")
        #expect(model.health == .ready)
        #expect(model.truthBoundary == "reviewable_candidate_not_truth")
        #expect(model.truthBoundaryCopy.localizedCaseInsensitiveContains("not accepted Cider truth"))
        #expect(model.groups.map(\.category) == JournalIntelligenceCategory.allCases)
        #expect(model.groups.map(\.label) == [
            "People updates", "Places", "Activities", "Preferences", "Commitments",
            "Tasks", "Artifacts & media", "Trip plans", "Memories",
        ])

        let proposals = model.groups.flatMap(\.proposals)
        #expect(proposals.count == 9)
        #expect(Set(proposals.map(\.candidateRef)).count == proposals.count)
        #expect(proposals.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(proposals.allSatisfy {
            $0.statusLabel == "Suggestion, not accepted truth"
                || $0.statusLabel == "Deferred suggestion, not accepted truth"
        })
        #expect(proposals.allSatisfy { !$0.source.quote.isEmpty })
        #expect(proposals.allSatisfy { $0.source.spanEnd > $0.source.spanStart })
        #expect(proposals.allSatisfy { $0.source.coordinateSpace == "capture_event.source_text" })
        #expect(proposals.allSatisfy { $0.sourceNavigation.captureCardID == $0.sectionID })
        #expect(proposals.allSatisfy { $0.sourceNavigation.precision == .exactCaptureMoment })
        #expect(proposals.contains { $0.source.typeLabel == "Text capture" && $0.source.channelLabel == "Cider CLI text" })
        #expect(proposals.contains { $0.source.typeLabel == "Voice transcript" && $0.source.channelLabel == "Voice Transcript" })

        let reconciliationLabels = Set(proposals.map(\.reconciliation.label))
        #expect(reconciliationLabels.contains("Likely repeated mention"))
        #expect(reconciliationLabels.contains("Likely new update"))
        #expect(reconciliationLabels.contains("Possible correction or conflict"))
        #expect(reconciliationLabels.contains("No likely existing match"))
        #expect(reconciliationLabels.contains("Not compared yet"))
        #expect(proposals.allSatisfy { !$0.reconciliation.explanation.isEmpty })

        var suppressedReceipt = receipt
        suppressedReceipt.groups = []
        suppressedReceipt.proposalCount = 0
        #expect(JournalIntelligenceDayReviewModel.make(receipt: suppressedReceipt, day: day).health == .suppressed)

        var emptyReceipt = suppressedReceipt
        emptyReceipt.suppressedCount = 0
        emptyReceipt.suppressions = []
        #expect(JournalIntelligenceDayReviewModel.make(receipt: emptyReceipt, day: day).health == .empty)

        var unavailableReceipt = receipt
        unavailableReceipt.journalOwners = []
        #expect(JournalIntelligenceDayReviewModel.make(receipt: unavailableReceipt, day: day).health == .unavailable)

        var staleReceipt = receipt
        staleReceipt.dataAsOf = .distantPast
        let staleModel = JournalIntelligenceDayReviewModel.make(receipt: staleReceipt, day: day)
        #expect(staleModel.health == .stale)
        #expect(staleModel.groups.flatMap(\.proposals).contains { $0.reconciliation.label == "Novelty not confirmed" })

        var partialReceipt = receipt
        let partialIndex = try #require(partialReceipt.groups.firstIndex { $0.category == .places })
        partialReceipt.groups[partialIndex].proposals[0].crossTimeReconciliation = reconciliation(
            status: .classificationWithheld,
            classification: nil,
            truncated: true
        )
        let partialModel = JournalIntelligenceDayReviewModel.make(receipt: partialReceipt, day: day)
        #expect(partialModel.health == .partial)
        #expect(partialModel.groups.flatMap(\.proposals).contains { $0.reconciliation.label == "Comparison incomplete" })

        let legacyNote = Note(
            id: UUID(),
            title: "Daily Journal \(JournalIntelligenceCorpus.date)",
            content: "Legacy source note",
            createdAt: note.createdAt.addingTimeInterval(1),
            modifiedAt: note.modifiedAt.addingTimeInterval(1),
            relativePath: "Inbox/Notes/Legacy source.md"
        )
        let aggregateDay = try #require(JournalLibraryReadModel.build(from: [note, legacyNote]).defaultDay)
        let aggregateModel = JournalIntelligenceDayReviewModel.make(receipt: receipt, day: aggregateDay)
        #expect(aggregateModel.groups.flatMap(\.proposals).allSatisfy {
            $0.sourceNavigation.precision == .sourceEntry
                && $0.sourceNavigation.boundaryCopy.localizedCaseInsensitiveContains("legacy")
        })

        var evidenceOnlyReceipt = receipt
        for groupIndex in evidenceOnlyReceipt.groups.indices {
            for proposalIndex in evidenceOnlyReceipt.groups[groupIndex].proposals.indices {
                evidenceOnlyReceipt.groups[groupIndex].proposals[proposalIndex].journalOwner.id = "missing-owner"
            }
        }
        let evidenceOnlyModel = JournalIntelligenceDayReviewModel.make(receipt: evidenceOnlyReceipt, day: day)
        #expect(evidenceOnlyModel.groups.flatMap(\.proposals).allSatisfy {
            $0.sourceNavigation.precision == .evidenceOnly
                && $0.sourceNavigation.captureCardID == nil
                && $0.sourceNavigation.boundaryCopy.localizedCaseInsensitiveContains("not available")
        })
    }

    @Test("Journal review audits every receipt category against truthful canonical candidate actions")
    func journalReviewAuditsEveryReceiptCategoryAgainstCanonicalActions() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let note = Note(
            id: fixture.noteID,
            title: "Daily Journal \(JournalIntelligenceCorpus.date)",
            content: JournalIntelligenceCorpus.journalMarkdown,
            createdAt: Date(timeIntervalSince1970: 1_784_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_784_000_000),
            relativePath: "Inbox/Notes/Daily Journal \(JournalIntelligenceCorpus.date).md"
        )
        let day = try #require(JournalLibraryReadModel.build(from: [note]).defaultDay)
        let model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let proposals = model.groups.flatMap(\.proposals)

        #expect(Set(proposals.map(\.category)) == Set(JournalIntelligenceCategory.allCases))
        #expect(proposals.allSatisfy { proposal in
            Set(proposal.actions.descriptors.map(\.action)) == Set(JournalIntelligenceReviewAction.allCases)
        })

        for proposal in proposals {
            let approve = try #require(proposal.actions.descriptor(for: .approve))
            let correct = try #require(proposal.actions.descriptor(for: .correct))
            let reject = try #require(proposal.actions.descriptor(for: .reject))
            let deferAction = try #require(proposal.actions.descriptor(for: .defer))
            #expect(reject.availability == .available)
            #expect(deferAction.availability == (proposal.reviewState == "deferred" ? .alreadyReviewed : .available))

            switch proposal.family {
            case "memory_candidate":
                #expect(approve.availability == .available)
                #expect(approve.preview.localizedCaseInsensitiveContains("memory"))
                #expect(approve.preview.localizedCaseInsensitiveContains("not create a task"))
                #expect(correct.availability == .requiresCorrection)
            case "graph_candidate":
                #expect(approve.availability == .requiresTarget)
                #expect(!approve.targetOptions.isEmpty)
                #expect(approve.guidance.localizedCaseInsensitiveContains("choose"))
                #expect(correct.availability == .requiresTarget)
                #expect(correct.preview.localizedCaseInsensitiveContains("does not approve"))
            default:
                Issue.record("Receipt emitted unsupported family \(proposal.family)")
            }
        }

        let unsupported = JournalIntelligenceReviewActionSet.unsupported(
            family: "future_candidate",
            reviewState: "suggested",
            guidance: "This suggestion family does not have a canonical review service yet."
        )
        #expect(unsupported.descriptors.allSatisfy { $0.availability == .unavailable })
        #expect(unsupported.descriptors.allSatisfy { $0.guidance.localizedCaseInsensitiveContains("does not have") })
    }

    @Test("Journal review mutations are source preserving fail closed and idempotent in disposable data")
    func journalReviewMutationsAreSourcePreservingFailClosedAndIdempotent() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-review-source-\(UUID().uuidString).md")
        try JournalIntelligenceCorpus.journalMarkdown.write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let note = Note(
            id: fixture.noteID,
            title: "Daily Journal \(JournalIntelligenceCorpus.date)",
            content: JournalIntelligenceCorpus.journalMarkdown,
            createdAt: Date(timeIntervalSince1970: 1_784_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_784_000_000),
            relativePath: sourceURL.path
        )
        let day = try #require(JournalLibraryReadModel.build(from: [note]).defaultDay)
        let sourceHashBefore = sha256(try Data(contentsOf: sourceURL))
        let captureSourceHashesBefore = try captureEventSourceHashes(in: fixture.database)
        let allTablesBefore = try allTableFingerprints(in: fixture.database)
        let immutableTablesBefore = try tableFingerprints(
            ["items", "notes", "capture_events", "capture_attachments", "todos", "projects", "bookmarks", "contacts", "vault_files"],
            in: fixture.database
        )

        let actionService = JournalIntelligenceReviewActionService(database: fixture.database)
        var model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        var actionTableChanges: [String: Set<String>] = [:]
        var tablesBeforeAction = allTablesBefore

        let memoryApprove = try #require(model.proposal(candidateRef: "memory_candidate:people-maya"))
        let memoryApproveRequest = JournalIntelligenceReviewActionRequest(
            proposal: memoryApprove,
            action: .approve
        )
        let approvedMemory = try actionService.perform(memoryApproveRequest, actor: "journal-review-test")
        #expect(approvedMemory.changed)
        #expect(approvedMemory.reviewState == "accepted")
        #expect(approvedMemory.truthBoundary == "accepted_memory_candidate")
        var tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["memory_approve"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction

        let approvedCounts = try mutationCounts(in: fixture.database)
        let approvedMemoryReplay = try actionService.perform(memoryApproveRequest, actor: "journal-review-test")
        #expect(!approvedMemoryReplay.changed)
        #expect(approvedMemoryReplay.actionReceiptID == approvedMemory.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == approvedCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let reviewedMemory = try #require(model.reviewedProposal(candidateRef: memoryApprove.candidateRef))
        #expect(reviewedMemory.reviewState == "accepted")
        #expect(reviewedMemory.source == memoryApprove.source)
        #expect(reviewedMemory.statusLabel.localizedCaseInsensitiveContains("approved"))
        #expect(reviewedMemory.actions.descriptors.allSatisfy { $0.availability == .alreadyReviewed })

        let staleMemory = try #require(model.proposal(candidateRef: "memory_candidate:commitment-map"))
        var staleRequest = JournalIntelligenceReviewActionRequest(
            proposal: staleMemory,
            action: .correct,
            correctedValue: "Bring Maya the corrected trail map tomorrow."
        )
        staleRequest.expectedUpdatedAt = .distantPast
        let beforeStale = try mutationCounts(in: fixture.database)
        #expect(throws: JournalIntelligenceReviewActionError.self) {
            _ = try actionService.perform(staleRequest, actor: "journal-review-test")
        }
        #expect(try mutationCounts(in: fixture.database) == beforeStale)

        let correctionRequest = JournalIntelligenceReviewActionRequest(
            proposal: staleMemory,
            action: .correct,
            correctedValue: "Bring Maya the corrected trail map tomorrow."
        )
        let corrected = try actionService.perform(correctionRequest, actor: "journal-review-test")
        #expect(corrected.changed)
        #expect(corrected.reviewState == "needs_review")
        #expect(corrected.truthBoundary == "reviewable_candidate_not_truth")
        #expect(try SecondBrainEnrichmentOutputService(database: fixture.database)
            .output(id: "commitment-map")?.evidence == staleMemory.source.quote)
        tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["memory_correct"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction
        let correctedCounts = try mutationCounts(in: fixture.database)
        let correctedReplay = try actionService.perform(correctionRequest, actor: "journal-review-test")
        #expect(!correctedReplay.changed)
        #expect(correctedReplay.actionReceiptID == corrected.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == correctedCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let graphCorrection = try #require(model.proposal(candidateRef: "graph_candidate:place-discovery"))
        let graphTarget = try #require(
            graphCorrection.actions.descriptor(for: .correct)?.targetOptions.first
        )
        let correctedGraph = try actionService.perform(
            JournalIntelligenceReviewActionRequest(
                proposal: graphCorrection,
                action: .correct,
                targetOptionRef: graphTarget.id
            ),
            actor: "journal-review-test"
        )
        #expect(correctedGraph.reviewState == "needs_review")
        #expect(try SecondBrainStore(database: fixture.database)
            .outgoingRelations(for: SecondBrainOwnerRef(ownerType: "note", ownerID: fixture.noteID.uuidString))
            .isEmpty)
        tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["graph_correct"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction
        let correctedGraphCounts = try mutationCounts(in: fixture.database)
        let correctedGraphReplay = try actionService.perform(
            JournalIntelligenceReviewActionRequest(
                proposal: graphCorrection,
                action: .correct,
                targetOptionRef: graphTarget.id
            ),
            actor: "journal-review-test"
        )
        #expect(!correctedGraphReplay.changed)
        #expect(correctedGraphReplay.actionReceiptID == correctedGraph.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == correctedGraphCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let correctedGraphProposal = try #require(model.proposal(candidateRef: graphCorrection.candidateRef))
        let approveTarget = try #require(
            correctedGraphProposal.actions.descriptor(for: .approve)?.targetOptions.first { $0.id == graphTarget.id }
        )
        let graphApproveRequest = JournalIntelligenceReviewActionRequest(
                proposal: correctedGraphProposal,
                action: .approve,
                targetOptionRef: approveTarget.id
        )
        let approvedGraph = try actionService.perform(graphApproveRequest, actor: "journal-review-test")
        #expect(approvedGraph.reviewState == "accepted")
        #expect(approvedGraph.targetOwnerRef == approveTarget.targetOwnerRef)
        #expect(try SecondBrainStore(database: fixture.database)
            .outgoingRelations(for: SecondBrainOwnerRef(ownerType: "note", ownerID: fixture.noteID.uuidString))
            .count == 1)
        tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["graph_approve"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction
        let approvedGraphCounts = try mutationCounts(in: fixture.database)
        let approvedGraphReplay = try actionService.perform(graphApproveRequest, actor: "journal-review-test")
        #expect(!approvedGraphReplay.changed)
        #expect(approvedGraphReplay.actionReceiptID == approvedGraph.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == approvedGraphCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let rejectProposal = try #require(model.proposal(candidateRef: "graph_candidate:artifact-arrival"))
        let rejectRequest = JournalIntelligenceReviewActionRequest(proposal: rejectProposal, action: .reject)
        let rejected = try actionService.perform(rejectRequest, actor: "journal-review-test")
        #expect(rejected.reviewState == "rejected")
        tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["graph_reject"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction
        let rejectedCounts = try mutationCounts(in: fixture.database)
        let rejectedReplay = try actionService.perform(rejectRequest, actor: "journal-review-test")
        #expect(!rejectedReplay.changed)
        #expect(rejectedReplay.actionReceiptID == rejected.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == rejectedCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let deferProposal = try #require(model.proposal(candidateRef: "memory_candidate:trip-kyoto"))
        let deferRequest = JournalIntelligenceReviewActionRequest(proposal: deferProposal, action: .defer)
        let deferred = try actionService.perform(deferRequest, actor: "journal-review-test")
        #expect(deferred.reviewState == "deferred")
        #expect(deferred.truthBoundary == "reviewable_candidate_not_truth")
        tablesAfterAction = try allTableFingerprints(in: fixture.database)
        actionTableChanges["memory_defer"] = changedTables(from: tablesBeforeAction, to: tablesAfterAction)
        tablesBeforeAction = tablesAfterAction
        let deferredCounts = try mutationCounts(in: fixture.database)
        let deferredReplay = try actionService.perform(deferRequest, actor: "journal-review-test")
        #expect(!deferredReplay.changed)
        #expect(deferredReplay.actionReceiptID == deferred.actionReceiptID)
        #expect(try mutationCounts(in: fixture.database) == deferredCounts)

        model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let targetRequiredProposal = try #require(model.proposal(candidateRef: "graph_candidate:preference-hike"))
        let targetRequiredRequest = JournalIntelligenceReviewActionRequest(
            proposal: targetRequiredProposal,
            action: .approve
        )
        let unavailableTargetRequest = JournalIntelligenceReviewActionRequest(
            proposal: targetRequiredProposal,
            action: .approve,
            targetOptionRef: "target-option:unavailable"
        )
        let correctionRequiredProposal = try #require(model.proposal(candidateRef: "memory_candidate:memory-hiking-mood"))
        let correctionRequiredRequest = JournalIntelligenceReviewActionRequest(
            proposal: correctionRequiredProposal,
            action: .correct,
            correctedValue: "   "
        )
        let beforeInvalid = try allTableFingerprints(in: fixture.database)
        #expect(throws: JournalIntelligenceReviewActionError.targetRequired(targetRequiredProposal.candidateRef)) {
            _ = try actionService.perform(targetRequiredRequest, actor: "journal-review-test")
        }
        #expect(throws: JournalIntelligenceReviewActionError.targetUnavailable("target-option:unavailable")) {
            _ = try actionService.perform(unavailableTargetRequest, actor: "journal-review-test")
        }
        #expect(throws: JournalIntelligenceReviewActionError.correctionRequired(correctionRequiredProposal.candidateRef)) {
            _ = try actionService.perform(correctionRequiredRequest, actor: "journal-review-test")
        }
        let missingRequest = JournalIntelligenceReviewActionRequest(
            candidateRef: "memory_candidate:missing",
            family: "memory_candidate",
            expectedReviewState: "suggested",
            expectedUpdatedAt: Date(),
            action: .reject
        )
        #expect(throws: JournalIntelligenceReviewActionError.self) {
            _ = try actionService.perform(missingRequest, actor: "journal-review-test")
        }
        let unsupportedRequest = JournalIntelligenceReviewActionRequest(
            candidateRef: "future_candidate:anything",
            family: "future_candidate",
            expectedReviewState: "suggested",
            expectedUpdatedAt: Date(),
            action: .approve
        )
        #expect(throws: JournalIntelligenceReviewActionError.self) {
            _ = try actionService.perform(unsupportedRequest, actor: "journal-review-test")
        }
        let missingSourceRequest = JournalIntelligenceReviewActionRequest(
            candidateRef: "memory_candidate:noise-no-provenance",
            family: "memory_candidate",
            expectedReviewState: "suggested",
            expectedUpdatedAt: try #require(
                SecondBrainEnrichmentOutputService(database: fixture.database)
                    .output(id: "noise-no-provenance")?.updatedAt
            ),
            action: .reject
        )
        #expect(throws: JournalIntelligenceReviewActionError.self) {
            _ = try actionService.perform(missingSourceRequest, actor: "journal-review-test")
        }
        #expect(try allTableFingerprints(in: fixture.database) == beforeInvalid)

        fixture.database.close()
        let reconstructedDatabase = CiderDatabase()
        try reconstructedDatabase.open(at: fixture.databaseURL)
        defer { reconstructedDatabase.close() }
        let loadedJournalNote = try loadJournalNote(fixture.noteID, from: reconstructedDatabase)
        let reconstructedNote = try #require(loadedJournalNote)
        let reconstructedDay = try #require(JournalLibraryReadModel.build(from: [reconstructedNote]).defaultDay)
        let relaunchedModel = try JournalIntelligenceDayReviewService(database: reconstructedDatabase)
            .review(for: reconstructedDay)
        #expect(relaunchedModel.reviewedProposal(candidateRef: memoryApprove.candidateRef)?.reviewState == "accepted")
        #expect(relaunchedModel.reviewedProposal(candidateRef: rejectProposal.candidateRef)?.reviewState == "rejected")
        #expect(relaunchedModel.proposal(candidateRef: "memory_candidate:commitment-map")?.reviewState == "needs_review")
        #expect(relaunchedModel.proposal(candidateRef: deferProposal.candidateRef)?.reviewState == "deferred")
        #expect(relaunchedModel.reviewedProposal(candidateRef: graphCorrection.candidateRef)?.source == graphCorrection.source)

        #expect(reconstructedDay.captureCards.map(\.id) == day.captureCards.map(\.id))
        #expect(relaunchedModel.reviewedProposal(candidateRef: memoryApprove.candidateRef)?.sourceNavigation.captureCardID == memoryApprove.sectionID)
        #expect(sha256(try Data(contentsOf: sourceURL)) == sourceHashBefore)
        #expect(try captureEventSourceHashes(in: reconstructedDatabase) == captureSourceHashesBefore)
        #expect(try tableFingerprints(
            ["items", "notes", "capture_events", "capture_attachments", "todos", "projects", "bookmarks", "contacts", "vault_files"],
            in: reconstructedDatabase
        ) == immutableTablesBefore)
        #expect(try scalarCount("action_receipts", in: reconstructedDatabase) == 6)
        #expect(try scalarCount("agent_actions", in: reconstructedDatabase) == 6)
        let allTablesAfter = try allTableFingerprints(in: reconstructedDatabase)
        let changedTables = Set(allTablesAfter.compactMap { table, fingerprint in
            allTablesBefore[table] == fingerprint ? nil : table
        })
        #expect(changedTables == [
            "action_receipts", "agent_actions", "enrichment_outputs", "owner_label_index",
            "owner_relations", "review_lifecycle_events", "source_evidence",
        ])
        let candidateDecisionTables: Set<String> = [
            "action_receipts", "agent_actions", "enrichment_outputs",
            "review_lifecycle_events", "source_evidence",
        ]
        #expect(actionTableChanges == [
            "memory_approve": candidateDecisionTables,
            "memory_correct": candidateDecisionTables,
            "graph_correct": candidateDecisionTables,
            "graph_reject": candidateDecisionTables,
            "memory_defer": candidateDecisionTables,
            "graph_approve": candidateDecisionTables.union(["owner_label_index", "owner_relations"]),
        ])
    }

    @Test("Journal review copy fails closed for every reconciliation and receipt health state")
    func journalReviewCopyFailsClosedForEveryState() throws {
        let matched = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .matched, classification: nil),
            receiptIsStale: false
        )
        #expect(matched.label == "Likely existing match")

        let repeated = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .matched, classification: .repeated),
            receiptIsStale: false
        )
        #expect(repeated.label == "Likely repeated mention")

        let update = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .matched, classification: .newUpdate),
            receiptIsStale: false
        )
        #expect(update.label == "Likely new update")

        let conflict = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .matched, classification: .correctionOrConflict),
            receiptIsStale: false
        )
        #expect(conflict.label == "Possible correction or conflict")

        let new = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .noMatch, classification: .genuinelyNew),
            receiptIsStale: false
        )
        #expect(new.label == "No likely existing match")

        let ambiguous = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .ambiguous, classification: nil),
            receiptIsStale: false
        )
        #expect(ambiguous.label == "Several possible matches")
        #expect(ambiguous.explanation.localizedCaseInsensitiveContains("not choose"))

        let unsupported = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .unsupported, classification: nil),
            receiptIsStale: false
        )
        #expect(unsupported.label == "Not compared yet")

        let partial = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .classificationWithheld, classification: nil, truncated: true),
            receiptIsStale: false
        )
        #expect(partial.label == "Comparison incomplete")
        #expect(partial.explanation.localizedCaseInsensitiveContains("not claim"))

        let staleNovelty = JournalIntelligenceReviewReconciliation.make(
            reconciliation: reconciliation(status: .noMatch, classification: .genuinelyNew),
            receiptIsStale: true
        )
        #expect(staleNovelty.label == "Novelty not confirmed")
        #expect(staleNovelty.explanation.localizedCaseInsensitiveContains("not claiming"))

        #expect(JournalIntelligenceDayReviewHealth.loading.message.localizedCaseInsensitiveContains("checking"))
        #expect(JournalIntelligenceDayReviewHealth.empty.message.localizedCaseInsensitiveContains("nothing"))
        #expect(JournalIntelligenceDayReviewHealth.suppressed.message.localizedCaseInsensitiveContains("held back"))
        #expect(JournalIntelligenceDayReviewHealth.partial.message.localizedCaseInsensitiveContains("partial"))
        #expect(JournalIntelligenceDayReviewHealth.stale.message.localizedCaseInsensitiveContains("stale"))
        #expect(JournalIntelligenceDayReviewHealth.unavailable.message.localizedCaseInsensitiveContains("unavailable"))
        #expect(JournalIntelligenceReviewActionError.missingCandidate("candidate").localizedDescription
            == "This suggestion no longer exists. Refresh Journal Review; nothing was changed.")
        #expect(JournalIntelligenceReviewActionError.staleCandidate("candidate").localizedDescription
            == "This suggestion changed after the page loaded. Refresh Journal Review before acting.")
        #expect(JournalIntelligenceReviewActionError.alreadyReviewed("candidate", "accepted").localizedDescription
            == "This suggestion is already accepted. Its source remains available; refresh before choosing another action.")
        #expect(JournalIntelligenceReviewActionError.unsupportedFamily("future_candidate").localizedDescription
            == "This future_candidate suggestion does not have a canonical Journal Review action service yet. Nothing was changed.")
        #expect(JournalIntelligenceReviewActionError.targetRequired("candidate").localizedDescription
            == "Choose the exact target first. Cider will not guess what to approve or correct.")
        #expect(JournalIntelligenceReviewActionError.targetUnavailable("target").localizedDescription
            == "That target is no longer available. Refresh Journal Review and choose again.")
        #expect(JournalIntelligenceReviewActionError.missingSourceEvidence("candidate").localizedDescription
            == "Cider cannot verify this suggestion's exact source evidence, so the action was blocked.")
        #expect(JournalIntelligenceReviewActionError.correctionRequired("candidate").localizedDescription
            == "Enter explicit corrected wording before saving this correction.")
    }

    @Test("production Journal Review hosts unclipped wide and narrow actions and opens the exact capture")
    func productionJournalReviewHostsWideAndNarrowActionsAndExactSource() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let note = Note(
            id: fixture.noteID,
            title: "Daily Journal \(JournalIntelligenceCorpus.date)",
            content: JournalIntelligenceCorpus.journalMarkdown,
            createdAt: Date(timeIntervalSince1970: 1_784_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_784_000_000),
            relativePath: "Disposable/Daily Journal \(JournalIntelligenceCorpus.date).md"
        )
        let day = try #require(JournalLibraryReadModel.build(from: [note]).defaultDay)
        let model = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)

        #expect(model.groups.map(\.category) == JournalIntelligenceCategory.allCases)
        #expect(Set(model.groups.flatMap(\.proposals).map(\.family)) == ["graph_candidate", "memory_candidate"])
        #expect(model.groups.flatMap(\.proposals).allSatisfy {
            $0.truthBoundary == "reviewable_candidate_not_truth"
        })

        let memoryGroup = try #require(model.groups.first { group in
            group.proposals.contains { $0.family == "memory_candidate" }
        })
        let graphGroup = try #require(model.groups.first { group in
            group.proposals.contains { $0.family == "graph_candidate" }
        })
        var hostedModel = model
        hostedModel.groups = [memoryGroup, graphGroup]
        hostedModel.reviewedGroups = []
        hostedModel.statement = "Cider found 2 things worth reviewing."

        let memory = try #require(memoryGroup.proposals.first { $0.family == "memory_candidate" })
        let graph = try #require(graphGroup.proposals.first { $0.family == "graph_candidate" })
        var openedSource: JournalIntelligenceSourceNavigation?
        let actionService = JournalIntelligenceReviewActionService(database: fixture.database)
        let actionCoordinator = CiderReviewActionCoordinator(database: fixture.database)

        for presentation in [
            JournalReviewHostedPresentation(name: "wide", width: 920),
            JournalReviewHostedPresentation(name: "narrow", width: 420),
        ] {
            let view = JournalIntelligenceDayReviewView(
                state: .ready(hostedModel),
                isExpanded: .constant(true),
                onReload: {},
                onOpenSource: { openedSource = $0 },
                performReviewAction: { request in
                    actionCoordinator.perform(request)
                }
            )
            .frame(width: presentation.width)
            .fixedSize(horizontal: false, vertical: true)

            let hosted = await hostJournalReview(view, width: presentation.width)
            defer {
                hosted.window.orderOut(nil)
                hosted.window.contentView = nil
            }

            let elements = inProcessJournalReviewAccessibilityElements(in: hosted.hostingView)
            let requiredLabels = [
                "Approve this exact suggestion as a Cider memory",
                "Save corrected wording without approving it",
                "Reject \(memory.value) without accepting truth",
                "Defer \(memory.value) for later review",
                "Choose exact target",
                "Save selected target as a correction without approving it",
                "Approve the explicitly selected target for \(graph.value)",
                "Reject \(graph.value) without accepting truth",
                "Defer \(graph.value) for later review",
            ]
            for label in requiredLabels {
                #expect(elements.contains { $0.label == label }, "Missing native accessibility control: \(label)")
            }
            #expect(elements.contains {
                $0.role == NSAccessibility.Role.textField.rawValue && $0.label == "Corrected wording"
            })

            let buttonFrames = elements
                .filter { $0.role == NSAccessibility.Role.button.rawValue && $0.frame != .zero }
                .map(\.frame)
            #expect(buttonFrames.count >= 8)
            #expect(buttonFrames.allSatisfy { frame in
                frame.width >= 24 && frame.height >= 16 && hosted.screenFrame.contains(frame.insetBy(dx: 0.5, dy: 0.5))
            })
            for (index, frame) in buttonFrames.enumerated() {
                #expect(buttonFrames.dropFirst(index + 1).allSatisfy { !frame.intersects($0) })
            }

            let evidenceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cid-830-journal-review-\(presentation.name).png")
            try writeJournalReviewPNG(hosted.hostingView, to: evidenceURL)
            #expect(FileManager.default.fileExists(atPath: evidenceURL.path))

            if presentation.name == "wide" {
                let sourceButton = try #require(elements.first { element in
                    element.nativeButton?.title == "Show exact capture"
                }?.nativeButton)
                let sourceAction = try #require(sourceButton.action)
                #expect(NSApp.sendAction(sourceAction, to: sourceButton.target, from: sourceButton))
                #expect(openedSource?.precision == .exactCaptureMoment)
                #expect(openedSource?.captureCardID == memory.sectionID)
            }
        }

        var actionableModel = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let memoryApproval = try #require(actionableModel.proposal(candidateRef: "memory_candidate:people-maya"))
        let approvedMemory = try actionService.perform(
            .init(proposal: memoryApproval, action: .approve),
            actor: "journal-review-production-composition-test"
        )
        #expect(approvedMemory.reviewState == "accepted")
        #expect(approvedMemory.message == "Approved this exact suggestion as a Cider memory. The Journal source was not changed.")

        actionableModel = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let memoryCorrection = try #require(actionableModel.proposal(candidateRef: "memory_candidate:commitment-map"))
        let correctedMemory = try actionService.perform(
            .init(
                proposal: memoryCorrection,
                action: .correct,
                correctedValue: "Bring Maya the corrected trail map tomorrow."
            ),
            actor: "journal-review-production-composition-test"
        )
        #expect(correctedMemory.reviewState == "needs_review")
        #expect(correctedMemory.truthBoundary == "reviewable_candidate_not_truth")

        actionableModel = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let graphApproval = try #require(actionableModel.proposal(candidateRef: "graph_candidate:place-discovery"))
        let explicitTarget = try #require(
            graphApproval.actions.descriptor(for: .approve)?.targetOptions.first
        )
        let approvedGraph = try actionService.perform(
            .init(
                proposal: graphApproval,
                action: .approve,
                targetOptionRef: explicitTarget.id
            ),
            actor: "journal-review-production-composition-test"
        )
        #expect(approvedGraph.reviewState == "accepted")
        #expect(approvedGraph.targetOwnerRef == explicitTarget.targetOwnerRef)
        #expect(approvedGraph.message == "Approved the explicitly selected graph link. The Journal source was not changed.")

        actionableModel = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let rejection = try #require(actionableModel.proposal(candidateRef: "graph_candidate:artifact-arrival"))
        #expect(try actionService.perform(
            .init(proposal: rejection, action: .reject),
            actor: "journal-review-production-composition-test"
        ).reviewState == "rejected")

        actionableModel = try JournalIntelligenceDayReviewService(database: fixture.database).review(for: day)
        let deferral = try #require(actionableModel.proposal(candidateRef: "memory_candidate:trip-kyoto"))
        let deferredMemory = try actionService.perform(
            .init(proposal: deferral, action: .defer),
            actor: "journal-review-production-composition-test"
        )
        #expect(deferredMemory.reviewState == "deferred")
        #expect(deferredMemory.truthBoundary == "reviewable_candidate_not_truth")

        fixture.database.close()
        let reconstructedDatabase = CiderDatabase()
        try reconstructedDatabase.open(at: fixture.databaseURL)
        defer { reconstructedDatabase.close() }
        let loadedReconstructedNote = try loadJournalNote(fixture.noteID, from: reconstructedDatabase)
        let reconstructedNote = try #require(loadedReconstructedNote)
        let reconstructedDay = try #require(JournalLibraryReadModel.build(from: [reconstructedNote]).defaultDay)
        let reconstructedModel = try JournalIntelligenceDayReviewService(database: reconstructedDatabase)
            .review(for: reconstructedDay)
        #expect(reconstructedModel.reviewedProposal(candidateRef: memoryApproval.candidateRef)?.reviewState == "accepted")
        #expect(reconstructedModel.reviewedProposal(candidateRef: graphApproval.candidateRef)?.reviewState == "accepted")
        #expect(reconstructedModel.reviewedProposal(candidateRef: rejection.candidateRef)?.reviewState == "rejected")
        #expect(reconstructedModel.proposal(candidateRef: memoryCorrection.candidateRef)?.reviewState == "needs_review")
        #expect(reconstructedModel.proposal(candidateRef: deferral.candidateRef)?.reviewState == "deferred")
        #expect(reconstructedModel.reviewedProposal(candidateRef: memoryApproval.candidateRef)?
            .sourceNavigation.captureCardID == memoryApproval.sectionID)
    }

    private func captureEventSourceHashes(in database: CiderDatabase) throws -> [String: String] {
        let statement = try database.prepare("SELECT id, COALESCE(source_text, '') FROM capture_events ORDER BY id;")
        var result: [String: String] = [:]
        while try statement.step() {
            result[statement.string(at: 0)] = sha256(Data(statement.string(at: 1).utf8))
        }
        return result
    }

    private func mutationCounts(in database: CiderDatabase) throws -> [String: Int] {
        let tables = [
            "enrichment_outputs", "owner_relations", "source_evidence",
            "review_lifecycle_events", "agent_actions", "action_receipts", "owner_label_index",
        ]
        return try Dictionary(uniqueKeysWithValues: tables.map { table in
            (table, try scalarCount(table, in: database))
        })
    }

    private func scalarCount(_ table: String, in database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func tableFingerprints(
        _ tables: [String],
        in database: CiderDatabase
    ) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: tables.map { table in
            let pragma = try database.prepare("PRAGMA table_info(\(table));")
            var columns: [String] = []
            while try pragma.step() {
                columns.append(pragma.string(at: 1))
            }
            let pairs = columns.flatMap { column in
                ["'\(column)'", "quote(\"\(column)\")"]
            }.joined(separator: ", ")
            let statement = try database.prepare("SELECT json_object(\(pairs)) FROM \(table);")
            var rows: [String] = []
            while try statement.step() {
                rows.append(statement.string(at: 0))
            }
            rows.sort()
            let content = rows.joined(separator: "\n")
            return (table, "count=\(rows.count);sha256=\(sha256(Data(content.utf8)))")
        })
    }

    private func changedTables(
        from before: [String: String],
        to after: [String: String]
    ) -> Set<String> {
        Set((Set(before.keys).union(after.keys)).filter { before[$0] != after[$0] })
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadJournalNote(_ id: UUID, from database: CiderDatabase) throws -> Note? {
        let statement = try database.prepare("""
            SELECT i.title, n.content, i.created_at, i.updated_at, COALESCE(i.relative_path, '')
            FROM items i
            JOIN notes n ON n.item_id = i.id
            WHERE i.id = ? AND i.type = 'note'
            LIMIT 1;
            """)
        statement.bind(id.uuidString, at: 1)
        guard try statement.step() else { return nil }
        return Note(
            id: id,
            title: statement.string(at: 0),
            content: statement.string(at: 1),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 2)),
            modifiedAt: DatabaseHelpers.decodeDate(statement.double(at: 3)),
            relativePath: statement.string(at: 4)
        )
    }

    private func allTableFingerprints(in database: CiderDatabase) throws -> [String: String] {
        let statement = try database.prepare("""
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
              AND name NOT LIKE 'sqlite_%'
            ORDER BY name;
            """)
        var tables: [String] = []
        while try statement.step() {
            tables.append(statement.string(at: 0))
        }
        return try tableFingerprints(tables, in: database)
    }

    private func reconciliation(
        status: JournalIntelligenceReconciliationStatus,
        classification: JournalIntelligenceReconciliationClassification?,
        truncated: Bool = false
    ) -> JournalIntelligenceCrossTimeReconciliation {
        JournalIntelligenceCrossTimeReconciliation(
            status: status,
            classification: classification,
            likelyMatches: [],
            reasonCodes: truncated ? ["canonical_scan_truncated", "classification_withheld"] : [],
            explanation: status == .ambiguous
                ? "Several canonical records could match, so Cider will not choose one."
                : "Production-shaped reconciliation explanation.",
            comparedCanonicalKinds: [],
            canonicalFamilyScans: truncated ? [
                JournalIntelligenceCanonicalFamilyScan(
                    family: "owner_labels",
                    limit: 800,
                    loadedCount: 800,
                    complete: false,
                    truncated: true
                ),
            ] : [],
            maxLikelyMatches: 3,
            safeNextCommands: []
        )
    }

    private struct JournalReviewHostedPresentation {
        var name: String
        var width: CGFloat
    }

    private struct JournalReviewAccessibilityElement {
        var role: String?
        var label: String?
        var frame: CGRect
        var nativeButton: NSButton?
    }

    private struct HostedJournalReview<Content: View> {
        var window: NSWindow
        var hostingView: CiderMainWindowHostingView<Content>
        var screenFrame: CGRect
    }

    private func hostJournalReview<Content: View>(
        _ view: Content,
        width: CGFloat
    ) async -> HostedJournalReview<Content> {
        let hostingView = CiderMainWindowHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let height = max(1, fitting.height)
        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 40, y: 40, width: width, height: height), display: false)
        window.title = "CID-830 disposable Journal Review \(UUID().uuidString)"
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(150))
        hostingView.layoutSubtreeIfNeeded()
        let frameInWindow = hostingView.convert(hostingView.bounds, to: nil)
        return HostedJournalReview(
            window: window,
            hostingView: hostingView,
            screenFrame: window.convertToScreen(frameInWindow)
        )
    }

    private func inProcessJournalReviewAccessibilityElements(
        in root: NSView
    ) -> [JournalReviewAccessibilityElement] {
        var elements: [JournalReviewAccessibilityElement] = []
        var visited = Set<ObjectIdentifier>()

        func collect(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            let role = object.perform(NSSelectorFromString("accessibilityRole"))?
                .takeUnretainedValue() as? String
            let label = object.perform(NSSelectorFromString("accessibilityLabel"))?
                .takeUnretainedValue() as? String
            let button = object as? any NSAccessibilityButton
            elements.append(.init(
                role: role,
                label: label,
                frame: button?.accessibilityFrame() ?? .zero,
                nativeButton: object as? NSButton
            ))
            if let children = object.perform(NSSelectorFromString("accessibilityChildren"))?
                .takeUnretainedValue() as? NSArray {
                for child in children {
                    if let child = child as? NSObject { collect(child) }
                }
            }
        }

        func collectView(_ view: NSView) {
            collect(view)
            if let button = view as? NSButton {
                let customLabel = button.accessibilityLabel()
                elements.append(.init(
                    role: NSAccessibility.Role.button.rawValue,
                    label: customLabel?.isEmpty == false ? customLabel : button.title,
                    frame: button.accessibilityFrame(),
                    nativeButton: button
                ))
            }
            if let field = view as? NSTextField,
               let object = field.accessibilityChildren()?.first as? NSObject,
               let role = object.perform(NSSelectorFromString("accessibilityRole"))?
                .takeUnretainedValue() as? String {
                elements.append(.init(
                    role: role,
                    label: field.accessibilityLabel() ?? field.placeholderString,
                    frame: field.accessibilityFrame(),
                    nativeButton: nil
                ))
            }
            for child in view.accessibilityChildren() ?? [] {
                if let child = child as? NSObject { collect(child) }
            }
            for subview in view.subviews { collectView(subview) }
        }
        collectView(root)
        return elements
    }

    private func writeJournalReviewPNG(_ view: NSView, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    private struct Fixture {
        var database: CiderDatabase
        var databaseURL: URL
        var noteID: UUID

        @MainActor
        func close() {
            database.close()
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }
    }

    private func makeFixture() throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-intelligence-receipt-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        let noteID = UUID()
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let baseTime = Date(timeIntervalSince1970: 1_784_000_000)

        try insertJournal(noteID: noteID, at: baseTime, into: database)
        for (index, capture) in JournalIntelligenceCorpus.captures.enumerated() {
            try insertCapture(capture, noteID: noteID, at: baseTime.addingTimeInterval(Double(index * 60)), into: database)
        }

        let morning = JournalIntelligenceCorpus.captures[0]
        let midday = JournalIntelligenceCorpus.captures[1]
        let correction = JournalIntelligenceCorpus.captures[2]
        let outputService = SecondBrainEnrichmentOutputService(database: database)

        try record(memory(
            id: "people-maya",
            owner: noteOwner,
            capture: morning,
            quote: "Maya started a new job at Alder Labs.",
            value: "Maya started a new job at Alder Labs.",
            kind: "relationship_event",
            confidence: 0.86
        ), capture: morning, using: outputService)
        try record(graph(
            id: "place-discovery",
            owner: noteOwner,
            capture: morning,
            quote: "I went to Discovery Park.",
            mention: "Discovery Park",
            types: [.place],
            relations: [.visited],
            confidence: 0.82
        ), capture: morning, using: outputService)
        try record(memory(
            id: "activity-hike",
            owner: noteOwner,
            capture: morning,
            quote: "I loved the cedar loop hike.",
            value: "Visher completed the cedar loop hike.",
            kind: "activity",
            confidence: 0.78
        ), capture: morning, using: outputService)
        try record(graph(
            id: "preference-hike",
            owner: noteOwner,
            capture: morning,
            quote: "I loved the cedar loop hike.",
            mention: "cedar loop hike",
            types: [.object],
            relations: [.likes],
            confidence: 0.78
        ), capture: morning, using: outputService)
        try record(memory(
            id: "commitment-map",
            owner: noteOwner,
            capture: morning,
            quote: "I promised Maya I would bring the trail map tomorrow.",
            value: "Bring Maya the trail map tomorrow.",
            kind: "commitment",
            confidence: 0.88
        ), capture: morning, using: outputService)
        var task = memory(
            id: "task-permit",
            owner: noteOwner,
            capture: morning,
            quote: "Remember to email the signed permit.",
            value: "Email the signed permit.",
            kind: "task_intent",
            confidence: 0.9
        )
        task.reviewState = "deferred"
        try record(task, capture: morning, using: outputService)
        try record(graph(
            id: "artifact-arrival",
            owner: noteOwner,
            capture: morning,
            quote: "I watched Arrival last night.",
            mention: "Arrival",
            types: [.movie, .media],
            relations: [.watched],
            confidence: 0.84
        ), capture: morning, using: outputService)
        try record(memory(
            id: "trip-kyoto",
            owner: noteOwner,
            capture: midday,
            quote: "We are planning a September trip to Kyoto.",
            value: "Plan a September trip to Kyoto.",
            kind: "trip_plan",
            confidence: 0.9
        ), capture: midday, using: outputService)
        try record(memory(
            id: "memory-hiking-mood",
            owner: noteOwner,
            capture: morning,
            quote: "Remember that hiking before work improves my mood.",
            value: "Hiking before work improves Visher's mood.",
            kind: "pattern",
            confidence: 0.88
        ), capture: morning, using: outputService)

        try record(graph(
            id: "noise-vague",
            owner: noteOwner,
            capture: correction,
            quote: "I liked it.",
            mention: "it",
            types: [.object],
            relations: [.likes],
            confidence: 0.91
        ), capture: correction, using: outputService)
        try record(graph(
            id: "noise-incidental",
            owner: noteOwner,
            capture: midday,
            quote: "Maybe Alex mentioned the old mall, but I am not sure.",
            mention: "old mall",
            types: [.place],
            relations: [.mentions],
            confidence: 0.51
        ), capture: midday, using: outputService)
        try record(graph(
            id: "noise-corrected",
            owner: noteOwner,
            capture: correction,
            quote: "I went to Portland.",
            mention: "Portland",
            types: [.place],
            relations: [.visited],
            confidence: 0.84
        ), capture: correction, using: outputService)
        try record(graph(
            id: "noise-duplicate",
            owner: noteOwner,
            capture: midday,
            quote: "I went to Discovery Park again.",
            mention: "Discovery Park",
            types: [.place],
            relations: [.visited],
            confidence: 0.8
        ), capture: midday, using: outputService)
        var accepted = memory(
            id: "noise-accepted",
            owner: noteOwner,
            capture: correction,
            quote: "I went to Seattle.",
            value: "Visher went to Seattle.",
            kind: "activity",
            confidence: 0.84
        )
        accepted.reviewState = "accepted"
        try record(accepted, capture: correction, using: outputService)
        var rejected = memory(
            id: "noise-rejected",
            owner: noteOwner,
            capture: correction,
            quote: "I did not visit the Red Barn.",
            value: "Visher visited the Red Barn.",
            kind: "activity",
            confidence: 0.84
        )
        rejected.reviewState = "rejected"
        try record(rejected, capture: correction, using: outputService)
        var missingProvenance = memory(
            id: "noise-no-provenance",
            owner: noteOwner,
            capture: midday,
            quote: "Save the ferry itinerary PDF with the trip.",
            value: "Save the ferry itinerary PDF.",
            kind: "artifact",
            confidence: 0.9
        )
        missingProvenance.metadata.removeValue(forKey: "capture_event_id")
        missingProvenance.metadata.removeValue(forKey: "capture_event_ref")
        try outputService.record(missingProvenance)

        return Fixture(database: database, databaseURL: url, noteID: noteID)
    }

    private func insertJournal(noteID: UUID, at date: Date, into database: CiderDatabase) throws {
        let title = "Daily Journal \(JournalIntelligenceCorpus.date)"
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, NULL, ?);
            """)
        item.bind(noteID.uuidString, at: 1)
            .bind(title, at: 2)
            .bind(date.timeIntervalSince1970, at: 3)
            .bind(date.timeIntervalSince1970, at: 4)
            .bind("Inbox/Notes/\(title).md", at: 5)
        try item.step()
        let note = try database.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        note.bind(noteID.uuidString, at: 1)
            .bind(JournalIntelligenceCorpus.journalMarkdown, at: 2)
        try note.step()
    }

    private func seedCanonicalReconciliationRecords(in database: CiderDatabase) throws {
        try insertContact(id: "contact-maya", title: "Maya", into: database)
        _ = try SecondBrainOwnerLabelIndexService(database: database).refreshContact(ownerID: "contact-maya")

        let timestamp = Date(timeIntervalSince1970: 1_783_000_000).timeIntervalSince1970
        let taskItem = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES ('todo-signed-permit', 'todo', 'Email the signed permit', ?, ?, NULL, 'Inbox/Todos/Email the signed permit.ics');
            """)
        taskItem.bind(timestamp, at: 1).bind(timestamp, at: 2)
        try taskItem.step()
        try database.runSQL("""
            INSERT INTO todos (item_id, details, due_date, priority, is_completed, completed_at, notes, checklist, surfacing_rules, action_url, snoozed_until)
            VALUES ('todo-signed-permit', '', NULL, NULL, 0, NULL, '', NULL, NULL, NULL, NULL);
            """)

        _ = try SecondBrainOwnerLabelIndexService(database: database).upsertLabel(
            owner: SecondBrainOwnerRef(ownerType: "media_item", ownerID: "arrival"),
            ownerKind: "media",
            canonicalLabel: "Arrival",
            aliases: ["Arrival (2016)"],
            sourceRefs: ["media_item:arrival"],
            labelSource: "test.canonical.media",
            confidence: 0.99
        )

        let priorOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: "prior-journal")
        let outputService = SecondBrainEnrichmentOutputService(database: database)
        try outputService.record(acceptedMemory(
            id: "accepted-maya-job",
            owner: priorOwner,
            value: "Maya started a new job at Beacon Works.",
            kind: "relationship_event"
        ))
        try outputService.record(acceptedMemory(
            id: "accepted-trip-kyoto",
            owner: priorOwner,
            value: "October trip to Kyoto",
            kind: "trip_plan"
        ))
        try outputService.record(acceptedMemory(
            id: "accepted-hiking-mood",
            owner: priorOwner,
            value: "Hiking before work improves Visher's mood.",
            kind: "pattern"
        ))

        var acceptedPreference = graph(
            id: "accepted-dislikes-hike",
            owner: priorOwner,
            capture: JournalIntelligenceCorpus.captures[0],
            quote: "I loved the cedar loop hike.",
            mention: "cedar loop hike",
            types: [.object],
            relations: [.dislikes],
            confidence: 0.95
        )
        acceptedPreference.reviewState = "accepted"
        acceptedPreference.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] = "graph_object"
        acceptedPreference.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] = "cedar-loop-hike"
        acceptedPreference.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType] = "dislikes"
        try outputService.record(acceptedPreference)
    }

    private func insertContact(id: String, title: String, into database: CiderDatabase) throws {
        let timestamp = Date(timeIntervalSince1970: 1_783_000_000).timeIntervalSince1970
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'contact', ?, ?, ?, NULL, ?);
            """)
        item.bind(id, at: 1)
            .bind(title, at: 2)
            .bind(timestamp, at: 3)
            .bind(timestamp, at: 4)
            .bind("Inbox/Contacts/\(id).vcf", at: 5)
        try item.step()
        let contact = try database.prepare("""
            INSERT INTO contacts (item_id, relationship_label, birthday, notes, email, phone, address, has_avatar, custom_fields)
            VALUES (?, '', NULL, '', '', '', '', 0, '[]');
            """)
        contact.bind(id, at: 1)
        try contact.step()
    }

    private func acceptedMemory(
        id: String,
        owner: SecondBrainOwnerRef,
        value: String,
        kind: String
    ) -> SecondBrainEnrichmentOutput {
        SecondBrainEnrichmentOutput(
            id: id,
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: value.lowercased(),
            label: "Accepted memory: \(kind)",
            evidence: value,
            source: "test.accepted_memory",
            confidence: 0.96,
            reviewState: "accepted",
            metadata: [
                "memory_kind": kind,
                "candidate_kind": kind,
                "source_kind": "journal",
                "source_quote": value,
                "truth_boundary": "accepted_memory_fact",
            ],
            createdAt: Date(timeIntervalSince1970: 1_783_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_783_000_000)
        )
    }

    private func insertCapture(_ capture: JournalIntelligenceCorpus.Capture, noteID: UUID, at date: Date, into database: CiderDatabase) throws {
        let metadata = DatabaseHelpers.encodeJSON([
            "date": JournalIntelligenceCorpus.date,
            "time": capture.time,
            "appendSource": capture.source,
            "input": capture.surface == "voice" ? "voice-transcript" : "text",
        ]) ?? "{}"
        let event = try database.prepare("""
            INSERT INTO capture_events (id, source_kind, surface, channel, channel_id, thread_id, message_id, sender_id, sender_name, source_url, source_file, source_text, attachment_count, metadata, created_at)
            VALUES (?, 'journal', ?, ?, NULL, NULL, NULL, NULL, 'Visher', NULL, NULL, ?, 0, ?, ?);
            """)
        event.bind(capture.id, at: 1)
            .bind(capture.surface, at: 2)
            .bind(capture.source, at: 3)
            .bind(capture.text, at: 4)
            .bind(metadata, at: 5)
            .bind(date.timeIntervalSince1970, at: 6)
        try event.step()

        let relation = try database.prepare("""
            INSERT INTO owner_relations (id, source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at)
            VALUES (?, 'capture_event', ?, 'note', ?, 'produced_item', 'Journal capture appended to note.', 'capture.add', 'system', 1, '{}', ?, ?);
            """)
        relation.bind("relation-\(capture.id)", at: 1)
            .bind(capture.id, at: 2)
            .bind(noteID.uuidString, at: 3)
            .bind(date.timeIntervalSince1970, at: 4)
            .bind(date.timeIntervalSince1970, at: 5)
        try relation.step()
    }

    private func record(_ output: SecondBrainEnrichmentOutput, capture: JournalIntelligenceCorpus.Capture, using service: SecondBrainEnrichmentOutputService) throws {
        var output = output
        output.metadata["capture_event_id"] = capture.id
        output.metadata["capture_event_ref"] = "capture_event:\(capture.id)"
        output.metadata["journal_date"] = JournalIntelligenceCorpus.date
        output.metadata["journal_time"] = capture.time
        try service.record(output)
    }

    private func graph(
        id: String,
        owner: SecondBrainOwnerRef,
        capture: JournalIntelligenceCorpus.Capture,
        quote: String,
        mention: String,
        types: [SecondBrainGraphCandidateContract.ObjectType],
        relations: [SecondBrainGraphCandidateContract.RelationType],
        confidence: Double
    ) -> SecondBrainEnrichmentOutput {
        var output = try! SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: types,
            relationGuesses: relations,
            confidence: confidence,
            confidenceReason: "The deterministic journal corpus contains an explicit source-backed statement.",
            source: "test.journal_intelligence_corpus"
        )
        output.id = id
        addSpan(to: &output, quote: quote, capture: capture)
        return output
    }

    private func memory(
        id: String,
        owner: SecondBrainOwnerRef,
        capture: JournalIntelligenceCorpus.Capture,
        quote: String,
        value: String,
        kind: String,
        confidence: Double
    ) -> SecondBrainEnrichmentOutput {
        var output = SecondBrainEnrichmentOutput(
            id: id,
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: value.lowercased(),
            label: "Memory candidate: \(kind)",
            evidence: quote,
            source: "test.journal_intelligence_corpus",
            confidence: confidence,
            reviewState: "suggested",
            metadata: [
                "memory_kind": kind,
                "candidate_kind": kind,
                "requires_review": "true",
                "source_kind": "journal",
                "source_quote": quote,
                "source_owner_ref": owner.canonicalRef,
                "truth_boundary": "reviewable_candidate_not_truth",
                "confidence_reason": "The deterministic journal corpus contains an explicit source-backed statement.",
            ]
        )
        addSpan(to: &output, quote: quote, capture: capture)
        return output
    }

    private func addSpan(to output: inout SecondBrainEnrichmentOutput, quote: String, capture: JournalIntelligenceCorpus.Capture) {
        let range = capture.text.range(of: quote)!
        output.metadata["source_span_start"] = String(capture.text.distance(from: capture.text.startIndex, to: range.lowerBound))
        output.metadata["source_span_end"] = String(capture.text.distance(from: capture.text.startIndex, to: range.upperBound))
    }
}
