import Foundation
import os

@MainActor
final class DatabaseSafetyService {
    static let shared = DatabaseSafetyService()

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
