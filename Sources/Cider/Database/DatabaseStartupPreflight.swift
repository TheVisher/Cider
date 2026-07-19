import Darwin
import CryptoKit
import Foundation
import SQLite3

struct DatabaseMigrationSafetyArtifact: Equatable {
    let url: URL
    let sourceSchemaVersion: Int
    let targetSchemaVersion: Int
}

fileprivate struct DatabaseSourceFileSignature: Equatable {
    let exists: Bool
    let byteSize: Int64
    let modificationDate: Date?
    let resourceIdentifier: String?
    let contentSHA256: String?
}

fileprivate struct DatabaseSourceContinuityToken: Equatable {
    let database: DatabaseSourceFileSignature
    let wal: DatabaseSourceFileSignature
}

final class DatabaseStartupLock {
    private var descriptor: Int32
    private let parentDevice: dev_t
    private let parentInode: ino_t
    private let parentGeneration: UInt32

    private init(
        descriptor: Int32,
        parentDevice: dev_t,
        parentInode: ino_t,
        parentGeneration: UInt32
    ) {
        self.descriptor = descriptor
        self.parentDevice = parentDevice
        self.parentInode = parentInode
        self.parentGeneration = parentGeneration
    }

    static func acquire(for databaseURL: URL, timeout: TimeInterval = 5) throws -> DatabaseStartupLock {
        // Lock the existing parent directory, not SQLite's database file.
        // Darwin implements flock with advisory file locks that can interfere
        // with SQLite's byte-range locking when both target the database file.
        let lockURL = databaseURL.deletingLastPathComponent()
        let descriptor = Darwin.open(lockURL.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The database source cannot be opened for the startup safety lock. Check vault permissions and disk availability."
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK || Date() >= deadline {
                Darwin.close(descriptor)
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .concurrentStartup,
                    detail: "Another Cider process did not finish database startup within \(Int(timeout)) seconds. Close the other process or retry."
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        var value = stat()
        guard fstat(descriptor, &value) == 0,
              value.st_mode & S_IFMT == S_IFDIR else {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The database parent authority changed while its startup lock was acquired."
            )
        }
        return DatabaseStartupLock(
            descriptor: descriptor,
            parentDevice: value.st_dev,
            parentInode: value.st_ino,
            parentGeneration: value.st_gen
        )
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    func validate(for databaseURL: URL) throws {
        guard descriptor >= 0 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .concurrentStartup,
                detail: "The held database namespace authority was already released."
            )
        }
        var held = stat()
        var reachable = stat()
        let parentPath = databaseURL.deletingLastPathComponent().path
        guard fstat(descriptor, &held) == 0,
              lstat(parentPath, &reachable) == 0,
              held.st_mode & S_IFMT == S_IFDIR,
              reachable.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == parentDevice,
              held.st_ino == parentInode,
              held.st_gen == parentGeneration,
              reachable.st_dev == parentDevice,
              reachable.st_ino == parentInode,
              reachable.st_gen == parentGeneration else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The held database namespace authority no longer matches the reachable parent directory."
            )
        }
    }

    func coversDirectory(device: dev_t, inode: ino_t, generation: UInt32) -> Bool {
        guard descriptor >= 0 else { return false }
        var held = stat()
        return fstat(descriptor, &held) == 0
            && held.st_mode & S_IFMT == S_IFDIR
            && held.st_dev == parentDevice
            && held.st_ino == parentInode
            && held.st_gen == parentGeneration
            && device == parentDevice
            && inode == parentInode
            && generation == parentGeneration
    }

    deinit {
        release()
    }
}

final class ExistingDatabaseInspection {
    let handle: OpaquePointer
    let schemaVersion: Int
    fileprivate let sourceContinuity: DatabaseSourceContinuityToken
    let sourceLineage: DatabaseSourceLineage
    private let disposableDirectoryURL: URL?
    private var isClosed = false

    fileprivate init(
        handle: OpaquePointer,
        schemaVersion: Int,
        sourceContinuity: DatabaseSourceContinuityToken,
        sourceLineage: DatabaseSourceLineage,
        disposableDirectoryURL: URL?
    ) {
        self.handle = handle
        self.schemaVersion = schemaVersion
        self.sourceContinuity = sourceContinuity
        self.sourceLineage = sourceLineage
        self.disposableDirectoryURL = disposableDirectoryURL
    }

    func close() {
        guard !isClosed else { return }
        sqlite3_close_v2(handle)
        if let disposableDirectoryURL {
            try? FileManager.default.removeItem(at: disposableDirectoryURL)
        }
        isClosed = true
    }

    deinit {
        close()
    }
}

enum DatabaseStartupPreflight {
    enum SourceState: Equatable {
        case fresh
        case existing
    }

    enum FreshDatabasePathReservationOutcome {
        case reserved(FreshDatabasePathReservation)
        case sourceAppeared
    }

    struct FreshDatabasePathReservation {
        fileprivate let sourceContinuity: DatabaseSourceContinuityToken
    }

    struct AuthoritativeMigrationReservation {
        let handle: OpaquePointer
        let schemaVersion: Int
        fileprivate let sourceContinuity: DatabaseSourceContinuityToken
    }

    static func sourceState(at databaseURL: URL) throws -> SourceState {
        let databaseExists = pathExists(databaseURL)
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")
        let walExists = pathExists(walURL)
        let shmExists = pathExists(shmURL)

        if !databaseExists {
            guard !walExists, !shmExists else {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .malformed,
                    detail: "The database file is absent while an orphan SQLite WAL or shared-memory sidecar remains. Preserve the files and restore a coherent database set before retrying."
                )
            }
            return .fresh
        }
        return .existing
    }

    /// Calls the default SQLite VFS with its actual exclusive-create contract.
    /// sqlite3_open_v2 intentionally ignores SQLITE_OPEN_EXCLUSIVE for a main
    /// database, but a VFS xOpen receives it as an O_EXCL-style requirement.
    static func reserveFreshDatabasePath(
        at databaseURL: URL
    ) throws -> FreshDatabasePathReservationOutcome {
        guard let vfs = sqlite3_vfs_find(nil), let open = vfs.pointee.xOpen else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "SQLite has no default VFS available for atomic database creation."
            )
        }
        let byteCount = Int(vfs.pointee.szOsFile)
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<sqlite3_file>.alignment
        )
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        let file = storage.assumingMemoryBound(to: sqlite3_file.self)
        defer { storage.deallocate() }

        var outputFlags: Int32 = 0
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE
            | SQLITE_OPEN_MAIN_DB
        let result = open(vfs, databaseURL.path, file, flags, &outputFlags)
        if result != SQLITE_OK {
            if pathExists(databaseURL) {
                return .sourceAppeared
            }
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "Atomic fresh database reservation failed without leaving a source to validate. Retry after other creators become idle."
            )
        }
        guard let methods = file.pointee.pMethods, let close = methods.pointee.xClose else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "SQLite created the fresh database reservation without a closable VFS handle."
            )
        }
        let closeResult = close(file)
        guard closeResult == SQLITE_OK else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "SQLite could not close the atomic fresh database reservation (code \(closeResult))."
            )
        }

        let continuity = try sourceSignatures(at: databaseURL)
        guard continuity.database.exists,
              continuity.database.byteSize == 0,
              !continuity.wal.exists else {
            return .sourceAppeared
        }
        return .reserved(FreshDatabasePathReservation(sourceContinuity: continuity))
    }

    /// Opens the atomically reserved empty source and takes SQLite's writer
    /// reservation before declaring it fresh. If any conforming creator wrote
    /// first, the caller must restart through existing-source preflight.
    static func openAuthoritativelyReservedFreshDatabase(
        at databaseURL: URL,
        reservation: FreshDatabasePathReservation
    ) throws -> OpaquePointer? {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            if pathExists(databaseURL) { return nil }
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The atomically reserved fresh database disappeared before SQLite could reserve it."
            )
        }
        sqlite3_busy_timeout(handle, 5_000)
        do {
            try execute(handle, sql: "PRAGMA foreign_keys=ON;")
            try execute(handle, sql: "BEGIN IMMEDIATE TRANSACTION;")
            let current = try sourceSignatures(at: databaseURL)
            guard current == reservation.sourceContinuity else {
                try? execute(handle, sql: "ROLLBACK;")
                sqlite3_close_v2(handle)
                return nil
            }
            return handle
        } catch {
            try? execute(handle, sql: "ROLLBACK;")
            sqlite3_close_v2(handle)
            if pathExists(databaseURL) { return nil }
            throw error
        }
    }

    static func establishExistingDatabaseHealth(at databaseURL: URL) throws -> ExistingDatabaseInspection {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: databaseURL.path) else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The existing database is not readable. Restore read permission or select a readable vault before retrying."
            )
        }
        let values: URLResourceValues
        do {
            values = try databaseURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The existing database metadata cannot be read: \(error.localizedDescription)"
            )
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The database path must be a regular, non-symbolic-link file."
            )
        }

        let lineageObservation: DatabaseSourceLineageObservation
        do {
            lineageObservation = try DatabaseSourceLineageObservation(databaseURL: databaseURL)
        } catch {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The database lineage could not be pinned before inspection: \(error.localizedDescription)"
            )
        }

        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let walSize: Int
        if fileManager.fileExists(atPath: walURL.path) {
            do {
                walSize = try walURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            } catch {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .unreadable,
                    detail: "The active SQLite WAL metadata cannot be read. Restore vault permissions before retrying."
                )
            }
        } else {
            walSize = 0
        }
        if walSize > 0 {
            return try inspectDisposableWALCopy(
                databaseURL: databaseURL,
                walURL: walURL,
                lineageObservation: lineageObservation
            )
        }

        let continuityBeforeOpen = try sourceSignatures(at: databaseURL)
        let handle = try openDatabase(
            path: immutableURI(for: databaseURL),
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
            failureKind: .unreadable
        )
        do {
            let version = try validateHealthAndReadVersion(handle)
            let continuityAfterValidation = try sourceSignatures(at: databaseURL)
            guard continuityBeforeOpen == continuityAfterValidation else {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .changedDuringRead,
                    detail: "The database changed during immutable startup validation. Retry after other writers become idle."
                )
            }
            return ExistingDatabaseInspection(
                handle: handle,
                schemaVersion: version,
                sourceContinuity: continuityAfterValidation,
                sourceLineage: try lineageObservation.validate(),
                disposableDirectoryURL: nil
            )
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }
    }

    static func reserveAndRevalidateExistingDatabase(
        at databaseURL: URL
    ) throws -> AuthoritativeMigrationReservation {
        let handle = try openDatabase(
            path: databaseURL.path,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            failureKind: .unreadable
        )
        do {
            try execute(handle, sql: "PRAGMA foreign_keys=ON;")
            try execute(handle, sql: "BEGIN IMMEDIATE TRANSACTION;")
            let version = try validateHealthAndReadVersion(handle)
            let signatures = try sourceSignatures(at: databaseURL)
            return AuthoritativeMigrationReservation(
                handle: handle,
                schemaVersion: version,
                sourceContinuity: signatures
            )
        } catch {
            try? execute(handle, sql: "ROLLBACK;")
            sqlite3_close_v2(handle)
            throw error
        }
    }

    static func validateAuthoritativeSourceContinuity(
        _ reservation: AuthoritativeMigrationReservation,
        matches inspection: ExistingDatabaseInspection
    ) throws {
        guard reservation.sourceContinuity == inspection.sourceContinuity else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The database or WAL content changed between verified artifact capture and the authoritative migration reservation. Startup was refused before migration."
            )
        }
    }

    static func validateAuthoritativeSourceContinuity(
        _ reservation: AuthoritativeMigrationReservation,
        at databaseURL: URL
    ) throws {
        let current = try sourceSignatures(at: databaseURL)
        guard current == reservation.sourceContinuity else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The reserved database or WAL content changed after the migration artifact was verified. Startup was refused before migration."
            )
        }
    }

    static func cancelAuthoritativeReservation(_ handle: OpaquePointer) throws {
        try execute(handle, sql: "ROLLBACK;")
    }

    static func createRequiredMigrationSafetyArtifact(
        from inspection: ExistingDatabaseInspection,
        sourceDatabaseURL: URL
    ) throws -> DatabaseMigrationSafetyArtifact {
        let rootURL = migrationSafetyDirectory(for: sourceDatabaseURL)
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw CiderDatabaseError.migrationSafetyArtifactCaptureFailed(
                detail: "Cannot create the private migration-safety directory: \(error.localizedDescription)"
            )
        }

        let identifier = UUID().uuidString.lowercased()
        let stagingURL = rootURL.appendingPathComponent(".migration-\(identifier).tmp.db")
        let finalURL = rootURL.appendingPathComponent(
            "migration-v\(inspection.schemaVersion)-to-v\(DatabaseMigrations.latestVersion)-\(timestamp())-\(identifier.prefix(8)).db"
        )
        defer {
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }

        try captureSQLiteBackup(source: inspection.handle, destinationURL: stagingURL)
        do {
            try verifyArtifact(
                at: stagingURL,
                expectedVersion: inspection.schemaVersion
            )
        } catch let error as CiderDatabaseError {
            throw error
        } catch {
            throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                detail: "The captured artifact could not be verified: \(error.localizedDescription)"
            )
        }

        do {
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        } catch {
            throw CiderDatabaseError.migrationSafetyArtifactCaptureFailed(
                detail: "The verified migration artifact could not be retained: \(error.localizedDescription)"
            )
        }
        return DatabaseMigrationSafetyArtifact(
            url: finalURL,
            sourceSchemaVersion: inspection.schemaVersion,
            targetSchemaVersion: DatabaseMigrations.latestVersion
        )
    }

    /// Captures the already health-checked logical source into a caller-owned
    /// staging path. The inspection may be an immutable source handle or a
    /// disposable coherent DB/WAL copy; neither path writes the retained source.
    static func captureBackup(
        from inspection: ExistingDatabaseInspection,
        to destinationDescriptor: Int32,
        maximumBytes: Int64
    ) throws {
        try CiderDatabase.captureOnlineBackup(
            from: inspection.handle,
            into: destinationDescriptor,
            maximumBytes: maximumBytes
        )
    }

    static func migrationSafetyDirectory(for sourceDatabaseURL: URL) -> URL {
        sourceDatabaseURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("sqlite", isDirectory: true)
            .appendingPathComponent("migration-safety", isDirectory: true)
            .appendingPathComponent(sourceDatabaseURL.lastPathComponent, isDirectory: true)
    }

    /// Proves the default VFS main file still occupies the pathname SQLite
    /// opened. SQLITE_FCNTL_HAS_MOVED is evaluated by the actual main
    /// sqlite3_file, so a parent swap-and-restore cannot be hidden by a later
    /// pathname check that happens to see the original directory again.
    static func validateOpenedMainFileLineage(
        _ handle: OpaquePointer,
        databaseURL: URL,
        expected: DatabaseSourceLineage
    ) throws {
        guard let filename = sqlite3_db_filename(handle, "main") else {
            throw CiderDatabaseError.open(
                "SQLite did not expose the opened main database pathname for lineage proof."
            )
        }
        let openedPath = URL(fileURLWithPath: String(cString: filename))
            .standardizedFileURL.path
        guard openedPath == databaseURL.standardizedFileURL.path else {
            throw CiderDatabaseError.open(
                "SQLite opened a main database pathname outside the recorded live database."
            )
        }

        var hasMoved: Int32 = 1
        let controlResult = sqlite3_file_control(
            handle,
            "main",
            SQLITE_FCNTL_HAS_MOVED,
            &hasMoved
        )
        guard controlResult == SQLITE_OK, hasMoved == 0 else {
            throw CiderDatabaseError.open(
                "SQLite could not prove that its actual main file remains the recorded live database."
            )
        }

        var source = stat()
        var parent = stat()
        guard lstat(databaseURL.path, &source) == 0,
              lstat(databaseURL.deletingLastPathComponent().path, &parent) == 0,
              source.st_mode & S_IFMT == S_IFREG,
              parent.st_mode & S_IFMT == S_IFDIR,
              source.st_dev == expected.source.device,
              source.st_ino == expected.source.inode,
              source.st_uid == expected.source.owner,
              source.st_mode & mode_t(0o7777) == expected.source.mode,
              parent.st_dev == expected.parent.device,
              parent.st_ino == expected.parent.inode,
              parent.st_uid == expected.parent.owner,
              parent.st_mode & mode_t(0o7777) == expected.parent.mode else {
            throw CiderDatabaseError.open(
                "The opened SQLite main file does not match the pinned source and parent identities."
            )
        }
    }

    static func validatePostOpenDatabase(_ handle: OpaquePointer) throws {
        do {
            let messages = try integrityMessages(handle)
            guard messages.count == 1,
                  messages[0].caseInsensitiveCompare("ok") == .orderedSame else {
                throw CiderDatabaseError.postOpenValidationFailed(messages: messages)
            }
            let version = try DatabaseMigrations.currentVersion(on: handle)
            guard version == DatabaseMigrations.latestVersion else {
                throw CiderDatabaseError.postOpenValidationFailed(
                    messages: ["schema version \(version) does not match required version \(DatabaseMigrations.latestVersion)"]
                )
            }
        } catch let error as CiderDatabaseError {
            throw error
        } catch {
            throw CiderDatabaseError.postOpenValidationFailed(messages: [error.localizedDescription])
        }
    }

    private static func inspectDisposableWALCopy(
        databaseURL: URL,
        walURL: URL,
        lineageObservation: DatabaseSourceLineageObservation
    ) throws -> ExistingDatabaseInspection {
        let fileManager = FileManager.default
        for _ in 0..<3 {
            let disposableDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("cider-database-preflight-\(UUID().uuidString)", isDirectory: true)
            let copiedDatabaseURL = disposableDirectory.appendingPathComponent(databaseURL.lastPathComponent)
            let copiedWALURL = URL(fileURLWithPath: copiedDatabaseURL.path + "-wal")
            do {
                let beforeDatabase = try signature(of: databaseURL)
                let beforeWAL = try signature(of: walURL)
                try fileManager.createDirectory(at: disposableDirectory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: databaseURL, to: copiedDatabaseURL)
                try fileManager.copyItem(at: walURL, to: copiedWALURL)
                let afterDatabase = try signature(of: databaseURL)
                let afterWAL = try signature(of: walURL)
                guard beforeDatabase == afterDatabase, beforeWAL == afterWAL else {
                    try? fileManager.removeItem(at: disposableDirectory)
                    continue
                }
                try validateWALStructure(at: copiedWALURL)

                let handle = try openDatabase(
                    path: copiedDatabaseURL.path,
                    flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                    failureKind: .malformed
                )
                do {
                    let version = try validateHealthAndReadVersion(handle)
                    return ExistingDatabaseInspection(
                        handle: handle,
                        schemaVersion: version,
                        sourceContinuity: DatabaseSourceContinuityToken(
                            database: afterDatabase,
                            wal: afterWAL
                        ),
                        sourceLineage: try lineageObservation.validate(),
                        disposableDirectoryURL: disposableDirectory
                    )
                } catch {
                    sqlite3_close_v2(handle)
                    try? fileManager.removeItem(at: disposableDirectory)
                    throw error
                }
            } catch let error as CiderDatabaseError {
                try? fileManager.removeItem(at: disposableDirectory)
                throw error
            } catch {
                try? fileManager.removeItem(at: disposableDirectory)
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .unreadable,
                    detail: "The database and WAL could not be read into a disposable health-check workspace: \(error.localizedDescription)"
                )
            }
        }
        throw CiderDatabaseError.startupPreflightFailed(
            kind: .changedDuringRead,
            detail: "The database changed repeatedly during read-only startup inspection. Retry after other writers become idle."
        )
    }

    private static func validateHealthAndReadVersion(_ handle: OpaquePointer) throws -> Int {
        do {
            let messages = try integrityMessages(handle)
            guard messages.count == 1,
                  messages[0].caseInsensitiveCompare("ok") == .orderedSame else {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .unhealthy,
                    detail: messages.isEmpty ? "SQLite returned no integrity result." : messages.joined(separator: " | ")
                )
            }
            let version = try DatabaseMigrations.currentVersion(on: handle)
            if version > DatabaseMigrations.latestVersion {
                throw CiderDatabaseError.schemaTooNew(
                    current: version,
                    supported: DatabaseMigrations.latestVersion
                )
            }
            return version
        } catch let error as CiderDatabaseError {
            throw error
        } catch {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "SQLite could not validate the existing database: \(error.localizedDescription)"
            )
        }
    }

    private static func captureSQLiteBackup(source: OpaquePointer, destinationURL: URL) throws {
        var destination: OpaquePointer?
        let openResult = sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let destination else {
            let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite destination error"
            sqlite3_close_v2(destination)
            throw CiderDatabaseError.migrationSafetyArtifactCaptureFailed(
                detail: "SQLite could not create the migration artifact: \(message)"
            )
        }
        defer { sqlite3_close_v2(destination) }
        let capturedResourceIdentifier = fileIdentity(at: destinationURL)

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw CiderDatabaseError.migrationSafetyArtifactCaptureFailed(
                detail: "SQLite could not initialize the migration artifact: \(String(cString: sqlite3_errmsg(destination)))"
            )
        }

        var result: Int32 = SQLITE_OK
        var busyAttempts = 0
        repeat {
            result = sqlite3_backup_step(backup, 256)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                busyAttempts += 1
                if busyAttempts >= 100 { break }
                sqlite3_sleep(10)
            }
        } while result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            let currentResourceIdentifier = fileIdentity(at: destinationURL)
            if capturedResourceIdentifier != currentResourceIdentifier {
                throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                    detail: "The staged migration artifact changed identity before verification could complete."
                )
            }
            throw CiderDatabaseError.migrationSafetyArtifactCaptureFailed(
                detail: "SQLite backup capture failed (step \(result), finish \(finishResult)): \(String(cString: sqlite3_errmsg(destination)))"
            )
        }
    }

    private static func verifyArtifact(at url: URL, expectedVersion: Int) throws {
        let identityBeforeVerification = fileIdentity(at: url)
        let handle: OpaquePointer
        do {
            handle = try openDatabase(
                path: immutableURI(for: url),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
                failureKind: .malformed
            )
        } catch {
            throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                detail: "The artifact could not be physically reopened: \(error.localizedDescription)"
            )
        }
        defer { sqlite3_close_v2(handle) }

        do {
            let messages = try integrityMessages(handle)
            guard messages.count == 1,
                  messages[0].caseInsensitiveCompare("ok") == .orderedSame else {
                throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                    detail: "The artifact failed SQLite integrity verification: \(messages.joined(separator: " | "))"
                )
            }
            let version = try DatabaseMigrations.currentVersion(on: handle)
            guard version == expectedVersion else {
                throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                    detail: "The artifact schema version \(version) does not match the preflight source version \(expectedVersion)."
                )
            }
            guard identityBeforeVerification != nil,
                  identityBeforeVerification == fileIdentity(at: url) else {
                throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                    detail: "The artifact changed identity during physical verification."
                )
            }
        } catch let error as CiderDatabaseError {
            throw error
        } catch {
            throw CiderDatabaseError.migrationSafetyArtifactVerificationFailed(
                detail: "Artifact verification failed: \(error.localizedDescription)"
            )
        }
    }

    private static func integrityMessages(_ handle: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let prepareResult = sqlite3_prepare_v2(handle, "PRAGMA integrity_check;", -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw SQLitePreflightError.message(String(cString: sqlite3_errmsg(handle)))
        }
        var messages: [String] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw SQLitePreflightError.message(String(cString: sqlite3_errmsg(handle)))
            }
            if let text = sqlite3_column_text(statement, 0) {
                messages.append(String(cString: text))
            }
        }
        return messages
    }

    private static func validateWALStructure(at walURL: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: walURL, options: [.mappedIfSafe])
        } catch {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "The active SQLite WAL cannot be read for structural validation."
            )
        }
        guard data.count >= 32 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "The active SQLite WAL is shorter than its required header."
            )
        }
        let magic = readUInt32BigEndian(data, at: 0)
        guard magic == 0x377F_0682 || magic == 0x377F_0683 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "The active SQLite WAL has an invalid header signature."
            )
        }
        guard readUInt32BigEndian(data, at: 4) == 3_007_000 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "The active SQLite WAL uses an unsupported format version."
            )
        }
        let encodedPageSize = readUInt32BigEndian(data, at: 8)
        let pageSize = encodedPageSize == 1 ? 65_536 : Int(encodedPageSize)
        guard pageSize >= 512,
              pageSize <= 65_536,
              pageSize.nonzeroBitCount == 1,
              (data.count - 32).isMultiple(of: pageSize + 24),
              data.count > 32 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "The active SQLite WAL has an invalid page size or incomplete frame."
            )
        }
        let salt1 = readUInt32BigEndian(data, at: 16)
        let salt2 = readUInt32BigEndian(data, at: 20)
        let checksumByteOrder: WALChecksumByteOrder = magic == 0x377F_0682 ? .little : .big
        var rollingChecksum = walChecksum(
            data,
            ranges: [0..<24],
            byteOrder: checksumByteOrder,
            initial: (0, 0)
        )
        guard rollingChecksum.0 == readUInt32BigEndian(data, at: 24),
              rollingChecksum.1 == readUInt32BigEndian(data, at: 28) else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .malformed,
                detail: "The active SQLite WAL header checksum is invalid."
            )
        }
        var offset = 32
        while offset < data.count {
            let pageNumber = readUInt32BigEndian(data, at: offset)
            let frameSalt1 = readUInt32BigEndian(data, at: offset + 8)
            let frameSalt2 = readUInt32BigEndian(data, at: offset + 12)
            guard pageNumber > 0, frameSalt1 == salt1, frameSalt2 == salt2 else {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .malformed,
                    detail: "The active SQLite WAL contains a structurally invalid frame."
                )
            }
            rollingChecksum = walChecksum(
                data,
                ranges: [
                    offset..<(offset + 8),
                    (offset + 24)..<(offset + 24 + pageSize),
                ],
                byteOrder: checksumByteOrder,
                initial: rollingChecksum
            )
            guard rollingChecksum.0 == readUInt32BigEndian(data, at: offset + 16),
                  rollingChecksum.1 == readUInt32BigEndian(data, at: offset + 20) else {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .malformed,
                    detail: "The active SQLite WAL contains a frame with an invalid checksum."
                )
            }
            offset += pageSize + 24
        }
    }

    private enum WALChecksumByteOrder {
        case little
        case big
    }

    private static func walChecksum(
        _ data: Data,
        ranges: [Range<Int>],
        byteOrder: WALChecksumByteOrder,
        initial: (UInt32, UInt32)
    ) -> (UInt32, UInt32) {
        var first = initial.0
        var second = initial.1
        for range in ranges {
            precondition(range.count.isMultiple(of: 8))
            var offset = range.lowerBound
            while offset < range.upperBound {
                let word1 = readUInt32(data, at: offset, byteOrder: byteOrder)
                let word2 = readUInt32(data, at: offset + 4, byteOrder: byteOrder)
                first = first &+ word1 &+ second
                second = second &+ word2 &+ first
                offset += 8
            }
        }
        return (first, second)
    }

    private static func readUInt32(
        _ data: Data,
        at offset: Int,
        byteOrder: WALChecksumByteOrder
    ) -> UInt32 {
        switch byteOrder {
        case .big:
            return readUInt32BigEndian(data, at: offset)
        case .little:
            return data[offset..<(offset + 4)].enumerated().reduce(UInt32(0)) { partial, pair in
                partial | (UInt32(pair.element) << UInt32(pair.offset * 8))
            }
        }
    }

    private static func readUInt32BigEndian(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    private static func fileIdentity(at url: URL) -> UInt64? {
        var information = stat()
        guard lstat(url.path, &information) == 0 else { return nil }
        return UInt64(information.st_ino)
    }

    private static func openDatabase(
        path: String,
        flags: Int32,
        failureKind: CiderDatabasePreflightFailureKind
    ) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite open error"
            sqlite3_close_v2(handle)
            throw CiderDatabaseError.startupPreflightFailed(
                kind: failureKind,
                detail: "SQLite could not open the database for read-only validation: \(message)"
            )
        }
        sqlite3_busy_timeout(handle, 5_000)
        return handle
    }

    private static func execute(_ handle: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                throw CiderDatabaseError.startupPreflightFailed(
                    kind: .concurrentStartup,
                    detail: "SQLite could not reserve the authoritative database source because another writer remained active: \(message)"
                )
            }
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .unreadable,
                detail: "SQLite could not establish the authoritative startup reservation: \(message)"
            )
        }
    }

    private static func sourceSignatures(
        at databaseURL: URL
    ) throws -> DatabaseSourceContinuityToken {
        DatabaseSourceContinuityToken(
            database: try signature(of: databaseURL),
            wal: try signature(of: URL(fileURLWithPath: databaseURL.path + "-wal"))
        )
    }

    private static func signature(of url: URL) throws -> DatabaseSourceFileSignature {
        guard pathExists(url) else {
            return absentSourceFileSignature()
        }
        let beforeValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ])
        // A zero-byte WAL contains no transaction frames and SQLite may create
        // it while acquiring the authoritative reservation. Treat its presence
        // as the same logical source state as no WAL.
        if url.path.hasSuffix("-wal"), beforeValues.fileSize == 0 {
            return absentSourceFileSignature()
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let afterValues = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ])
        guard beforeValues.fileSize == afterValues.fileSize,
              beforeValues.contentModificationDate == afterValues.contentModificationDate,
              String(describing: beforeValues.fileResourceIdentifier)
                == String(describing: afterValues.fileResourceIdentifier) else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .changedDuringRead,
                detail: "The database source changed while its content-sensitive startup signature was being computed."
            )
        }
        return DatabaseSourceFileSignature(
            exists: true,
            byteSize: Int64(afterValues.fileSize ?? 0),
            modificationDate: afterValues.contentModificationDate,
            resourceIdentifier: afterValues.fileResourceIdentifier.map { String(describing: $0) },
            contentSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func absentSourceFileSignature() -> DatabaseSourceFileSignature {
        DatabaseSourceFileSignature(
            exists: false,
            byteSize: 0,
            modificationDate: nil,
            resourceIdentifier: nil,
            contentSHA256: nil
        )
    }

    private static func pathExists(_ url: URL) -> Bool {
        var information = stat()
        return lstat(url.path, &information) == 0
    }

    private static func immutableURI(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = "file"
        components.queryItems = [
            URLQueryItem(name: "mode", value: "ro"),
            URLQueryItem(name: "immutable", value: "1"),
        ]
        return components.string ?? "file:\(url.path)?mode=ro&immutable=1"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }
}

private enum SQLitePreflightError: Error {
    case message(String)
}
