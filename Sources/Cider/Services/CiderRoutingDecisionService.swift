import Foundation

struct CiderRoutingDecisionTarget: Equatable {
    var kind: String
    var name: String
    var relativePath: String
    var folderID: UUID?

    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "kind": kind,
            "name": name,
            "relativePath": relativePath,
        ]
        if let folderID {
            dictionary["folderID"] = folderID.uuidString
        }
        return dictionary
    }
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
        var dictionary: [String: Any] = [
            "command": command,
            "item": item.toDictionary(),
            "history": history.map { $0.toDictionary() },
            "reviewNeeded": reviewNeeded,
            "nextSafeAction": nextSafeAction,
        ]
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

@MainActor
final class CiderRoutingDecisionService {
    private let database: CiderDatabase?

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(database: CiderDatabase? = nil) {
        self.database = database
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
        createdAt: Date = Date()
    ) throws -> CiderRoutingDecision {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }

        let decision = CiderRoutingDecision(
            id: UUID(),
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
                target_folder_id, confidence, reason, actor, source, review_state,
                created_at, supersedes_decision_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(decision.id.uuidString, at: 1)
            .bind(decision.itemID.uuidString, at: 2)
            .bind(decision.itemType, at: 3)
            .bind(decision.target.kind, at: 4)
            .bind(decision.target.name, at: 5)
            .bind(decision.target.relativePath, at: 6)
            .bind(decision.target.folderID?.uuidString, at: 7)
            .bind(decision.confidence, at: 8)
            .bind(decision.reason, at: 9)
            .bind(decision.actor, at: 10)
            .bind(decision.source, at: 11)
            .bind(decision.reviewState, at: 12)
            .bind(DatabaseHelpers.encode(decision.createdAt), at: 13)
            .bind(decision.supersedesDecisionID?.uuidString, at: 14)
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
        return try explain(itemID: itemID)
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

    private func decisions(for itemID: UUID) throws -> [CiderRoutingDecision] {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }
        let stmt = try db.prepare("""
            SELECT id, item_id, item_type, target_kind, target_name, target_relative_path,
                   target_folder_id, confidence, reason, actor, source, review_state,
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
                targetID: decision.target.folderID?.uuidString,
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
