import CryptoKit
import Foundation
import os

struct CiderRoutingDecisionTarget: Equatable, Sendable {
    var kind: String
    var name: String
    var relativePath: String
    var folderID: UUID?
    var spaceID: String? = nil

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "kind": kind,
            "name": name,
            "relativePath": relativePath,
        ]
        if let folderID {
            dictionary["folderID"] = folderID.uuidString
        }
        if let spaceID {
            dictionary["spaceID"] = spaceID
        }
        return dictionary
    }
}

struct CiderRoutingReviewMutationResult: Equatable {
    var item: CiderRoutingItemSummary
    var decision: CiderRoutingDecision
    var receiptID: String
    var changed: Bool
    var truthBoundary: String
}

struct CiderRoutingDecision: Identifiable, Equatable {
    var id: UUID
    var itemID: UUID
    var itemType: String
    var target: CiderRoutingDecisionTarget
    var confidence: Double
    var reason: String
    var actor: String
    var source: String
    var reviewState: String
    var createdAt: Date
    var supersedesDecisionID: UUID?

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "id": id.uuidString,
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "target": target.toDictionary(),
            "confidence": confidence,
            "reason": reason,
            "actor": actor,
            "source": source,
            "reviewState": reviewState,
            "createdAt": formatter.string(from: createdAt),
        ]
        if let supersedesDecisionID {
            dictionary["supersedesDecisionID"] = supersedesDecisionID.uuidString
        }
        return dictionary
    }
}

struct CiderRoutingItemSummary: Equatable {
    var id: UUID
    var type: String
    var title: String
    var relativePath: String?
    var folderID: UUID?
    var updatedAt: Date? = nil

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": id.uuidString,
            "type": type,
            "title": title,
        ]
        if let relativePath {
            dictionary["relativePath"] = relativePath
        }
        if let folderID {
            dictionary["folderID"] = folderID.uuidString
        }
        return dictionary
    }
}

struct CiderRoutingExplanation: Equatable {
    var command: String
    var item: CiderRoutingItemSummary
    var latestDecision: CiderRoutingDecision?
    var history: [CiderRoutingDecision]
    var reviewNeeded: Bool
    var nextSafeAction: String

    func toDictionary() -> [String: Any] {
        let confidence = latestDecision?.confidence
        let needsRouting = reviewNeeded || latestDecision?.reviewState == "needs_review"
        let blockingIssues = reviewNeeded ? ["routing_needs_review"] : []
        var dictionary: [String: Any] = [
            "ok": true,
            "command": command,
            "readOnly": true,
            "changed": false,
            "item": item.toDictionary(),
            "history": history.map { $0.toDictionary() },
            "reviewNeeded": reviewNeeded,
            "nextSafeAction": nextSafeAction,
        ]
        CiderAgentDecisionContract.merge(
            CiderAgentDecisionContract.dictionary(
                saved: true,
                needsReview: reviewNeeded,
                needsRouting: needsRouting,
                confidence: confidence,
                blockingIssues: blockingIssues,
                recommendedNextAction: reviewNeeded ? "review_route" : nextSafeAction,
                safeNextCommands: [
                    "cider-cli item get \(item.type) \(item.id.uuidString) --json",
                    "cider-cli item context \(item.type) \(item.id.uuidString) --json",
                ]
            ),
            into: &dictionary
        )
        if let latestDecision {
            dictionary["routing"] = latestDecision.toDictionary()
        } else {
            dictionary["routing"] = NSNull()
        }
        return dictionary
    }
}

enum CiderRoutingDecisionError: LocalizedError {
    case databaseUnavailable
    case itemNotFound(UUID)
    case itemReferenceNotFound(String)
    case ambiguousItemReference(String, Int)
    case decisionNotFound(UUID)
    case unsupportedItemType(String)
    case correctionFailed(UUID)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "SQLite database is not open."
        case .itemNotFound(let id):
            return "No item found with ID \(id.uuidString)."
        case .itemReferenceNotFound(let ref):
            return "No item found matching '\(ref)'."
        case .ambiguousItemReference(let ref, let count):
            return "Item reference '\(ref)' is ambiguous; it matches \(count) items."
        case .decisionNotFound(let id):
            return "No routing decision found for item \(id.uuidString)."
        case .unsupportedItemType(let type):
            return "Routing correction is not supported for item type '\(type)' yet."
        case .correctionFailed(let id):
            return "Could not apply routing correction to item \(id.uuidString)."
        }
    }
}

enum CiderRoutingReviewActionError: Error, LocalizedError, Equatable {
    case malformedCandidate
    case candidateUnavailable
    case itemMismatch
    case staleCandidate
    case alreadyReviewed
    case unsupportedAction
    case missingDestination
    case invalidDestination
    case unresolvedDestination
    case ambiguousDestination
    case unauthorizedDestination
    case unsupportedCorrectionItemType
    case assignmentFailed

    var errorDescription: String? {
        switch self {
        case .malformedCandidate, .candidateUnavailable, .itemMismatch:
            return "This routing suggestion is no longer available. Refresh the review list; nothing was changed."
        case .staleCandidate:
            return "This routing suggestion changed after it loaded. Refresh the review list before acting."
        case .alreadyReviewed:
            return "This routing suggestion was already reviewed. Refresh to see its current state."
        case .unsupportedAction:
            return "This action is not supported for routing review. Nothing was changed."
        case .missingDestination:
            return "Choose an explicit routing destination before continuing. Nothing was changed."
        case .invalidDestination:
            return "That routing destination is invalid. Refresh the available destinations; nothing was changed."
        case .unresolvedDestination:
            return "That routing destination no longer exists. Refresh the available destinations; nothing was changed."
        case .ambiguousDestination:
            return "That routing destination is ambiguous. Choose one exact destination; nothing was changed."
        case .unauthorizedDestination:
            return "Cider could not verify authority for that routing destination. Nothing was changed."
        case .unsupportedCorrectionItemType:
            return "Use the item's Move action to correct this non-bookmark destination. Nothing was changed."
        case .assignmentFailed:
            return "Cider could not safely move this item to the selected destination. Nothing was changed."
        }
    }
}

enum CiderRoutingReviewMutationCheckpoint: Equatable {
    case afterBookmarkFileMove
    case afterBookmarkPersistence
    case afterRequiredAudit
    case afterLifecycle
}

@MainActor
final class CiderRoutingDecisionService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "CiderRoutingDecisionService"
    )

    private let database: CiderDatabase?
    private let failureInjector: (@MainActor (CiderRoutingReviewMutationCheckpoint) throws -> Void)?

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(
        database: CiderDatabase? = nil,
        failureInjector: (@MainActor (CiderRoutingReviewMutationCheckpoint) throws -> Void)? = nil
    ) {
        self.database = database
        self.failureInjector = failureInjector
    }

    @discardableResult
    func performReviewAction(
        candidateID: UUID,
        itemID: UUID,
        expectedReviewState: String,
        expectedCreatedAt: Date,
        action: CiderReviewAction,
        destination requestedDestination: CiderRoutingDecisionTarget?,
        reason: String?,
        actor: String,
        bookmarkService: VaultBookmarkService = .shared
    ) throws -> CiderRoutingReviewMutationResult {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        guard action == .approve || action == .defer || action == .correct else {
            throw CiderRoutingReviewActionError.unsupportedAction
        }
        guard let requestedDestination else {
            throw CiderRoutingReviewActionError.missingDestination
        }
        let normalizedDestination = try syntacticallyNormalizedDestination(requestedDestination)
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fingerprint = Self.reviewRequestFingerprint(
            candidateID: candidateID,
            itemID: itemID,
            expectedReviewState: expectedReviewState,
            expectedCreatedAt: expectedCreatedAt,
            action: action,
            actor: actor,
            destination: normalizedDestination,
            reason: normalizedReason
        )
        let receiptID = "routing-review:\(action.rawValue):\(fingerprint)"
        if let replay = try replayedReviewMutation(
            candidateID: candidateID,
            itemID: itemID,
            action: action,
            actor: actor,
            requestFingerprint: fingerprint,
            receiptID: receiptID
        ) {
            return replay
        }

        var result: CiderRoutingReviewMutationResult!
        var routingAssignment: VaultBookmarkService.CompensatableRoutingAssignment?
        do {
            try db.withTransaction {
            let candidate = try decision(id: candidateID)
            guard candidate.itemID == itemID else {
                throw CiderRoutingReviewActionError.itemMismatch
            }
            let latest = try latestDecision(for: itemID)
            guard latest.id == candidate.id,
                  candidate.reviewState == expectedReviewState,
                  Self.preciseVersion(candidate.createdAt) == Self.preciseVersion(expectedCreatedAt) else {
                if ["accepted", "corrected", "manual_move", "deferred"].contains(latest.reviewState) {
                    throw CiderRoutingReviewActionError.alreadyReviewed
                }
                throw CiderRoutingReviewActionError.staleCandidate
            }
            if action == .defer, candidate.reviewState == "deferred" {
                throw CiderRoutingReviewActionError.alreadyReviewed
            }
            let item = try itemSummary(for: itemID)
            let destination = try validatedDestination(
                normalizedDestination,
                item: item,
                candidate: candidate,
                action: action,
                database: db
            )
            let source: String
            let reviewState: String
            let status: String
            let mutationReason: String
            let truthBoundary: String
            switch action {
            case .approve:
                source = "routing.approve"
                reviewState = "accepted"
                status = "accepted"
                mutationReason = "Approved existing routing decision."
                truthBoundary = "accepted_routing_decision"
            case .defer:
                source = "review.defer"
                reviewState = "deferred"
                status = "deferred"
                mutationReason = normalizedReason.isEmpty ? "Deferred from routing review." : normalizedReason
                truthBoundary = "reviewable_candidate_not_truth"
            case .correct:
                source = "routing.correct"
                reviewState = "corrected"
                status = "corrected"
                mutationReason = normalizedReason.isEmpty ? "Corrected routing destination." : normalizedReason
                truthBoundary = "corrected_routing_destination"
            case .reject:
                throw CiderRoutingReviewActionError.unsupportedAction
            }

            if action == .correct {
                guard item.type == "bookmark" else {
                    throw CiderRoutingReviewActionError.unsupportedCorrectionItemType
                }
                routingAssignment = try bookmarkService.beginCompensatableRoutingAssignment(
                    itemID,
                    to: destination,
                    database: db,
                    failureInjector: failureInjector
                )
            }

            let resultingDecision = try recordDecision(
                itemID: itemID,
                itemType: item.type,
                target: destination,
                confidence: action == .correct ? 1 : candidate.confidence,
                reason: mutationReason,
                actor: actor,
                source: source,
                reviewState: reviewState,
                supersedesDecisionID: candidate.id,
                createdAt: Date(
                    timeIntervalSince1970: max(
                        Date().timeIntervalSince1970,
                        candidate.createdAt.timeIntervalSince1970.nextUp
                    )
                ),
                decisionID: Self.deterministicDecisionID(requestFingerprint: fingerprint)
            )
            let command = "review.routing.\(action.rawValue)"
            let beforeState = routingAuditState(candidate)
            let afterState = routingAuditState(resultingDecision)
            _ = try MutationAuditService(database: db).recordRequired(
                action: command,
                itemType: item.type,
                itemID: itemID,
                before: beforeState,
                after: afterState,
                metadata: [
                    "actor": actor,
                    "routingDecisionID": resultingDecision.id.uuidString,
                    "supersedesDecisionID": candidate.id.uuidString,
                    "targetRelativePath": destination.relativePath,
                ],
                source: Self.auditSource(for: actor)
            )
            try failureInjector?(.afterRequiredAudit)
            try SecondBrainReviewLifecycleService(database: db).record(
                SecondBrainReviewLifecycleEvent(
                    owner: SecondBrainOwnerRef(ownerType: "routing_decision", ownerID: resultingDecision.id.uuidString),
                    candidateRef: "routing_decision:\(resultingDecision.id.uuidString)",
                    lifecycleState: reviewState,
                    eventKind: status,
                    actor: actor,
                    source: command,
                    toolName: command,
                    reason: mutationReason,
                    supersedesRef: "routing_decision:\(candidate.id.uuidString)",
                    metadata: [
                        "item_ref": "\(item.type):\(item.id.uuidString)",
                        "target_relative_path": destination.relativePath,
                        "confidence": String(resultingDecision.confidence),
                    ],
                    createdAt: resultingDecision.createdAt
                )
            )
            try failureInjector?(.afterLifecycle)
            let targetFingerprint = Self.destinationFingerprint(destination)
            let beforeJSON = DatabaseHelpers.encodeJSON([
                "reviewState": candidate.reviewState,
                "routingDecisionID": candidate.id.uuidString,
                "targetFingerprint": Self.destinationFingerprint(candidate.target),
            ])
            let afterJSON = DatabaseHelpers.encodeJSON([
                "requestFingerprint": fingerprint,
                "reviewState": reviewState,
                "routingState": reviewState,
                "truthBoundary": truthBoundary,
                "routingDecisionID": resultingDecision.id.uuidString,
                "resultingVersion": Self.preciseVersion(resultingDecision.createdAt),
                "targetFingerprint": targetFingerprint,
            ])
            let owner = SecondBrainOwnerRef(ownerType: secondBrainOwnerType(for: item.type), ownerID: item.id.uuidString)
            let safeVerificationCommands = [
                "cider-cli review list --include-deferred --json",
                "cider-cli item action-ledger list --owner \(owner.canonicalRef) --command \(command) --json",
                "cider-cli item context \(item.type) \(item.id.uuidString) --max-history 10 --json",
                "cider-cli routing explain \(item.id.uuidString) --json",
                "cider-cli item action-ledger inspect \(receiptID) --json",
            ]
            let safeNextCommands = [
                "cider-cli review list --json",
                "cider-cli review list --include-deferred --json",
                "cider-cli item recall-context --item \(item.type) \(item.id.uuidString) --history-command \(command) --json",
            ]
            _ = try SecondBrainActionReceiptLedgerService(database: db).record(
                SecondBrainActionReceiptRecord(
                    id: receiptID,
                    command: command,
                    action: action.rawValue,
                    actor: actor,
                    status: status,
                    owner: owner,
                    sourceRefs: [owner.canonicalRef, "routing_decision:\(candidate.id.uuidString)", "routing_decision:\(resultingDecision.id.uuidString)"],
                    evidenceRefs: ["routing_decision:\(candidate.id.uuidString)"],
                    readOnly: false,
                    changed: true,
                    beforeJSON: beforeJSON,
                    afterJSON: afterJSON,
                    safeVerificationCommands: safeVerificationCommands,
                    safeNextCommands: safeNextCommands,
                    receiptJSON: DatabaseHelpers.encodeJSON([
                        "id": receiptID,
                        "commandFamily": "routing_decision",
                        "truthBoundary": truthBoundary,
                        "requestFingerprint": fingerprint,
                    ]),
                    createdAt: resultingDecision.createdAt
                )
            )

            result = CiderRoutingReviewMutationResult(
                item: item,
                decision: resultingDecision,
                receiptID: receiptID,
                changed: true,
                truthBoundary: truthBoundary
            )
            }
        } catch {
            let transactionError = error
            if let routingAssignment {
                do {
                    try bookmarkService.compensateRoutingAssignment(routingAssignment)
                } catch {
                    throw CiderRoutingReviewActionError.assignmentFailed
                }
            }
            throw transactionError
        }
        if let routingAssignment {
            bookmarkService.finalizeRoutingAssignment(routingAssignment)
        }
        return result
    }

    @discardableResult
    func recordDecision(
        itemID: UUID,
        itemType: String,
        target: CiderRoutingDecisionTarget,
        confidence: Double,
        reason: String,
        actor: String,
        source: String,
        reviewState: String,
        supersedesDecisionID: UUID? = nil,
        createdAt: Date = Date(),
        decisionID: UUID = UUID()
    ) throws -> CiderRoutingDecision {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }

        let decision = CiderRoutingDecision(
            id: decisionID,
            itemID: itemID,
            itemType: itemType,
            target: target,
            confidence: confidence,
            reason: reason,
            actor: actor,
            source: source,
            reviewState: reviewState,
            createdAt: createdAt,
            supersedesDecisionID: supersedesDecisionID
        )

        let stmt = try db.prepare("""
            INSERT INTO routing_decisions (
                id, item_id, item_type, target_kind, target_name, target_relative_path,
                target_folder_id, target_space_id, confidence, reason, actor, source, review_state,
                created_at, supersedes_decision_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(decision.id.uuidString, at: 1)
            .bind(decision.itemID.uuidString, at: 2)
            .bind(decision.itemType, at: 3)
            .bind(decision.target.kind, at: 4)
            .bind(decision.target.name, at: 5)
            .bind(decision.target.relativePath, at: 6)
            .bind(decision.target.folderID?.uuidString, at: 7)
            .bind(decision.target.spaceID, at: 8)
            .bind(decision.confidence, at: 9)
            .bind(decision.reason, at: 10)
            .bind(decision.actor, at: 11)
            .bind(decision.source, at: 12)
            .bind(decision.reviewState, at: 13)
            .bind(DatabaseHelpers.encode(decision.createdAt), at: 14)
            .bind(decision.supersedesDecisionID?.uuidString, at: 15)
        try stmt.step()
        try mirrorToSecondBrainProvenance(decision, database: db)
        return decision
    }

    func explain(itemID: UUID) throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        let history = try decisions(for: itemID)
        let latest = history.first
        return CiderRoutingExplanation(
            command: "routing.explain",
            item: item,
            latestDecision: latest,
            history: history,
            reviewNeeded: latest?.reviewState == "needs_review" || latest == nil,
            nextSafeAction: nextSafeAction(for: latest)
        )
    }

    func explain(itemRef: String) throws -> CiderRoutingExplanation {
        try explain(itemID: resolveItemID(ref: itemRef))
    }

    @discardableResult
    func recordCreateProvenance(
        itemID: UUID,
        source: String,
        actor: String = "user",
        reviewReason: String,
        acceptedReason: String
    ) throws -> CiderRoutingExplanation {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let item = try itemSummary(for: itemID)
        let previous = try? latestDecision(for: itemID)
        let target = targetFromCurrentItem(item)
        let isInbox = target.kind == "inbox"
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: isInbox ? 0 : 1,
            reason: isInbox ? reviewReason : acceptedReason,
            actor: actor,
            source: source,
            reviewState: isInbox ? "needs_review" : "accepted",
            supersedesDecisionID: previous?.id
        )
        _ = try SecondBrainItemContentIndexingService(database: db).rebuild(
            owner: SecondBrainOwnerRef(
                ownerType: secondBrainOwnerType(for: item.type),
                ownerID: itemID.uuidString
            )
        )
        return try explain(itemID: itemID)
    }

    func recordCreateProvenanceOrLog(
        itemID: UUID,
        source: String,
        actor: String = "user",
        reviewReason: String,
        acceptedReason: String
    ) {
        do {
            _ = try recordCreateProvenance(
                itemID: itemID,
                source: source,
                actor: actor,
                reviewReason: reviewReason,
                acceptedReason: acceptedReason
            )
        } catch {
            Self.logger.error("Failed to record create provenance for \(itemID.uuidString) from \(source): \(error.localizedDescription)")
        }
    }

    @discardableResult
    func approve(itemID: UUID, actor: String = "user") throws -> CiderRoutingExplanation {
        let latest = try latestDecision(for: itemID)
        _ = try recordDecision(
            itemID: itemID,
            itemType: latest.itemType,
            target: latest.target,
            confidence: latest.confidence,
            reason: "Approved existing routing decision.",
            actor: actor,
            source: "routing.approve",
            reviewState: "accepted",
            supersedesDecisionID: latest.id
        )
        return try explain(itemID: itemID)
    }

    @discardableResult
    func recordSpaceAssignment(
        itemID: UUID,
        spaceID: String,
        spaceName: String,
        reason: String,
        confidence: Double,
        actor: String = "agent",
        source: String
    ) throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        let previous = try? latestDecision(for: itemID)
        let target = CiderRoutingDecisionTarget(
            kind: "space",
            name: spaceName,
            relativePath: spaceName,
            folderID: nil,
            spaceID: spaceID
        )
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: confidence,
            reason: reason,
            actor: actor,
            source: source,
            reviewState: "accepted",
            supersedesDecisionID: previous?.id
        )
        try CiderSpaceMembershipStore(database: resolvedDatabase ?? .shared).assign(
            item: LibraryEntityRef(type: libraryEntityType(for: item.type), entityID: itemID),
            toSpaceID: spaceID,
            spaceName: spaceName,
            reason: reason,
            confidence: confidence,
            source: source,
            actor: actor
        )
        return try explain(itemID: itemID)
    }

    @discardableResult
    func recordManualMove(
        itemID: UUID,
        target: CiderRoutingDecisionTarget,
        reason: String,
        actor: String = "user",
        source: String
    ) throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        let previous = try? latestDecision(for: itemID)
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: 1,
            reason: reason,
            actor: actor,
            source: source,
            reviewState: "manual_move",
            supersedesDecisionID: previous?.id
        )
        return try explain(itemID: itemID)
    }

    @discardableResult
    func correctBookmark(
        itemID: UUID,
        target: CiderRoutingDecisionTarget,
        reason: String,
        actor: String = "user",
        bookmarkService: VaultBookmarkService
    ) throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        guard item.type == "bookmark" else { throw CiderRoutingDecisionError.unsupportedItemType(item.type) }
        guard bookmarkService.assignBookmark(
            itemID,
            toFolder: target.folderID,
            auditMetadata: [
                "classification": "routing_correction",
                "routingSource": "routing.correct",
                "actor": actor,
                "targetRelativePath": target.relativePath,
            ]
        ) else {
            throw CiderRoutingDecisionError.correctionFailed(itemID)
        }

        let previous = try? latestDecision(for: itemID)
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: 1,
            reason: reason,
            actor: actor,
            source: "routing.correct",
            reviewState: "corrected",
            supersedesDecisionID: previous?.id
        )
        return try explain(itemID: itemID)
    }

    @discardableResult
    func moveBookmarkManually(
        itemID: UUID,
        target: CiderRoutingDecisionTarget,
        reason: String,
        actor: String = "user",
        source: String = "bookmark.move",
        bookmarkService: VaultBookmarkService
    ) throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        guard item.type == "bookmark" else { throw CiderRoutingDecisionError.unsupportedItemType(item.type) }
        guard bookmarkService.assignBookmark(
            itemID,
            toFolder: target.folderID,
            auditMetadata: [
                "classification": "manual_routing_move",
                "routingSource": source,
                "actor": actor,
                "targetRelativePath": target.relativePath,
            ]
        ) else {
            throw CiderRoutingDecisionError.correctionFailed(itemID)
        }

        let previous = try? latestDecision(for: itemID)
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: 1,
            reason: reason,
            actor: actor,
            source: source,
            reviewState: "manual_move",
            supersedesDecisionID: previous?.id
        )
        return try explain(itemID: itemID)
    }

    @discardableResult
    func rerunDeterministic(itemID: UUID, actor: String = "agent") throws -> CiderRoutingExplanation {
        let item = try itemSummary(for: itemID)
        let previous = try? latestDecision(for: itemID)
        let target = targetFromCurrentItem(item)
        let isInbox = target.kind == "inbox"
        _ = try recordDecision(
            itemID: itemID,
            itemType: item.type,
            target: target,
            confidence: isInbox ? 0 : 1,
            reason: isInbox
                ? "No deterministic route was available, so Cider kept the item in Inbox for review."
                : "Deterministic reroute used the item's current folder.",
            actor: actor,
            source: "routing.rerun",
            reviewState: isInbox ? "needs_review" : "accepted",
            supersedesDecisionID: previous?.id
        )
        return try explain(itemID: itemID)
    }

    func resolveItemID(ref: String) throws -> UUID {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let stmt = try db.prepare("""
            SELECT id FROM items
            WHERE lower(id) LIKE ?
            ORDER BY updated_at DESC, created_at DESC;
            """)
        stmt.bind(trimmed.lowercased() + "%", at: 1)
        var matches: [UUID] = []
        while try stmt.step() {
            if let id = UUID(uuidString: stmt.string(at: 0)) {
                matches.append(id)
            }
        }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw CiderRoutingDecisionError.itemReferenceNotFound(ref) }
        throw CiderRoutingDecisionError.ambiguousItemReference(ref, matches.count)
    }

    private func latestDecision(for itemID: UUID) throws -> CiderRoutingDecision {
        guard let decision = try decisions(for: itemID).first else {
            throw CiderRoutingDecisionError.decisionNotFound(itemID)
        }
        return decision
    }

    private func decision(id: UUID) throws -> CiderRoutingDecision {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let stmt = try db.prepare("""
            SELECT id, item_id, item_type, target_kind, target_name, target_relative_path,
                   target_folder_id, target_space_id, confidence, reason, actor, source, review_state,
                   created_at, supersedes_decision_id
            FROM routing_decisions
            WHERE id = ?
            LIMIT 1;
            """)
        stmt.bind(id.uuidString, at: 1)
        guard try stmt.step(),
              let decisionID = UUID(uuidString: stmt.string(at: 0)),
              let itemID = UUID(uuidString: stmt.string(at: 1)) else {
            throw CiderRoutingReviewActionError.candidateUnavailable
        }
        return CiderRoutingDecision(
            id: decisionID,
            itemID: itemID,
            itemType: stmt.string(at: 2),
            target: CiderRoutingDecisionTarget(
                kind: stmt.string(at: 3),
                name: stmt.string(at: 4),
                relativePath: stmt.string(at: 5),
                folderID: stmt.optionalString(at: 6).flatMap(UUID.init(uuidString:)),
                spaceID: stmt.optionalString(at: 7)
            ),
            confidence: stmt.double(at: 8),
            reason: stmt.string(at: 9),
            actor: stmt.string(at: 10),
            source: stmt.string(at: 11),
            reviewState: stmt.string(at: 12),
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 13)),
            supersedesDecisionID: stmt.optionalString(at: 14).flatMap(UUID.init(uuidString:))
        )
    }

    private func decisions(for itemID: UUID) throws -> [CiderRoutingDecision] {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let stmt = try db.prepare("""
            SELECT id, item_id, item_type, target_kind, target_name, target_relative_path,
                   target_folder_id, target_space_id, confidence, reason, actor, source, review_state,
                   created_at, supersedes_decision_id
            FROM routing_decisions
            WHERE item_id = ?
            ORDER BY created_at DESC, id DESC;
            """)
        stmt.bind(itemID.uuidString, at: 1)

        var decisions: [CiderRoutingDecision] = []
        while try stmt.step() {
            guard let id = UUID(uuidString: stmt.string(at: 0)),
                  let itemID = UUID(uuidString: stmt.string(at: 1)) else { continue }
            decisions.append(CiderRoutingDecision(
                id: id,
                itemID: itemID,
                itemType: stmt.string(at: 2),
                target: CiderRoutingDecisionTarget(
                    kind: stmt.string(at: 3),
                    name: stmt.string(at: 4),
                    relativePath: stmt.string(at: 5),
                    folderID: stmt.optionalString(at: 6).flatMap(UUID.init(uuidString:)),
                    spaceID: stmt.optionalString(at: 7)
                ),
                confidence: stmt.double(at: 8),
                reason: stmt.string(at: 9),
                actor: stmt.string(at: 10),
                source: stmt.string(at: 11),
                reviewState: stmt.string(at: 12),
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 13)),
                supersedesDecisionID: stmt.optionalString(at: 14).flatMap(UUID.init(uuidString:))
            ))
        }
        return decisions
    }

    private func mirrorToSecondBrainProvenance(
        _ decision: CiderRoutingDecision,
        database db: CiderDatabase
    ) throws {
        let owner = SecondBrainOwnerRef(
            ownerType: secondBrainOwnerType(for: decision.itemType),
            ownerID: decision.itemID.uuidString
        )
        try SecondBrainStore(database: db).recordRoutingDecision(
            SecondBrainRoutingDecision(
                id: decision.id.uuidString,
                owner: owner,
                itemID: decision.itemID.uuidString,
                targetType: decision.target.kind,
                targetID: decision.target.kind == "space"
                    ? decision.target.spaceID
                    : decision.target.folderID?.uuidString,
                targetPath: decision.target.relativePath,
                confidence: decision.confidence,
                reason: decision.reason,
                status: decision.reviewState,
                actor: decision.actor,
                source: decision.source,
                reviewedAt: decision.reviewState == "needs_review" ? nil : decision.createdAt
            )
        )
    }

    private func secondBrainOwnerType(for itemType: String) -> String {
        itemType == "event" ? "dateCard" : itemType
    }

    private func replayedReviewMutation(
        candidateID: UUID,
        itemID: UUID,
        action: CiderReviewAction,
        actor: String,
        requestFingerprint: String,
        receiptID: String
    ) throws -> CiderRoutingReviewMutationResult? {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        guard let receipt = try SecondBrainActionReceiptLedgerService(database: db).inspect(id: receiptID),
              receipt.command == "review.routing.\(action.rawValue)",
              receipt.action == action.rawValue,
              receipt.actor == actor,
              receipt.changed,
              !receipt.readOnly,
              receipt.owner?.ownerID == itemID.uuidString,
              receipt.sourceRefs.contains("routing_decision:\(candidateID.uuidString)"),
              let afterJSON = receipt.afterJSON,
              let after = DatabaseHelpers.decodeJSON([String: String].self, from: afterJSON),
              after["requestFingerprint"] == requestFingerprint,
              let resultingIDText = after["routingDecisionID"],
              let resultingID = UUID(uuidString: resultingIDText) else {
            return nil
        }
        let latest = try latestDecision(for: itemID)
        guard latest.id == resultingID,
              latest.reviewState == after["reviewState"],
              Self.preciseVersion(latest.createdAt) == after["resultingVersion"],
              Self.destinationFingerprint(latest.target) == after["targetFingerprint"] else {
            return nil
        }
        return CiderRoutingReviewMutationResult(
            item: try itemSummary(for: itemID),
            decision: latest,
            receiptID: receipt.id,
            changed: false,
            truthBoundary: after["truthBoundary"] ?? "reviewable_candidate_not_truth"
        )
    }

    private func syntacticallyNormalizedDestination(
        _ target: CiderRoutingDecisionTarget
    ) throws -> CiderRoutingDecisionTarget {
        let kind = target.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = target.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard ["inbox", "folder", "space"].contains(kind),
              !name.isEmpty,
              !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw CiderRoutingReviewActionError.invalidDestination
        }
        return CiderRoutingDecisionTarget(
            kind: kind,
            name: name,
            relativePath: components.joined(separator: "/"),
            folderID: target.folderID,
            spaceID: target.spaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func validatedDestination(
        _ requested: CiderRoutingDecisionTarget,
        item: CiderRoutingItemSummary,
        candidate: CiderRoutingDecision,
        action: CiderReviewAction,
        database db: CiderDatabase
    ) throws -> CiderRoutingDecisionTarget {
        if action == .approve || action == .defer {
            let candidateTarget = try syntacticallyNormalizedDestination(candidate.target)
            guard Self.destinationFingerprint(candidateTarget) == Self.destinationFingerprint(requested) else {
                throw CiderRoutingReviewActionError.unauthorizedDestination
            }
        }
        switch requested.kind {
        case "inbox":
            guard requested.folderID == nil,
                  requested.spaceID?.isEmpty != false,
                  requested.relativePath == "Inbox" || requested.relativePath.hasPrefix("Inbox/") else {
                throw CiderRoutingReviewActionError.invalidDestination
            }
            if action == .correct, item.type == "bookmark", requested.relativePath != "Inbox/Bookmarks" {
                throw CiderRoutingReviewActionError.unauthorizedDestination
            }
            return requested
        case "folder":
            guard requested.spaceID?.isEmpty != false else {
                throw CiderRoutingReviewActionError.invalidDestination
            }
            guard let folderID = requested.folderID else {
                let stmt = try db.prepare("SELECT relative_path FROM folders ORDER BY relative_path;")
                var matches = 0
                while try stmt.step() {
                    let path = stmt.string(at: 0)
                    let leaf = path.split(separator: "/").last.map(String.init) ?? path
                    if path.localizedCaseInsensitiveCompare(requested.relativePath) == .orderedSame
                        || leaf.localizedCaseInsensitiveCompare(requested.name) == .orderedSame {
                        matches += 1
                    }
                }
                if matches > 1 {
                    throw CiderRoutingReviewActionError.ambiguousDestination
                }
                if matches == 1 {
                    throw CiderRoutingReviewActionError.unauthorizedDestination
                }
                throw CiderRoutingReviewActionError.unresolvedDestination
            }
            let stmt = try db.prepare("SELECT relative_path FROM folders WHERE id = ? LIMIT 2;")
            stmt.bind(folderID.uuidString, at: 1)
            guard try stmt.step() else {
                throw CiderRoutingReviewActionError.unresolvedDestination
            }
            let canonicalPath = stmt.string(at: 0)
            guard canonicalPath == requested.relativePath else {
                throw CiderRoutingReviewActionError.unauthorizedDestination
            }
            return CiderRoutingDecisionTarget(
                kind: "folder",
                name: canonicalPath.split(separator: "/").last.map(String.init) ?? requested.name,
                relativePath: canonicalPath,
                folderID: folderID,
                spaceID: nil
            )
        case "space":
            guard action != .correct,
                  requested.folderID == nil,
                  requested.spaceID?.isEmpty == false else {
                throw CiderRoutingReviewActionError.unauthorizedDestination
            }
            return requested
        default:
            throw CiderRoutingReviewActionError.invalidDestination
        }
    }

    private func routingAuditState(_ decision: CiderRoutingDecision) -> [String: String] {
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

    private static func auditSource(for actor: String) -> MutationAuditSource? {
        switch actor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "agent": return .agent
        case "cli", "cider-cli": return .cli
        default: return nil
        }
    }

    private static func reviewRequestFingerprint(
        candidateID: UUID,
        itemID: UUID,
        expectedReviewState: String,
        expectedCreatedAt: Date,
        action: CiderReviewAction,
        actor: String,
        destination: CiderRoutingDecisionTarget,
        reason: String
    ) -> String {
        let values = [
            "routing_decision:\(candidateID.uuidString.lowercased())",
            itemID.uuidString.lowercased(),
            action.rawValue,
            actor.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedReviewState,
            preciseVersion(expectedCreatedAt),
            destination.kind,
            destination.name,
            destination.relativePath,
            destination.folderID?.uuidString.lowercased() ?? "",
            destination.spaceID ?? "",
            reason,
        ]
        let framed = values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(framed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func destinationFingerprint(_ target: CiderRoutingDecisionTarget) -> String {
        let values = [
            target.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            target.name.trimmingCharacters(in: .whitespacesAndNewlines),
            target.relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
            target.folderID?.uuidString.lowercased() ?? "",
            target.spaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        ]
        let framed = values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(framed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func preciseVersion(_ date: Date) -> String {
        String(format: "%016llx", date.timeIntervalSinceReferenceDate.bitPattern)
    }

    private static func deterministicDecisionID(requestFingerprint: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("routing-decision:\(requestFingerprint)".utf8)))
        var uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        uuid.6 = (uuid.6 & 0x0F) | 0x50
        uuid.8 = (uuid.8 & 0x3F) | 0x80
        return UUID(uuid: uuid)
    }

    private func libraryEntityType(for itemType: String) throws -> LibraryEntityType {
        if itemType == "event" { return .dateCard }
        guard let type = LibraryEntityType(rawValue: itemType) else {
            throw CiderRoutingDecisionError.unsupportedItemType(itemType)
        }
        return type
    }

    private func itemSummary(for itemID: UUID) throws -> CiderRoutingItemSummary {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let stmt = try db.prepare("""
            SELECT id, type, title, relative_path, folder_id, updated_at
            FROM items
            WHERE id = ?;
            """)
        stmt.bind(itemID.uuidString, at: 1)
        guard try stmt.step(),
              let id = UUID(uuidString: stmt.string(at: 0)) else {
            throw CiderRoutingDecisionError.itemNotFound(itemID)
        }
        return CiderRoutingItemSummary(
            id: id,
            type: stmt.string(at: 1),
            title: stmt.string(at: 2),
            relativePath: stmt.optionalString(at: 3),
            folderID: stmt.optionalString(at: 4).flatMap(UUID.init(uuidString:)),
            updatedAt: stmt.optionalDouble(at: 5).map(DatabaseHelpers.decodeDate)
        )
    }

    private func targetFromCurrentItem(_ item: CiderRoutingItemSummary) -> CiderRoutingDecisionTarget {
        if let folderID = item.folderID,
           let folder = VaultFolderService.shared.folder(for: folderID) {
            return CiderRoutingDecisionTarget(
                kind: "folder",
                name: folder.name,
                relativePath: folder.relativePath,
                folderID: folder.id
            )
        }
        if let relativePath = item.relativePath,
           relativePath.hasPrefix("Inbox/") {
            let parts = relativePath.split(separator: "/").prefix(2).map(String.init)
            let inboxPath = parts.count == 2 ? parts.joined(separator: "/") : "Inbox"
            return CiderRoutingDecisionTarget(
                kind: "inbox",
                name: inboxPath,
                relativePath: inboxPath,
                folderID: nil
            )
        }
        return CiderRoutingDecisionTarget(
            kind: "inbox",
            name: "Inbox",
            relativePath: "Inbox",
            folderID: nil
        )
    }

    private func nextSafeAction(for decision: CiderRoutingDecision?) -> String {
        guard let decision else { return "route_or_review" }
        switch decision.reviewState {
        case "needs_review":
            return "approve_or_correct_route"
        default:
            return "inspect_item"
        }
    }
}
