import Foundation
import SQLite3
import os

/// Version-based migration runner for the Cider SQLite database.
/// Tracks the current schema version and applies incremental migrations.
enum DatabaseMigrations {

    private static let logger = Logger(subsystem: "com.cider.app", category: "DatabaseMigrations")

    /// Run all pending migrations on the given database connection.
    /// Creates the schema_version table if it does not exist.
    static func runMigrations(on db: OpaquePointer) throws {
        // Ensure schema_version table exists
        try runOnDB(db, CiderSchema.createSchemaVersion)

        var currentVersion = try readVersion(db)
        logger.info("Current schema version: \(currentVersion)")

        if currentVersion < 1 {
            try migrateToV1(db)
            currentVersion = try readVersion(db)
        }
        if currentVersion < 2 {
            try migrateToV2(db)
        }
    }

    // MARK: - V1 -> V2: vault_files.title_manually_set + schema_migrations table

    private static func migrateToV2(_ db: OpaquePointer) throws {
        logger.info("Migrating to schema version 2...")

        try withTransaction(db) {
            // Idempotent ALTER: only add the column if it's not already present.
            if !(try columnExists(db, table: "vault_files", column: "title_manually_set")) {
                try runOnDB(db, "ALTER TABLE vault_files ADD COLUMN title_manually_set INTEGER NOT NULL DEFAULT 0;")
            }
            // Ensure the named-migration ledger exists (harmless if already created by v1 fresh installs).
            try runOnDB(db, CiderSchema.createSchemaMigrations)
            try runOnDB(db, "DELETE FROM schema_version;")
            try runOnDB(db, "INSERT INTO schema_version (version) VALUES (2);")
        }

        logger.info("Migration to v2 complete")
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
