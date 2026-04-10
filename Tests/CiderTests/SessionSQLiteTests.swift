import Foundation
import Testing
@testable import Cider

@Suite("Session SQLite Tests")
@MainActor
struct SessionSQLiteTests {

    // MARK: - Helpers

    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-session-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func makeService(_ db: CiderDatabase) -> BrowserSessionStorage {
        BrowserSessionStorage(database: db)
    }

    private func makeSession(
        id: UUID = UUID(),
        name: String = "My Session",
        tabs: [BrowserSessionTab] = [],
        sourceBrowserBundleID: String? = nil,
        sourceBrowserName: String? = nil,
        folderID: UUID? = nil,
        labelIDs: [UUID] = [],
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) -> BrowserSession {
        BrowserSession(
            id: id,
            name: name,
            tabs: tabs,
            sourceBrowserBundleID: sourceBrowserBundleID,
            sourceBrowserName: sourceBrowserName,
            folderID: folderID,
            labelIDs: labelIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - 1. Basic round-trip

    @Test("Session round-trips all top-level fields")
    func basicRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let session = makeSession(
            name: "Morning Research",
            tabs: [
                BrowserSessionTab(urlString: "https://apple.com", title: "Apple"),
                BrowserSessionTab(urlString: "https://swift.org", title: "Swift")
            ],
            sourceBrowserBundleID: "com.apple.Safari",
            sourceBrowserName: "Safari"
        )
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)

        #expect(service2.sessions.count == 1)
        let loaded = service2.sessions[0]
        #expect(loaded.id == session.id)
        #expect(loaded.name == "Morning Research")
        #expect(loaded.sourceBrowserBundleID == "com.apple.Safari")
        #expect(loaded.sourceBrowserName == "Safari")
        #expect(loaded.tabs.count == 2)
    }

    // MARK: - 2. Tabs array round-trip

    @Test("Tabs array with id/urlString/title preserves identity")
    func tabsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let tab1 = BrowserSessionTab(id: UUID(), urlString: "https://example.com/a", title: "A")
        let tab2 = BrowserSessionTab(id: UUID(), urlString: "https://example.com/b", title: "B")
        let tab3 = BrowserSessionTab(id: UUID(), urlString: "https://example.com/c", title: "C")
        let session = makeSession(tabs: [tab1, tab2, tab3])
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!

        #expect(loaded.tabs.count == 3)
        #expect(loaded.tabs[0].id == tab1.id)
        #expect(loaded.tabs[0].urlString == "https://example.com/a")
        #expect(loaded.tabs[0].title == "A")
        #expect(loaded.tabs[1].id == tab2.id)
        #expect(loaded.tabs[2].id == tab3.id)
    }

    // MARK: - 3. Empty tabs array → NULL round-trips as empty

    @Test("Empty tabs array round-trips as empty (stored as NULL)")
    func emptyTabsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let session = makeSession(name: "Empty", tabs: [])
        service.persistSessionToDatabase(db, session: session)

        // Verify tabs column is NULL
        let stmt = try db.prepare("SELECT tabs FROM sessions WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(session.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == nil)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        #expect(service2.sessions.first?.tabs.isEmpty == true)
    }

    // MARK: - 4. Nil optional fields

    @Test("Nil sourceBrowserBundleID / sourceBrowserName / folderID round-trip as nil")
    func nilOptionalFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let session = makeSession(
            name: "Bare",
            sourceBrowserBundleID: nil,
            sourceBrowserName: nil,
            folderID: nil
        )
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!
        #expect(loaded.sourceBrowserBundleID == nil)
        #expect(loaded.sourceBrowserName == nil)
        #expect(loaded.folderID == nil)
    }

    // MARK: - 5. Update existing session

    @Test("Updating an existing session (UPSERT) replaces tabs/name without duplicating row")
    func updateSession() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        var session = makeSession(
            name: "Original",
            tabs: [BrowserSessionTab(urlString: "https://a.com", title: "A")]
        )
        service.persistSessionToDatabase(db, session: session)

        session.name = "Updated"
        session.tabs = [
            BrowserSessionTab(urlString: "https://b.com", title: "B"),
            BrowserSessionTab(urlString: "https://c.com", title: "C")
        ]
        session.updatedAt = Date(timeIntervalSince1970: 1_700_100_000)
        service.persistSessionToDatabase(db, session: session)

        // Row count should still be 1
        let countStmt = try db.prepare("SELECT count(*) FROM sessions WHERE id = ?;")
        countStmt.bind(DatabaseHelpers.encode(session.id), at: 1)
        try countStmt.step()
        #expect(countStmt.int(at: 0) == 1)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!
        #expect(loaded.name == "Updated")
        #expect(loaded.tabs.count == 2)
        #expect(loaded.tabs[0].urlString == "https://b.com")
    }

    // MARK: - 6. Delete session

    @Test("Delete removes session row")
    func deleteSession() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let session = makeSession(name: "Goner")
        service.persistSessionToDatabase(db, session: session)

        service.deleteSessionFromDatabase(db, sessionID: session.id)

        let stmt = try db.prepare("SELECT count(*) FROM sessions WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(session.id), at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    // MARK: - 7. Multiple sessions persist independently

    @Test("Multiple sessions persist and load independently")
    func multipleSessions() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let s1 = makeSession(name: "First", createdAt: Date(timeIntervalSince1970: 1_700_000_300))
        let s2 = makeSession(name: "Second", createdAt: Date(timeIntervalSince1970: 1_700_000_200))
        let s3 = makeSession(name: "Third", createdAt: Date(timeIntervalSince1970: 1_700_000_100))
        service.persistSessionToDatabase(db, session: s1)
        service.persistSessionToDatabase(db, session: s2)
        service.persistSessionToDatabase(db, session: s3)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        #expect(service2.sessions.count == 3)
        // Ordered by created_at DESC
        #expect(service2.sessions.map(\.name) == ["First", "Second", "Third"])
    }

    // MARK: - 8. labelIDs JSON array round-trip

    @Test("labelIDs JSON column round-trips multiple UUIDs, empty → NULL")
    func labelIDsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let l1 = UUID()
        let l2 = UUID()
        let l3 = UUID()

        let withLabels = makeSession(name: "Labeled", labelIDs: [l1, l2, l3])
        let empty = makeSession(name: "Unlabeled", labelIDs: [])
        service.persistSessionToDatabase(db, session: withLabels)
        service.persistSessionToDatabase(db, session: empty)

        // Empty → NULL in column
        let emptyStmt = try db.prepare("SELECT label_ids FROM sessions WHERE id = ?;")
        emptyStmt.bind(DatabaseHelpers.encode(empty.id), at: 1)
        try emptyStmt.step()
        #expect(emptyStmt.optionalString(at: 0) == nil)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loadedWith = service2.sessions.first { $0.id == withLabels.id }!
        let loadedEmpty = service2.sessions.first { $0.id == empty.id }!
        #expect(Set(loadedWith.labelIDs) == Set([l1, l2, l3]))
        #expect(loadedEmpty.labelIDs.isEmpty)
    }

    // MARK: - 9. folder_id foreign key round-trip

    @Test("folder_id foreign key round-trips against folders table")
    func folderForeignKey() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folder = VaultFolder(relativePath: "Research")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)
        let session = makeSession(name: "In Folder", folderID: folder.id)
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!
        #expect(loaded.folderID == folder.id)

        // Verify column value matches
        let stmt = try db.prepare("SELECT folder_id FROM sessions WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(session.id), at: 1)
        try stmt.step()
        #expect(DatabaseHelpers.decodeUUID(stmt.optionalString(at: 0) ?? "") == folder.id)
    }

    // MARK: - 10. Empty database loads empty

    @Test("Empty database loads zero sessions")
    func emptyDatabase() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadSessionsFromDatabase(db)
        #expect(service.sessions.isEmpty)
    }

    // MARK: - 11. Date precision

    @Test("createdAt / updatedAt survive round-trip with sub-ms precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let created = Date(timeIntervalSince1970: 1_234_567_890.123)
        let updated = Date(timeIntervalSince1970: 1_234_567_999.456)
        let session = makeSession(name: "Dated", createdAt: created, updatedAt: updated)
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!
        #expect(abs(loaded.createdAt.timeIntervalSince(created)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(updated)) < 0.001)
    }

    // MARK: - 12. Tab with nil title round-trips

    @Test("Tab with nil title round-trips as nil")
    func tabNilTitle() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let tab = BrowserSessionTab(urlString: "https://untitled.example", title: nil)
        let session = makeSession(tabs: [tab])
        service.persistSessionToDatabase(db, session: session)

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        let loaded = service2.sessions.first!
        #expect(loaded.tabs.count == 1)
        #expect(loaded.tabs[0].title == nil)
        #expect(loaded.tabs[0].urlString == "https://untitled.example")
    }

    // MARK: - 13. JSON migration: calling persistSessionToDatabaseInner within a transaction works

    @Test("Batch migration via withTransaction + persistSessionToDatabaseInner persists all sessions")
    func batchMigrationInsideTransaction() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        // Simulate the JSON-to-SQLite migration path: a batch of sessions wrapped
        // in a single transaction, just like the production init() does.
        let batch = (0..<5).map { i in
            makeSession(
                name: "Migrated \(i)",
                tabs: [BrowserSessionTab(urlString: "https://m\(i).example", title: "M\(i)")]
            )
        }

        try db.withTransaction {
            for session in batch {
                try service.persistSessionToDatabaseInner(db, session: session)
            }
        }

        let service2 = makeService(db)
        service2.loadSessionsFromDatabase(db)
        #expect(service2.sessions.count == 5)
        let names = Set(service2.sessions.map(\.name))
        #expect(names == Set(["Migrated 0", "Migrated 1", "Migrated 2", "Migrated 3", "Migrated 4"]))
    }

    // MARK: - 14. Rename persists to database

    @Test("Direct persist of renamed session updates the database name column")
    func renamePersists() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        var session = makeSession(name: "Original Name")
        service.persistSessionToDatabase(db, session: session)

        session.name = "New Name"
        session.updatedAt = Date(timeIntervalSince1970: 1_700_111_111)
        service.persistSessionToDatabase(db, session: session)

        let stmt = try db.prepare("SELECT name FROM sessions WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(session.id), at: 1)
        try stmt.step()
        #expect(stmt.string(at: 0) == "New Name")
    }
}
