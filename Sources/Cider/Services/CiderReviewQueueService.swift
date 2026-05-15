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

@MainActor
final class CiderReviewQueueService {
    private let database: CiderDatabase?
    private let routingDecisionService: CiderRoutingDecisionService

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(
        database: CiderDatabase? = nil,
        routingDecisionService: CiderRoutingDecisionService? = nil
    ) {
        self.database = database
        self.routingDecisionService = routingDecisionService ?? CiderRoutingDecisionService(database: database)
    }

    func list(
        limit: Int = 50,
        includeDeferred: Bool = false,
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

        let sorted = reviewItems.sorted { lhs, rhs in
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

    @discardableResult
    func approve(itemID: UUID, actor: String = "user") throws -> CiderRoutingExplanation {
        try routingDecisionService.approve(itemID: itemID, actor: actor)
    }

    @discardableResult
    func correctBookmark(
        itemID: UUID,
        target: CiderRoutingDecisionTarget,
        reason: String,
        actor: String = "user",
        bookmarkService: VaultBookmarkService
    ) throws -> CiderRoutingExplanation {
        try routingDecisionService.correctBookmark(
            itemID: itemID,
            target: target,
            reason: reason,
            actor: actor,
            bookmarkService: bookmarkService
        )
    }

    @discardableResult
    func deferReview(itemID: UUID, reason: String, actor: String = "user") throws -> CiderRoutingExplanation {
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
        return try routingDecisionService.explain(itemID: itemID)
    }

    func resolveItemID(ref: String) throws -> UUID {
        try routingDecisionService.resolveItemID(ref: ref)
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
            suggestedAction: failed ? "Retry enrichment or correct route" : "Enrich and route",
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
}
