import Foundation
import Testing
@testable import Cider

@Suite("Cider Item Mutation Service Tests")
@MainActor
struct CiderItemMutationServiceTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-mutation-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    @discardableResult
    private func insertItem(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        type: String = "note",
        title: String = "Move me",
        relativePath: String = "Inbox/Notes/Move me.md"
    ) throws -> UUID {
        let now = Date().timeIntervalSince1970
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
        return id
    }

    @discardableResult
    private func insertFolder(_ db: CiderDatabase, id: UUID = UUID(), relativePath: String) throws -> UUID {
        let now = Date().timeIntervalSince1970
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(relativePath, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
        try stmt.step()
        return id
    }

    @Test("move returns confirmed state with audit routing and agent action IDs")
    func moveReturnsConfirmedStateAndProvenance() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertItem(db)
        let folderID = try insertFolder(db, relativePath: "Projects/Research")
        let ref = LibraryEntityRef(type: .note, entityID: itemID)
        let service = CiderItemMutationService(
            database: db,
            assignToFolder: { ref, folderID in
                let stmt = try db.prepare("""
                    UPDATE items
                    SET folder_id = ?, relative_path = ?, updated_at = ?
                    WHERE id = ?;
                    """)
                stmt.bind(folderID?.uuidString, at: 1)
                    .bind("Projects/Research/Move me.md", at: 2)
                    .bind(Date().timeIntervalSince1970, at: 3)
                    .bind(ref.entityID.uuidString, at: 4)
                try stmt.step()
                return true
            }
        )

        let result = try service.move(
            ref: ref,
            toFolder: folderID,
            targetRelativePath: "Projects/Research",
            actor: "agent",
            source: "test.item.move"
        )

        #expect(result.ok == true)
        #expect(result.command == "item.move")
        #expect(result.before.folderID == nil)
        #expect(result.after?.folderID == folderID)
        #expect(result.mutationAuditEntryID != nil)
        #expect(result.routingDecisionID != nil)
        #expect(result.agentActionID != nil)
        #expect(result.partialFailures.isEmpty)
        #expect(result.nextSafeAction == "inspect_item")

        let auditEntries = MutationAuditService(database: db).loadEntries()
        #expect(auditEntries.contains(where: {
            $0.id == result.mutationAuditEntryID && $0.action == "item_move" && $0.itemID == itemID
        }))

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: itemID.uuidString)
        let actions = try SecondBrainStore(database: db).agentActions(for: owner)
        #expect(actions.contains(where: {
            $0.id == result.agentActionID && $0.actionType == "item.move" && $0.status == "succeeded"
        }))

        let routing = try SecondBrainStore(database: db).routingDecisions(for: owner)
        #expect(routing.contains(where: {
            $0.id == result.routingDecisionID?.uuidString && $0.status == "manual_move"
        }))
    }

    @Test("failed assignment returns partial failure without claiming provenance")
    func failedAssignmentReturnsPartialFailure() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertItem(db)
        let folderID = try insertFolder(db, relativePath: "Projects/Research")
        let ref = LibraryEntityRef(type: .note, entityID: itemID)
        let service = CiderItemMutationService(
            database: db,
            assignToFolder: { _, _ in false }
        )

        let result = try service.move(
            ref: ref,
            toFolder: folderID,
            targetRelativePath: "Projects/Research",
            actor: "agent",
            source: "test.item.move"
        )

        #expect(result.ok == false)
        #expect(result.after == nil)
        #expect(result.mutationAuditEntryID == nil)
        #expect(result.routingDecisionID == nil)
        #expect(result.agentActionID == nil)
        #expect(result.partialFailures.contains("assignment_failed"))
    }
}
