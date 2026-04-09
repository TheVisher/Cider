import Foundation
import Testing
@testable import Cider

@Suite("CiderDatabase Tests")
@MainActor
struct CiderDatabaseTests {

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    // MARK: - Bootstrap

    @Test("Opens database and creates schema at version 1")
    func openCreatesSchema() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        // Verify schema version is 1
        let stmt = try db.prepare("SELECT version FROM schema_version LIMIT 1;")
        let hasRow = try stmt.step()
        #expect(hasRow)
        #expect(stmt.int(at: 0) == 1)
    }

    @Test("Items table exists after schema creation")
    func itemsTableExists() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let stmt = try db.prepare(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='items';"
        )
        try stmt.step()
        #expect(stmt.int(at: 0) == 1)
    }

    @Test("All expected tables are created")
    func allTablesCreated() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let expectedTables = [
            "folders", "labels", "items", "bookmarks", "notes", "todos",
            "events", "contacts", "vault_files", "sessions",
            "item_labels", "dismissed_labels", "tags", "item_tags",
            "item_links", "trash", "schema_version",
        ]

        for table in expectedTables {
            let stmt = try db.prepare(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?;"
            )
            stmt.bind(table, at: 1)
            try stmt.step()
            #expect(stmt.int(at: 0) == 1, "Table '\(table)' should exist")
        }
    }

    @Test("Foreign keys are enabled")
    func foreignKeysEnabled() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let stmt = try db.prepare("PRAGMA foreign_keys;")
        try stmt.step()
        #expect(stmt.int(at: 0) == 1)
    }

    // MARK: - Reopening

    @Test("Reopening database preserves data and does not re-migrate")
    func reopenPreservesData() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        // First open: create schema and insert data
        let db1 = CiderDatabase()
        try db1.open(at: url)
        let folderID = UUID().uuidString
        try db1.runSQL("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES ('\(folderID)', 'test/path', 0.0, 0.0);
            """)
        db1.close()

        // Second open: verify data persists and version is still 1
        let db2 = CiderDatabase()
        try db2.open(at: url)
        defer { db2.close() }

        let folderStmt = try db2.prepare("SELECT relative_path FROM folders WHERE id = ?;")
        folderStmt.bind(folderID, at: 1)
        let hasRow = try folderStmt.step()
        #expect(hasRow)
        #expect(folderStmt.string(at: 0) == "test/path")

        let versionStmt = try db2.prepare("SELECT version FROM schema_version LIMIT 1;")
        try versionStmt.step()
        #expect(versionStmt.int(at: 0) == 1)
    }

    // MARK: - Transactions

    @Test("Transaction commits on success")
    func transactionCommits() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        try db.withTransaction {
            try db.runSQL("""
                INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
                VALUES ('label1', 'Test', '#FF0000', 'custom', 0.0, 0.0);
                """)
        }

        let stmt = try db.prepare("SELECT name FROM labels WHERE id = 'label1';")
        let hasRow = try stmt.step()
        #expect(hasRow)
        #expect(stmt.string(at: 0) == "Test")
    }

    @Test("Transaction rolls back on error")
    func transactionRollsBackOnError() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        do {
            try db.withTransaction {
                try db.runSQL("""
                    INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
                    VALUES ('label2', 'RolledBack', '#00FF00', 'custom', 0.0, 0.0);
                    """)
                // Force an error with invalid SQL
                try db.runSQL("INSERT INTO nonexistent_table VALUES (1);")
            }
        } catch {
            // Expected
        }

        // The label should not exist because the transaction was rolled back
        let stmt = try db.prepare("SELECT count(*) FROM labels WHERE id = 'label2';")
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    // MARK: - Foreign Key Enforcement

    @Test("Foreign key constraint prevents orphan items")
    func foreignKeyConstraint() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        // Inserting an item with a non-existent folder_id should fail
        #expect(throws: CiderDatabaseError.self) {
            try db.runSQL("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id)
                VALUES ('item1', 'bookmark', 'Test', 0.0, 0.0, 'nonexistent_folder');
                """)
        }
    }

    // MARK: - DatabaseHelpers Round-Trips

    @Test("UUID round-trips through encode/decode")
    func uuidRoundTrip() {
        let original = UUID()
        let encoded = DatabaseHelpers.encode(original)
        let decoded = DatabaseHelpers.decodeUUID(encoded)
        #expect(decoded == original)
    }

    @Test("Date round-trips through encode/decode")
    func dateRoundTrip() {
        let original = Date()
        let encoded = DatabaseHelpers.encode(original)
        let decoded = DatabaseHelpers.decodeDate(encoded)
        #expect(abs(decoded.timeIntervalSince(original)) < 0.001)
    }

    @Test("String array round-trips through JSON encode/decode")
    func stringArrayRoundTrip() {
        let original = ["hello", "world", "test with spaces"]
        let encoded = DatabaseHelpers.encode(original)
        let decoded = DatabaseHelpers.decodeStringArray(encoded)
        #expect(decoded == original)
    }

    @Test("Empty string array round-trips")
    func emptyStringArrayRoundTrip() {
        let original: [String] = []
        let encoded = DatabaseHelpers.encode(original)
        let decoded = DatabaseHelpers.decodeStringArray(encoded)
        #expect(decoded == original)
    }

    @Test("UUID array round-trips through JSON encode/decode")
    func uuidArrayRoundTrip() {
        let original = [UUID(), UUID(), UUID()]
        let encoded = DatabaseHelpers.encode(original)
        let decoded = DatabaseHelpers.decodeUUIDArray(encoded)
        #expect(decoded == original)
    }

    @Test("Nil JSON decodes to empty arrays")
    func nilJsonDecodesToEmpty() {
        #expect(DatabaseHelpers.decodeStringArray(nil).isEmpty)
        #expect(DatabaseHelpers.decodeUUIDArray(nil).isEmpty)
    }

    @Test("Codable round-trips through JSON encode/decode")
    func codableRoundTrip() {
        struct TestModel: Codable, Equatable {
            let name: String
            let count: Int
        }
        let original = TestModel(name: "test", count: 42)
        let encoded = DatabaseHelpers.encodeJSON(original)
        #expect(encoded != nil)
        let decoded = DatabaseHelpers.decodeJSON(TestModel.self, from: encoded)
        #expect(decoded == original)
    }

    // MARK: - SQLStatement

    @Test("SQLStatement bind and read round-trip")
    func statementBindAndRead() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let itemID = UUID().uuidString
        let now = Date().timeIntervalSinceReferenceDate

        // Insert using prepared statement
        let insert = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """)
        insert.bind(itemID, at: 1)
            .bind("bookmark", at: 2)
            .bind("Test Bookmark", at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
        try insert.step()

        // Read back using prepared statement
        let select = try db.prepare("SELECT id, type, title, created_at, folder_id FROM items WHERE id = ?;")
        select.bind(itemID, at: 1)
        let hasRow = try select.step()
        #expect(hasRow)
        #expect(select.string(at: 0) == itemID)
        #expect(select.string(at: 1) == "bookmark")
        #expect(select.string(at: 2) == "Test Bookmark")
        #expect(abs(select.double(at: 3) - now) < 0.001)
        #expect(select.optionalString(at: 4) == nil) // folder_id is NULL
    }

    @Test("CASCADE delete removes detail rows")
    func cascadeDelete() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let itemID = UUID().uuidString
        let now = Date().timeIntervalSinceReferenceDate

        // Insert item + bookmark detail
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at)
            VALUES ('\(itemID)', 'bookmark', 'Test', \(now), \(now));
            """)
        try db.runSQL("""
            INSERT INTO bookmarks (item_id, url) VALUES ('\(itemID)', 'https://example.com');
            """)

        // Delete the item - cascade should remove the bookmark row
        try db.runSQL("DELETE FROM items WHERE id = '\(itemID)';")

        let stmt = try db.prepare("SELECT count(*) FROM bookmarks WHERE item_id = ?;")
        stmt.bind(itemID, at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }
}
