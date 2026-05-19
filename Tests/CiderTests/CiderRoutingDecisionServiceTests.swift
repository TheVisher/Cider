import Foundation
import Testing
@testable import Cider

@Suite("Cider Routing Decision Service Tests")
@MainActor
struct CiderRoutingDecisionServiceTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-routing-test-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(atPath: url.path + "-wal")
        try? fm.removeItem(atPath: url.path + "-shm")
    }

    private func insertBookmarkItem(_ db: CiderDatabase, id: UUID = UUID()) throws -> UUID {
        try db.withTransaction {
            let item = try db.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'bookmark', 'Example', ?, ?, NULL, 'Inbox/Bookmarks/Example.webloc');
                """)
            item.bind(id.uuidString, at: 1)
                .bind(Date().timeIntervalSince1970, at: 2)
                .bind(Date().timeIntervalSince1970, at: 3)
            try item.step()

            let bookmark = try db.prepare("""
                INSERT INTO bookmarks (item_id, url, notes, notes_manually_set, title_manually_set)
                VALUES (?, 'https://example.com', '', 0, 0);
                """)
            bookmark.bind(id.uuidString, at: 1)
            try bookmark.step()
        }
        return id
    }

    private func insertGenericItem(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        type: String,
        title: String,
        relativePath: String
    ) throws -> UUID {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(Date().timeIntervalSince1970, at: 4)
            .bind(Date().timeIntervalSince1970, at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
        return id
    }

    private func insertFolder(_ db: CiderDatabase, id: UUID = UUID(), relativePath: String) throws -> UUID {
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(relativePath, at: 2)
            .bind(Date().timeIntervalSince1970, at: 3)
            .bind(Date().timeIntervalSince1970, at: 4)
        try stmt.step()
        return id
    }

    @Test("routing decisions explain latest target and preserve superseded correction provenance")
    func decisionsExplainAndPreserveCorrection() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmarkItem(db)
        let folderID = try insertFolder(db, relativePath: "Projects/Research")
        let service = CiderRoutingDecisionService(database: db)

        let initial = try service.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "No deterministic route was supplied.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )

        let correction = try service.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "folder", name: "Research", relativePath: "Projects/Research", folderID: folderID),
            confidence: 1,
            reason: "Erik corrected this into Research.",
            actor: "user",
            source: "routing.correct",
            reviewState: "corrected",
            supersedesDecisionID: initial.id
        )

        let explanation = try service.explain(itemID: itemID)

        #expect(explanation.item.id == itemID)
        #expect(explanation.latestDecision?.id == correction.id)
        #expect(explanation.latestDecision?.supersedesDecisionID == initial.id)
        #expect(explanation.latestDecision?.target.relativePath == "Projects/Research")
        #expect(explanation.latestDecision?.confidence == 1)
        #expect(explanation.latestDecision?.actor == "user")
        #expect(explanation.history.map(\.id) == [correction.id, initial.id])
        #expect(explanation.reviewNeeded == false)
        #expect(explanation.nextSafeAction == "inspect_item")
    }

    @Test("manual move provenance works for non-bookmark item types")
    func manualMoveProvenanceWorksForNonBookmarkItemTypes() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let noteID = try insertGenericItem(
            db,
            type: "note",
            title: "Move me",
            relativePath: "Inbox/Notes/Move me.md"
        )
        let folderID = try insertFolder(db, relativePath: "Projects/Research")
        let service = CiderRoutingDecisionService(database: db)
        let initial = try service.recordDecision(
            itemID: noteID,
            itemType: "note",
            target: .init(kind: "inbox", name: "Inbox/Notes", relativePath: "Inbox/Notes", folderID: nil),
            confidence: 0,
            reason: "Captured note needs routing.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )

        let explanation = try service.recordManualMove(
            itemID: noteID,
            target: .init(kind: "folder", name: "Research", relativePath: "Projects/Research", folderID: folderID),
            reason: "Moved with note move.",
            actor: "user",
            source: "note.move"
        )

        #expect(explanation.item.id == noteID)
        #expect(explanation.latestDecision?.itemType == "note")
        #expect(explanation.latestDecision?.source == "note.move")
        #expect(explanation.latestDecision?.reviewState == "manual_move")
        #expect(explanation.latestDecision?.target.relativePath == "Projects/Research")
        #expect(explanation.latestDecision?.supersedesDecisionID == initial.id)
        #expect(explanation.history.count == 2)
        #expect(explanation.reviewNeeded == false)
    }

    @Test("create provenance rebuilds content chunks for derived mutation wrappers")
    func createProvenanceRebuildsContentChunks() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmarkItem(db)
        let service = CiderRoutingDecisionService(database: db)

        _ = try service.recordCreateProvenance(
            itemID: itemID,
            source: "library.editor.bookmark.create",
            reviewReason: "Created bookmark needs review.",
            acceptedReason: "Created bookmark in selected folder."
        )

        let stmt = try db.prepare("""
            SELECT COUNT(*)
            FROM content_chunks
            WHERE owner_type = 'bookmark' AND owner_id = ?;
            """)
        stmt.bind(itemID.uuidString, at: 1)
        #expect(try stmt.step())
        #expect(stmt.int(at: 0) > 0)
    }

    @Test("space assignment records routing provenance and native membership without moving files")
    func spaceAssignmentRecordsRoutingProvenanceAndNativeMembership() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertGenericItem(
            db,
            type: "bookmark",
            title: "Steam game page",
            relativePath: "Inbox/Bookmarks/Steam game page.webloc"
        )
        let service = CiderRoutingDecisionService(database: db)

        let explanation = try service.recordSpaceAssignment(
            itemID: itemID,
            spaceID: "space-media",
            spaceName: "Media",
            reason: "Steam game page belongs in Media without requiring a Media/Games folder.",
            confidence: 0.91,
            actor: "agent",
            source: "capture.route"
        )

        #expect(explanation.latestDecision?.target.kind == "space")
        #expect(explanation.latestDecision?.target.spaceID == "space-media")
        #expect(explanation.latestDecision?.target.name == "Media")
        #expect(explanation.latestDecision?.reviewState == "accepted")
        #expect(explanation.reviewNeeded == false)

        let ref = LibraryEntityRef(type: .bookmark, entityID: itemID)
        let memberships = try CiderSpaceMembershipStore(database: db).memberships(for: ref)
        #expect(memberships.map(\.spaceID) == ["space-media"])
        #expect(memberships.first?.reason == "Steam game page belongs in Media without requiring a Media/Games folder.")

        let context = try CiderItemContextService(database: db).agentContext(for: ref)
        #expect(context.provenance.contains("space:Media"))
        #expect(context.provenance.contains("routing:capture.route"))
        #expect(context.spaceMemberships.map(\.spaceName) == ["Media"])

        let itemStmt = try db.prepare("SELECT folder_id, relative_path FROM items WHERE id = ?;")
        itemStmt.bind(itemID.uuidString, at: 1)
        #expect(try itemStmt.step())
        #expect(itemStmt.optionalString(at: 0) == nil)
        #expect(itemStmt.string(at: 1) == "Inbox/Bookmarks/Steam game page.webloc")

        let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: itemID.uuidString)
        let routing = try SecondBrainStore(database: db).routingDecisions(for: owner)
        #expect(routing.first?.targetType == "space")
        #expect(routing.first?.targetID == "space-media")
    }
}
