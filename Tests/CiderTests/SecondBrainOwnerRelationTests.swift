import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Owner Relation Tests")
@MainActor
struct SecondBrainOwnerRelationTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-owner-relations-\(UUID().uuidString).db")
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

    private func insertItem(_ ref: LibraryEntityRef, title: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, NULL);
            """)
        stmt.bind(ref.entityID.uuidString, at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
        try stmt.step()
    }

    @Test("Owner relations persist, list outgoing, and list backlinks")
    func ownerRelationsPersistAndBacklink() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let card = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        let doc = SecondBrainOwnerRef(ownerType: "doc", ownerID: "Docs/STORAGE.md")

        try store.recordRelation(SecondBrainRelation(
            sourceOwner: card,
            targetOwner: doc,
            relationType: "references",
            evidence: "Card points at storage doc.",
            source: "test",
            actor: "agent",
            confidence: 0.95,
            metadata: ["section": "acceptance"]
        ))

        let outgoing = try store.outgoingRelations(for: card)
        #expect(outgoing.count == 1)
        #expect(outgoing[0].sourceOwner == card)
        #expect(outgoing[0].targetOwner == doc)
        #expect(outgoing[0].relationType == "references")
        #expect(outgoing[0].evidence == "Card points at storage doc.")
        #expect(outgoing[0].source == "test")
        #expect(outgoing[0].actor == "agent")
        #expect(outgoing[0].confidence == 0.95)
        #expect(outgoing[0].metadata["section"] == "acceptance")

        let backlinks = try store.backlinks(for: doc)
        #expect(backlinks.map(\.id) == outgoing.map(\.id))
    }

    @Test("Existing item_links are bridged as owner relations")
    func itemLinksBridgeIntoOwnerRelations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(bookmark, title: "SQLite graph", into: db)
        try insertItem(note, title: "Design note", into: db)

        try ItemLinkService(database: db).addDirectLink(from: bookmark, to: note)

        let store = SecondBrainStore(database: db)
        let bookmarkOwner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.entityID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)

        let outgoing = try store.outgoingRelations(for: bookmarkOwner)
        #expect(outgoing.count == 1)
        #expect(outgoing[0].sourceOwner == bookmarkOwner)
        #expect(outgoing[0].targetOwner == noteOwner)
        #expect(outgoing[0].relationType == "linked")
        #expect(outgoing[0].source == "item_links")
        #expect(outgoing[0].metadata["bridge"] == "item_links")

        let backlinks = try store.backlinks(for: noteOwner)
        #expect(backlinks.count == 1)
        #expect(backlinks[0].sourceOwner == bookmarkOwner)
        #expect(backlinks[0].targetOwner == noteOwner)
    }

    @Test("Item context exposes bridged owner relations")
    func itemContextIncludesOwnerRelations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(bookmark, title: "SQLite graph", into: db)
        try insertItem(note, title: "Design note", into: db)
        try ItemLinkService(database: db).addDirectLink(from: bookmark, to: note)

        let context = try CiderItemContextService(
            database: db,
            linkService: ItemLinkService(database: db),
            secondBrainStore: SecondBrainStore(database: db),
            spaceMembershipStore: CiderSpaceMembershipStore(database: db)
        ).context(for: bookmark)

        #expect(context.ownerRelations.count == 1)
        #expect(context.ownerRelations[0].targetOwner.ownerType == "note")
        #expect(context.backlinks.isEmpty)
    }

    @Test("Deleting an item cleans second-brain owner provenance")
    func deletingItemCleansSecondBrainOwnerProvenance() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(bookmark, title: "Delete me", into: db)
        try insertItem(note, title: "Related note", into: db)

        let store = SecondBrainStore(database: db)
        let bookmarkOwner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmark.entityID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.replaceProjection(
            owner: bookmarkOwner,
            sections: [
                SecondBrainSection(
                    owner: bookmarkOwner,
                    sectionKey: "summary",
                    title: "Summary",
                    body: "Owner-only projected context.",
                    source: "test",
                    sortOrder: 0
                ),
            ],
            keeping: ["summary"],
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    itemID: nil,
                    source: "test",
                    title: "Delete me",
                    body: "Searchable stale chunk.",
                    chunkIndex: 0
                ),
            ]
        )
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: bookmarkOwner,
            targetOwner: noteOwner,
            relationType: "references",
            evidence: "Bookmark references note.",
            source: "test",
            actor: "agent"
        ))
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: noteOwner,
            targetOwner: bookmarkOwner,
            relationType: "mentioned_by",
            evidence: "Note mentions bookmark.",
            source: "test",
            actor: "agent"
        ))
        try store.recordRoutingDecision(SecondBrainRoutingDecision(
            owner: bookmarkOwner,
            itemID: bookmark.entityID.uuidString,
            targetType: "folder",
            targetID: nil,
            targetPath: "Projects/Delete",
            confidence: 0.9,
            reason: "Route before delete.",
            status: "accepted",
            actor: "agent",
            source: "test"
        ))
        try store.recordAgentAction(SecondBrainAgentAction(
            owner: bookmarkOwner,
            itemID: bookmark.entityID.uuidString,
            toolName: "cider-cli",
            actionType: "route",
            source: "test",
            status: "succeeded",
            summary: "Routed before delete."
        ))

        VaultBookmarkService(database: db, schedulesEnrichment: false).deleteBookmarkFromDatabase(db, bookmarkID: bookmark.entityID)

        #expect(try store.sections(for: bookmarkOwner).isEmpty)
        #expect(try store.searchChunks(query: "stale chunk", limit: 5).isEmpty)
        #expect(try store.outgoingRelations(for: bookmarkOwner).isEmpty)
        #expect(try store.backlinks(for: bookmarkOwner).isEmpty)
        #expect(try store.routingDecisions(for: bookmarkOwner).isEmpty)
        #expect(try store.agentActions(for: bookmarkOwner).isEmpty)
    }
}
