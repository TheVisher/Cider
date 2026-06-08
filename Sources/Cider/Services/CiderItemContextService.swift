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

struct CiderItemCaptureProvenance: Identifiable, Equatable {
    var id: String { eventID }
    var eventID: String
    var owner: SecondBrainOwnerRef
    var sourceKind: String
    var surface: String?
    var channel: String?
    var channelID: String?
    var threadID: String?
    var messageID: String?
    var senderID: String?
    var senderName: String?
    var sourceURL: String?
    var sourceFile: String?
    var sourceText: String?
    var attachmentCount: Int
    var metadata: [String: String]
    var createdAt: Date
    var relation: SecondBrainRelation
}

struct CiderItemContextBundle: Equatable {
    var item: CiderItemSummary
    var owner: SecondBrainOwnerRef
    var sections: [SecondBrainSection]
    var chunks: [CiderItemChunk]
    var related: [ItemLinkSummary]
    var ownerRelations: [SecondBrainRelation]
    var backlinks: [SecondBrainRelation]
    var spaceMemberships: [CiderSpaceMembership]
    var routingDecisions: [SecondBrainRoutingDecision]
    var agentActions: [SecondBrainAgentAction]
    var enrichmentOutputs: [SecondBrainEnrichmentOutput]
    var captureProvenance: [CiderItemCaptureProvenance]
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
    var ownerRelations: [SecondBrainRelation]
    var backlinks: [SecondBrainRelation]
    var captureProvenance: [CiderItemCaptureProvenance]
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

enum CiderItemSearchScope: String, Codable, CaseIterable, Equatable {
    case all
    case personalMemory
    case projectKanban
    case qaArtifacts
    case files
}

struct CiderItemSearchResult: Identifiable, Codable, Equatable {
    var id: String
    var kind: CiderItemSearchResultKind
    var owner: SecondBrainOwnerRef
    var item: CiderItemSummary?
    var title: String
    var snippet: String
    var rank: Double
    var stage: String?
    var matchedQuery: String?
    var rankFactors: [String]
    var searchScope: CiderItemSearchScope

    init(
        id: String,
        kind: CiderItemSearchResultKind,
        owner: SecondBrainOwnerRef,
        item: CiderItemSummary?,
        title: String,
        snippet: String,
        rank: Double,
        stage: String? = nil,
        matchedQuery: String? = nil,
        rankFactors: [String] = [],
        searchScope: CiderItemSearchScope = .all
    ) {
        self.id = id
        self.kind = kind
        self.owner = owner
        self.item = item
        self.title = title
        self.snippet = snippet
        self.rank = rank
        self.stage = stage
        self.matchedQuery = matchedQuery
        self.rankFactors = rankFactors
        self.searchScope = searchScope
    }
}

struct CiderItemSearchDiagnosticsWarning: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var kind: String
    var message: String
    var owner: SecondBrainOwnerRef?
    var item: CiderItemSummary?
}

struct CiderItemSearchSemanticStatus: Equatable {
    var available: Bool
    var status: String
    var reason: String
    var mode: String
    var candidateCount: Int
    var candidates: [CiderItemSearchSemanticCandidate]
    var requiresRebuild: Bool
    var safeNextCommands: [String]
}

struct CiderItemSearchSemanticCandidate: Identifiable, Equatable {
    var id: String
    var item: CiderItemSummary?
    var owner: SecondBrainOwnerRef?
    var score: Double
    var rationale: String
    var rankFactors: [String]
}

struct CiderItemSearchIndexFreshness: Equatable {
    var status: String
    var itemUpdatedAt: Date?
    var newestChunkUpdatedAt: Date?
    var chunkCount: Int
}

struct CiderItemSearchDiagnosticsChunkMatch: Identifiable, Equatable {
    var id: String { chunk.id }
    var searchResult: CiderItemSearchResult
    var chunk: CiderItemChunk
    var item: CiderItemSummary?
    var routingDecisions: [SecondBrainRoutingDecision]
    var captureProvenance: [CiderItemCaptureProvenance]
    var indexFreshness: CiderItemSearchIndexFreshness
}

struct CiderItemSearchIndexWarning: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var kind: String
    var message: String
    var owner: SecondBrainOwnerRef
    var item: CiderItemSummary?
    var itemUpdatedAt: Date?
    var newestChunkUpdatedAt: Date?
    var chunkCount: Int
    var safeRepairCommand: String
}

struct CiderItemSearchDiagnosticsReport: Equatable {
    var command: String = "item.search-debug"
    var query: String
    var generatedAt: Date
    var exactMatches: [CiderItemSearchResult]
    var fallbackStages: [CiderItemSearchFallbackStage]
    var matchedChunks: [CiderItemSearchDiagnosticsChunkMatch]
    var candidateItems: [CiderItemSummary]
    var excludedItems: [CiderItemSearchDiagnosticsWarning]
    var indexWarnings: [CiderItemSearchIndexWarning]
    var semanticStatus: CiderItemSearchSemanticStatus
    var warnings: [CiderItemSearchDiagnosticsWarning]
    var errors: [CiderItemSearchDiagnosticsWarning]
    var safeNextCommands: [String]
}

struct CiderItemSearchFallbackStage: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var query: String
    var resultCount: Int
    var explanation: String
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
        let backlinks = try secondBrainStore.backlinks(for: owner)
        return CiderItemContextBundle(
            item: item,
            owner: owner,
            sections: try secondBrainStore.sections(for: owner),
            chunks: try chunks(for: owner),
            related: linkService.summaries(for: try linkService.relatedRefs(for: ref)),
            ownerRelations: try secondBrainStore.outgoingRelations(for: owner),
            backlinks: backlinks,
            spaceMemberships: try spaceMembershipStore.memberships(for: ref),
            routingDecisions: try secondBrainStore.routingDecisions(for: owner),
            agentActions: try secondBrainStore.agentActions(for: owner),
            enrichmentOutputs: try SecondBrainEnrichmentOutputService(database: database).outputs(for: owner),
            captureProvenance: try captureProvenance(from: backlinks)
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
            ownerRelations: Array(bundle.ownerRelations.prefix(normalizedLimits.maxRelated)),
            backlinks: Array(bundle.backlinks.prefix(normalizedLimits.maxRelated)),
            captureProvenance: Array(bundle.captureProvenance.prefix(normalizedLimits.maxHistory)),
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

    func items(inSpaceID spaceID: String) throws -> [CiderItemSummary] {
        try spaceMembershipStore.itemRefs(inSpaceID: spaceID).compactMap { ref in
            try? itemSummary(id: ref.entityID)
        }
    }

    func search(
        _ query: String,
        limit: Int = 20,
        inSpaceID spaceID: String? = nil,
        scope: CiderItemSearchScope = .all
    ) throws -> [CiderItemSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let spaceRefs = try spaceID.map { Set(try spaceMembershipStore.itemRefs(inSpaceID: $0)) }
        let plan = recallQueryPlan(for: trimmed)
        return try rankedSearchResults(
            queryPlan: plan,
            limit: limit,
            spaceRefs: spaceRefs,
            scope: scope
        )
    }

    func searchDiagnostics(_ query: String, limit: Int = 20) throws -> CiderItemSearchDiagnosticsReport {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(1, limit)
        let generatedAt = nowProvider()
        guard !trimmed.isEmpty else {
            return CiderItemSearchDiagnosticsReport(
                query: trimmed,
                generatedAt: generatedAt,
                exactMatches: [],
                fallbackStages: [],
                matchedChunks: [],
                candidateItems: [],
                excludedItems: [],
                indexWarnings: [],
                semanticStatus: semanticUnavailableStatus(),
                warnings: [
                    CiderItemSearchDiagnosticsWarning(
                        kind: "empty_query",
                        message: "Search diagnostics need a non-empty query."
                    )
                ],
                errors: [],
                safeNextCommands: []
            )
        }

        var warnings: [CiderItemSearchDiagnosticsWarning] = []
        var errors: [CiderItemSearchDiagnosticsWarning] = []
        let queryPlan = recallQueryPlan(for: trimmed)
        let filteredLowSignalTerms = lowSignalRecallTerms(in: trimmed)
        if !filteredLowSignalTerms.isEmpty {
            warnings.append(
                CiderItemSearchDiagnosticsWarning(
                    kind: "low_signal_terms_filtered",
                    message: "Ignored low-signal fallback terms: \(filteredLowSignalTerms.joined(separator: ", "))."
                )
            )
        }
        let exactMatches: [CiderItemSearchResult]
        do {
            exactMatches = try rankedSearchResults(
                queryPlan: queryPlan,
                limit: boundedLimit,
                spaceRefs: nil
            )
        } catch {
            exactMatches = try searchItems(trimmed, limit: boundedLimit)
            errors.append(
                CiderItemSearchDiagnosticsWarning(
                    kind: "fts_search_unavailable",
                    message: error.localizedDescription
                )
            )
        }
        let fallbackStages = queryPlan.map { stage in
            CiderItemSearchFallbackStage(
                name: stage.name,
                query: stage.query,
                resultCount: exactMatches.filter { diagnosticResult($0, matches: stage) }.count,
                explanation: stage.explanation
            )
        }

        var matchedChunks: [CiderItemSearchDiagnosticsChunkMatch] = []
        do {
            let chunkMatches = try secondBrainStore.searchChunks(query: trimmed, limit: boundedLimit)
            for result in chunkMatches {
                guard let chunk = try chunk(id: result.id, owner: result.owner) else {
                    warnings.append(
                        CiderItemSearchDiagnosticsWarning(
                            kind: "missing_chunk_row",
                            message: "FTS returned chunk \(result.id), but the content_chunks row was not readable.",
                            owner: result.owner
                        )
                    )
                    continue
                }
                let item = try? itemSummary(owner: result.owner)
                let routing = (try? secondBrainStore.routingDecisions(for: result.owner)) ?? []
                let backlinks = (try? secondBrainStore.backlinks(for: result.owner)) ?? []
                let provenance = (try? captureProvenance(from: backlinks)) ?? []
                matchedChunks.append(
                    CiderItemSearchDiagnosticsChunkMatch(
                        searchResult: CiderItemSearchResult(
                            id: "chunk-\(result.id)",
                            kind: .chunk,
                            owner: result.owner,
                            item: item,
                            title: result.title,
                            snippet: result.snippet,
                            rank: result.rank,
                            stage: "chunk_fts",
                            matchedQuery: trimmed,
                            rankFactors: ["original_chunk_fts"]
                        ),
                        chunk: chunk,
                        item: item,
                        routingDecisions: routing,
                        captureProvenance: provenance,
                        indexFreshness: try indexFreshness(for: result.owner, item: item)
                    )
                )
            }
        } catch {
            errors.append(
                CiderItemSearchDiagnosticsWarning(
                    kind: "fts_chunk_diagnostics_unavailable",
                    message: error.localizedDescription
                )
            )
        }

        let candidateItems = exactMatches.compactMap(\.item).reduce(into: [CiderItemSummary]()) { output, item in
            guard !output.contains(where: { $0.id == item.id }) else { return }
            output.append(item)
        }
        let indexWarnings = try itemIndexWarnings(matching: trimmed, limit: boundedLimit)
        if exactMatches.isEmpty && matchedChunks.isEmpty {
            warnings.append(
                CiderItemSearchDiagnosticsWarning(
                    kind: "no_matches",
                    message: "No title/path or FTS chunk matches were found for '\(trimmed)'."
                )
            )
            warnings.append(
                CiderItemSearchDiagnosticsWarning(
                    kind: "semantic_recall_unavailable",
                    message: "No lexical matches were found, and supplemental semantic/vector recall is unavailable. Exact item/chunk provenance remains canonical; run item doctor and rebuild stale chunks before relying on semantic recall."
                )
            )
        }

        var safeCommands = [
            "cider-cli item search \"\(escapedCommandArgument(trimmed))\" --limit \(boundedLimit) --json",
            "cider-cli item search-debug \"\(escapedCommandArgument(trimmed))\" --limit \(boundedLimit) --json",
            "cider-cli item doctor --json",
        ]
        for item in candidateItems + matchedChunks.compactMap(\.item) {
            safeCommands.append("cider-cli item get \(item.type.rawValue) \(item.id.uuidString) --json")
            safeCommands.append("cider-cli item context \(item.type.rawValue) \(item.id.uuidString) --json")
            safeCommands.append("cider-cli item rebuild-chunks \(item.type.rawValue) \(item.id.uuidString) --json")
        }
        safeCommands += indexWarnings.map(\.safeRepairCommand)

        return CiderItemSearchDiagnosticsReport(
            query: trimmed,
            generatedAt: generatedAt,
            exactMatches: exactMatches,
            fallbackStages: fallbackStages,
            matchedChunks: matchedChunks,
            candidateItems: candidateItems,
            excludedItems: [],
            indexWarnings: indexWarnings,
            semanticStatus: semanticUnavailableStatus(),
            warnings: warnings,
            errors: errors,
            safeNextCommands: orderedUnique(safeCommands)
        )
    }

    private func searchItems(
        _ query: String,
        limit: Int,
        spaceRefs: Set<LibraryEntityRef>? = nil
    ) throws -> [CiderItemSearchResult] {
        let sql: String
        if spaceRefs == nil {
            sql = """
            SELECT id, type, title, created_at, updated_at, folder_id, relative_path
            FROM items
            WHERE title LIKE ? ESCAPE '\\'
               OR IFNULL(relative_path, '') LIKE ? ESCAPE '\\'
            ORDER BY
                CASE WHEN title LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                updated_at DESC,
                title COLLATE NOCASE ASC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT id, type, title, created_at, updated_at, folder_id, relative_path
            FROM items
            WHERE (title LIKE ? ESCAPE '\\'
               OR IFNULL(relative_path, '') LIKE ? ESCAPE '\\')
            ORDER BY
                CASE WHEN title LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                updated_at DESC,
                title COLLATE NOCASE ASC;
            """
        }
        let stmt = try database.prepare(sql)
        let containsPattern = "%\(escapedLikePattern(query))%"
        let prefixPattern = "\(escapedLikePattern(query))%"
        stmt.bind(containsPattern, at: 1)
            .bind(containsPattern, at: 2)
            .bind(prefixPattern, at: 3)
        if spaceRefs == nil {
            stmt.bind(max(1, limit), at: 4)
        }

        var results: [CiderItemSearchResult] = []
        while try stmt.step() {
            let item = try itemSummary(from: stmt)
            if let spaceRefs {
                let ref = LibraryEntityRef(type: item.type, entityID: item.id)
                guard spaceRefs.contains(ref) else { continue }
            }
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
            if spaceRefs != nil, results.count >= max(1, limit) { break }
        }
        return results
    }

    private func diagnosticResult(
        _ result: CiderItemSearchResult,
        matches stage: RecallQueryStage
    ) -> Bool {
        result.stage == stage.name
            || result.matchedQuery == stage.query
            || result.rankFactors.contains("matched_query:\(stage.query)")
    }

    private struct RecallQueryStage: Equatable {
        var name: String
        var query: String
        var explanation: String
    }

    private struct RecallRankEvidence {
        var rankContribution: Double
        var factors: [String]
    }

    private struct TagFacetFilter: Equatable {
        var itemTypes: [LibraryEntityType] = []
        var tagQueries: [String] = []

        var hasFilters: Bool {
            !itemTypes.isEmpty || !tagQueries.isEmpty
        }
    }

    private struct LifeMemoryTypeIntent: Equatable {
        var itemType: LibraryEntityType
        var contentTokens: [String]

        var isBroadTypeOnly: Bool {
            contentTokens.isEmpty
        }
    }

    private func recallQueryPlan(for query: String) -> [RecallQueryStage] {
        var stages: [RecallQueryStage] = [
            RecallQueryStage(
                name: "original_query",
                query: query,
                explanation: "Original user query."
            )
        ]
        if parseTagFacetFilter(from: query).hasFilters {
            stages.append(
                RecallQueryStage(
                    name: "tag_facet_filter",
                    query: query,
                    explanation: "Intersected broad type/source facets with focused tag facets for recall filtering."
                )
            )
        }
        let expansions = recallExpandedQueries(for: query)
        for expanded in expansions where expanded.caseInsensitiveCompare(query) != .orderedSame {
            stages.append(
                RecallQueryStage(
                    name: "human_query_expansion",
                    query: expanded,
                    explanation: "Expanded human recall terms for \(query), including \(expanded)."
                )
            )
        }
        return orderedUniqueStages(stages)
    }

    private func recallExpandedQueries(for query: String) -> [String] {
        let tokens = recallTokens(query)
        var expansions: [String] = []
        let synonymMap: [String: [String]] = [
            "adhd": ["ADHD", "evaluation", "symptoms", "Adderall", "document"],
            "symptoms": ["symptoms", "evaluation"],
            "document": ["document", "file", "pdf", "docx"],
            "doc": ["doc", "document", "file", "docx"],
            "pdf": ["pdf", "file", "document"],
            "docx": ["docx", "file", "document"],
            "resume": ["resume", "cv", "pdf", "docx", "file"],
            "imdb": ["IMDb", "movie", "movies", "media"],
            "movie": ["movie", "movies", "media", "IMDb"],
            "movies": ["movies", "movie", "media", "IMDb"],
            "tiktok": ["TikTok", "video", "recipe", "capture"],
            "video": ["video", "TikTok", "capture"],
            "recipe": ["recipe", "recipes", "TikTok"],
            "steam": ["Steam", "game", "games", "media"],
            "game": ["game", "games", "Steam", "media"],
            "games": ["games", "game", "Steam", "media"],
            "tl": ["TL", "team leader", "team lead", "work hub"],
            "team": ["team leader", "team lead", "TL"],
            "leader": ["team leader", "team lead", "TL"],
            "lead": ["team lead", "team leader", "TL"],
            "work": ["work", "team leader", "TL"],
            "hub": ["hub", "work hub", "team leader"],
        ]
        for token in tokens {
            guard !isLowSignalRecallExpansion(token) else { continue }
            expansions.append(token)
            expansions.append(contentsOf: synonymMap[token.lowercased()] ?? [])
        }
        if tokens.contains(where: { $0.caseInsensitiveCompare("team") == .orderedSame })
            && tokens.contains(where: { $0.caseInsensitiveCompare("leader") == .orderedSame }) {
            expansions.append(contentsOf: ["team leader", "team lead", "TL"])
        }
        if tokens.contains(where: { $0.caseInsensitiveCompare("work") == .orderedSame })
            && tokens.contains(where: { $0.caseInsensitiveCompare("hub") == .orderedSame }) {
            expansions.append("work hub")
        }
        let filtered = orderedUnique(expansions)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }
        return Array(filtered[0..<min(filtered.count, 24)])
    }

    private func lowSignalRecallTerms(in query: String) -> [String] {
        orderedUnique(
            recallTokens(query)
                .map { normalizedRecallToken($0) }
                .filter(isLowSignalRecallExpansion)
        )
    }

    private func isLowSignalRecallExpansion(_ token: String) -> Bool {
        let normalized = normalizedRecallToken(token)
        let lowSignal: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by",
            "for", "forgot", "from", "i", "in", "into", "is", "it",
            "me", "of", "on", "or", "that", "the", "this", "title",
            "to", "using", "with",
        ]
        return lowSignal.contains(normalized)
    }

    private func recallTokens(_ query: String) -> [String] {
        query
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func orderedUniqueStages(_ stages: [RecallQueryStage]) -> [RecallQueryStage] {
        var seen = Set<String>()
        var output: [RecallQueryStage] = []
        for stage in stages {
            let key = "\(stage.name):\(stage.query.lowercased())"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(stage)
        }
        return output
    }

    private func rankedSearchResults(
        queryPlan: [RecallQueryStage],
        limit: Int,
        spaceRefs: Set<LibraryEntityRef>? = nil,
        scope: CiderItemSearchScope = .all
    ) throws -> [CiderItemSearchResult] {
        let boundedLimit = max(1, limit)
        var bestByOwner: [String: CiderItemSearchResult] = [:]
        let originalQuery = queryPlan.first?.query ?? ""
        let tagFilter = parseTagFacetFilter(from: originalQuery)
        let lifeMemoryTypeIntent = lifeMemoryTypeIntent(in: originalQuery)

        if tagFilter.hasFilters == false,
           let lifeMemoryTypeIntent,
           lifeMemoryTypeIntent.isBroadTypeOnly {
            let typeMatches = try searchTagFacetItems(
                query: originalQuery,
                filter: TagFacetFilter(itemTypes: [lifeMemoryTypeIntent.itemType]),
                limit: max(boundedLimit, boundedLimit * 3),
                spaceRefs: spaceRefs
            )
            for var match in typeMatches {
                match.stage = "generic_type_intent"
                match.matchedQuery = originalQuery
                match.rankFactors = orderedUnique(match.rankFactors + [
                    "generic_life_memory_type_intent",
                    "type_intent_match",
                ])
                mergeRecallResult(match, into: &bestByOwner)
            }
        }

        if tagFilter.hasFilters {
            let tagMatches = try searchTagFacetItems(
                query: originalQuery,
                filter: tagFilter,
                limit: max(boundedLimit, boundedLimit * 3),
                spaceRefs: spaceRefs
            )
            for match in tagMatches {
                mergeRecallResult(match, into: &bestByOwner)
            }
        }

        for (stageIndex, stage) in queryPlan.enumerated() {
            if stage.name == "tag_facet_filter" { continue }
            let stageLimit = max(boundedLimit, boundedLimit * 3)
            let itemMatches = try searchItems(stage.query, limit: stageLimit, spaceRefs: spaceRefs)
            for match in itemMatches {
                if tagFilter.hasFilters {
                    guard let item = match.item,
                          try self.item(item, matches: tagFilter) != nil else {
                        continue
                    }
                }
                var result = match
                result.stage = stage.name
                result.matchedQuery = stage.query
                let evidence = try recallRankEvidence(
                    result: result,
                    chunk: nil,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stage: stage
                )
                result.rank = recallRank(
                    result: result,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stageIndex: stageIndex,
                    scope: scope,
                    evidence: evidence
                )
                result.rankFactors = recallRankFactors(
                    result: result,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stage: stage,
                    stageIndex: stageIndex,
                    scope: scope,
                    evidence: evidence
                )
                mergeRecallResult(result, into: &bestByOwner)
            }

            let chunkMatches = try secondBrainStore.searchChunks(query: stage.query, limit: stageLimit)
            for match in chunkMatches {
                let item = try? itemSummary(owner: match.owner)
                if tagFilter.hasFilters {
                    guard let item,
                          try self.item(item, matches: tagFilter) != nil else {
                        continue
                    }
                }
                if let spaceRefs, let item {
                    let ref = LibraryEntityRef(type: item.type, entityID: item.id)
                    guard spaceRefs.contains(ref) else { continue }
                } else if spaceRefs != nil {
                    continue
                }
                var result = CiderItemSearchResult(
                    id: "chunk-\(match.id)",
                    kind: .chunk,
                    owner: match.owner,
                    item: item,
                    title: match.title,
                    snippet: match.snippet,
                    rank: match.rank,
                    stage: stage.name,
                    matchedQuery: stage.query
                )
                let matchedChunk = try? chunk(id: match.id, owner: match.owner)
                let evidence = try recallRankEvidence(
                    result: result,
                    chunk: matchedChunk,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stage: stage
                )
                result.rank = recallRank(
                    result: result,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stageIndex: stageIndex,
                    scope: scope,
                    evidence: evidence
                )
                result.rankFactors = recallRankFactors(
                    result: result,
                    originalQuery: originalQuery,
                    matchedQuery: stage.query,
                    stage: stage,
                    stageIndex: stageIndex,
                    scope: scope,
                    evidence: evidence
                )
                mergeRecallResult(result, into: &bestByOwner)
            }
        }

        let hasExpandedRecallIntent = queryPlan.count > 1
        let hasSavedItemMatch = bestByOwner.values.contains { $0.item != nil }
        let candidates = bestByOwner.values.filter { result in
            !shouldSuppressOwnerOnlyKanbanResult(
                result,
                hasExpandedRecallIntent: hasExpandedRecallIntent,
                hasSavedItemMatch: hasSavedItemMatch,
                query: originalQuery,
                scope: scope
            )
                && searchResult(result, isIncludedIn: scope)
        }

        return Array(candidates)
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                if (lhs.item != nil) != (rhs.item != nil) { return lhs.item != nil }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(boundedLimit)
            .map { result in
                var scoped = result
                scoped.searchScope = scope
                return scoped
            }
    }

    private func searchResult(
        _ result: CiderItemSearchResult,
        isIncludedIn scope: CiderItemSearchScope
    ) -> Bool {
        switch scope {
        case .all:
            return true
        case .personalMemory:
            return !isProjectOrQAArtifact(result)
        case .projectKanban:
            return result.owner.ownerType == "kanban_card" || isProjectArtifact(result)
        case .qaArtifacts:
            return isQAArtifact(result)
        case .files:
            return result.item?.type == .vaultFile || result.owner.ownerType == "vaultFile"
        }
    }

    private func shouldSuppressOwnerOnlyKanbanResult(
        _ result: CiderItemSearchResult,
        hasExpandedRecallIntent: Bool,
        hasSavedItemMatch: Bool,
        query: String,
        scope: CiderItemSearchScope
    ) -> Bool {
        guard hasExpandedRecallIntent,
              hasSavedItemMatch,
              result.owner.ownerType == "kanban_card",
              result.item == nil else {
            return false
        }
        if scope == .projectKanban { return false }
        if scope == .all, shouldBoostProjectKanbanCard(for: query) { return false }
        return true
    }

    private func isProjectOrQAArtifact(_ result: CiderItemSearchResult) -> Bool {
        result.owner.ownerType == "kanban_card" || isProjectArtifact(result) || isQAArtifact(result)
    }

    private func isProjectArtifact(_ result: CiderItemSearchResult) -> Bool {
        guard let path = result.item?.relativePath else {
            return result.owner.ownerType == "kanban_card"
        }
        return normalizedPathComponents(path).first == "projects"
    }

    private func isQAArtifact(_ result: CiderItemSearchResult) -> Bool {
        let components = normalizedPathComponents(result.item?.relativePath ?? "")
        return components.contains("qa") || components.contains("audits")
    }

    private func normalizedPathComponents(_ path: String) -> [String] {
        path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
    }

    private func searchTagFacetItems(
        query: String,
        filter: TagFacetFilter,
        limit: Int,
        spaceRefs: Set<LibraryEntityRef>?
    ) throws -> [CiderItemSearchResult] {
        let activeDatabaseTypes = LibraryEntityType.activeCases.map(ItemLinkService.databaseItemType(for:))
        guard !activeDatabaseTypes.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: activeDatabaseTypes.count).joined(separator: ", ")
        let stmt = try database.prepare("""
            SELECT id, type, title, created_at, updated_at, folder_id, relative_path
            FROM items
            WHERE type IN (\(placeholders))
            ORDER BY updated_at DESC, title COLLATE NOCASE ASC;
            """)
        for (index, type) in activeDatabaseTypes.enumerated() {
            stmt.bind(type, at: Int32(index + 1))
        }

        var results: [CiderItemSearchResult] = []
        while try stmt.step() {
            let summary = try itemSummary(from: stmt)
            if let spaceRefs {
                let ref = LibraryEntityRef(type: summary.type, entityID: summary.id)
                guard spaceRefs.contains(ref) else { continue }
            }
            guard let tagEvidence = try item(summary, matches: filter) else { continue }

            let owner = owner(for: summary)
            var factors = [
                "saved_library_item",
                "stage:tag_facet_filter",
                "matched_query:\(query)",
            ]
            factors += tagEvidence
            let result = CiderItemSearchResult(
                id: "item-\(summary.id.uuidString)",
                kind: .item,
                owner: owner,
                item: summary,
                title: summary.title,
                snippet: summary.relativePath ?? summary.type.rawValue,
                rank: 1_400 + recallRecencyContribution(for: summary),
                stage: "tag_facet_filter",
                matchedQuery: query,
                rankFactors: orderedUnique(factors)
            )
            results.append(result)
            if results.count >= max(1, limit) { break }
        }
        return results
    }

    private func mergeRecallResult(
        _ result: CiderItemSearchResult,
        into bestByOwner: inout [String: CiderItemSearchResult]
    ) {
        let key = result.item.map { "\($0.type.rawValue):\($0.id.uuidString)" }
            ?? "\(result.owner.ownerType):\(result.owner.ownerID)"
        guard var existing = bestByOwner[key] else {
            bestByOwner[key] = result
            return
        }
        let mergedFactors = orderedUnique(existing.rankFactors + result.rankFactors)
        if existing.kind == .item, result.item?.id == existing.item?.id {
            existing.rank = max(existing.rank, result.rank)
            if result.kind == .chunk && result.snippet.count > existing.snippet.count {
                existing.snippet = result.snippet
            }
            existing.rankFactors = mergedFactors
            if existing.stage == nil { existing.stage = result.stage }
            if existing.matchedQuery == nil { existing.matchedQuery = result.matchedQuery }
            bestByOwner[key] = existing
            return
        }
        if result.kind == .item, result.item?.id == existing.item?.id {
            var replacement = result
            replacement.rank = max(existing.rank, result.rank)
            if existing.kind == .chunk && existing.snippet.count > replacement.snippet.count {
                replacement.snippet = existing.snippet
            }
            replacement.rankFactors = mergedFactors
            if replacement.stage == nil { replacement.stage = existing.stage }
            if replacement.matchedQuery == nil { replacement.matchedQuery = existing.matchedQuery }
            bestByOwner[key] = replacement
            return
        }
        if result.rank > existing.rank || (result.item != nil && existing.item == nil) {
            var replacement = result
            replacement.rankFactors = mergedFactors
            bestByOwner[key] = replacement
        } else {
            existing.rankFactors = mergedFactors
            bestByOwner[key] = existing
        }
    }

    private func recallRank(
        result: CiderItemSearchResult,
        originalQuery: String,
        matchedQuery: String,
        stageIndex: Int,
        scope: CiderItemSearchScope,
        evidence: RecallRankEvidence
    ) -> Double {
        var rank: Double = result.item == nil ? 100 : 900
        if result.kind == .item { rank += 120 }
        if result.owner.ownerType == "kanban_card" {
            switch scope {
            case .projectKanban:
                rank += 1_250
            case .all:
                rank += shouldBoostProjectKanbanCard(for: originalQuery) ? 720 : -650
            default:
                rank -= 650
            }
        }
        if let item = result.item {
            rank += typeIntentBoost(item: item, query: originalQuery)
            if item.title.localizedCaseInsensitiveContains(matchedQuery) { rank += 40 }
            if item.relativePath?.localizedCaseInsensitiveContains(matchedQuery) == true { rank += 35 }
        }
        rank += evidence.rankContribution
        if scope == .all,
           shouldDemoteArtifacts(forLifeMemoryQuery: originalQuery),
           isProjectOrQAArtifact(result) {
            rank -= 700
        }
        rank -= Double(stageIndex * 20)
        return rank
    }

    private func recallRankFactors(
        result: CiderItemSearchResult,
        originalQuery: String,
        matchedQuery: String,
        stage: RecallQueryStage,
        stageIndex: Int,
        scope: CiderItemSearchScope,
        evidence: RecallRankEvidence
    ) -> [String] {
        var factors: [String] = []
        factors.append(result.item == nil ? "owner_only_chunk" : "saved_library_item")
        factors.append(result.kind == .item ? "title_or_path_match" : "chunk_match")
        if result.owner.ownerType == "kanban_card" {
            switch scope {
            case .projectKanban:
                factors.append("kanban_card_project_scope_boost")
            case .all where shouldBoostProjectKanbanCard(for: originalQuery):
                factors.append("kanban_card_explicit_project_intent")
            default:
                factors.append("kanban_demoted_for_saved_item_recall")
            }
        }
        factors.append("stage:\(stage.name)")
        factors.append("matched_query:\(matchedQuery)")
        if stageIndex > 0 { factors.append("human_query_expansion:\(matchedQuery)") }
        if let item = result.item {
            factors += typeIntentFactors(item: item, query: matchedQuery)
        }
        if scope == .all,
           shouldDemoteArtifacts(forLifeMemoryQuery: originalQuery),
           isProjectOrQAArtifact(result) {
            factors.append("artifact_demoted_for_life_memory_type_intent")
        }
        factors += evidence.factors
        return orderedUnique(factors)
    }

    private func recallRankEvidence(
        result: CiderItemSearchResult,
        chunk: CiderItemChunk?,
        originalQuery: String,
        matchedQuery: String,
        stage: RecallQueryStage
    ) throws -> RecallRankEvidence {
        let queryTokens = recallTokens(originalQuery).map { normalizedRecallToken($0) }
        let distinctiveTokens = orderedUnique(queryTokens)
            .filter { isDistinctiveRecallToken($0) }
        let title = result.item?.title ?? result.title
        let path = result.item?.relativePath ?? ""
        let snippet = result.snippet
        let chunkTitle = chunk?.title ?? (result.kind == .chunk ? result.title : "")
        let chunkBody = chunk?.body ?? (result.kind == .chunk ? result.snippet : "")
        let source = chunk?.source ?? ""
        let combined = [title, path, snippet, chunkTitle, chunkBody, source].joined(separator: " ")

        var contribution: Double = 0
        var factors: [String] = []
        var matchedDistinctive: [String] = []
        let fieldMatches: [(name: String, text: String, weight: Double)] = [
            ("item_title", title, 50),
            ("relative_path", path, 18),
            ("chunk_title", chunkTitle, 40),
            ("chunk_body", chunkBody, 30),
            ("snippet", snippet, 12),
        ]
        for field in fieldMatches {
            let matched = distinctiveTokens.filter { containsRecallToken($0, in: field.text) }
            guard !matched.isEmpty else { continue }
            factors.append("matched_field:\(field.name)")
            contribution += Double(matched.count) * field.weight
            matchedDistinctive += matched
        }

        let uniqueDistinctive = orderedUnique(matchedDistinctive)
        if !uniqueDistinctive.isEmpty {
            contribution += Double(uniqueDistinctive.count * uniqueDistinctive.count) * 8
            factors.append("distinctive_terms:\(uniqueDistinctive.joined(separator: ","))")
        }

        let queryProviderIntents = recallProviderSignals(in: originalQuery)
        for provider in queryProviderIntents {
            factors.append("query_provider_intent:\(provider)")
        }

        let providerSignals = recallProviderSignals(in: combined)
        for provider in providerSignals {
            contribution += 32
            factors.append("provider_signal:\(provider)")
        }

        if let item = result.item {
            if item.type == .vaultFile {
                contribution += 28
                factors.append("type_signal:vaultFile")
            }
            let memberships = try spaceMembershipStore.memberships(for: LibraryEntityRef(type: item.type, entityID: item.id))
            for membership in memberships {
                contribution += 24
                factors.append("space_intent:\(membership.spaceName)")
            }
            let recency = recallRecencyContribution(for: item)
            contribution += recency
            factors.append("recency_contribution:\(Int(recency.rounded()))")
        }

        if stage.name == "original_query" && matchedQuery == originalQuery {
            contribution += 12
        }

        return RecallRankEvidence(rankContribution: contribution, factors: orderedUnique(factors))
    }

    private func normalizedRecallToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
    }

    private func isDistinctiveRecallToken(_ token: String) -> Bool {
        guard token.count >= 3 else { return false }
        let generic: Set<String> = [
            "and", "the", "for", "with", "from", "this", "that",
            "capture", "saved", "item", "social", "video", "media",
            "file", "document", "doc", "pdf", "movie", "game", "games",
            "tiktok", "imdb", "steam", "rottentomatoes", "rotten", "tomatoes",
        ]
        return !generic.contains(token)
    }

    private func containsRecallToken(_ token: String, in text: String) -> Bool {
        guard !token.isEmpty else { return false }
        return recallTokens(text).map { normalizedRecallToken($0) }.contains(token)
    }

    private func recallProviderSignals(in text: String) -> [String] {
        let lower = text.lowercased()
        var providers: [String] = []
        let signals: [(String, [String])] = [
            ("tiktok", ["tiktok"]),
            ("imdb", ["imdb"]),
            ("rottentomatoes", ["rotten tomatoes", "rottentomatoes"]),
            ("steam", ["steam"]),
            ("docx", ["docx"]),
            ("pdf", ["pdf"]),
        ]
        for (provider, aliases) in signals where aliases.contains(where: { lower.contains($0) }) {
            providers.append(provider)
        }
        return orderedUnique(providers)
    }

    private func recallRecencyContribution(for item: CiderItemSummary) -> Double {
        let age = max(0, nowProvider().timeIntervalSince(item.updatedAt))
        let day = 86_400.0
        if age <= day { return 25 }
        if age <= day * 7 { return 18 }
        if age <= day * 30 { return 10 }
        if age <= day * 120 { return 4 }
        return 0
    }

    private func typeIntentBoost(item: CiderItemSummary, query: String) -> Double {
        let lower = query.lowercased()
        switch item.type {
        case .vaultFile:
            return ["file", "document", "doc", "pdf", "docx", "resume"].contains { lower.contains($0) } ? 70 : 0
        case .bookmark:
            return ["bookmark", "link", "recipe", "imdb", "movie", "tiktok", "steam", "game", "video", "capture"].contains { lower.contains($0) } ? 55 : 0
        case .note:
            if isDailyJournal(item),
               ["journal", "reflection", "voice", "driving", "parked"].contains(where: lower.contains) {
                return 520
            }
            return ["note", "hub", "work", "tl", "team leader"].contains { lower.contains($0) } ? 45 : 0
        case .contact:
            return ["contact", "person", "people", "vcf", "vcard"].contains { lower.contains($0) } ? 220 : 0
        case .todo:
            return ["todo", "todos", "task", "tasks"].contains { lower.contains($0) } ? 220 : 0
        case .dateCard:
            return ["event", "events", "date", "dates", "calendar"].contains { lower.contains($0) } ? 240 : 0
        default:
            return 0
        }
    }

    private func typeIntentFactors(item: CiderItemSummary, query: String) -> [String] {
        guard typeIntentBoost(item: item, query: query) > 0 else { return [] }
        let lower = query.lowercased()
        switch item.type {
        case .note where isDailyJournal(item)
            && ["journal", "reflection", "voice", "driving", "parked"].contains(where: lower.contains):
            return ["journal_intent_match", "type_intent_match"]
        case .contact:
            return ["contact_intent_match", "type_intent_match"]
        case .todo:
            return ["todo_intent_match", "type_intent_match"]
        case .dateCard:
            return ["event_intent_match", "type_intent_match"]
        default:
            return ["type_intent_match"]
        }
    }

    private func lifeMemoryTypeIntent(in query: String) -> LifeMemoryTypeIntent? {
        let normalizedTokens = recallTokens(query).map(normalizedRecallToken)
        guard !normalizedTokens.isEmpty else { return nil }
        let typeAliases: [(type: LibraryEntityType, aliases: Set<String>)] = [
            (.dateCard, ["event", "events", "date", "dates", "calendar"]),
            (.todo, ["todo", "todos", "task", "tasks"]),
            (.contact, ["contact", "contacts", "person", "people"]),
            (.vaultFile, ["file", "files", "document", "documents", "doc", "docs", "pdf", "docx"]),
            (.bookmark, ["bookmark", "bookmarks", "link", "links"]),
            (.note, ["note", "notes", "journal", "journals"]),
        ]
        for entry in typeAliases {
            guard normalizedTokens.contains(where: entry.aliases.contains) else { continue }
            let contentTokens = normalizedTokens.filter { !entry.aliases.contains($0) }
            return LifeMemoryTypeIntent(itemType: entry.type, contentTokens: contentTokens)
        }
        return nil
    }

    private func shouldDemoteArtifacts(forLifeMemoryQuery query: String) -> Bool {
        guard lifeMemoryTypeIntent(in: query) != nil else { return false }
        let lower = query.lowercased()
        let explicitArtifactSignals = [
            "qa", "audit", "screenshot", "evidence", "artifact", "project", "kanban", "plan", "acceptance"
        ]
        return !explicitArtifactSignals.contains(where: lower.contains)
    }

    private func shouldBoostProjectKanbanCard(for query: String) -> Bool {
        let lower = query.lowercased()
        if lower.range(of: #"\bcid-\d+\b"#, options: .regularExpression) != nil { return true }
        let explicitProjectSignals = [
            "project", "kanban", "card", "cid", "artifact", "scope", "scopes", "acceptance", "implementation"
        ]
        return explicitProjectSignals.contains(where: lower.contains)
    }

    private func isDailyJournal(_ item: CiderItemSummary) -> Bool {
        item.title.localizedCaseInsensitiveContains("Daily Journal")
            || item.relativePath?.localizedCaseInsensitiveContains("Daily Journal") == true
    }

    private func parseTagFacetFilter(from query: String) -> TagFacetFilter {
        var filter = TagFacetFilter()
        let tokens = query.split { $0.isWhitespace }.map(String.init)
        for token in tokens {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !value.isEmpty else { continue }

            switch key {
            case "type", "source":
                if let itemType = itemTypeFacet(value) {
                    filter.itemTypes.append(itemType)
                }
            case "tag", "topic":
                filter.tagQueries.append(value)
            default:
                continue
            }
        }
        filter.itemTypes = orderedUnique(filter.itemTypes.map(\.rawValue)).compactMap(LibraryEntityType.init(rawValue:))
        filter.tagQueries = orderedUnique(filter.tagQueries)
        return filter
    }

    private func itemTypeFacet(_ raw: String) -> LibraryEntityType? {
        switch raw.lowercased() {
        case "bookmark", "bookmarks", "link", "links":
            return .bookmark
        case "note", "notes", "journal":
            return .note
        case "file", "files", "document", "documents", "pdf", "docx":
            return .vaultFile
        case "contact", "contacts", "person", "people":
            return .contact
        case "todo", "todos", "task", "tasks":
            return .todo
        case "event", "events", "date", "dates":
            return .dateCard
        default:
            return nil
        }
    }

    private func item(
        _ item: CiderItemSummary,
        matches filter: TagFacetFilter
    ) throws -> [String]? {
        var factors: [String] = []

        if !filter.itemTypes.isEmpty {
            guard filter.itemTypes.contains(item.type) else { return nil }
        }

        let tags = try itemTags(for: item.id)
        for type in filter.itemTypes {
            let expectedTypeTag = canonicalTypeTag(for: type)
            if let matched = tags.first(where: { tagMatches($0, query: expectedTypeTag) }) {
                factors.append("tag_filter:\(matched)")
                factors.append("tag_facet:type")
            } else {
                factors.append("type_filter:\(type.rawValue)")
            }
        }

        for query in filter.tagQueries {
            guard let matched = tags.first(where: { tagMatches($0, query: query) }) else {
                return nil
            }
            factors.append("tag_filter:\(matched)")
            factors.append("tag_facet:\(facetName(for: matched) ?? "tag")")
        }

        return orderedUnique(factors)
    }

    private func itemTags(for itemID: UUID) throws -> [String] {
        let stmt = try database.prepare("""
            SELECT t.name
            FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.item_id = ?
            ORDER BY t.name COLLATE NOCASE ASC;
            """)
        stmt.bind(DatabaseHelpers.encode(itemID), at: 1)

        var tags: [String] = []
        while try stmt.step() {
            tags.append(stmt.string(at: 0))
        }
        return tags
    }

    private func tagMatches(_ tag: String, query: String) -> Bool {
        let normalizedTag = normalizedTagFacet(tag)
        let normalizedQuery = normalizedTagFacet(query)
        guard !normalizedQuery.isEmpty else { return false }
        if normalizedTag == normalizedQuery { return true }
        return normalizedTag.split(separator: "/").last.map(String.init) == normalizedQuery
    }

    private func normalizedTagFacet(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_")).inverted)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private func canonicalTypeTag(for type: LibraryEntityType) -> String {
        switch type {
        case .bookmark:
            return "type/bookmark"
        case .note:
            return "type/note"
        case .vaultFile:
            return "type/file"
        case .contact:
            return "type/contact"
        case .todo:
            return "type/todo"
        case .dateCard:
            return "type/event"
        case .externalFile:
            return "type/file"
        case .session:
            return "type/session"
        }
    }

    private func facetName(for tag: String) -> String? {
        let parts = tag.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let normalized = normalizedTagFacet(parts[0])
        return normalized.isEmpty ? nil : normalized
    }

    private func chunk(id: String, owner: SecondBrainOwnerRef) throws -> CiderItemChunk? {
        let stmt = try database.prepare("""
            SELECT id, item_id, source, title, body, chunk_index, metadata, created_at, updated_at
            FROM content_chunks
            WHERE id = ? AND owner_type = ? AND owner_id = ?
            LIMIT 1;
            """)
        stmt.bind(id, at: 1)
            .bind(owner.ownerType, at: 2)
            .bind(owner.ownerID, at: 3)
        guard try stmt.step() else { return nil }
        return CiderItemChunk(
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
    }

    private func itemIndexWarnings(matching query: String, limit: Int) throws -> [CiderItemSearchIndexWarning] {
        let activeDatabaseTypes = LibraryEntityType.activeCases.map(ItemLinkService.databaseItemType(for:))
        guard !activeDatabaseTypes.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: activeDatabaseTypes.count).joined(separator: ", ")
        let stmt = try database.prepare("""
            SELECT i.id, i.type, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path,
                   COUNT(c.id) AS chunk_count,
                   MAX(c.updated_at) AS newest_chunk_updated_at
            FROM items i
            LEFT JOIN content_chunks c
              ON c.owner_id = i.id
             AND c.owner_type = CASE WHEN i.type = 'event' THEN 'dateCard' ELSE i.type END
            WHERE i.type IN (\(placeholders))
              AND (
                    i.title LIKE ? ESCAPE '\\'
                 OR IFNULL(i.relative_path, '') LIKE ? ESCAPE '\\'
              )
            GROUP BY i.id, i.type, i.title, i.created_at, i.updated_at, i.folder_id, i.relative_path
            HAVING chunk_count = 0 OR newest_chunk_updated_at IS NULL OR newest_chunk_updated_at < i.updated_at
            ORDER BY i.updated_at DESC, i.title COLLATE NOCASE ASC
            LIMIT ?;
            """)
        for (index, type) in activeDatabaseTypes.enumerated() {
            stmt.bind(type, at: Int32(index + 1))
        }
        let pattern = "%\(escapedLikePattern(query))%"
        let queryStart = activeDatabaseTypes.count + 1
        stmt.bind(pattern, at: Int32(queryStart))
            .bind(pattern, at: Int32(queryStart + 1))
            .bind(max(1, limit), at: Int32(queryStart + 2))

        var warnings: [CiderItemSearchIndexWarning] = []
        while try stmt.step() {
            let item = try itemSummary(from: stmt)
            let owner = owner(for: item)
            let chunkCount = stmt.int(at: 7)
            let itemUpdatedAt = item.updatedAt
            let newestChunkUpdatedAt = stmt.optionalDouble(at: 8).map(DatabaseHelpers.decodeDate)
            let kind = chunkCount == 0 ? "missing_chunks" : "stale_chunks"
            let message: String
            if chunkCount == 0 {
                message = "Item matched the query by title/path, but has no searchable content chunks."
            } else {
                message = "Item matched the query by title/path, but its newest content chunk is older than the item row."
            }
            warnings.append(
                CiderItemSearchIndexWarning(
                    kind: kind,
                    message: message,
                    owner: owner,
                    item: item,
                    itemUpdatedAt: itemUpdatedAt,
                    newestChunkUpdatedAt: newestChunkUpdatedAt,
                    chunkCount: chunkCount,
                    safeRepairCommand: "cider-cli item rebuild-chunks \(item.type.rawValue) \(item.id.uuidString) --json"
                )
            )
        }
        return warnings
    }

    private func indexFreshness(for owner: SecondBrainOwnerRef, item: CiderItemSummary?) throws -> CiderItemSearchIndexFreshness {
        let stmt = try database.prepare("""
            SELECT COUNT(id), MAX(updated_at)
            FROM content_chunks
            WHERE owner_type = ? AND owner_id = ?;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        guard try stmt.step() else {
            return CiderItemSearchIndexFreshness(status: "unknown", itemUpdatedAt: item?.updatedAt, newestChunkUpdatedAt: nil, chunkCount: 0)
        }
        let chunkCount = stmt.int(at: 0)
        let newestChunkUpdatedAt = stmt.optionalDouble(at: 1).map(DatabaseHelpers.decodeDate)
        let status: String
        if chunkCount == 0 {
            status = "missing"
        } else if let item, let newestChunkUpdatedAt, newestChunkUpdatedAt < item.updatedAt {
            status = "stale"
        } else {
            status = "fresh"
        }
        return CiderItemSearchIndexFreshness(
            status: status,
            itemUpdatedAt: item?.updatedAt,
            newestChunkUpdatedAt: newestChunkUpdatedAt,
            chunkCount: chunkCount
        )
    }

    private func semanticUnavailableStatus() -> CiderItemSearchSemanticStatus {
        CiderItemSearchSemanticStatus(
            available: false,
            status: "unavailable",
            reason: "Semantic/vector recall is not configured for item search-debug yet.",
            mode: "supplemental",
            candidateCount: 0,
            candidates: [],
            requiresRebuild: true,
            safeNextCommands: [
                "cider-cli item doctor --json",
            ]
        )
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
        values += bundle.captureProvenance.map { provenance in
            if let surface = provenance.surface, let channel = provenance.channel {
                return "capture:\(surface)/\(channel)"
            }
            if let surface = provenance.surface {
                return "capture:\(surface)"
            }
            return "capture:\(provenance.sourceKind)"
        }
        if !bundle.enrichmentOutputs.isEmpty {
            values.append("enrichment_outputs:\(bundle.enrichmentOutputs.count)")
        }
        if !bundle.related.isEmpty {
            values.append("related:\(bundle.related.count)")
        }
        if !bundle.ownerRelations.isEmpty {
            values.append("owner_relations:\(bundle.ownerRelations.count)")
        }
        if !bundle.backlinks.isEmpty {
            values.append("backlinks:\(bundle.backlinks.count)")
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
        if let itemSurfacing = CiderSurfacingExplanationService.itemContextExplanation(for: bundle.item) {
            return itemSurfacing
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

    private func captureProvenance(from backlinks: [SecondBrainRelation]) throws -> [CiderItemCaptureProvenance] {
        let captureRelations = backlinks.filter {
            $0.sourceOwner.ownerType == "capture_event" && $0.relationType == "produced_item"
        }
        guard !captureRelations.isEmpty else { return [] }

        var provenance: [CiderItemCaptureProvenance] = []
        for relation in captureRelations {
            guard let event = try captureEvent(owner: relation.sourceOwner, relation: relation) else {
                continue
            }
            provenance.append(event)
        }
        return provenance.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.eventID < rhs.eventID
        }
    }

    private func captureEvent(
        owner: SecondBrainOwnerRef,
        relation: SecondBrainRelation
    ) throws -> CiderItemCaptureProvenance? {
        let stmt = try database.prepare("""
            SELECT id, source_kind, surface, channel, channel_id, thread_id, message_id,
                   sender_id, sender_name, source_url, source_file, source_text,
                   attachment_count, metadata, created_at
            FROM capture_events
            WHERE id = ?
            LIMIT 1;
            """)
        stmt.bind(owner.ownerID, at: 1)
        guard try stmt.step() else { return nil }

        return CiderItemCaptureProvenance(
            eventID: stmt.string(at: 0),
            owner: owner,
            sourceKind: stmt.string(at: 1),
            surface: stmt.optionalString(at: 2),
            channel: stmt.optionalString(at: 3),
            channelID: stmt.optionalString(at: 4),
            threadID: stmt.optionalString(at: 5),
            messageID: stmt.optionalString(at: 6),
            senderID: stmt.optionalString(at: 7),
            senderName: stmt.optionalString(at: 8),
            sourceURL: stmt.optionalString(at: 9),
            sourceFile: stmt.optionalString(at: 10),
            sourceText: stmt.optionalString(at: 11),
            attachmentCount: stmt.int(at: 12),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 13)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 14)),
            relation: relation
        )
    }

    private func safeCommands(for bundle: CiderItemContextBundle) -> [String] {
        let type = bundle.item.type.rawValue
        let id = bundle.item.id.uuidString
        var commands = [
            "cider-cli item get \(type) \(id) --json",
            "cider-cli item context \(type) \(id) --json",
            "cider-cli item related \(type) \(id) --json",
            "cider-cli item relations \(type) \(id) --json",
            "cider-cli item backlinks \(type) \(id) --json",
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
