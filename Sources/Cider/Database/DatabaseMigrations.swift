import Foundation
import SQLite3
import os

/// Version-based migration runner for the Cider SQLite database.
/// Tracks the current schema version and applies incremental migrations.
enum DatabaseMigrations {

    private static let logger = Logger(subsystem: "com.cider.app", category: "DatabaseMigrations")

    /// Highest schema version this build knows how to run against.
    /// Bump together with any new `migrateToVN` function.
    static let latestVersion: Int = 8

    /// Run all pending migrations on the given database connection.
    /// Creates the schema_version table if it does not exist.
    static func runMigrations(on db: OpaquePointer) throws {
        // Ensure schema_version table exists
        try runOnDB(db, CiderSchema.createSchemaVersion)

        var currentVersion = try readVersion(db)
        logger.info("Current schema version: \(currentVersion)")

        // Fail fast on a DB from a newer build. Silently running forward-only
        // migrations would leave an unknown schema in place and crash downstream
        // when columns/tables disagree.
        if currentVersion > latestVersion {
            logger.error("Schema version \(currentVersion) is newer than supported (\(latestVersion))")
            throw CiderDatabaseError.schemaTooNew(current: currentVersion, supported: latestVersion)
        }

        if currentVersion < 1 {
            try migrateToV1(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 2 {
            try migrateToV2(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 3 {
            try migrateToV3(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 4 {
            try migrateToV4(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 5 {
            try migrateToV5(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 6 {
            try migrateToV6(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 7 {
            try migrateToV7(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 8 {
            try migrateToV8(db)
        }
    }

    // MARK: - V7 -> V8: Direct action URLs for todos and events

    private static func migrateToV8(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 8...")

        try withTransaction(db) {
            if try tableExists(db, table: "todos"),
               !(try columnExists(db, table: "todos", column: "action_url")) {
                try runOnDB(db, "ALTER TABLE todos ADD COLUMN action_url TEXT;")
            }
            if try tableExists(db, table: "events"),
               !(try columnExists(db, table: "events", column: "action_url")) {
                try runOnDB(db, "ALTER TABLE events ADD COLUMN action_url TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (8);")
        }

        logger.info("Migration to v8 complete")
    }

    // MARK: - V6 -> V7: Contact custom fields

    private static func migrateToV7(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 7...")

        try withTransaction(db) {
            if try tableExists(db, table: "contacts"),
               !(try columnExists(db, table: "contacts", column: "custom_fields")) {
                try runOnDB(db, "ALTER TABLE contacts ADD COLUMN custom_fields TEXT NOT NULL DEFAULT '[]';")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (7);")
        }

        logger.info("Migration to v7 complete")
    }

    // MARK: - V5 -> V6: mutation audit log

    private static func migrateToV6(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 6...")

        try withTransaction(db) {
            try runOnDB(db, CiderSchema.createMutationAudit)
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_mutation_audit_time ON mutation_audit(occurred_at);")
            try runOnDB(db, "CREATE INDEX IF NOT EXISTS idx_mutation_audit_item ON mutation_audit(item_type, item_id, occurred_at);")
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (6);")
        }

        logger.info("Migration to v6 complete")
    }

    // MARK: - V4 -> V5: Note summaries move into SQLite

    private static func migrateToV5(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 5...")

        try withTransaction(db) {
            if try tableExists(db, table: "notes"),
               !(try columnExists(db, table: "notes", column: "summary")) {
                try runOnDB(db, "ALTER TABLE notes ADD COLUMN summary TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (5);")
        }

        logger.info("Migration to v5 complete")
    }

    // MARK: - V3 -> V4: Todo surfacing rules

    private static func migrateToV4(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 4...")

        try withTransaction(db) {
            if try tableExists(db, table: "todos"),
               !(try columnExists(db, table: "todos", column: "surfacing_rules")) {
                try runOnDB(db, "ALTER TABLE todos ADD COLUMN surfacing_rules TEXT;")
            }
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (4);")
        }

        logger.info("Migration to v4 complete")
    }

    // MARK: - V2 -> V3: Clean up ghost storage-type folder rows
    //
    // Older code paths wrote folder rows for paths under reserved top-level
    // directories (Inbox/Bookmarks, Unsorted/..., etc.). These aren't real
    // user folders — they're storage-type subtrees that the reconciler
    // correctly excludes from disk scans. The stale rows linger in the
    // `folders` table with live items attached, causing every reconcile to
    // log "Skipping removal of missing folder …" and blocking cleanup.
    //
    // This migration:
    //   1. Identifies folder rows whose path starts with a reserved top
    //      component.
    //   2. Re-parents any items and sessions pointing at them to NULL
    //      (semantically "unfiled", which puts them back in the Inbox view).
    //   3. Deletes the ghost folder rows.
    private static func migrateToV3(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 3...")

        // Top-level reserved directory names. Kept in sync with
        // VaultFolderService.reservedDirectoryNames — duplicated here so the
        // migration stays self-contained (no service-layer imports into the
        // DB layer).
        let reservedTopComponents: [String] = [
            "Inbox", "Unsorted",
            "Bookmarks", "Contacts", "DateCards", "Labels", "Notes",
            "SavedViews", "Sources", "Stacks", "Tags",
        ]

        try withTransaction(db) {
            var ghostIDs: [String] = []
            for top in reservedTopComponents {
                let escaped = top.replacingOccurrences(of: "'", with: "''")
                // Match "<reserved>" exactly OR "<reserved>/…". Don't match
                // "Inboxed" or similar unrelated prefixes.
                let pattern1 = "\(escaped)"
                let pattern2 = "\(escaped)/%"
                let sql = """
                    SELECT id FROM folders
                    WHERE relative_path = '\(pattern1)'
                       OR relative_path LIKE '\(pattern2)';
                    """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_finalize(stmt)
                    throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
                }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cID = sqlite3_column_text(stmt, 0) {
                        ghostIDs.append(String(cString: cID))
                    }
                }
                sqlite3_finalize(stmt)
            }

            if ghostIDs.isEmpty {
                logger.info("No ghost storage-type folders to clean up")
            } else {
                logger.info("Cleaning up \(ghostIDs.count) ghost storage-type folder(s)")
                for ghostID in ghostIDs {
                    let escaped = ghostID.replacingOccurrences(of: "'", with: "''")
                    // Re-parent dependents to NULL before deleting the row so
                    // the FK constraint doesn't reject the delete.
                    try runOnDB(db, "UPDATE items SET folder_id = NULL WHERE folder_id = '\(escaped)';")
                    try runOnDB(db, "UPDATE sessions SET folder_id = NULL WHERE folder_id = '\(escaped)';")
                    try runOnDB(db, "DELETE FROM folders WHERE id = '\(escaped)';")
                }
            }

            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (3);")
        }

        logger.info("Migration to v3 complete")
    }

    // MARK: - V1 -> V2: vault_files.title_manually_set + schema_migrations table

    private static func migrateToV2(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 2...")

        try withTransaction(db) {
            if try tableExists(db, table: "vault_files") {
                // Idempotent ALTER: only add the column if it's not already present.
                if !(try columnExists(db, table: "vault_files", column: "title_manually_set")) {
                    try runOnDB(db, "ALTER TABLE vault_files ADD COLUMN title_manually_set INTEGER NOT NULL DEFAULT 0;")
                }
            } else {
                logger.warning("Schema version 1 is missing vault_files; skipping v2 ALTER TABLE")
            }
            // Ensure the named-migration ledger exists (harmless if already created by v1 fresh installs).
            try runOnDB(db, CiderSchema.createSchemaMigrations)
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (2);")
        }

        logger.info("Migration to v2 complete")
    }

    private static func tableExists(_ db: OpaquePointer, table: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escapedTable)' LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }

        let step = sqlite3_step(stmt)
        if step == SQLITE_ROW {
            return true
        }
        if step == SQLITE_DONE {
            return false
        }
        throw CiderDatabaseError.step(String(cString: sqlite3_errmsg(db)))
    }

    /// Returns true if `column` exists on `table` (queries PRAGMA table_info).
    private static func columnExists(_ db: OpaquePointer, table: String, column: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CiderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Column 1 of table_info is the column name.
            if let cName = sqlite3_column_text(stmt, 1) {
                let name = String(cString: cName)
                if name == column { return true }
            }
        }
        return false
    }

    // MARK: - V0 -> V1: Create all tables

    private static func migrateToV1(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 1...")

        try withTransaction(db) {
            // Create all tables in dependency order
            for sql in CiderSchema.allTables {
                try runOnDB(db, sql)
            }

            // Create all indexes
            for sql in CiderSchema.createIndexes {
                try runOnDB(db, sql)
            }

            // Set version to 1 (keep schema_version as a single-row table).
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (1);")
        }

        logger.info("Migration to v1 complete")
    }

    // MARK: - Helpers

    private static func readVersion(_ db: OpaquePointer) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let rc = sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version;", -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CiderDatabaseError.prepare(message)
        }

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        // No rows means version 0 (fresh database)
        return 0
    }

    private static func withTransaction(_ db: OpaquePointer, body: () throws -> Void) throws {
        try runOnDB(db, "BEGIN TRANSACTION;")
        do {
            try body()
            try runOnDB(db, "COMMIT;")
        } catch {
            try? runOnDB(db, "ROLLBACK;")
            throw error
        }
    }

    private static func runOnDB(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            throw CiderDatabaseError.runExec(message)
        }
    }
}
