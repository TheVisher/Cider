import Foundation

struct CiderDueToSurfaceFeed: Equatable {
    var command: String = "item.due-to-surface"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var candidates: [CiderDueToSurfaceCandidate]
    var countsByFamily: [String: Int]
    var safeNextCommands: [String]
}

struct CiderDueToSurfaceEvidence: Equatable {
    var ref: String
    var kind: String
    var summary: String
    var sourceOwnerRef: String?
    var candidateRef: String?
    var metadata: [String: String] = [:]
}

struct CiderDueToSurfaceWindow: Equatable {
    var label: String
    var startsAt: Date?
    var endsAt: Date?
}

struct CiderDueToSurfaceCandidate: Identifiable, Equatable {
    enum Family: String {
        case agenda
        case reviewItem = "review_item"
        case staleCapture = "stale_capture"
        case linkedContext = "linked_context"
        case acceptedMemoryFact = "accepted_memory_fact"
    }

    var id: String
    var family: Family
    var owner: SecondBrainOwnerRef
    var title: String
    var itemType: String
    var whyNow: String
    var reasonCodes: [String]
    var urgency: String
    var window: CiderDueToSurfaceWindow
    var confidence: Double
    var reviewState: String
    var truthBoundary: String
    var candidateBoundary: String? = nil
    var explanation: String? = nil
    var factRef: String? = nil
    var candidateRef: String? = nil
    var sourceCitation: String? = nil
    var relatedRefs: [String] = []
    var safeVerificationCommands: [String] = []
    var score: Double
    var sourceRefs: [String]
    var citedEvidence: [CiderDueToSurfaceEvidence]
    var safeNextCommands: [String]
}

struct CiderDueToSurfaceStaleCapture: Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var itemType: String
    var relativePath: String?
    var createdAt: Date
    var updatedAt: Date
    var reasonCodes: [String]
}

struct CiderDueToSurfaceLinkedContext: Equatable {
    var id: String
    var sourceOwner: SecondBrainOwnerRef
    var targetOwner: SecondBrainOwnerRef
    var title: String
    var reason: String
    var reasonCodes: [String]
    var confidence: Double
    var reviewState: String
    var evidenceRef: String?
    var safeNextCommands: [String]
}

enum CiderDueToSurfaceFeedService {
    static func build(
        agenda: AgendaBriefing,
        reviewItems: [CiderReviewQueueItem],
        staleCaptures: [CiderDueToSurfaceStaleCapture],
        linkedContext: [CiderDueToSurfaceLinkedContext],
        acceptedMemoryFacts: [SecondBrainAcceptedMemoryFact] = [],
        now: Date = Date(),
        limit: Int = 20
    ) -> CiderDueToSurfaceFeed {
        var candidates: [CiderDueToSurfaceCandidate] = []
        candidates += agenda.items.compactMap { agendaCandidate($0, now: now) }
        candidates += reviewItems.map { reviewCandidate($0, now: now) }
        candidates += staleCaptures.map { staleCaptureCandidate($0, now: now) }
        candidates += linkedContext.map { linkedContextCandidate($0, now: now) }
        candidates += acceptedMemoryFacts.map { acceptedMemoryFactCandidate($0, now: now) }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let capped = Array(sorted.prefix(max(0, limit)))
        return CiderDueToSurfaceFeed(
            generatedAt: now,
            candidates: capped,
            countsByFamily: groupedCounts(capped.map { $0.family.rawValue }),
            safeNextCommands: [
                "cider-cli item due-to-surface --json",
                "cider-cli agenda --json",
                "cider-cli capture review-queue --limit 20 --json",
                "cider-cli item recall-context --query <topic> --json",
                "cider-cli item memory-facts resurface --json",
                "cider-cli item similarity-health --json",
            ]
        )
    }

    static func acceptedMemoryFactCandidates(
        _ facts: [SecondBrainAcceptedMemoryFact],
        now: Date = Date(),
        limit: Int = 20
    ) -> [CiderDueToSurfaceCandidate] {
        facts.map { acceptedMemoryFactCandidate($0, now: now) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func acceptedMemoryFactCandidate(_ fact: SecondBrainAcceptedMemoryFact, now: Date) -> CiderDueToSurfaceCandidate {
        let output = fact.candidate
        let memoryKind = output.metadata["accepted_memory_kind"] ?? output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? "memory"
        let memoryStatus = output.metadata["memory_status"] ?? "current"
        let reviewedAt = output.metadata["reviewed_at"].flatMap { ISO8601DateFormatter().date(from: $0) }
        var reasonCodes = ["accepted_memory_fact", "follow_up_relevance", memoryKind, memoryStatus]
        if output.metadata["memory_key"] != nil { reasonCodes.append("has_memory_key") }
        if output.metadata["linked_owner_refs"] != nil { reasonCodes.append("has_linked_owners") }
        let relatedRefs = DatabaseHelpers.decodeStringArray(output.metadata["linked_owner_refs"])
        let evidenceRef = output.metadata["source_evidence_ref"] ?? "source_evidence:\(output.id)"
        let sourceCitation = output.metadata["source_owner_ref"] ?? output.owner.canonicalRef
        let explanation = "Accepted memory fact is eligible for follow-up relevance because it was explicitly accepted and has source-backed evidence."
        let safeCommands = [
            "cider-cli item memory-facts inspect \(output.id) --json",
            "cider-cli item recall-context --item \(output.owner.ownerType) \(output.owner.ownerID) --json",
            "cider-cli item action-ledger list --owner \(output.owner.canonicalRef) --command item.accept-memory-candidate --json",
        ]
        return CiderDueToSurfaceCandidate(
            id: fact.factRef,
            family: .acceptedMemoryFact,
            owner: output.owner,
            title: output.metadata["accepted_value"] ?? output.value,
            itemType: memoryKind,
            whyNow: explanation,
            reasonCodes: Array(Set(reasonCodes)).sorted(),
            urgency: "context",
            window: CiderDueToSurfaceWindow(label: "accepted memory follow-up", startsAt: reviewedAt ?? output.updatedAt, endsAt: nil),
            confidence: output.confidence ?? 0.75,
            reviewState: output.reviewState,
            truthBoundary: "accepted_memory_fact",
            candidateBoundary: "reviewable_memory_candidates_excluded",
            explanation: explanation,
            factRef: fact.factRef,
            candidateRef: fact.candidateRef,
            sourceCitation: sourceCitation,
            relatedRefs: relatedRefs,
            safeVerificationCommands: ["cider-cli item memory-facts inspect \(output.id) --json"],
            score: 58 + ((output.confidence ?? 0.75) * 10),
            sourceRefs: Array(Set([fact.factRef, fact.candidateRef, output.owner.canonicalRef, sourceCitation] + relatedRefs)).sorted(),
            citedEvidence: [
                CiderDueToSurfaceEvidence(
                    ref: evidenceRef,
                    kind: "accepted_memory_fact_source",
                    summary: output.evidence,
                    sourceOwnerRef: sourceCitation,
                    candidateRef: fact.candidateRef,
                    metadata: [
                        "truthBoundary": "accepted_memory_fact",
                        "candidateBoundary": "reviewable_memory_candidates_excluded",
                    ]
                ),
            ],
            safeNextCommands: safeCommands
        )
    }

    private static func agendaCandidate(_ item: AgendaBriefingItem, now: Date) -> CiderDueToSurfaceCandidate? {
        guard item.surfaceToday else { return nil }
        let ownerType = item.itemType == .todo ? "todo" : "dateCard"
        let urgency = item.surfacingExplanation.urgency
        return CiderDueToSurfaceCandidate(
            id: "agenda:\(ownerType):\(item.id.uuidString)",
            family: .agenda,
            owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: item.id.uuidString),
            title: item.title,
            itemType: item.itemType.rawValue,
            whyNow: item.reason,
            reasonCodes: ["agenda_due", item.status.rawValue, item.bucket.rawValue, item.itemType.rawValue],
            urgency: urgency,
            window: CiderDueToSurfaceWindow(label: item.reason, startsAt: now, endsAt: item.dueAt),
            confidence: 0.95,
            reviewState: item.status.rawValue,
            truthBoundary: "agenda_read_model_not_mutation",
            score: urgencyScore(urgency) + 30,
            sourceRefs: ["\(ownerType):\(item.id.uuidString)"],
            citedEvidence: [
                CiderDueToSurfaceEvidence(
                    ref: "\(ownerType):\(item.id.uuidString)",
                    kind: "agenda_item",
                    summary: item.reminderPolicy,
                    sourceOwnerRef: "\(ownerType):\(item.id.uuidString)",
                    candidateRef: nil,
                    metadata: ["status": item.status.rawValue, "bucket": item.bucket.rawValue]
                ),
            ],
            safeNextCommands: [
                "cider-cli item why-surfaced \(ownerType) \(item.id.uuidString) --json",
                "cider-cli agenda --json",
            ]
        )
    }

    private static func reviewCandidate(_ item: CiderReviewQueueItem, now: Date) -> CiderDueToSurfaceCandidate {
        let owner = SecondBrainOwnerRef(ownerType: item.itemType, ownerID: item.itemID.uuidString)
        let candidateRef = item.candidateRef ?? item.candidateID.map { "candidate:\($0)" }
        var evidence: [CiderDueToSurfaceEvidence] = [
            CiderDueToSurfaceEvidence(
                ref: candidateRef ?? "review_item:\(item.id)",
                kind: item.kind,
                summary: item.sourceQuote ?? item.reason,
                sourceOwnerRef: item.sourceItemRef ?? owner.canonicalRef,
                candidateRef: candidateRef,
                metadata: ["reviewState": item.reviewState, "source": item.source]
            ),
        ]
        if let sourceEvidenceRecord = item.sourceEvidenceRecord {
            evidence.append(CiderDueToSurfaceEvidence(
                ref: "source_evidence:\(sourceEvidenceRecord.id)",
                kind: sourceEvidenceRecord.evidenceKind,
                summary: sourceEvidenceRecord.sourceQuote,
                sourceOwnerRef: sourceEvidenceRecord.sourceOwnerRef,
                candidateRef: sourceEvidenceRecord.candidateRef
            ))
        }
        return CiderDueToSurfaceCandidate(
            id: "review:\(item.id)",
            family: .reviewItem,
            owner: owner,
            title: item.title,
            itemType: item.itemType,
            whyNow: item.reason,
            reasonCodes: Array(Set(item.reasonCodes + [item.kind, "reviewable_candidate"])).sorted(),
            urgency: reviewUrgency(severity: item.kind, priority: item.createdAt.timeIntervalSince1970),
            window: CiderDueToSurfaceWindow(label: "review queue", startsAt: item.createdAt, endsAt: nil),
            confidence: item.confidence ?? 0.6,
            reviewState: item.reviewState,
            truthBoundary: "reviewable_candidate_not_truth",
            score: 75,
            sourceRefs: [owner.canonicalRef] + [candidateRef].compactMap { $0 },
            citedEvidence: evidence,
            safeNextCommands: item.safeNextCommands.isEmpty ? ["cider-cli capture review-queue --limit 20 --json"] : item.safeNextCommands
        )
    }

    private static func staleCaptureCandidate(_ capture: CiderDueToSurfaceStaleCapture, now: Date) -> CiderDueToSurfaceCandidate {
        CiderDueToSurfaceCandidate(
            id: "stale_capture:\(capture.owner.canonicalRef)",
            family: .staleCapture,
            owner: capture.owner,
            title: capture.title,
            itemType: capture.itemType,
            whyNow: "Unfiled capture has aged in an inbox/review state.",
            reasonCodes: Array(Set(capture.reasonCodes + ["stale_capture"])).sorted(),
            urgency: "review",
            window: CiderDueToSurfaceWindow(label: "stale since capture", startsAt: capture.createdAt, endsAt: now),
            confidence: 0.7,
            reviewState: "suggested",
            truthBoundary: "reviewable_candidate_not_truth",
            score: 65,
            sourceRefs: [capture.owner.canonicalRef],
            citedEvidence: [
                CiderDueToSurfaceEvidence(
                    ref: capture.owner.canonicalRef,
                    kind: "stale_unfiled_capture",
                    summary: capture.relativePath ?? capture.title,
                    sourceOwnerRef: capture.owner.canonicalRef,
                    candidateRef: nil
                ),
            ],
            safeNextCommands: [
                "cider-cli item context \(capture.itemType) \(capture.owner.ownerID) --json",
                "cider-cli capture review-queue --limit 20 --json",
            ]
        )
    }

    private static func linkedContextCandidate(_ linked: CiderDueToSurfaceLinkedContext, now: Date) -> CiderDueToSurfaceCandidate {
        var evidence = [
            CiderDueToSurfaceEvidence(
                ref: linked.evidenceRef ?? "linked_context:\(linked.id)",
                kind: "linked_context_signal",
                summary: linked.reason,
                sourceOwnerRef: linked.sourceOwner.canonicalRef,
                candidateRef: "similarity_candidate:\(linked.id)",
                metadata: ["targetOwnerRef": linked.targetOwner.canonicalRef]
            ),
        ]
        if let evidenceRef = linked.evidenceRef, evidenceRef.hasPrefix("source_evidence:") {
            evidence[0].kind = "source_evidence"
        }
        return CiderDueToSurfaceCandidate(
            id: "linked_context:\(linked.id)",
            family: .linkedContext,
            owner: linked.sourceOwner,
            title: linked.title,
            itemType: linked.sourceOwner.ownerType,
            whyNow: linked.reason,
            reasonCodes: Array(Set(linked.reasonCodes + ["linked_context"])).sorted(),
            urgency: "context",
            window: CiderDueToSurfaceWindow(label: "link candidate", startsAt: now, endsAt: nil),
            confidence: linked.confidence,
            reviewState: linked.reviewState,
            truthBoundary: "reviewable_candidate_not_truth",
            score: 55 + linked.confidence,
            sourceRefs: [linked.sourceOwner.canonicalRef, linked.targetOwner.canonicalRef],
            citedEvidence: evidence,
            safeNextCommands: linked.safeNextCommands
        )
    }

    private static func urgencyScore(_ urgency: String) -> Double {
        switch urgency {
        case "overdue": return 100
        case "today": return 90
        case "review": return 70
        case "upcoming": return 60
        case "context": return 50
        default: return 40
        }
    }

    private static func reviewUrgency(severity: String, priority: TimeInterval) -> String { "review" }

    static func groupedFamilyCounts(_ candidates: [CiderDueToSurfaceCandidate]) -> [String: Int] {
        groupedCounts(candidates.map { $0.family.rawValue })
    }

    private static func groupedCounts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in counts[value, default: 0] += 1 }
    }
}
