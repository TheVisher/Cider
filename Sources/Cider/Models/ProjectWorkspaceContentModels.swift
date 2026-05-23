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
        let terms = project.referenceSearchTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return items.compactMap { item -> ProjectReferenceItem? in
            let ref = item.entityRef
            let linkedCardCount = linkedCounts[ref.id] ?? 0
            if linkedCardCount > 0 {
                return ProjectReferenceItem(
                    item: item,
                    ref: ref,
                    reason: "Linked to \(linkedCardCount) \(linkedCardCount == 1 ? "card" : "cards")",
                    linkedCardCount: linkedCardCount,
                    isLinkedToProjectCard: true
                )
            }

            guard let matchedTerm = terms.first(where: { matches($0, item: item) }) else { return nil }
            return ProjectReferenceItem(
                item: item,
                ref: ref,
                reason: "Matches \(displayTerm(matchedTerm))",
                linkedCardCount: 0,
                isLinkedToProjectCard: false
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

    private static func matches(_ term: String, item: LibraryItemV2) -> Bool {
        let normalizedTerm = normalizeSearch(term)
        return searchableText(for: item).contains { field in
            normalizeSearch(field).localizedStandardContains(normalizedTerm)
        }
    }

    private static func searchableText(for item: LibraryItemV2) -> [String] {
        switch item {
        case .bookmark(let bookmark):
            var fields = [bookmark.title, bookmark.urlString, bookmark.notes, bookmark.relativePath ?? ""]
            fields.append(contentsOf: bookmark.tags)
            if let ocr = bookmark.ocrText { fields.append(ocr) }
            return fields
        case .note(let note):
            return [note.title, note.content, note.summary ?? "", note.relativePath] + note.tags
        case .dateCard(let dateCard):
            return [dateCard.title, dateCard.details, dateCard.location]
        case .contact(let contact):
            return [contact.displayName, contact.relationshipLabel, contact.notes]
        case .todo(let todo):
            return [todo.title, todo.details] + todo.checklist.map(\.title)
        case .vaultFile(let file):
            var fields = [file.filename, file.displayTitle, file.relativePath, file.notes]
            fields.append(contentsOf: file.tags)
            if let ocr = file.ocrText { fields.append(ocr) }
            return fields
        }
    }

    private static func displayTerm(_ term: String) -> String {
        term
            .split(separator: " ")
            .map { word in
                if word.localizedCaseInsensitiveCompare("ios") == .orderedSame {
                    return "iOS"
                }
                guard let first = word.first else { return "" }
                return String(first).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    private static func normalizeSearch(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

struct ProjectWorkspaceOverviewModel: Equatable {
    let workspace: ProjectWorkspace
    let totals: ProjectWorkspaceCardTotals
    let boardSummaries: [ProjectWorkspaceBoardSummary]
    let projectRows: [ProjectWorkspaceProjectRow]
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

struct ProjectWorkspaceArtifactRow: Identifiable, Equatable {
    let owner: SecondBrainOwnerRef
    let title: String
    let relationType: String
    let evidence: String
    let safeCommand: String

    var id: String { "\(owner.canonicalRef):\(relationType)" }
}

struct ProjectWorkspaceNoteRow: Identifiable, Equatable {
    let note: Note
    let owner: SecondBrainOwnerRef
    let path: String

    var id: UUID { note.id }
    var title: String { note.title }
    var preview: String {
        let content = note.content.isEmpty ? note.resolvedContent : note.content
        return String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
    }
}

struct ProjectWorkspaceSurfaceModel: Equatable {
    let workspace: ProjectWorkspace
    let surface: ProjectWorkspaceSurface
    let notes: [ProjectWorkspaceNoteRow]
}

enum ProjectWorkspaceSurfaceProvider {
    private static let logger = Logger(subsystem: "com.cider.app", category: "ProjectWorkspaceSurface")

    static func model(
        for workspace: ProjectWorkspace,
        surface: ProjectWorkspaceSurface,
        notes: [Note]
    ) -> ProjectWorkspaceSurfaceModel {
        let rows: [ProjectWorkspaceNoteRow]
        switch surface {
        case .notes:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["note"],
                includeNilArtifactType: true
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
                allowedArtifactTypes: ["plan", "handoff"],
                includeNilArtifactType: false
            )
            logger.info("Project plans/handoffs surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        case .decisions:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["decision"],
                includeNilArtifactType: false
            )
            logger.info("Project decisions surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        case .qaAudits:
            rows = projectArtifactRows(
                for: workspace,
                notes: notes,
                allowedArtifactTypes: ["qa", "audit"],
                includeNilArtifactType: false
            )
            logger.info("Project QA/Audits surface model workspace=\(workspace.id, privacy: .public) renderedArtifacts=\(rows.count, privacy: .public) totalNotes=\(notes.count, privacy: .public)")
        default:
            rows = []
        }
        return ProjectWorkspaceSurfaceModel(workspace: workspace, surface: surface, notes: rows)
    }

    private static func projectArtifactRows(
        for workspace: ProjectWorkspace,
        notes: [Note],
        allowedArtifactTypes: Set<String>,
        includeNilArtifactType: Bool
    ) -> [ProjectWorkspaceNoteRow] {
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(workspace.id)
        return notes
            .filter { note in
                guard SecondBrainProjectGraphService.normalizedProjectID(note.projectID ?? "") == projectID else {
                    return false
                }
                guard let artifactType = note.artifactType?.localizedLowercase else {
                    return includeNilArtifactType
                }
                return allowedArtifactTypes.contains(artifactType)
            }
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { note in
                ProjectWorkspaceNoteRow(
                    note: note,
                    owner: SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString),
                    path: note.relativePath
                )
            }
    }
}

enum ProjectWorkspaceOverviewProvider {
    static func model(
        for workspace: ProjectWorkspace,
        catalog: ProjectWorkspaceCatalog,
        boards: [KanbanBoard],
        artifactRelations: [SecondBrainRelation] = []
    ) -> ProjectWorkspaceOverviewModel {
        let boardSummaries = scopedBoards(for: workspace, boards: boards)
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
            artifacts: artifactRows(from: artifactRelations, projectID: workspace.id),
            boardCreationActionTitle: workspace.kind == .project ? "New Board" : nil
        )
    }

    private static func scopedBoards(for workspace: ProjectWorkspace, boards: [KanbanBoard]) -> [KanbanBoard] {
        let scopedIDs = Set(workspace.boardIDs)
        return boards.filter { scopedIDs.contains($0.id) }
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
