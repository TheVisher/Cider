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

    @Test("Opens database and creates schema at latest version")
    func openCreatesSchema() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        // Verify schema version is at the latest. schema_version is a
        // single-row table after migration.
        let stmt = try db.prepare("SELECT MAX(version) FROM schema_version;")
        let hasRow = try stmt.step()
        #expect(hasRow)
        #expect(stmt.int(at: 0) == DatabaseMigrations.latestVersion)
    }

    @Test("Open configures a busy timeout for writer contention")
    func openConfiguresBusyTimeout() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let stmt = try db.prepare("PRAGMA busy_timeout;")
        let hasRow = try stmt.step()
        #expect(hasRow)
        #expect(stmt.int(at: 0) == 5000)
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
            "item_links", "owner_relations", "projects", "capture_events",
            "capture_attachments", "enrichment_outputs", "similarity_candidates",
            "similarity_reconciliation_runs", "action_receipts",
            "trash", "mutation_audit", "folder_sync_decisions",
            "schema_version", "schema_migrations",
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

    @Test("Integrity check returns ok for a healthy database")
    func integrityCheckPasses() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let status = try db.integrityCheck()
        #expect(status.isHealthy)
        #expect(status.messages == ["ok"])
    }

    @Test("VACUUM INTO creates a portable backup containing current data")
    func vacuumIntoCreatesBackup() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let insert = try db.prepare(
            "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        )
        insert.bind("backup-label", at: 1)
            .bind("Backed Up", at: 2)
            .bind("#FF0000", at: 3)
            .bind("custom", at: 4)
            .bind(0.0, at: 5)
            .bind(0.0, at: 6)
        try insert.step()

        let backupURL = url.deletingPathExtension().appendingPathExtension("backup.db")
        defer { cleanup(backupURL) }

        try db.vacuum(into: backupURL)

        let backupDB = CiderDatabase()
        try backupDB.open(at: backupURL)
        defer { backupDB.close() }

        let stmt = try backupDB.prepare("SELECT name FROM labels WHERE id = ?;")
        stmt.bind("backup-label", at: 1)
        #expect(try stmt.step())
        #expect(stmt.string(at: 0) == "Backed Up")
    }

    @Test("DatabaseSafetyService captures a pre-open snapshot of database files")
    func preOpenSnapshotCopiesDatabaseFiles() throws {
        let isolatedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-db-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        let url = isolatedDir.appendingPathComponent("cider.db")
        defer { try? FileManager.default.removeItem(at: isolatedDir) }

        let db = CiderDatabase()
        try db.open(at: url)
        let insert = try db.prepare(
            "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        )
        insert.bind("snapshot-label", at: 1)
            .bind("Snapshot", at: 2)
            .bind("#00FF00", at: 3)
            .bind("custom", at: 4)
            .bind(0.0, at: 5)
            .bind(0.0, at: 6)
        try insert.step()
        db.close()

        let walURL = URL(fileURLWithPath: url.path + "-wal")
        try Data("wal".utf8).write(to: walURL)
        defer { try? FileManager.default.removeItem(at: walURL) }

        let service = DatabaseSafetyService()
        service.capturePreOpenSnapshotIfNeeded(databaseURL: url)

        let preflightDir = service.preOpenSnapshotsDirectory(for: url)
        let snapshots = try FileManager.default.contentsOfDirectory(at: preflightDir, includingPropertiesForKeys: nil)
        #expect(!snapshots.isEmpty)

        let matchingSnapshot = snapshots.first { snapshotURL in
            let dbCopy = snapshotURL.appendingPathComponent(url.lastPathComponent).path
            let walCopy = snapshotURL.appendingPathComponent(walURL.lastPathComponent).path
            return FileManager.default.fileExists(atPath: dbCopy)
                && FileManager.default.fileExists(atPath: walCopy)
        }

        #expect(matchingSnapshot != nil)
    }

    @Test("DatabaseSafetyService lists rolling backups newest first")
    func listRollingBackupsNewestFirst() throws {
        let isolatedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-db-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        let url = isolatedDir.appendingPathComponent("cider.db")
        defer { try? FileManager.default.removeItem(at: isolatedDir) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let service = DatabaseSafetyService()
        let first = try service.createRollingBackup(reason: "first", database: db)
        Thread.sleep(forTimeInterval: 1.1)
        let second = try service.createRollingBackup(reason: "second", database: db)

        let backups = service.listRollingBackups(databaseURL: url)
        #expect(backups.count == 2)
        #expect(backups[0].url.standardizedFileURL == second.standardizedFileURL)
        #expect(backups[1].url.standardizedFileURL == first.standardizedFileURL)
    }

    @Test("Restoring a rolling backup replaces the current database contents")
    func restoreRollingBackupReplacesDatabaseContents() throws {
        let isolatedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-db-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        let url = isolatedDir.appendingPathComponent("cider.db")
        defer { try? FileManager.default.removeItem(at: isolatedDir) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        let originalInsert = try db.prepare(
            "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        )
        originalInsert.bind("restore-original", at: 1)
            .bind("Original", at: 2)
            .bind("#111111", at: 3)
            .bind("custom", at: 4)
            .bind(0.0, at: 5)
            .bind(0.0, at: 6)
        try originalInsert.step()

        let service = DatabaseSafetyService()
        let backupURL = try service.createRollingBackup(reason: "restore-test", database: db)

        let changedInsert = try db.prepare(
            "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        )
        changedInsert.bind("restore-after", at: 1)
            .bind("After Backup", at: 2)
            .bind("#222222", at: 3)
            .bind("custom", at: 4)
            .bind(0.0, at: 5)
            .bind(0.0, at: 6)
        try changedInsert.step()

        let result = try service.restoreRollingBackup(
            from: backupURL,
            into: url,
            database: db,
            reopenDatabase: true
        )
        #expect(result.restoredBackup.url == backupURL)
        #expect(result.preRestoreSnapshotURL != nil)

        let originalLookup = try db.prepare("SELECT name FROM labels WHERE id = ?;")
        originalLookup.bind("restore-original", at: 1)
        #expect(try originalLookup.step())
        #expect(originalLookup.string(at: 0) == "Original")

        let changedLookup = try db.prepare("SELECT count(*) FROM labels WHERE id = ?;")
        changedLookup.bind("restore-after", at: 1)
        #expect(try changedLookup.step())
        #expect(changedLookup.int(at: 0) == 0)
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
        let insertFolder = try db1.prepare(
            "INSERT INTO folders (id, relative_path, created_at, updated_at) VALUES (?, ?, 0.0, 0.0);"
        )
        insertFolder.bind(folderID, at: 1).bind("test/path", at: 2)
        try insertFolder.step()
        db1.close()

        // Second open: verify data persists and version is still at the latest
        let db2 = CiderDatabase()
        try db2.open(at: url)
        defer { db2.close() }

        let folderStmt = try db2.prepare("SELECT relative_path FROM folders WHERE id = ?;")
        folderStmt.bind(folderID, at: 1)
        let hasRow = try folderStmt.step()
        #expect(hasRow)
        #expect(folderStmt.string(at: 0) == "test/path")

        let versionStmt = try db2.prepare("SELECT MAX(version) FROM schema_version;")
        try versionStmt.step()
        #expect(versionStmt.int(at: 0) == DatabaseMigrations.latestVersion)
    }

    // MARK: - Double-open guard

    @Test("open() throws when the database is already open")
    func openThrowsWhenAlreadyOpen() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        #expect(throws: CiderDatabaseError.self) {
            try db.open(at: url)
        }
    }

    @Test("open() succeeds again after close()")
    func openSucceedsAfterClose() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        db.close()
        try db.open(at: url)
        db.close()
    }

    // MARK: - Schema version guard

    @Test("open() throws when schema_version is newer than supported")
    func openThrowsOnFutureSchema() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        // First create a valid database at the current version, then bump
        // schema_version to simulate a DB written by a newer build.
        do {
            let db = CiderDatabase()
            try db.open(at: url)
            let future = DatabaseMigrations.latestVersion + 1
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (\(future));")
            db.close()
        }

        let db2 = CiderDatabase()
        #expect(throws: CiderDatabaseError.self) {
            try db2.open(at: url)
        }
    }

    @Test("v10 migration repairs legacy routing_decisions table from a v9 database")
    func v10RepairsLegacyRoutingDecisionsTable() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let folderID = UUID().uuidString
        let itemID = UUID().uuidString
        let decisionID = UUID().uuidString

        do {
            let db = CiderDatabase()
            try db.open(at: url)
            try db.runSQL("""
                INSERT INTO folders (id, relative_path, created_at, updated_at)
                VALUES ('\(folderID)', 'Spaces/Recipes', 0.0, 0.0);
                """)
            try db.runSQL("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES ('\(itemID)', 'bookmark', 'Legacy Route', 0.0, 0.0, '\(folderID)', 'Spaces/Recipes/Legacy Route.md');
                """)
            try db.runSQL("DROP TABLE routing_decisions;")
            try db.runSQL("""
                CREATE TABLE routing_decisions (
                    id TEXT PRIMARY KEY,
                    item_id TEXT,
                    owner_type TEXT NOT NULL,
                    owner_id TEXT NOT NULL,
                    target_type TEXT NOT NULL,
                    target_id TEXT,
                    target_path TEXT,
                    confidence REAL NOT NULL,
                    reason TEXT NOT NULL,
                    status TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    source TEXT NOT NULL,
                    candidates_json TEXT,
                    created_at REAL NOT NULL,
                    reviewed_at REAL
                );
                """)
            try db.runSQL("""
                INSERT INTO routing_decisions (
                    id, item_id, owner_type, owner_id, target_type, target_id,
                    target_path, confidence, reason, status, actor, source,
                    candidates_json, created_at, reviewed_at
                ) VALUES (
                    '\(decisionID)', '\(itemID)', 'bookmark', '\(itemID)', 'folder', '\(folderID)',
                    'Spaces/Recipes', 0.82, 'Legacy candidate route.', 'needs_review',
                    'agent', 'legacy.routing', '[]', 1234.0, NULL
                );
                """)
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (9);")
            db.close()
        }

        let migrated = CiderDatabase()
        try migrated.open(at: url)
        defer { migrated.close() }

        let versionStmt = try migrated.prepare("SELECT MAX(version) FROM schema_version;")
        #expect(try versionStmt.step())
        #expect(versionStmt.int(at: 0) == DatabaseMigrations.latestVersion)

        let stmt = try migrated.prepare("""
            SELECT item_type, target_kind, target_name, target_relative_path,
                   target_folder_id, confidence, reason, actor, source, review_state,
                   created_at, supersedes_decision_id
            FROM routing_decisions
            WHERE id = ?;
            """)
        stmt.bind(decisionID, at: 1)
        #expect(try stmt.step())
        #expect(stmt.string(at: 0) == "bookmark")
        #expect(stmt.string(at: 1) == "folder")
        #expect(stmt.string(at: 2) == "Recipes")
        #expect(stmt.string(at: 3) == "Spaces/Recipes")
        #expect(stmt.string(at: 4) == folderID)
        #expect(stmt.double(at: 5) == 0.82)
        #expect(stmt.string(at: 6) == "Legacy candidate route.")
        #expect(stmt.string(at: 7) == "agent")
        #expect(stmt.string(at: 8) == "legacy.routing")
        #expect(stmt.string(at: 9) == "needs_review")
        #expect(stmt.double(at: 10) == 1234.0)
        #expect(stmt.optionalString(at: 11) == nil)

        let legacyBackup = try migrated.prepare(
            "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'routing_decisions_legacy_v9';"
        )
        #expect(try legacyBackup.step())
        #expect(legacyBackup.int(at: 0) == 1)
    }

    @Test("v11 migration adds snoozedUntil columns to todo and event tables")
    func v11AddsReminderSnoozeColumns() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        do {
            let db = CiderDatabase()
            try db.open(at: url)
            try db.runSQL("DROP TABLE todos;")
            try db.runSQL("""
                CREATE TABLE todos (
                    item_id      TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
                    details      TEXT NOT NULL DEFAULT '',
                    due_date     REAL,
                    priority     TEXT,
                    is_completed INTEGER NOT NULL DEFAULT 0,
                    completed_at REAL,
                    notes        TEXT NOT NULL DEFAULT '',
                    checklist    TEXT,
                    surfacing_rules TEXT,
                    action_url   TEXT
                );
                """)
            try db.runSQL("DROP TABLE events;")
            try db.runSQL("""
                CREATE TABLE events (
                    item_id         TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
                    details         TEXT NOT NULL DEFAULT '',
                    start_at        REAL NOT NULL,
                    end_at          REAL,
                    all_day         INTEGER NOT NULL DEFAULT 0,
                    location        TEXT NOT NULL DEFAULT '',
                    amount          REAL,
                    recurrence_rule TEXT,
                    is_completed    INTEGER NOT NULL DEFAULT 0,
                    completed_at    REAL,
                    surfacing_rules TEXT,
                    action_url      TEXT
                );
                """)
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (10);")
            db.close()
        }

        let migrated = CiderDatabase()
        try migrated.open(at: url)
        defer { migrated.close() }

        let versionStmt = try migrated.prepare("SELECT MAX(version) FROM schema_version;")
        #expect(try versionStmt.step())
        #expect(versionStmt.int(at: 0) == DatabaseMigrations.latestVersion)
        #expect(try columnExists("snoozed_until", in: "todos", db: migrated))
        #expect(try columnExists("snoozed_until", in: "events", db: migrated))
    }

    @Test("v12 migration adds durable folder sync decisions")
    func v12AddsFolderSyncDecisions() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        do {
            let db = CiderDatabase()
            try db.open(at: url)
            try db.runSQL("DROP TABLE IF EXISTS folder_sync_decisions;")
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (11);")
            db.close()
        }

        let migrated = CiderDatabase()
        try migrated.open(at: url)
        defer { migrated.close() }

        let versionStmt = try migrated.prepare("SELECT MAX(version) FROM schema_version;")
        #expect(try versionStmt.step())
        #expect(versionStmt.int(at: 0) == DatabaseMigrations.latestVersion)

        let tableStmt = try migrated.prepare(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='folder_sync_decisions';"
        )
        #expect(try tableStmt.step())
        #expect(tableStmt.int(at: 0) == 1)

        #expect(try columnExists("remote_folder_id", in: "folder_sync_decisions", db: migrated))
        #expect(try columnExists("local_folder_id", in: "folder_sync_decisions", db: migrated))
        #expect(try columnExists("decision", in: "folder_sync_decisions", db: migrated))
        #expect(try columnExists("reason", in: "folder_sync_decisions", db: migrated))
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
            let insert = try db.prepare(
                "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
            )
            insert.bind("label1", at: 1)
                .bind("Test", at: 2)
                .bind("#FF0000", at: 3)
                .bind("custom", at: 4)
                .bind(0.0, at: 5)
                .bind(0.0, at: 6)
            try insert.step()
        }

        let stmt = try db.prepare("SELECT name FROM labels WHERE id = ?;")
        stmt.bind("label1", at: 1)
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
                let insert = try db.prepare(
                    "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
                )
                insert.bind("label2", at: 1)
                    .bind("RolledBack", at: 2)
                    .bind("#00FF00", at: 3)
                    .bind("custom", at: 4)
                    .bind(0.0, at: 5)
                    .bind(0.0, at: 6)
                try insert.step()
                // Force an error with invalid SQL
                try db.runSQL("INSERT INTO nonexistent_table VALUES (1);")
            }
        } catch {
            // Expected
        }

        // The label should not exist because the transaction was rolled back
        let stmt = try db.prepare("SELECT count(*) FROM labels WHERE id = ?;")
        stmt.bind("label2", at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    @Test("Nested successful transaction commits with outer transaction")
    func nestedSuccessfulTransactionCommitsWithOuterTransaction() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        let db = CiderDatabase()
        try db.open(at: url)
        defer { db.close() }

        try db.withTransaction {
            let outer = try db.prepare(
                "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
            )
            outer.bind("outer-label", at: 1)
                .bind("Outer", at: 2)
                .bind("#111111", at: 3)
                .bind("custom", at: 4)
                .bind(0.0, at: 5)
                .bind(0.0, at: 6)
            try outer.step()

            try db.withTransaction {
                let inner = try db.prepare(
                    "INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
                )
                inner.bind("inner-label", at: 1)
                    .bind("Inner", at: 2)
                    .bind("#222222", at: 3)
                    .bind("custom", at: 4)
                    .bind(0.0, at: 5)
                    .bind(0.0, at: 6)
                try inner.step()
            }
        }

        let stmt = try db.prepare("SELECT count(*) FROM labels WHERE id IN (?, ?);")
        stmt.bind("outer-label", at: 1)
            .bind("inner-label", at: 2)
        try stmt.step()
        #expect(stmt.int(at: 0) == 2)
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
            let stmt = try db.prepare(
                "INSERT INTO items (id, type, title, created_at, updated_at, folder_id) VALUES (?, ?, ?, ?, ?, ?);"
            )
            stmt.bind("item1", at: 1)
                .bind("bookmark", at: 2)
                .bind("Test", at: 3)
                .bind(0.0, at: 4)
                .bind(0.0, at: 5)
                .bind("nonexistent_folder", at: 6)
            try stmt.step()
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

    @Test("Malformed array JSON decodes to empty arrays")
    func malformedArrayJsonDecodesToEmpty() {
        #expect(DatabaseHelpers.decodeStringArray("not-json").isEmpty)
        #expect(DatabaseHelpers.decodeStringArray("{\"value\":\"not an array\"}").isEmpty)
        #expect(DatabaseHelpers.decodeUUIDArray("[\"not-a-uuid\"]").isEmpty)
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
        let now = Date().timeIntervalSince1970

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
        let now = Date().timeIntervalSince1970

        // Insert item + bookmark detail
        let insertItem = try db.prepare(
            "INSERT INTO items (id, type, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
        )
        insertItem.bind(itemID, at: 1)
            .bind("bookmark", at: 2)
            .bind("Test", at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
        try insertItem.step()

        let insertBookmark = try db.prepare(
            "INSERT INTO bookmarks (item_id, url) VALUES (?, ?);"
        )
        insertBookmark.bind(itemID, at: 1).bind("https://example.com", at: 2)
        try insertBookmark.step()

        // Delete the item - cascade should remove the bookmark row
        let deleteItem = try db.prepare("DELETE FROM items WHERE id = ?;")
        deleteItem.bind(itemID, at: 1)
        try deleteItem.step()

        let stmt = try db.prepare("SELECT count(*) FROM bookmarks WHERE item_id = ?;")
        stmt.bind(itemID, at: 1)
        try stmt.step()
        #expect(stmt.int(at: 0) == 0)
    }

    private func columnExists(_ column: String, in table: String, db: CiderDatabase) throws -> Bool {
        let stmt = try db.prepare("PRAGMA table_info(\(table));")
        while try stmt.step() {
            if stmt.string(at: 1) == column {
                return true
            }
        }
        return false
    }
}
