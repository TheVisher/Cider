import Foundation
import SQLite3
import os

struct DatabaseIntegrityStatus: Equatable {
    let messages: [String]

    var isHealthy: Bool {
        messages.count == 1 && messages[0].caseInsensitiveCompare("ok") == .orderedSame
    }
}

/// SQLite database connection manager for Cider.
/// Not a singleton — instantiate for testing, share one instance in the app.
@MainActor
final class CiderDatabase {
    private enum TransactionMode: Equatable {
        case deferred
        case immediate
    }

    /// Shared app-wide database instance. Must be opened during app launch.
    static let shared = CiderDatabase()

    private let logger = Logger(subsystem: "com.cider.app", category: "CiderDatabase")
    private var db: OpaquePointer?
    private(set) var databaseURL: URL?
    private(set) var lastMigrationSafetyArtifactURL: URL?
    private var transactionDepth = 0
    private var rootTransactionMode: TransactionMode?

    /// Whether the database connection is currently open.
    var isOpen: Bool { db != nil }

    // MARK: - Lifecycle

    /// Open the database at the given file URL.
    /// Creates the file if it does not exist. Existing sources are validated
    /// without mutation before open; older healthy sources receive a mandatory
    /// verified SQLite safety artifact before migrations can write.
    func open(at url: URL) throws {
        let path = url.path
        // Refuse double-open — a second call would leak the prior handle and
        // potentially point at a different file. Callers must close() first if
        // they really want to reopen.
        if db != nil {
            throw CiderDatabaseError.alreadyOpen(path)
        }
        lastMigrationSafetyArtifactURL = nil
        logger.info("Opening database at \(path)")

        let startupLock = try DatabaseStartupLock.acquire(for: url)
        defer { startupLock.release() }

        // Freshness is authoritative only after Cider startup serialization,
        // and remains provisional until the SQLite VFS atomically reserves the
        // path and an IMMEDIATE transaction verifies that it is still empty.
        var sourceState = try DatabaseStartupPreflight.sourceState(at: url)
        var isFreshDatabase = false

        var handle: OpaquePointer?
        var inspection: ExistingDatabaseInspection?
        var reservationActive = false
        var sourceSchemaVersion = 0
        var migrationArtifact: DatabaseMigrationSafetyArtifact?

        do {
            if sourceState == .fresh {
                switch try DatabaseStartupPreflight.reserveFreshDatabasePath(at: url) {
                case .reserved(let pathReservation):
                    if let freshHandle = try DatabaseStartupPreflight
                        .openAuthoritativelyReservedFreshDatabase(
                            at: url,
                            reservation: pathReservation
                        ) {
                        handle = freshHandle
                        reservationActive = true
                        isFreshDatabase = true
                    } else {
                        sourceState = try DatabaseStartupPreflight.sourceState(at: url)
                    }
                case .sourceAppeared:
                    sourceState = try DatabaseStartupPreflight.sourceState(at: url)
                }
                if !isFreshDatabase, sourceState != .existing {
                    throw CiderDatabaseError.startupPreflightFailed(
                        kind: .changedDuringRead,
                        detail: "The database path changed repeatedly during atomic fresh creation. Retry after other creators become idle."
                    )
                }
            }

            if !isFreshDatabase {
                // First establish health without source mutation. Then reserve
                // the real SQLite source and revalidate it authoritatively so
                // the verified artifact and migration use one logical snapshot.
                let established = try DatabaseStartupPreflight.establishExistingDatabaseHealth(at: url)
                inspection = established
                sourceSchemaVersion = established.schemaVersion
                if sourceSchemaVersion < DatabaseMigrations.latestVersion {
                    let artifact = try DatabaseStartupPreflight.createRequiredMigrationSafetyArtifact(
                        from: established,
                        sourceDatabaseURL: url
                    )
                    migrationArtifact = artifact
                    lastMigrationSafetyArtifactURL = artifact.url
                }

                let reservation = try DatabaseStartupPreflight.reserveAndRevalidateExistingDatabase(at: url)
                handle = reservation.handle
                reservationActive = true
                sourceSchemaVersion = reservation.schemaVersion
                try DatabaseStartupPreflight.validateAuthoritativeSourceContinuity(
                    reservation,
                    matches: established
                )
                try DatabaseStartupPreflight.validateAuthoritativeSourceContinuity(
                    reservation,
                    at: url
                )
                established.close()
                inspection = nil
                if sourceSchemaVersion == DatabaseMigrations.latestVersion {
                    try DatabaseStartupPreflight.cancelAuthoritativeReservation(reservation.handle)
                    reservationActive = false
                }
            }

            guard let handle else {
                throw CiderDatabaseError.open("SQLite returned no database handle")
            }
            sqlite3_busy_timeout(handle, 5000)
            // Enable foreign key enforcement
            try runSQL("PRAGMA foreign_keys=ON;", on: handle)

            if isFreshDatabase {
                try DatabaseMigrations.runMigrations(
                    on: handle,
                    insideExistingImmediateTransaction: true
                )
                reservationActive = false
            } else if sourceSchemaVersion < DatabaseMigrations.latestVersion {
                do {
                    try DatabaseMigrations.runMigrations(
                        on: handle,
                        insideExistingImmediateTransaction: true
                    )
                    reservationActive = false
                } catch {
                    reservationActive = sqlite3_get_autocommit(handle) == 0
                    if let migrationArtifact {
                        throw CiderDatabaseError.migrationFailed(
                            artifactURL: migrationArtifact.url,
                            detail: error.localizedDescription
                        )
                    }
                    throw error
                }
            }

            // WAL is configured only after an existing source passed preflight
            // and any required migration transaction committed.
            try runSQL("PRAGMA journal_mode=WAL;", on: handle)

            // No recovery/reconcile/service writer is composed until this final
            // validation confirms the migrated/current database is usable.
            try DatabaseStartupPreflight.validatePostOpenDatabase(handle)

            db = handle
            databaseURL = url
        } catch {
            inspection?.close()
            if reservationActive, let handle {
                try? DatabaseStartupPreflight.cancelAuthoritativeReservation(handle)
            }
            sqlite3_close_v2(handle)
            db = nil
            databaseURL = nil
            throw error
        }

        logger.info("Database opened successfully")
    }

    /// Close the database connection.
    func close() {
        guard let db else { return }
        sqlite3_close_v2(db)
        self.db = nil
        self.databaseURL = nil
        self.transactionDepth = 0
        self.rootTransactionMode = nil
        logger.info("Database closed")
    }

    // Note: No deinit — callers must call close() explicitly.
    // Swift 6 strict concurrency prevents accessing @MainActor state from nonisolated deinit.

    // MARK: - SQL Operations

    /// Run a SQL string that does not return results (DDL, INSERT, UPDATE, DELETE).
    func runSQL(_ sql: String) throws {
        guard let db else { throw CiderDatabaseError.runExec("Database not open") }
        try runSQL(sql, on: db)
    }

    private func runSQL(_ sql: String, on handle: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            if rc == SQLITE_BUSY || rc == SQLITE_LOCKED {
                throw CiderDatabaseError.busy(message)
            }
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
    func withTransaction<T>(_ body: @MainActor () throws -> T) throws -> T {
        try withTransaction(mode: .deferred, body)
    }

    /// Acquires SQLite's single-writer reservation before the body performs any
    /// authoritative reads. This prevents a deferred read snapshot from becoming
    /// stale before its first write on another physical WAL connection.
    func withImmediateTransaction<T>(_ body: @MainActor () throws -> T) throws -> T {
        try withTransaction(mode: .immediate, body)
    }

    private func withTransaction<T>(
        mode: TransactionMode,
        _ body: @MainActor () throws -> T
    ) throws -> T {
        let isNested = transactionDepth > 0
        let savepointName = "cider_transaction_\(transactionDepth + 1)"
        if isNested {
            guard let rootTransactionMode else {
                throw CiderDatabaseError.transactionState(
                    "Nested transaction depth has no root transaction mode."
                )
            }
            if mode == .immediate, rootTransactionMode == .deferred {
                throw CiderDatabaseError.immediateTransactionRequiresImmediateRoot
            }
            try runSQL("SAVEPOINT \(savepointName);")
        } else {
            guard rootTransactionMode == nil else {
                throw CiderDatabaseError.transactionState(
                    "Root transaction mode remained set after the previous transaction."
                )
            }
            let beginStatement = switch mode {
            case .deferred: "BEGIN TRANSACTION;"
            case .immediate: "BEGIN IMMEDIATE TRANSACTION;"
            }
            try runSQL(beginStatement)
            rootTransactionMode = mode
        }

        transactionDepth += 1
        defer {
            transactionDepth -= 1
            if !isNested {
                rootTransactionMode = nil
            }
        }

        do {
            let result = try body()
            if isNested {
                try runSQL("RELEASE SAVEPOINT \(savepointName);")
            } else {
                try runSQL("COMMIT;")
            }
            return result
        } catch {
            if isNested {
                try? runSQL("ROLLBACK TO SAVEPOINT \(savepointName);")
                try? runSQL("RELEASE SAVEPOINT \(savepointName);")
            } else {
                try? runSQL("ROLLBACK;")
            }
            throw error
        }
    }

    /// Force a checkpoint so the main database file is current before backup/inspection work.
    func checkpointWal(mode: String = "TRUNCATE") throws {
        try runSQL("PRAGMA wal_checkpoint(\(mode));")
    }

    /// Run `PRAGMA integrity_check` and return the raw status rows.
    func integrityCheck() throws -> DatabaseIntegrityStatus {
        let stmt = try prepare("PRAGMA integrity_check;")
        var messages: [String] = []
        while try stmt.step() {
            messages.append(stmt.string(at: 0))
        }
        return DatabaseIntegrityStatus(messages: messages)
    }

    /// Create a portable SQLite backup using `VACUUM INTO`.
    func vacuum(into destinationURL: URL) throws {
        let escapedPath = destinationURL.path.replacingOccurrences(of: "'", with: "''")
        try runSQL("VACUUM INTO '\(escapedPath)';")
    }
}
