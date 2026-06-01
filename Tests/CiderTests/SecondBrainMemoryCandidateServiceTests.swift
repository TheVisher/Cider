import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Memory Candidate Service Tests")
@MainActor
struct SecondBrainMemoryCandidateServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-memory-candidate-\(UUID().uuidString).db")
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

    @Test("suggestion stores reviewable candidate and audit action for project owner")
    func suggestionStoresReviewableCandidateAndAuditActionForProjectOwner() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        _ = try SecondBrainProjectGraphService(database: db).upsertProject(id: "Cider", title: "Cider")
        let service = SecondBrainMemoryCandidateService(database: db)

        let result = try service.suggest(
            ownerType: "project",
            ownerRef: "Cider",
            kind: "agent_lesson",
            value: "Prefer conservative backend slices before memory graph work.",
            evidence: "CID-351 card says no automatic permanent memory writes without review.",
            source: "codex",
            confidence: 0.82
        )

        #expect(result.owner == SecondBrainOwnerRef(ownerType: "project", ownerID: "cider"))
        #expect(result.candidate.kind == "memory_candidate")
        #expect(result.candidate.reviewState == "suggested")
        #expect(result.candidate.metadata["memory_kind"] == "agent_lesson")
        #expect(result.candidate.value == "Prefer conservative backend slices before memory graph work.")
        #expect(result.candidate.evidence.contains("CID-351"))
        #expect(result.candidate.confidence == 0.82)

        let outputs = try SecondBrainEnrichmentOutputService(database: db).outputs(for: result.owner)
        #expect(outputs.count == 1)
        #expect(outputs[0].id == result.candidate.id)

        let actions = try SecondBrainStore(database: db).agentActions(for: result.owner)
        #expect(actions.count == 1)
        #expect(actions[0].actionType == "memory_candidate_suggested")
        #expect(actions[0].status == "suggested")
        #expect(actions[0].resultJSON?.contains(result.candidate.id) == true)
    }

    @Test("suggestion supports item owner and appears in item context enrichment outputs")
    func suggestionSupportsItemOwnerAndAppearsInItemContextEnrichmentOutputs() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        try insertNoteItem(owner: owner, into: db)

        let result = try SecondBrainMemoryCandidateService(database: db).suggest(
            ownerType: "note",
            ownerRef: owner.ownerID,
            kind: "preference",
            value: "Use Cider Kanban cards for implementation handoffs.",
            evidence: "AGENTS.md says Kanban is the active work surface.",
            source: "test",
            confidence: 0.7
        )

        let ref = LibraryEntityRef(type: .note, entityID: UUID(uuidString: owner.ownerID)!)
        let context = try CiderItemContextService(database: db).context(for: ref)
        #expect(context.enrichmentOutputs.contains { $0.id == result.candidate.id })
    }

    @Test("suggestion supports projected Kanban card owner")
    func suggestionSupportsProjectedKanbanCardOwner() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/0a7798")
        try SecondBrainStore(database: db).upsertSection(SecondBrainSection(
            owner: owner,
            itemID: nil,
            sectionKey: "card",
            title: "CID-351",
            body: "Add reviewable agent memory candidate CLI.",
            source: "test",
            confidence: 1,
            metadata: [:],
            sortOrder: 0
        ))

        let result = try SecondBrainMemoryCandidateService(database: db).suggest(
            ownerType: "kanban_card",
            ownerRef: "2afee0/0a7798",
            kind: "project_context",
            value: "CID-351 is the conservative memory candidate backend slice.",
            evidence: "The card requires candidate extraction only, reviewable queue, and no auto-promotion.",
            source: "test",
            confidence: nil
        )

        #expect(result.owner == owner)
        #expect(result.candidate.metadata["memory_kind"] == "project_context")
    }

    @Test("suggestion refuses unresolved owner and missing required text")
    func suggestionRefusesUnresolvedOwnerAndMissingRequiredText() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = SecondBrainMemoryCandidateService(database: db)

        #expect(throws: SecondBrainMemoryCandidateService.MemoryCandidateError.self) {
            _ = try service.suggest(
                ownerType: "project",
                ownerRef: "missing",
                kind: "preference",
                value: "Use Kanban.",
                evidence: "User asked.",
                source: "test",
                confidence: nil
            )
        }

        _ = try SecondBrainProjectGraphService(database: db).upsertProject(id: "Cider", title: "Cider")

        #expect(throws: SecondBrainMemoryCandidateService.MemoryCandidateError.self) {
            _ = try service.suggest(
                ownerType: "project",
                ownerRef: "Cider",
                kind: "preference",
                value: "   ",
                evidence: "User asked.",
                source: "test",
                confidence: nil
            )
        }

        #expect(throws: SecondBrainMemoryCandidateService.MemoryCandidateError.self) {
            _ = try service.suggest(
                ownerType: "project",
                ownerRef: "Cider",
                kind: "preference",
                value: "Use Kanban.",
                evidence: "",
                source: "test",
                confidence: nil
            )
        }
    }

    private func insertNoteItem(owner: SecondBrainOwnerRef, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', 'Memory note', ?, ?, NULL, 'Inbox/Memory note.md');
            """)
        itemStmt.bind(owner.ownerID, at: 1)
            .bind(now, at: 2)
            .bind(now, at: 3)
        try itemStmt.step()

        let noteStmt = try db.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, '', NULL, 0);")
        noteStmt.bind(owner.ownerID, at: 1)
        try noteStmt.step()
    }
}
