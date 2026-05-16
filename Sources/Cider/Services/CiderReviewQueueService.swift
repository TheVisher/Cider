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

struct CiderReviewQueueItem: Identifiable, Equatable {
    var id: String
    var kind: String
    var source: String
    var itemID: UUID
    var itemType: String
    var title: String
    var relativePath: String?
    var reason: String
    var suggestedAction: String
    var reviewState: String
    var confidence: Double?
    var routingDecisionID: UUID?
    var target: CiderRoutingDecisionTarget?
    var createdAt: Date
    var safeActions: [String]

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
        if let routingDecisionID {
            dictionary["routingDecisionID"] = routingDecisionID.uuidString
        }
        if let target {
            dictionary["target"] = target.toDictionary()
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

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(
        database: CiderDatabase? = nil,
        routingDecisionService: CiderRoutingDecisionService? = nil,
        enrichmentScheduler: ((UUID) -> Void)? = nil
    ) {
        self.database = database
        self.routingDecisionService = routingDecisionService ?? CiderRoutingDecisionService(database: database)
        self.enrichmentScheduler = enrichmentScheduler ?? { bookmarkID in
            VaultBookmarkService.shared.refetchMetadata(for: bookmarkID)
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
            reviewItems.append(routingReviewItem(decision: decision, item: item))
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
                reviewItems.append(inboxReviewItem(item: item, now: now))
                seenItemIDs.insert(item.id)
            }
        }

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
            entry.action == "review.enrich.batch.schedule"
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
            SELECT id, type, title, relative_path, folder_id
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
                folderID: stmt.optionalString(at: 4).flatMap(UUID.init(uuidString:))
            )
        }
        return items
    }

    private struct BookmarkReviewDetails {
        var url: String
        var enrichmentStatus: String?
        var lastEnrichedAt: Date?
    }

    private func bookmarkDetails(in db: CiderDatabase) throws -> [UUID: BookmarkReviewDetails] {
        let stmt = try db.prepare("""
            SELECT item_id, url, enrichment_status, last_enriched_at
            FROM bookmarks;
            """)
        var details: [UUID: BookmarkReviewDetails] = [:]
        while try stmt.step() {
            guard let itemID = UUID(uuidString: stmt.string(at: 0)) else { continue }
            details[itemID] = BookmarkReviewDetails(
                url: stmt.string(at: 1),
                enrichmentStatus: stmt.optionalString(at: 2),
                lastEnrichedAt: stmt.optionalDouble(at: 3).map(DatabaseHelpers.decodeDate)
            )
        }
        return details
    }

    private func routingReviewItem(
        decision: CiderRoutingDecision,
        item: CiderRoutingItemSummary
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
            suggestedAction: decision.reviewState == "deferred" ? "Revisit route" : "Approve or correct route",
            reviewState: decision.reviewState,
            confidence: decision.confidence,
            routingDecisionID: decision.id,
            target: decision.target,
            createdAt: decision.createdAt,
            safeActions: decision.reviewState == "deferred"
                ? ["approve", "correct"]
                : ["approve", "correct", "defer"]
        )
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
            suggestedAction: failed ? "Enrichment failed" : "Needs enrichment",
            reviewState: failed ? "needs_review" : "pending",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["enrich", "correct", "defer"]
        )
    }

    private func inboxReviewItem(
        item: CiderRoutingItemSummary,
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
            suggestedAction: "Route to folder",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["correct", "defer"]
        )
    }

    private func sortRank(_ item: CiderReviewQueueItem) -> Int {
        switch item.kind {
        case "low_confidence_routing":
            return 0
        case "enrichment":
            return 1
        case "inbox_backlog":
            return 2
        case "deferred_routing":
            return 3
        default:
            return 4
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
        case "inbox_backlog":
            return "manual_routing_required"
        default:
            if item.itemType != "bookmark" {
                return "unsupported_item_type"
            }
            return "not_enrichment_candidate"
        }
    }

    private func primarySafeAction(for item: CiderReviewQueueItem) -> String {
        for action in ["enrich", "approve", "correct", "defer"] where item.safeActions.contains(action) {
            return action
        }
        return item.safeActions.first ?? "none"
    }

    private func groupSortRank(_ group: CiderReviewQueueGroup) -> Int {
        switch group.kind {
        case "low_confidence_routing":
            return 0
        case "enrichment":
            return group.reviewState == "needs_review" ? 1 : 2
        case "inbox_backlog":
            return 3
        case "deferred_routing":
            return 4
        default:
            return 5
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
            let samples = sortedEntries.prefix(cappedSampleLimit).map { entry in
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
                resultState: "scheduled",
                candidateCount: candidateCount,
                scheduledCount: entries.count,
                excludedCount: excludedCount,
                failedCount: max(0, candidateCount - entries.count),
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
