import Foundation

struct SecondBrainProject: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var status: String
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var owner: SecondBrainOwnerRef {
        SecondBrainProjectGraphService.owner(projectID: id)
    }
}

struct SecondBrainProjectContext: Equatable {
    var project: SecondBrainProject
    var owner: SecondBrainOwnerRef
    var sections: [SecondBrainSection]
    var outgoingRelations: [SecondBrainRelation]
    var backlinks: [SecondBrainRelation]
    var artifactRelations: [SecondBrainRelation]
    var artifactOwners: [SecondBrainOwnerRef]
    var boardOwners: [SecondBrainOwnerRef]
    var cardOwners: [SecondBrainOwnerRef]
    var safeCommands: [String]
    var readOnly: Bool = true
    var changed: Bool = false
    var mutationReason: String? = nil
}

@MainActor
final class SecondBrainProjectGraphService {
    static let workspaceSource = "project_workspace"

    private let database: CiderDatabase
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
    }

    nonisolated static func owner(projectID: String) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: "project", ownerID: normalizedProjectID(projectID))
    }

    nonisolated static func normalizedProjectID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .localizedLowercase
    }

    @discardableResult
    func upsertProject(
        id rawID: String,
        title: String,
        subtitle: String = "",
        status: String = "active",
        metadata: [String: String] = [:]
    ) throws -> SecondBrainProject {
        let id = Self.normalizedProjectID(rawID)
        let now = Date()
        let existing = try project(id: id)
        let project = SecondBrainProject(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : title,
            subtitle: subtitle,
            status: status,
            metadata: metadata,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        try database.withTransaction {
            let stmt = try database.prepare("""
                INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    subtitle = excluded.subtitle,
                    status = excluded.status,
                    metadata = excluded.metadata,
                    updated_at = excluded.updated_at;
                """)
            stmt.bind(project.id, at: 1)
                .bind(project.title, at: 2)
                .bind(project.subtitle, at: 3)
                .bind(project.status, at: 4)
                .bind(DatabaseHelpers.encodeJSON(project.metadata) ?? "{}", at: 5)
                .bind(DatabaseHelpers.encode(project.createdAt), at: 6)
                .bind(DatabaseHelpers.encode(project.updatedAt), at: 7)
            try stmt.step()
            _ = try SecondBrainOwnerLabelIndexService(database: database).refreshProject(id: project.id)
        }
        return project
    }

    func project(id rawID: String) throws -> SecondBrainProject? {
        let id = Self.normalizedProjectID(rawID)
        let stmt = try database.prepare("""
            SELECT id, title, subtitle, status, metadata, created_at, updated_at
            FROM projects
            WHERE id = ? OR lower(title) = lower(?)
            LIMIT 1;
            """)
        stmt.bind(id, at: 1)
            .bind(rawID, at: 2)
        guard try stmt.step() else { return nil }
        return project(from: stmt)
    }

    @discardableResult
    func syncWorkspace(_ workspace: ProjectWorkspace, boards: [KanbanBoard]) throws -> SecondBrainProjectContext {
        let project = try upsertProject(
            id: workspace.id,
            title: workspace.title,
            subtitle: workspace.subtitle,
            metadata: [
                "workspace_kind": workspace.kind.rawValue,
                "reference_terms": workspace.referenceSearchTerms.joined(separator: ","),
            ]
        )
        let projectOwner = project.owner
        let scopedBoards = boards.filter { workspace.boardIDs.contains($0.id) }
        var relations: [SecondBrainRelation] = []
        for board in scopedBoards {
            let boardOwner = SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: board.id)
            relations.append(relation(
                source: projectOwner,
                target: boardOwner,
                type: "has_board",
                evidence: "Project workspace includes board \(board.name).",
                metadata: ["board_id": board.id, "board_name": board.name]
            ))
            for card in board.allCards {
                relations.append(relation(
                    source: projectOwner,
                    target: SecondBrainKanbanProjectionService.owner(boardID: board.id, cardID: card.id),
                    type: "has_card",
                    evidence: "Project workspace includes Kanban card \(card.title).",
                    metadata: ["board_id": board.id, "card_id": card.id, "card_title": card.title]
                ))
            }
        }
        try store.replaceRelations(
            sourceOwner: projectOwner,
            sourcePrefix: Self.workspaceSource,
            with: relations
        )
        var context = try context(for: project.id)
        context.readOnly = false
        context.changed = true
        context.mutationReason = "Synced project workspace metadata and Kanban owner relations."
        return context
    }

    func context(for rawID: String) throws -> SecondBrainProjectContext {
        guard let project = try project(id: rawID) else {
            throw ProjectGraphError.projectNotFound(rawID)
        }
        let owner = project.owner
        let outgoing = try store.outgoingRelations(for: owner)
        let backlinks = try store.backlinks(for: owner)
        let artifacts = artifactRelations(projectOwner: owner, outgoing: outgoing, backlinks: backlinks)
        return SecondBrainProjectContext(
            project: project,
            owner: owner,
            sections: try store.sections(for: owner),
            outgoingRelations: outgoing,
            backlinks: backlinks,
            artifactRelations: artifacts,
            artifactOwners: artifacts.map { artifactOwner(projectOwner: owner, relation: $0) },
            boardOwners: outgoing.map(\.targetOwner).filter { $0.ownerType == "kanban_board" },
            cardOwners: outgoing.map(\.targetOwner).filter { $0.ownerType == "kanban_card" },
            safeCommands: [
                "cider-cli item project-context \(project.id) --json",
                "cider-cli item sync-project \(project.id) --json",
                "cider-cli item relations project \(project.id) --json",
                "cider-cli item backlinks project \(project.id) --json",
            ]
        )
    }

    func contextOrSyncWorkspace(
        for rawID: String,
        workspace: ProjectWorkspace?,
        boards: [KanbanBoard]
    ) throws -> SecondBrainProjectContext {
        if let context = try? context(for: rawID) {
            return context
        }
        guard let workspace else {
            throw ProjectGraphError.projectNotFound(rawID)
        }
        return try syncWorkspace(workspace, boards: boards)
    }

    private func artifactRelations(
        projectOwner: SecondBrainOwnerRef,
        outgoing: [SecondBrainRelation],
        backlinks: [SecondBrainRelation]
    ) -> [SecondBrainRelation] {
        (outgoing + backlinks)
            .filter { relation in
                let type = relation.relationType.lowercased()
                return type == "artifact_of"
                    || type == "has_artifact"
                    || type == "project_artifact"
                    || type.hasSuffix("_doc_for")
                    || type.hasSuffix("_note_for")
                    || type.hasSuffix("_handoff_for")
                    || type.hasSuffix("_audit_for")
                    || type.contains("artifact")
            }
            .sorted { lhs, rhs in
                let lhsOwner = artifactOwner(projectOwner: projectOwner, relation: lhs).canonicalRef
                let rhsOwner = artifactOwner(projectOwner: projectOwner, relation: rhs).canonicalRef
                if lhsOwner != rhsOwner { return lhsOwner < rhsOwner }
                return lhs.relationType < rhs.relationType
            }
    }

    private func artifactOwner(projectOwner: SecondBrainOwnerRef, relation: SecondBrainRelation) -> SecondBrainOwnerRef {
        relation.sourceOwner == projectOwner ? relation.targetOwner : relation.sourceOwner
    }

    private func relation(
        source: SecondBrainOwnerRef,
        target: SecondBrainOwnerRef,
        type: String,
        evidence: String,
        metadata: [String: String]
    ) -> SecondBrainRelation {
        SecondBrainRelation(
            sourceOwner: source,
            targetOwner: target,
            relationType: type,
            evidence: evidence,
            source: Self.workspaceSource,
            actor: "system",
            confidence: 1,
            metadata: metadata
        )
    }

    private func project(from stmt: SQLStatement) -> SecondBrainProject {
        SecondBrainProject(
            id: stmt.string(at: 0),
            title: stmt.string(at: 1),
            subtitle: stmt.string(at: 2),
            status: stmt.string(at: 3),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 4)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 5)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 6))
        )
    }

    enum ProjectGraphError: LocalizedError {
        case projectNotFound(String)

        var errorDescription: String? {
            switch self {
            case .projectNotFound(let ref):
                "Project '\(ref)' was not found in the backend project graph."
            }
        }
    }
}
