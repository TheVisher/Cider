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
}
