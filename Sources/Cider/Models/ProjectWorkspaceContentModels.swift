import Foundation
import OSLog

struct ProjectReferenceItem: Identifiable, Equatable {
    let item: LibraryItemV2
    let ref: LibraryEntityRef
    let reason: String
    let linkedCardCount: Int
    let isLinkedToProjectCard: Bool

    var id: String { ref.id }
}

enum ProjectReferenceProvider {
    static func references(
        for project: ProjectWorkspace,
        items: [LibraryItemV2],
        boards: [KanbanBoard]
    ) -> [ProjectReferenceItem] {
        let projectBoards = boards.filter { project.boardIDs.contains($0.id) }
        let linkedCounts = linkedReferenceCounts(in: projectBoards)
        let assetsPrefix = projectAssetPrefix(for: project)

        return items.compactMap { item -> ProjectReferenceItem? in
            guard let relativePath = relativePath(for: item),
                  isPath(relativePath, inFolder: assetsPrefix) else {
                return nil
            }

            let ref = item.entityRef
            let linkedCardCount = linkedCounts[ref.id] ?? 0
            return ProjectReferenceItem(
                item: item,
                ref: ref,
                reason: assetsPrefix,
                linkedCardCount: linkedCardCount,
                isLinkedToProjectCard: linkedCardCount > 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.isLinkedToProjectCard != rhs.isLinkedToProjectCard {
                return lhs.isLinkedToProjectCard && !rhs.isLinkedToProjectCard
            }
            if lhs.linkedCardCount != rhs.linkedCardCount {
                return lhs.linkedCardCount > rhs.linkedCardCount
            }
            if lhs.item.updatedDate != rhs.item.updatedDate {
                return lhs.item.updatedDate > rhs.item.updatedDate
            }
            return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
        }
    }

    private static func linkedReferenceCounts(in boards: [KanbanBoard]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for board in boards {
            for card in board.allCards {
                for ref in card.linkedEntities {
                    counts[ref.id, default: 0] += 1
                }
            }
        }
        return counts
    }

    private static func projectAssetPrefix(for project: ProjectWorkspace) -> String {
        "Projects/\(project.title)/Assets"
    }

    private static func relativePath(for item: LibraryItemV2) -> String? {
        switch item {
        case .bookmark(let bookmark):
            bookmark.relativePath
        case .note(let note):
            note.relativePath
        case .vaultFile(let file):
            file.relativePath
        case .dateCard, .contact, .todo:
            nil
        }
    }

    private static func isPath(_ path: String, inFolder folder: String) -> Bool {
        path == folder || path.hasPrefix("\(folder)/")
    }

}

struct ProjectWorkspaceOverviewModel: Equatable {
    let workspace: ProjectWorkspace
    let totals: ProjectWorkspaceCardTotals
    let boardSummaries: [ProjectWorkspaceBoardSummary]
    let projectRows: [ProjectWorkspaceProjectRow]
    let resources: [ProjectWorkspaceResourceRow]
    let latestUpdate: ProjectWorkspaceLatestUpdate?
    let milestoneRows: [ProjectWorkspaceMilestoneRow]
    let recentArtifacts: [ProjectWorkspaceCoreDocRow]
    let artifacts: [ProjectWorkspaceArtifactRow]
    let boardCreationActionTitle: String?
}

struct ProjectWorkspaceCardTotals: Equatable {
    var queued = 0
    var inProgress = 0
    var testing = 0
    var blocked = 0
    var total = 0
}

struct ProjectWorkspaceBoardSummary: Identifiable, Equatable {
    let boardID: String
    let boardName: String
    let totals: ProjectWorkspaceCardTotals

    var id: String { boardID }
}

struct ProjectWorkspaceProjectRow: Identifiable, Equatable {
    let projectID: String
    let title: String
    let subtitle: String
    let totals: ProjectWorkspaceCardTotals

    var id: String { projectID }
}

struct ProjectWorkspaceResourceRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL
}

struct ProjectWorkspaceCoreDocRow: Identifiable, Equatable {
    let id: String
    let title: String
    let relativePath: String
    let modifiedAt: Date
    let lineCount: Int
    let wordCount: Int
    let fileURL: URL
}

struct ProjectWorkspaceArtifactRow: Identifiable, Equatable {
    let owner: SecondBrainOwnerRef
    let title: String
    let relationType: String
    let evidence: String
    let safeCommand: String

    var id: String { "\(owner.canonicalRef):\(relationType)" }
}

struct ProjectWorkspaceLatestUpdate: Identifiable, Equatable {
    let boardID: String
    let boardName: String
    let cardID: String
    let cardDisplayKey: String
    let cardTitle: String
    let entryID: String
    let typeLabel: String
    let body: String
    let author: String?
    let createdAt: Date
    let symbolName: String

    var id: String { "\(boardID):\(cardID):\(entryID)" }
}

struct ProjectWorkspaceMilestoneRow: Identifiable, Equatable {
    let boardID: String
    let boardName: String
    let cardID: String
    let cardDisplayKey: String
    let title: String
    let tags: [String]
    let description: String
    let status: String
    let progressText: String?
    let completedChildCount: Int
    let childCount: Int
    let progressFraction: Double
    let artifactLinks: [ProjectWorkspaceMilestoneArtifactLink]
    let updatedAt: Date

    var id: String { "\(boardID):\(cardID)" }
}

struct ProjectWorkspaceMilestoneArtifactLink: Identifiable, Equatable {
    let owner: SecondBrainOwnerRef
    let title: String
    let artifactType: String
    let relationType: String

    var id: String { "\(owner.canonicalRef):\(relationType)" }

    var displayType: String {
        switch artifactType.localizedLowercase {
        case "qa", "audit":
            return "QA"
        case "plan":
            return "Plan"
        case "decision":
            return "Decision"
        default:
            return artifactType.split(separator: "-")
                .map { part in
                    guard let first = part.first else { return "" }
                    return first.uppercased() + part.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}

struct ProjectWorkspaceNoteRow: Identifiable, Equatable {
    let id: UUID
    let note: Note
    let owner: SecondBrainOwnerRef
    let path: String
    let linkedCardLabels: [String]
    let agentLabels: [String]
    let planMetadata: ProjectPlanMetadata?

    init(
        note: Note,
        owner: SecondBrainOwnerRef,
        path: String,
        linkedCardLabels: [String] = [],
        agentLabels: [String] = [],
        planMetadata: ProjectPlanMetadata? = nil
    ) {
        self.id = note.id
        self.note = note
        self.owner = owner
        self.path = path
        self.linkedCardLabels = linkedCardLabels
        self.agentLabels = agentLabels
        self.planMetadata = planMetadata
    }

    var title: String { note.title }
    var preview: String {
        let content = note.content.isEmpty ? note.resolvedContent : note.content
        return String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
    }

    var relationSummary: String {
        var parts: [String] = []
        if !linkedCardLabels.isEmpty {
            let cardSummaries = linkedCardLabels.map { label in
                guard let separatorRange = label.range(of: ": ") else { return label }
                let cardID = String(label[..<separatorRange.lowerBound])
                let relationNames = String(label[separatorRange.upperBound...])
                return "\(cardID) (\(relationNames))"
            }
            parts.append("cards: \(cardSummaries.joined(separator: ", "))")
        }
        if !agentLabels.isEmpty {
            parts.append("agents: \(agentLabels.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}

enum ProjectPlanScope: String, CaseIterable, Equatable, Identifiable {
    case active
    case parkedIdeas
    case templates
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .parkedIdeas: return "Parked"
        case .templates: return "Templates"
        case .all: return "All"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "list.bullet.clipboard"
        case .parkedIdeas: return "archivebox"
        case .templates: return "doc.on.doc"
        case .all: return "tray.full"
        }
    }

    func includes(_ metadata: ProjectPlanMetadata?) -> Bool {
        switch self {
        case .active:
            return metadata?.isActive ?? true
        case .parkedIdeas:
            return metadata?.isIdeaPlan == true && metadata?.isParked == true
        case .templates:
            return metadata?.isTemplate == true
        case .all:
            return true
        }
    }
}

struct ProjectWorkspaceSurfaceModel: Equatable {
    let workspace: ProjectWorkspace
    let surface: ProjectWorkspaceSurface
    let notes: [ProjectWorkspaceNoteRow]
}

enum ProjectWorkspaceSurfaceDisplayMode: String, CaseIterable, Equatable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum ProjectWorkspaceSurfaceProvider {
    private static let logger = Logger(subsystem: "com.cider.app", category: "ProjectWorkspaceSurface")

    static func model(
        for workspace: ProjectWorkspace,
        surface: ProjectWorkspaceSurface,
        notes: [Note],
        artifactRelations: [SecondBrainRelation] = [],
        planScope: ProjectPlanScope = .active
    ) -> ProjectWorkspaceSurfaceModel {
        let rows: [ProjectWorkspaceNoteRow]
        switch surface {
        case .milestones:
            rows = []
        case .notes:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["note"],
                includeNilArtifactType: true,
                requiredFolderName: "Notes",
                artifactRelations: artifactRelations
            )
            let projectID = SecondBrainProjectGraphService.normalizedProjectID(workspace.id)
            let candidateCount = notes.filter { note in
                SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID
            }.count
            logger.info("Project notes surface model workspace=\(workspace.id, privacy: .public) candidateProjectNotes=\(candidateCount, privacy: .public) renderedNotes=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        case .plansHandoffs:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["plan"],
                includeNilArtifactType: false,
                requiredFolderName: "Plans",
                artifactRelations: artifactRelations,
                planScope: planScope
            )
            logger.info("Project plans/handoffs surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        case .decisions:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["decision"],
                includeNilArtifactType: false,
                requiredFolderName: "Decisions",
                artifactRelations: artifactRelations
            )
            logger.info("Project decisions surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        case .qaAudits:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["qa", "audit"],
                includeNilArtifactType: false,
                requiredFolderName: "QA",
                artifactRelations: artifactRelations
            )
            logger.info("Project QA/Audits surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        default:
            rows = []
        }
        return ProjectWorkspaceSurfaceModel(workspace: workspace, surface: surface, notes: rows)
    }

    @MainActor
    static func artifactRelations(for notes: [Note], database: CiderDatabase = .shared) -> [SecondBrainRelation] {
        let store = SecondBrainStore(database: database)
        return notes.flatMap { note in
            let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
            return (try? store.relatedRelations(for: owner)) ?? []
        }
    }

    private static func projectArtifactRows(
        for workspace: ProjectWorkspace,
        notes: [Note],
        allowedArtifactTypes: Set<String>,
        includeNilArtifactType: Bool,
        requiredFolderName: String? = nil,
        artifactRelations: [SecondBrainRelation],
        planScope: ProjectPlanScope? = nil
    ) -> [ProjectWorkspaceNoteRow] {
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(workspace.id)
        let relationsBySourceOwner = Dictionary(grouping: artifactRelations, by: \.sourceOwner)
        return notes
            .filter { note in
                guard SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID else {
                    return false
                }
                if let requiredFolderName {
                    let folder = "Projects/\(workspace.title)/\(requiredFolderName)"
                    guard note.relativePath == folder || note.relativePath.hasPrefix("\(folder)/") else {
                        return false
                    }
                }
                guard let artifactType = note.artifactType?.localizedLowercase else {
                    return includeNilArtifactType
                }
                guard allowedArtifactTypes.contains(artifactType) else { return false }
                if artifactType == "plan", let planScope {
                    return planScope.includes(note.projectPlanMetadata)
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { note in
                let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
                let relations = relationsBySourceOwner[owner] ?? []
                return ProjectWorkspaceNoteRow(
                    note: note,
                    owner: owner,
                    path: note.relativePath,
                    linkedCardLabels: linkedCardLabels(from: relations),
                    agentLabels: agentLabels(from: relations),
                    planMetadata: note.projectPlanMetadata
                )
            }
    }

    private static func linkedCardLabels(from relations: [SecondBrainRelation]) -> [String] {
        var cardOrder: [String] = []
        var relationNamesByCardID: [String: [String]] = [:]
        var seenRelationNamesByCardID: [String: Set<String>] = [:]

        for relation in relations where relation.targetOwner.ownerType == "kanban_card" {
            let cardID = relation.targetOwner.ownerID.split(separator: "/").last.map(String.init) ?? relation.targetOwner.ownerID
            if relationNamesByCardID[cardID] == nil {
                cardOrder.append(cardID)
                relationNamesByCardID[cardID] = []
                seenRelationNamesByCardID[cardID] = []
            }

            let relationName = ProjectArtifactRelationType.displayName(for: relation.relationType)
            guard seenRelationNamesByCardID[cardID]?.contains(relationName) != true else { continue }
            seenRelationNamesByCardID[cardID]?.insert(relationName)
            relationNamesByCardID[cardID]?.append(relationName)
        }

        return cardOrder.compactMap { cardID in
            guard let relationNames = relationNamesByCardID[cardID], !relationNames.isEmpty else { return nil }
            return "\(cardID): \(relationNames.joined(separator: ", "))"
        }
    }

    private static func agentLabels(from relations: [SecondBrainRelation]) -> [String] {
        var seen: Set<String> = []
        var labels: [String] = []
        for actor in relations.map(\.actor) {
            let label = actor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !seen.contains(label) else { continue }
            seen.insert(label)
            labels.append(label)
        }
        return labels
    }
}

enum ProjectWorkspaceOverviewProvider {
    static func model(
        for workspace: ProjectWorkspace,
        catalog: ProjectWorkspaceCatalog,
        boards: [KanbanBoard],
        artifactRelations: [SecondBrainRelation] = [],
        coreDocsRoot: URL? = nil
    ) -> ProjectWorkspaceOverviewModel {
        let workspaceBoards = scopedBoards(for: workspace, boards: boards)
        let artifacts = artifactRows(from: artifactRelations, projectID: workspace.id)
        let resources = resourceRows(for: workspace)
        let coreDocs = coreDocRows(root: coreDocsRoot)
        let boardSummaries = workspaceBoards
            .map { board in
                ProjectWorkspaceBoardSummary(
                    boardID: board.id,
                    boardName: board.name,
                    totals: totals(for: board)
                )
            }
        let projectRows: [ProjectWorkspaceProjectRow]
        if workspace.kind == .home {
            projectRows = catalog.activeProjects.map { project in
                let totals = aggregate(
                    scopedBoards(for: project, boards: boards).map { self.totals(for: $0) }
                )
                return ProjectWorkspaceProjectRow(
                    projectID: project.id,
                    title: project.title,
                    subtitle: project.subtitle,
                    totals: totals
                )
            }
        } else {
            projectRows = []
        }

        return ProjectWorkspaceOverviewModel(
            workspace: workspace,
            totals: aggregate(boardSummaries.map(\.totals)),
            boardSummaries: boardSummaries,
            projectRows: projectRows,
            resources: resources,
            latestUpdate: latestUpdate(from: workspaceBoards),
            milestoneRows: milestoneRows(from: workspaceBoards, artifactRelations: artifactRelations, limit: 5),
            recentArtifacts: Array(coreDocs.prefix(9)),
            artifacts: artifacts,
            boardCreationActionTitle: workspace.kind == .project ? "New Board" : nil
        )
    }

    private static func scopedBoards(for workspace: ProjectWorkspace, boards: [KanbanBoard]) -> [KanbanBoard] {
        let scopedIDs = Set(workspace.boardIDs)
        return boards.filter { scopedIDs.contains($0.id) }
    }

    static func milestoneRows(
        for workspace: ProjectWorkspace,
        boards: [KanbanBoard],
        artifactRelations: [SecondBrainRelation] = []
    ) -> [ProjectWorkspaceMilestoneRow] {
        milestoneRows(
            from: scopedBoards(for: workspace, boards: boards),
            artifactRelations: artifactRelations,
            limit: nil
        )
    }

    private static func totals(for board: KanbanBoard) -> ProjectWorkspaceCardTotals {
        var result = ProjectWorkspaceCardTotals()
        for column in board.columns {
            let cards = column.cards
            result.total += cards.count
            switch columnKind(for: column) {
            case .queued:
                result.queued += cards.count
            case .inProgress:
                result.inProgress += cards.count
            case .testing:
                result.testing += cards.count
            case .other:
                break
            }
            result.blocked += cards.filter(isBlocked).count
        }
        return result
    }

    private static func aggregate(_ totals: [ProjectWorkspaceCardTotals]) -> ProjectWorkspaceCardTotals {
        totals.reduce(ProjectWorkspaceCardTotals()) { partial, next in
            ProjectWorkspaceCardTotals(
                queued: partial.queued + next.queued,
                inProgress: partial.inProgress + next.inProgress,
                testing: partial.testing + next.testing,
                blocked: partial.blocked + next.blocked,
                total: partial.total + next.total
            )
        }
    }

    private enum ColumnKind {
        case queued
        case inProgress
        case testing
        case other
    }

    private static func columnKind(for column: KanbanColumn) -> ColumnKind {
        let name = column.name.localizedLowercase
        if name.contains("test") || name.contains("qa") || name.contains("review") {
            return .testing
        }
        if name.contains("progress") || name.contains("doing") || name.contains("active") {
            return .inProgress
        }
        if name.contains("queued") || name.contains("backlog") || name.contains("ready") || name.contains("next") {
            return .queued
        }
        return .other
    }

    private static func isBlocked(_ card: KanbanCard) -> Bool {
        if card.tags.contains(where: { $0.localizedCaseInsensitiveContains("blocked") }) {
            return true
        }
        let text = [card.title, card.notes ?? "", card.aiSummary ?? ""].joined(separator: " ")
        return text.localizedCaseInsensitiveContains("blocked")
            || text.localizedCaseInsensitiveContains("blocker")
    }

    private static func latestUpdate(from boards: [KanbanBoard]) -> ProjectWorkspaceLatestUpdate? {
        let candidates = boards.flatMap { board in
            board.allCards.flatMap { card in
                card.historyEntries.compactMap { entry -> ProjectWorkspaceLatestUpdate? in
                    let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { return nil }
                    return ProjectWorkspaceLatestUpdate(
                        boardID: board.id,
                        boardName: board.name,
                        cardID: card.id,
                        cardDisplayKey: board.displayKey(for: card),
                        cardTitle: card.title,
                        entryID: entry.id,
                        typeLabel: entry.type.displayName,
                        body: body,
                        author: entry.author,
                        createdAt: entry.createdAt,
                        symbolName: entry.type.symbolName
                    )
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }.first
    }

    private static func milestoneRows(
        from boards: [KanbanBoard],
        artifactRelations: [SecondBrainRelation],
        limit: Int?
    ) -> [ProjectWorkspaceMilestoneRow] {
        let artifactLinksByCardRef = milestoneArtifactLinksByCardRef(from: artifactRelations)
        let candidates = boards.flatMap { board in
            board.columns.flatMap { column in
                column.cards.compactMap { card -> (row: ProjectWorkspaceMilestoneRow, rank: Int)? in
                    guard let summary = KanbanBoardLayout.childSummary(for: card.id, in: board),
                          summary.totalCount > 0 else {
                        return nil
                    }

                    let latestActivityAt = ([card.updatedAt, card.completed, Optional(card.created)] + card.historyEntries.map { Optional($0.createdAt) })
                        .compactMap { $0 }
                        .max() ?? card.created
                    return (
                        ProjectWorkspaceMilestoneRow(
                            boardID: board.id,
                            boardName: board.name,
                            cardID: card.id,
                            cardDisplayKey: board.displayKey(for: card),
                            title: card.title,
                            tags: card.tags,
                            description: milestoneDescription(for: card),
                            status: column.name,
                            progressText: summary.progressText,
                            completedChildCount: summary.doneCount,
                            childCount: summary.totalCount,
                            progressFraction: Double(summary.doneCount) / Double(summary.totalCount),
                            artifactLinks: artifactLinksByCardRef["\(board.id)/\(card.id)"] ?? [],
                            updatedAt: latestActivityAt
                        ),
                        statusRank(for: column)
                    )
                }
            }
        }

        let explicitMilestones = candidates.filter { isExplicitMilestone($0.row) }
        let source = explicitMilestones.isEmpty ? candidates : explicitMilestones

        let sortedRows = source.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.row.updatedAt != rhs.row.updatedAt { return lhs.row.updatedAt > rhs.row.updatedAt }
            return lhs.row.id < rhs.row.id
        }
        .map(\.row)

        if let limit {
            return Array(sortedRows.prefix(limit))
        }
        return sortedRows
    }

    private static func isExplicitMilestone(_ row: ProjectWorkspaceMilestoneRow) -> Bool {
        row.tags.contains { $0.localizedCaseInsensitiveCompare("milestone-object") == .orderedSame }
            || row.title.localizedCaseInsensitiveContains("milestone:")
    }

    private static func milestoneDescription(for card: KanbanCard) -> String {
        let text = (card.notes ?? card.aiSummary ?? "")
            .replacingOccurrences(of: "\\n", with: "\n")
        let sections = KanbanCardSectionParser.sections(from: text)
        let preferredKeys = ["goal", "problem", "mvp_scope", "scope"]
        for key in preferredKeys {
            if let section = sections.first(where: { $0.key == key }) {
                let cleaned = cleanedMilestoneDescription(section.body)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return cleanedMilestoneDescription(text)
    }

    private static func cleanedMilestoneDescription(_ raw: String) -> String {
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("-")
                    && !line.localizedCaseInsensitiveContains("non-goals")
                    && !line.localizedCaseInsensitiveContains("acceptance criteria")
            }
        let joined = lines.joined(separator: " ")
        return String(joined.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func milestoneArtifactLinksByCardRef(
        from relations: [SecondBrainRelation]
    ) -> [String: [ProjectWorkspaceMilestoneArtifactLink]] {
        var linksByCardRef: [String: [ProjectWorkspaceMilestoneArtifactLink]] = [:]
        for relation in relations {
            let pair: (note: SecondBrainOwnerRef, card: SecondBrainOwnerRef)?
            if relation.sourceOwner.ownerType == "note", relation.targetOwner.ownerType == "kanban_card" {
                pair = (relation.sourceOwner, relation.targetOwner)
            } else if relation.targetOwner.ownerType == "note", relation.sourceOwner.ownerType == "kanban_card" {
                pair = (relation.targetOwner, relation.sourceOwner)
            } else {
                pair = nil
            }
            guard let pair else { continue }

            let artifactType = relation.metadata["artifactType"] ?? relation.metadata["artifact_type"] ?? "note"
            guard ["plan", "qa", "audit", "decision"].contains(artifactType.localizedLowercase) else {
                continue
            }
            let link = ProjectWorkspaceMilestoneArtifactLink(
                owner: pair.note,
                title: artifactTitle(for: pair.note, relation: relation),
                artifactType: artifactType,
                relationType: relation.relationType
            )
            linksByCardRef[pair.card.ownerID, default: []].append(link)
        }

        return linksByCardRef.mapValues { links in
            var seen: Set<String> = []
            return links.filter { link in
                seen.insert(link.id).inserted
            }
            .sorted { lhs, rhs in
                if lhs.artifactType != rhs.artifactType {
                    return lhs.artifactType < rhs.artifactType
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func statusRank(for column: KanbanColumn) -> Int {
        if column.isDoneLikeColumn { return 4 }
        switch columnKind(for: column) {
        case .inProgress: return 0
        case .queued: return 1
        case .testing: return 2
        case .other: return 3
        }
    }

    private static func resourceRows(for workspace: ProjectWorkspace) -> [ProjectWorkspaceResourceRow] {
        guard workspace.id == "cider" else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ProjectWorkspaceResourceRow(
                id: "github",
                title: "GitHub Repository",
                subtitle: "TheVisher/Cider",
                systemImage: "chevron.left.forwardslash.chevron.right",
                url: URL(string: "https://github.com/TheVisher/Cider")!
            ),
            ProjectWorkspaceResourceRow(
                id: "local-repo",
                title: "Local Repository",
                subtitle: "~/Cider",
                systemImage: "folder",
                url: home.appendingPathComponent("Cider", isDirectory: true)
            ),
            ProjectWorkspaceResourceRow(
                id: "vault",
                title: "Cider Vault",
                subtitle: "~/CiderVault",
                systemImage: "externaldrive",
                url: home.appendingPathComponent("CiderVault", isDirectory: true)
            )
        ]
    }

    private static func coreDocRows(root explicitRoot: URL?) -> [ProjectWorkspaceCoreDocRow] {
        guard let docsRoot = explicitRoot ?? defaultDocsRoot() else { return [] }
        let docs = [
            "PRODUCT.md",
            "FEATURES.md",
            "ARCHITECTURE.md",
            "STORAGE.md",
            "AGENT.md",
            "CLI.md",
            "QA.md",
            "DESIGN.md",
            "CONVENTIONS.md",
        ]

        return docs.compactMap { filename in
            let url = docsRoot.appendingPathComponent(filename)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let modifiedAt = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .distantPast
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).count
            let words = content.split { $0.isWhitespace || $0.isNewline }.count
            return ProjectWorkspaceCoreDocRow(
                id: filename,
                title: filename.replacingOccurrences(of: ".md", with: ""),
                relativePath: "Docs/\(filename)",
                modifiedAt: modifiedAt,
                lineCount: lines,
                wordCount: words,
                fileURL: url
            )
        }
    }

    private static func defaultDocsRoot() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            ProcessInfo.processInfo.environment["CIDER_REPO_PATH"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            home.appendingPathComponent("Cider", isDirectory: true),
        ].compactMap { $0 }

        return candidates
            .map { $0.appendingPathComponent("Docs", isDirectory: true) }
            .first { fileManager.fileExists(atPath: $0.appendingPathComponent("INDEX.md").path) }
    }

    private static func artifactRows(
        from relations: [SecondBrainRelation],
        projectID: String
    ) -> [ProjectWorkspaceArtifactRow] {
        let projectOwner = SecondBrainProjectGraphService.owner(projectID: projectID)
        return relations.map { relation in
            let owner = relation.sourceOwner == projectOwner ? relation.targetOwner : relation.sourceOwner
            return ProjectWorkspaceArtifactRow(
                owner: owner,
                title: artifactTitle(for: owner, relation: relation),
                relationType: relation.relationType,
                evidence: relation.evidence,
                safeCommand: "cider-cli item context \(owner.ownerType) \(owner.ownerID) --json"
            )
        }
        .sorted { lhs, rhs in
            if lhs.title.localizedCaseInsensitiveCompare(rhs.title) != .orderedSame {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.owner.canonicalRef < rhs.owner.canonicalRef
        }
    }

    private static func artifactTitle(for owner: SecondBrainOwnerRef, relation: SecondBrainRelation) -> String {
        let metadataKeys = ["title", "card_title", "name", "filename", "path"]
        for key in metadataKeys {
            if let value = relation.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return owner.canonicalRef
    }
}

extension LibraryItemV2 {
    var entityRef: LibraryEntityRef {
        switch self {
        case .bookmark(let bookmark):
            return LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        case .note(let note):
            return LibraryEntityRef(type: .note, entityID: note.id)
        case .dateCard(let dateCard):
            return LibraryEntityRef(type: .dateCard, entityID: dateCard.id)
        case .contact(let contact):
            return LibraryEntityRef(type: .contact, entityID: contact.id)
        case .todo(let todo):
            return LibraryEntityRef(type: .todo, entityID: todo.id)
        case .vaultFile(let file):
            return LibraryEntityRef(type: .vaultFile, entityID: file.id)
        }
    }
}
