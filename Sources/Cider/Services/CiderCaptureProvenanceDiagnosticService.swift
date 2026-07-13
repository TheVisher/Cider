import CryptoKit
import Foundation

enum CiderCaptureProvenanceGapClassification: String, Codable, CaseIterable {
    case evidenceBackedDuplicate = "evidence_backed_duplicate"
    case explicitFailureOrAbandonment = "explicit_failure_or_abandonment"
    case survivingCanonicalItemWithRecoverableProvenance = "surviving_canonical_item_with_recoverable_provenance"
    case unresolvedProvenanceGap = "unresolved_provenance_gap"
}

struct CiderCaptureProvenanceGapCounts: Codable, Equatable {
    var evidenceBackedDuplicate = 0
    var explicitFailureOrAbandonment = 0
    var survivingCanonicalItemWithRecoverableProvenance = 0
    var unresolvedProvenanceGap = 0

    mutating func increment(_ classification: CiderCaptureProvenanceGapClassification) {
        switch classification {
        case .evidenceBackedDuplicate:
            evidenceBackedDuplicate += 1
        case .explicitFailureOrAbandonment:
            explicitFailureOrAbandonment += 1
        case .survivingCanonicalItemWithRecoverableProvenance:
            survivingCanonicalItemWithRecoverableProvenance += 1
        case .unresolvedProvenanceGap:
            unresolvedProvenanceGap += 1
        }
    }

    func toDictionary() -> [String: Int] {
        [
            CiderCaptureProvenanceGapClassification.evidenceBackedDuplicate.rawValue: evidenceBackedDuplicate,
            CiderCaptureProvenanceGapClassification.explicitFailureOrAbandonment.rawValue: explicitFailureOrAbandonment,
            CiderCaptureProvenanceGapClassification.survivingCanonicalItemWithRecoverableProvenance.rawValue: survivingCanonicalItemWithRecoverableProvenance,
            CiderCaptureProvenanceGapClassification.unresolvedProvenanceGap.rawValue: unresolvedProvenanceGap,
        ]
    }
}

struct CiderCaptureProvenanceGapFinding: Codable, Equatable, Identifiable {
    var id: String { captureEventID }
    var captureEventID: String
    var captureEventRef: String
    var sourceKind: String
    var classification: CiderCaptureProvenanceGapClassification
    var reasonCode: String
    var reason: String
    var itemRef: String?
    var evidenceRefs: [String]
    var truthBoundary: String
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "captureEventID": captureEventID,
            "captureEventRef": captureEventRef,
            "sourceKind": sourceKind,
            "classification": classification.rawValue,
            "reasonCode": reasonCode,
            "reason": reason,
            "evidenceRefs": evidenceRefs,
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
            "safeVerificationCommands": safeVerificationCommands,
        ]
        if let itemRef { result["itemRef"] = itemRef }
        return result
    }
}

struct CiderCaptureProvenanceDiagnosticReport: Codable, Equatable {
    var command = "capture.provenance-gaps"
    var readOnly = true
    var changed = false
    var requestedLimit: Int
    var appliedLimit: Int
    var maximumLimit: Int
    var totalMissingCount: Int
    var scannedCount: Int
    var omittedCount: Int
    var hasMore: Bool
    var counts: CiderCaptureProvenanceGapCounts
    var findings: [CiderCaptureProvenanceGapFinding]
    var truthBoundary: String
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        [
            "ok": true,
            "command": command,
            "readOnly": readOnly,
            "changed": changed,
            "requestedLimit": requestedLimit,
            "appliedLimit": appliedLimit,
            "maximumLimit": maximumLimit,
            "totalMissingCount": totalMissingCount,
            "scannedCount": scannedCount,
            "omittedCount": omittedCount,
            "hasMore": hasMore,
            "counts": counts.toDictionary(),
            "findings": findings.map { $0.toDictionary() },
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

enum CiderCaptureProvenanceExplanationError: String, Error, Equatable, LocalizedError {
    case malformedCaptureEventRef = "malformed_capture_event_ref"
    case captureEventNotFound = "capture_event_not_found"
    case unsupportedSourceKind = "unsupported_capture_source_kind"
    case captureEventNoLongerHasGap = "capture_event_no_longer_has_provenance_gap"
    case malformedDuplicateAuditContinuation = "malformed_duplicate_audit_continuation"
    case forgedDuplicateAuditContinuation = "forged_duplicate_audit_continuation"
    case mismatchedDuplicateAuditContinuation = "mismatched_duplicate_audit_continuation"
    case staleDuplicateAuditContinuation = "stale_duplicate_audit_continuation"
    case duplicateAuditLimitOutOfRange = "duplicate_audit_limit_out_of_range"

    var errorDescription: String? { rawValue }
}

enum CiderCaptureProvenanceEvidenceCategory: String, Codable, Equatable {
    case captureEvent = "capture_event"
    case producedItemRelation = "produced_item_relation"
    case captureMetadata = "capture_metadata"
    case canonicalItemReadback = "canonical_item_readback"
    case duplicateAudit = "duplicate_audit"
}

enum CiderCaptureProvenanceEvidenceStatus: String, Codable, Equatable {
    case found
    case missing
    case ambiguous
    case stale
    case malformed
    case capped
    case notApplicable = "not_applicable"
}

struct CiderCaptureProvenanceEvidenceCheck: Codable, Equatable {
    var category: CiderCaptureProvenanceEvidenceCategory
    var status: CiderCaptureProvenanceEvidenceStatus
    var reasonCode: String
    var evidenceRefs: [String]

    func toDictionary() -> [String: Any] {
        [
            "category": category.rawValue,
            "status": status.rawValue,
            "reasonCode": reasonCode,
            "evidenceRefs": evidenceRefs,
        ]
    }
}

enum CiderCaptureProvenanceCandidateEvidenceCategory: String, Codable, Equatable, Hashable {
    case exactPersistedItemReference = "exact_persisted_item_reference"
    case canonicalURLMatch = "canonical_url_match"
    case nearbyDuplicateAuditMatch = "nearby_duplicate_audit_match"
}

enum CiderCaptureProvenanceCandidateDiscoveryOutcome: String, Codable, Equatable, Hashable {
    case zeroCandidates = "zero_candidates"
    case oneCandidateInsufficient = "one_candidate_insufficient"
    case multipleCandidatesAmbiguous = "multiple_candidates_ambiguous"
    case cappedCandidateEvidence = "capped_candidate_evidence"
}

struct CiderCaptureProvenanceCandidateEvidenceCount: Codable, Equatable {
    var category: CiderCaptureProvenanceCandidateEvidenceCategory
    var status: CiderCaptureProvenanceEvidenceStatus
    var reasonCode: String
    var candidateCount: Int
    var candidateCountIsLowerBound: Bool
    var candidateRefs: [String]

    func toDictionary() -> [String: Any] {
        [
            "category": category.rawValue,
            "status": status.rawValue,
            "reasonCode": reasonCode,
            "candidateCount": candidateCount,
            "candidateCountIsLowerBound": candidateCountIsLowerBound,
            "candidateRefs": candidateRefs,
        ]
    }
}

struct CiderCaptureProvenanceCandidateDiscovery: Codable, Equatable {
    var readOnly = true
    var changed = false
    var outcome: CiderCaptureProvenanceCandidateDiscoveryOutcome
    var reasonCode: String
    var discoveredCandidateCount: Int
    var discoveredCandidateCountIsLowerBound: Bool
    var countsByEvidenceCategory: [CiderCaptureProvenanceCandidateEvidenceCount]
    var candidateRefs: [String]
    var candidateRefsTruncated: Bool
    var candidateSelected = false
    var saturated: Bool
    var caps: [String: Int]
    var truthBoundary: String
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        [
            "readOnly": readOnly,
            "changed": changed,
            "outcome": outcome.rawValue,
            "reasonCode": reasonCode,
            "discoveredCandidateCount": discoveredCandidateCount,
            "discoveredCandidateCountIsLowerBound": discoveredCandidateCountIsLowerBound,
            "countsByEvidenceCategory": countsByEvidenceCategory.map { $0.toDictionary() },
            "candidateRefs": candidateRefs,
            "candidateRefsTruncated": candidateRefsTruncated,
            "candidateSelected": candidateSelected,
            "saturated": saturated,
            "caps": caps,
            "truthBoundary": truthBoundary,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

struct CiderCaptureDuplicateAuditScanPage: Codable, Equatable {
    var requestedLimit: Int
    var appliedLimit: Int
    var maximumLimit: Int
    var scannedCount: Int
    var cumulativeScannedCount: Int
    var hasMore: Bool
    var saturated: Bool
    var exhausted: Bool
    var scannedAuditRefs: [String]
    var scannedAuditRefsTruncated: Bool
    var continuationToken: String?

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "requestedLimit": requestedLimit,
            "appliedLimit": appliedLimit,
            "maximumLimit": maximumLimit,
            "scannedCount": scannedCount,
            "cumulativeScannedCount": cumulativeScannedCount,
            "hasMore": hasMore,
            "saturated": saturated,
            "exhausted": exhausted,
            "scannedAuditRefs": scannedAuditRefs,
            "scannedAuditRefsTruncated": scannedAuditRefsTruncated,
        ]
        if let continuationToken { result["continuationToken"] = continuationToken }
        return result
    }
}

struct CiderCaptureProvenanceGapExplanation: Codable, Equatable {
    var command = "capture.provenance-gap"
    var readOnly = true
    var changed = false
    var captureEventID: String
    var captureEventRef: String
    var sourceKind: String
    var classification: CiderCaptureProvenanceGapClassification
    var reasonCode: String
    var explanation: String
    var itemRef: String?
    var checkedEvidence: [CiderCaptureProvenanceEvidenceCheck]
    var evidenceRefs: [String]
    var missingEvidenceReasons: [String]
    var caps: [String: Int]
    var duplicateAuditScan: CiderCaptureDuplicateAuditScanPage
    var candidateDiscovery: CiderCaptureProvenanceCandidateDiscovery?
    var truthBoundary: String
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "ok": true,
            "command": command,
            "readOnly": readOnly,
            "changed": changed,
            "captureEventID": captureEventID,
            "captureEventRef": captureEventRef,
            "sourceKind": sourceKind,
            "classification": classification.rawValue,
            "reasonCode": reasonCode,
            "explanation": explanation,
            "checkedEvidence": checkedEvidence.map { $0.toDictionary() },
            "evidenceRefs": evidenceRefs,
            "missingEvidenceReasons": missingEvidenceReasons,
            "caps": caps,
            "duplicateAuditScan": duplicateAuditScan.toDictionary(),
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
            "safeVerificationCommands": safeVerificationCommands,
        ]
        if let itemRef { result["itemRef"] = itemRef }
        if let candidateDiscovery { result["candidateDiscovery"] = candidateDiscovery.toDictionary() }
        return result
    }
}

struct CiderCaptureProvenanceAggregateEvidenceOutcome: Codable, Equatable {
    var category: CiderCaptureProvenanceEvidenceCategory
    var status: CiderCaptureProvenanceEvidenceStatus
    var reasonCode: String

    func toDictionary() -> [String: Any] {
        [
            "category": category.rawValue,
            "status": status.rawValue,
            "reasonCode": reasonCode,
        ]
    }
}

struct CiderCaptureProvenanceGapPatternGroup: Codable, Equatable {
    var sourceKind: String
    var classification: CiderCaptureProvenanceGapClassification
    var reasonCode: String
    var checkedEvidence: [CiderCaptureProvenanceAggregateEvidenceOutcome]
    var timeBucket: String
    var versionBucket: String?
    var count: Int
    var sampleCaptureEventRefs: [String]

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "sourceKind": sourceKind,
            "classification": classification.rawValue,
            "reasonCode": reasonCode,
            "checkedEvidence": checkedEvidence.map { $0.toDictionary() },
            "timeBucket": timeBucket,
            "count": count,
            "sampleCaptureEventRefs": sampleCaptureEventRefs,
        ]
        if let versionBucket { result["versionBucket"] = versionBucket }
        return result
    }
}

struct CiderCaptureProvenanceCandidateOutcomeAggregateCount: Codable, Equatable {
    var outcome: CiderCaptureProvenanceCandidateDiscoveryOutcome
    var count: Int
    var sampleCaptureEventRefs: [String]
    var sampleRefsTruncated: Bool

    func toDictionary() -> [String: Any] {
        [
            "outcome": outcome.rawValue,
            "count": count,
            "sampleCaptureEventRefs": sampleCaptureEventRefs,
            "sampleRefsTruncated": sampleRefsTruncated,
        ]
    }
}

struct CiderCaptureProvenanceCandidateEvidenceAggregateCount: Codable, Equatable {
    var category: CiderCaptureProvenanceCandidateEvidenceCategory
    var eventCount: Int
    var candidateCount: Int
    var candidateCountIsLowerBound: Bool
    var saturated: Bool
    var statusCounts: [String: Int]

    func toDictionary() -> [String: Any] {
        [
            "category": category.rawValue,
            "eventCount": eventCount,
            "candidateCount": candidateCount,
            "candidateCountIsLowerBound": candidateCountIsLowerBound,
            "saturated": saturated,
            "statusCounts": statusCounts,
        ]
    }
}

struct CiderCaptureProvenanceCandidateDiscoveryAggregate: Codable, Equatable {
    var readOnly = true
    var changed = false
    var eligibleCount: Int
    var excludedCount: Int
    var sampledCount: Int
    var sampleRefsTruncated: Bool
    var countsByOutcome: [CiderCaptureProvenanceCandidateOutcomeAggregateCount]
    var countsByEvidenceCategory: [CiderCaptureProvenanceCandidateEvidenceAggregateCount]
    var saturated: Bool
    var caps: [String: Int]
    var truthBoundary: String
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        [
            "readOnly": readOnly,
            "changed": changed,
            "eligibleCount": eligibleCount,
            "excludedCount": excludedCount,
            "sampledCount": sampledCount,
            "sampleRefsTruncated": sampleRefsTruncated,
            "countsByOutcome": countsByOutcome.map { $0.toDictionary() },
            "countsByEvidenceCategory": countsByEvidenceCategory.map { $0.toDictionary() },
            "saturated": saturated,
            "caps": caps,
            "truthBoundary": truthBoundary,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

enum CiderCaptureHistoricalMarkerStatus: String, Codable, Equatable {
    case found
    case missing
    case malformed
    case unsupported
    case stale
    case privacySensitive = "privacy_sensitive"
    case ambiguous
}

enum CiderCaptureProvenanceGuaranteeStatus: String, Codable, Equatable {
    case activeRelationRequired = "active_relation_required"
    case inactiveNonproducing = "inactive_nonproducing"
    case notEvidenced = "not_evidenced"
}

struct CiderCaptureProvenanceHistoricalBoundaryGroup: Codable, Equatable {
    var timeBucket: String
    var schemaMarkerStatus: CiderCaptureHistoricalMarkerStatus
    var versionMarkerStatus: CiderCaptureHistoricalMarkerStatus
    var lifecycleMarkerStatus: CiderCaptureHistoricalMarkerStatus
    var versionBucket: String?
    var lifecycleCapability: String
    var provenanceGuarantee: CiderCaptureProvenanceGuaranteeStatus
    var reasonCodes: [String]
    var count: Int
    var sampleCaptureEventRefs: [String]
    var sampleRefsTruncated: Bool

    func toDictionary() -> [String: Any] {
        var result: [String: Any] = [
            "timeBucket": timeBucket,
            "schemaMarkerStatus": schemaMarkerStatus.rawValue,
            "versionMarkerStatus": versionMarkerStatus.rawValue,
            "lifecycleMarkerStatus": lifecycleMarkerStatus.rawValue,
            "lifecycleCapability": lifecycleCapability,
            "provenanceGuarantee": provenanceGuarantee.rawValue,
            "reasonCodes": reasonCodes,
            "count": count,
            "sampleCaptureEventRefs": sampleCaptureEventRefs,
            "sampleRefsTruncated": sampleRefsTruncated,
        ]
        if let versionBucket { result["versionBucket"] = versionBucket }
        return result
    }
}

struct CiderCaptureProvenanceHistoricalBoundaryReport: Codable, Equatable {
    var readOnly = true
    var changed = false
    var classifiedCount: Int
    var excludedCount: Int
    var sampledCount: Int
    var groups: [CiderCaptureProvenanceHistoricalBoundaryGroup]
    var failClosedCounts: [String: Int]
    var saturated: Bool
    var caps: [String: Int]
    var truthBoundary: String
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        [
            "readOnly": readOnly,
            "changed": changed,
            "classifiedCount": classifiedCount,
            "excludedCount": excludedCount,
            "sampledCount": sampledCount,
            "groups": groups.map { $0.toDictionary() },
            "failClosedCounts": failClosedCounts,
            "saturated": saturated,
            "caps": caps,
            "truthBoundary": truthBoundary,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

struct CiderCaptureProvenanceGapAggregateReport: Codable, Equatable {
    var command = "capture.provenance-gap-patterns"
    var readOnly = true
    var changed = false
    var requestedLimit: Int
    var appliedLimit: Int
    var maximumLimit: Int
    var requestedSampleLimit: Int
    var appliedSampleLimit: Int
    var maximumSampleLimit: Int
    var totalMissingCount: Int
    var scannedCount: Int
    var unresolvedCount: Int
    var excludedCount: Int
    var omittedCount: Int
    var saturated: Bool
    var coverage: String
    var sampledCount: Int
    var groups: [CiderCaptureProvenanceGapPatternGroup]
    var candidateDiscovery: CiderCaptureProvenanceCandidateDiscoveryAggregate
    var historicalBoundaries: CiderCaptureProvenanceHistoricalBoundaryReport
    var failClosedCounts: [String: Int]
    var truthBoundary: String
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]

    func toDictionary() -> [String: Any] {
        [
            "ok": true,
            "command": command,
            "readOnly": readOnly,
            "changed": changed,
            "requestedLimit": requestedLimit,
            "appliedLimit": appliedLimit,
            "maximumLimit": maximumLimit,
            "requestedSampleLimit": requestedSampleLimit,
            "appliedSampleLimit": appliedSampleLimit,
            "maximumSampleLimit": maximumSampleLimit,
            "totalMissingCount": totalMissingCount,
            "scannedCount": scannedCount,
            "unresolvedCount": unresolvedCount,
            "excludedCount": excludedCount,
            "omittedCount": omittedCount,
            "saturated": saturated,
            "coverage": coverage,
            "sampledCount": sampledCount,
            "groups": groups.map { $0.toDictionary() },
            "candidateDiscovery": candidateDiscovery.toDictionary(),
            "historicalBoundaries": historicalBoundaries.toDictionary(),
            "failClosedCounts": failClosedCounts,
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
            "safeVerificationCommands": safeVerificationCommands,
        ]
    }
}

@MainActor
final class CiderCaptureProvenanceDiagnosticService {
    static let defaultLimit = 50
    static let maximumLimit = 100
    static let defaultAggregateSampleLimit = 3
    static let maximumAggregateSampleLimit = 10
    private static let duplicateAuditLimit = 500
    private static let duplicateAuditWindow: TimeInterval = 120
    private static let evidenceRefLimit = 10
    private static let supportedSourceKinds: Set<String> = [
        "url", "text", "note", "todo", "file", "event", "contact", "journal",
        "screen_capture", "image", "chat_unsupported_attachment",
    ]

    private struct CaptureEventRow {
        var id: String
        var sourceKind: String
        var sourceURL: String?
        var metadataJSON: String
        var createdAt: Date
    }

    private struct DuplicateAuditSnapshot: Equatable {
        var count: Int
        var newestID: String?
        var newestOccurredAt: Double?
    }

    private struct DuplicateAuditCursor: Codable {
        var version: Int
        var captureEventID: String
        var eventFingerprint: String
        var snapshotCount: Int
        var snapshotNewestID: String?
        var snapshotNewestOccurredAt: Double?
        var lastID: String
        var lastOccurredAt: Double
        var cumulativeScannedCount: Int
    }

    private struct DuplicateAuditPage {
        var entries: [MutationAuditEntry]
        var hasMore: Bool
        var cumulativeScannedCount: Int
        var continuationToken: String?
    }

    private struct CanonicalItemEvidence {
        var cliType: String
        var itemID: UUID
        var itemRef: String { "\(cliType):\(itemID.uuidString)" }
    }

    private struct CanonicalCandidateEvidence {
        var check: CiderCaptureProvenanceEvidenceCheck
        var uniqueBookmark: CanonicalItemEvidence?
        var canonicalURL: String?
        var candidateCount: Int
        var candidateCountIsLowerBound: Bool
    }

    private struct AggregateGroupKey: Hashable {
        var sourceKind: String
        var classification: String
        var reasonCode: String
        var evidenceSignature: String
        var timeBucket: String
        var versionBucket: String?
    }

    private struct AggregateGroupAccumulator {
        var checkedEvidence: [CiderCaptureProvenanceAggregateEvidenceOutcome]
        var count: Int
        var captureEventRefs: [String]
    }

    private struct CandidateEvidenceAggregateAccumulator {
        var eventCount = 0
        var candidateCount = 0
        var candidateCountIsLowerBound = false
        var saturated = false
        var statusCounts: [String: Int] = [:]
    }

    private struct HistoricalBoundaryEvidence {
        var schemaMarkerStatus: CiderCaptureHistoricalMarkerStatus
        var versionMarkerStatus: CiderCaptureHistoricalMarkerStatus
        var lifecycleMarkerStatus: CiderCaptureHistoricalMarkerStatus
        var versionBucket: String?
        var lifecycleCapability: String
        var provenanceGuarantee: CiderCaptureProvenanceGuaranteeStatus
        var reasonCodes: [String]
    }

    private struct HistoricalBoundaryKey: Hashable {
        var timeBucket: String
        var schemaMarkerStatus: String
        var versionMarkerStatus: String
        var lifecycleMarkerStatus: String
        var versionBucket: String?
        var lifecycleCapability: String
        var provenanceGuarantee: String
        var reasonCodes: String
    }

    private struct HistoricalBoundaryAccumulator {
        var count: Int
        var captureEventRefs: [String]
    }

    private let database: CiderDatabase
    private let itemContextService: CiderItemContextService
    private let mutationAuditService: MutationAuditService
    private let secondBrainStore: SecondBrainStore

    init(database: CiderDatabase = .shared) {
        self.database = database
        self.itemContextService = CiderItemContextService(database: database)
        self.mutationAuditService = MutationAuditService(database: database)
        self.secondBrainStore = SecondBrainStore(database: database)
    }

    func explain(
        captureEventRef rawRef: String,
        duplicateAuditContinuation: String? = nil,
        duplicateAuditLimit requestedDuplicateAuditLimit: Int = CiderCaptureProvenanceDiagnosticService.duplicateAuditLimit
    ) throws -> CiderCaptureProvenanceGapExplanation {
        guard (1...Self.duplicateAuditLimit).contains(requestedDuplicateAuditLimit) else {
            throw CiderCaptureProvenanceExplanationError.duplicateAuditLimitOutOfRange
        }
        let components = rawRef.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0] == "capture_event",
              let eventID = UUID(uuidString: String(components[1])) else {
            throw CiderCaptureProvenanceExplanationError.malformedCaptureEventRef
        }
        guard let event = try captureEvent(id: eventID) else {
            throw CiderCaptureProvenanceExplanationError.captureEventNotFound
        }
        guard Self.supportedSourceKinds.contains(event.sourceKind) else {
            throw CiderCaptureProvenanceExplanationError.unsupportedSourceKind
        }
        guard event.sourceKind == "url" || duplicateAuditContinuation == nil else {
            throw CiderCaptureProvenanceExplanationError.mismatchedDuplicateAuditContinuation
        }

        let owner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: event.id)
        let producedItemRelations = try secondBrainStore.outgoingRelations(for: owner)
            .filter { $0.relationType == "produced_item" }
        guard producedItemRelations.isEmpty else {
            throw CiderCaptureProvenanceExplanationError.captureEventNoLongerHasGap
        }

        let auditPage = try duplicateAuditPage(
            for: event,
            continuation: duplicateAuditContinuation,
            limit: requestedDuplicateAuditLimit
        )
        let boundedAudits = auditPage.entries
        let auditCapReached = auditPage.hasMore
        let finding = classify(event, duplicateAudits: boundedAudits)
        let captureRef = "capture_event:\(event.id)"
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: event.metadataJSON)
        let candidateEvidence = canonicalCandidateEvidence(for: event, metadata: metadata)
        let auditEvidence = duplicateAuditEvidence(
            for: event,
            candidateEvidence: candidateEvidence,
            audits: boundedAudits,
            capReached: auditCapReached
        )

        let checks = [
            CiderCaptureProvenanceEvidenceCheck(
                category: .captureEvent,
                status: .found,
                reasonCode: "capture_event_readback_succeeded",
                evidenceRefs: [captureRef]
            ),
            CiderCaptureProvenanceEvidenceCheck(
                category: .producedItemRelation,
                status: .missing,
                reasonCode: "produced_item_relation_absent",
                evidenceRefs: []
            ),
            metadataEvidence(for: event, metadata: metadata),
            candidateEvidence.check,
            auditEvidence,
        ]
        let missingReasons = orderedUnique(checks.compactMap { check in
            switch check.status {
            case .missing, .ambiguous, .stale, .malformed, .capped:
                return check.reasonCode
            case .found, .notApplicable:
                return nil
            }
        }.map { reason in
            reason == "capture_metadata_has_no_provenance_claim" ? "no_exact_persisted_item_reference" : reason
        })
        let replayCommand = "cider-cli capture provenance-gap \(captureRef) --duplicate-audit-limit \(requestedDuplicateAuditLimit) --json"
        let continuationCommand = auditPage.continuationToken.map {
            "cider-cli capture provenance-gap \(captureRef) --duplicate-audit-limit \(requestedDuplicateAuditLimit) --duplicate-audit-cursor \($0) --json"
        }
        let safeCommands = orderedUnique([replayCommand] + [continuationCommand].compactMap { $0 } + finding.safeVerificationCommands)
        let refs = orderedUnique(finding.evidenceRefs + checks.flatMap(\.evidenceRefs))
            .prefix(Self.evidenceRefLimit)
        let discovery = finding.classification == .unresolvedProvenanceGap
            ? candidateDiscovery(
                for: event,
                metadata: metadata,
                metadataEvidence: checks[2],
                candidateEvidence: candidateEvidence,
                auditEvidence: auditEvidence,
                audits: boundedAudits,
                auditPage: auditPage,
                safeVerificationCommands: safeCommands
            )
            : nil

        return CiderCaptureProvenanceGapExplanation(
            captureEventID: event.id,
            captureEventRef: captureRef,
            sourceKind: event.sourceKind,
            classification: finding.classification,
            reasonCode: finding.reasonCode,
            explanation: explanationSummary(for: finding.reasonCode),
            itemRef: finding.itemRef,
            checkedEvidence: checks,
            evidenceRefs: Array(refs),
            missingEvidenceReasons: missingReasons,
            caps: [
                "duplicateAuditEntries": Self.duplicateAuditLimit,
                "evidenceRefs": Self.evidenceRefLimit,
            ],
            duplicateAuditScan: CiderCaptureDuplicateAuditScanPage(
                requestedLimit: requestedDuplicateAuditLimit,
                appliedLimit: requestedDuplicateAuditLimit,
                maximumLimit: Self.duplicateAuditLimit,
                scannedCount: auditPage.entries.count,
                cumulativeScannedCount: auditPage.cumulativeScannedCount,
                hasMore: auditPage.hasMore,
                saturated: auditPage.hasMore,
                exhausted: !auditPage.hasMore,
                scannedAuditRefs: auditPage.entries.prefix(Self.evidenceRefLimit).map { "mutation_audit:\($0.id.uuidString)" },
                scannedAuditRefsTruncated: auditPage.entries.count > Self.evidenceRefLimit,
                continuationToken: auditPage.continuationToken
            ),
            candidateDiscovery: discovery,
            truthBoundary: "read_only_explanation_no_inference_candidate_selection_or_provenance_repair",
            safeNextCommands: safeCommands,
            safeVerificationCommands: safeCommands
        )
    }

    private func duplicateAuditPage(
        for event: CaptureEventRow,
        continuation: String?,
        limit: Int
    ) throws -> DuplicateAuditPage {
        guard event.sourceKind == "url" else {
            return DuplicateAuditPage(
                entries: [], hasMore: false, cumulativeScannedCount: 0, continuationToken: nil
            )
        }

        let snapshot = try duplicateAuditSnapshot()
        let cursor: DuplicateAuditCursor?
        if let continuation {
            cursor = try decodeDuplicateAuditCursor(continuation)
            guard cursor?.captureEventID == event.id else {
                throw CiderCaptureProvenanceExplanationError.mismatchedDuplicateAuditContinuation
            }
            guard cursor?.eventFingerprint == eventFingerprint(event) else {
                throw CiderCaptureProvenanceExplanationError.staleDuplicateAuditContinuation
            }
            guard cursor?.snapshotCount == snapshot.count,
                  cursor?.snapshotNewestID == snapshot.newestID,
                  cursor?.snapshotNewestOccurredAt == snapshot.newestOccurredAt else {
                throw CiderCaptureProvenanceExplanationError.staleDuplicateAuditContinuation
            }
        } else {
            cursor = nil
        }

        let loaded = try loadDuplicateAuditEntries(limit: limit + 1, after: cursor)
        let entries = Array(loaded.prefix(limit))
        let hasMore = loaded.count > limit
        let cumulative = (cursor?.cumulativeScannedCount ?? 0) + entries.count
        let nextToken: String?
        if hasMore, let last = entries.last {
            nextToken = try encodeDuplicateAuditCursor(DuplicateAuditCursor(
                version: 1,
                captureEventID: event.id,
                eventFingerprint: eventFingerprint(event),
                snapshotCount: snapshot.count,
                snapshotNewestID: snapshot.newestID,
                snapshotNewestOccurredAt: snapshot.newestOccurredAt,
                lastID: last.id.uuidString,
                lastOccurredAt: last.occurredAt.timeIntervalSince1970,
                cumulativeScannedCount: cumulative
            ))
        } else {
            nextToken = nil
        }
        return DuplicateAuditPage(
            entries: entries,
            hasMore: hasMore,
            cumulativeScannedCount: cumulative,
            continuationToken: nextToken
        )
    }

    private func duplicateAuditSnapshot() throws -> DuplicateAuditSnapshot {
        let countStatement = try database.prepare("SELECT count(*) FROM mutation_audit;")
        _ = try countStatement.step()
        let count = countStatement.int(at: 0)
        let newest = try database.prepare("SELECT id, occurred_at FROM mutation_audit ORDER BY occurred_at DESC, id DESC LIMIT 1;")
        guard try newest.step() else {
            return DuplicateAuditSnapshot(count: count, newestID: nil, newestOccurredAt: nil)
        }
        return DuplicateAuditSnapshot(count: count, newestID: newest.string(at: 0), newestOccurredAt: newest.double(at: 1))
    }

    private func loadDuplicateAuditEntries(limit: Int, after cursor: DuplicateAuditCursor?) throws -> [MutationAuditEntry] {
        let statement: SQLStatement
        if let cursor {
            statement = try database.prepare("""
                SELECT id, occurred_at, item_type, item_id, action, source, before_state, after_state, metadata
                FROM mutation_audit
                WHERE occurred_at < ? OR (occurred_at = ? AND id < ?)
                ORDER BY occurred_at DESC, id DESC
                LIMIT ?;
                """)
            statement.bind(cursor.lastOccurredAt, at: 1)
                .bind(cursor.lastOccurredAt, at: 2)
                .bind(cursor.lastID, at: 3)
                .bind(limit, at: 4)
        } else {
            statement = try database.prepare("""
                SELECT id, occurred_at, item_type, item_id, action, source, before_state, after_state, metadata
                FROM mutation_audit
                ORDER BY occurred_at DESC, id DESC
                LIMIT ?;
                """)
            statement.bind(limit, at: 1)
        }
        var entries: [MutationAuditEntry] = []
        while try statement.step() {
            guard let id = UUID(uuidString: statement.string(at: 0)),
                  let itemID = UUID(uuidString: statement.string(at: 3)),
                  let source = MutationAuditSource(rawValue: statement.string(at: 5)) else { continue }
            entries.append(MutationAuditEntry(
                id: id,
                occurredAt: DatabaseHelpers.decodeDate(statement.double(at: 1)),
                itemType: statement.string(at: 2),
                itemID: itemID,
                action: statement.string(at: 4),
                source: source,
                beforeState: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 6)) ?? [:],
                afterState: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 7)) ?? [:],
                metadata: DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 8)) ?? [:]
            ))
        }
        return entries
    }

    private func eventFingerprint(_ event: CaptureEventRow) -> String {
        let material = [event.id, event.sourceKind, event.sourceURL ?? "", event.metadataJSON, String(event.createdAt.timeIntervalSince1970)]
            .joined(separator: "\u{1F}")
        return Self.sha256(material)
    }

    private func encodeDuplicateAuditCursor(_ cursor: DuplicateAuditCursor) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cursor)
        let payload = Self.base64URL(data)
        return "\(payload).\(Self.sha256("cider.duplicate-audit-continuation.v1|\(payload)"))"
    }

    private func decodeDuplicateAuditCursor(_ token: String) throws -> DuplicateAuditCursor {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let data = Self.dataFromBase64URL(String(parts[0])) else {
            throw CiderCaptureProvenanceExplanationError.malformedDuplicateAuditContinuation
        }
        let payload = String(parts[0])
        let expected = Self.sha256("cider.duplicate-audit-continuation.v1|\(payload)")
        guard String(parts[1]) == expected else {
            throw CiderCaptureProvenanceExplanationError.forgedDuplicateAuditContinuation
        }
        guard let cursor = try? JSONDecoder().decode(DuplicateAuditCursor.self, from: data),
              cursor.version == 1,
              cursor.cumulativeScannedCount >= 0,
              UUID(uuidString: cursor.captureEventID) != nil,
              UUID(uuidString: cursor.lastID) != nil else {
            throw CiderCaptureProvenanceExplanationError.malformedDuplicateAuditContinuation
        }
        return cursor
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func dataFromBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    func diagnose(limit requestedLimit: Int = CiderCaptureProvenanceDiagnosticService.defaultLimit) throws -> CiderCaptureProvenanceDiagnosticReport {
        let appliedLimit = min(max(requestedLimit, 1), Self.maximumLimit)
        let totalMissingCount = try missingCaptureEventCount()
        let events = try missingCaptureEvents(limit: appliedLimit)
        let duplicateAudits = mutationAuditService.loadEntries(limit: Self.duplicateAuditLimit)
        var counts = CiderCaptureProvenanceGapCounts()
        var findings: [CiderCaptureProvenanceGapFinding] = []

        for event in events {
            let finding = classify(event, duplicateAudits: duplicateAudits)
            counts.increment(finding.classification)
            findings.append(finding)
        }

        let replayCommand = "cider-cli capture provenance-gaps --limit \(appliedLimit) --json"
        let eventCommands = findings.flatMap(\.safeNextCommands)
        return CiderCaptureProvenanceDiagnosticReport(
            requestedLimit: requestedLimit,
            appliedLimit: appliedLimit,
            maximumLimit: Self.maximumLimit,
            totalMissingCount: totalMissingCount,
            scannedCount: findings.count,
            omittedCount: max(0, totalMissingCount - findings.count),
            hasMore: totalMissingCount > findings.count,
            counts: counts,
            findings: findings,
            truthBoundary: "read_only_diagnostic_evidence_not_repaired_provenance_or_accepted_truth",
            safeNextCommands: orderedUnique([replayCommand] + eventCommands),
            safeVerificationCommands: [replayCommand]
        )
    }

    func aggregateUnresolvedGaps(
        limit requestedLimit: Int = CiderCaptureProvenanceDiagnosticService.defaultLimit,
        sampleLimit requestedSampleLimit: Int = CiderCaptureProvenanceDiagnosticService.defaultAggregateSampleLimit
    ) throws -> CiderCaptureProvenanceGapAggregateReport {
        let appliedSampleLimit = min(max(requestedSampleLimit, 0), Self.maximumAggregateSampleLimit)
        let diagnostic = try diagnose(limit: requestedLimit)
        var accumulators: [AggregateGroupKey: AggregateGroupAccumulator] = [:]
        var candidateOutcomeCounts: [CiderCaptureProvenanceCandidateDiscoveryOutcome: Int] = [:]
        var candidateOutcomeRefs: [CiderCaptureProvenanceCandidateDiscoveryOutcome: [String]] = [:]
        var candidateEvidenceCounts: [CiderCaptureProvenanceCandidateEvidenceCategory: CandidateEvidenceAggregateAccumulator] = [:]
        var candidateEligibleCount = 0
        var candidateExcludedCount = 0
        var candidateEvidenceSaturated = false
        var failClosedCounts: [String: Int] = [:]
        var excludedCount = 0
        var historicalAccumulators: [HistoricalBoundaryKey: HistoricalBoundaryAccumulator] = [:]
        var historicalFailClosedCounts: [String: Int] = [:]
        var historicalExcludedCount = 0

        for finding in diagnostic.findings where finding.classification == .unresolvedProvenanceGap {
            guard Self.supportedSourceKinds.contains(finding.sourceKind) else {
                excludedCount += 1
                candidateExcludedCount += 1
                historicalExcludedCount += 1
                failClosedCounts[CiderCaptureProvenanceExplanationError.unsupportedSourceKind.rawValue, default: 0] += 1
                historicalFailClosedCounts[CiderCaptureProvenanceExplanationError.unsupportedSourceKind.rawValue, default: 0] += 1
                continue
            }
            guard let eventID = UUID(uuidString: finding.captureEventID),
                  let event = try captureEvent(id: eventID) else {
                excludedCount += 1
                candidateExcludedCount += 1
                historicalExcludedCount += 1
                failClosedCounts["capture_event_readback_failed", default: 0] += 1
                historicalFailClosedCounts["capture_event_readback_failed", default: 0] += 1
                continue
            }

            let explanation: CiderCaptureProvenanceGapExplanation
            do {
                explanation = try explain(captureEventRef: finding.captureEventRef)
            } catch let error as CiderCaptureProvenanceExplanationError {
                excludedCount += 1
                candidateExcludedCount += 1
                historicalExcludedCount += 1
                failClosedCounts[error.rawValue, default: 0] += 1
                historicalFailClosedCounts[error.rawValue, default: 0] += 1
                continue
            }

            let boundaryEvidence = Self.historicalBoundaryEvidence(for: event)
            for reasonCode in boundaryEvidence.reasonCodes where reasonCode != "supported_historical_boundary_markers" {
                historicalFailClosedCounts[reasonCode, default: 0] += 1
            }
            let boundaryKey = HistoricalBoundaryKey(
                timeBucket: Self.utcMonthBucket(for: event.createdAt),
                schemaMarkerStatus: boundaryEvidence.schemaMarkerStatus.rawValue,
                versionMarkerStatus: boundaryEvidence.versionMarkerStatus.rawValue,
                lifecycleMarkerStatus: boundaryEvidence.lifecycleMarkerStatus.rawValue,
                versionBucket: boundaryEvidence.versionBucket,
                lifecycleCapability: boundaryEvidence.lifecycleCapability,
                provenanceGuarantee: boundaryEvidence.provenanceGuarantee.rawValue,
                reasonCodes: boundaryEvidence.reasonCodes.joined(separator: "|")
            )
            if var accumulator = historicalAccumulators[boundaryKey] {
                accumulator.count += 1
                accumulator.captureEventRefs.append(finding.captureEventRef)
                historicalAccumulators[boundaryKey] = accumulator
            } else {
                historicalAccumulators[boundaryKey] = HistoricalBoundaryAccumulator(
                    count: 1,
                    captureEventRefs: [finding.captureEventRef]
                )
            }

            if explanation.checkedEvidence.contains(where: { $0.status == .malformed }) {
                candidateExcludedCount += 1
                failClosedCounts["malformed_candidate_discovery_input", default: 0] += 1
            } else if let discovery = explanation.candidateDiscovery {
                candidateEligibleCount += 1
                candidateOutcomeCounts[discovery.outcome, default: 0] += 1
                candidateOutcomeRefs[discovery.outcome, default: []].append(finding.captureEventRef)
                candidateEvidenceSaturated = candidateEvidenceSaturated || discovery.saturated
                for evidence in discovery.countsByEvidenceCategory {
                    var accumulator = candidateEvidenceCounts[evidence.category] ?? CandidateEvidenceAggregateAccumulator()
                    accumulator.eventCount += 1
                    accumulator.candidateCount += evidence.candidateCount
                    accumulator.candidateCountIsLowerBound = accumulator.candidateCountIsLowerBound || evidence.candidateCountIsLowerBound
                    accumulator.saturated = accumulator.saturated || evidence.candidateCountIsLowerBound
                    accumulator.statusCounts[evidence.status.rawValue, default: 0] += 1
                    candidateEvidenceCounts[evidence.category] = accumulator
                }
            } else {
                candidateExcludedCount += 1
                failClosedCounts["candidate_discovery_unavailable", default: 0] += 1
            }

            let outcomes = explanation.checkedEvidence.map {
                CiderCaptureProvenanceAggregateEvidenceOutcome(
                    category: $0.category,
                    status: $0.status,
                    reasonCode: $0.reasonCode
                )
            }
            for reason in explanation.missingEvidenceReasons {
                failClosedCounts[reason, default: 0] += 1
            }
            let key = AggregateGroupKey(
                sourceKind: explanation.sourceKind,
                classification: explanation.classification.rawValue,
                reasonCode: explanation.reasonCode,
                evidenceSignature: outcomes.map {
                    "\($0.category.rawValue)=\($0.status.rawValue):\($0.reasonCode)"
                }.joined(separator: "|"),
                timeBucket: Self.utcMonthBucket(for: event.createdAt),
                versionBucket: Self.safeVersionBucket(metadataJSON: event.metadataJSON)
            )
            if var accumulator = accumulators[key] {
                accumulator.count += 1
                accumulator.captureEventRefs.append(finding.captureEventRef)
                accumulators[key] = accumulator
            } else {
                accumulators[key] = AggregateGroupAccumulator(
                    checkedEvidence: outcomes,
                    count: 1,
                    captureEventRefs: [finding.captureEventRef]
                )
            }
        }

        if diagnostic.omittedCount > 0 {
            failClosedCounts["scan_cap_reached"] = diagnostic.omittedCount
        }
        let sortedKeys = accumulators.keys.sorted { lhs, rhs in
            let leftCount = accumulators[lhs]?.count ?? 0
            let rightCount = accumulators[rhs]?.count ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return Self.aggregateSortKey(lhs) < Self.aggregateSortKey(rhs)
        }
        var samplesRemaining = appliedSampleLimit
        var sampledCount = 0
        let groups = sortedKeys.compactMap { key -> CiderCaptureProvenanceGapPatternGroup? in
            guard let accumulator = accumulators[key] else { return nil }
            let sampleCount = min(samplesRemaining, accumulator.captureEventRefs.count)
            let samples = Array(accumulator.captureEventRefs.prefix(sampleCount))
            samplesRemaining -= sampleCount
            sampledCount += sampleCount
            return CiderCaptureProvenanceGapPatternGroup(
                sourceKind: key.sourceKind,
                classification: CiderCaptureProvenanceGapClassification(rawValue: key.classification) ?? .unresolvedProvenanceGap,
                reasonCode: key.reasonCode,
                checkedEvidence: accumulator.checkedEvidence,
                timeBucket: key.timeBucket,
                versionBucket: key.versionBucket,
                count: accumulator.count,
                sampleCaptureEventRefs: samples
            )
        }
        let replayCommand = "cider-cli capture provenance-gap-patterns --limit \(diagnostic.appliedLimit) --sample-limit \(appliedSampleLimit) --json"
        let drilldownCommands = groups.flatMap(\.sampleCaptureEventRefs).map {
            "cider-cli capture provenance-gap \($0) --json"
        }
        let commands = orderedUnique([replayCommand] + drilldownCommands)
        let outcomeOrder: [CiderCaptureProvenanceCandidateDiscoveryOutcome] = [
            .zeroCandidates, .oneCandidateInsufficient, .multipleCandidatesAmbiguous, .cappedCandidateEvidence,
        ]
        var candidateSamplesRemaining = appliedSampleLimit
        var candidateSampledCount = 0
        let countsByOutcome = outcomeOrder.map { outcome in
            let refs = (candidateOutcomeRefs[outcome] ?? []).sorted()
            let sampleCount = min(candidateSamplesRemaining, refs.count)
            let samples = Array(refs.prefix(sampleCount))
            candidateSamplesRemaining -= sampleCount
            candidateSampledCount += sampleCount
            return CiderCaptureProvenanceCandidateOutcomeAggregateCount(
                outcome: outcome,
                count: candidateOutcomeCounts[outcome] ?? 0,
                sampleCaptureEventRefs: samples,
                sampleRefsTruncated: refs.count > samples.count
            )
        }
        let evidenceCategoryOrder: [CiderCaptureProvenanceCandidateEvidenceCategory] = [
            .exactPersistedItemReference, .canonicalURLMatch, .nearbyDuplicateAuditMatch,
        ]
        let countsByEvidenceCategory = evidenceCategoryOrder.map { category in
            let accumulator = candidateEvidenceCounts[category] ?? CandidateEvidenceAggregateAccumulator()
            return CiderCaptureProvenanceCandidateEvidenceAggregateCount(
                category: category,
                eventCount: accumulator.eventCount,
                candidateCount: accumulator.candidateCount,
                candidateCountIsLowerBound: accumulator.candidateCountIsLowerBound,
                saturated: accumulator.saturated,
                statusCounts: accumulator.statusCounts
            )
        }
        let candidateSampleRefsTruncated = candidateEligibleCount > candidateSampledCount
        let candidateCommands = orderedUnique([replayCommand] + countsByOutcome.flatMap(\.sampleCaptureEventRefs).map {
            "cider-cli capture provenance-gap \($0) --json"
        })
        let candidateDiscovery = CiderCaptureProvenanceCandidateDiscoveryAggregate(
            eligibleCount: candidateEligibleCount,
            excludedCount: candidateExcludedCount,
            sampledCount: candidateSampledCount,
            sampleRefsTruncated: candidateSampleRefsTruncated,
            countsByOutcome: countsByOutcome,
            countsByEvidenceCategory: countsByEvidenceCategory,
            saturated: diagnostic.hasMore || candidateEvidenceSaturated || candidateSampleRefsTruncated,
            caps: [
                "scanEvents": Self.maximumLimit,
                "sampleCaptureEventRefs": appliedSampleLimit,
                "candidateRefsPerEvent": Self.evidenceRefLimit,
                "duplicateAuditEntriesPerEvent": Self.duplicateAuditLimit,
            ],
            truthBoundary: "read_only_bounded_candidate_evidence_aggregate_no_candidate_selection_provenance_inference_or_repair",
            safeVerificationCommands: candidateCommands
        )
        let sortedBoundaryKeys = historicalAccumulators.keys.sorted { lhs, rhs in
            let leftCount = historicalAccumulators[lhs]?.count ?? 0
            let rightCount = historicalAccumulators[rhs]?.count ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return Self.historicalBoundarySortKey(lhs) < Self.historicalBoundarySortKey(rhs)
        }
        var historicalSamplesRemaining = appliedSampleLimit
        var historicalSampledCount = 0
        let historicalGroups = sortedBoundaryKeys.compactMap { key -> CiderCaptureProvenanceHistoricalBoundaryGroup? in
            guard let accumulator = historicalAccumulators[key] else { return nil }
            let sortedRefs = accumulator.captureEventRefs.sorted()
            let sampleCount = min(historicalSamplesRemaining, sortedRefs.count)
            let samples = Array(sortedRefs.prefix(sampleCount))
            historicalSamplesRemaining -= sampleCount
            historicalSampledCount += sampleCount
            return CiderCaptureProvenanceHistoricalBoundaryGroup(
                timeBucket: key.timeBucket,
                schemaMarkerStatus: CiderCaptureHistoricalMarkerStatus(rawValue: key.schemaMarkerStatus) ?? .malformed,
                versionMarkerStatus: CiderCaptureHistoricalMarkerStatus(rawValue: key.versionMarkerStatus) ?? .malformed,
                lifecycleMarkerStatus: CiderCaptureHistoricalMarkerStatus(rawValue: key.lifecycleMarkerStatus) ?? .malformed,
                versionBucket: key.versionBucket,
                lifecycleCapability: key.lifecycleCapability,
                provenanceGuarantee: CiderCaptureProvenanceGuaranteeStatus(rawValue: key.provenanceGuarantee) ?? .notEvidenced,
                reasonCodes: key.reasonCodes.split(separator: "|").map(String.init),
                count: accumulator.count,
                sampleCaptureEventRefs: samples,
                sampleRefsTruncated: sortedRefs.count > samples.count
            )
        }
        if diagnostic.omittedCount > 0 {
            historicalFailClosedCounts["scan_cap_reached"] = diagnostic.omittedCount
        }
        let historicalReplayCommands = orderedUnique([replayCommand] + historicalGroups.flatMap(\.sampleCaptureEventRefs).map {
            "cider-cli capture provenance-gap \($0) --json"
        })
        let historicalBoundaries = CiderCaptureProvenanceHistoricalBoundaryReport(
            classifiedCount: historicalGroups.reduce(0) { $0 + $1.count },
            excludedCount: historicalExcludedCount,
            sampledCount: historicalSampledCount,
            groups: historicalGroups,
            failClosedCounts: historicalFailClosedCounts,
            saturated: diagnostic.hasMore || historicalGroups.contains(where: \.sampleRefsTruncated),
            caps: [
                "scanEvents": Self.maximumLimit,
                "sampleCaptureEventRefs": appliedSampleLimit,
            ],
            truthBoundary: "source_backed_capture_metadata_markers_only_no_ownership_inference_provenance_creation_or_repair",
            safeVerificationCommands: historicalReplayCommands
        )
        return CiderCaptureProvenanceGapAggregateReport(
            requestedLimit: requestedLimit,
            appliedLimit: diagnostic.appliedLimit,
            maximumLimit: Self.maximumLimit,
            requestedSampleLimit: requestedSampleLimit,
            appliedSampleLimit: appliedSampleLimit,
            maximumSampleLimit: Self.maximumAggregateSampleLimit,
            totalMissingCount: diagnostic.totalMissingCount,
            scannedCount: diagnostic.scannedCount,
            unresolvedCount: groups.reduce(0) { $0 + $1.count },
            excludedCount: excludedCount,
            omittedCount: diagnostic.omittedCount,
            saturated: diagnostic.hasMore,
            coverage: diagnostic.hasMore ? "partial_bounded_scan" : "complete_bounded_set",
            sampledCount: sampledCount,
            groups: groups,
            candidateDiscovery: candidateDiscovery,
            historicalBoundaries: historicalBoundaries,
            failClosedCounts: failClosedCounts,
            truthBoundary: "read_only_bounded_aggregate_of_persisted_evidence_no_provenance_inference_selection_or_repair",
            safeNextCommands: commands,
            safeVerificationCommands: commands
        )
    }

    private static func aggregateSortKey(_ key: AggregateGroupKey) -> String {
        [
            key.sourceKind,
            key.classification,
            key.reasonCode,
            key.evidenceSignature,
            key.timeBucket,
            key.versionBucket ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func historicalBoundarySortKey(_ key: HistoricalBoundaryKey) -> String {
        [
            key.timeBucket,
            key.schemaMarkerStatus,
            key.versionMarkerStatus,
            key.lifecycleMarkerStatus,
            key.versionBucket ?? "",
            key.lifecycleCapability,
            key.provenanceGuarantee,
            key.reasonCodes,
        ].joined(separator: "\u{1F}")
    }

    private static func utcMonthBucket(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func historicalBoundaryEvidence(for event: CaptureEventRow) -> HistoricalBoundaryEvidence {
        guard let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: event.metadataJSON) else {
            return HistoricalBoundaryEvidence(
                schemaMarkerStatus: .malformed,
                versionMarkerStatus: .malformed,
                lifecycleMarkerStatus: .malformed,
                versionBucket: nil,
                lifecycleCapability: "unknown",
                provenanceGuarantee: .notEvidenced,
                reasonCodes: ["malformed_capture_metadata"]
            )
        }

        let schema = historicalSchemaMarker(in: metadata)
        let version = historicalVersionMarker(in: metadata)
        let lifecycle = historicalLifecycleMarker(in: metadata, createdAt: event.createdAt)
        var reasons = [schema.reasonCode, version.reasonCode, lifecycle.reasonCode]
        if schema.status == .found, version.status == .found, lifecycle.status == .found {
            reasons = ["supported_historical_boundary_markers"]
        }

        let guarantee: CiderCaptureProvenanceGuaranteeStatus
        if schema.status == .found, version.status == .found, lifecycle.status == .found {
            switch lifecycle.capability {
            case "completed_producing_capture": guarantee = .activeRelationRequired
            case "explicit_nonproducing_capture": guarantee = .inactiveNonproducing
            default: guarantee = .notEvidenced
            }
        } else {
            guarantee = .notEvidenced
        }

        return HistoricalBoundaryEvidence(
            schemaMarkerStatus: schema.status,
            versionMarkerStatus: version.status,
            lifecycleMarkerStatus: lifecycle.status,
            versionBucket: version.value,
            lifecycleCapability: lifecycle.capability,
            provenanceGuarantee: guarantee,
            reasonCodes: reasons.sorted()
        )
    }

    private static func historicalSchemaMarker(
        in metadata: [String: String]
    ) -> (status: CiderCaptureHistoricalMarkerStatus, reasonCode: String) {
        let values = markerValues(
            in: metadata,
            keys: ["capture_schema_version", "captureSchemaVersion", "provenance_schema_version", "provenanceSchemaVersion"]
        )
        guard !values.isEmpty else { return (.missing, "missing_schema_marker") }
        guard !values.contains(where: isPrivacySensitiveMarker) else {
            return (.privacySensitive, "privacy_sensitive_schema_marker")
        }
        let distinct = Set(values)
        guard distinct.count == 1, let value = distinct.first else {
            return (.ambiguous, "ambiguous_schema_marker")
        }
        guard let schemaVersion = Int(value), String(schemaVersion) == value, schemaVersion > 0 else {
            return (.malformed, "malformed_schema_marker")
        }
        guard schemaVersion == 1 else { return (.unsupported, "unsupported_schema_marker") }
        return (.found, "supported_schema_marker")
    }

    private static func historicalVersionMarker(
        in metadata: [String: String]
    ) -> (status: CiderCaptureHistoricalMarkerStatus, value: String?, reasonCode: String) {
        let values = markerValues(
            in: metadata,
            keys: ["app_version", "appVersion", "capture_version", "captureVersion", "source_version", "sourceVersion"]
        )
        guard !values.isEmpty else { return (.missing, nil, "missing_version_marker") }
        guard !values.contains(where: isPrivacySensitiveMarker) else {
            return (.privacySensitive, nil, "privacy_sensitive_version_marker")
        }
        let distinct = Set(values)
        guard distinct.count == 1, let value = distinct.first else {
            return (.ambiguous, nil, "ambiguous_version_marker")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_"))
        guard !value.isEmpty, value.count <= 32, value.unicodeScalars.allSatisfy(allowed.contains) else {
            return (.malformed, nil, "malformed_version_marker")
        }
        return (.found, value, "supported_version_marker")
    }

    private static func historicalLifecycleMarker(
        in metadata: [String: String],
        createdAt: Date
    ) -> (status: CiderCaptureHistoricalMarkerStatus, capability: String, reasonCode: String) {
        let values = markerValues(in: metadata, keys: ["capture_outcome", "outcome"])
        if values.isEmpty {
            let producedTypes = markerValues(in: metadata, keys: ["produced_item_type", "producedItemType"])
            let producedIDs = markerValues(in: metadata, keys: ["produced_item_id", "producedItemID"])
            if !producedTypes.isEmpty || !producedIDs.isEmpty {
                guard producedTypes.count == 1, producedIDs.count == 1 else {
                    return (.ambiguous, "unknown", "ambiguous_lifecycle_marker")
                }
                guard !isPrivacySensitiveMarker(producedTypes[0]), !isPrivacySensitiveMarker(producedIDs[0]) else {
                    return (.privacySensitive, "unknown", "privacy_sensitive_lifecycle_marker")
                }
                return (.found, "completed_producing_capture", "exact_produced_item_lifecycle_marker")
            }
            if metadata["review_reason"] == "unsupported_attachment" {
                return (.found, "explicit_nonproducing_capture", "explicit_nonproducing_lifecycle_marker")
            }
            return (.missing, "unknown", "missing_lifecycle_marker")
        }
        guard !values.contains(where: isPrivacySensitiveMarker) else {
            return (.privacySensitive, "unknown", "privacy_sensitive_lifecycle_marker")
        }
        let normalized = Set(values.map { $0.lowercased() })
        guard normalized.count == 1, let outcome = normalized.first else {
            return (.ambiguous, "unknown", "ambiguous_lifecycle_marker")
        }
        let completed: Set<String> = ["completed", "created", "success", "succeeded", "recorded", "produced"]
        let nonproducing: Set<String> = [
            "duplicate", "deduplicated", "existing_item", "failed", "failure", "error",
            "abandoned", "cancelled", "canceled", "dismissed", "skipped",
        ]
        let pending: Set<String> = ["pending", "queued", "in_progress", "processing"]
        if completed.contains(outcome) {
            return (.found, "completed_producing_capture", "completed_lifecycle_marker")
        }
        if nonproducing.contains(outcome) {
            return (.found, "explicit_nonproducing_capture", "explicit_nonproducing_lifecycle_marker")
        }
        if pending.contains(outcome) {
            if Date().timeIntervalSince(createdAt) > 86_400 {
                return (.stale, "pending_capture", "stale_lifecycle_marker")
            }
            return (.found, "pending_capture", "pending_lifecycle_marker")
        }
        return (.unsupported, "unknown", "unsupported_lifecycle_marker")
    }

    private static func markerValues(in metadata: [String: String], keys: [String]) -> [String] {
        keys.compactMap { key in
            guard let value = metadata[key] else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isPrivacySensitiveMarker(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return ["PRIVATE", "SECRET", "PASSWORD", "CREDENTIAL", "TOKEN", "SENTINEL"].contains {
            normalized.contains($0)
        }
    }

    private static func safeVersionBucket(metadataJSON: String) -> String? {
        guard let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: metadataJSON) else {
            return nil
        }
        let versionKeys = ["app_version", "appVersion", "capture_version", "captureVersion", "source_version", "sourceVersion"]
        let candidate = versionKeys.compactMap { metadata[$0] }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty, candidate.count <= 32 else { return nil }
        guard !isPrivacySensitiveMarker(candidate) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_"))
        guard candidate.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return candidate
    }

    private func missingCaptureEventCount() throws -> Int {
        let statement = try database.prepare("""
            SELECT count(*)
            FROM capture_events e
            WHERE NOT EXISTS (
                SELECT 1
                FROM owner_relations r
                WHERE r.source_owner_type = 'capture_event'
                  AND r.source_owner_id = e.id
                  AND r.relation_type = 'produced_item'
            );
            """)
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func captureEvent(id: UUID) throws -> CaptureEventRow? {
        let statement = try database.prepare("""
            SELECT id, source_kind, source_url, metadata, created_at
            FROM capture_events
            WHERE id = ? COLLATE NOCASE
            LIMIT 1;
            """)
        statement.bind(id.uuidString, at: 1)
        guard try statement.step() else { return nil }
        return CaptureEventRow(
            id: statement.string(at: 0),
            sourceKind: statement.string(at: 1),
            sourceURL: statement.optionalString(at: 2),
            metadataJSON: statement.string(at: 3),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 4))
        )
    }

    private func missingCaptureEvents(limit: Int) throws -> [CaptureEventRow] {
        let statement = try database.prepare("""
            SELECT e.id, e.source_kind, e.source_url, e.metadata, e.created_at
            FROM capture_events e
            WHERE NOT EXISTS (
                SELECT 1
                FROM owner_relations r
                WHERE r.source_owner_type = 'capture_event'
                  AND r.source_owner_id = e.id
                  AND r.relation_type = 'produced_item'
            )
            ORDER BY e.created_at DESC, e.id ASC
            LIMIT ?;
            """)
        statement.bind(limit, at: 1)
        var rows: [CaptureEventRow] = []
        while try statement.step() {
            rows.append(CaptureEventRow(
                id: statement.string(at: 0),
                sourceKind: statement.string(at: 1),
                sourceURL: statement.optionalString(at: 2),
                metadataJSON: statement.string(at: 3),
                createdAt: DatabaseHelpers.decodeDate(statement.double(at: 4))
            ))
        }
        return rows
    }

    private func classify(
        _ event: CaptureEventRow,
        duplicateAudits: [MutationAuditEntry]
    ) -> CiderCaptureProvenanceGapFinding {
        let captureRef = "capture_event:\(event.id)"
        let backlinkCommand = "cider-cli item backlinks capture_event \(event.id) --json"
        guard let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: event.metadataJSON) else {
            return finding(
                event: event,
                classification: .unresolvedProvenanceGap,
                reasonCode: "malformed_capture_metadata",
                reason: "Capture metadata is malformed or is not a string-to-string object, so the event cannot be classified safely.",
                evidenceRefs: [captureRef],
                truthBoundary: "insufficient_evidence_no_inference_or_mutation",
                safeCommands: [backlinkCommand]
            )
        }

        if let duplicate = explicitDuplicateEvidence(metadata: metadata),
           let item = canonicalItem(type: duplicate.type, id: duplicate.id) {
            let itemCommand = "cider-cli item get \(item.cliType) \(item.itemID.uuidString) --json"
            return finding(
                event: event,
                classification: .evidenceBackedDuplicate,
                reasonCode: "explicit_duplicate_with_canonical_item",
                reason: "Persisted capture metadata explicitly records a duplicate and the referenced canonical item survives.",
                item: item,
                evidenceRefs: [captureRef, item.itemRef, "capture_metadata:duplicate"],
                truthBoundary: "explained_duplicate_evidence_only_no_relation_repair",
                safeCommands: [backlinkCommand, itemCommand]
            )
        }

        if let duplicate = auditedBookmarkDuplicate(event: event, audits: duplicateAudits) {
            let itemCommand = "cider-cli item get bookmark \(duplicate.itemID.uuidString) --json"
            return finding(
                event: event,
                classification: .evidenceBackedDuplicate,
                reasonCode: "canonical_url_duplicate_audit",
                reason: "The source URL resolves to one surviving canonical bookmark and a nearby deduplicate_url_capture audit identifies that same item.",
                item: duplicate,
                evidenceRefs: [captureRef, duplicate.itemRef, "mutation_audit:deduplicate_url_capture"],
                truthBoundary: "explained_duplicate_evidence_only_no_relation_repair",
                safeCommands: [backlinkCommand, itemCommand]
            )
        }

        if let explicitOutcome = explicitNonproducingOutcome(event: event, metadata: metadata) {
            return finding(
                event: event,
                classification: .explicitFailureOrAbandonment,
                reasonCode: explicitOutcome.code,
                reason: explicitOutcome.reason,
                evidenceRefs: [captureRef, "capture_metadata:\(explicitOutcome.evidenceKey)"],
                truthBoundary: "explicit_nonproducing_history_no_item_or_relation_expected",
                safeCommands: [backlinkCommand]
            )
        }

        if let reference = recoverableItemReference(metadata: metadata) {
            guard let item = canonicalItem(type: reference.type, id: reference.id) else {
                return finding(
                    event: event,
                    classification: .unresolvedProvenanceGap,
                    reasonCode: "referenced_canonical_item_not_found",
                    reason: "Capture metadata contains an item reference, but canonical item readback failed or the persisted type does not match.",
                    evidenceRefs: [captureRef, "capture_metadata:produced_item_ref"],
                    truthBoundary: "insufficient_evidence_no_inference_or_mutation",
                    safeCommands: [backlinkCommand]
                )
            }
            let getCommand = "cider-cli item get \(item.cliType) \(item.itemID.uuidString) --json"
            let contextCommand = "cider-cli item context \(item.cliType) \(item.itemID.uuidString) --json"
            return finding(
                event: event,
                classification: .survivingCanonicalItemWithRecoverableProvenance,
                reasonCode: "persisted_item_ref_and_canonical_readback",
                reason: "Capture metadata names a produced item and canonical item context readback confirms that exact surviving item and type.",
                item: item,
                evidenceRefs: [captureRef, item.itemRef, "capture_metadata:produced_item_ref"],
                truthBoundary: "recoverable_provenance_evidence_only_relation_remains_missing",
                safeCommands: [backlinkCommand, getCommand, contextCommand]
            )
        }

        return finding(
            event: event,
            classification: .unresolvedProvenanceGap,
            reasonCode: "no_conclusive_persisted_evidence",
            reason: "No explicit non-producing outcome, evidence-backed duplicate, or exact surviving canonical item reference was found.",
            evidenceRefs: [captureRef],
            truthBoundary: "insufficient_evidence_no_inference_or_mutation",
            safeCommands: [backlinkCommand]
        )
    }

    private func explicitDuplicateEvidence(metadata: [String: String]) -> (type: String, id: String)? {
        let outcome = firstValue(in: metadata, keys: ["capture_outcome", "outcome"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["duplicate", "deduplicated", "existing_item"].contains(outcome) else { return nil }
        guard let type = firstValue(in: metadata, keys: ["existing_item_type", "item_type"]),
              let id = firstValue(in: metadata, keys: ["existing_item_id", "item_id"]) else { return nil }
        return (type, id)
    }

    private func explicitNonproducingOutcome(
        event: CaptureEventRow,
        metadata: [String: String]
    ) -> (code: String, reason: String, evidenceKey: String)? {
        if event.sourceKind == "chat_unsupported_attachment",
           metadata["review_reason"] == "unsupported_attachment" {
            return (
                "explicit_nonproducing_capture_event",
                "This event intentionally records an unsupported chat attachment for review and did not claim to produce an item.",
                "review_reason"
            )
        }

        guard let rawOutcome = firstValue(in: metadata, keys: ["capture_outcome", "outcome"]) else {
            return nil
        }
        let outcome = rawOutcome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let failureValues: Set<String> = ["failed", "failure", "error"]
        let abandonmentValues: Set<String> = ["abandoned", "cancelled", "canceled", "dismissed", "skipped"]
        if failureValues.contains(outcome) {
            let detail = firstValue(in: metadata, keys: ["failure_reason", "reason", "error"]) ?? rawOutcome
            return ("explicit_capture_failure", "Capture history explicitly records failure: \(detail)", "capture_outcome")
        }
        if abandonmentValues.contains(outcome) {
            let detail = firstValue(in: metadata, keys: ["abandonment_reason", "reason"]) ?? rawOutcome
            return ("explicit_capture_abandonment", "Capture history explicitly records abandonment: \(detail)", "capture_outcome")
        }
        return nil
    }

    private func recoverableItemReference(metadata: [String: String]) -> (type: String, id: String)? {
        guard let type = firstValue(in: metadata, keys: ["produced_item_type", "producedItemType"]),
              let id = firstValue(in: metadata, keys: ["produced_item_id", "producedItemID"]) else {
            return nil
        }
        return (type, id)
    }

    private func canonicalItem(type rawType: String, id rawID: String) -> CanonicalItemEvidence? {
        guard let itemID = UUID(uuidString: rawID),
              let cliType = canonicalCLIType(rawType),
              let entityType = LibraryEntityType(rawValue: cliType) else {
            return nil
        }
        do {
            let context = try itemContextService.context(for: LibraryEntityRef(type: entityType, entityID: itemID))
            guard context.item.type == entityType else { return nil }
            return CanonicalItemEvidence(cliType: cliType, itemID: itemID)
        } catch {
            return nil
        }
    }

    private func auditedBookmarkDuplicate(
        event: CaptureEventRow,
        audits: [MutationAuditEntry]
    ) -> CanonicalItemEvidence? {
        guard let sourceURL = event.sourceURL,
              let canonicalSourceURL = VaultDuplicateAuditor.canonicalBookmarkURL(sourceURL),
              let itemID = uniqueBookmarkID(matchingCanonicalURL: canonicalSourceURL),
              let item = canonicalItem(type: "bookmark", id: itemID.uuidString) else {
            return nil
        }
        let matchingAudit = audits.first { audit in
            guard audit.action == "deduplicate_url_capture",
                  audit.itemType == "bookmark",
                  audit.itemID == itemID,
                  abs(audit.occurredAt.timeIntervalSince(event.createdAt)) <= Self.duplicateAuditWindow else {
                return false
            }
            let auditURL = audit.metadata["canonicalURL"] ?? audit.metadata["incomingURL"]
            return auditURL.flatMap(VaultDuplicateAuditor.canonicalBookmarkURL) == canonicalSourceURL
        }
        return matchingAudit == nil ? nil : item
    }

    private func uniqueBookmarkID(matchingCanonicalURL canonicalURL: String) -> UUID? {
        do {
            let statement = try database.prepare("SELECT item_id, url FROM bookmarks ORDER BY item_id ASC;")
            var matches: [UUID] = []
            while try statement.step() {
                guard VaultDuplicateAuditor.canonicalBookmarkURL(statement.string(at: 1)) == canonicalURL,
                      let itemID = UUID(uuidString: statement.string(at: 0)) else { continue }
                matches.append(itemID)
                if matches.count > 1 { return nil }
            }
            return matches.first
        } catch {
            return nil
        }
    }

    private func metadataEvidence(
        for event: CaptureEventRow,
        metadata: [String: String]?
    ) -> CiderCaptureProvenanceEvidenceCheck {
        guard let metadata else {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .captureMetadata,
                status: .malformed,
                reasonCode: "malformed_capture_metadata",
                evidenceRefs: []
            )
        }
        if recoverableItemReference(metadata: metadata) != nil {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .captureMetadata,
                status: .found,
                reasonCode: "exact_produced_item_ref_present",
                evidenceRefs: ["capture_metadata:produced_item_ref"]
            )
        }
        if explicitDuplicateEvidence(metadata: metadata) != nil {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .captureMetadata,
                status: .found,
                reasonCode: "explicit_duplicate_ref_present",
                evidenceRefs: ["capture_metadata:duplicate"]
            )
        }
        if let outcome = explicitNonproducingOutcome(event: event, metadata: metadata) {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .captureMetadata,
                status: .found,
                reasonCode: outcome.code,
                evidenceRefs: ["capture_metadata:\(outcome.evidenceKey)"]
            )
        }
        return CiderCaptureProvenanceEvidenceCheck(
            category: .captureMetadata,
            status: .missing,
            reasonCode: "capture_metadata_has_no_provenance_claim",
            evidenceRefs: []
        )
    }

    private func canonicalCandidateEvidence(
        for event: CaptureEventRow,
        metadata: [String: String]?
    ) -> CanonicalCandidateEvidence {
        if let metadata, let reference = recoverableItemReference(metadata: metadata) {
            if let item = canonicalItem(type: reference.type, id: reference.id) {
                return CanonicalCandidateEvidence(
                    check: CiderCaptureProvenanceEvidenceCheck(
                        category: .canonicalItemReadback,
                        status: .found,
                        reasonCode: "exact_canonical_item_readback_succeeded",
                        evidenceRefs: [item.itemRef]
                    ),
                    uniqueBookmark: nil,
                    canonicalURL: nil,
                    candidateCount: 1,
                    candidateCountIsLowerBound: false
                )
            }
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .missing,
                    reasonCode: "referenced_canonical_item_not_found",
                    evidenceRefs: []
                ),
                uniqueBookmark: nil,
                canonicalURL: nil,
                candidateCount: 0,
                candidateCountIsLowerBound: false
            )
        }
        if let metadata, let duplicate = explicitDuplicateEvidence(metadata: metadata) {
            if let item = canonicalItem(type: duplicate.type, id: duplicate.id) {
                return CanonicalCandidateEvidence(
                    check: CiderCaptureProvenanceEvidenceCheck(
                        category: .canonicalItemReadback,
                        status: .found,
                        reasonCode: "explicit_duplicate_item_readback_succeeded",
                        evidenceRefs: [item.itemRef]
                    ),
                    uniqueBookmark: nil,
                    canonicalURL: nil,
                    candidateCount: 1,
                    candidateCountIsLowerBound: false
                )
            }
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .missing,
                    reasonCode: "referenced_canonical_item_not_found",
                    evidenceRefs: []
                ),
                uniqueBookmark: nil,
                canonicalURL: nil,
                candidateCount: 0,
                candidateCountIsLowerBound: false
            )
        }
        guard event.sourceKind == "url",
              let sourceURL = event.sourceURL,
              let canonicalURL = VaultDuplicateAuditor.canonicalBookmarkURL(sourceURL) else {
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .notApplicable,
                    reasonCode: "canonical_item_not_named_by_persisted_evidence",
                    evidenceRefs: []
                ),
                uniqueBookmark: nil,
                canonicalURL: nil,
                candidateCount: 0,
                candidateCountIsLowerBound: false
            )
        }

        let candidates = bookmarkCandidates(matchingCanonicalURL: canonicalURL)
        if candidates.count > Self.evidenceRefLimit {
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .capped,
                    reasonCode: "canonical_url_candidate_cap_reached",
                    evidenceRefs: candidates.prefix(Self.evidenceRefLimit).map(\.itemRef)
                ),
                uniqueBookmark: nil,
                canonicalURL: canonicalURL,
                candidateCount: candidates.count,
                candidateCountIsLowerBound: true
            )
        }
        if candidates.count > 1 {
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .ambiguous,
                    reasonCode: "ambiguous_canonical_url_candidates",
                    evidenceRefs: candidates.map(\.itemRef)
                ),
                uniqueBookmark: nil,
                canonicalURL: canonicalURL,
                candidateCount: candidates.count,
                candidateCountIsLowerBound: false
            )
        }
        if let candidate = candidates.first {
            return CanonicalCandidateEvidence(
                check: CiderCaptureProvenanceEvidenceCheck(
                    category: .canonicalItemReadback,
                    status: .found,
                    reasonCode: "unique_canonical_url_candidate_readback_succeeded",
                    evidenceRefs: [candidate.itemRef]
                ),
                uniqueBookmark: candidate,
                canonicalURL: canonicalURL,
                candidateCount: 1,
                candidateCountIsLowerBound: false
            )
        }
        return CanonicalCandidateEvidence(
            check: CiderCaptureProvenanceEvidenceCheck(
                category: .canonicalItemReadback,
                status: .missing,
                reasonCode: "no_surviving_canonical_url_candidate",
                evidenceRefs: []
            ),
            uniqueBookmark: nil,
            canonicalURL: canonicalURL,
            candidateCount: 0,
            candidateCountIsLowerBound: false
        )
    }

    private func bookmarkCandidates(matchingCanonicalURL canonicalURL: String) -> [CanonicalItemEvidence] {
        do {
            let statement = try database.prepare("SELECT item_id, url FROM bookmarks ORDER BY item_id ASC;")
            var candidates: [CanonicalItemEvidence] = []
            while try statement.step() {
                guard VaultDuplicateAuditor.canonicalBookmarkURL(statement.string(at: 1)) == canonicalURL,
                      let item = canonicalItem(type: "bookmark", id: statement.string(at: 0)) else { continue }
                candidates.append(item)
                if candidates.count > Self.evidenceRefLimit { break }
            }
            return candidates
        } catch {
            return []
        }
    }

    private func candidateDiscovery(
        for event: CaptureEventRow,
        metadata: [String: String]?,
        metadataEvidence: CiderCaptureProvenanceEvidenceCheck,
        candidateEvidence: CanonicalCandidateEvidence,
        auditEvidence: CiderCaptureProvenanceEvidenceCheck,
        audits: [MutationAuditEntry],
        auditPage: DuplicateAuditPage,
        safeVerificationCommands: [String]
    ) -> CiderCaptureProvenanceCandidateDiscovery {
        let hasPersistedReference = metadata.map {
            recoverableItemReference(metadata: $0) != nil || explicitDuplicateEvidence(metadata: $0) != nil
        } ?? false
        let exactCount = hasPersistedReference ? candidateEvidence.candidateCount : 0
        let exactRefs = hasPersistedReference ? candidateEvidence.check.evidenceRefs.sorted() : []
        let exactStatus = hasPersistedReference ? candidateEvidence.check.status : metadataEvidence.status
        let exactReason = hasPersistedReference ? candidateEvidence.check.reasonCode : metadataEvidence.reasonCode

        let canonicalCount = hasPersistedReference ? 0 : candidateEvidence.candidateCount
        let canonicalRefs = hasPersistedReference ? [] : candidateEvidence.check.evidenceRefs.sorted()
        let canonicalStatus: CiderCaptureProvenanceEvidenceStatus = hasPersistedReference
            ? .notApplicable
            : candidateEvidence.check.status
        let canonicalReason = hasPersistedReference
            ? "canonical_url_discovery_not_needed_for_exact_persisted_reference"
            : candidateEvidence.check.reasonCode
        let nearbyAuditRefs = nearbyDuplicateAuditCandidateRefs(for: event, audits: audits)
        let counts = [
            CiderCaptureProvenanceCandidateEvidenceCount(
                category: .exactPersistedItemReference,
                status: exactStatus,
                reasonCode: exactReason,
                candidateCount: exactCount,
                candidateCountIsLowerBound: false,
                candidateRefs: exactRefs
            ),
            CiderCaptureProvenanceCandidateEvidenceCount(
                category: .canonicalURLMatch,
                status: canonicalStatus,
                reasonCode: canonicalReason,
                candidateCount: canonicalCount,
                candidateCountIsLowerBound: !hasPersistedReference && candidateEvidence.candidateCountIsLowerBound,
                candidateRefs: canonicalRefs
            ),
            CiderCaptureProvenanceCandidateEvidenceCount(
                category: .nearbyDuplicateAuditMatch,
                status: auditEvidence.status,
                reasonCode: auditEvidence.reasonCode,
                candidateCount: nearbyAuditRefs.count,
                candidateCountIsLowerBound: auditPage.hasMore,
                candidateRefs: nearbyAuditRefs
            ),
        ]
        let discoveredCount = hasPersistedReference ? exactCount : canonicalCount
        let countIsLowerBound = !hasPersistedReference && candidateEvidence.candidateCountIsLowerBound
        let saturated = countIsLowerBound || auditPage.hasMore
        let outcome: CiderCaptureProvenanceCandidateDiscoveryOutcome
        let reasonCode: String
        if countIsLowerBound {
            outcome = .cappedCandidateEvidence
            reasonCode = "canonical_candidate_count_cap_reached"
        } else if discoveredCount == 0 {
            outcome = .zeroCandidates
            reasonCode = "zero_surviving_canonical_candidates"
        } else if discoveredCount == 1 {
            outcome = .oneCandidateInsufficient
            if auditPage.hasMore {
                reasonCode = "one_candidate_with_capped_supporting_evidence"
            } else if auditEvidence.status == .stale {
                reasonCode = "one_candidate_with_stale_supporting_evidence"
            } else {
                reasonCode = "one_candidate_without_sufficient_provenance_evidence"
            }
        } else {
            outcome = .multipleCandidatesAmbiguous
            reasonCode = "multiple_surviving_canonical_candidates"
        }
        let candidateRefs = Array(orderedUnique(exactRefs + canonicalRefs).sorted().prefix(Self.evidenceRefLimit))

        return CiderCaptureProvenanceCandidateDiscovery(
            outcome: outcome,
            reasonCode: reasonCode,
            discoveredCandidateCount: discoveredCount,
            discoveredCandidateCountIsLowerBound: countIsLowerBound,
            countsByEvidenceCategory: counts,
            candidateRefs: candidateRefs,
            candidateRefsTruncated: discoveredCount > candidateRefs.count,
            saturated: saturated,
            caps: [
                "candidateRefs": Self.evidenceRefLimit,
                "duplicateAuditEntries": Self.duplicateAuditLimit,
            ],
            truthBoundary: "bounded_persisted_candidate_evidence_only_no_candidate_selection_provenance_inference_or_repair",
            safeVerificationCommands: safeVerificationCommands
        )
    }

    private func nearbyDuplicateAuditCandidateRefs(
        for event: CaptureEventRow,
        audits: [MutationAuditEntry]
    ) -> [String] {
        guard let sourceURL = event.sourceURL,
              let canonicalURL = VaultDuplicateAuditor.canonicalBookmarkURL(sourceURL) else { return [] }
        let refs = audits.compactMap { audit -> String? in
            guard audit.action == "deduplicate_url_capture",
                  audit.itemType == "bookmark",
                  abs(audit.occurredAt.timeIntervalSince(event.createdAt)) <= Self.duplicateAuditWindow,
                  let auditURL = audit.metadata["canonicalURL"] ?? audit.metadata["incomingURL"],
                  VaultDuplicateAuditor.canonicalBookmarkURL(auditURL) == canonicalURL,
                  let item = canonicalItem(type: "bookmark", id: audit.itemID.uuidString) else {
                return nil
            }
            return item.itemRef
        }
        return Array(orderedUnique(refs).sorted().prefix(Self.evidenceRefLimit))
    }

    private func duplicateAuditEvidence(
        for event: CaptureEventRow,
        candidateEvidence: CanonicalCandidateEvidence,
        audits: [MutationAuditEntry],
        capReached: Bool
    ) -> CiderCaptureProvenanceEvidenceCheck {
        guard event.sourceKind == "url" else {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: .notApplicable,
                reasonCode: "duplicate_audit_not_applicable_to_source_kind",
                evidenceRefs: []
            )
        }
        guard candidateEvidence.check.status != .ambiguous,
              candidateEvidence.check.status != .capped,
              let candidate = candidateEvidence.uniqueBookmark,
              let canonicalURL = candidateEvidence.canonicalURL else {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: candidateEvidence.check.status == .ambiguous ? .ambiguous : .missing,
                reasonCode: candidateEvidence.check.status == .ambiguous
                    ? "duplicate_audit_not_checked_for_ambiguous_candidates"
                    : "duplicate_audit_has_no_unique_candidate",
                evidenceRefs: []
            )
        }
        let matches = audits.filter { audit in
            guard audit.action == "deduplicate_url_capture",
                  audit.itemType == "bookmark",
                  audit.itemID == candidate.itemID else { return false }
            let auditURL = audit.metadata["canonicalURL"] ?? audit.metadata["incomingURL"]
            return auditURL.flatMap(VaultDuplicateAuditor.canonicalBookmarkURL) == canonicalURL
        }
        if let nearby = matches.first(where: {
            abs($0.occurredAt.timeIntervalSince(event.createdAt)) <= Self.duplicateAuditWindow
        }) {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: .found,
                reasonCode: "nearby_duplicate_audit_matches_unique_candidate",
                evidenceRefs: ["mutation_audit:\(nearby.id.uuidString)"]
            )
        }
        guard !capReached else {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: .capped,
                reasonCode: "duplicate_audit_scan_cap_reached",
                evidenceRefs: []
            )
        }
        if !matches.isEmpty {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: .stale,
                reasonCode: "matching_duplicate_audit_outside_time_window",
                evidenceRefs: []
            )
        }
        return CiderCaptureProvenanceEvidenceCheck(
            category: .duplicateAudit,
            status: .missing,
            reasonCode: "no_matching_duplicate_audit",
            evidenceRefs: []
        )
    }

    private func explanationSummary(for reasonCode: String) -> String {
        switch reasonCode {
        case "explicit_duplicate_with_canonical_item", "canonical_url_duplicate_audit":
            return "Persisted duplicate evidence explains why this capture event has no produced_item relation."
        case "explicit_nonproducing_capture_event", "explicit_capture_failure", "explicit_capture_abandonment":
            return "Persisted capture history records an explicit non-producing outcome."
        case "persisted_item_ref_and_canonical_readback":
            return "An exact persisted item reference and canonical readback explain a recoverable provenance gap."
        default:
            return "Persisted evidence is insufficient to explain this provenance gap conclusively."
        }
    }

    private func finding(
        event: CaptureEventRow,
        classification: CiderCaptureProvenanceGapClassification,
        reasonCode: String,
        reason: String,
        item: CanonicalItemEvidence? = nil,
        evidenceRefs: [String],
        truthBoundary: String,
        safeCommands: [String]
    ) -> CiderCaptureProvenanceGapFinding {
        CiderCaptureProvenanceGapFinding(
            captureEventID: event.id,
            captureEventRef: "capture_event:\(event.id)",
            sourceKind: event.sourceKind,
            classification: classification,
            reasonCode: reasonCode,
            reason: reason,
            itemRef: item?.itemRef,
            evidenceRefs: evidenceRefs,
            truthBoundary: truthBoundary,
            safeNextCommands: orderedUnique(safeCommands),
            safeVerificationCommands: orderedUnique(safeCommands)
        )
    }

    private func canonicalCLIType(_ rawType: String) -> String? {
        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bookmark": return "bookmark"
        case "note", "journal": return "note"
        case "todo", "task": return "todo"
        case "event", "datecard", "date_card": return "dateCard"
        case "contact": return "contact"
        case "file", "vaultfile", "vault_file": return "vaultFile"
        default: return nil
        }
    }

    private func firstValue(in metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = metadata[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
