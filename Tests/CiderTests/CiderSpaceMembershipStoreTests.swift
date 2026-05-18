import Foundation
import Testing
@testable import Cider

@Suite("Cider Space Membership Store Tests")
@MainActor
struct CiderSpaceMembershipStoreTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-space-membership-\(UUID().uuidString).db")
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
        type: String = "bookmark",
        title: String = "Steam page",
        relativePath: String = "Inbox/Bookmarks/Steam page.webloc"
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

    @Test("space membership is native item metadata and does not require folder assignment")
    func spaceMembershipIsNativeItemMetadata() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertItem(db)
        let ref = LibraryEntityRef(type: .bookmark, entityID: itemID)
        let store = CiderSpaceMembershipStore(database: db)

        let membership = try store.assign(
            item: ref,
            toSpaceID: "space-media",
            spaceName: "Media",
            reason: "Steam URL belongs in the Media/Games meaning layer.",
            confidence: 0.94,
            source: "test.space.assign",
            actor: "codex"
        )

        #expect(membership.item == ref)
        #expect(membership.spaceID == "space-media")
        #expect(membership.spaceName == "Media")
        #expect(membership.reason == "Steam URL belongs in the Media/Games meaning layer.")
        #expect(membership.confidence == 0.94)
        #expect(membership.source == "test.space.assign")
        #expect(membership.actor == "codex")

        let itemMemberships = try store.memberships(for: ref)
        #expect(itemMemberships.map(\.spaceID) == ["space-media"])
        #expect(itemMemberships.first?.item == ref)

        let spaceItems = try store.itemRefs(inSpaceID: "space-media")
        #expect(spaceItems == [ref])

        let itemStmt = try db.prepare("SELECT folder_id, relative_path FROM items WHERE id = ?;")
        itemStmt.bind(itemID.uuidString, at: 1)
        #expect(try itemStmt.step())
        #expect(itemStmt.optionalString(at: 0) == nil)
        #expect(itemStmt.string(at: 1) == "Inbox/Bookmarks/Steam page.webloc")
    }
}
