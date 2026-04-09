import Foundation
import SQLite3
import os

/// SQLite database connection manager for Cider.
/// Not a singleton — instantiate for testing, share one instance in the app.
@MainActor
final class CiderDatabase {

    private let logger = Logger(subsystem: "com.cider.app", category: "CiderDatabase")
    private var db: OpaquePointer?

    /// Whether the database connection is currently open.
    var isOpen: Bool { db != nil }

    // MARK: - Lifecycle

    /// Open the database at the given file URL.
    /// Creates the file if it does not exist. Enables WAL mode, foreign keys,
    /// and runs pending schema migrations.
    func open(at url: URL) throws {
        let path = url.path
        logger.info("Opening database at \(path)")

        var handle: OpaquePointer?
        let rc = sqlite3_open(path, &handle)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw CiderDatabaseError.open(message)
        }

        db = handle

        // Enable WAL mode for concurrent reads
        try runSQL("PRAGMA journal_mode=WAL;")
        // Enable foreign key enforcement
        try runSQL("PRAGMA foreign_keys=ON;")

        // Run schema migrations
        try DatabaseMigrations.runMigrations(on: handle)

        logger.info("Database opened successfully")
    }

    /// Close the database connection.
    func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
        logger.info("Database closed")
    }

    // Note: No deinit — callers must call close() explicitly.
    // Swift 6 strict concurrency prevents accessing @MainActor state from nonisolated deinit.

    // MARK: - SQL Operations

    /// Run a SQL string that does not return results (DDL, INSERT, UPDATE, DELETE).
    func runSQL(_ sql: String) throws {
        guard let db else { throw CiderDatabaseError.runExec("Database not open") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw CiderDatabaseError.runExec(message)
        }
    }

    /// Prepare a SQL statement for binding and stepping.
    func prepare(_ sql: String) throws -> SQLStatement {
        guard let db else { throw CiderDatabaseError.prepare("Database not open") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CiderDatabaseError.prepare(message)
        }
        return SQLStatement(stmt)
    }

    /// Run a block inside a SQLite transaction.
    /// Commits on success, rolls back on throw.
    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try runSQL("BEGIN TRANSACTION;")
        do {
            let result = try body()
            try runSQL("COMMIT;")
            return result
        } catch {
            try? runSQL("ROLLBACK;")
            throw error
        }
    }
}
