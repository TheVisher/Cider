import Foundation
import Testing
@testable import Cider

@Suite("Cider Space Capture Dashboard Service Tests")
@MainActor
struct CiderSpaceCaptureDashboardServiceTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-space-capture-dashboard-test-\(UUID().uuidString).db")
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

    private func insertFolder(_ db: CiderDatabase, id: UUID = UUID(), path: String) throws -> UUID {
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(path, at: 2)
            .bind(Date().timeIntervalSince1970, at: 3)
            .bind(Date().timeIntervalSince1970, at: 4)
        try stmt.step()
        return id
    }

    private func insertBookmark(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        title: String,
        url: String,
        folderID: UUID?,
        relativePath: String,
        createdAt: Date = Date()
    ) throws -> UUID {
        try db.withTransaction {
            let item = try db.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'bookmark', ?, ?, ?, ?, ?);
                """)
            item.bind(id.uuidString, at: 1)
                .bind(title, at: 2)
                .bind(createdAt.timeIntervalSince1970, at: 3)
                .bind(createdAt.timeIntervalSince1970, at: 4)
                .bind(folderID?.uuidString, at: 5)
                .bind(relativePath, at: 6)
            try item.step()

            let bookmark = try db.prepare("""
                INSERT INTO bookmarks (item_id, url, notes, notes_manually_set, title_manually_set, enrichment_status, last_enriched_at)
                VALUES (?, ?, '', 0, 0, 'complete', ?);
                """)
            bookmark.bind(id.uuidString, at: 1)
                .bind(url, at: 2)
                .bind(createdAt.timeIntervalSince1970, at: 3)
            try bookmark.step()
        }
        return id
    }

    private func makeSpace(path: String = "Spaces/Research") -> CiderSpace {
        CiderSpace(
            id: "space-research",
            name: "Research",
            systemImage: "book",
            purpose: "Research links and notes.",
            preset: .blank,
            aiInstructions: "Route research saves here.",
            routingHints: ["Prefer research sources."],
            defaultViews: [.overview, .recent],
            rootRelativePath: path,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("space dashboard splits accepted routed captures from needs-review candidates")
    func dashboardSplitsAcceptedAndReviewCaptures() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let space = makeSpace()
        let folderID = try insertFolder(db, path: space.rootRelativePath)
        let acceptedID = try insertBookmark(
            db,
            title: "SQLite Notes",
            url: "https://example.com/sqlite",
            folderID: folderID,
            relativePath: "Spaces/Research/SQLite Notes.webloc",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let reviewID = try insertBookmark(
            db,
            title: "Ambiguous Paper",
            url: "https://example.com/paper",
            folderID: nil,
            relativePath: "Inbox/Bookmarks/Ambiguous Paper.webloc",
            createdAt: Date(timeIntervalSince1970: 110)
        )
        let outsideID = try insertBookmark(
            db,
            title: "Outside",
            url: "https://example.com/outside",
            folderID: nil,
            relativePath: "Inbox/Bookmarks/Outside.webloc",
            createdAt: Date(timeIntervalSince1970: 120)
        )
        let routing = CiderRoutingDecisionService(database: db)
        let acceptedDecision = try routing.recordDecision(
            itemID: acceptedID,
            itemType: "bookmark",
            target: .init(kind: "folder", name: "Research", relativePath: space.rootRelativePath, folderID: folderID),
            confidence: 1,
            reason: "Capture used the supplied deterministic target.",
            actor: "agent",
            source: "capture.add",
            reviewState: "accepted",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let reviewDecision = try routing.recordDecision(
            itemID: reviewID,
            itemType: "bookmark",
            target: .init(kind: "folder", name: "Research", relativePath: space.rootRelativePath, folderID: folderID),
            confidence: 0.42,
            reason: "Candidate research route needs confirmation.",
            actor: "agent",
            source: "routing.rerun",
            reviewState: "needs_review",
            createdAt: Date(timeIntervalSince1970: 210)
        )
        _ = try routing.recordDecision(
            itemID: outsideID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "Not a space candidate.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review",
            createdAt: Date(timeIntervalSince1970: 220)
        )

        let dashboard = try CiderSpaceCaptureDashboardService(database: db).dashboard(for: space)

        #expect(dashboard.recentRouted.map(\.itemID) == [acceptedID])
        #expect(dashboard.needsReview.map(\.itemID) == [reviewID])
        #expect(dashboard.recentRouted[0].routingDecisionID == acceptedDecision.id)
        #expect(dashboard.needsReview[0].routingDecisionID == reviewDecision.id)
        #expect(dashboard.recentRouted[0].sourceURL == "https://example.com/sqlite")
        #expect(dashboard.needsReview[0].reviewState == "needs_review")
        #expect(dashboard.needsReview[0].safeActions == ["routing explain", "review approve", "review correct", "review defer"])
    }

    @Test("space dashboard uses the latest routing decision for each item")
    func dashboardUsesLatestRoutingDecision() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let space = makeSpace()
        let spaceFolderID = try insertFolder(db, path: space.rootRelativePath)
        let inboxID = try insertFolder(db, path: "Inbox/Bookmarks")
        let itemID = try insertBookmark(
            db,
            title: "Moved Later",
            url: "https://example.com/moved",
            folderID: inboxID,
            relativePath: "Inbox/Bookmarks/Moved Later.webloc"
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "folder", name: "Research", relativePath: space.rootRelativePath, folderID: spaceFolderID),
            confidence: 0.4,
            reason: "Old candidate.",
            actor: "agent",
            source: "routing.rerun",
            reviewState: "needs_review",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: inboxID),
            confidence: 0,
            reason: "Superseded back to Inbox.",
            actor: "agent",
            source: "review.defer",
            reviewState: "deferred",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let dashboard = try CiderSpaceCaptureDashboardService(database: db).dashboard(for: space)

        #expect(dashboard.recentRouted.isEmpty)
        #expect(dashboard.needsReview.isEmpty)
    }
}
