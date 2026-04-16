import Foundation
import os

@MainActor
final class DatabaseSafetyService {
    static let shared = DatabaseSafetyService()

    struct SQLiteBackupInfo: Equatable {
        enum Kind: String, Equatable {
            case rolling
            case preflight
        }

        let kind: Kind
        let url: URL
        let createdAt: Date
        let byteSize: Int64
    }

    enum RestoreError: LocalizedError {
        case missingBackup(URL)
        case unhealthyBackup(URL, messages: [String])

        var errorDescription: String? {
            switch self {
            case .missingBackup(let url):
                return "Backup not found at \(url.path)."
            case .unhealthyBackup(let url, let messages):
                let detail = messages.isEmpty ? "unknown integrity failure" : messages.joined(separator: " | ")
                return "Backup at \(url.path) failed integrity check: \(detail)"
            }
        }
    }

    struct RestoreResult: Equatable {
        let restoredBackup: SQLiteBackupInfo
        let preRestoreSnapshotURL: URL?
    }

    private struct SafetyState: Codable {
        var lastPreOpenSnapshotAt: Date?
        var lastIntegrityCheckAt: Date?
        var lastRollingBackupAt: Date?
    }

    private let logger = Logger(subsystem: "com.cider.app", category: "DatabaseSafety")
    private let fileManager: FileManager

    private let preOpenSnapshotInterval: TimeInterval = 12 * 60 * 60
    private let integrityCheckInterval: TimeInterval = 12 * 60 * 60
    private let rollingBackupInterval: TimeInterval = 12 * 60 * 60
    private let preOpenRetentionCount = 3
    private let rollingBackupRetentionCount = 7

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func capturePreOpenSnapshotIfNeeded(databaseURL: URL) {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }

        do {
            var state = try loadState(for: databaseURL)
            guard shouldRun(lastRunAt: state.lastPreOpenSnapshotAt, minimumInterval: preOpenSnapshotInterval) else {
                return
            }

            let snapshotURL = try captureRawSnapshot(databaseURL: databaseURL, reason: "pre-open")
            state.lastPreOpenSnapshotAt = Date()
            try saveState(state, for: databaseURL)
            try pruneSnapshots(in: preOpenSnapshotsDirectory(for: databaseURL), keep: preOpenRetentionCount)
            logger.info("Captured pre-open database snapshot at \(snapshotURL.path)")
        } catch {
            logger.error("Failed to capture pre-open database snapshot: \(error.localizedDescription)")
        }
    }

    func performStartupSafetyPass(database: CiderDatabase = .shared) {
        guard database.isOpen, let databaseURL = database.databaseURL else { return }

        do {
            var state = try loadState(for: databaseURL)

            if shouldRun(lastRunAt: state.lastIntegrityCheckAt, minimumInterval: integrityCheckInterval) {
                let integrity = try database.integrityCheck()
                state.lastIntegrityCheckAt = Date()
                try saveState(state, for: databaseURL)

                if integrity.isHealthy {
                    logger.info("SQLite integrity check passed")
                } else {
                    logger.error("SQLite integrity check failed: \(integrity.messages.joined(separator: " | "))")
                    _ = try? createRollingBackup(reason: "integrity-failure", database: database, updateState: false)
                }
            }

            if shouldRun(lastRunAt: state.lastRollingBackupAt, minimumInterval: rollingBackupInterval) {
                _ = try createRollingBackup(reason: "startup", database: database, updateState: false)
                state.lastRollingBackupAt = Date()
                try saveState(state, for: databaseURL)
            }
        } catch {
            logger.error("Database safety pass failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createRollingBackup(
        reason: String,
        database: CiderDatabase = .shared,
        updateState: Bool = true
    ) throws -> URL {
        guard let databaseURL = database.databaseURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let rollingDir = rollingBackupsDirectory(for: databaseURL)
        try fileManager.createDirectory(at: rollingDir, withIntermediateDirectories: true)

        let filename = "\(timestampString())-\(sanitize(reason)).db"
        let backupURL = rollingDir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        try database.checkpointWal(mode: "TRUNCATE")
        try database.vacuum(into: backupURL)
        try pruneSnapshots(in: rollingDir, keep: rollingBackupRetentionCount)

        if updateState {
            var state = try loadState(for: databaseURL)
            state.lastRollingBackupAt = Date()
            try saveState(state, for: databaseURL)
        }

        logger.info("Created rolling SQLite backup at \(backupURL.path)")
        return backupURL
    }

    // MARK: - Paths

    func backupsRootDirectory(for databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent("sqlite", isDirectory: true)
    }

    func rollingBackupsDirectory(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("rolling", isDirectory: true)
    }

    func preOpenSnapshotsDirectory(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("preflight", isDirectory: true)
    }

    func listRollingBackups(databaseURL: URL) -> [SQLiteBackupInfo] {
        listBackups(in: rollingBackupsDirectory(for: databaseURL), kind: .rolling)
    }

    func listPreOpenSnapshots(databaseURL: URL) -> [SQLiteBackupInfo] {
        listBackups(in: preOpenSnapshotsDirectory(for: databaseURL), kind: .preflight)
    }

    @discardableResult
    func createManualBackup(database: CiderDatabase = .shared) throws -> URL {
        try createRollingBackup(reason: "manual", database: database)
    }

    @discardableResult
    func restoreRollingBackup(
        from backupURL: URL,
        into databaseURL: URL,
        database: CiderDatabase? = nil,
        reopenDatabase: Bool = false
    ) throws -> RestoreResult {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw RestoreError.missingBackup(backupURL)
        }

        let restoredBackup = try backupInfo(for: backupURL, kind: .rolling)

        let verificationDB = CiderDatabase()
        try verificationDB.open(at: backupURL)
        let integrity = try verificationDB.integrityCheck()
        verificationDB.close()
        guard integrity.isHealthy else {
            throw RestoreError.unhealthyBackup(backupURL, messages: integrity.messages)
        }

        let preRestoreSnapshotURL: URL?
        if fileManager.fileExists(atPath: databaseURL.path) {
            preRestoreSnapshotURL = try captureRawSnapshot(databaseURL: databaseURL, reason: "pre-restore")
        } else {
            preRestoreSnapshotURL = nil
        }

        if let database, database.isOpen, database.databaseURL == databaseURL {
            database.close()
        }

        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try removeDatabaseArtifacts(at: databaseURL)
        try fileManager.copyItem(at: backupURL, to: databaseURL)

        if reopenDatabase, let database {
            try database.open(at: databaseURL)
        }

        logger.info("Restored SQLite database from backup \(backupURL.lastPathComponent, privacy: .public)")
        return RestoreResult(restoredBackup: restoredBackup, preRestoreSnapshotURL: preRestoreSnapshotURL)
    }

    private func stateFileURL(for databaseURL: URL) -> URL {
        backupsRootDirectory(for: databaseURL).appendingPathComponent("state.json")
    }

    // MARK: - Internal helpers

    private func captureRawSnapshot(databaseURL: URL, reason: String) throws -> URL {
        let snapshotsDir = preOpenSnapshotsDirectory(for: databaseURL)
        try fileManager.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let snapshotDir = snapshotsDir.appendingPathComponent("\(timestampString())-\(sanitize(reason))", isDirectory: true)
        try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        let candidates = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]

        for sourceURL in candidates where fileManager.fileExists(atPath: sourceURL.path) {
            let destinationURL = snapshotDir.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return snapshotDir
    }

    private func loadState(for databaseURL: URL) throws -> SafetyState {
        let stateURL = stateFileURL(for: databaseURL)
        guard fileManager.fileExists(atPath: stateURL.path) else { return SafetyState() }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(SafetyState.self, from: data)
    }

    private func saveState(_ state: SafetyState, for databaseURL: URL) throws {
        let root = backupsRootDirectory(for: databaseURL)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL(for: databaseURL), options: .atomic)
    }

    private func pruneSnapshots(in directoryURL: URL, keep count: Int) throws {
        guard count > 0, fileManager.fileExists(atPath: directoryURL.path) else { return }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for url in sorted.dropFirst(count) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func listBackups(in directoryURL: URL, kind: SQLiteBackupInfo.Kind) -> [SQLiteBackupInfo] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { try? backupInfo(for: $0, kind: kind) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func backupInfo(for url: URL, kind: SQLiteBackupInfo.Kind) throws -> SQLiteBackupInfo {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
        let createdAt = values.contentModificationDate ?? values.creationDate ?? .distantPast
        let byteSize: Int64
        if kind == .preflight {
            byteSize = try folderSize(at: url)
        } else {
            byteSize = Int64(values.fileSize ?? 0)
        }
        return SQLiteBackupInfo(kind: kind, url: url, createdAt: createdAt, byteSize: byteSize)
    }

    private func folderSize(at directoryURL: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func removeDatabaseArtifacts(at databaseURL: URL) throws {
        let paths = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]

        for url in paths where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func shouldRun(lastRunAt: Date?, minimumInterval: TimeInterval) -> Bool {
        guard let lastRunAt else { return true }
        return Date().timeIntervalSince(lastRunAt) >= minimumInterval
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    private func sanitize(_ reason: String) -> String {
        let invalid = CharacterSet.alphanumerics.inverted
        let cleaned = reason
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        return cleaned.isEmpty ? "backup" : cleaned
    }
}
