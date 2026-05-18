import Foundation

struct CiderItemSummary: Identifiable, Codable, Equatable {
    var id: UUID
    var type: LibraryEntityType
    var title: String
    var relativePath: String?
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct CiderItemChunk: Identifiable, Codable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var itemID: UUID?
    var source: String
    var title: String
    var body: String
    var chunkIndex: Int
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
}

struct CiderItemContextBundle: Equatable {
    var item: CiderItemSummary
    var owner: SecondBrainOwnerRef
    var sections: [SecondBrainSection]
    var chunks: [CiderItemChunk]
    var related: [ItemLinkSummary]
    var spaceMemberships: [CiderSpaceMembership]
    var routingDecisions: [SecondBrainRoutingDecision]
    var agentActions: [SecondBrainAgentAction]
}

struct CiderItemAgentContextLimits: Equatable {
    var maxSections: Int = 3
    var maxChunks: Int = 3
    var maxRelated: Int = 5
    var maxHistory: Int = 5
    var maxBodyCharacters: Int = 600

    static let `default` = CiderItemAgentContextLimits()
}

struct CiderItemAgentContextBlock: Identifiable, Equatable {
    var id: String
    var kind: String
    var title: String
    var body: String
    var source: String
}

struct CiderItemAgentReviewState: Equatable {
    var status: String
    var reason: String
    var confidence: Double?
    var targetType: String
    var targetPath: String?
    var source: String
    var createdAt: Date
}

struct CiderItemAgentContextHistoryEntry: Identifiable, Equatable {
    var id: String
    var kind: String
    var summary: String
    var source: String
    var status: String
    var createdAt: Date
}

struct CiderItemAgentContextPacket: Equatable {
    var item: CiderItemSummary
    var owner: SecondBrainOwnerRef
    var summary: String
    var provenance: [String]
    var spaceMemberships: [CiderSpaceMembership]
    var contentBlocks: [CiderItemAgentContextBlock]
    var related: [ItemLinkSummary]
    var review: CiderItemAgentReviewState?
    var surfacing: CiderSurfacingExplanation
    var recentHistory: [CiderItemAgentContextHistoryEntry]
    var safeCommands: [String]
    var limits: CiderItemAgentContextLimits
}

enum CiderItemSearchResultKind: String, Codable {
    case item
    case chunk
}

struct CiderItemSearchResult: Identifiable, Codable, Equatable {
    var id: String
    var kind: CiderItemSearchResultKind
    var owner: SecondBrainOwnerRef
    var item: CiderItemSummary?
    var title: String
    var snippet: String
    var rank: Double
}

enum CiderItemContextError: Error, LocalizedError {
    case itemNotFound(UUID)
    case unsupportedItemType(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "No item found for \(id.uuidString)."
        case .unsupportedItemType(let type):
            return "Unsupported item type '\(type)'."
        }
    }
}

@MainActor
final class CiderItemContextService {
    private let database: CiderDatabase
    private let linkService: ItemLinkService
    private let secondBrainStore: SecondBrainStore
    private let spaceMembershipStore: CiderSpaceMembershipStore
    private let todoProvider: () -> [TodoCard]
    private let dateCardProvider: () -> [DateCard]
    private let nowProvider: () -> Date

    init(
        database: CiderDatabase = .shared,
        linkService: ItemLinkService? = nil,
        secondBrainStore: SecondBrainStore? = nil,
        spaceMembershipStore: CiderSpaceMembershipStore? = nil,
        todoProvider: @escaping () -> [TodoCard] = { TodoCardStorage.shared.todoCards },
        dateCardProvider: @escaping () -> [DateCard] = { DateCardStorage.shared.dateCards },
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.database = database
        self.linkService = linkService ?? ItemLinkService(database: database)
        self.secondBrainStore = secondBrainStore ?? SecondBrainStore(database: database)
        self.spaceMembershipStore = spaceMembershipStore ?? CiderSpaceMembershipStore(database: database)
        self.todoProvider = todoProvider
        self.dateCardProvider = dateCardProvider
        self.nowProvider = nowProvider
    }

    func context(for ref: LibraryEntityRef) throws -> CiderItemContextBundle {
        let item = try itemSummary(id: ref.entityID)
        let owner = owner(for: item)
        return CiderItemContextBundle(
            item: item,
            owner: owner,
            sections: try secondBrainStore.sections(for: owner),
            chunks: try chunks(for: owner),
            related: linkService.summaries(for: try linkService.relatedRefs(for: ref)),
            spaceMemberships: try spaceMembershipStore.memberships(for: ref),
            routingDecisions: try secondBrainStore.routingDecisions(for: owner),
            agentActions: try secondBrainStore.agentActions(for: owner)
        )
    }

    func agentContext(
        for ref: LibraryEntityRef,
        limits: CiderItemAgentContextLimits = .default
    ) throws -> CiderItemAgentContextPacket {
        let bundle = try context(for: ref)
        let normalizedLimits = normalize(limits)
        return CiderItemAgentContextPacket(
            item: bundle.item,
            owner: bundle.owner,
            summary: clipped(summary(for: bundle), limit: normalizedLimits.maxBodyCharacters),
            provenance: provenance(for: bundle),
            spaceMemberships: bundle.spaceMemberships,
            contentBlocks: contentBlocks(for: bundle, limits: normalizedLimits),
            related: Array(bundle.related.prefix(normalizedLimits.maxRelated)),
            review: reviewState(for: bundle),
            surfacing: surfacingExplanation(for: bundle),
            recentHistory: recentHistory(for: bundle, limit: normalizedLimits.maxHistory),
            safeCommands: safeCommands(for: bundle),
            limits: normalizedLimits
        )
    }

    func related(for ref: LibraryEntityRef) throws -> [ItemLinkSummary] {
        linkService.summaries(for: try linkService.relatedRefs(for: ref))
    }

    func search(_ query: String, limit: Int = 20) throws -> [CiderItemSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results = try searchItems(trimmed, limit: limit)
        let remainingLimit = max(1, limit - results.count)
        let chunkMatches = try secondBrainStore.searchChunks(query: trimmed, limit: remainingLimit)
        for match in chunkMatches {
            let item = try? itemSummary(owner: match.owner)
            results.append(
                CiderItemSearchResult(
                    id: "chunk-\(match.id)",
                    kind: .chunk,
                    owner: match.owner,
                    item: item,
                    title: match.title,
                    snippet: match.snippet,
                    rank: match.rank
                )
            )
        }

        return Array(results.prefix(max(1, limit)))
    }

    private func searchItems(_ query: String, limit: Int) throws -> [CiderItemSearchResult] {
        let stmt = try database.prepare("""
            SELECT id, type, title, created_at, updated_at, folder_id, relative_path
            FROM items
            WHERE title LIKE ? ESCAPE '\\'
               OR IFNULL(relative_path, '') LIKE ? ESCAPE '\\'
            ORDER BY
                CASE WHEN title LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                updated_at DESC,
                title COLLATE NOCASE ASC
            LIMIT ?;
            """)
        let containsPattern = "%\(escapedLikePattern(query))%"
        let prefixPattern = "\(escapedLikePattern(query))%"
        stmt.bind(containsPattern, at: 1)
            .bind(containsPattern, at: 2)
            .bind(prefixPattern, at: 3)
            .bind(max(1, limit), at: 4)

        var results: [CiderItemSearchResult] = []
        while try stmt.step() {
            let item = try itemSummary(from: stmt)
            let owner = owner(for: item)
            results.append(
                CiderItemSearchResult(
                    id: "item-\(item.id.uuidString)",
                    kind: .item,
                    owner: owner,
                    item: item,
                    title: item.title,
                    snippet: item.relativePath ?? item.type.rawValue,
                    rank: 0
                )
            )
        }
        return results
    }

    private func chunks(for owner: SecondBrainOwnerRef) throws -> [CiderItemChunk] {
        let stmt = try database.prepare("""
            SELECT id, item_id, source, title, body, chunk_index, metadata, created_at, updated_at
            FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?
            ORDER BY chunk_index ASC, title COLLATE NOCASE ASC;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)

        var chunks: [CiderItemChunk] = []
        while try stmt.step() {
            chunks.append(
                CiderItemChunk(
                    id: stmt.string(at: 0),
                    owner: owner,
                    itemID: stmt.optionalString(at: 1).flatMap(UUID.init(uuidString:)),
                    source: stmt.string(at: 2),
                    title: stmt.string(at: 3),
                    body: stmt.string(at: 4),
                    chunkIndex: stmt.int(at: 5),
                    metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 6)) ?? [:],
                    createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 7)),
                    updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 8))
                )
            )
        }
        return chunks
    }

    private func summary(for bundle: CiderItemContextBundle) -> String {
        if let section = bundle.sections.first(where: { ["summary", "overview", "current_state"].contains($0.sectionKey) }),
           !section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return section.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let section = bundle.sections.first(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return section.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let chunk = bundle.chunks.first(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return chunk.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return bundle.item.title
    }

    private func provenance(for bundle: CiderItemContextBundle) -> [String] {
        var values: [String] = ["item:\(bundle.item.type.rawValue)"]
        if let relativePath = bundle.item.relativePath {
            values.append("path:\(relativePath)")
        }
        values += bundle.sections.map { "section:\($0.source)" }
        values += bundle.chunks.map { "chunk:\($0.source)" }
        values += bundle.spaceMemberships.map { "space:\($0.spaceName)" }
        values += bundle.routingDecisions.map { "routing:\($0.source)" }
        values += bundle.agentActions.map { "agent:\($0.source)" }
        if !bundle.related.isEmpty {
            values.append("related:\(bundle.related.count)")
        }
        return orderedUnique(values)
    }

    private func contentBlocks(
        for bundle: CiderItemContextBundle,
        limits: CiderItemAgentContextLimits
    ) -> [CiderItemAgentContextBlock] {
        let sectionBlocks = bundle.sections
            .prefix(limits.maxSections)
            .map { section in
                CiderItemAgentContextBlock(
                    id: "section-\(section.id)",
                    kind: "section",
                    title: section.title,
                    body: clipped(section.body, limit: limits.maxBodyCharacters),
                    source: section.source
                )
            }
        let chunkBlocks = bundle.chunks
            .prefix(limits.maxChunks)
            .map { chunk in
                CiderItemAgentContextBlock(
                    id: "chunk-\(chunk.id)",
                    kind: "chunk",
                    title: chunk.title,
                    body: clipped(chunk.body, limit: limits.maxBodyCharacters),
                    source: chunk.source
                )
            }
        return sectionBlocks + chunkBlocks
    }

    private func reviewState(for bundle: CiderItemContextBundle) -> CiderItemAgentReviewState? {
        guard let decision = bundle.routingDecisions.sorted(by: { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }).first else {
            return nil
        }
        return CiderItemAgentReviewState(
            status: decision.status,
            reason: decision.reason,
            confidence: decision.confidence,
            targetType: decision.targetType,
            targetPath: decision.targetPath,
            source: decision.source,
            createdAt: decision.createdAt
        )
    }

    private func surfacingExplanation(for bundle: CiderItemContextBundle) -> CiderSurfacingExplanation {
        if let review = reviewState(for: bundle) {
            return CiderSurfacingExplanation(
                reason: review.reason,
                urgency: review.status == "needs_review" ? "review" : "normal",
                sourceSignal: "item_context",
                reviewState: review.status,
                suggestedAction: review.status == "needs_review" ? "Approve or correct route" : "Open",
                actionURLString: nil
            )
        }
        if let reminderSurfacing = reminderSurfacingExplanation(for: bundle.item) {
            return reminderSurfacing
        }
        return CiderSurfacingExplanation(
            reason: summary(for: bundle),
            urgency: "normal",
            sourceSignal: "item_context",
            reviewState: "ok",
            suggestedAction: "Open",
            actionURLString: nil
        )
    }

    private func reminderSurfacingExplanation(for item: CiderItemSummary) -> CiderSurfacingExplanation? {
        let itemType: CiderReminderRelevanceItem.ItemType
        switch item.type {
        case .todo:
            itemType = .todo
        case .dateCard:
            itemType = .dateCard
        default:
            return nil
        }

        return CiderReminderRelevanceService.relevance(
            todos: todoProvider(),
            dateCards: dateCardProvider(),
            now: nowProvider()
        )
        .first { $0.id == item.id && $0.itemType == itemType }?
        .surfacing
    }

    private func recentHistory(
        for bundle: CiderItemContextBundle,
        limit: Int
    ) -> [CiderItemAgentContextHistoryEntry] {
        let routing = bundle.routingDecisions.map { decision in
            CiderItemAgentContextHistoryEntry(
                id: "routing-\(decision.id)",
                kind: "routing",
                summary: decision.reason,
                source: decision.source,
                status: decision.status,
                createdAt: decision.createdAt
            )
        }
        let actions = bundle.agentActions.map { action in
            CiderItemAgentContextHistoryEntry(
                id: "agent-\(action.id)",
                kind: "agent_action",
                summary: action.summary,
                source: action.source,
                status: action.status,
                createdAt: action.createdAt
            )
        }
        return Array((routing + actions)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
            .prefix(limit))
    }

    private func safeCommands(for bundle: CiderItemContextBundle) -> [String] {
        let type = bundle.item.type.rawValue
        let id = bundle.item.id.uuidString
        var commands = [
            "cider-cli item get \(type) \(id) --json",
            "cider-cli item context \(type) \(id) --json",
            "cider-cli item related \(type) \(id) --json",
            "cider-cli item search \"\(escapedCommandArgument(bundle.item.title))\" --limit 5 --json",
        ]
        if !bundle.routingDecisions.isEmpty {
            commands.append("cider-cli routing explain \(id) --json")
        }
        return commands
    }

    private func normalize(_ limits: CiderItemAgentContextLimits) -> CiderItemAgentContextLimits {
        CiderItemAgentContextLimits(
            maxSections: max(0, limits.maxSections),
            maxChunks: max(0, limits.maxChunks),
            maxRelated: max(0, limits.maxRelated),
            maxHistory: max(0, limits.maxHistory),
            maxBodyCharacters: max(40, limits.maxBodyCharacters)
        )
    }

    private func clipped(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end])
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

    private func escapedCommandArgument(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func itemSummary(owner: SecondBrainOwnerRef) throws -> CiderItemSummary {
        guard let id = UUID(uuidString: owner.ownerID) else {
            throw CiderItemContextError.itemNotFound(UUID())
        }
        return try itemSummary(id: id)
    }

    private func itemSummary(id: UUID) throws -> CiderItemSummary {
        let stmt = try database.prepare("""
            SELECT id, type, title, created_at, updated_at, folder_id, relative_path
            FROM items
            WHERE id = ?;
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        guard try stmt.step() else {
            throw CiderItemContextError.itemNotFound(id)
        }
        return try itemSummary(from: stmt)
    }

    private func itemSummary(from stmt: SQLStatement) throws -> CiderItemSummary {
        guard let id = UUID(uuidString: stmt.string(at: 0)) else {
            throw CiderItemContextError.itemNotFound(UUID())
        }
        guard let type = itemType(fromDatabaseType: stmt.string(at: 1)) else {
            throw CiderItemContextError.unsupportedItemType(stmt.string(at: 1))
        }
        return CiderItemSummary(
            id: id,
            type: type,
            title: stmt.string(at: 2),
            relativePath: stmt.optionalString(at: 6),
            folderID: stmt.optionalString(at: 5).flatMap(UUID.init(uuidString:)),
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 4))
        )
    }

    private func owner(for item: CiderItemSummary) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: item.type.rawValue, ownerID: item.id.uuidString)
    }

    private func itemType(fromDatabaseType raw: String) -> LibraryEntityType? {
        let normalized = raw == "event" ? "dateCard" : raw
        guard let type = LibraryEntityType(rawValue: normalized),
              LibraryEntityType.activeCases.contains(type) else {
            return nil
        }
        return type
    }

    private func escapedLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
