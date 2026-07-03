import XCTest
@testable import Cider
@testable import CiderCLI

final class CiderDueToSurfaceFeedServiceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }

    func testDueToSurfaceFeedCombinesAgendaReviewStaleCaptureAndLinkedContextWithEvidence() throws {
        let now = date(2026, 6, 15)
        let dueTodo = TodoCard(title: "Pay rent", dueDate: now, priority: .high, actionURLString: "https://rent.example.com")
        let completedTodo = TodoCard(title: "Pay insurance", dueDate: now, isCompleted: true, completedAt: now)
        let dueDateCard = DateCard(title: "Dinner with Jami", startAt: now)
        let staleNote = CiderDueToSurfaceStaleCapture(
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: "stale-note"),
            title: "Inbox capture about Pine House",
            itemType: "note",
            relativePath: "Inbox/Notes/Pine House.md",
            createdAt: date(2026, 6, 10),
            updatedAt: date(2026, 6, 10),
            reasonCodes: ["inbox_unfiled", "stale_capture"]
        )
        let staleNoteID = UUID()
        let reviewItem = CiderReviewQueueItem(
            id: "review-1",
            kind: "graph_candidate",
            source: "enrichment_outputs",
            itemID: staleNoteID,
            itemType: "note",
            title: "Pine House graph candidate",
            relativePath: nil,
            reason: "review graph candidate",
            reasonCodes: ["graph_candidate", "reviewable_candidate"],
            suggestedAction: "review_graph_candidate",
            reviewState: "suggested",
            createdAt: now,
            safeActions: ["inspect"],
            candidateID: "gc-1",
            candidateRef: "graph_candidate:gc-1",
            sourceQuote: "We went to Pine House.",
            safeNextCommands: ["cider-cli item graph-candidate gc-1 --json"],
            reviewFamily: "graph_candidate"
        )
        let linked = CiderDueToSurfaceLinkedContext(
            id: "sim-1",
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: "stale-note"),
            targetOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: "other-note"),
            title: "Potential Pine House context link",
            reason: "Similarity candidate can connect this capture to related context.",
            reasonCodes: ["similarity_candidate", "chunk_overlap"],
            confidence: 0.72,
            reviewState: "suggested",
            evidenceRef: "source_evidence:e1",
            safeNextCommands: ["cider-cli item similarity note stale-note --json"]
        )
        let acceptedFact = SecondBrainAcceptedMemoryFact(candidate: SecondBrainEnrichmentOutput(
            id: "mem-accepted-1",
            owner: SecondBrainOwnerRef(ownerType: "note", ownerID: staleNoteID.uuidString),
            chunkID: "chunk-accepted-1",
            kind: "memory_candidate",
            value: "Pine House is relevant to dinner planning",
            normalizedValue: "pine house is relevant to dinner planning",
            label: "Accepted memory",
            evidence: "We went to Pine House.",
            source: "item.memory-suggest",
            confidence: 0.91,
            reviewState: "accepted",
            metadata: [
                "memory_kind": "preference",
                "memory_key": "pine-house.dinner",
                "source_owner_ref": "note:\(staleNoteID.uuidString)",
                "source_evidence_ref": "source_evidence:accepted-1",
            ],
            createdAt: now,
            updatedAt: now
        ))

        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [dueTodo, completedTodo], dateCards: [dueDateCard], now: now, calendar: calendar),
            reviewItems: [reviewItem],
            staleCaptures: [staleNote],
            linkedContext: [linked],
            acceptedMemoryFacts: [acceptedFact],
            now: now,
            limit: 20
        )

        XCTAssertEqual(feed.command, "item.due-to-surface")
        XCTAssertFalse(feed.changed)
        XCTAssertEqual(feed.candidates.count, 6)
        XCTAssertTrue(feed.candidates.contains { $0.family == .agenda && $0.owner.ownerID == dueTodo.id.uuidString })
        let dateCardCandidate = try XCTUnwrap(feed.candidates.first { $0.family == .agenda && $0.owner.ownerID == dueDateCard.id.uuidString })
        XCTAssertEqual(dateCardCandidate.owner.ownerType, "dateCard")
        XCTAssertTrue(dateCardCandidate.sourceRefs.contains("dateCard:\(dueDateCard.id.uuidString)"))
        XCTAssertTrue(dateCardCandidate.safeNextCommands.contains("cider-cli item why-surfaced dateCard \(dueDateCard.id.uuidString) --json"))
        XCTAssertFalse(dateCardCandidate.safeNextCommands.contains { $0.contains("date_card") })
        XCTAssertFalse(feed.candidates.contains { $0.title == "Pay insurance" })
        XCTAssertTrue(feed.candidates.contains { $0.family == .reviewItem && $0.reasonCodes.contains("reviewable_candidate") && $0.truthBoundary == "reviewable_candidate_not_truth" })
        XCTAssertTrue(feed.candidates.contains { $0.family == .staleCapture && $0.reasonCodes.contains("stale_capture") })
        XCTAssertTrue(feed.candidates.contains { $0.family == .linkedContext && $0.citedEvidence.contains { $0.ref == "source_evidence:e1" } })
        let memoryFact = try XCTUnwrap(feed.candidates.first { $0.family == .acceptedMemoryFact })
        XCTAssertEqual(memoryFact.factRef, "accepted_memory_fact:mem-accepted-1")
        XCTAssertEqual(memoryFact.candidateRef, "memory_candidate:mem-accepted-1")
        XCTAssertEqual(memoryFact.truthBoundary, "accepted_memory_fact")
        XCTAssertEqual(memoryFact.candidateBoundary, "reviewable_memory_candidates_excluded")
        XCTAssertTrue(memoryFact.reasonCodes.contains("follow_up_relevance"))
        XCTAssertTrue(memoryFact.sourceRefs.contains("source_evidence:accepted-1"))
        XCTAssertTrue(memoryFact.safeVerificationCommands.contains("cider-cli item memory-facts inspect mem-accepted-1 --json"))
        let memoryFactDict = dueToSurfaceCandidateToDict(memoryFact, formatter: ISO8601DateFormatter())
        let relevance = try XCTUnwrap(memoryFactDict["surfacingRelevance"] as? [String: Any])
        XCTAssertEqual(relevance["truthBoundary"] as? String, "accepted_memory_fact")
        XCTAssertEqual(relevance["candidateBoundary"] as? String, "reviewable_memory_candidates_excluded")
        XCTAssertTrue((relevance["verificationCommands"] as? [String])?.contains("cider-cli item memory-facts inspect mem-accepted-1 --json") == true)
        XCTAssertTrue(((relevance["relevanceReasons"] as? [[String: Any]]) ?? []).contains { $0["kind"] as? String == "follow_up_relevance" })
        XCTAssertTrue(feed.safeNextCommands.contains("cider-cli item due-to-surface --json"))
    }

    func testDueToSurfaceFeedOrdersByUrgencyScoreAndKeepsReviewStateSuggested() {
        let now = date(2026, 6, 15)
        let overdue = TodoCard(title: "Overdue task", dueDate: date(2026, 6, 14))
        let upcoming = TodoCard(title: "Upcoming task", dueDate: date(2026, 6, 18))

        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [upcoming, overdue], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )

        XCTAssertEqual(feed.candidates.map(\.title).prefix(2), ["Overdue task", "Upcoming task"])
        XCTAssertTrue(feed.candidates.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" || $0.truthBoundary == "agenda_read_model_not_mutation" })
        XCTAssertEqual(feed.candidates.first?.urgency, "overdue")
        XCTAssertEqual(feed.candidates.first?.reviewState, "overdue")
    }

    func testAgendaDueCandidateExposesTransportNeutralPingContract() throws {
        let now = date(2026, 6, 15)
        let dueTodo = TodoCard(title: "Ping-ready todo", dueDate: now)

        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [dueTodo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )

        let candidate = try XCTUnwrap(feed.candidates.first)
        let dict = dueToSurfaceCandidateToDict(candidate, formatter: ISO8601DateFormatter())

        XCTAssertEqual(dict["itemID"] as? String, dueTodo.id.uuidString)
        XCTAssertEqual(dict["kind"] as? String, "todo")
        XCTAssertEqual(dict["completionState"] as? String, "active")
        XCTAssertEqual(dict["ackState"] as? String, "unacknowledged")
        let due = try XCTUnwrap(dict["due"] as? [String: Any])
        XCTAssertEqual(due["status"] as? String, "today")
        XCTAssertNotNil(due["at"] as? String)
        let ping = try XCTUnwrap(dict["ping"] as? [String: Any])
        XCTAssertEqual(ping["sourceOfTruth"] as? String, "cider_item")
        XCTAssertEqual(ping["transportBoundary"] as? String, "transport_records_delivery_only")
        XCTAssertEqual(ping["duplicateKey"] as? String, "todo:\(dueTodo.id.uuidString):\(dueTodo.dueDate!.timeIntervalSince1970):surface")
        XCTAssertEqual(ping["receiptCommand"] as? String, "cider-cli item ping-receipt record todo \(dueTodo.id.uuidString) --transport <transport> --surface <surface> --json")
        let safeCommands = try XCTUnwrap(dict["safeNextCommands"] as? [String])
        XCTAssertTrue(safeCommands.contains("cider-cli item ping-receipt record todo \(dueTodo.id.uuidString) --transport <transport> --surface <surface> --json"))
    }
}
