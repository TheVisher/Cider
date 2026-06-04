import Foundation

enum CiderRecallCapability: String, CaseIterable, Codable, Hashable {
    case lookup
    case context
    case related
    case reminderSurfacing
}

struct CiderRecallProbe: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var query: String
    var expectedRef: LibraryEntityRef
    var expectedRelatedRefs: [LibraryEntityRef]
    var expectsSurfaceToday: Bool?

    init(
        id: String,
        title: String,
        query: String,
        expectedRef: LibraryEntityRef,
        expectedRelatedRefs: [LibraryEntityRef] = [],
        expectsSurfaceToday: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.expectedRef = expectedRef
        self.expectedRelatedRefs = expectedRelatedRefs
        self.expectsSurfaceToday = expectsSurfaceToday
    }
}

struct CiderRecallProbeCheck: Equatable {
    var capability: CiderRecallCapability
    var passed: Bool
    var detail: String
}

struct CiderRecallTopResult: Equatable {
    var rank: Int
    var score: Double
    var kind: CiderItemSearchResultKind
    var owner: SecondBrainOwnerRef
    var title: String
    var snippet: String
    var stage: String?
    var matchedQuery: String?
    var rankFactors: [String]
    var matchedExpected: Bool
}

struct CiderRecallProbeResult: Equatable, Identifiable {
    var id: String { probe.id }
    var probe: CiderRecallProbe
    var checks: [CiderRecallProbeCheck]
    var topResults: [CiderRecallTopResult]

    var passed: Bool {
        checks.allSatisfy(\.passed)
    }
}

struct CiderRecallCapabilityScore: Equatable {
    var capability: CiderRecallCapability
    var passed: Int
    var failed: Int

    var total: Int { passed + failed }
}

struct CiderRecallScorecard: Equatable {
    var generatedAt: Date
    var results: [CiderRecallProbeResult]
    var capabilityScores: [CiderRecallCapability: CiderRecallCapabilityScore]

    var totalProbeCount: Int { results.count }
    var passedProbeCount: Int { results.filter(\.passed).count }
    var failedProbeCount: Int { totalProbeCount - passedProbeCount }
    var passRate: Double {
        guard totalProbeCount > 0 else { return 0 }
        return Double(passedProbeCount) / Double(totalProbeCount)
    }
}

@MainActor
final class CiderRecallScorecardService {
    private let database: CiderDatabase
    private let linkService: ItemLinkService
    private let secondBrainStore: SecondBrainStore
    private let contextService: CiderItemContextService
    private let todoProvider: () -> [TodoCard]
    private let dateCardProvider: () -> [DateCard]
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        database: CiderDatabase = .shared,
        linkService: ItemLinkService? = nil,
        secondBrainStore: SecondBrainStore? = nil,
        todoProvider: @escaping () -> [TodoCard] = { TodoCardStorage.shared.todoCards },
        dateCardProvider: @escaping () -> [DateCard] = { DateCardStorage.shared.dateCards },
        nowProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.database = database
        self.linkService = linkService ?? ItemLinkService(database: database)
        self.secondBrainStore = secondBrainStore ?? SecondBrainStore(database: database)
        self.todoProvider = todoProvider
        self.dateCardProvider = dateCardProvider
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.contextService = CiderItemContextService(
            database: database,
            linkService: self.linkService,
            secondBrainStore: self.secondBrainStore,
            todoProvider: todoProvider,
            dateCardProvider: dateCardProvider,
            nowProvider: nowProvider
        )
    }

    func evaluate(probes: [CiderRecallProbe], searchLimit: Int = 5) throws -> CiderRecallScorecard {
        let normalizedLimit = max(1, searchLimit)
        let results = try probes.map { probe in
            try evaluate(probe: probe, searchLimit: normalizedLimit)
        }
        return CiderRecallScorecard(
            generatedAt: nowProvider(),
            results: results,
            capabilityScores: capabilityScores(for: results)
        )
    }

    func suggestedProbes(limit: Int = 12) throws -> [CiderRecallProbe] {
        let stmt = try database.prepare("""
            SELECT id, type, title
            FROM items
            WHERE TRIM(title) <> ''
            ORDER BY updated_at DESC, title COLLATE NOCASE ASC
            LIMIT ?;
            """)
        stmt.bind(max(1, limit), at: 1)

        var probes: [CiderRecallProbe] = []
        while try stmt.step() {
            guard let id = UUID(uuidString: stmt.string(at: 0)),
                  let type = libraryEntityType(fromDatabaseType: stmt.string(at: 1)) else {
                continue
            }
            let title = stmt.string(at: 2)
            let ref = LibraryEntityRef(type: type, entityID: id)
            let related = (try? linkService.relatedRefs(for: ref)) ?? []
            probes.append(
                CiderRecallProbe(
                    id: "item-\(id.uuidString)",
                    title: "Recall \(title)",
                    query: title,
                    expectedRef: ref,
                    expectedRelatedRefs: Array(related.prefix(3)),
                    expectsSurfaceToday: reminderSurfaceToday(for: ref)
                )
            )
        }
        return probes
    }

    func evaluateSuggested(limit: Int = 12, searchLimit: Int = 5) throws -> CiderRecallScorecard {
        try evaluate(probes: suggestedProbes(limit: limit), searchLimit: searchLimit)
    }

    private func evaluate(probe: CiderRecallProbe, searchLimit: Int) throws -> CiderRecallProbeResult {
        let searchResults = try contextService.search(probe.query, limit: searchLimit)
        let topResults = searchResults.enumerated().map { index, result in
            CiderRecallTopResult(
                rank: index + 1,
                score: result.rank,
                kind: result.kind,
                owner: result.owner,
                title: result.title,
                snippet: result.snippet,
                stage: result.stage,
                matchedQuery: result.matchedQuery,
                rankFactors: result.rankFactors,
                matchedExpected: matchesExpected(result, expectedRef: probe.expectedRef)
            )
        }

        var checks: [CiderRecallProbeCheck] = [
            CiderRecallProbeCheck(
                capability: .lookup,
                passed: topResults.contains(where: \.matchedExpected),
                detail: topResults.contains(where: \.matchedExpected)
                    ? "expected item found"
                    : "expected \(probe.expectedRef.type.rawValue):\(probe.expectedRef.entityID.uuidString) not in top \(searchLimit)"
            )
        ]

        let context: CiderItemContextBundle?
        do {
            context = try contextService.context(for: probe.expectedRef)
            checks.append(
                CiderRecallProbeCheck(
                    capability: .context,
                    passed: true,
                    detail: "context retrieved"
                )
            )
        } catch {
            context = nil
            checks.append(
                CiderRecallProbeCheck(
                    capability: .context,
                    passed: false,
                    detail: error.localizedDescription
                )
            )
        }

        if !probe.expectedRelatedRefs.isEmpty {
            let relatedIDs = Set((context?.related ?? []).map(\.ref.id))
            let missing = probe.expectedRelatedRefs.filter { !relatedIDs.contains($0.id) }
            checks.append(
                CiderRecallProbeCheck(
                    capability: .related,
                    passed: missing.isEmpty,
                    detail: missing.isEmpty
                        ? "expected related refs found"
                        : "missing related refs: \(missing.map { "\($0.type.rawValue):\($0.entityID.uuidString)" }.joined(separator: ", "))"
                )
            )
        }

        if let expectedSurfaceToday = probe.expectsSurfaceToday {
            let actualSurfaceToday = reminderSurfaceToday(for: probe.expectedRef)
            checks.append(
                CiderRecallProbeCheck(
                    capability: .reminderSurfacing,
                    passed: actualSurfaceToday == expectedSurfaceToday,
                    detail: actualSurfaceToday.map { "surfaceToday=\($0)" } ?? "no reminder surfacing"
                )
            )
        }

        return CiderRecallProbeResult(probe: probe, checks: checks, topResults: topResults)
    }

    private func capabilityScores(for results: [CiderRecallProbeResult]) -> [CiderRecallCapability: CiderRecallCapabilityScore] {
        var scores: [CiderRecallCapability: CiderRecallCapabilityScore] = [:]
        for capability in CiderRecallCapability.allCases {
            scores[capability] = CiderRecallCapabilityScore(capability: capability, passed: 0, failed: 0)
        }
        for check in results.flatMap(\.checks) {
            var score = scores[check.capability] ?? CiderRecallCapabilityScore(capability: check.capability, passed: 0, failed: 0)
            if check.passed {
                score.passed += 1
            } else {
                score.failed += 1
            }
            scores[check.capability] = score
        }
        return scores
    }

    private func matchesExpected(_ result: CiderItemSearchResult, expectedRef: LibraryEntityRef) -> Bool {
        if result.item?.id == expectedRef.entityID && result.item?.type == expectedRef.type {
            return true
        }
        return result.owner == owner(for: expectedRef)
    }

    private func reminderSurfaceToday(for ref: LibraryEntityRef) -> Bool? {
        let itemType: CiderReminderRelevanceItem.ItemType
        switch ref.type {
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
            now: nowProvider(),
            calendar: calendar
        )
        .first { $0.itemType == itemType && $0.id == ref.entityID }?
        .surfaceToday
    }

    private func owner(for ref: LibraryEntityRef) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: ref.type.rawValue, ownerID: ref.entityID.uuidString)
    }

    private func libraryEntityType(fromDatabaseType raw: String) -> LibraryEntityType? {
        let normalized = raw == "event" ? "dateCard" : raw
        guard let type = LibraryEntityType(rawValue: normalized),
              LibraryEntityType.activeCases.contains(type) else {
            return nil
        }
        return type
    }
}
