import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Project Graph Tests")
@MainActor
struct SecondBrainProjectGraphTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-graph-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("Project records provide stable project owners")
    func projectRecordsProvideStableOwners() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = SecondBrainProjectGraphService(database: db)
        let project = try service.upsertProject(
            id: "Cider",
            title: "Cider",
            subtitle: "Main product workspace",
            metadata: ["source": "test"]
        )

        #expect(project.id == "cider")
        #expect(project.owner == SecondBrainOwnerRef(ownerType: "project", ownerID: "cider"))
        let context = try service.context(for: "Cider")
        #expect(context.project.title == "Cider")
        #expect(context.safeCommands.contains("cider-cli item project-context cider --json"))
    }

    @Test("Project workspace sync links boards and cards through owner relations")
    func projectWorkspaceSyncLinksBoardsAndCards() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [
                    KanbanCard(id: "card-a", title: "Project docs")
                ])
            ]
        )
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let service = SecondBrainProjectGraphService(database: db)

        let context = try service.syncWorkspace(workspace, boards: [board])

        #expect(context.owner == SecondBrainOwnerRef(ownerType: "project", ownerID: "cider"))
        #expect(context.boardOwners == [SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: "2afee0")])
        #expect(context.cardOwners == [SecondBrainKanbanProjectionService.owner(boardID: "2afee0", cardID: "card-a")])
        #expect(context.outgoingRelations.map(\.relationType).sorted() == ["has_board", "has_card"])
    }

    @Test("Project context includes artifact backlinks")
    func projectContextIncludesArtifactBacklinks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let service = SecondBrainProjectGraphService(database: db, store: store)
        let project = try service.upsertProject(id: "Cider", title: "Cider")
        let note = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)

        try store.recordRelation(SecondBrainRelation(
            sourceOwner: note,
            targetOwner: project.owner,
            relationType: "artifact_of",
            evidence: "Audit note belongs to Cider.",
            source: "test",
            actor: "agent",
            confidence: 1
        ))

        let context = try service.context(for: "cider")
        #expect(context.backlinks.count == 1)
        #expect(context.backlinks[0].sourceOwner == note)
        #expect(context.backlinks[0].relationType == "artifact_of")
        #expect(context.artifactOwners == [note])
        #expect(context.artifactRelations.map(\.relationType) == ["artifact_of"])
    }

    @Test("Project context is read-only when graph row is missing")
    func projectContextIsReadOnlyWhenGraphRowIsMissing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = SecondBrainProjectGraphService(database: db)

        #expect(throws: SecondBrainProjectGraphService.ProjectGraphError.self) {
            _ = try service.context(for: "cider")
        }
        #expect(try service.project(id: "cider") == nil)
    }

    @Test("Project sync seeds a known workspace when graph row is missing")
    func projectSyncSeedsKnownWorkspaceWhenMissing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(id: "card-a", title: "Seed project context")
                ])
            ]
        )
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let service = SecondBrainProjectGraphService(database: db)

        let context = try service.syncWorkspace(workspace, boards: [board])

        #expect(context.project.id == "cider")
        #expect(context.boardOwners == [SecondBrainOwnerRef(ownerType: "kanban_board", ownerID: "2afee0")])
        #expect(context.cardOwners == [SecondBrainKanbanProjectionService.owner(boardID: "2afee0", cardID: "card-a")])
        #expect(try service.project(id: "cider") != nil)
    }
}
