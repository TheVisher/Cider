import Foundation

struct CiderSpaceCaptureDashboard: Equatable {
    var command: String
    var generatedAt: Date
    var spaceID: String
    var spaceName: String
    var rootRelativePath: String
    var recentRouted: [CiderSpaceCaptureDashboardItem]
    var needsReview: [CiderSpaceCaptureDashboardItem]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "command": command,
            "generatedAt": formatter.string(from: generatedAt),
            "space": [
                "id": spaceID,
                "name": spaceName,
                "rootRelativePath": rootRelativePath,
            ],
            "recentRouted": recentRouted.map { $0.toDictionary() },
            "needsReview": needsReview.map { $0.toDictionary() },
            "counts": [
                "recentRouted": recentRouted.count,
                "needsReview": needsReview.count,
            ],
        ]
    }
}

struct CiderSpaceCaptureDashboardItem: Identifiable, Equatable {
    var id: String
    var itemID: UUID
    var itemType: String
    var title: String
    var sourceURL: String?
    var sourceTitle: String?
    var itemRelativePath: String?
    var routingDecisionID: UUID
    var target: CiderRoutingDecisionTarget
    var confidence: Double
    var reason: String
    var reviewState: String
    var routedAt: Date
    var safeActions: [String]
    var membershipAuthority: String?

    var routingExplanationCommand: String {
        "cider-cli routing explain \(itemID.uuidString.prefix(8)) --json"
    }

    var itemContextCommands: [String] {
        [
            "cider-cli item get \(itemType) \(itemID.uuidString) --json",
            "cider-cli item context \(itemType) \(itemID.uuidString) --json",
            "cider-cli item related \(itemType) \(itemID.uuidString) --json",
        ]
    }

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "id": id,
            "itemID": itemID.uuidString,
            "itemType": itemType,
            "title": title,
            "routingDecisionID": routingDecisionID.uuidString,
            "target": target.toDictionary(),
            "confidence": confidence,
            "reason": reason,
            "reviewState": reviewState,
            "routedAt": formatter.string(from: routedAt),
            "safeActions": safeActions,
            "routingExplanationCommand": routingExplanationCommand,
            "itemContextCommands": itemContextCommands,
        ]
        if let sourceURL {
            dictionary["sourceURL"] = sourceURL
        }
        if let sourceTitle {
            dictionary["sourceTitle"] = sourceTitle
        }
        if let itemRelativePath {
            dictionary["itemRelativePath"] = itemRelativePath
        }
        if let membershipAuthority {
            dictionary["membershipAuthority"] = membershipAuthority
        }
        return dictionary
    }
}

@MainActor
final class CiderSpaceCaptureDashboardService {
    private let database: CiderDatabase?

    private var resolvedDatabase: CiderDatabase? {
        database ?? (CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil)
    }

    init(database: CiderDatabase? = nil) {
        self.database = database
    }

    func dashboard(
        for space: CiderSpace,
        recentLimit: Int = 10,
        reviewLimit: Int = 10,
        now: Date = Date()
    ) throws -> CiderSpaceCaptureDashboard {
        guard let db = resolvedDatabase else { throw CiderRoutingDecisionError.databaseUnavailable }

        var rows: [DashboardRow] = []
        for row in try latestRows(in: db) {
            guard let authority = try membershipAuthority(for: row, space: space, in: db) else {
                continue
            }
            var scopedRow = row
            scopedRow.membershipAuthority = authority
            rows.append(scopedRow)
        }

        let recent = rows
            .filter { isAcceptedState($0.reviewState) }
            .sorted(by: routeSort)
            .prefix(max(0, recentLimit))
            .map { dashboardItem($0) }

        let review = rows
            .filter { isReviewState($0.reviewState) }
            .sorted(by: routeSort)
            .prefix(max(0, reviewLimit))
            .map { dashboardItem($0) }

        return CiderSpaceCaptureDashboard(
            command: "space.captures",
            generatedAt: now,
            spaceID: space.id,
            spaceName: space.name,
            rootRelativePath: space.rootRelativePath,
            recentRouted: Array(recent),
            needsReview: Array(review)
        )
    }

    private struct DashboardRow {
        var decisionID: UUID
        var itemID: UUID
        var itemType: String
        var target: CiderRoutingDecisionTarget
        var confidence: Double
        var reason: String
        var reviewState: String
        var routedAt: Date
        var title: String
        var itemRelativePath: String?
        var sourceURL: String?
        var membershipAuthority: String?
    }

    private func latestRows(in db: CiderDatabase) throws -> [DashboardRow] {
        let stmt = try db.prepare("""
            SELECT rd.id, rd.item_id, rd.item_type, rd.target_kind, rd.target_name,
                   rd.target_relative_path, rd.target_folder_id, rd.target_space_id, rd.confidence,
                   rd.reason, rd.review_state, rd.created_at,
                   i.title, i.relative_path, b.url
            FROM routing_decisions rd
            JOIN items i ON i.id = rd.item_id
            LEFT JOIN bookmarks b ON b.item_id = rd.item_id
            ORDER BY rd.item_id ASC, rd.created_at DESC, rd.id DESC;
            """)

        var rows: [DashboardRow] = []
        var seen = Set<UUID>()
        while try stmt.step() {
            guard let decisionID = UUID(uuidString: stmt.string(at: 0)),
                  let itemID = UUID(uuidString: stmt.string(at: 1)),
                  !seen.contains(itemID) else {
                continue
            }
            seen.insert(itemID)
            rows.append(DashboardRow(
                decisionID: decisionID,
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
                reviewState: stmt.string(at: 10),
                routedAt: DatabaseHelpers.decodeDate(stmt.double(at: 11)),
                title: stmt.string(at: 12),
                itemRelativePath: stmt.optionalString(at: 13),
                sourceURL: stmt.optionalString(at: 14)
            ))
        }
        return rows
    }

    private func membershipAuthority(
        for row: DashboardRow,
        space: CiderSpace,
        in db: CiderDatabase
    ) throws -> String? {
        let membershipSpaceIDs = try explicitMembershipSpaceIDs(for: row, in: db)
        if !membershipSpaceIDs.isEmpty {
            return membershipSpaceIDs.contains(space.id) ? "space_memberships" : nil
        }

        let relationSpaceIDs = try ownerRelationSpaceIDs(for: row, in: db)
        if !relationSpaceIDs.isEmpty {
            return relationSpaceIDs.contains(space.id) ? "owner_relations" : nil
        }

        if row.target.spaceID == space.id {
            return "routing_target_space"
        }
        if path(row.target.relativePath, isIn: space.rootRelativePath) {
            return "target_path_fallback"
        }
        if row.itemRelativePath.map({ path($0, isIn: space.rootRelativePath) }) == true {
            return "item_path_fallback"
        }
        return nil
    }

    private func explicitMembershipSpaceIDs(for row: DashboardRow, in db: CiderDatabase) throws -> Set<String> {
        let stmt = try db.prepare("""
            SELECT space_id
            FROM space_memberships
            WHERE item_id = ? AND item_type = ?;
            """)
        stmt.bind(row.itemID.uuidString, at: 1)
            .bind(row.itemType, at: 2)

        var spaceIDs = Set<String>()
        while try stmt.step() {
            spaceIDs.insert(stmt.string(at: 0))
        }
        return spaceIDs
    }

    private func ownerRelationSpaceIDs(for row: DashboardRow, in db: CiderDatabase) throws -> Set<String> {
        let stmt = try db.prepare("""
            SELECT target_owner_id
            FROM owner_relations
            WHERE source_owner_type = ?
              AND source_owner_id = ?
              AND target_owner_type = 'space'
              AND relation_type = 'belongs_to_space';
            """)
        stmt.bind(row.itemType, at: 1)
            .bind(row.itemID.uuidString, at: 2)

        var spaceIDs = Set<String>()
        while try stmt.step() {
            spaceIDs.insert(stmt.string(at: 0))
        }
        return spaceIDs
    }

    private func path(_ path: String, isIn root: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let normalizedRoot = root.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private func isAcceptedState(_ state: String) -> Bool {
        state == "accepted" || state == "corrected"
    }

    private func isReviewState(_ state: String) -> Bool {
        state == "needs_review" || state == "suggested" || state == "deferred"
    }

    private func routeSort(_ lhs: DashboardRow, _ rhs: DashboardRow) -> Bool {
        if lhs.routedAt != rhs.routedAt { return lhs.routedAt > rhs.routedAt }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func dashboardItem(_ row: DashboardRow) -> CiderSpaceCaptureDashboardItem {
        CiderSpaceCaptureDashboardItem(
            id: "space-capture-\(row.decisionID.uuidString)",
            itemID: row.itemID,
            itemType: row.itemType,
            title: row.title,
            sourceURL: row.sourceURL,
            sourceTitle: row.title,
            itemRelativePath: row.itemRelativePath,
            routingDecisionID: row.decisionID,
            target: row.target,
            confidence: row.confidence,
            reason: row.reason,
            reviewState: row.reviewState,
            routedAt: row.routedAt,
            safeActions: safeActions(for: row.reviewState, itemType: row.itemType),
            membershipAuthority: row.membershipAuthority
        )
    }

    private func safeActions(for reviewState: String, itemType: String) -> [String] {
        if isReviewState(reviewState) {
            return [
                "routing explain",
                "review approve",
                itemType == "bookmark" ? "review correct" : "item move",
                "review defer",
            ]
        }
        return ["routing explain"]
    }
}
