import CryptoKit
import Darwin
import Foundation
import SQLite3

public enum OfflineDatabaseRestoreClassification: String, Codable, Sendable {
    case old
    case new
    case ambiguous
    case unknown
}

public struct OfflineDatabaseIntegrityReceipt: Codable, Equatable, Sendable {
    public let isHealthy: Bool
    public let messages: [String]
    public let schemaVersion: Int
}

public struct OfflineDatabaseRestoreReceipt: Codable, Equatable, Sendable {
    public let ok: Bool
    public let changed: Bool
    public let classification: OfflineDatabaseRestoreClassification
    public let backupPath: String
    public let rollbackPath: String
    public let receiptPath: String
    public let resumedInterruptedRestore: Bool
    public let integrity: OfflineDatabaseIntegrityReceipt
}

public struct OfflineDatabaseRestoreFailureReceipt: Codable, Equatable, Sendable {
    public let ok: Bool
    public let changed: Bool?
    public let classification: OfflineDatabaseRestoreClassification
    public let command: String
    public let error: String
    public let backupPath: String
    public let databasePath: String
    public let rollbackPath: String?
    public let receiptPath: String?
    public let intentPath: String?
    public let evidencePreserved: Bool
}

public struct OfflineDatabaseRestoreFailure: Error, LocalizedError, Sendable {
    public let receipt: OfflineDatabaseRestoreFailureReceipt

    public var errorDescription: String? { receipt.error }
}

enum OfflineDatabaseRestoreError: Error, LocalizedError {
    case blocked(String)
    case sqlite(String)
    case ambiguous(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let detail): "Offline database restore was blocked: \(detail)"
        case .sqlite(let detail): "Offline SQLite restore failed: \(detail)"
        case .ambiguous(let detail): "Offline restore state is ambiguous and remains blocked: \(detail)"
        }
    }
}

private struct OfflineDatabaseLogicalFingerprint: Codable, Equatable {
    let digest: String
    let schemaVersion: Int
}

private struct OfflineDatabaseRestoreIntent: Codable {
    static let version = 1

    let formatVersion: Int
    let transactionID: String
    let databasePath: String
    let backupPath: String
    let rollbackPath: String
    let receiptPath: String
    let lineageIdentifier: String
    let old: OfflineDatabaseLogicalFingerprint
    let new: OfflineDatabaseLogicalFingerprint
    let createdAt: Date
}

private struct OfflineDatabaseTerminalReceipt: Codable, Equatable {
    static let version = 1

    let formatVersion: Int
    let transactionID: String
    let databasePath: String
    let backupPath: String
    let rollbackPath: String
    let classification: OfflineDatabaseRestoreClassification
    let logicalFingerprint: OfflineDatabaseLogicalFingerprint
    let integrity: OfflineDatabaseIntegrityReceipt
    let completedAt: Date
}

@MainActor
public enum OfflineDatabaseRestoreRunner {
    public static func restore(
        backupURL: URL,
        databaseURL: URL,
        lockTimeout: TimeInterval = 5
    ) throws -> OfflineDatabaseRestoreReceipt {
        let normalizedDatabaseURL = databaseURL.standardizedFileURL
        let normalizedBackupURL = backupURL.standardizedFileURL
        var context = FailureContext(
            databaseURL: normalizedDatabaseURL,
            backupURL: normalizedBackupURL
        )
        let ownership: DatabaseStartupLock
        do {
            ownership = try DatabaseStartupLock.acquireMaintenanceExclusive(
                for: normalizedDatabaseURL,
                timeout: lockTimeout
            )
        } catch {
            throw failure(
                from: error,
                context: context,
                forcedChanged: false,
                forcedClassification: .unknown
            )
        }
        defer { ownership.release() }

        do {
            return try performRestore(context: &context)
        } catch let diagnosed as OfflineDatabaseRestoreFailure {
            throw diagnosed
        } catch {
            throw failure(from: error, context: context)
        }
    }

    private static func performRestore(
        context: inout FailureContext
    ) throws -> OfflineDatabaseRestoreReceipt {
        let normalizedDatabaseURL = context.databaseURL
        let normalizedBackupURL = context.backupURL
        let service = DatabaseSafetyService()
        let lineage = try DatabaseSourceLineageObservation(databaseURL: normalizedDatabaseURL)
            .validate()
        let paths = try MaintenancePaths(databaseURL: normalizedDatabaseURL)
        context.paths = paths
        let candidateURL = paths.rootURL.appendingPathComponent(
            ".candidate-\(UUID().uuidString.lowercased()).db"
        )
        defer { try? FileManager.default.removeItem(at: candidateURL) }

        let activeIntent = try readIntentIfPresent(at: paths.intentURL)
        context.intent = activeIntent
        if activeIntent == nil {
            context.old = try inspectDatabase(at: normalizedDatabaseURL).fingerprint
        }

        let source = try service.materializeCurrentV2RollingRestoreSource(
            from: normalizedBackupURL,
            at: candidateURL,
            expectedLineage: lineage.identifier,
            destinationURL: normalizedDatabaseURL
        )
        let newInspection = try inspectDatabase(at: candidateURL, immutable: true)
        context.new = newInspection.fingerprint

        let intent: OfflineDatabaseRestoreIntent
        let resumed: Bool
        if let activeIntent {
            guard activeIntent.formatVersion == OfflineDatabaseRestoreIntent.version,
                  activeIntent.databasePath == normalizedDatabaseURL.path,
                  activeIntent.backupPath == normalizedBackupURL.path,
                  activeIntent.lineageIdentifier == lineage.identifier,
                  activeIntent.new == newInspection.fingerprint else {
                throw OfflineDatabaseRestoreError.ambiguous(
                    "The durable restore intent does not match this database, package, lineage, or logical NEW image. Rollback evidence was preserved at \(activeIntent.rollbackPath)."
                )
            }
            intent = activeIntent
            resumed = true
        } else {
            let old = try required(context.old, "The exact OLD fingerprint was not available.")
            let rollbackURL = try service.captureOfflinePreRestoreRollback(
                databaseURL: normalizedDatabaseURL
            )
            try verifyRollback(
                rollbackURL,
                equals: old,
                service: service,
                paths: paths
            )
            let transactionID = UUID().uuidString.lowercased()
            let receiptURL = paths.receiptsURL.appendingPathComponent(
                "restore-\(transactionID).json"
            )
            intent = OfflineDatabaseRestoreIntent(
                formatVersion: OfflineDatabaseRestoreIntent.version,
                transactionID: transactionID,
                databasePath: normalizedDatabaseURL.path,
                backupPath: normalizedBackupURL.path,
                rollbackPath: rollbackURL.path,
                receiptPath: receiptURL.path,
                lineageIdentifier: lineage.identifier,
                old: old,
                new: newInspection.fingerprint,
                createdAt: Date()
            )
            try paths.createIntent(intent)
            context.intent = intent
            resumed = false
        }

        let current = try inspectDatabase(at: normalizedDatabaseURL)
        switch classify(current.fingerprint, using: intent) {
        case .old:
            try source.validateSourceUnchanged()
            try verifyRollback(
                URL(fileURLWithPath: intent.rollbackPath),
                equals: intent.old,
                service: service,
                paths: paths
            )
            try onlineBackup(
                from: candidateURL,
                intoExisting: normalizedDatabaseURL
            )
        case .new:
            break
        case nil:
            throw OfflineDatabaseRestoreError.ambiguous(
                "The destination is neither exact logical OLD nor exact logical NEW. No further mutation was attempted; rollback evidence remains at \(intent.rollbackPath)."
            )
        }

        try source.validateSourceUnchanged()
        let integrity = try verifyTerminalNew(
            at: normalizedDatabaseURL,
            expected: intent.new
        )
        let terminal = OfflineDatabaseTerminalReceipt(
            formatVersion: OfflineDatabaseTerminalReceipt.version,
            transactionID: intent.transactionID,
            databasePath: intent.databasePath,
            backupPath: intent.backupPath,
            rollbackPath: intent.rollbackPath,
            classification: .new,
            logicalFingerprint: intent.new,
            integrity: integrity,
            completedAt: Date()
        )
        let terminalURL = URL(fileURLWithPath: intent.receiptPath)
        if FileManager.default.fileExists(atPath: terminalURL.path) {
            let retained: OfflineDatabaseTerminalReceipt
            do {
                retained = try JSONDecoder().decode(
                    OfflineDatabaseTerminalReceipt.self,
                    from: Data(contentsOf: terminalURL, options: [.mappedIfSafe])
                )
            } catch {
                throw OfflineDatabaseRestoreError.ambiguous(
                    "Terminal receipt evidence exists but is unreadable. Active intent and rollback evidence were preserved."
                )
            }
            guard retained.formatVersion == terminal.formatVersion,
                  retained.transactionID == terminal.transactionID,
                  retained.databasePath == terminal.databasePath,
                  retained.backupPath == terminal.backupPath,
                  retained.rollbackPath == terminal.rollbackPath,
                  retained.classification == .new,
                  retained.logicalFingerprint == terminal.logicalFingerprint,
                  retained.integrity == terminal.integrity else {
                throw OfflineDatabaseRestoreError.ambiguous(
                    "Terminal receipt evidence conflicts with verified NEW. Active intent and rollback evidence were preserved."
                )
            }
        } else {
            try paths.createReceipt(terminal, named: terminalURL.lastPathComponent)
        }
        try paths.retireIntent()

        return OfflineDatabaseRestoreReceipt(
            ok: true,
            changed: true,
            classification: .new,
            backupPath: normalizedBackupURL.path,
            rollbackPath: intent.rollbackPath,
            receiptPath: intent.receiptPath,
            resumedInterruptedRestore: resumed,
            integrity: integrity
        )
    }

    private enum ClassifiedState {
        case old
        case new
    }

    private struct FailureContext {
        let databaseURL: URL
        let backupURL: URL
        var paths: MaintenancePaths?
        var intent: OfflineDatabaseRestoreIntent?
        var old: OfflineDatabaseLogicalFingerprint?
        var new: OfflineDatabaseLogicalFingerprint?
    }

    private static func failure(
        from error: Error,
        context: FailureContext,
        forcedChanged: Bool? = nil,
        forcedClassification: OfflineDatabaseRestoreClassification? = nil
    ) -> OfflineDatabaseRestoreFailure {
        let retainedIntent = context.intent ?? context.paths.flatMap {
            try? readIntentIfPresent(at: $0.intentURL)
        }
        let old = retainedIntent?.old ?? context.old
        let new = retainedIntent?.new ?? context.new
        var classification = forcedClassification ?? .unknown
        var changed = forcedChanged

        if forcedClassification == nil {
            do {
                let current = try inspectDatabase(at: context.databaseURL).fingerprint
                if let old, current == old {
                    classification = .old
                    changed = false
                } else if let new, current == new {
                    classification = .new
                    changed = true
                } else if old != nil || new != nil {
                    classification = .ambiguous
                    changed = nil
                }
            } catch {
                classification = .unknown
                changed = nil
            }
        }

        let rollbackPath = retainedIntent?.rollbackPath
        let receiptPath = retainedIntent?.receiptPath
        let intentPath = context.paths?.intentURL.path
        let intentExists = intentPath.map(FileManager.default.fileExists(atPath:)) ?? false
        let rollbackExists = rollbackPath.map(FileManager.default.fileExists(atPath:)) ?? false
        return OfflineDatabaseRestoreFailure(
            receipt: OfflineDatabaseRestoreFailureReceipt(
                ok: false,
                changed: changed,
                classification: classification,
                command: "db.restore",
                error: error.localizedDescription,
                backupPath: context.backupURL.path,
                databasePath: context.databaseURL.path,
                rollbackPath: rollbackPath,
                receiptPath: receiptPath,
                intentPath: intentPath,
                evidencePreserved: intentExists || rollbackExists
            )
        )
    }

    private static func required<T>(_ value: T?, _ detail: String) throws -> T {
        guard let value else { throw OfflineDatabaseRestoreError.blocked(detail) }
        return value
    }

    private static func classify(
        _ fingerprint: OfflineDatabaseLogicalFingerprint,
        using intent: OfflineDatabaseRestoreIntent
    ) -> ClassifiedState? {
        if fingerprint == intent.old { return .old }
        if fingerprint == intent.new { return .new }
        return nil
    }

    private static func verifyRollback(
        _ rollbackURL: URL,
        equals expected: OfflineDatabaseLogicalFingerprint,
        service: DatabaseSafetyService,
        paths: MaintenancePaths
    ) throws {
        let verification = service.verifyBackup(at: rollbackURL)
        guard verification.state == .verified, verification.isVerified else {
            throw OfflineDatabaseRestoreError.blocked(
                "The pre-restore rollback is not a healthy current-v2 package: \(verification.messages.joined(separator: " | "))"
            )
        }
        let materialized = paths.rootURL.appendingPathComponent(
            ".rollback-check-\(UUID().uuidString.lowercased()).db"
        )
        defer { try? FileManager.default.removeItem(at: materialized) }
        try service.materializeVerifiedBackupDatabase(from: rollbackURL, at: materialized)
        let rollback = try inspectDatabase(at: materialized, immutable: true)
        guard rollback.fingerprint == expected else {
            throw OfflineDatabaseRestoreError.blocked(
                "The retained rollback is healthy but is not exact logical OLD. It was preserved at \(rollbackURL.path)."
            )
        }
    }

    private static func onlineBackup(
        from sourceURL: URL,
        intoExisting destinationURL: URL
    ) throws {
        var source: OpaquePointer?
        let sourceResult = sqlite3_open_v2(
            immutableURI(for: sourceURL),
            &source,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard sourceResult == SQLITE_OK, let source else {
            let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown source open error"
            sqlite3_close_v2(source)
            throw OfflineDatabaseRestoreError.sqlite("The verified NEW source could not be opened: \(message)")
        }
        defer { sqlite3_close_v2(source) }

        var destination: OpaquePointer?
        let destinationResult = sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard destinationResult == SQLITE_OK, let destination else {
            let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown destination open error"
            sqlite3_close_v2(destination)
            throw OfflineDatabaseRestoreError.sqlite("The existing destination could not be opened: \(message)")
        }
        sqlite3_busy_timeout(destination, 5_000)
        var destinationClosed = false
        defer {
            if !destinationClosed { sqlite3_close_v2(destination) }
        }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw OfflineDatabaseRestoreError.sqlite(
                "sqlite3_backup_init failed: \(String(cString: sqlite3_errmsg(destination)))"
            )
        }
        var backupFinished = false
        defer {
            if !backupFinished { sqlite3_backup_finish(backup) }
        }

        var busyAttempts = 0
        var stepResult: Int32 = SQLITE_OK
        repeat {
            stepResult = sqlite3_backup_step(backup, 128)
            if stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                busyAttempts += 1
                guard busyAttempts < 100 else { break }
                sqlite3_sleep(10)
            }
        } while stepResult == SQLITE_OK || stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED

        let finishResult = sqlite3_backup_finish(backup)
        backupFinished = true
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw OfflineDatabaseRestoreError.sqlite(
                "SQLite Online Backup did not complete (step \(stepResult), finish \(finishResult)): \(String(cString: sqlite3_errmsg(destination)))"
            )
        }
        guard sqlite3_close_v2(destination) == SQLITE_OK else {
            throw OfflineDatabaseRestoreError.sqlite("The restored destination could not be closed cleanly.")
        }
        destinationClosed = true
    }

    private static func verifyTerminalNew(
        at databaseURL: URL,
        expected: OfflineDatabaseLogicalFingerprint
    ) throws -> OfflineDatabaseIntegrityReceipt {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown reopen error"
            sqlite3_close_v2(handle)
            throw OfflineDatabaseRestoreError.sqlite("Physical reopen failed: \(message)")
        }
        defer { sqlite3_close_v2(handle) }
        sqlite3_busy_timeout(handle, 5_000)

        let journalMode = try scalarText(handle, sql: "PRAGMA journal_mode=WAL;")
        guard journalMode.caseInsensitiveCompare("wal") == .orderedSame else {
            throw OfflineDatabaseRestoreError.sqlite("The restored database could not resume WAL mode.")
        }
        try execute(handle, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(handle, sql: "UPDATE schema_version SET version = version;")
            try execute(handle, sql: "ROLLBACK;")
        } catch {
            try? execute(handle, sql: "ROLLBACK;")
            throw error
        }

        let inspection = try inspectDatabase(handle: handle)
        guard inspection.fingerprint == expected else {
            throw OfflineDatabaseRestoreError.ambiguous(
                "Physical reopen was healthy, but logical content/schema is not exact NEW."
            )
        }
        return inspection.integrity
    }

    private struct DatabaseInspection {
        let fingerprint: OfflineDatabaseLogicalFingerprint
        let integrity: OfflineDatabaseIntegrityReceipt
    }

    private static func inspectDatabase(
        at url: URL,
        immutable: Bool = false
    ) throws -> DatabaseInspection {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            immutable ? immutableURI(for: url) : url.path,
            &handle,
            SQLITE_OPEN_READONLY | (immutable ? SQLITE_OPEN_URI : 0) | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown open error"
            sqlite3_close_v2(handle)
            throw OfflineDatabaseRestoreError.sqlite("Database inspection open failed: \(message)")
        }
        defer { sqlite3_close_v2(handle) }
        do {
            return try inspectDatabase(handle: handle)
        } catch {
            throw OfflineDatabaseRestoreError.sqlite(
                "Inspection of \(url.lastPathComponent) failed: \(error.localizedDescription)"
            )
        }
    }

    private static func inspectDatabase(handle: OpaquePointer) throws -> DatabaseInspection {
        let messages = try stringRows(handle, sql: "PRAGMA integrity_check;")
        guard messages.count == 1,
              messages[0].caseInsensitiveCompare("ok") == .orderedSame else {
            throw OfflineDatabaseRestoreError.sqlite(
                "Integrity check failed: \(messages.joined(separator: " | "))"
            )
        }
        let schemaVersion = try DatabaseMigrations.currentVersion(on: handle)
        guard schemaVersion == DatabaseMigrations.latestVersion else {
            throw OfflineDatabaseRestoreError.sqlite(
                "Schema version \(schemaVersion) is not current version \(DatabaseMigrations.latestVersion)."
            )
        }
        let digest = try logicalDigest(handle)
        return DatabaseInspection(
            fingerprint: OfflineDatabaseLogicalFingerprint(
                digest: digest,
                schemaVersion: schemaVersion
            ),
            integrity: OfflineDatabaseIntegrityReceipt(
                isHealthy: true,
                messages: messages,
                schemaVersion: schemaVersion
            )
        )
    }

    private static func logicalDigest(_ handle: OpaquePointer) throws -> String {
        var hasher = SHA256()
        feed("cider-logical-database-v1", into: &hasher)
        feed(try scalarText(handle, sql: "PRAGMA user_version;"), into: &hasher)
        feed(try scalarText(handle, sql: "PRAGMA application_id;"), into: &hasher)

        var schemaStatement: OpaquePointer?
        defer { sqlite3_finalize(schemaStatement) }
        guard sqlite3_prepare_v2(
            handle,
            "SELECT type, name, tbl_name, COALESCE(sql, '') FROM sqlite_schema ORDER BY type, name, tbl_name, COALESCE(sql, '');",
            -1,
            &schemaStatement,
            nil
        ) == SQLITE_OK else {
            throw OfflineDatabaseRestoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        while sqlite3_step(schemaStatement) == SQLITE_ROW {
            for index in 0..<4 {
                feed(columnData(schemaStatement, index: Int32(index)), into: &hasher)
            }
        }

        let tableNames = try stringRows(
            handle,
            sql: "SELECT name FROM sqlite_schema WHERE type='table' AND name <> 'sqlite_schema' ORDER BY name;"
        )
        for tableName in tableNames {
            feed(tableName, into: &hasher)
            let escaped = tableName.replacingOccurrences(of: "\"", with: "\"\"")
            let literal = tableName.replacingOccurrences(of: "'", with: "''")
            let declaration = try scalarText(
                handle,
                sql: "SELECT COALESCE(sql, '') FROM sqlite_schema WHERE type='table' AND name='\(literal)';"
            )
            let includesRowID = !declaration.uppercased().contains("WITHOUT ROWID")
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle,
                includesRowID
                    ? "SELECT rowid, * FROM \"\(escaped)\";"
                    : "SELECT * FROM \"\(escaped)\";",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw OfflineDatabaseRestoreError.sqlite(
                    "Could not read logical table \(tableName): \(String(cString: sqlite3_errmsg(handle)))"
                )
            }
            defer { sqlite3_finalize(statement) }
            let columnCount = sqlite3_column_count(statement)
            feed(Int64(columnCount), into: &hasher)
            for index in 0..<columnCount {
                feed(String(cString: sqlite3_column_name(statement, index)), into: &hasher)
            }
            var rowDigests: [Data] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else {
                    throw OfflineDatabaseRestoreError.sqlite(
                        "Logical table \(tableName) read failed: \(String(cString: sqlite3_errmsg(handle)))"
                    )
                }
                var rowHasher = SHA256()
                for index in 0..<columnCount {
                    feed(columnData(statement, index: index), into: &rowHasher)
                }
                rowDigests.append(Data(rowHasher.finalize()))
            }
            rowDigests.sort { $0.lexicographicallyPrecedes($1) }
            feed(Int64(rowDigests.count), into: &hasher)
            for digest in rowDigests { feed(digest, into: &hasher) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func columnData(_ statement: OpaquePointer?, index: Int32) -> Data {
        var data = Data([UInt8(sqlite3_column_type(statement, index))])
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            var value = sqlite3_column_int64(statement, index).bigEndian
            data.append(Data(bytes: &value, count: MemoryLayout.size(ofValue: value)))
        case SQLITE_FLOAT:
            var value = sqlite3_column_double(statement, index).bitPattern.bigEndian
            data.append(Data(bytes: &value, count: MemoryLayout.size(ofValue: value)))
        case SQLITE_TEXT, SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            if count > 0, let bytes = sqlite3_column_blob(statement, index) {
                data.append(bytes.assumingMemoryBound(to: UInt8.self), count: count)
            }
        default:
            break
        }
        return data
    }

    private static func feed(_ string: String, into hasher: inout SHA256) {
        feed(Data(string.utf8), into: &hasher)
    }

    private static func feed(_ value: Int64, into hasher: inout SHA256) {
        var bigEndian = value.bigEndian
        feed(Data(bytes: &bigEndian, count: MemoryLayout.size(ofValue: bigEndian)), into: &hasher)
    }

    private static func feed(_ data: Data, into hasher: inout SHA256) {
        var length = UInt64(data.count).bigEndian
        hasher.update(data: Data(bytes: &length, count: MemoryLayout.size(ofValue: length)))
        hasher.update(data: data)
    }

    private static func stringRows(_ handle: OpaquePointer, sql: String) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OfflineDatabaseRestoreError.sqlite(
                "Query failed [\(sql)]: \(String(cString: sqlite3_errmsg(handle)))"
            )
        }
        var values: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw OfflineDatabaseRestoreError.sqlite(
                    "Query step failed [\(sql)]: \(String(cString: sqlite3_errmsg(handle)))"
                )
            }
            values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
        }
        return values
    }

    private static func scalarText(_ handle: OpaquePointer, sql: String) throws -> String {
        try stringRows(handle, sql: sql).first ?? ""
    }

    private static func execute(_ handle: OpaquePointer, sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(message) }
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            throw OfflineDatabaseRestoreError.sqlite(
                message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            )
        }
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

    private final class MaintenancePaths {
        let rootURL: URL
        let receiptsURL: URL
        let intentURL: URL
        private let rootDescriptor: Int32
        private let receiptsDescriptor: Int32

        init(databaseURL: URL) throws {
            let databaseParent = databaseURL.deletingLastPathComponent().standardizedFileURL
            let parentDescriptor = Darwin.open(
                databaseParent.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard parentDescriptor >= 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "The database parent could not be pinned for durable maintenance evidence."
                )
            }
            var opened = [parentDescriptor]
            do {
                let backups = try Self.openOrCreateDirectory(
                    named: "backups",
                    under: parentDescriptor
                )
                opened.append(backups)
                let sqlite = try Self.openOrCreateDirectory(named: "sqlite", under: backups)
                opened.append(sqlite)
                let maintenance = try Self.openOrCreateDirectory(
                    named: "maintenance",
                    under: sqlite
                )
                opened.append(maintenance)
                let receipts = try Self.openOrCreateDirectory(
                    named: "receipts",
                    under: maintenance
                )
                opened.append(receipts)
                rootDescriptor = maintenance
                receiptsDescriptor = receipts
                for descriptor in opened where descriptor != maintenance && descriptor != receipts {
                    Darwin.close(descriptor)
                }
            } catch {
                opened.forEach { Darwin.close($0) }
                throw error
            }
            rootURL = databaseParent
                .appendingPathComponent("backups", isDirectory: true)
                .appendingPathComponent("sqlite", isDirectory: true)
                .appendingPathComponent("maintenance", isDirectory: true)
            receiptsURL = rootURL.appendingPathComponent("receipts", isDirectory: true)
            intentURL = rootURL.appendingPathComponent("active-restore-v1.json")
        }

        deinit {
            Darwin.close(receiptsDescriptor)
            Darwin.close(rootDescriptor)
        }

        func createIntent(_ intent: OfflineDatabaseRestoreIntent) throws {
            try Self.durableCreateJSON(
                intent,
                named: intentURL.lastPathComponent,
                in: rootDescriptor,
                displayURL: intentURL
            )
        }

        func createReceipt<T: Encodable>(_ receipt: T, named name: String) throws {
            try Self.durableCreateJSON(
                receipt,
                named: name,
                in: receiptsDescriptor,
                displayURL: receiptsURL.appendingPathComponent(name)
            )
        }

        func retireIntent() throws {
            guard unlinkat(rootDescriptor, intentURL.lastPathComponent, 0) == 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "The verified terminal receipt exists, but the active intent could not be retired (errno \(errno))."
                )
            }
            guard fsync(rootDescriptor) == 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "The active intent was unlinked, but its parent directory could not be durably flushed (errno \(errno))."
                )
            }
        }

        private static func openOrCreateDirectory(
            named name: String,
            under parent: Int32
        ) throws -> Int32 {
            var created = false
            var descriptor = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            if descriptor < 0, errno == ENOENT {
                guard mkdirat(parent, name, S_IRWXU) == 0 else {
                    throw OfflineDatabaseRestoreError.blocked(
                        "The durable evidence directory \(name) could not be created (errno \(errno))."
                    )
                }
                created = true
                descriptor = Darwin.openat(
                    parent,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard descriptor >= 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "The durable evidence directory \(name) could not be pinned (errno \(errno))."
                )
            }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFDIR,
                  metadata.st_uid == geteuid(),
                  metadata.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0 else {
                Darwin.close(descriptor)
                throw OfflineDatabaseRestoreError.blocked(
                    "The durable evidence directory \(name) has unsafe identity or permissions."
                )
            }
            if created {
                guard fsync(descriptor) == 0, fsync(parent) == 0 else {
                    let savedErrno = errno
                    Darwin.close(descriptor)
                    throw OfflineDatabaseRestoreError.blocked(
                        "The new durable evidence directory \(name) or its parent could not be flushed (errno \(savedErrno))."
                    )
                }
            }
            return descriptor
        }

        private static func durableCreateJSON<T: Encodable>(
            _ value: T,
            named name: String,
            in directory: Int32,
            displayURL: URL
        ) throws {
            let data = try JSONEncoder().encode(value)
            let descriptor = Darwin.openat(
                directory,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "Durable maintenance evidence could not be exclusively created at \(displayURL.path) (errno \(errno))."
                )
            }
            defer { Darwin.close(descriptor) }
            var offset = 0
            try data.withUnsafeBytes { bytes in
                while offset < bytes.count {
                    let result = Darwin.write(
                        descriptor,
                        bytes.baseAddress?.advanced(by: offset),
                        bytes.count - offset
                    )
                    if result < 0, errno == EINTR { continue }
                    guard result > 0 else {
                        throw OfflineDatabaseRestoreError.blocked(
                            "Durable maintenance evidence write failed at \(displayURL.path) (errno \(errno))."
                        )
                    }
                    offset += result
                }
            }
            guard fsync(descriptor) == 0, fsync(directory) == 0 else {
                throw OfflineDatabaseRestoreError.blocked(
                    "Durable maintenance evidence could not be flushed at \(displayURL.path) (errno \(errno))."
                )
            }
        }
    }

    private static func readIntentIfPresent(at url: URL) throws -> OfflineDatabaseRestoreIntent? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(
                OfflineDatabaseRestoreIntent.self,
                from: Data(contentsOf: url, options: [.mappedIfSafe])
            )
        } catch {
            throw OfflineDatabaseRestoreError.ambiguous(
                "The durable restore intent is unreadable. It was preserved at \(url.path): \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
enum OfflineDatabaseRestoreStartupGate {
    static func reconcileBeforeOrdinaryOpen(databaseURL: URL) throws {
        let rootURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("sqlite", isDirectory: true)
            .appendingPathComponent("maintenance", isDirectory: true)
        let intentURL = rootURL.appendingPathComponent("active-restore-v1.json")
        guard FileManager.default.fileExists(atPath: intentURL.path) else { return }
        let intent: OfflineDatabaseRestoreIntent
        do {
            intent = try JSONDecoder().decode(
                OfflineDatabaseRestoreIntent.self,
                from: Data(contentsOf: intentURL, options: [.mappedIfSafe])
            )
        } catch {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .maintenanceRequired,
                detail: "An interrupted offline restore has unreadable intent evidence at \(intentURL.path). Resume maintenance restore before ordinary database use."
            )
        }
        let receiptURL = URL(fileURLWithPath: intent.receiptPath)
        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(OfflineDatabaseTerminalReceipt.self, from: receiptData),
              receipt.formatVersion == OfflineDatabaseTerminalReceipt.version,
              receipt.transactionID == intent.transactionID,
              receipt.databasePath == intent.databasePath,
              receipt.backupPath == intent.backupPath,
              receipt.rollbackPath == intent.rollbackPath,
              receipt.classification == .new,
              receipt.logicalFingerprint == intent.new,
              receipt.integrity.isHealthy,
              receipt.integrity.schemaVersion == intent.new.schemaVersion else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .maintenanceRequired,
                detail: "An interrupted offline restore is active. Resume the maintenance helper; rollback evidence remains at \(intent.rollbackPath)."
            )
        }
        let current = try OfflineDatabaseRestoreRunner.inspectForStartupGate(at: databaseURL)
        guard current == intent.new else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .maintenanceRequired,
                detail: "The restore receipt exists, but the database is not exact logical NEW. Ordinary use is blocked and rollback evidence remains at \(intent.rollbackPath)."
            )
        }
        guard unlink(intentURL.path) == 0 else {
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .maintenanceRequired,
                detail: "The completed restore intent could not be retired safely."
            )
        }
        let directory = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0, fsync(directory) == 0 else {
            if directory >= 0 { Darwin.close(directory) }
            throw CiderDatabaseError.startupPreflightFailed(
                kind: .maintenanceRequired,
                detail: "The completed restore reconciliation could not be durably recorded."
            )
        }
        Darwin.close(directory)
    }
}

private extension OfflineDatabaseRestoreRunner {
    static func inspectForStartupGate(at url: URL) throws -> OfflineDatabaseLogicalFingerprint {
        try inspectDatabase(at: url).fingerprint
    }
}
