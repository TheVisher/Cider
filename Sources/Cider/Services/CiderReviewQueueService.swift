import Foundation

struct CiderReviewQueueResult: Equatable {
    var command: String
    var generatedAt: Date
    var items: [CiderReviewQueueItem]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "count": items.count,
            "items": items.map { $0.toDictionary() },
        ]
    }
}

struct CiderCaptureReviewWorklistResult: Equatable {
    var command: String = "capture.review-queue"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var totalCount: Int
    var items: [CiderCaptureReviewWorklistItem]
    var countsByReasonCode: [String: Int]
    var countsByKind: [String: Int]
    var safeNextCommands: [String]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "ok": true,
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "readOnly": readOnly,
            "changed": changed,
            "totalCount": totalCount,
            "count": items.count,
            "countsByReasonCode": countsByReasonCode,
            "countsByKind": countsByKind,
            "items": items.map { $0.toDictionary() },
            "safeNextCommands": safeNextCommands,
        ]
    }
}

struct CiderReviewQueueSourceEvidenceRecord: Equatable {
    var id: String
    var evidenceKind: String
    var sourceOwnerRef: String
    var sourceQuote: String
    var spanStart: Int? = nil
    var spanEnd: Int? = nil
    var extractionSource: String
    var derivedOwnerRef: String
    var derivedKind: String
    var candidateRef: String? = nil

    init(record: SecondBrainSourceEvidenceRecord) {
        id = record.id
        evidenceKind = record.evidenceKind
        sourceOwnerRef = record.sourceOwnerRef
        sourceQuote = record.sourceQuote
        spanStart = record.spanStart
        spanEnd = record.spanEnd
        extractionSource = record.extractionSource
        derivedOwnerRef = record.derivedOwnerRef
        derivedKind = record.derivedKind
        candidateRef = record.candidateRef
    }

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": id,
            "ref": "source_evidence:\(id)",
            "evidenceKind": evidenceKind,
            "sourceOwnerRef": sourceOwnerRef,
            "sourceQuote": sourceQuote,
            "extractionSource": extractionSource,
            "derivedOwnerRef": derivedOwnerRef,
            "derivedKind": derivedKind,
        ]
        if let spanStart { dictionary["spanStart"] = spanStart }
        if let spanEnd { dictionary["spanEnd"] = spanEnd }
        if let candidateRef { dictionary["candidateRef"] = candidateRef }
        return dictionary
    }
}

struct CiderReviewQueueLifecycleEventRecord: Equatable {
    var id: String
    var candidateRef: String?
    var lifecycleState: String
    var eventKind: String
    var actor: String
    var source: String
    var toolName: String?
    var reason: String?
    var sourceEvidenceRef: String?
    var createdAt: Date

    init(_ event: SecondBrainReviewLifecycleEvent) {
        self.id = event.id
        self.candidateRef = event.candidateRef
        self.lifecycleState = event.lifecycleState
        self.eventKind = event.eventKind
        self.actor = event.actor
        self.source = event.source
        self.toolName = event.toolName
        self.reason = event.reason
        self.sourceEvidenceRef = event.sourceEvidenceRef
        self.createdAt = event.createdAt
    }

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": id,
            "lifecycleState": lifecycleState,
            "eventKind": eventKind,
            "actor": actor,
            "source": source,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "truthBoundary": lifecycleState == "accepted" ? "accepted_truth_requires_explicit_event" : "reviewable_candidate_not_truth",
        ]
        if let candidateRef { dictionary["candidateRef"] = candidateRef }
        if let toolName { dictionary["toolName"] = toolName }
        if let reason { dictionary["reason"] = reason }
        if let sourceEvidenceRef { dictionary["sourceEvidenceRef"] = sourceEvidenceRef }
        return dictionary
    }
}

struct CiderGraphCandidateTargetOption: Equatable {
    var optionRef: String
    var label: String
    var targetOwner: SecondBrainOwnerRef
    var relationType: String
    var targetKind: String
    var sourceQuote: String
    var sourceItemRef: String
    var evidenceRefs: [String]
    var confidence: Double?
    var provenanceRefs: [String] = []
    var sourceRefs: [String] = []
    var externalIDs: [String: String] = [:]
    var selectionRequired: Bool = true
    var correctionAllowed: Bool = true

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "optionRef": optionRef,
            "label": label,
            "targetOwner": [
                "ownerType": targetOwner.ownerType,
                "ownerID": targetOwner.ownerID,
                "ref": targetOwner.canonicalRef,
            ],
            "relationType": relationType,
            "targetKind": targetKind,
            "sourceQuote": sourceQuote,
            "sourceItemRef": sourceItemRef,
            "evidenceRefs": evidenceRefs,
            "selectionRequired": selectionRequired,
            "correctionAllowed": correctionAllowed,
            "truthState": "reviewable_candidate_not_truth",
            "reviewSafety": [
                "reviewable_candidate_not_truth",
                "accept_requires_explicit_target_option_or_correction",
                "no_hidden_guess_promotion",
            ],
        ]
        if let confidence {
            dictionary["confidence"] = confidence
        }
        if !provenanceRefs.isEmpty {
            dictionary["provenanceRefs"] = provenanceRefs
        }
        if !sourceRefs.isEmpty {
            dictionary["sourceRefs"] = sourceRefs
        }
        if !externalIDs.isEmpty {
            dictionary["externalIDs"] = externalIDs
        }
        return dictionary
    }
}

struct CiderCaptureReviewWorklistItem: Identifiable, Equatable {
    var id: String
    var kind: String
    var source: String
    var ownerType: String
    var ownerID: String
    var itemID: UUID?
    var itemType: String
    var title: String
    var relativePath: String?
    var reason: String
    var reasonCodes: [String]
    var severity: String
    var priority: Int
    var reviewState: String
    var provenance: [String: String]
    var routingState: [String: String]?
    var indexingStatus: String?
    var enrichmentStatus: String?
    var attachmentSummary: [String: String]?
    var createdAt: Date
    var safeNextCommands: [String]
    var confidence: Double? = nil
    var candidateID: String? = nil
    var candidateRef: String? = nil
    var sourceQuote: String? = nil
    var possibleTypes: [String] = []
    var possibleRelations: [String] = []
    var candidateActions: [String] = []
    var memoryKind: String? = nil
    var linkedOwnerRefs: [String] = []
    var observedDate: String? = nil
    var memoryKey: String? = nil
    var memoryStatus: String? = nil
    var proposedDate: String? = nil
    var eventLabel: String? = nil
    var factKind: String? = nil
    var targetRef: String? = nil
    var factConfidence: String? = nil
    var reviewFamily: String? = nil
    var sourceItemRef: String? = nil
    var sourceItemTitle: String? = nil
    var sourceItemDate: String? = nil
    var extractionReason: String? = nil
    var proposedChange: [String: String] = [:]
    var storage: [String: String] = [:]
    var truthState: String? = nil
    var acceptEffect: String? = nil
    var rejectEffect: String? = nil
    var candidateQualityLevel: String? = nil
    var candidateQualityCodes: [String] = []
    var candidateQualityExplanation: String? = nil
    var sourceEvidenceRecord: CiderReviewQueueSourceEvidenceRecord? = nil
    var lifecycleHistory: [CiderReviewQueueLifecycleEventRecord] = []
    var targetOptions: [CiderGraphCandidateTargetOption] = []
    var routeIntents: [CiderCaptureResult.RouteIntent] = []

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "id": id,
            "kind": kind,
            "source": source,
            "owner": [
                "ownerType": ownerType,
                "ownerID": ownerID,
                "ref": "\(ownerType):\(ownerID)",
            ],
            "itemType": itemType,
            "title": title,
            "reason": reason,
            "reasonCodes": reasonCodes,
            "severity": severity,
            "priority": priority,
            "reviewState": reviewState,
            "provenance": provenance,
            "createdAt": formatter.string(from: createdAt),
            "safeNextCommands": safeNextCommands,
        ]
        if let itemID {
            dictionary["itemID"] = itemID.uuidString
        }
        if let relativePath {
            dictionary["relativePath"] = relativePath
        }
        if let routingState {
            dictionary["routingState"] = routingStateDictionary(from: routingState)
        }
        if let indexingStatus {
            dictionary["indexingStatus"] = indexingStatus
        }
        if let enrichmentStatus {
            dictionary["enrichmentStatus"] = enrichmentStatus
        }
        if let attachmentSummary {
            dictionary["attachmentSummary"] = attachmentSummary
        }
        if let confidence {
            dictionary["confidence"] = confidence
        }
        if let candidateID {
            dictionary["candidateID"] = candidateID
        }
        if let candidateRef {
            dictionary["candidateRef"] = candidateRef
        }
        if let sourceQuote {
            dictionary["sourceQuote"] = sourceQuote
        }
        if !possibleTypes.isEmpty {
            dictionary["possibleTypes"] = possibleTypes
        }
        if !possibleRelations.isEmpty {
            dictionary["possibleRelations"] = possibleRelations
        }
        if !candidateActions.isEmpty {
            dictionary["candidateActions"] = candidateActions
        }
        if let memoryKind {
            dictionary["memoryKind"] = memoryKind
        }
        if !linkedOwnerRefs.isEmpty {
            dictionary["linkedOwnerRefs"] = linkedOwnerRefs
        }
        if let observedDate {
            dictionary["observedDate"] = observedDate
        }
        if let memoryKey {
            dictionary["memoryKey"] = memoryKey
        }
        if let memoryStatus {
            dictionary["memoryStatus"] = memoryStatus
        }
        if let proposedDate { dictionary["proposedDate"] = proposedDate }
        if let eventLabel { dictionary["eventLabel"] = eventLabel }
        if let factKind { dictionary["factKind"] = factKind }
        if let targetRef { dictionary["targetRef"] = targetRef }
        if let factConfidence { dictionary["factConfidence"] = factConfidence }
        if let reviewFamily { dictionary["reviewFamily"] = reviewFamily }
        if let sourceItemRef { dictionary["sourceItemRef"] = sourceItemRef }
        if let sourceItemTitle { dictionary["sourceItemTitle"] = sourceItemTitle }
        if let sourceItemDate { dictionary["sourceItemDate"] = sourceItemDate }
        if let extractionReason { dictionary["extractionReason"] = extractionReason }
        if !proposedChange.isEmpty { dictionary["proposedChange"] = proposedChange }
        if !storage.isEmpty { dictionary["storage"] = storage }
        if let sourceEvidenceRecord { dictionary["sourceEvidenceRecord"] = sourceEvidenceRecord.toDictionary() }
        if !lifecycleHistory.isEmpty { dictionary["lifecycleHistory"] = lifecycleHistory.map { $0.toDictionary() } }
        if !targetOptions.isEmpty { dictionary["targetOptions"] = targetOptions.map { $0.toDictionary() } }
        if !routeIntents.isEmpty {
            let intents = routeIntents.map { $0.toDictionary() }
            dictionary["routeIntents"] = intents
            dictionary["routeIntent"] = intents[0]
        }
        if let truthState { dictionary["truthState"] = truthState }
        if let acceptEffect { dictionary["acceptEffect"] = acceptEffect }
        if let rejectEffect { dictionary["rejectEffect"] = rejectEffect }
        if candidateQualityLevel != nil || !candidateQualityCodes.isEmpty || candidateQualityExplanation != nil {
            var quality: [String: Any] = [:]
            if let candidateQualityLevel { quality["level"] = candidateQualityLevel }
            if !candidateQualityCodes.isEmpty { quality["codes"] = candidateQualityCodes }
            if let candidateQualityExplanation { quality["explanation"] = candidateQualityExplanation }
            dictionary["quality"] = quality
            dictionary["qualityFlags"] = candidateQualityCodes
        }
        CiderAgentDecisionContract.merge(agentDecisionDictionary(), into: &dictionary)
        return dictionary
    }

    private func routingStateDictionary(from state: [String: String]) -> [String: Any] {
        var dictionary: [String: Any] = state
        if let confidence = state["confidence"].flatMap(Double.init) {
            dictionary["confidence"] = confidence
        }
        return dictionary
    }

    private func agentDecisionDictionary() -> [String: Any] {
        let needsReview = reviewState == "needs_review" || reviewState == "suggested"
        let needsRouting = kind == "low_confidence_routing"
            || reasonCodes.contains(where: { $0.hasPrefix("routing_") || $0 == "inbox_unrouted" })
            || routingState != nil
        let needsEnrichment = kind == "enrichment"
            || reasonCodes.contains(where: { $0.hasPrefix("enrichment_") })
            || enrichmentStatus == "needs_review"
        let confidence = confidence ?? routingState?["confidence"].flatMap(Double.init)
        let recommendedAction: String
        switch kind {
        case "graph_candidate":
            recommendedAction = "review_graph_candidate"
        case "memory_candidate":
            recommendedAction = "review_memory_candidate"
        case "event_date_fact":
            recommendedAction = "review_event_date_fact"
        default:
            recommendedAction = needsReview ? "review_route" : "inspect_item"
        }
        return CiderAgentDecisionContract.dictionary(
            saved: true,
            needsReview: needsReview,
            needsEnrichment: needsEnrichment,
            needsRouting: needsRouting,
            confidence: confidence,
            blockingIssues: reasonCodes,
            recommendedNextAction: recommendedAction,
            safeNextCommands: safeNextCommands
        )
    }
}

struct CiderReviewQueueSummaryResult: Equatable {
    var command: String
    var generatedAt: Date
    var totalCount: Int
    var countsByKind: [String: Int]
    var countsByItemType: [String: Int]
    var countsByReviewState: [String: Int]
    var countsBySafeAction: [String: Int]
    var groups: [CiderReviewQueueGroup] = []
    var batchEnrichmentPreview: CiderReviewQueueBatchEnrichmentPreview = .empty

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "totalCount": totalCount,
            "countsByKind": countsByKind,
            "countsByItemType": countsByItemType,
            "countsByReviewState": countsByReviewState,
            "countsBySafeAction": countsBySafeAction,
            "groups": groups.map { $0.toDictionary() },
            "batchEnrichmentPreview": batchEnrichmentPreview.toDictionary(),
        ]
    }
}

struct CiderReviewQueueGroup: Equatable {
    var id: String
    var kind: String
    var reviewState: String
    var requiredSafeAction: String
    var itemType: String
    var count: Int
    var sampleItems: [CiderReviewQueueItem]

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "kind": kind,
            "reviewState": reviewState,
            "requiredSafeAction": requiredSafeAction,
            "itemType": itemType,
            "count": count,
            "sampleItems": sampleItems.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewQueueDrilldownResult: Equatable {
    var command: String
    var generatedAt: Date
    var groupID: String
    var kind: String
    var reviewState: String
    var requiredSafeAction: String
    var itemType: String
    var totalCount: Int
    var limit: Int
    var offset: Int
    var hasMore: Bool
    var items: [CiderReviewQueueItem]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "groupID": groupID,
            "kind": kind,
            "reviewState": reviewState,
            "requiredSafeAction": requiredSafeAction,
            "itemType": itemType,
            "totalCount": totalCount,
            "count": items.count,
            "limit": limit,
            "offset": offset,
            "hasMore": hasMore,
            "items": items.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewQueueBatchEnrichmentPreview: Equatable {
    static let empty = CiderReviewQueueBatchEnrichmentPreview(
        action: "review.enrich",
        isMutating: false,
        candidateCount: 0,
        candidateSampleLimit: 0,
        candidateSamples: [],
        excludedCount: 0,
        exclusionsByReason: [:]
    )

    var action: String
    var isMutating: Bool
    var candidateCount: Int
    var candidateSampleLimit: Int
    var candidateSamples: [CiderReviewQueueItem]
    var excludedCount: Int
    var exclusionsByReason: [String: Int]

    func toDictionary() -> [String: Any] {
        [
            "action": action,
            "isMutating": isMutating,
            "candidateCount": candidateCount,
            "candidateSampleLimit": candidateSampleLimit,
            "candidateSamples": candidateSamples.map { $0.toDictionary() },
            "excludedCount": excludedCount,
            "exclusionsByReason": exclusionsByReason,
        ]
    }
}

struct CiderReviewEnrichmentDiagnosisResult: Equatable {
    var command: String = "review.enrichment.diagnosis"
    var generatedAt: Date
    var isMutating: Bool = false
    var totalCandidateCount: Int
    var sampleLimit: Int
    var groups: [CiderReviewEnrichmentDiagnosisGroup]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "isMutating": isMutating,
            "totalCandidateCount": totalCandidateCount,
            "sampleLimit": sampleLimit,
            "groups": groups.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewEnrichmentDiagnosisGroup: Equatable {
    var id: String
    var summary: String
    var count: Int
    var sampleItems: [CiderReviewEnrichmentDiagnosisItem]

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "summary": summary,
            "count": count,
            "sampleItems": sampleItems.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewEnrichmentDiagnosisItem: Equatable {
    var itemID: UUID
    var title: String
    var relativePath: String?
    var enrichmentStatus: String?
    var lastEnrichedAt: Date?
    var diagnosisReason: String

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "itemID": itemID.uuidString,
            "title": title,
            "diagnosisReason": diagnosisReason,
        ]
        if let relativePath {
            dictionary["relativePath"] = relativePath
        }
        if let enrichmentStatus {
            dictionary["enrichmentStatus"] = enrichmentStatus
        }
        if let lastEnrichedAt {
            dictionary["lastEnrichedAt"] = formatter.string(from: lastEnrichedAt)
        }
        return dictionary
    }
}

struct CiderReviewEnrichmentReconciliationPlanResult: Equatable {
    var command: String = "review.enrichment.reconciliationPlan"
    var generatedAt: Date
    var isMutating: Bool = false
    var approvalRequired: Bool = true
    var totalCandidateCount: Int
    var proposedChangeCount: Int
    var blockedCount: Int
    var sampleLimit: Int
    var groups: [CiderReviewEnrichmentReconciliationPlanGroup]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "isMutating": isMutating,
            "approvalRequired": approvalRequired,
            "totalCandidateCount": totalCandidateCount,
            "proposedChangeCount": proposedChangeCount,
            "blockedCount": blockedCount,
            "sampleLimit": sampleLimit,
            "groups": groups.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewEnrichmentReconciliationPlanGroup: Equatable {
    var id: String
    var summary: String
    var count: Int
    var proposedChangeCount: Int
    var blockedCount: Int
    var sampleItems: [CiderReviewEnrichmentReconciliationPlanItem]

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "summary": summary,
            "count": count,
            "proposedChangeCount": proposedChangeCount,
            "blockedCount": blockedCount,
            "sampleItems": sampleItems.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewEnrichmentReconciliationSampleResult: Equatable {
    var command: String = "review.enrichment.reconciliationSamples"
    var generatedAt: Date
    var isMutating: Bool = false
    var approvalRequired: Bool = true
    var groupID: String?
    var totalCandidateCount: Int
    var matchingCandidateCount: Int
    var limit: Int
    var sampleItems: [CiderReviewEnrichmentReconciliationPlanItem]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "isMutating": isMutating,
            "approvalRequired": approvalRequired,
            "totalCandidateCount": totalCandidateCount,
            "matchingCandidateCount": matchingCandidateCount,
            "limit": limit,
            "sampleItems": sampleItems.map { $0.toDictionary() },
        ]
        if let groupID {
            dictionary["groupID"] = groupID
        }
        return dictionary
    }
}

struct CiderReviewEnrichmentReconciliationApplyResult: Equatable {
    var command: String = "review.enrichment.reconciliationApply"
    var generatedAt: Date
    var status: String
    var actor: String
    var isMutating: Bool
    var approvalRequired: Bool = true
    var requiredApprovalToken: String
    var groupID: String?
    var limit: Int
    var totalCandidateCount: Int
    var matchingCandidateCount: Int
    var proposedChangeCount: Int
    var selectedCount: Int
    var projectedRemainingCandidateCount: Int
    var appliedCount: Int
    var skippedCount: Int
    var blockers: [String]
    var selectedItems: [CiderReviewEnrichmentReconciliationPlanItem]
    var appliedItems: [CiderReviewEnrichmentReconciliationPlanItem]
    var safeActions: [String] = ["review summary", "review enrichment-reconcile-plan", "review enrichment-reconcile-samples"]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "status": status,
            "actor": actor,
            "isMutating": isMutating,
            "approvalRequired": approvalRequired,
            "requiredApprovalToken": requiredApprovalToken,
            "limit": limit,
            "totalCandidateCount": totalCandidateCount,
            "matchingCandidateCount": matchingCandidateCount,
            "proposedChangeCount": proposedChangeCount,
            "selectedCount": selectedCount,
            "projectedRemainingCandidateCount": projectedRemainingCandidateCount,
            "appliedCount": appliedCount,
            "skippedCount": skippedCount,
            "blockers": blockers,
            "selectedItems": selectedItems.map { $0.toDictionary() },
            "appliedItems": appliedItems.map { $0.toDictionary() },
            "safeActions": safeActions,
        ]
        if let groupID {
            dictionary["groupID"] = groupID
        }
        return dictionary
    }
}

struct CiderReviewEnrichmentReconciliationPlanItem: Equatable {
    var groupID: String = ""
    var itemID: UUID
    var title: String
    var url: String = ""
    var relativePath: String?
    var currentStatus: String?
    var currentLastEnrichedAt: Date?
    var proposedStatus: String?
    var proposedLastEnrichedAt: Date?
    var proposalReason: String
    var evidence: [String]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "groupID": groupID,
            "itemID": itemID.uuidString,
            "title": title,
            "url": url,
            "proposalReason": proposalReason,
            "evidence": evidence,
        ]
        if let relativePath {
            dictionary["relativePath"] = relativePath
        }
        if let currentStatus {
            dictionary["currentStatus"] = currentStatus
        }
        if let currentLastEnrichedAt {
            dictionary["currentLastEnrichedAt"] = formatter.string(from: currentLastEnrichedAt)
        }
        if let proposedStatus {
            dictionary["proposedStatus"] = proposedStatus
        }
        if let proposedLastEnrichedAt {
            dictionary["proposedLastEnrichedAt"] = formatter.string(from: proposedLastEnrichedAt)
        }
        return dictionary
    }
}

struct CiderReviewQueueItem: Identifiable, Equatable {
    var id: String
    var kind: String
    var source: String
    var itemID: UUID
    var itemType: String
    var title: String
    var relativePath: String?
    var reason: String
    var reasonCodes: [String] = []
    var suggestedAction: String
    var reviewState: String
    var confidence: Double?
    var confidenceReason: String? = nil
    var routingDecisionID: UUID?
    var target: CiderRoutingDecisionTarget?
    var createdAt: Date
    var safeActions: [String]
    var candidateID: String? = nil
    var candidateRef: String? = nil
    var sourceQuote: String? = nil
    var possibleTypes: [String] = []
    var possibleRelations: [String] = []
    var candidateActions: [String] = []
    var memoryKind: String? = nil
    var linkedOwnerRefs: [String] = []
    var observedDate: String? = nil
    var memoryKey: String? = nil
    var memoryStatus: String? = nil
    var proposedDate: String? = nil
    var eventLabel: String? = nil
    var factKind: String? = nil
    var targetRef: String? = nil
    var factConfidence: String? = nil
    var safeNextCommands: [String] = []
    var reviewFamily: String? = nil
    var sourceItemRef: String? = nil
    var sourceItemTitle: String? = nil
    var sourceItemDate: String? = nil
    var extractionReason: String? = nil
    var proposedChange: [String: String] = [:]
    var storage: [String: String] = [:]
    var truthState: String? = nil
    var acceptEffect: String? = nil
    var rejectEffect: String? = nil
    var candidateQualityLevel: String? = nil
    var candidateQualityCodes: [String] = []
    var candidateQualityExplanation: String? = nil
    var sourceEvidenceRecord: CiderReviewQueueSourceEvidenceRecord? = nil
    var lifecycleHistory: [CiderReviewQueueLifecycleEventRecord] = []
    var targetOptions: [CiderGraphCandidateTargetOption] = []
    var routeIntents: [CiderCaptureResult.RouteIntent] = []

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "id": id,
            "kind": kind,
            "source": source,
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "reason": reason,
            "reasonCodes": reasonCodes,
            "suggestedAction": suggestedAction,
            "reviewState": reviewState,
            "createdAt": formatter.string(from: createdAt),
            "safeActions": safeActions,
        ]
        if let relativePath {
            dictionary["relativePath"] = relativePath
        }
        if let confidence {
            dictionary["confidence"] = confidence
        }
        if let confidenceReason {
            dictionary["confidenceReason"] = confidenceReason
        }
        if let routingDecisionID {
            dictionary["routingDecisionID"] = routingDecisionID.uuidString
        }
        if let target {
            dictionary["target"] = target.toDictionary()
        }
        if let candidateID {
            dictionary["candidateID"] = candidateID
        }
        if let candidateRef {
            dictionary["candidateRef"] = candidateRef
        }
        if let sourceQuote {
            dictionary["sourceQuote"] = sourceQuote
        }
        if !possibleTypes.isEmpty {
            dictionary["possibleTypes"] = possibleTypes
        }
        if !possibleRelations.isEmpty {
            dictionary["possibleRelations"] = possibleRelations
        }
        if !candidateActions.isEmpty {
            dictionary["candidateActions"] = candidateActions
        }
        if let memoryKind {
            dictionary["memoryKind"] = memoryKind
        }
        if !linkedOwnerRefs.isEmpty {
            dictionary["linkedOwnerRefs"] = linkedOwnerRefs
        }
        if let observedDate {
            dictionary["observedDate"] = observedDate
        }
        if let memoryKey {
            dictionary["memoryKey"] = memoryKey
        }
        if let memoryStatus {
            dictionary["memoryStatus"] = memoryStatus
        }
        if let proposedDate { dictionary["proposedDate"] = proposedDate }
        if let eventLabel { dictionary["eventLabel"] = eventLabel }
        if let factKind { dictionary["factKind"] = factKind }
        if let targetRef { dictionary["targetRef"] = targetRef }
        if let factConfidence { dictionary["factConfidence"] = factConfidence }
        if let reviewFamily { dictionary["reviewFamily"] = reviewFamily }
        if let sourceItemRef { dictionary["sourceItemRef"] = sourceItemRef }
        if let sourceItemTitle { dictionary["sourceItemTitle"] = sourceItemTitle }
        if let sourceItemDate { dictionary["sourceItemDate"] = sourceItemDate }
        if let extractionReason { dictionary["extractionReason"] = extractionReason }
        if !proposedChange.isEmpty { dictionary["proposedChange"] = proposedChange }
        if !storage.isEmpty { dictionary["storage"] = storage }
        if let sourceEvidenceRecord { dictionary["sourceEvidenceRecord"] = sourceEvidenceRecord.toDictionary() }
        if !lifecycleHistory.isEmpty { dictionary["lifecycleHistory"] = lifecycleHistory.map { $0.toDictionary() } }
        if !targetOptions.isEmpty { dictionary["targetOptions"] = targetOptions.map { $0.toDictionary() } }
        if !routeIntents.isEmpty {
            let intents = routeIntents.map { $0.toDictionary() }
            dictionary["routeIntents"] = intents
            dictionary["routeIntent"] = intents[0]
        }
        if let truthState { dictionary["truthState"] = truthState }
        if let acceptEffect { dictionary["acceptEffect"] = acceptEffect }
        if let rejectEffect { dictionary["rejectEffect"] = rejectEffect }
        if candidateQualityLevel != nil || !candidateQualityCodes.isEmpty || candidateQualityExplanation != nil {
            var quality: [String: Any] = [:]
            if let candidateQualityLevel { quality["level"] = candidateQualityLevel }
            if !candidateQualityCodes.isEmpty { quality["codes"] = candidateQualityCodes }
            if let candidateQualityExplanation { quality["explanation"] = candidateQualityExplanation }
            dictionary["quality"] = quality
            dictionary["qualityFlags"] = candidateQualityCodes
        }
        if !safeNextCommands.isEmpty {
            dictionary["safeNextCommands"] = safeNextCommands
        }
        return dictionary
    }
}

struct CiderReviewQueueActionResult: Equatable {
    var action: String
    var itemID: UUID
    var itemType: String
    var title: String
    var status: String
    var message: String
    var actor: String
    var safeActions: [String]

    func toDictionary() -> [String: Any] {
        [
            "action": action,
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "status": status,
            "message": message,
            "actor": actor,
            "safeActions": safeActions,
        ]
    }
}

struct CiderReviewRoutingActionResult: Equatable {
    var action: String
    var itemID: UUID
    var itemType: String
    var title: String
    var status: String
    var message: String
    var actor: String
    var reviewState: String
    var routingDecisionID: UUID
    var supersedesDecisionID: UUID?
    var target: CiderRoutingDecisionTarget
    var remainingActiveRoutingReviewCount: Int
    var safeActions: [String]

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "action": action,
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "status": status,
            "message": message,
            "actor": actor,
            "reviewState": reviewState,
            "routingDecisionID": routingDecisionID.uuidString,
            "target": target.toDictionary(),
            "remainingActiveRoutingReviewCount": remainingActiveRoutingReviewCount,
            "safeActions": safeActions,
        ]
        if let supersedesDecisionID {
            dictionary["supersedesDecisionID"] = supersedesDecisionID.uuidString
        }
        return dictionary
    }
}

struct CiderReviewCandidateQueueActionResult {
    var command: String
    var action: String
    var candidateID: String
    var candidateRef: String
    var reviewFamily: String
    var reviewState: String
    var truthBoundary: String
    var beforeState: String?
    var afterState: String
    var changed: Bool
    var actor: String
    var provenance: [String: Any]
    var actionReceipt: [String: Any]
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "ok": true,
            "command": command,
            "action": action,
            "readOnly": false,
            "changed": changed,
            "candidateID": candidateID,
            "candidateRef": candidateRef,
            "reviewFamily": reviewFamily,
            "reviewState": reviewState,
            "truthBoundary": truthBoundary,
            "afterState": afterState,
            "actor": actor,
            "provenance": provenance,
            "actionReceipt": actionReceipt,
            "safeVerificationCommands": safeVerificationCommands,
            "safeNextCommands": safeNextCommands,
        ]
        if let beforeState {
            dictionary["beforeState"] = beforeState
        }
        return dictionary
    }
}

struct CiderReviewQueueBatchEnrichmentFailure: Equatable {
    var itemID: UUID
    var itemType: String
    var title: String
    var reason: String

    func toDictionary() -> [String: Any] {
        [
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "reason": reason,
        ]
    }
}

struct CiderReviewQueueBatchEnrichmentResult: Equatable {
    var action: String
    var batchID: UUID
    var generatedAt: Date
    var actor: String
    var isMutating: Bool
    var candidateCount: Int
    var scheduledCount: Int
    var excludedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var exclusionsByReason: [String: Int]
    var failures: [CiderReviewQueueBatchEnrichmentFailure]
    var safeActions: [String]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "action": action,
            "batchID": batchID.uuidString,
            "generatedAt": formatter.string(from: generatedAt),
            "actor": actor,
            "isMutating": isMutating,
            "candidateCount": candidateCount,
            "scheduledCount": scheduledCount,
            "excludedCount": excludedCount,
            "skippedCount": skippedCount,
            "failedCount": failedCount,
            "exclusionsByReason": exclusionsByReason,
            "failures": failures.map { $0.toDictionary() },
            "safeActions": safeActions,
        ]
    }
}

struct CiderReviewActionJobHistoryResult: Equatable {
    var command: String
    var generatedAt: Date
    var jobs: [CiderReviewActionJobSummary]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "count": jobs.count,
            "jobs": jobs.map { $0.toDictionary() },
        ]
    }
}

struct CiderReviewActionJobSummary: Equatable {
    var action: String
    var actionFamily: String
    var jobID: String
    var batchID: UUID?
    var firstScheduledAt: Date
    var lastScheduledAt: Date
    var actor: String
    var source: String
    var resultState: String
    var candidateCount: Int
    var scheduledCount: Int
    var excludedCount: Int
    var failedCount: Int
    var itemSamples: [CiderReviewActionJobItemSample]
    var safeActions: [String]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "action": action,
            "actionFamily": actionFamily,
            "jobID": jobID,
            "firstScheduledAt": formatter.string(from: firstScheduledAt),
            "lastScheduledAt": formatter.string(from: lastScheduledAt),
            "actor": actor,
            "source": source,
            "resultState": resultState,
            "candidateCount": candidateCount,
            "scheduledCount": scheduledCount,
            "excludedCount": excludedCount,
            "failedCount": failedCount,
            "itemSamples": itemSamples.map { $0.toDictionary() },
            "safeActions": safeActions,
        ]
        if let batchID {
            dictionary["batchID"] = batchID.uuidString
        }
        return dictionary
    }
}

struct CiderReviewActionJobItemSample: Equatable {
    var itemID: UUID
    var itemType: String
    var title: String
    var status: String

    func toDictionary() -> [String: Any] {
        [
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "status": status,
        ]
    }
}

enum CiderReviewQueueActionError: Error, LocalizedError {
    case itemNotFound(UUID)
    case unsupportedItemType(String)
    case noEnrichmentIssue(UUID)

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "No review item found for \(id.uuidString)."
        case .unsupportedItemType(let type):
            return "Review enrichment is only supported for bookmarks, not \(type)."
        case .noEnrichmentIssue(let id):
            return "No active enrichment review issue found for \(id.uuidString)."
        }
    }
}

@MainActor
final class CiderReviewQueueService {
    private let database: CiderDatabase?
    private let routingDecisionService: CiderRoutingDecisionService
    private let enrichmentScheduler: (UUID) -> Void
    private let duplicateFindingsProvider: () -> [VaultDuplicateAuditor.Finding]

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(
        database: CiderDatabase? = nil,
        routingDecisionService: CiderRoutingDecisionService? = nil,
        enrichmentScheduler: ((UUID) -> Void)? = nil,
        duplicateFindingsProvider: (() -> [VaultDuplicateAuditor.Finding])? = nil
    ) {
        self.database = database
        self.routingDecisionService = routingDecisionService ?? CiderRoutingDecisionService(database: database)
        self.enrichmentScheduler = enrichmentScheduler ?? { bookmarkID in
            VaultBookmarkService.shared.refetchMetadata(for: bookmarkID)
        }
        self.duplicateFindingsProvider = duplicateFindingsProvider ?? {
            if let database, database !== CiderDatabase.shared {
                return []
            }
            return VaultDuplicateAuditor.scan()
        }
    }

    func list(
        limit: Int = 50,
        includeDeferred: Bool = false,
        kind: String? = nil,
        itemType: String? = nil,
        reviewState: String? = nil,
        requiredSafeAction: String? = nil,
        now: Date = Date()
    ) throws -> CiderReviewQueueResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let latestDecisions = try latestRoutingDecisions(in: db)
        let itemsByID = try itemSummaries(in: db)
        let bookmarkDetails = try bookmarkDetails(in: db)
        let latestByItemID = Dictionary(uniqueKeysWithValues: latestDecisions.map { ($0.itemID, $0) })

        var reviewItems: [CiderReviewQueueItem] = []
        var seenItemIDs = Set<UUID>()

        for decision in latestDecisions {
            guard shouldSurface(decision.reviewState, includeDeferred: includeDeferred),
                  let item = itemsByID[decision.itemID] else {
                continue
            }
            reviewItems.append(routingReviewItem(
                decision: decision,
                item: item,
                details: bookmarkDetails[decision.itemID]
            ))
            seenItemIDs.insert(decision.itemID)
        }

        for item in itemsByID.values where item.type == "bookmark" {
            guard !seenItemIDs.contains(item.id),
                  let details = bookmarkDetails[item.id] else {
                continue
            }
            if latestByItemID[item.id]?.reviewState == "deferred" {
                continue
            }

            if let enrichment = enrichmentReviewItem(item: item, details: details, now: now) {
                reviewItems.append(enrichment)
                seenItemIDs.insert(item.id)
                continue
            }

            if latestByItemID[item.id] == nil,
               item.folderID == nil,
               item.relativePath?.hasPrefix("Inbox/") == true {
                reviewItems.append(inboxReviewItem(item: item, details: details, now: now))
                seenItemIDs.insert(item.id)
            }
        }

        reviewItems.append(contentsOf: duplicateReviewItems(now: now))
        reviewItems.append(contentsOf: try graphCandidateReviewItems(
            in: db,
            itemsByID: itemsByID,
            includeDeferred: includeDeferred
        ))
        reviewItems.append(contentsOf: try memoryCandidateReviewItems(
            in: db,
            itemsByID: itemsByID,
            includeDeferred: includeDeferred
        ))
        reviewItems.append(contentsOf: try eventDateFactReviewItems(
            in: db,
            itemsByID: itemsByID,
            includeDeferred: includeDeferred
        ))

        let filtered = reviewItems.filter { item in
            if let kind, item.kind != kind { return false }
            if let itemType, item.itemType != itemType { return false }
            if let reviewState, item.reviewState != reviewState { return false }
            if let requiredSafeAction, !item.safeActions.contains(requiredSafeAction) { return false }
            return true
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsRank = sortRank(lhs)
            let rhsRank = sortRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return CiderReviewQueueResult(
            command: "review.list",
            generatedAt: now,
            items: Array(sorted.prefix(max(0, limit)))
        )
    }

    func summary(
        includeDeferred: Bool = false,
        batchEnrichmentSampleLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewQueueSummaryResult {
        let items = try list(
            limit: Int.max,
            includeDeferred: includeDeferred,
            now: now
        ).items

        return CiderReviewQueueSummaryResult(
            command: "review.summary",
            generatedAt: now,
            totalCount: items.count,
            countsByKind: groupedCounts(items.map(\.kind)),
            countsByItemType: groupedCounts(items.map(\.itemType)),
            countsByReviewState: groupedCounts(items.map(\.reviewState)),
            countsBySafeAction: groupedCounts(items.flatMap(\.safeActions)),
            groups: reviewGroups(for: items),
            batchEnrichmentPreview: batchEnrichmentPreview(
                for: items,
                sampleLimit: batchEnrichmentSampleLimit
            )
        )
    }

    func captureReviewWorklist(
        limit: Int = 50,
        includeDeferred: Bool = false,
        kind: String? = nil,
        itemType: String? = nil,
        reviewState: String? = nil,
        requiredSafeAction: String? = nil,
        now: Date = Date()
    ) throws -> CiderCaptureReviewWorklistResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let cappedLimit = max(0, limit)
        let reviewItems = try list(
            limit: Int.max,
            includeDeferred: includeDeferred,
            kind: kind,
            itemType: itemType,
            reviewState: reviewState,
            requiredSafeAction: requiredSafeAction,
            now: now
        ).items
            .map(captureWorklistItem(from:))
        let includeCaptureDiagnostics = kind == nil
            && itemType == nil
            && reviewState == nil
            && requiredSafeAction == nil
        let captureItems = includeCaptureDiagnostics ? try unsupportedAttachmentWorklistItems(in: db, now: now) : []
        let indexingItems = includeCaptureDiagnostics ? try indexingWorklistItems(in: db, now: now) : []
        let allItems = (reviewItems + captureItems + indexingItems).sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let page = Array(allItems.prefix(cappedLimit))
        let safeNextCommands = orderedUnique(
            [
                "cider-cli capture review-queue --limit \(cappedLimit) --json",
                "cider-cli review summary --json",
                "cider-cli item doctor --json",
            ] + page.flatMap(\.safeNextCommands)
        )
        return CiderCaptureReviewWorklistResult(
            generatedAt: now,
            totalCount: allItems.count,
            items: page,
            countsByReasonCode: groupedCounts(allItems.flatMap(\.reasonCodes)),
            countsByKind: groupedCounts(allItems.map(\.kind)),
            safeNextCommands: safeNextCommands
        )
    }

    func drilldown(
        groupID: String,
        limit: Int = 50,
        offset: Int = 0,
        now: Date = Date()
    ) throws -> CiderReviewQueueDrilldownResult {
        let parts = groupID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let kind = parts.count > 0 ? parts[0] : ""
        let reviewState = parts.count > 1 ? parts[1] : ""
        let requiredSafeAction = parts.count > 2 ? parts[2] : ""
        let itemType = parts.count > 3 ? parts[3] : ""
        let cappedLimit = max(0, limit)
        let cappedOffset = max(0, offset)
        let includeDeferred = kind == "deferred_routing" || reviewState == "deferred"
        let items = try list(
            limit: Int.max,
            includeDeferred: includeDeferred,
            kind: kind.isEmpty ? nil : kind,
            itemType: itemType.isEmpty ? nil : itemType,
            reviewState: reviewState.isEmpty ? nil : reviewState,
            requiredSafeAction: requiredSafeAction == "none" || requiredSafeAction.isEmpty ? nil : requiredSafeAction,
            now: now
        ).items.filter { item in
            groupID == "\(item.kind):\(item.reviewState):\(primarySafeAction(for: item)):\(item.itemType)"
        }
        let page = Array(items.dropFirst(cappedOffset).prefix(cappedLimit))

        return CiderReviewQueueDrilldownResult(
            command: "review.drilldown",
            generatedAt: now,
            groupID: groupID,
            kind: kind,
            reviewState: reviewState,
            requiredSafeAction: requiredSafeAction,
            itemType: itemType,
            totalCount: items.count,
            limit: cappedLimit,
            offset: cappedOffset,
            hasMore: cappedOffset + page.count < items.count,
            items: page
        )
    }

    func enrichmentDiagnosis(
        sampleLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewEnrichmentDiagnosisResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let items = try itemSummaries(in: db)
        let bookmarkDetails = try bookmarkDetails(in: db)
        let cappedLimit = max(0, sampleLimit)
        let orderedGroupIDs = [
            "missing_status",
            "never_enriched",
            "failed",
            "complete_missing_timestamp",
            "attempted_incomplete",
        ]

        var counts: [String: Int] = [:]
        var samples: [String: [CiderReviewEnrichmentDiagnosisItem]] = [:]
        var summaries: [String: String] = [:]

        for item in items.values
            .filter({ $0.type == "bookmark" })
            .sorted(by: enrichmentDiagnosisSort)
        {
            guard let details = bookmarkDetails[item.id],
                  enrichmentReviewItem(item: item, details: details, now: now) != nil else {
                continue
            }

            let reason = enrichmentDiagnosisReason(
                status: details.enrichmentStatus,
                lastEnrichedAt: details.lastEnrichedAt
            )
            counts[reason.id, default: 0] += 1
            summaries[reason.id] = reason.summary

            if samples[reason.id, default: []].count < cappedLimit {
                samples[reason.id, default: []].append(
                    CiderReviewEnrichmentDiagnosisItem(
                        itemID: item.id,
                        title: item.title,
                        relativePath: item.relativePath,
                        enrichmentStatus: details.enrichmentStatus,
                        lastEnrichedAt: details.lastEnrichedAt,
                        diagnosisReason: reason.summary
                    )
                )
            }
        }

        let groups = orderedGroupIDs.compactMap { id -> CiderReviewEnrichmentDiagnosisGroup? in
            guard let count = counts[id], count > 0 else { return nil }
            return CiderReviewEnrichmentDiagnosisGroup(
                id: id,
                summary: summaries[id] ?? id,
                count: count,
                sampleItems: samples[id] ?? []
            )
        }

        return CiderReviewEnrichmentDiagnosisResult(
            generatedAt: now,
            totalCandidateCount: counts.values.reduce(0, +),
            sampleLimit: cappedLimit,
            groups: groups
        )
    }

    func enrichmentReconciliationPlan(
        sampleLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewEnrichmentReconciliationPlanResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let items = try itemSummaries(in: db)
        let bookmarkDetails = try bookmarkDetails(in: db)
        let cappedLimit = max(0, sampleLimit)
        let orderedGroupIDs = [
            "can_mark_complete_from_ai_fields",
            "can_mark_partial_from_metadata_fields",
            "needs_enrichment_run",
        ]
        var counts: [String: Int] = [:]
        var proposedCounts: [String: Int] = [:]
        var blockedCounts: [String: Int] = [:]
        var samples: [String: [CiderReviewEnrichmentReconciliationPlanItem]] = [:]
        var summaries: [String: String] = [:]

        for item in items.values
            .filter({ $0.type == "bookmark" })
            .sorted(by: enrichmentDiagnosisSort)
        {
            guard let details = bookmarkDetails[item.id],
                  enrichmentReviewItem(item: item, details: details, now: now) != nil else {
                continue
            }

            let plan = enrichmentReconciliationProposal(item: item, details: details)
            counts[plan.groupID, default: 0] += 1
            summaries[plan.groupID] = plan.summary
            if plan.proposedStatus == nil {
                blockedCounts[plan.groupID, default: 0] += 1
            } else {
                proposedCounts[plan.groupID, default: 0] += 1
            }

            if samples[plan.groupID, default: []].count < cappedLimit {
                samples[plan.groupID, default: []].append(
                    enrichmentReconciliationPlanItem(
                        item: item,
                        details: details,
                        plan: plan
                    )
                )
            }
        }

        let groups = orderedGroupIDs.compactMap { id -> CiderReviewEnrichmentReconciliationPlanGroup? in
            guard let count = counts[id], count > 0 else { return nil }
            return CiderReviewEnrichmentReconciliationPlanGroup(
                id: id,
                summary: summaries[id] ?? id,
                count: count,
                proposedChangeCount: proposedCounts[id] ?? 0,
                blockedCount: blockedCounts[id] ?? 0,
                sampleItems: samples[id] ?? []
            )
        }

        return CiderReviewEnrichmentReconciliationPlanResult(
            generatedAt: now,
            totalCandidateCount: counts.values.reduce(0, +),
            proposedChangeCount: proposedCounts.values.reduce(0, +),
            blockedCount: blockedCounts.values.reduce(0, +),
            sampleLimit: cappedLimit,
            groups: groups
        )
    }

    func enrichmentReconciliationSamples(
        groupID: String? = nil,
        limit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewEnrichmentReconciliationSampleResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let items = try itemSummaries(in: db)
        let bookmarkDetails = try bookmarkDetails(in: db)
        let cappedLimit = max(0, limit)
        var totalCandidateCount = 0
        var matchingCandidateCount = 0
        var samples: [CiderReviewEnrichmentReconciliationPlanItem] = []

        for item in items.values
            .filter({ $0.type == "bookmark" })
            .sorted(by: enrichmentDiagnosisSort)
        {
            guard let details = bookmarkDetails[item.id],
                  enrichmentReviewItem(item: item, details: details, now: now) != nil else {
                continue
            }

            totalCandidateCount += 1
            let plan = enrichmentReconciliationProposal(item: item, details: details)
            if let groupID, plan.groupID != groupID {
                continue
            }

            matchingCandidateCount += 1
            if samples.count < cappedLimit {
                samples.append(
                    enrichmentReconciliationPlanItem(
                        item: item,
                        details: details,
                        plan: plan
                    )
                )
            }
        }

        return CiderReviewEnrichmentReconciliationSampleResult(
            generatedAt: now,
            groupID: groupID,
            totalCandidateCount: totalCandidateCount,
            matchingCandidateCount: matchingCandidateCount,
            limit: cappedLimit,
            sampleItems: samples
        )
    }

    func applyEnrichmentReconciliation(
        groupID: String? = nil,
        limit: Int = 10,
        approvalToken: String?,
        execute: Bool = false,
        actor: String = "user",
        now: Date = Date()
    ) throws -> CiderReviewEnrichmentReconciliationApplyResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let cappedLimit = max(0, limit)
        let candidates = try enrichmentReconciliationCandidates(groupID: groupID, now: now)
        let proposedCandidates = candidates.items.filter { $0.proposedStatus != nil && $0.proposedLastEnrichedAt != nil }
        let selectedCount = min(cappedLimit, proposedCandidates.count)
        let requiredApprovalToken = Self.enrichmentReconciliationApprovalToken(
            groupID: groupID,
            limit: cappedLimit,
            matchingCandidateCount: candidates.matchingCandidateCount,
            proposedChangeCount: proposedCandidates.count
        )
        var result = CiderReviewEnrichmentReconciliationApplyResult(
            generatedAt: now,
            status: execute ? "refused" : "planned",
            actor: actor,
            isMutating: false,
            requiredApprovalToken: requiredApprovalToken,
            groupID: groupID,
            limit: cappedLimit,
            totalCandidateCount: candidates.totalCandidateCount,
            matchingCandidateCount: candidates.matchingCandidateCount,
            proposedChangeCount: proposedCandidates.count,
            selectedCount: selectedCount,
            projectedRemainingCandidateCount: max(0, candidates.totalCandidateCount - selectedCount),
            appliedCount: 0,
            skippedCount: candidates.matchingCandidateCount,
            blockers: [],
            selectedItems: Array(proposedCandidates.prefix(selectedCount)),
            appliedItems: []
        )

        guard !proposedCandidates.isEmpty else {
            result.status = "refused"
            result.blockers.append("no proposed enrichment status changes are available for this selection")
            return result
        }
        guard execute else {
            result.status = "planned"
            result.blockers.append("dry-run only; pass --execute with the exact approval token to mutate")
            result.skippedCount = max(0, candidates.matchingCandidateCount - result.selectedItems.count)
            return result
        }
        guard approvalToken == requiredApprovalToken else {
            result.status = "refused"
            result.blockers.append("exact approval token required: \(requiredApprovalToken)")
            return result
        }

        for item in proposedCandidates.prefix(cappedLimit) {
            guard let proposedStatus = item.proposedStatus,
                  let proposedLastEnrichedAt = item.proposedLastEnrichedAt else {
                continue
            }
            try updateBookmarkEnrichmentStatus(
                itemID: item.itemID,
                status: proposedStatus,
                lastEnrichedAt: proposedLastEnrichedAt,
                in: db
            )
            MutationAuditService(database: db).record(
                action: "review.enrichment.reconciliationApply",
                itemType: "bookmark",
                itemID: item.itemID,
                before: [
                    "enrichmentStatus": item.currentStatus ?? "",
                    "lastEnrichedAt": item.currentLastEnrichedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                ],
                after: [
                    "enrichmentStatus": proposedStatus,
                    "lastEnrichedAt": ISO8601DateFormatter().string(from: proposedLastEnrichedAt),
                ],
                metadata: [
                    "actor": actor,
                    "groupID": item.groupID,
                    "evidence": item.evidence.joined(separator: ","),
                    "requiredApprovalToken": requiredApprovalToken,
                    "matchingCandidateCount": String(candidates.matchingCandidateCount),
                    "proposedChangeCount": String(proposedCandidates.count),
                ].filter { !$0.value.isEmpty },
                source: actor == "agent" ? .agent : nil
            )
            result.appliedItems.append(item)
        }

        result.status = "applied"
        result.isMutating = true
        result.appliedCount = result.appliedItems.count
        result.projectedRemainingCandidateCount = max(0, candidates.totalCandidateCount - result.appliedCount)
        result.skippedCount = max(0, candidates.matchingCandidateCount - result.appliedCount)
        return result
    }

    static func enrichmentReconciliationApprovalToken(
        groupID: String?,
        limit: Int,
        matchingCandidateCount: Int,
        proposedChangeCount: Int
    ) -> String {
        let selection = groupID ?? "all"
        return "review.enrichment.reconciliationApply:\(selection):limit=\(max(0, limit)):matching=\(matchingCandidateCount):proposed=\(proposedChangeCount)"
    }

    @discardableResult
    func approve(itemID: UUID, actor: String = "user") throws -> CiderReviewRoutingActionResult {
        let before = try routingDecisionService.explain(itemID: itemID)
        let after = try routingDecisionService.approve(itemID: itemID, actor: actor)
        return try routingActionResult(
            action: "review.routing.approve",
            status: "accepted",
            message: "Approved the proposed routing decision.",
            actor: actor,
            before: before,
            after: after
        )
    }

    @discardableResult
    func approveEventDateFact(candidateID: String, actor: String = "user") throws -> SecondBrainEventDateFactCandidateView {
        var view = try SecondBrainEventDateFactReviewService(database: resolvedDatabase ?? .shared)
            .accept(candidateID: candidateID, actor: actor, decisionNote: "Approved from review queue.")
        view.actionReceipt["command"] = "review.event-date-facts.approve"
        view.actionReceipt["action"] = "approve"
        return view
    }

    @discardableResult
    func rejectEventDateFact(candidateID: String, reason: String, actor: String = "user") throws -> SecondBrainEventDateFactCandidateView {
        var view = try SecondBrainEventDateFactReviewService(database: resolvedDatabase ?? .shared)
            .reject(candidateID: candidateID, actor: actor, reason: reason)
        view.actionReceipt["command"] = "review.event-date-facts.reject"
        view.actionReceipt["action"] = "reject"
        return view
    }

    @discardableResult
    func deferEventDateFact(candidateID: String, reason: String, actor: String = "user") throws -> SecondBrainEventDateFactCandidateView {
        var view = try SecondBrainEventDateFactReviewService(database: resolvedDatabase ?? .shared)
            .deferReview(candidateID: candidateID, actor: actor, reason: reason)
        view.actionReceipt["command"] = "review.event-date-facts.defer"
        view.actionReceipt["action"] = "defer"
        return view
    }

    @discardableResult
    func approveMemoryCandidate(candidateID: String, actor: String = "user") throws -> CiderReviewCandidateQueueActionResult {
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "memory_candidate",
            command: "review.memory-candidates.approve",
            action: "approve",
            actor: actor
        ) { service, id in
            try service.acceptMemoryCandidate(id, actor: actor)
        }
    }

    @discardableResult
    func rejectMemoryCandidate(candidateID: String, reason: String, actor: String = "user") throws -> CiderReviewCandidateQueueActionResult {
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "memory_candidate",
            command: "review.memory-candidates.reject",
            action: "reject",
            actor: actor
        ) { service, id in
            try service.rejectMemoryCandidate(id, reason: reason, actor: actor)
        }
    }

    @discardableResult
    func deferMemoryCandidate(candidateID: String, reason: String, actor: String = "user") throws -> CiderReviewCandidateQueueActionResult {
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "memory_candidate",
            command: "review.memory-candidates.defer",
            action: "defer",
            actor: actor
        ) { service, id in
            try service.deferMemoryCandidate(id, reason: reason, actor: actor)
        }
    }

    @discardableResult
    func approveGraphCandidate(
        candidateID: String,
        actor: String = "user",
        targetOptionRef: String? = nil,
        correctedTargetOwner: SecondBrainOwnerRef? = nil,
        correctedRelationType: String? = nil,
        targetOwner: SecondBrainOwnerRef? = nil,
        relationType: String? = nil
    ) throws -> CiderReviewCandidateQueueActionResult {
        let resolvedSelection = try graphCandidateApprovalSelection(
            candidateID: candidateID,
            targetOptionRef: targetOptionRef,
            correctedTargetOwner: correctedTargetOwner,
            correctedRelationType: correctedRelationType,
            targetOwner: targetOwner,
            relationType: relationType
        )
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "graph_candidate",
            command: "review.graph-candidates.approve",
            action: "approve",
            actor: actor
        ) { service, id in
            try service.acceptGraphCandidateIfResolved(
                id,
                actor: actor,
                targetOwner: resolvedSelection.targetOwner,
                relationType: resolvedSelection.relationType
            )
        }
    }

    private func graphCandidateApprovalSelection(
        candidateID rawID: String,
        targetOptionRef: String?,
        correctedTargetOwner: SecondBrainOwnerRef?,
        correctedRelationType: String?,
        targetOwner: SecondBrainOwnerRef?,
        relationType: String?
    ) throws -> (targetOwner: SecondBrainOwnerRef?, relationType: String?) {
        guard targetOptionRef != nil || correctedTargetOwner != nil else {
            return (targetOwner, relationType)
        }
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let id = normalizedReviewCandidateID(rawID, reviewFamily: "graph_candidate")
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        guard let output = try outputService.output(id: id) else {
            throw CiderReviewCandidateActionService.ReviewCandidateActionError.candidateNotFound(id)
        }
        let candidate = try SecondBrainGraphCandidateContract.validate(output)
        if let correctedTargetOwner {
            return (
                correctedTargetOwner,
                correctedRelationType
                    ?? relationType
                    ?? candidate.relationGuesses.first?.rawValue
                    ?? SecondBrainGraphCandidateContract.RelationType.mentions.rawValue
            )
        }
        if let targetOptionRef,
           let option = Self.graphCandidateTargetOption(ref: targetOptionRef, output: output, candidate: candidate, database: db) {
            return (option.targetOwner, correctedRelationType ?? relationType ?? option.relationType)
        }
        throw CiderReviewCandidateActionService.ReviewCandidateActionError.graphAcceptNeedsResolvedTarget(id)
    }

    @discardableResult
    func rejectGraphCandidate(candidateID: String, reason: String, actor: String = "user") throws -> CiderReviewCandidateQueueActionResult {
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "graph_candidate",
            command: "review.graph-candidates.reject",
            action: "reject",
            actor: actor
        ) { service, id in
            try service.rejectGraphCandidate(id, reason: reason, actor: actor)
        }
    }

    @discardableResult
    func deferGraphCandidate(candidateID: String, reason: String, actor: String = "user") throws -> CiderReviewCandidateQueueActionResult {
        return try reviewCandidateAction(
            candidateID: candidateID,
            reviewFamily: "graph_candidate",
            command: "review.graph-candidates.defer",
            action: "defer",
            actor: actor
        ) { service, id in
            try service.deferGraphCandidate(id, reason: reason, actor: actor)
        }
    }

    private func reviewCandidateAction(
        candidateID rawID: String,
        reviewFamily: String,
        command: String,
        action: String,
        actor: String,
        mutate: (CiderReviewCandidateActionService, String) throws -> CiderReviewCandidateActionResult
    ) throws -> CiderReviewCandidateQueueActionResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let id = normalizedReviewCandidateID(rawID, reviewFamily: reviewFamily)
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        guard let before = try outputService.output(id: id) else {
            throw CiderReviewCandidateActionService.ReviewCandidateActionError.candidateNotFound(id)
        }
        let beforeState = before.reviewState
        _ = try mutate(CiderReviewCandidateActionService(database: db), id)
        guard let after = try outputService.output(id: id) else {
            throw CiderReviewCandidateActionService.ReviewCandidateActionError.candidateNotFound(id)
        }
        return reviewCandidateQueueActionResult(
            command: command,
            action: action,
            actor: actor,
            reviewFamily: reviewFamily,
            before: before,
            after: after,
            changed: beforeState != after.reviewState
        )
    }

    private func reviewCandidateQueueActionResult(
        command: String,
        action: String,
        actor: String,
        reviewFamily: String,
        before: SecondBrainEnrichmentOutput,
        after: SecondBrainEnrichmentOutput,
        changed: Bool
    ) -> CiderReviewCandidateQueueActionResult {
        let candidateRef = "\(reviewFamily):\(after.id)"
        let sourceRef = after.owner.canonicalRef
        let evidenceRef = after.metadata["source_evidence_ref"] ?? after.metadata["source_evidence_id"].map { "source_evidence:\($0)" }
        let acceptedTargetOwner = SecondBrainOwnerRef(
            ownerType: after.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] ?? "",
            ownerID: after.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] ?? ""
        )
        let acceptedTargetOwnerRef = acceptedTargetOwner.ownerType.isEmpty || acceptedTargetOwner.ownerID.isEmpty
            ? nil
            : acceptedTargetOwner.canonicalRef
        let acceptedRelationType = after.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType]
        let beforeBoundary = truthBoundary(forReviewFamily: reviewFamily, reviewState: before.reviewState)
        let afterBoundary = truthBoundary(forReviewFamily: reviewFamily, reviewState: after.reviewState)
        let safeVerificationCommands = orderedUnique([
            candidateInspectCommand(forReviewFamily: reviewFamily, candidateID: after.id),
            "cider-cli item action-ledger list --owner \(sourceRef) --command \(command) --json",
            "cider-cli capture review-queue --kind \(reviewFamily) --include-deferred --json",
        ])
        let safeNextCommands = orderedUnique([
            candidateInspectCommand(forReviewFamily: reviewFamily, candidateID: after.id),
            "cider-cli capture review-queue --kind \(reviewFamily) --json",
            "cider-cli review summary --json",
        ])
        let provenance: [String: Any] = [
            "sourceRef": sourceRef,
            "candidateRef": candidateRef,
            "evidenceRef": evidenceRef ?? "",
            "targetOwnerRef": acceptedTargetOwnerRef ?? "",
            "relationType": acceptedRelationType ?? "",
            "storage": "enrichment_outputs",
        ].filter { !($0.value as? String == "") }
        var afterReceipt: [String: Any] = [
            "reviewState": after.reviewState,
            "truthBoundary": afterBoundary,
        ]
        if let acceptedTargetOwnerRef {
            afterReceipt["acceptedTargetOwnerRef"] = acceptedTargetOwnerRef
        }
        if let acceptedRelationType {
            afterReceipt["acceptedRelationType"] = acceptedRelationType
        }
        let actionReceipt: [String: Any] = [
            "command": command,
            "action": action,
            "actor": actor,
            "owner": [
                "ownerType": after.owner.ownerType,
                "ownerID": after.owner.ownerID,
                "ref": sourceRef,
            ],
            "ownerRef": sourceRef,
            "sourceRefs": orderedUnique([sourceRef, candidateRef]),
            "evidenceRefs": orderedUnique([sourceRef, evidenceRef].compactMap { $0 }),
            "readOnly": false,
            "changed": changed,
            "status": "succeeded",
            "truthBoundary": afterBoundary,
            "before": [
                "reviewState": before.reviewState,
                "truthBoundary": beforeBoundary,
            ],
            "after": afterReceipt,
            "safeVerificationCommands": safeVerificationCommands,
            "safeNextCommands": safeNextCommands,
        ]
        return CiderReviewCandidateQueueActionResult(
            command: command,
            action: action,
            candidateID: after.id,
            candidateRef: candidateRef,
            reviewFamily: reviewFamily,
            reviewState: after.reviewState,
            truthBoundary: afterBoundary,
            beforeState: before.reviewState,
            afterState: after.reviewState,
            changed: changed,
            actor: actor,
            provenance: provenance,
            actionReceipt: actionReceipt,
            safeVerificationCommands: safeVerificationCommands,
            safeNextCommands: safeNextCommands
        )
    }

    private func normalizedReviewCandidateID(_ rawID: String, reviewFamily: String) -> String {
        rawID
            .replacingOccurrences(of: "\(reviewFamily):", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func candidateInspectCommand(forReviewFamily reviewFamily: String, candidateID: String) -> String {
        switch reviewFamily {
        case "graph_candidate":
            return "cider-cli item graph-candidate \(candidateID) --json"
        case "memory_candidate":
            return "cider-cli item memory-facts inspect \(candidateID) --json"
        default:
            return "cider-cli capture review-queue --kind \(reviewFamily) --json"
        }
    }

    private func truthBoundary(forReviewFamily reviewFamily: String, reviewState: String) -> String {
        switch (reviewFamily, reviewState) {
        case ("graph_candidate", "accepted"):
            return "accepted_graph_truth"
        case ("memory_candidate", "accepted"):
            return "accepted_memory_candidate"
        default:
            return "reviewable_candidate_not_truth"
        }
    }

    @discardableResult
    func correctBookmark(
        itemID: UUID,
        target: CiderRoutingDecisionTarget,
        reason: String,
        actor: String = "user",
        bookmarkService: VaultBookmarkService
    ) throws -> CiderReviewRoutingActionResult {
        let before = try routingDecisionService.explain(itemID: itemID)
        let after = try routingDecisionService.correctBookmark(
            itemID: itemID,
            target: target,
            reason: reason,
            actor: actor,
            bookmarkService: bookmarkService
        )
        return try routingActionResult(
            action: "review.routing.correct",
            status: "corrected",
            message: "Applied a corrected routing destination.",
            actor: actor,
            before: before,
            after: after
        )
    }

    @discardableResult
    func deferReview(itemID: UUID, reason: String, actor: String = "user") throws -> CiderReviewRoutingActionResult {
        let explanation = try routingDecisionService.explain(itemID: itemID)
        guard let latest = explanation.latestDecision else {
            throw CiderRoutingDecisionError.decisionNotFound(itemID)
        }
        _ = try routingDecisionService.recordDecision(
            itemID: itemID,
            itemType: latest.itemType,
            target: latest.target,
            confidence: latest.confidence,
            reason: reason,
            actor: actor,
            source: "review.defer",
            reviewState: "deferred",
            supersedesDecisionID: latest.id
        )
        let after = try routingDecisionService.explain(itemID: itemID)
        return try routingActionResult(
            action: "review.routing.defer",
            status: "deferred",
            message: "Deferred the routing review item.",
            actor: actor,
            before: explanation,
            after: after
        )
    }

    @discardableResult
    func enrich(itemID: UUID, actor: String = "user") throws -> CiderReviewQueueActionResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let items = try itemSummaries(in: db)
        guard let item = items[itemID] else {
            throw CiderReviewQueueActionError.itemNotFound(itemID)
        }
        guard item.type == "bookmark" else {
            throw CiderReviewQueueActionError.unsupportedItemType(item.type)
        }

        let bookmarkDetails = try bookmarkDetails(in: db)
        guard let details = bookmarkDetails[itemID],
              enrichmentReviewItem(item: item, details: details, now: Date()) != nil else {
            throw CiderReviewQueueActionError.noEnrichmentIssue(itemID)
        }

        enrichmentScheduler(itemID)
        return CiderReviewQueueActionResult(
            action: "review.enrich",
            itemID: item.id,
            itemType: item.type,
            title: item.title,
            status: "scheduled",
            message: "Scheduled bookmark enrichment. The review item remains until metadata completes.",
            actor: actor,
            safeActions: ["review list", "bookmark get"]
        )
    }

    func enrichBatch(
        actor: String = "user",
        sampleFailureLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewQueueBatchEnrichmentResult {
        let items = try list(limit: Int.max, now: now).items
        let candidates = items.filter { item in
            item.kind == "enrichment"
                && item.itemType == "bookmark"
                && item.safeActions.contains("enrich")
        }
        let exclusions = items.compactMap { batchEnrichmentExclusionReason(for: $0) }
        let batchID = UUID()
        let failureLimit = max(0, sampleFailureLimit)
        var scheduledCount = 0
        var failures: [CiderReviewQueueBatchEnrichmentFailure] = []

        for candidate in candidates {
            do {
                _ = try enrich(itemID: candidate.itemID, actor: actor)
                MutationAuditService(database: resolvedDatabase).record(
                    action: "review.enrich.batch.schedule",
                    itemType: candidate.itemType,
                    itemID: candidate.itemID,
                    after: [
                        "reviewAction": "enrich",
                        "status": "scheduled",
                    ],
                    metadata: [
                        "batchID": batchID.uuidString,
                        "candidateCount": String(candidates.count),
                        "excludedCount": String(exclusions.count),
                    ],
                    source: mutationAuditSource(for: actor)
                )
                scheduledCount += 1
            } catch {
                if failures.count < failureLimit {
                    failures.append(
                        CiderReviewQueueBatchEnrichmentFailure(
                            itemID: candidate.itemID,
                            itemType: candidate.itemType,
                            title: candidate.title,
                            reason: error.localizedDescription
                        )
                    )
                }
            }
        }

        return CiderReviewQueueBatchEnrichmentResult(
            action: "review.enrich.batch",
            batchID: batchID,
            generatedAt: now,
            actor: actor,
            isMutating: true,
            candidateCount: candidates.count,
            scheduledCount: scheduledCount,
            excludedCount: exclusions.count,
            skippedCount: 0,
            failedCount: candidates.count - scheduledCount,
            exclusionsByReason: groupedCounts(exclusions),
            failures: failures,
            safeActions: ["review summary", "review list", "bookmark get"]
        )
    }

    func actionJobHistory(
        limit: Int = 20,
        itemSampleLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderReviewActionJobHistoryResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let entries = MutationAuditService(database: db).loadEntries()
        let batchEntries = entries.filter { entry in
            (entry.action == "review.enrich.batch.schedule"
                || entry.action == "review.enrich.batch.result")
                && entry.metadata["batchID"] != nil
        }
        let routingEntries = entries.filter { entry in
            entry.action.hasPrefix("review.routing.")
                && entry.metadata["routingDecisionID"] != nil
        }
        let items = try itemSummaries(in: db)
        let cappedLimit = max(0, limit)
        let jobs = (
            batchJobSummaries(
                from: batchEntries,
                items: items,
                limit: Int.max,
                itemSampleLimit: itemSampleLimit
            )
            + routingActionJobSummaries(
                from: routingEntries,
                items: items,
                itemSampleLimit: itemSampleLimit
            )
        )
        .sorted {
            if $0.lastScheduledAt != $1.lastScheduledAt {
                return $0.lastScheduledAt > $1.lastScheduledAt
            }
            return $0.jobID > $1.jobID
        }
        .prefix(cappedLimit)
        .map { $0 }

        return CiderReviewActionJobHistoryResult(
            command: "review.jobs",
            generatedAt: now,
            jobs: jobs
        )
    }

    func resolveItemID(ref: String) throws -> UUID {
        try routingDecisionService.resolveItemID(ref: ref)
    }

    private func mutationAuditSource(for actor: String) -> MutationAuditSource? {
        switch actor.lowercased() {
        case "agent":
            return .agent
        case "cli":
            return .cli
        default:
            return nil
        }
    }

    private func shouldSurface(_ reviewState: String, includeDeferred: Bool) -> Bool {
        switch reviewState {
        case "needs_review", "suggested":
            return true
        case "deferred":
            return includeDeferred
        default:
            return false
        }
    }

    private func latestRoutingDecisions(in db: CiderDatabase) throws -> [CiderRoutingDecision] {
        let stmt = try db.prepare("""
            SELECT id, item_id, item_type, target_kind, target_name, target_relative_path,
                   target_folder_id, confidence, reason, actor, source, review_state,
                   created_at, supersedes_decision_id
            FROM routing_decisions
            ORDER BY item_id ASC, created_at DESC, id DESC;
            """)
        var decisions: [CiderRoutingDecision] = []
        var seen = Set<UUID>()
        while try stmt.step() {
            guard let id = UUID(uuidString: stmt.string(at: 0)),
                  let itemID = UUID(uuidString: stmt.string(at: 1)),
                  !seen.contains(itemID) else {
                continue
            }
            seen.insert(itemID)
            decisions.append(CiderRoutingDecision(
                id: id,
                itemID: itemID,
                itemType: stmt.string(at: 2),
                target: CiderRoutingDecisionTarget(
                    kind: stmt.string(at: 3),
                    name: stmt.string(at: 4),
                    relativePath: stmt.string(at: 5),
                    folderID: stmt.optionalString(at: 6).flatMap(UUID.init(uuidString:))
                ),
                confidence: stmt.double(at: 7),
                reason: stmt.string(at: 8),
                actor: stmt.string(at: 9),
                source: stmt.string(at: 10),
                reviewState: stmt.string(at: 11),
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 12)),
                supersedesDecisionID: stmt.optionalString(at: 13).flatMap(UUID.init(uuidString:))
            ))
        }
        return decisions
    }

    private func itemSummaries(in db: CiderDatabase) throws -> [UUID: CiderRoutingItemSummary] {
        let stmt = try db.prepare("""
            SELECT id, type, title, relative_path, folder_id, updated_at
            FROM items;
            """)
        var items: [UUID: CiderRoutingItemSummary] = [:]
        while try stmt.step() {
            guard let id = UUID(uuidString: stmt.string(at: 0)) else { continue }
            items[id] = CiderRoutingItemSummary(
                id: id,
                type: stmt.string(at: 1),
                title: stmt.string(at: 2),
                relativePath: stmt.optionalString(at: 3),
                folderID: stmt.optionalString(at: 4).flatMap(UUID.init(uuidString:)),
                updatedAt: stmt.optionalDouble(at: 5).map(DatabaseHelpers.decodeDate)
            )
        }
        return items
    }

    private struct BookmarkReviewDetails {
        var url: String
        var enrichmentStatus: String?
        var lastEnrichedAt: Date?
        var aiSummary: String?
        var ocrText: String?
        var dominantColors: String?
        var mediaType: String?
        var thumbnailRelativePath: String?
        var thumbnailRemoteURL: String?
        var originalImagePath: String?
        var carouselImagePaths: String?
        var readerUnavailable: Bool?
        var preferredHeroMode: String?
    }

    private struct EnrichmentReconciliationCandidateSet {
        var totalCandidateCount: Int
        var matchingCandidateCount: Int
        var items: [CiderReviewEnrichmentReconciliationPlanItem]
    }

    private func bookmarkDetails(in db: CiderDatabase) throws -> [UUID: BookmarkReviewDetails] {
        let stmt = try db.prepare("""
            SELECT item_id, url, enrichment_status, last_enriched_at,
                   ai_summary, ocr_text, dominant_colors, media_type,
                   thumbnail_relative_path, thumbnail_remote_url, original_image_path,
                   carousel_image_paths, reader_unavailable, preferred_hero_mode
            FROM bookmarks;
            """)
        var details: [UUID: BookmarkReviewDetails] = [:]
        while try stmt.step() {
            guard let itemID = UUID(uuidString: stmt.string(at: 0)) else { continue }
            details[itemID] = BookmarkReviewDetails(
                url: stmt.string(at: 1),
                enrichmentStatus: stmt.optionalString(at: 2),
                lastEnrichedAt: stmt.optionalDouble(at: 3).map(DatabaseHelpers.decodeDate),
                aiSummary: stmt.optionalString(at: 4),
                ocrText: stmt.optionalString(at: 5),
                dominantColors: stmt.optionalString(at: 6),
                mediaType: stmt.optionalString(at: 7),
                thumbnailRelativePath: stmt.optionalString(at: 8),
                thumbnailRemoteURL: stmt.optionalString(at: 9),
                originalImagePath: stmt.optionalString(at: 10),
                carouselImagePaths: stmt.optionalString(at: 11),
                readerUnavailable: stmt.optionalBool(at: 12),
                preferredHeroMode: stmt.optionalString(at: 13)
            )
        }
        return details
    }

    private func enrichmentReconciliationCandidates(
        groupID: String?,
        now: Date
    ) throws -> EnrichmentReconciliationCandidateSet {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let items = try itemSummaries(in: db)
        let bookmarkDetails = try bookmarkDetails(in: db)
        var totalCandidateCount = 0
        var matchingCandidateCount = 0
        var matchedItems: [CiderReviewEnrichmentReconciliationPlanItem] = []

        for item in items.values
            .filter({ $0.type == "bookmark" })
            .sorted(by: enrichmentDiagnosisSort)
        {
            guard let details = bookmarkDetails[item.id],
                  enrichmentReviewItem(item: item, details: details, now: now) != nil else {
                continue
            }

            totalCandidateCount += 1
            let plan = enrichmentReconciliationProposal(item: item, details: details)
            if let groupID, plan.groupID != groupID {
                continue
            }

            matchingCandidateCount += 1
            matchedItems.append(
                enrichmentReconciliationPlanItem(
                    item: item,
                    details: details,
                    plan: plan
                )
            )
        }

        return EnrichmentReconciliationCandidateSet(
            totalCandidateCount: totalCandidateCount,
            matchingCandidateCount: matchingCandidateCount,
            items: matchedItems
        )
    }

    private func updateBookmarkEnrichmentStatus(
        itemID: UUID,
        status: String,
        lastEnrichedAt: Date,
        in db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            UPDATE bookmarks
            SET enrichment_status = ?,
                last_enriched_at = ?
            WHERE item_id = ?;
            """)
        stmt.bind(status, at: 1)
            .bind(DatabaseHelpers.encode(lastEnrichedAt), at: 2)
            .bind(itemID.uuidString, at: 3)
        try stmt.step()
    }

    private func routingReviewItem(
        decision: CiderRoutingDecision,
        item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails?
    ) -> CiderReviewQueueItem {
        CiderReviewQueueItem(
            id: "review-routing-\(decision.id.uuidString)",
            kind: decision.reviewState == "deferred" ? "deferred_routing" : "low_confidence_routing",
            source: "routing_decision",
            itemID: item.id,
            itemType: item.type,
            title: item.title,
            relativePath: item.relativePath,
            reason: decision.reason,
            reasonCodes: routingReasonCodes(for: decision),
            suggestedAction: decision.reviewState == "deferred" ? "Revisit route" : "Approve or correct route",
            reviewState: decision.reviewState,
            confidence: decision.confidence,
            routingDecisionID: decision.id,
            target: decision.target,
            createdAt: decision.createdAt,
            safeActions: decision.reviewState == "deferred"
                ? routingSafeActions(for: item.type, includeDefer: false)
                : routingSafeActions(for: item.type, includeDefer: true),
            routeIntents: routeIntents(for: item, details: details)
        )
    }

    private func routingSafeActions(for itemType: String, includeDefer: Bool) -> [String] {
        var actions = ["approve", itemType == "bookmark" ? "correct" : "item move"]
        if includeDefer {
            actions.append("defer")
        }
        return actions
    }

    private func routingReasonCodes(for decision: CiderRoutingDecision) -> [String] {
        if decision.reviewState == "deferred" {
            return ["routing_deferred"]
        }
        if decision.confidence < 0.5 {
            return ["routing_low_confidence"]
        }
        return ["routing_requires_review"]
    }

    private func enrichmentReviewItem(
        item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails,
        now: Date
    ) -> CiderReviewQueueItem? {
        let status = details.enrichmentStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status != "complete" || details.lastEnrichedAt == nil else { return nil }
        let failed = status == "failed" || status == "error"
        return CiderReviewQueueItem(
            id: "review-enrichment-\(item.id.uuidString)",
            kind: "enrichment",
            source: "bookmark",
            itemID: item.id,
            itemType: item.type,
            title: item.title,
            relativePath: item.relativePath,
            reason: failed ? "Bookmark enrichment failed." : "Bookmark enrichment is incomplete.",
            reasonCodes: enrichmentReasonCodes(status: status, lastEnrichedAt: details.lastEnrichedAt),
            suggestedAction: failed ? "Enrichment failed" : "Needs enrichment",
            reviewState: failed ? "needs_review" : "pending",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["enrich", "correct", "defer"]
        )
    }

    static func candidateQualitySignal(mentionText: String, sourceQuote: String?) -> (level: String, codes: [String], explanation: String) {
        let normalized = mentionText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        var codes: [String] = []
        let words = normalized.split(separator: " ").map(String.init)
        let weakPronouns: Set<String> = ["it", "this", "that", "one", "thing", "stuff", "whatever", "something", "anything"]
        if words.isEmpty {
            codes.append("empty_mention")
        }
        if words.allSatisfy({ weakPronouns.contains($0) }) {
            codes.append("pronoun_or_placeholder_only")
        }
        if words.count <= 3 && words.contains(where: { weakPronouns.contains($0) }) {
            codes.append("vague_pronoun_fragment")
        }
        if normalized.hasPrefix("to ") || normalized.hasPrefix("about ") || normalized.hasPrefix("and ") || normalized.hasPrefix("but ") {
            codes.append("clause_fragment")
        }
        if normalized.contains(" to have ") || normalized.contains(" to talk ") || normalized.contains(" moved closer") {
            codes.append("event_clause_not_object")
        }
        if normalized.contains("whatever") || normalized.contains("stuff like") {
            codes.append("contains_vague_modifier")
        }
        if words.count > 7 {
            codes.append("long_phrase_maybe_not_canonical_object")
        }
        let level: String
        let explanation: String
        if codes.contains("pronoun_or_placeholder_only") || codes.contains("vague_pronoun_fragment") || codes.contains("event_clause_not_object") {
            level = "low"
            explanation = "Likely noisy: extracted phrase is vague, pronoun-heavy, or reads like a clause rather than a canonical object. Keep the source quote and reject/correct/delegate instead of accepting as truth."
        } else if codes.isEmpty {
            level = "good"
            explanation = "Looks like a concrete source-backed candidate; still review before accepting because candidates are not truth."
        } else {
            level = "needs_review"
            explanation = "Review carefully: candidate is source-backed but has wording that may need correction before becoming a canonical object."
        }
        return (level, codes, explanation)
    }

    static func graphCandidateTargetOptions(
        output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        sourceItemRef: String? = nil,
        evidenceRef: String? = nil,
        database: CiderDatabase? = nil
    ) -> [CiderGraphCandidateTargetOption] {
        guard candidate.reviewState.isReviewable else { return [] }
        guard candidate.kind == .object || candidate.kind == .objectRelation else { return [] }
        let targetKind = candidate.objectTypeGuesses.first?.rawValue ?? "object"
        let fallbackTargetOwner = candidate.acceptedTargetOwner ?? SecondBrainOwnerRef(
            ownerType: "graph_object",
            ownerID: "\(targetKind)-\(graphCandidateTargetSlug(candidate.mentionText))"
        )
        let relationType = candidate.acceptedRelationType?.rawValue
            ?? candidate.relationGuesses.first?.rawValue
            ?? SecondBrainGraphCandidateContract.RelationType.mentions.rawValue
        let sourceRef = sourceItemRef ?? output.owner.canonicalRef
        var seenRefs = Set<String>()
        let refs = [sourceRef, evidenceRef].compactMap { $0 }.filter { seenRefs.insert($0).inserted }
        let existingOptions = existingGraphCandidateTargetOptions(
            output: output,
            candidate: candidate,
            targetKind: targetKind,
            relationType: relationType,
            sourceRef: sourceRef,
            evidenceRefs: refs,
            database: database
        )
        let fallbackOption = CiderGraphCandidateTargetOption(
            optionRef: "graph_target_option:\(output.id):candidate-object",
            label: "\(candidate.mentionText) -> \(fallbackTargetOwner.canonicalRef)",
            targetOwner: fallbackTargetOwner,
            relationType: relationType,
            targetKind: targetKind,
            sourceQuote: candidate.sourceQuote,
            sourceItemRef: sourceRef,
            evidenceRefs: refs,
            confidence: candidate.confidence
        )
        var seenOptionOwners = Set(existingOptions.map { "\($0.targetOwner.canonicalRef)|\($0.relationType)" })
        let fallbackKey = "\(fallbackOption.targetOwner.canonicalRef)|\(fallbackOption.relationType)"
        if seenOptionOwners.insert(fallbackKey).inserted {
            return existingOptions + [fallbackOption]
        }
        return existingOptions
    }

    private struct ExistingGraphCandidateTargetMatch {
        var owner: SecondBrainOwnerRef
        var targetKind: String
        var label: String
        var searchableText: String
        var baseConfidence: Double
        var rankHint: Int
        var provenanceRefs: [String] = []
        var sourceRefs: [String] = []
        var externalIDs: [String: String] = [:]
    }

    private static func existingGraphCandidateTargetOptions(
        output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        targetKind: String,
        relationType: String,
        sourceRef: String,
        evidenceRefs: [String],
        database: CiderDatabase?
    ) -> [CiderGraphCandidateTargetOption] {
        guard let database else { return [] }
        let matches = (try? existingGraphCandidateTargetMatches(in: database, candidate: candidate, targetKind: targetKind)) ?? []
        var seen = Set<String>()
        return matches.prefix(4).enumerated().compactMap { index, match in
            guard seen.insert(match.owner.canonicalRef).inserted else { return nil }
            return CiderGraphCandidateTargetOption(
                optionRef: "graph_target_option:\(output.id):existing-\(index + 1)",
                label: "\(candidate.mentionText) -> existing \(match.label) (\(match.owner.canonicalRef))",
                targetOwner: match.owner,
                relationType: relationType,
                targetKind: match.targetKind,
                sourceQuote: candidate.sourceQuote,
                sourceItemRef: sourceRef,
                evidenceRefs: uniqueReviewRefs(evidenceRefs + match.provenanceRefs),
                confidence: min(0.99, match.baseConfidence),
                provenanceRefs: match.provenanceRefs,
                sourceRefs: match.sourceRefs,
                externalIDs: match.externalIDs
            )
        }
    }

    private static func existingGraphCandidateTargetMatches(
        in database: CiderDatabase,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        targetKind: String
    ) throws -> [ExistingGraphCandidateTargetMatch] {
        let mention = candidate.mentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mention.isEmpty else { return [] }
        let allowedOwnerTypes = graphCandidateAllowedExistingOwnerTypes(targetKind: targetKind, candidate: candidate)
        let allowedOwnerKinds = graphCandidateAllowedExistingOwnerKinds(targetKind: targetKind, candidate: candidate)
        var matches: [ExistingGraphCandidateTargetMatch] = []
        matches.append(contentsOf: try indexedOwnerTargetMatches(
            in: database,
            candidate: candidate,
            allowedOwnerKinds: allowedOwnerKinds,
            allowedOwnerTypes: allowedOwnerTypes
        ))
        matches.append(contentsOf: try contactTargetMatches(in: database))
        matches.append(contentsOf: try projectTargetMatches(in: database))
        matches.append(contentsOf: try projectedOwnerTargetMatches(in: database, allowedOwnerTypes: allowedOwnerTypes))
        matches.append(contentsOf: try acceptedGraphObjectTargetMatches(in: database, allowedOwnerTypes: allowedOwnerTypes))

        let mentionTokens = graphCandidateLookupTokens(mention)
        let sourceTokens = graphCandidateLookupTokens(candidate.sourceQuote)
        guard !mentionTokens.isEmpty else { return [] }
        var bestByOwner: [SecondBrainOwnerRef: ExistingGraphCandidateTargetMatch] = [:]
        for match in matches {
            let score = graphCandidateTargetScore(
                mention: mention,
                mentionTokens: mentionTokens,
                sourceTokens: sourceTokens,
                match: match
            )
            guard score >= 0.52 else { continue }
            var ranked = match
            ranked.baseConfidence = score
            if let current = bestByOwner[match.owner], current.baseConfidence >= score {
                continue
            }
            bestByOwner[match.owner] = ranked
        }
        return bestByOwner.values.sorted { lhs, rhs in
            if lhs.baseConfidence != rhs.baseConfidence { return lhs.baseConfidence > rhs.baseConfidence }
            if lhs.rankHint != rhs.rankHint { return lhs.rankHint < rhs.rankHint }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func indexedOwnerTargetMatches(
        in database: CiderDatabase,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        allowedOwnerKinds: Set<String>,
        allowedOwnerTypes: Set<String>
    ) throws -> [ExistingGraphCandidateTargetMatch] {
        try SecondBrainOwnerLabelIndexService(database: database).search(
            query: candidate.mentionText,
            ownerKinds: allowedOwnerKinds,
            ownerTypes: allowedOwnerTypes,
            limit: 8
        ).enumerated().map { index, record in
            ExistingGraphCandidateTargetMatch(
                owner: record.owner,
                targetKind: graphCandidateTargetKind(ownerType: record.owner.ownerType, ownerKind: record.ownerKind, fallback: record.ownerKind),
                label: record.canonicalLabel,
                searchableText: ([record.canonicalLabel] + record.aliases + record.externalIDs.values).joined(separator: " "),
                baseConfidence: record.confidence ?? 0.88,
                rankHint: index,
                provenanceRefs: record.provenanceRefs,
                sourceRefs: record.sourceRefs,
                externalIDs: record.externalIDs
            )
        }
    }

    private static func contactTargetMatches(in database: CiderDatabase) throws -> [ExistingGraphCandidateTargetMatch] {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, c.relationship_label, c.notes, c.email
            FROM contacts c
            JOIN items i ON i.id = c.item_id
            ORDER BY i.updated_at DESC
            LIMIT 200;
            """)
        var matches: [ExistingGraphCandidateTargetMatch] = []
        while try stmt.step() {
            let title = stmt.string(at: 1)
            let searchable = [title, stmt.string(at: 2), stmt.string(at: 3), stmt.string(at: 4)]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            matches.append(ExistingGraphCandidateTargetMatch(
                owner: SecondBrainOwnerRef(ownerType: "contact", ownerID: stmt.string(at: 0)),
                targetKind: "person",
                label: title,
                searchableText: searchable,
                baseConfidence: 0,
                rankHint: 10
            ))
        }
        return matches
    }

    private static func projectTargetMatches(in database: CiderDatabase) throws -> [ExistingGraphCandidateTargetMatch] {
        let stmt = try database.prepare("""
            SELECT id, title, subtitle, metadata
            FROM projects
            ORDER BY updated_at DESC
            LIMIT 200;
            """)
        var matches: [ExistingGraphCandidateTargetMatch] = []
        while try stmt.step() {
            let title = stmt.string(at: 1)
            let searchable = [title, stmt.string(at: 2), stmt.string(at: 3)]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            matches.append(ExistingGraphCandidateTargetMatch(
                owner: SecondBrainOwnerRef(ownerType: "project", ownerID: stmt.string(at: 0)),
                targetKind: "project",
                label: title,
                searchableText: searchable,
                baseConfidence: 0,
                rankHint: 20
            ))
        }
        return matches
    }

    private static func projectedOwnerTargetMatches(
        in database: CiderDatabase,
        allowedOwnerTypes: Set<String>
    ) throws -> [ExistingGraphCandidateTargetMatch] {
        let placeholders = Array(repeating: "?", count: allowedOwnerTypes.count).joined(separator: ",")
        guard !placeholders.isEmpty else { return [] }
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, title, body, confidence
            FROM item_sections
            WHERE owner_type IN (\(placeholders))
            ORDER BY updated_at DESC
            LIMIT 300;
            """)
        for (index, ownerType) in allowedOwnerTypes.sorted().enumerated() {
            stmt.bind(ownerType, at: Int32(index + 1))
        }
        var matches: [ExistingGraphCandidateTargetMatch] = []
        while try stmt.step() {
            let ownerType = stmt.string(at: 0)
            let title = stmt.string(at: 2)
            matches.append(ExistingGraphCandidateTargetMatch(
                owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: stmt.string(at: 1)),
                targetKind: graphCandidateTargetKind(ownerType: ownerType, fallback: ownerType),
                label: title.isEmpty ? stmt.string(at: 1) : title,
                searchableText: [title, stmt.string(at: 3)].joined(separator: " "),
                baseConfidence: stmt.optionalDouble(at: 4) ?? 0,
                rankHint: 30
            ))
        }
        return matches
    }

    private static func acceptedGraphObjectTargetMatches(
        in database: CiderDatabase,
        allowedOwnerTypes: Set<String>
    ) throws -> [ExistingGraphCandidateTargetMatch] {
        let placeholders = Array(repeating: "?", count: allowedOwnerTypes.count).joined(separator: ",")
        guard !placeholders.isEmpty else { return [] }
        let stmt = try database.prepare("""
            SELECT target_owner_type, target_owner_id, evidence, metadata, confidence
            FROM owner_relations
            WHERE target_owner_type IN (\(placeholders))
            ORDER BY updated_at DESC
            LIMIT 300;
            """)
        for (index, ownerType) in allowedOwnerTypes.sorted().enumerated() {
            stmt.bind(ownerType, at: Int32(index + 1))
        }
        var matches: [ExistingGraphCandidateTargetMatch] = []
        while try stmt.step() {
            let ownerType = stmt.string(at: 0)
            let ownerID = stmt.string(at: 1)
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 3)) ?? [:]
            let label = metadata["target_label"]
                ?? metadata["mediaItemTitle"]
                ?? metadata["candidate_mention_text"]
                ?? ownerID
            let searchable = [label, ownerID, stmt.string(at: 2), metadata.values.joined(separator: " ")]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            matches.append(ExistingGraphCandidateTargetMatch(
                owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID),
                targetKind: graphCandidateTargetKind(ownerType: ownerType, fallback: ownerType),
                label: label,
                searchableText: searchable,
                baseConfidence: stmt.optionalDouble(at: 4) ?? 0,
                rankHint: 40
            ))
        }
        return matches
    }

    private static func graphCandidateAllowedExistingOwnerTypes(
        targetKind: String,
        candidate: SecondBrainGraphCandidateContract.Candidate
    ) -> Set<String> {
        var types: Set<String> = ["graph_object", "media_item", "place", "project", "contact"]
        let rawKinds = Set(candidate.objectTypeGuesses.map(\.rawValue) + [targetKind])
        if rawKinds.contains("person") || rawKinds.contains("contact") {
            types.formUnion(["contact", "person"])
        }
        if rawKinds.contains("project") {
            types.insert("project")
        }
        if rawKinds.contains("movie") || rawKinds.contains("book") || rawKinds.contains("show") || rawKinds.contains("media") {
            types.insert("media_item")
        }
        if rawKinds.contains("place") || rawKinds.contains("restaurant") {
            types.insert("place")
        }
        return types
    }

    private static func graphCandidateTargetKind(ownerType: String, fallback: String) -> String {
        switch ownerType {
        case "contact", "person":
            return "person"
        case "media_item":
            return "media"
        default:
            return fallback
        }
    }

    private static func graphCandidateTargetKind(ownerType: String, ownerKind: String, fallback: String) -> String {
        if ownerKind == "media" { return "media" }
        if ownerKind == "person" { return "person" }
        if ownerKind == "place" { return "place" }
        if ownerKind == "project" { return "project" }
        return graphCandidateTargetKind(ownerType: ownerType, fallback: fallback)
    }

    private static func graphCandidateAllowedExistingOwnerKinds(
        targetKind: String,
        candidate: SecondBrainGraphCandidateContract.Candidate
    ) -> Set<String> {
        let rawKinds = Set(candidate.objectTypeGuesses.map(\.rawValue) + [targetKind])
        var kinds: Set<String> = ["media", "place", "project", "person", "graph_object", "object"]
        if rawKinds.contains("movie") || rawKinds.contains("book") || rawKinds.contains("show") || rawKinds.contains("media") {
            kinds = ["media"]
        } else if rawKinds.contains("place") || rawKinds.contains("restaurant") {
            kinds = ["place"]
        } else if rawKinds.contains("person") || rawKinds.contains("contact") {
            kinds = ["person"]
        } else if rawKinds.contains("project") {
            kinds = ["project"]
        }
        return kinds
    }

    private static func graphCandidateTargetScore(
        mention: String,
        mentionTokens: Set<String>,
        sourceTokens: Set<String>,
        match: ExistingGraphCandidateTargetMatch
    ) -> Double {
        let normalizedMention = graphCandidateLookupNormalized(mention)
        let normalizedText = graphCandidateLookupNormalized(match.searchableText)
        if normalizedText == normalizedMention {
            return 0.96
        }
        if !normalizedMention.isEmpty && normalizedText.contains(normalizedMention) {
            return 0.9
        }
        let normalizedLabel = graphCandidateLookupNormalized(match.label)
        if normalizedLabel.count >= 4,
           normalizedMention.contains(normalizedLabel) {
            return 0.86
        }
        let matchTokens = graphCandidateLookupTokens(match.searchableText)
        guard !matchTokens.isEmpty else { return 0 }
        let overlap = mentionTokens.intersection(matchTokens)
        let sourceOverlap = sourceTokens.intersection(matchTokens)
        let mentionScore = Double(overlap.count) / Double(max(mentionTokens.count, 1))
        let sourceScore = min(0.18, Double(sourceOverlap.count) * 0.03)
        let storedConfidenceBoost = min(0.08, max(0, match.baseConfidence) * 0.08)
        return min(0.88, mentionScore * 0.72 + sourceScore + storedConfidenceBoost)
    }

    private static func graphCandidateLookupTokens(_ value: String) -> Set<String> {
        let stopwords: Set<String> = ["the", "a", "an", "and", "or", "to", "of", "for", "with", "in", "on", "at"]
        return Set(graphCandidateLookupNormalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    private static func graphCandidateLookupNormalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func uniqueReviewRefs(_ refs: [String]) -> [String] {
        var seen = Set<String>()
        return refs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func graphCandidateTargetOption(
        ref rawRef: String,
        output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainGraphCandidateContract.Candidate,
        database: CiderDatabase? = nil
    ) -> CiderGraphCandidateTargetOption? {
        let normalized = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return graphCandidateTargetOptions(output: output, candidate: candidate, database: database).first { $0.optionRef == normalized }
    }

    private static func graphCandidateTargetSlug(_ value: String) -> String {
        let slug = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "object" : String(slug.prefix(80))
    }

    private func reviewSourceItemDate(from item: CiderRoutingItemSummary) -> String? {
        let pattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        if let relativePath = item.relativePath,
           let range = relativePath.range(of: pattern, options: .regularExpression) {
            return String(relativePath[range])
        }
        if let range = item.title.range(of: pattern, options: .regularExpression) {
            return String(item.title[range])
        }
        return nil
    }

    private func graphCandidateReviewItems(
        in db: CiderDatabase,
        itemsByID: [UUID: CiderRoutingItemSummary],
        includeDeferred: Bool
    ) throws -> [CiderReviewQueueItem] {
        let states: Set<String> = includeDeferred
            ? ["suggested", "needs_review", "deferred"]
            : ["suggested", "needs_review"]
        let outputs = try SecondBrainEnrichmentOutputService(database: db).outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: states
        )

        return outputs.compactMap { output in
            guard let sourceItemID = UUID(uuidString: output.owner.ownerID),
                  let item = itemsByID[sourceItemID],
                  let candidate = try? SecondBrainGraphCandidateContract.validate(output) else {
                return nil
            }
            let possibleTypes = candidate.objectTypeGuesses.map(\.rawValue)
            let possibleRelations = candidate.relationGuesses.map(\.rawValue)
            let candidateActions = candidate.safeActions.map(\.rawValue)
            let typeLabel = possibleTypes.isEmpty ? "object" : possibleTypes.joined(separator: ", ")
            let relationLabel = possibleRelations.isEmpty ? nil : possibleRelations.joined(separator: ", ")
            let reason = relationLabel.map {
                "Review extracted \(typeLabel) candidate from source quote; possible relation: \($0)."
            } ?? "Review extracted \(typeLabel) candidate from source quote."
            let quality = Self.candidateQualitySignal(mentionText: candidate.mentionText, sourceQuote: candidate.sourceQuote)
            let sourceItemRef = "\(item.type):\(item.id.uuidString)"
            let relation = possibleRelations.first ?? "mentions"
            let sourceEvidenceRecord = SecondBrainSourceEvidenceService.recordFromOutput(output).map(CiderReviewQueueSourceEvidenceRecord.init)
            let targetOptions = Self.graphCandidateTargetOptions(
                output: output,
                candidate: candidate,
                sourceItemRef: sourceItemRef,
                evidenceRef: sourceEvidenceRecord.map { "source_evidence:\($0.id)" },
                database: db
            )

            return CiderReviewQueueItem(
                id: "review-graph-candidate-\(output.id)",
                kind: "graph_candidate",
                source: "graph_candidate",
                itemID: sourceItemID,
                itemType: item.type,
                title: candidate.mentionText,
                relativePath: item.relativePath,
                reason: reason,
                reasonCodes: ["graph_candidate_review"],
                suggestedAction: "Review graph candidate",
                reviewState: output.reviewState,
                confidence: candidate.confidence,
                confidenceReason: candidate.confidenceReason,
                routingDecisionID: nil,
                target: nil,
                createdAt: output.createdAt,
                safeActions: candidateActions.isEmpty
                    ? ["inspect_source", "correct", "reject", "delegate_enrichment"]
                    : candidateActions,
                candidateID: output.id,
                candidateRef: "graph_candidate:\(output.id)",
                sourceQuote: candidate.sourceQuote,
                possibleTypes: possibleTypes,
                possibleRelations: possibleRelations,
                candidateActions: candidate.actionGuesses,
                safeNextCommands: graphCandidateSafeNextCommands(output: output, sourceItem: item, targetOptions: targetOptions),
                reviewFamily: "graph_candidate",
                sourceItemRef: sourceItemRef,
                sourceItemTitle: item.title,
                sourceItemDate: reviewSourceItemDate(from: item),
                extractionReason: "Cider extracted '\(candidate.mentionText)' from the exact source quote and inferred a reviewable \(relation) graph candidate. This is not accepted graph truth until explicitly accepted.",
                proposedChange: [
                    "changeType": "graph_relation_candidate",
                    "mentionText": candidate.mentionText,
                    "relationType": relation,
                    "targetKind": typeLabel,
                    "truthState": "reviewable_candidate_not_truth",
                ],
                storage: [
                    "table": "enrichment_outputs",
                    "service": "SecondBrainEnrichmentOutputService",
                    "kind": SecondBrainGraphCandidateContract.outputKind,
                    "readModels": "CiderReviewQueueService.graphCandidateReviewItems; cider-cli item graph-candidate; cider-cli capture review-queue",
                ],
                truthState: candidate.reviewState == .accepted ? "accepted_graph_truth" : "reviewable_candidate_not_truth",
                acceptEffect: "Accepting records an explicit cited graph relation/canonical object decision; it does not happen silently from extraction.",
                rejectEffect: "Rejecting marks this candidate rejected while preserving the source quote and audit trail.",
                candidateQualityLevel: quality.level,
                candidateQualityCodes: quality.codes,
                candidateQualityExplanation: quality.explanation,
                sourceEvidenceRecord: sourceEvidenceRecord,
                lifecycleHistory: lifecycleHistoryRecords(for: output, in: db),
                targetOptions: targetOptions
            )
        }
    }

    private func graphCandidateSafeNextCommands(
        output: SecondBrainEnrichmentOutput,
        sourceItem: CiderRoutingItemSummary,
        targetOptions: [CiderGraphCandidateTargetOption] = []
    ) -> [String] {
        orderedUnique([
            targetOptions.first.map { "cider-cli review approve \(output.id) --target-option \($0.optionRef) --json" }
                ?? "cider-cli review approve \(output.id) --json",
            "cider-cli review approve \(output.id) --json",
            "cider-cli review reject \(output.id) --reason <reason> --json",
            "cider-cli review defer \(output.id) --reason <reason> --json",
            "cider-cli item graph-candidate \(output.id) --json",
            "cider-cli item graph-candidates \(output.owner.ownerType) \(output.owner.ownerID) --json",
            "cider-cli item context \(sourceItem.type) \(sourceItem.id.uuidString) --json",
            "cider-cli capture review-queue --json",
        ])
    }

    private func memoryCandidateReviewItems(
        in db: CiderDatabase,
        itemsByID: [UUID: CiderRoutingItemSummary],
        includeDeferred: Bool
    ) throws -> [CiderReviewQueueItem] {
        let states: Set<String> = includeDeferred
            ? ["suggested", "needs_review", "deferred"]
            : ["suggested", "needs_review"]
        let outputs = try SecondBrainEnrichmentOutputService(database: db).outputs(
            kind: "memory_candidate",
            reviewStates: states
        )

        return outputs.compactMap { output in
            guard let sourceItemID = UUID(uuidString: output.owner.ownerID),
                  let item = itemsByID[sourceItemID] else {
                return nil
            }
            let memoryKind = output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? "memory"
            let linkedOwnerRefs = DatabaseHelpers.decodeStringArray(output.metadata["linked_owner_refs"])
            let reason = "Review source-backed \(memoryKind.replacingOccurrences(of: "_", with: " ")) memory candidate before promotion."
            let sourceItemRef = "\(item.type):\(item.id.uuidString)"

            return CiderReviewQueueItem(
                id: "review-memory-candidate-\(output.id)",
                kind: "memory_candidate",
                source: "memory_candidate",
                itemID: sourceItemID,
                itemType: item.type,
                title: output.value,
                relativePath: item.relativePath,
                reason: reason,
                reasonCodes: ["memory_candidate_review"],
                suggestedAction: "Review memory candidate",
                reviewState: output.reviewState,
                confidence: output.confidence,
                routingDecisionID: nil,
                target: nil,
                createdAt: output.createdAt,
                safeActions: ["inspect_source", "accept", "reject", "defer", "correct"],
                candidateID: output.id,
                candidateRef: "memory_candidate:\(output.id)",
                sourceQuote: output.evidence,
                memoryKind: memoryKind,
                linkedOwnerRefs: linkedOwnerRefs,
                observedDate: output.metadata["observed_date"],
                memoryKey: output.metadata["memory_key"],
                memoryStatus: output.metadata["memory_status"],
                safeNextCommands: memoryCandidateSafeNextCommands(output: output, sourceItem: item),
                reviewFamily: "memory_candidate",
                sourceItemRef: sourceItemRef,
                sourceItemTitle: item.title,
                sourceItemDate: reviewSourceItemDate(from: item),
                extractionReason: "Cider extracted a source-backed memory candidate from the exact source quote; it remains reviewable and is not promoted until accepted.",
                proposedChange: [
                    "changeType": "memory_candidate",
                    "memoryKind": memoryKind,
                    "value": output.value,
                    "truthState": "reviewable_candidate_not_truth",
                ],
                storage: [
                    "table": "enrichment_outputs",
                    "service": "SecondBrainEnrichmentOutputService",
                    "kind": "memory_candidate",
                    "readModels": "CiderReviewQueueService.memoryCandidateReviewItems; cider-cli item memory-candidate; cider-cli capture review-queue",
                ],
                truthState: output.reviewState == "accepted" ? "accepted_memory_candidate" : "reviewable_candidate_not_truth",
                acceptEffect: "Accepting marks the source-backed memory candidate accepted for promotion; extraction alone never writes user-owned memory truth.",
                rejectEffect: "Rejecting marks this memory candidate rejected while preserving source evidence and audit history.",
                candidateQualityLevel: "needs_review",
                candidateQualityCodes: ["requires_human_memory_review"],
                candidateQualityExplanation: "Memory candidates are intentionally reviewable; inspect the source quote before accepting.",
                sourceEvidenceRecord: SecondBrainSourceEvidenceService.recordFromOutput(output).map(CiderReviewQueueSourceEvidenceRecord.init),
                lifecycleHistory: lifecycleHistoryRecords(for: output, in: db)
            )
        }
    }

    private func lifecycleHistoryRecords(for output: SecondBrainEnrichmentOutput, in db: CiderDatabase) -> [CiderReviewQueueLifecycleEventRecord] {
        let service = SecondBrainReviewLifecycleService(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: output.id)
        do {
            var events = try service.events(owner: owner)
            if let candidateRef = SecondBrainReviewLifecycleService.candidateRef(for: output) {
                let byCandidate = try service.events(candidateRef: candidateRef)
                var seen = Set(events.map(\.id))
                events.append(contentsOf: byCandidate.filter { seen.insert($0.id).inserted })
            }
            return events.sorted { $0.createdAt < $1.createdAt }.map(CiderReviewQueueLifecycleEventRecord.init)
        } catch {
            return []
        }
    }

    private func memoryCandidateSafeNextCommands(
        output: SecondBrainEnrichmentOutput,
        sourceItem: CiderRoutingItemSummary
    ) -> [String] {
        orderedUnique([
            "cider-cli review approve \(output.id) --json",
            "cider-cli review reject \(output.id) --reason <reason> --json",
            "cider-cli review defer \(output.id) --reason <reason> --json",
            "cider-cli item context \(sourceItem.type) \(sourceItem.id.uuidString) --json",
            "cider-cli item get \(sourceItem.type) \(sourceItem.id.uuidString) --json",
            "cider-cli capture review-queue --kind memory_candidate --json",
            "cider-cli capture review-queue --json",
        ])
    }

    private func eventDateFactReviewItems(
        in db: CiderDatabase,
        itemsByID: [UUID: CiderRoutingItemSummary],
        includeDeferred: Bool
    ) throws -> [CiderReviewQueueItem] {
        let states = includeDeferred
            ? ["suggested", "needs_review", "deferred"]
            : ["suggested", "needs_review"]
        let candidates = try SecondBrainFactValidityService(database: db).candidates(reviewStates: states)

        return candidates.compactMap { candidate in
            let metadata = candidate.candidate.metadata
            guard metadata["candidate_family"] == "event_date_fact",
                  let sourceItemID = UUID(uuidString: candidate.candidate.sourceOwner.ownerID),
                  let item = itemsByID[sourceItemID] else {
                return nil
            }

            let factKind = metadata["fact_kind"] ?? "event_date"
            let eventLabel = metadata["event_label"] ?? candidate.targetRef
            let proposedDate = metadata["proposed_date"]
            let sourceItemRef = "\(item.type):\(item.id.uuidString)"
            let confidence = metadata["confidence"] ?? "source_backed_observation"
            let acceptedBoundary = factKind == "contact_birthday" ? "accepted_contact_birthday" : "accepted_event_date"
            let sourceEvidenceRecord = candidate.sourceEvidenceRecord.map(CiderReviewQueueSourceEvidenceRecord.init)
            let lifecycleHistory = candidate.lifecycleHistory
                .sorted { $0.createdAt < $1.createdAt }
                .map(CiderReviewQueueLifecycleEventRecord.init)

            return CiderReviewQueueItem(
                id: "review-event-date-fact-\(candidate.id)",
                kind: "event_date_fact",
                source: "fact_validity_candidate",
                itemID: sourceItemID,
                itemType: item.type,
                title: eventLabel,
                relativePath: item.relativePath,
                reason: candidate.candidate.reason,
                reasonCodes: ["event_date_fact_review"],
                suggestedAction: "Review event/date fact",
                reviewState: candidate.reviewState,
                confidence: nil,
                confidenceReason: confidence,
                routingDecisionID: nil,
                target: nil,
                createdAt: candidate.candidate.createdAt,
                safeActions: ["accept", "reject", "defer"],
                candidateID: candidate.id,
                candidateRef: candidate.candidate.candidateRef,
                sourceQuote: candidate.candidate.sourceQuote,
                proposedDate: proposedDate,
                eventLabel: eventLabel,
                factKind: factKind,
                targetRef: candidate.targetRef,
                factConfidence: confidence,
                safeNextCommands: eventDateFactSafeNextCommands(candidate: candidate, sourceItem: item),
                reviewFamily: "event_date_fact",
                sourceItemRef: sourceItemRef,
                sourceItemTitle: item.title,
                sourceItemDate: reviewSourceItemDate(from: item) ?? proposedDate,
                extractionReason: "Cider extracted a source-backed \(factKind.replacingOccurrences(of: "_", with: " ")) candidate for \(eventLabel); it remains reviewable and is not accepted truth until approved.",
                proposedChange: [
                    "changeType": "event_date_fact",
                    "factKind": factKind,
                    "eventLabel": eventLabel,
                    "targetRef": candidate.targetRef,
                    "proposedDate": proposedDate ?? "",
                    "truthState": "reviewable_candidate_not_truth",
                ].filter { !$0.value.isEmpty },
                storage: [
                    "table": "fact_validity_candidates",
                    "service": "SecondBrainEventDateFactReviewService",
                    "candidateFamily": "event_date_fact",
                    "readModels": "CiderReviewQueueService.eventDateFactReviewItems; cider-cli item event-date-facts; cider-cli review list",
                ],
                truthState: candidate.reviewState == "accepted" ? acceptedBoundary : "reviewable_candidate_not_truth",
                acceptEffect: "Accepting creates or updates \(acceptedBoundary) structured truth; extraction alone never mutates contacts or date cards.",
                rejectEffect: "Rejecting marks the event/date fact candidate rejected while preserving source evidence and audit history.",
                candidateQualityLevel: "needs_review",
                candidateQualityCodes: ["requires_explicit_event_date_fact_review"],
                candidateQualityExplanation: "Event/date facts are source-backed candidates only. Approve only after the proposed date and source quote match.",
                sourceEvidenceRecord: sourceEvidenceRecord,
                lifecycleHistory: lifecycleHistory
            )
        }
    }

    private func eventDateFactSafeNextCommands(
        candidate: SecondBrainFactValidityCandidateView,
        sourceItem: CiderRoutingItemSummary
    ) -> [String] {
        orderedUnique([
            "cider-cli item context \(sourceItem.type) \(sourceItem.id.uuidString) --json",
            "cider-cli item event-date-facts inspect \(candidate.id) --json",
            "cider-cli item fact-validity inspect \(candidate.id) --json",
            "cider-cli review approve \(candidate.id) --json",
            "cider-cli review reject \(candidate.id) --reason <reason> --json",
            "cider-cli review defer \(candidate.id) --reason <reason> --json",
            "cider-cli review list --kind event_date_fact --json",
        ])
    }

    private func enrichmentReasonCodes(status: String?, lastEnrichedAt: Date?) -> [String] {
        if status == "failed" || status == "error" {
            return ["enrichment_failed"]
        }
        if status == "complete", lastEnrichedAt == nil {
            return ["enrichment_complete_missing_timestamp"]
        }
        if lastEnrichedAt != nil {
            return ["enrichment_attempted_incomplete"]
        }
        return ["enrichment_missing_metadata"]
    }

    private func enrichmentDiagnosisReason(
        status: String?,
        lastEnrichedAt: Date?
    ) -> (id: String, summary: String) {
        let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus?.isEmpty != false {
            return (
                "missing_status",
                "Bookmark has no enrichment status."
            )
        }
        if normalizedStatus == "complete", lastEnrichedAt == nil {
            return (
                "complete_missing_timestamp",
                "Bookmark says enrichment is complete but has no last enriched timestamp."
            )
        }
        if normalizedStatus == "failed" || normalizedStatus == "error" {
            return (
                "failed",
                "Bookmark enrichment previously failed or errored."
            )
        }
        if lastEnrichedAt != nil {
            return (
                "attempted_incomplete",
                "Bookmark has an enrichment timestamp but is not marked complete."
            )
        }
        return (
            "never_enriched",
            "Bookmark has no enrichment timestamp and is still incomplete."
        )
    }

    private func enrichmentReconciliationProposal(
        item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails
    ) -> (
        groupID: String,
        summary: String,
        proposedStatus: String?,
        proposedLastEnrichedAt: Date?,
        evidence: [String]
    ) {
        let aiEvidence = compactEvidence([
            ("ai_summary", details.aiSummary),
            ("ocr_text", details.ocrText),
            ("dominant_colors", details.dominantColors),
        ])
        if !aiEvidence.isEmpty {
            return (
                "can_mark_complete_from_ai_fields",
                "Bookmark has AI enrichment fields but no enrichment status; dry-run proposes marking it complete.",
                "complete",
                details.lastEnrichedAt ?? item.updatedAt,
                aiEvidence
            )
        }

        let metadataEvidence = compactEvidence([
            ("media_type", details.mediaType),
            ("thumbnail_relative_path", details.thumbnailRelativePath),
            ("thumbnail_remote_url", details.thumbnailRemoteURL),
            ("original_image_path", details.originalImagePath),
            ("carousel_image_paths", details.carouselImagePaths),
            ("preferred_hero_mode", details.preferredHeroMode),
        ]) + (details.readerUnavailable == nil ? [] : ["reader_unavailable"])
        if !metadataEvidence.isEmpty {
            return (
                "can_mark_partial_from_metadata_fields",
                "Bookmark has non-AI metadata fields but no enrichment status; dry-run proposes marking it partial.",
                "partial",
                details.lastEnrichedAt ?? item.updatedAt,
                metadataEvidence
            )
        }

        return (
            "needs_enrichment_run",
            "Bookmark has no stored enrichment evidence; leave it queued for enrichment.",
            nil,
            nil,
            []
        )
    }

    private func enrichmentReconciliationPlanItem(
        item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails,
        plan: (
            groupID: String,
            summary: String,
            proposedStatus: String?,
            proposedLastEnrichedAt: Date?,
            evidence: [String]
        )
    ) -> CiderReviewEnrichmentReconciliationPlanItem {
        CiderReviewEnrichmentReconciliationPlanItem(
            groupID: plan.groupID,
            itemID: item.id,
            title: item.title,
            url: details.url,
            relativePath: item.relativePath,
            currentStatus: details.enrichmentStatus,
            currentLastEnrichedAt: details.lastEnrichedAt,
            proposedStatus: plan.proposedStatus,
            proposedLastEnrichedAt: plan.proposedLastEnrichedAt,
            proposalReason: plan.summary,
            evidence: plan.evidence
        )
    }

    private func compactEvidence(_ pairs: [(String, String?)]) -> [String] {
        pairs.compactMap { key, value in
            guard let value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return key
        }
    }

    private func enrichmentDiagnosisSort(
        _ lhs: CiderRoutingItemSummary,
        _ rhs: CiderRoutingItemSummary
    ) -> Bool {
        if lhs.relativePath != rhs.relativePath {
            return (lhs.relativePath ?? "") < (rhs.relativePath ?? "")
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func inboxReviewItem(
        item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails?,
        now: Date
    ) -> CiderReviewQueueItem {
        CiderReviewQueueItem(
            id: "review-inbox-\(item.id.uuidString)",
            kind: "inbox_backlog",
            source: "item",
            itemID: item.id,
            itemType: item.type,
            title: item.title,
            relativePath: item.relativePath,
            reason: "Item is still in Inbox without a routing decision.",
            reasonCodes: ["inbox_unrouted"],
            suggestedAction: "Route to folder",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["correct", "defer"],
            routeIntents: routeIntents(for: item, details: details)
        )
    }

    private func routeIntents(
        for item: CiderRoutingItemSummary,
        details: BookmarkReviewDetails?
    ) -> [CiderCaptureResult.RouteIntent] {
        guard item.type == "bookmark", let details else { return [] }
        return CiderCaptureIntentStagingService.routeIntents(for: .init(
            title: item.title,
            urlString: details.url,
            sourceFile: nil,
            sourceText: details.aiSummary,
            sourceContext: nil
        ))
    }

    private func duplicateReviewItems(now: Date) -> [CiderReviewQueueItem] {
        duplicateFindingsProvider().compactMap { finding in
            guard let firstItem = finding.items.first,
                  let itemID = UUID(uuidString: firstItem.id) else {
                return nil
            }
            return CiderReviewQueueItem(
                id: "review-duplicate-\(finding.id)",
                kind: "duplicate_candidate",
                source: "duplicate_auditor",
                itemID: itemID,
                itemType: finding.entityType.rawValue,
                title: finding.summary,
                relativePath: firstItem.path,
                reason: finding.detail,
                reasonCodes: ["duplicate_\(reasonCodeSuffix(for: finding.kind.rawValue))"],
                suggestedAction: "Review duplicate candidates",
                reviewState: "needs_review",
                confidence: duplicateConfidenceScore(finding.confidence),
                routingDecisionID: nil,
                target: nil,
                createdAt: now,
                safeActions: ["inspect_duplicates", "manual_review"],
                candidateRef: "duplicate_candidate:\(finding.id)",
                storage: [
                    "service": "VaultDuplicateAuditor",
                    "kind": "duplicate_candidate",
                    "lifecycleExtensionPoint": "review_lifecycle_events can store duplicate_candidate:<id> decisions when duplicate mutation flows are added",
                ],
                truthState: "reviewable_candidate_not_truth",
                lifecycleHistory: [
                    CiderReviewQueueLifecycleEventRecord(SecondBrainReviewLifecycleEvent(
                        id: "duplicate-candidate-suggested-\(finding.id)",
                        owner: SecondBrainOwnerRef(ownerType: "duplicate_candidate", ownerID: finding.id),
                        candidateRef: "duplicate_candidate:\(finding.id)",
                        lifecycleState: "needs_review",
                        eventKind: "suggested",
                        actor: "system",
                        source: "duplicate_auditor",
                        toolName: "VaultDuplicateAuditor",
                        reason: finding.detail,
                        metadata: [
                            "entity_type": finding.entityType.rawValue,
                            "duplicate_kind": finding.kind.rawValue,
                            "confidence": finding.confidence.rawValue,
                        ],
                        createdAt: now
                    ))
                ]
            )
        }
    }

    private func captureWorklistItem(from item: CiderReviewQueueItem) -> CiderCaptureReviewWorklistItem {
        let severity: String
        let priority: Int
        switch item.kind {
        case "duplicate_candidate":
            severity = "high"
            priority = 20
        case "low_confidence_routing":
            severity = "medium"
            priority = 30
        case "enrichment":
            severity = item.reviewState == "needs_review" ? "medium" : "low"
            priority = item.reviewState == "needs_review" ? 40 : 60
        default:
            severity = item.reviewState == "needs_review" ? "medium" : "low"
            priority = 70
        }
        var routingState: [String: String]?
        if let target = item.target {
            routingState = [
                "reviewState": item.reviewState,
                "targetKind": target.kind,
                "targetName": target.name,
                "targetPath": target.relativePath,
            ]
            if let confidence = item.confidence {
                routingState?["confidence"] = String(confidence)
            }
            if let routingDecisionID = item.routingDecisionID {
                routingState?["routingDecisionID"] = routingDecisionID.uuidString
            }
        }
        return CiderCaptureReviewWorklistItem(
            id: "capture-worklist-\(item.id)",
            kind: item.kind,
            source: item.source,
            ownerType: item.itemType,
            ownerID: item.itemID.uuidString,
            itemID: item.itemID,
            itemType: item.itemType,
            title: item.title,
            relativePath: item.relativePath,
            reason: item.reason,
            reasonCodes: item.reasonCodes,
            severity: severity,
            priority: priority,
            reviewState: item.reviewState,
            provenance: [
                "source": item.source,
                "kind": item.kind,
            ],
            routingState: routingState,
            indexingStatus: nil,
            enrichmentStatus: item.kind == "enrichment" ? item.reviewState : nil,
            attachmentSummary: nil,
            createdAt: item.createdAt,
            safeNextCommands: item.safeNextCommands.isEmpty
                ? itemSafeInspectionCommands(type: item.itemType, id: item.itemID, title: item.title)
                : item.safeNextCommands,
            confidence: item.confidence,
            candidateID: item.candidateID,
            candidateRef: item.candidateRef,
            sourceQuote: item.sourceQuote,
            possibleTypes: item.possibleTypes,
            possibleRelations: item.possibleRelations,
            candidateActions: item.candidateActions,
            memoryKind: item.memoryKind,
            linkedOwnerRefs: item.linkedOwnerRefs,
            observedDate: item.observedDate,
            memoryKey: item.memoryKey,
            memoryStatus: item.memoryStatus,
            proposedDate: item.proposedDate,
            eventLabel: item.eventLabel,
            factKind: item.factKind,
            targetRef: item.targetRef,
            factConfidence: item.factConfidence,
            reviewFamily: item.reviewFamily,
            sourceItemRef: item.sourceItemRef,
            sourceItemTitle: item.sourceItemTitle,
            sourceItemDate: item.sourceItemDate,
            extractionReason: item.extractionReason,
            proposedChange: item.proposedChange,
            storage: item.storage,
            truthState: item.truthState,
            acceptEffect: item.acceptEffect,
            rejectEffect: item.rejectEffect,
            candidateQualityLevel: item.candidateQualityLevel,
            candidateQualityCodes: item.candidateQualityCodes,
            candidateQualityExplanation: item.candidateQualityExplanation,
            sourceEvidenceRecord: item.sourceEvidenceRecord,
            targetOptions: item.targetOptions,
            routeIntents: item.routeIntents
        )
    }

    private func unsupportedAttachmentWorklistItems(in db: CiderDatabase, now: Date) throws -> [CiderCaptureReviewWorklistItem] {
        let stmt = try db.prepare("""
            SELECT e.id, e.source_kind, e.surface, e.channel, e.channel_id, e.thread_id,
                   e.message_id, e.sender_id, e.sender_name, e.source_text,
                   e.attachment_count, e.created_at,
                   o.kind, o.review_state, o.evidence, o.metadata,
                   COUNT(a.id) AS attachment_row_count,
                   SUM(CASE WHEN a.local_path IS NULL AND a.remote_url IS NOT NULL THEN 1 ELSE 0 END) AS remote_only_count,
                   GROUP_CONCAT(COALESCE(a.filename, a.source_attachment_id, a.remote_url), ', ') AS attachment_names
            FROM capture_events e
            JOIN enrichment_outputs o
              ON o.owner_type = 'capture_event'
             AND o.owner_id = e.id
             AND o.review_state IN ('needs_review', 'suggested')
             AND o.kind IN ('unsupported_chat_attachment')
            LEFT JOIN capture_attachments a
              ON a.capture_event_id = e.id
            GROUP BY e.id, o.id
            ORDER BY e.created_at DESC, e.id DESC;
            """)
        var items: [CiderCaptureReviewWorklistItem] = []
        while try stmt.step() {
            let eventID = stmt.string(at: 0)
            let sourceKind = stmt.string(at: 1)
            let surface = stmt.optionalString(at: 2)
            let channel = stmt.optionalString(at: 3)
            let channelID = stmt.optionalString(at: 4)
            let threadID = stmt.optionalString(at: 5)
            let messageID = stmt.optionalString(at: 6)
            let senderID = stmt.optionalString(at: 7)
            let senderName = stmt.optionalString(at: 8)
            let sourceText = stmt.optionalString(at: 9)
            let attachmentCount = stmt.int(at: 10)
            let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 11))
            let reviewState = stmt.string(at: 13)
            let evidence = stmt.optionalString(at: 14) ?? "Capture has unsupported attachment content that needs review."
            let attachmentRowCount = stmt.int(at: 16)
            let remoteOnlyCount = stmt.int(at: 17)
            let attachmentNames = stmt.optionalString(at: 18)
            var reasonCodes = ["unsupported_attachment"]
            if remoteOnlyCount > 0 {
                reasonCodes.append("remote_only_attachment")
            }
            var provenance: [String: String] = [
                "sourceKind": sourceKind,
            ]
            if let surface { provenance["surface"] = surface }
            if let channel { provenance["channel"] = channel }
            if let channelID { provenance["channelID"] = channelID }
            if let threadID { provenance["threadID"] = threadID }
            if let messageID { provenance["messageID"] = messageID }
            if let senderID { provenance["senderID"] = senderID }
            if let senderName { provenance["senderName"] = senderName }
            if let sourceText, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                provenance["sourceTextPreview"] = String(sourceText.prefix(120))
            }
            var attachmentSummary = [
                "count": String(max(attachmentCount, attachmentRowCount)),
                "remoteOnlyCount": String(remoteOnlyCount),
            ]
            if let attachmentNames, !attachmentNames.isEmpty {
                attachmentSummary["names"] = attachmentNames
            }
            items.append(CiderCaptureReviewWorklistItem(
                id: "capture-worklist-unsupported-\(eventID)",
                kind: "unsupported_attachment",
                source: "capture_event",
                ownerType: "capture_event",
                ownerID: eventID,
                itemID: nil,
                itemType: "capture_event",
                title: attachmentNames ?? "Unsupported capture attachment",
                relativePath: nil,
                reason: evidence,
                reasonCodes: reasonCodes,
                severity: "high",
                priority: 10,
                reviewState: reviewState,
                provenance: provenance,
                routingState: nil,
                indexingStatus: nil,
                enrichmentStatus: reviewState,
                attachmentSummary: attachmentSummary,
                createdAt: createdAt,
                safeNextCommands: [
                    "cider-cli item backlinks capture_event \(eventID) --json",
                    "cider-cli item owner-get capture_event \(eventID) --json",
                    "cider-cli review summary --json",
                ]
            ))
        }
        return items
    }

    private func indexingWorklistItems(in db: CiderDatabase, now: Date) throws -> [CiderCaptureReviewWorklistItem] {
        let activeDatabaseTypes = LibraryEntityType.activeCases.map(ItemLinkService.databaseItemType(for:))
        guard !activeDatabaseTypes.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: activeDatabaseTypes.count).joined(separator: ", ")
        let stmt = try db.prepare("""
            SELECT i.id, i.type, i.title, i.relative_path, i.updated_at,
                   COUNT(c.id) AS chunk_count,
                   MAX(c.updated_at) AS newest_chunk_updated_at
            FROM items i
            LEFT JOIN content_chunks c
              ON c.owner_id = i.id
             AND c.owner_type = CASE WHEN i.type = 'event' THEN 'dateCard' ELSE i.type END
            WHERE i.type IN (\(placeholders))
            GROUP BY i.id, i.type, i.title, i.relative_path, i.updated_at
            HAVING chunk_count = 0 OR newest_chunk_updated_at IS NULL OR newest_chunk_updated_at < i.updated_at
            ORDER BY i.updated_at DESC, i.title COLLATE NOCASE ASC;
            """)
        for (index, type) in activeDatabaseTypes.enumerated() {
            stmt.bind(type, at: Int32(index + 1))
        }
        var items: [CiderCaptureReviewWorklistItem] = []
        while try stmt.step() {
            guard let itemID = UUID(uuidString: stmt.string(at: 0)) else { continue }
            let rawType = stmt.string(at: 1)
            let itemType = rawType == "event" ? "dateCard" : rawType
            let title = stmt.string(at: 2)
            let relativePath = stmt.optionalString(at: 3)
            let itemUpdatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 4))
            let chunkCount = stmt.int(at: 5)
            let newestChunkUpdatedAt = stmt.optionalDouble(at: 6).map(DatabaseHelpers.decodeDate)
            let indexingStatus = chunkCount == 0 ? "missing" : "stale"
            let reasonCode = chunkCount == 0 ? "index_missing_chunks" : "index_stale_chunks"
            let reason = chunkCount == 0
                ? "Item has no searchable content chunks."
                : "Item content chunks are older than the item row."
            var provenance: [String: String] = [
                "source": "content_chunks",
                "itemUpdatedAt": ISO8601DateFormatter().string(from: itemUpdatedAt),
                "chunkCount": String(chunkCount),
            ]
            if let newestChunkUpdatedAt {
                provenance["newestChunkUpdatedAt"] = ISO8601DateFormatter().string(from: newestChunkUpdatedAt)
            }
            items.append(CiderCaptureReviewWorklistItem(
                id: "capture-worklist-index-\(itemID.uuidString)",
                kind: "indexing",
                source: "content_chunks",
                ownerType: itemType,
                ownerID: itemID.uuidString,
                itemID: itemID,
                itemType: itemType,
                title: title,
                relativePath: relativePath,
                reason: reason,
                reasonCodes: [reasonCode],
                severity: "medium",
                priority: indexingStatus == "missing" ? 35 : 45,
                reviewState: "needs_review",
                provenance: provenance,
                routingState: nil,
                indexingStatus: indexingStatus,
                enrichmentStatus: nil,
                attachmentSummary: nil,
                createdAt: itemUpdatedAt,
                safeNextCommands: [
                    "cider-cli item get \(itemType) \(itemID.uuidString) --json",
                    "cider-cli item context \(itemType) \(itemID.uuidString) --json",
                    "cider-cli item search-debug \"\(escapedCommandArgument(title))\" --limit 5 --json",
                    "cider-cli item doctor --json",
                ]
            ))
        }
        return items
    }

    private func itemSafeInspectionCommands(type: String, id: UUID, title: String) -> [String] {
        [
            "cider-cli item get \(type) \(id.uuidString) --json",
            "cider-cli item context \(type) \(id.uuidString) --json",
            "cider-cli item search-debug \"\(escapedCommandArgument(title))\" --limit 5 --json",
            "cider-cli review list --limit 20 --json",
        ]
    }

    private func escapedCommandArgument(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            output.append(value)
        }
        return output
    }

    private func reasonCodeSuffix(for rawValue: String) -> String {
        var result = ""
        var previousWasLowercaseOrDigit = false
        for character in rawValue {
            if character.isUppercase {
                if previousWasLowercaseOrDigit {
                    result.append("_")
                }
                result.append(character.lowercased())
                previousWasLowercaseOrDigit = false
            } else {
                result.append(character)
                previousWasLowercaseOrDigit = character.isLowercase || character.isNumber
            }
        }
        return result
    }

    private func duplicateConfidenceScore(_ confidence: VaultDuplicateAuditor.Confidence) -> Double {
        switch confidence {
        case .exact:
            return 1
        case .likely:
            return 0.75
        case .possible:
            return 0.5
        }
    }

    private func sortRank(_ item: CiderReviewQueueItem) -> Int {
        switch item.kind {
        case "graph_candidate":
            return 0
        case "memory_candidate":
            return 1
        case "event_date_fact":
            return 2
        case "low_confidence_routing":
            return 3
        case "enrichment":
            return 4
        case "duplicate_candidate":
            return 5
        case "inbox_backlog":
            return 6
        case "deferred_routing":
            return 7
        default:
            return 8
        }
    }

    private func reviewGroups(for items: [CiderReviewQueueItem]) -> [CiderReviewQueueGroup] {
        struct Accumulator {
            var kind: String
            var reviewState: String
            var requiredSafeAction: String
            var itemType: String
            var count: Int
            var sampleItems: [CiderReviewQueueItem]
        }

        var accumulators: [String: Accumulator] = [:]
        for item in items {
            let safeAction = primarySafeAction(for: item)
            let id = "\(item.kind):\(item.reviewState):\(safeAction):\(item.itemType)"
            if var accumulator = accumulators[id] {
                accumulator.count += 1
                if accumulator.sampleItems.count < 3 {
                    accumulator.sampleItems.append(item)
                }
                accumulators[id] = accumulator
            } else {
                accumulators[id] = Accumulator(
                    kind: item.kind,
                    reviewState: item.reviewState,
                    requiredSafeAction: safeAction,
                    itemType: item.itemType,
                    count: 1,
                    sampleItems: [item]
                )
            }
        }

        return accumulators
            .values
            .map { accumulator in
                CiderReviewQueueGroup(
                    id: "\(accumulator.kind):\(accumulator.reviewState):\(accumulator.requiredSafeAction):\(accumulator.itemType)",
                    kind: accumulator.kind,
                    reviewState: accumulator.reviewState,
                    requiredSafeAction: accumulator.requiredSafeAction,
                    itemType: accumulator.itemType,
                    count: accumulator.count,
                    sampleItems: accumulator.sampleItems
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = groupSortRank(lhs)
                let rhsRank = groupSortRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }

    private func batchEnrichmentPreview(
        for items: [CiderReviewQueueItem],
        sampleLimit: Int
    ) -> CiderReviewQueueBatchEnrichmentPreview {
        let candidates = items.filter { item in
            item.kind == "enrichment"
                && item.itemType == "bookmark"
                && item.safeActions.contains("enrich")
        }
        let exclusions = items.compactMap { batchEnrichmentExclusionReason(for: $0) }
        let cappedLimit = max(0, sampleLimit)

        return CiderReviewQueueBatchEnrichmentPreview(
            action: "review.enrich",
            isMutating: false,
            candidateCount: candidates.count,
            candidateSampleLimit: cappedLimit,
            candidateSamples: Array(candidates.prefix(cappedLimit)),
            excludedCount: exclusions.count,
            exclusionsByReason: groupedCounts(exclusions)
        )
    }

    private func batchEnrichmentExclusionReason(for item: CiderReviewQueueItem) -> String? {
        if item.kind == "enrichment",
           item.itemType == "bookmark",
           item.safeActions.contains("enrich") {
            return nil
        }
        switch item.kind {
        case "low_confidence_routing", "deferred_routing":
            return "routing_requires_explicit_approval"
        case "graph_candidate":
            return "graph_candidate_requires_review"
        case "memory_candidate":
            return "memory_candidate_requires_review"
        case "event_date_fact":
            return "event_date_fact_requires_review"
        case "inbox_backlog":
            return "manual_routing_required"
        case "duplicate_candidate":
            return "duplicate_review_required"
        default:
            if item.itemType != "bookmark" {
                return "unsupported_item_type"
            }
            return "not_enrichment_candidate"
        }
    }

    private func primarySafeAction(for item: CiderReviewQueueItem) -> String {
        if item.kind == "event_date_fact", item.safeActions.contains("accept") {
            return "accept"
        }
        for action in ["enrich", "approve", "inspect_source", "correct", "defer"] where item.safeActions.contains(action) {
            return action
        }
        return item.safeActions.first ?? "none"
    }

    private func groupSortRank(_ group: CiderReviewQueueGroup) -> Int {
        switch group.kind {
        case "low_confidence_routing":
            return 0
        case "graph_candidate":
            return 1
        case "memory_candidate":
            return 2
        case "event_date_fact":
            return 3
        case "enrichment":
            return group.reviewState == "needs_review" ? 4 : 5
        case "duplicate_candidate":
            return 6
        case "inbox_backlog":
            return 7
        case "deferred_routing":
            return 8
        default:
            return 9
        }
    }

    private func batchJobSummaries(
        from entries: [MutationAuditEntry],
        items: [UUID: CiderRoutingItemSummary],
        limit: Int,
        itemSampleLimit: Int
    ) -> [CiderReviewActionJobSummary] {
        let grouped = Dictionary(grouping: entries) { entry in
            entry.metadata["batchID"] ?? ""
        }
        let cappedLimit = max(0, limit)
        let cappedSampleLimit = max(0, itemSampleLimit)

        return grouped.compactMap { rawBatchID, entries -> CiderReviewActionJobSummary? in
            guard let batchID = UUID(uuidString: rawBatchID) else { return nil }
            let sortedEntries = entries.sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
            guard let newest = sortedEntries.first,
                  let oldest = sortedEntries.last else { return nil }
            let candidateCount = newest.metadata["candidateCount"].flatMap(Int.init) ?? entries.count
            let excludedCount = newest.metadata["excludedCount"].flatMap(Int.init) ?? 0
            let scheduleEntries = entries.filter { $0.action == "review.enrich.batch.schedule" }
            let resultEntries = entries.filter { $0.action == "review.enrich.batch.result" }
            let latestByItem = Dictionary(grouping: sortedEntries, by: \.itemID)
                .compactMapValues { grouped in grouped.sorted {
                    if $0.occurredAt != $1.occurredAt {
                        return $0.occurredAt > $1.occurredAt
                    }
                    if $0.action != $1.action {
                        return $0.action == "review.enrich.batch.result"
                    }
                    return $0.id.uuidString > $1.id.uuidString
                }.first }
            let sampleEntries = latestByItem.values.sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
            let failures = resultEntries.filter { entry in
                let status = entry.afterState["status"] ?? "scheduled"
                return status != "completed" && status != "skipped"
            }
            let resultState: String
            if resultEntries.isEmpty {
                resultState = "scheduled"
            } else if failures.isEmpty && resultEntries.count >= scheduleEntries.count {
                resultState = "completed"
            } else if failures.count == resultEntries.count && resultEntries.count >= scheduleEntries.count {
                resultState = "failed"
            } else {
                resultState = "partial"
            }
            let samples = sampleEntries.prefix(cappedSampleLimit).map { entry in
                let item = items[entry.itemID]
                return CiderReviewActionJobItemSample(
                    itemID: entry.itemID,
                    itemType: entry.itemType,
                    title: item?.title ?? entry.itemID.uuidString,
                    status: entry.afterState["status"] ?? "scheduled"
                )
            }

            return CiderReviewActionJobSummary(
                action: "review.enrich.batch",
                actionFamily: "enrichment",
                jobID: batchID.uuidString,
                batchID: batchID,
                firstScheduledAt: oldest.occurredAt,
                lastScheduledAt: newest.occurredAt,
                actor: newest.source.rawValue,
                source: newest.source.rawValue,
                resultState: resultState,
                candidateCount: candidateCount,
                scheduledCount: scheduleEntries.count,
                excludedCount: excludedCount,
                failedCount: failures.count + max(0, candidateCount - scheduleEntries.count),
                itemSamples: samples,
                safeActions: ["review summary", "review list", "bookmark get"]
            )
        }
        .sorted {
            if $0.lastScheduledAt != $1.lastScheduledAt {
                return $0.lastScheduledAt > $1.lastScheduledAt
            }
            return $0.jobID > $1.jobID
        }
        .prefix(cappedLimit)
        .map { $0 }
    }

    private func routingActionJobSummaries(
        from entries: [MutationAuditEntry],
        items: [UUID: CiderRoutingItemSummary],
        itemSampleLimit: Int
    ) -> [CiderReviewActionJobSummary] {
        let cappedSampleLimit = max(0, itemSampleLimit)
        return entries.compactMap { entry in
            guard let routingDecisionID = entry.metadata["routingDecisionID"] else { return nil }
            let item = items[entry.itemID]
            let resultState = entry.afterState["reviewState"] ?? entry.action.replacingOccurrences(of: "review.routing.", with: "")
            let samples = cappedSampleLimit > 0
                ? [
                    CiderReviewActionJobItemSample(
                        itemID: entry.itemID,
                        itemType: entry.itemType,
                        title: item?.title ?? entry.itemID.uuidString,
                        status: resultState
                    ),
                ]
                : []

            return CiderReviewActionJobSummary(
                action: entry.action,
                actionFamily: "routing",
                jobID: routingDecisionID,
                batchID: nil,
                firstScheduledAt: entry.occurredAt,
                lastScheduledAt: entry.occurredAt,
                actor: entry.metadata["actor"] ?? entry.source.rawValue,
                source: entry.source.rawValue,
                resultState: resultState,
                candidateCount: 1,
                scheduledCount: 1,
                excludedCount: 0,
                failedCount: 0,
                itemSamples: samples,
                safeActions: ["review summary", "review list", "routing explain"]
            )
        }
    }

    private func routingActionResult(
        action: String,
        status: String,
        message: String,
        actor: String,
        before: CiderRoutingExplanation,
        after: CiderRoutingExplanation
    ) throws -> CiderReviewRoutingActionResult {
        guard let latest = after.latestDecision else {
            throw CiderRoutingDecisionError.decisionNotFound(after.item.id)
        }
        let remaining = try list(
            limit: Int.max,
            kind: "low_confidence_routing",
            reviewState: "needs_review"
        ).items.count
        let result = CiderReviewRoutingActionResult(
            action: action,
            itemID: after.item.id,
            itemType: after.item.type,
            title: after.item.title,
            status: status,
            message: message,
            actor: actor,
            reviewState: latest.reviewState,
            routingDecisionID: latest.id,
            supersedesDecisionID: latest.supersedesDecisionID,
            target: latest.target,
            remainingActiveRoutingReviewCount: remaining,
            safeActions: ["review summary", "review list", "routing explain"]
        )

        MutationAuditService(database: resolvedDatabase).record(
            action: action,
            itemType: after.item.type,
            itemID: after.item.id,
            before: before.latestDecision.map(routingDecisionAuditState) ?? [:],
            after: routingDecisionAuditState(latest),
            metadata: [
                "actor": actor,
                "routingDecisionID": latest.id.uuidString,
                "supersedesDecisionID": latest.supersedesDecisionID?.uuidString ?? "",
                "targetRelativePath": latest.target.relativePath,
                "remainingActiveRoutingReviewCount": String(remaining),
            ].filter { !$0.value.isEmpty },
            source: actor == "agent" ? .agent : nil
        )

        if let db = resolvedDatabase {
            try SecondBrainReviewLifecycleService(database: db).record(
                SecondBrainReviewLifecycleEvent(
                    owner: SecondBrainOwnerRef(ownerType: "routing_decision", ownerID: latest.id.uuidString),
                    candidateRef: "routing_decision:\(latest.id.uuidString)",
                    lifecycleState: latest.reviewState,
                    eventKind: status,
                    actor: actor,
                    source: action,
                    toolName: action,
                    reason: latest.reason,
                    supersedesRef: latest.supersedesDecisionID.map { "routing_decision:\($0.uuidString)" },
                    metadata: [
                        "item_ref": "\(after.item.type):\(after.item.id.uuidString)",
                        "target_relative_path": latest.target.relativePath,
                        "confidence": String(latest.confidence),
                    ],
                    createdAt: latest.createdAt
                )
            )
        }

        return result
    }

    private func routingDecisionAuditState(_ decision: CiderRoutingDecision) -> [String: String] {
        [
            "decisionID": decision.id.uuidString,
            "reviewState": decision.reviewState,
            "targetRelativePath": decision.target.relativePath,
            "confidence": String(decision.confidence),
            "reason": decision.reason,
            "actor": decision.actor,
            "source": decision.source,
        ]
    }

    private func groupedCounts(_ values: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts
    }
}
