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
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
            "safeVerificationCommands": safeVerificationCommands,
        ]
        if let itemRef { result["itemRef"] = itemRef }
        return result
    }
}

@MainActor
final class CiderCaptureProvenanceDiagnosticService {
    static let defaultLimit = 50
    static let maximumLimit = 100
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

    private struct CanonicalItemEvidence {
        var cliType: String
        var itemID: UUID
        var itemRef: String { "\(cliType):\(itemID.uuidString)" }
    }

    private struct CanonicalCandidateEvidence {
        var check: CiderCaptureProvenanceEvidenceCheck
        var uniqueBookmark: CanonicalItemEvidence?
        var canonicalURL: String?
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

    func explain(captureEventRef rawRef: String) throws -> CiderCaptureProvenanceGapExplanation {
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

        let owner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: event.id)
        let producedItemRelations = try secondBrainStore.outgoingRelations(for: owner)
            .filter { $0.relationType == "produced_item" }
        guard producedItemRelations.isEmpty else {
            throw CiderCaptureProvenanceExplanationError.captureEventNoLongerHasGap
        }

        let loadedAudits = mutationAuditService.loadEntries(limit: Self.duplicateAuditLimit + 1)
        let auditCapReached = loadedAudits.count > Self.duplicateAuditLimit
        let boundedAudits = Array(loadedAudits.prefix(Self.duplicateAuditLimit))
        let finding = classify(event, duplicateAudits: auditCapReached ? [] : boundedAudits)
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
        let replayCommand = "cider-cli capture provenance-gap \(captureRef) --json"
        let safeCommands = orderedUnique([replayCommand] + finding.safeVerificationCommands)
        let refs = orderedUnique(finding.evidenceRefs + checks.flatMap(\.evidenceRefs))
            .prefix(Self.evidenceRefLimit)

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
            truthBoundary: "read_only_explanation_no_inference_candidate_selection_or_provenance_repair",
            safeNextCommands: safeCommands,
            safeVerificationCommands: safeCommands
        )
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
                    canonicalURL: nil
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
                canonicalURL: nil
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
                    canonicalURL: nil
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
                canonicalURL: nil
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
                canonicalURL: nil
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
                canonicalURL: canonicalURL
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
                canonicalURL: canonicalURL
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
                canonicalURL: canonicalURL
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
            canonicalURL: canonicalURL
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
        guard !capReached else {
            return CiderCaptureProvenanceEvidenceCheck(
                category: .duplicateAudit,
                status: .capped,
                reasonCode: "duplicate_audit_scan_cap_reached",
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
