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
    var routingDecisions: [SecondBrainRoutingDecision]
    var agentActions: [SecondBrainAgentAction]
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

    init(
        database: CiderDatabase = .shared,
        linkService: ItemLinkService? = nil,
        secondBrainStore: SecondBrainStore? = nil
    ) {
        self.database = database
        self.linkService = linkService ?? ItemLinkService(database: database)
        self.secondBrainStore = secondBrainStore ?? SecondBrainStore(database: database)
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
            routingDecisions: try secondBrainStore.routingDecisions(for: owner),
            agentActions: try secondBrainStore.agentActions(for: owner)
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
