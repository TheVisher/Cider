import Darwin
import CryptoKit
import Foundation
import SQLite3
import os

struct DatabaseIntegrityStatus: Equatable {
    let messages: [String]

    var isHealthy: Bool {
        messages.count == 1 && messages[0].caseInsensitiveCompare("ok") == .orderedSame
    }
}

struct DatabaseSourceLineage: Equatable {
    struct ObjectIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let owner: uid_t
        let mode: mode_t
    }

    let source: ObjectIdentity
    let parent: ObjectIdentity
    let sourceFilename: String
    let identifier: String

    init(source: ObjectIdentity, parent: ObjectIdentity, sourceFilename: String) {
        self.source = source
        self.parent = parent
        self.sourceFilename = sourceFilename
        let material = "\(source.device):\(source.inode):\(source.owner):"
            + "\(parent.device):\(parent.inode):\(parent.owner):\(sourceFilename)"
        identifier = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum CiderDatabaseBackupCapacityError: Error, LocalizedError, Equatable {
    case sourceSetOverflow
    case captureExceedsReservation(actual: Int64, reserved: Int64)

    var errorDescription: String? {
        switch self {
        case .sourceSetOverflow:
            "The pinned SQLite DB/WAL/SHM byte upper bound overflowed Int64."
        case .captureExceedsReservation(let actual, let reserved):
            "The coherent SQLite image grew to \(actual) bytes after aggregate admission reserved \(reserved) bytes. No image bytes were written."
        }
    }
}

/// A process-scoped observation that proves a SQLite pathname and its parent
/// remained the same owned, non-publicly-writable objects. It leaves no
/// filesystem metadata behind if the process is interrupted.
final class DatabaseSourceLineageObservation {
    private let sourceURL: URL
    private let parentURL: URL
    private let sourceDescriptor: Int32
    private let parentDescriptor: Int32
    private let queueDescriptor: Int32
    private let captured: DatabaseSourceLineage

    init(databaseURL: URL) throws {
        sourceURL = databaseURL.standardizedFileURL
        parentURL = databaseURL.deletingLastPathComponent().standardizedFileURL
        parentDescriptor = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard parentDescriptor >= 0 else {
            throw CiderDatabaseError.open("The database parent could not be pinned for lineage validation.")
        }
        sourceDescriptor = Darwin.openat(
            parentDescriptor,
            databaseURL.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard sourceDescriptor >= 0 else {
            Darwin.close(parentDescriptor)
            throw CiderDatabaseError.open("The database source could not be pinned for lineage validation.")
        }
        queueDescriptor = kqueue()
        guard queueDescriptor >= 0 else {
            Darwin.close(sourceDescriptor)
            Darwin.close(parentDescriptor)
            throw CiderDatabaseError.open("The database lineage monitor could not be created.")
        }
        do {
            let source = try Self.identity(sourceDescriptor, expectedType: S_IFREG, label: "source")
            let parent = try Self.identity(parentDescriptor, expectedType: S_IFDIR, label: "parent")
            try Self.requirePrivateOwnership(source, label: "database source")
            try Self.requirePrivateOwnership(parent, label: "database parent")
            captured = DatabaseSourceLineage(
                source: source,
                parent: parent,
                sourceFilename: databaseURL.lastPathComponent
            )
            try watch(sourceDescriptor, includeLinkChanges: true)
            try watch(parentDescriptor, includeLinkChanges: false)
        } catch {
            Darwin.close(queueDescriptor)
            Darwin.close(sourceDescriptor)
            Darwin.close(parentDescriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(queueDescriptor)
        Darwin.close(sourceDescriptor)
        Darwin.close(parentDescriptor)
    }

    func validate() throws -> DatabaseSourceLineage {
        let source = try Self.identity(sourceDescriptor, expectedType: S_IFREG, label: "source")
        let parent = try Self.identity(parentDescriptor, expectedType: S_IFDIR, label: "parent")
        var reachableSource = stat()
        var reachableParent = stat()
        guard fstatat(
            parentDescriptor,
            captured.sourceFilename,
            &reachableSource,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        lstat(parentURL.path, &reachableParent) == 0,
        Self.matches(source, reachableSource),
        Self.matches(parent, reachableParent),
        source == captured.source,
        parent == captured.parent,
        !hasObservedIdentityChange() else {
            throw CiderDatabaseError.open(
                "The database source or parent changed identity during lineage validation."
            )
        }
        try Self.requirePrivateOwnership(source, label: "database source")
        try Self.requirePrivateOwnership(parent, label: "database parent")
        return captured
    }

    /// Returns a conservative logical-byte upper bound from descriptors opened
    /// relative to the already-pinned database parent. A later SQLite growth is
    /// handled by the capture write ceiling; this snapshot never follows a
    /// replacement pathname or performs source writes.
    func coherentSQLiteSetByteUpperBound() throws -> Int64 {
        _ = try validate()
        var descriptors: [Int32] = []
        defer { descriptors.forEach { Darwin.close($0) } }

        for (offset, suffix) in ["", "-wal", "-shm"].enumerated() {
            let name = captured.sourceFilename + suffix
            let descriptor = Darwin.openat(
                parentDescriptor,
                name,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
            )
            if descriptor < 0, offset > 0, errno == ENOENT { continue }
            guard descriptor >= 0 else {
                throw CiderDatabaseError.open("The pinned SQLite set member \(name) could not be opened.")
            }
            descriptors.append(descriptor)
        }

        var total: Int64 = 0
        for descriptor in descriptors {
            var descriptorStat = stat()
            guard fstat(descriptor, &descriptorStat) == 0,
                  descriptorStat.st_mode & S_IFMT == S_IFREG,
                  descriptorStat.st_uid == captured.source.owner,
                  descriptorStat.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0,
                  descriptorStat.st_nlink == 1,
                  descriptorStat.st_size >= 0 else {
                throw CiderDatabaseError.open(
                    "A pinned SQLite DB/WAL/SHM member is linked, non-regular, or not privately owned."
                )
            }
            let (sum, overflow) = total.addingReportingOverflow(Int64(descriptorStat.st_size))
            guard !overflow else { throw CiderDatabaseBackupCapacityError.sourceSetOverflow }
            total = sum
        }
        guard total > 0 else {
            throw CiderDatabaseError.open("The pinned SQLite DB/WAL/SHM set has no bounded bytes.")
        }
        _ = try validate()
        return total
    }

    private func watch(_ descriptor: Int32, includeLinkChanges: Bool) throws {
        var notes = UInt32(NOTE_DELETE) | UInt32(NOTE_RENAME) | UInt32(NOTE_REVOKE)
        if includeLinkChanges { notes |= UInt32(NOTE_LINK) }
        var change = kevent(
            ident: UInt(descriptor),
            filter: Int16(EVFILT_VNODE),
            flags: UInt16(EV_ADD) | UInt16(EV_CLEAR),
            fflags: notes,
            data: 0,
            udata: nil
        )
        guard kevent(queueDescriptor, &change, 1, nil, 0, nil) == 0 else {
            throw CiderDatabaseError.open("The database lineage monitor could not watch its source.")
        }
    }

    private func hasObservedIdentityChange() -> Bool {
        var event = kevent()
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        return kevent(queueDescriptor, nil, 0, &event, 1, &timeout) > 0
    }

    private static func identity(
        _ descriptor: Int32,
        expectedType: mode_t,
        label: String
    ) throws -> DatabaseSourceLineage.ObjectIdentity {
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == expectedType else {
            throw CiderDatabaseError.open("The database \(label) is not the expected filesystem object.")
        }
        return DatabaseSourceLineage.ObjectIdentity(
            device: value.st_dev,
            inode: value.st_ino,
            owner: value.st_uid,
            mode: value.st_mode & mode_t(0o7777)
        )
    }

    private static func requirePrivateOwnership(
        _ identity: DatabaseSourceLineage.ObjectIdentity,
        label: String
    ) throws {
        guard identity.owner == geteuid(), identity.mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
            throw CiderDatabaseError.open(
                "The \(label) must be owned by the current user and not writable by group or others."
            )
        }
    }

    private static func matches(
        _ identity: DatabaseSourceLineage.ObjectIdentity,
        _ value: stat
    ) -> Bool {
        identity.device == value.st_dev
            && identity.inode == value.st_ino
            && identity.owner == value.st_uid
            && identity.mode == value.st_mode & mode_t(0o7777)
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
    private(set) var backupSourceLineage: DatabaseSourceLineage?
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
    func open(at url: URL, namespaceAuthority: DatabaseStartupLock? = nil) throws {
        let path = url.path
        // Refuse double-open — a second call would leak the prior handle and
        // potentially point at a different file. Callers must close() first if
        // they really want to reopen.
        if db != nil {
            throw CiderDatabaseError.alreadyOpen(path)
        }
        lastMigrationSafetyArtifactURL = nil
        logger.info("Opening database at \(path)")

        let startupLock = try namespaceAuthority ?? DatabaseStartupLock.acquire(for: url)
        let ownsStartupLock = namespaceAuthority == nil
        defer {
            if ownsStartupLock { startupLock.release() }
        }
        try startupLock.validate(for: url)
        if ownsStartupLock {
            _ = try DatabaseSafetyService().reconcileInterruptedRestore(
                at: url,
                namespaceAuthority: startupLock
            )
            try startupLock.validate(for: url)
        }

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
        var sourceLineageObservation: DatabaseSourceLineageObservation?

        do {
            if sourceState == .fresh {
                switch try DatabaseStartupPreflight.reserveFreshDatabasePath(at: url) {
                case .reserved(let pathReservation):
                    sourceLineageObservation = try DatabaseSourceLineageObservation(databaseURL: url)
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

                sourceLineageObservation = try DatabaseSourceLineageObservation(databaseURL: url)
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
            guard let sourceLineageObservation else {
                throw CiderDatabaseError.open("The open database has no pinned source lineage.")
            }
            let openedLineage = try sourceLineageObservation.validate()
            try DatabaseStartupPreflight.validateOpenedMainFileLineage(
                handle,
                databaseURL: url,
                expected: openedLineage
            )
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

            let sourceLineage = try sourceLineageObservation.validate()
            db = handle
            databaseURL = url
            backupSourceLineage = sourceLineage
        } catch {
            inspection?.close()
            if reservationActive, let handle {
                try? DatabaseStartupPreflight.cancelAuthoritativeReservation(handle)
            }
            sqlite3_close_v2(handle)
            db = nil
            databaseURL = nil
            backupSourceLineage = nil
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
        self.backupSourceLineage = nil
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

    /// Capture one logical SQLite snapshot into a caller-owned staging path.
    /// SQLite's online backup API includes committed WAL frames without forcing
    /// a checkpoint or otherwise changing the live source database.
    func captureOnlineBackup(
        into destinationDescriptor: Int32,
        maximumBytes: Int64
    ) throws {
        guard let db else { throw CiderDatabaseError.open("Database not open") }

        try Self.captureOnlineBackup(
            from: db,
            into: destinationDescriptor,
            maximumBytes: maximumBytes
        )
    }

    /// Captures a logical SQLite image in memory, then publishes its bytes only
    /// through a caller-owned descriptor that was exclusively created relative
    /// to the pinned staging directory. SQLite never opens a staged pathname.
    nonisolated static func captureOnlineBackup(
        from source: OpaquePointer,
        into descriptor: Int32,
        maximumBytes: Int64
    ) throws {
        guard maximumBytes > 0 else {
            throw CiderDatabaseBackupCapacityError.captureExceedsReservation(
                actual: 1,
                reserved: maximumBytes
            )
        }
        let reservedIdentity = try stagedFileIdentity(descriptor: descriptor, requireEmpty: true)

        var destination: OpaquePointer?
        let openResult = sqlite3_open_v2(
            ":memory:",
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let destination else {
            let message = destination.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown SQLite destination error"
            sqlite3_close_v2(destination)
            throw CiderDatabaseError.open("Could not create the isolated backup image: \(message)")
        }
        defer { sqlite3_close_v2(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw CiderDatabaseError.runExec(
                "Could not initialize staged backup: \(String(cString: sqlite3_errmsg(destination)))"
            )
        }

        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw CiderDatabaseError.runExec(
                "SQLite backup capture failed (step \(stepResult), finish \(finishResult)): "
                + String(cString: sqlite3_errmsg(destination))
            )
        }

        var byteCount: sqlite3_int64 = 0
        guard let serialized = sqlite3_serialize(destination, "main", &byteCount, 0), byteCount > 0 else {
            throw CiderDatabaseError.runExec("SQLite could not serialize the completed backup image.")
        }
        defer { sqlite3_free(serialized) }
        guard byteCount <= maximumBytes else {
            throw CiderDatabaseBackupCapacityError.captureExceedsReservation(
                actual: Int64(byteCount),
                reserved: maximumBytes
            )
        }

        _ = try stagedFileIdentity(
            descriptor: descriptor,
            matching: reservedIdentity,
            requireEmpty: true
        )
        var written: sqlite3_int64 = 0
        while written < byteCount {
            let result = Darwin.write(
                descriptor,
                serialized.advanced(by: Int(written)),
                Int(byteCount - written)
            )
            if result < 0, errno == EINTR { continue }
            guard result > 0 else {
                throw CiderDatabaseError.runExec(
                    "Could not write the exclusively reserved backup image (errno \(errno))."
                )
            }
            written += sqlite3_int64(result)
        }
        guard fsync(descriptor) == 0 else {
            throw CiderDatabaseError.runExec(
                "Could not flush the exclusively reserved backup image (errno \(errno))."
            )
        }
        _ = try stagedFileIdentity(
            descriptor: descriptor,
            matching: reservedIdentity,
            expectedSize: byteCount
        )
    }

    private struct StagedFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    @discardableResult
    nonisolated private static func stagedFileIdentity(
        descriptor: Int32,
        matching expected: StagedFileIdentity? = nil,
        requireEmpty: Bool = false,
        expectedSize: sqlite3_int64? = nil
    ) throws -> StagedFileIdentity {
        var descriptorStat = stat()
        guard fstat(descriptor, &descriptorStat) == 0 else {
            throw CiderDatabaseError.runExec("The staged backup identity could not be revalidated.")
        }
        let descriptorType = descriptorStat.st_mode & S_IFMT
        let identity = StagedFileIdentity(device: descriptorStat.st_dev, inode: descriptorStat.st_ino)
        guard descriptorType == S_IFREG,
              descriptorStat.st_nlink == 1,
              expected == nil || identity == expected else {
            throw CiderDatabaseError.runExec(
                "The staged backup descriptor was linked or replaced during capture. No retained file was accepted."
            )
        }
        if requireEmpty, descriptorStat.st_size != 0 {
            throw CiderDatabaseError.runExec("The exclusive staged backup reservation was not empty.")
        }
        if let expectedSize, descriptorStat.st_size != off_t(expectedSize) {
            throw CiderDatabaseError.runExec("The staged backup size changed during capture.")
        }
        return identity
    }
}
