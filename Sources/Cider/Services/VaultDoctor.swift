import Foundation
import os

/// Audit tool that scans the vault for inconsistencies between disk,
/// SQLite, and in-memory service state. Used by `cider-cli folder doctor`
/// for interactive and scripted health checks.
///
/// Philosophy: detect only. The scan is read-only. Fixing is opt-in via
/// `fix(_:)` and always operates on a single finding at a time so the
/// caller can confirm or batch as they see fit.
@MainActor
final class VaultDoctor {
    static let shared = VaultDoctor()

    private let logger = Logger(subsystem: "com.cider.app", category: "VaultDoctor")

    private var vaultRoot: URL { StoragePaths.cachedVaultDirectoryURL }
    private var database: CiderDatabase? {
        CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil
    }

    /// Directories at the vault root that are Cider-internal or reserved
    /// and should NEVER be flagged as "untracked". Must stay in sync with
    /// VaultFolderService.reservedDirectoryNames.
    private static let reservedTopDirs: Set<String> = [
        "Inbox", "Unsorted",
        "Bookmarks", "Contacts", "DateCards", "Labels", "Notes",
        "SavedViews", "Sources", "Stacks", "Tags",
    ]

    // MARK: - Finding Model

    enum Severity: String, Codable {
        case info
        case warning
        case error
    }

    /// A single inconsistency discovered during a scan. Each finding has
    /// enough context for the caller to display it, decide whether to fix
    /// it, and — if fixable — apply the fix via `fix(_:)`.
    struct Finding: Codable, Identifiable {
        /// Stable per-scan id so the CLI can reference it in dialog.
        let id: String
        let kind: Kind
        let severity: Severity
        let summary: String
        let detail: String
        /// True if `VaultDoctor.fix(_:)` knows how to resolve this finding
        /// automatically and safely. Findings that require human judgement
        /// are reported with `isFixable == false`.
        let isFixable: Bool
        /// Short label for what the fix would do, for confirmation prompts.
        let fixLabel: String?
        /// Payload for the fix action. Opaque to callers — only used
        /// internally by `fix(_:)`.
        let payload: Payload

        enum Kind: String, Codable {
            case ghostFolderRow        // folders row exists, directory missing
            case untrackedEmptyDir     // directory exists, no folders row, empty
            case untrackedNonEmptyDir  // directory exists, no folders row, has content
            case staleItemFolderRef    // items.folder_id points at nonexistent folder
            case staleSessionFolderRef // sessions.folder_id points at nonexistent folder
            case duplicateFolderPath   // multiple folders rows with same relative_path (schema invariant violation)
            case orphanBreadcrumb      // old .cider/folders/.trash/*-breadcrumbs.json > 30 days old
            case reservedPathInFolders // folders row for a reserved top dir (legacy drift)
        }

        /// Fix-action payload. Decoded opaquely — NOT user-facing.
        struct Payload: Codable {
            var folderID: UUID?
            var itemID: UUID?
            var sessionID: UUID?
            var relativePath: String?
            var breadcrumbFile: String?
        }
    }

    /// A single scan pass producing a structured report. Independent of
    /// `fix(_:)` — callers can render, filter, or round-trip the report
    /// before choosing which findings to apply.
    struct Report: Codable {
        let startedAt: Date
        let finishedAt: Date
        let findings: [Finding]

        var counts: [Severity: Int] {
            var out: [Severity: Int] = [:]
            for f in findings { out[f.severity, default: 0] += 1 }
            return out
        }

        var fixableCount: Int {
            findings.filter(\.isFixable).count
        }
    }

    // MARK: - Scan

    /// Runs every check and returns a structured Report. Read-only.
    func scan() -> Report {
        let started = Date()
        var findings: [Finding] = []

        findings.append(contentsOf: scanGhostFolderRows())
        findings.append(contentsOf: scanUntrackedDirectories())
        findings.append(contentsOf: scanStaleItemFolderRefs())
        findings.append(contentsOf: scanStaleSessionFolderRefs())
        findings.append(contentsOf: scanDuplicateFolderPaths())
        findings.append(contentsOf: scanOrphanBreadcrumbs())
        findings.append(contentsOf: scanReservedPathsInFolders())

        return Report(
            startedAt: started,
            finishedAt: Date(),
            findings: findings
        )
    }

    // MARK: - Checks

    /// Check 1: folders row exists but the directory is missing from disk.
    /// Usually means the directory was deleted outside Cider (Finder, rm,
    /// external sync). Safe to fix by deleting the folders row IF no items
    /// still reference it.
    private func scanGhostFolderRows() -> [Finding] {
        var out: [Finding] = []
        let folders = VaultFolderService.shared.folders
        let fm = FileManager.default
        for folder in folders {
            let url = vaultRoot.appendingPathComponent(folder.relativePath)
            if !fm.fileExists(atPath: url.path) {
                // Check if items still reference it — if so, we need to
                // unfile them first (so the fix knows what's required).
                let itemCount = countItemsReferencingFolder(folder.id)
                let severity: Severity = itemCount > 0 ? .error : .warning
                let detail = itemCount > 0
                    ? "\(itemCount) item(s) still reference this folder — fix will unfile them before removing the row."
                    : "Directory is gone and no items reference it — safe to drop the row."
                out.append(Finding(
                    id: "ghost-\(folder.id.uuidString)",
                    kind: .ghostFolderRow,
                    severity: severity,
                    summary: "Ghost folder row: \(folder.relativePath)",
                    detail: detail,
                    isFixable: true,
                    fixLabel: itemCount > 0
                        ? "Unfile \(itemCount) item(s) then delete folder row"
                        : "Delete folder row",
                    payload: Finding.Payload(folderID: folder.id, relativePath: folder.relativePath)
                ))
            }
        }
        return out
    }

    /// Check 2: directory exists on disk but no folders row tracks it.
    /// Split into `untrackedEmptyDir` (safe to remove) and
    /// `untrackedNonEmptyDir` (needs human decision — adopt or leave).
    private func scanUntrackedDirectories() -> [Finding] {
        var out: [Finding] = []
        let fm = FileManager.default
        let indexedPaths = Set(VaultFolderService.shared.folders.map(\.relativePath))
        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return out }

        for case let url as URL in enumerator {
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir else { continue }
            let relativePath = url.path.replacingOccurrences(
                of: vaultRoot.path + "/",
                with: ""
            )
            // Skip reserved top-level dirs
            let topComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
            if Self.reservedTopDirs.contains(topComponent) { continue }
            if indexedPaths.contains(relativePath) { continue }

            // Determine emptiness (any non-hidden non-reserved child files
            // OR subdirectories count as non-empty)
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            if contents.isEmpty {
                out.append(Finding(
                    id: "untracked-empty-\(relativePath)",
                    kind: .untrackedEmptyDir,
                    severity: .warning,
                    summary: "Untracked empty directory: \(relativePath)",
                    detail: "Directory exists on disk with no entries and no folders row. Leftover from a crashed mutation, manual `mkdir`, or partially-completed delete.",
                    isFixable: true,
                    fixLabel: "Remove empty directory from disk",
                    payload: Finding.Payload(relativePath: relativePath)
                ))
            } else {
                out.append(Finding(
                    id: "untracked-\(relativePath)",
                    kind: .untrackedNonEmptyDir,
                    severity: .warning,
                    summary: "Untracked non-empty directory: \(relativePath)",
                    detail: "Directory exists on disk with \(contents.count) entr\(contents.count == 1 ? "y" : "ies") and no folders row. Needs a human to decide: adopt it (register as a vault folder), or move contents elsewhere.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: Finding.Payload(relativePath: relativePath)
                ))
            }
        }
        return out
    }

    /// Check 3: items.folder_id points at a folder that doesn't exist.
    /// Always a data-integrity bug. Fix by setting folder_id = NULL
    /// (item drops back to Inbox).
    private func scanStaleItemFolderRefs() -> [Finding] {
        var out: [Finding] = []
        guard let db = database else { return out }
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.type, i.title, i.folder_id
                FROM items i
                WHERE i.folder_id IS NOT NULL
                  AND i.folder_id NOT IN (SELECT id FROM folders);
                """)
            while try stmt.step() {
                guard let itemID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)),
                      let folderID = stmt.optionalString(at: 3).flatMap(DatabaseHelpers.decodeUUID)
                else { continue }
                let type = stmt.string(at: 1)
                let title = stmt.string(at: 2)
                out.append(Finding(
                    id: "stale-item-\(itemID.uuidString)",
                    kind: .staleItemFolderRef,
                    severity: .error,
                    summary: "Stale folder_id on \(type): \(title)",
                    detail: "Item references folder \(folderID.uuidString.prefix(8)) which doesn't exist in the folders table. Fix unfiles it to Inbox.",
                    isFixable: true,
                    fixLabel: "Unfile to Inbox (set folder_id = NULL)",
                    payload: Finding.Payload(itemID: itemID)
                ))
            }
        } catch {
            logger.error("scanStaleItemFolderRefs: \(error.localizedDescription)")
        }
        return out
    }

    /// Check 4: sessions.folder_id points at a nonexistent folder. Same
    /// shape as #3 but on the separate sessions table.
    private func scanStaleSessionFolderRefs() -> [Finding] {
        var out: [Finding] = []
        guard let db = database else { return out }
        do {
            let stmt = try db.prepare("""
                SELECT s.id, s.name, s.folder_id
                FROM sessions s
                WHERE s.folder_id IS NOT NULL
                  AND s.folder_id NOT IN (SELECT id FROM folders);
                """)
            while try stmt.step() {
                guard let sessionID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)),
                      let folderID = stmt.optionalString(at: 2).flatMap(DatabaseHelpers.decodeUUID)
                else { continue }
                let name = stmt.string(at: 1)
                out.append(Finding(
                    id: "stale-session-\(sessionID.uuidString)",
                    kind: .staleSessionFolderRef,
                    severity: .error,
                    summary: "Stale folder_id on session: \(name)",
                    detail: "Session references folder \(folderID.uuidString.prefix(8)) which doesn't exist. Fix unfiles it to Inbox.",
                    isFixable: true,
                    fixLabel: "Unfile to Inbox (set folder_id = NULL)",
                    payload: Finding.Payload(sessionID: sessionID)
                ))
            }
        } catch {
            logger.error("scanStaleSessionFolderRefs: \(error.localizedDescription)")
        }
        return out
    }

    /// Check 5: multiple folders rows sharing the same relative_path.
    /// Should be impossible because `relative_path` is UNIQUE in the
    /// schema, but worth checking as an invariant monitor.
    private func scanDuplicateFolderPaths() -> [Finding] {
        var out: [Finding] = []
        var byPath: [String: [VaultFolder]] = [:]
        for folder in VaultFolderService.shared.folders {
            byPath[folder.relativePath, default: []].append(folder)
        }
        for (path, dupes) in byPath where dupes.count > 1 {
            let ids = dupes.map { $0.id.uuidString.prefix(8) }.joined(separator: ", ")
            out.append(Finding(
                id: "dupe-\(path)",
                kind: .duplicateFolderPath,
                severity: .error,
                summary: "Duplicate folder rows at path: \(path)",
                detail: "Multiple folder rows share this relative_path (\(dupes.count) rows: \(ids)). Schema invariant violation — this should never happen. Manual investigation required.",
                isFixable: false,
                fixLabel: nil,
                payload: Finding.Payload(relativePath: path)
            ))
        }
        return out
    }

    /// Check 6: breadcrumb files older than 30 days in
    /// `.cider/folders/.trash/`. Safe to clean as housekeeping.
    private func scanOrphanBreadcrumbs() -> [Finding] {
        var out: [Finding] = []
        let fm = FileManager.default
        let trashDir = vaultRoot.appendingPathComponent(".cider/folders/.trash")
        guard let files = try? fm.contentsOfDirectory(
            at: trashDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return out }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        for url in files where url.lastPathComponent.hasSuffix("-breadcrumbs.json") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = values?.contentModificationDate ?? Date()
            if modDate < cutoff {
                out.append(Finding(
                    id: "orphan-breadcrumb-\(url.lastPathComponent)",
                    kind: .orphanBreadcrumb,
                    severity: .info,
                    summary: "Old breadcrumb file: \(url.lastPathComponent)",
                    detail: "Breadcrumb modified \(modDate.formatted()), older than 30 days. Safe to delete — nothing references it anymore.",
                    isFixable: true,
                    fixLabel: "Delete breadcrumb file",
                    payload: Finding.Payload(breadcrumbFile: url.path)
                ))
            }
        }
        return out
    }

    /// Check 7: folders row exists for a reserved top dir (Inbox, Bookmarks,
    /// Notes, etc). These should never be tracked as user folders. Legacy
    /// drift that the schema-v3 migration tried to clean up, but still
    /// worth monitoring.
    private func scanReservedPathsInFolders() -> [Finding] {
        var out: [Finding] = []
        for folder in VaultFolderService.shared.folders {
            let topComponent = folder.relativePath.split(separator: "/").first.map(String.init) ?? folder.relativePath
            if Self.reservedTopDirs.contains(topComponent) {
                out.append(Finding(
                    id: "reserved-\(folder.id.uuidString)",
                    kind: .reservedPathInFolders,
                    severity: .error,
                    summary: "Reserved path in folders table: \(folder.relativePath)",
                    detail: "This path starts with a reserved top-level directory (\(topComponent)) and should not be tracked as a user folder. Usually means the schema-v3 migration missed it.",
                    isFixable: true,
                    fixLabel: "Remove folder row (reserved path)",
                    payload: Finding.Payload(folderID: folder.id, relativePath: folder.relativePath)
                ))
            }
        }
        return out
    }

    // MARK: - Helpers

    private func countItemsReferencingFolder(_ folderID: UUID) -> Int {
        guard let db = database else { return 0 }
        do {
            let itemStmt = try db.prepare("SELECT COUNT(*) FROM items WHERE folder_id = ?;")
            itemStmt.bind(DatabaseHelpers.encode(folderID), at: 1)
            let itemCount = try itemStmt.step() ? Int(itemStmt.int64(at: 0)) : 0
            let sessionStmt = try db.prepare("SELECT COUNT(*) FROM sessions WHERE folder_id = ?;")
            sessionStmt.bind(DatabaseHelpers.encode(folderID), at: 1)
            let sessionCount = try sessionStmt.step() ? Int(sessionStmt.int64(at: 0)) : 0
            return itemCount + sessionCount
        } catch {
            logger.error("countItemsReferencingFolder: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Fix

    /// Applies the fix for a single finding. Returns true on success,
    /// false on failure or unsupported finding. Not transactional across
    /// findings — callers are expected to scan again after a batch fix
    /// to verify the state.
    @discardableResult
    func fix(_ finding: Finding) -> Bool {
        guard finding.isFixable else { return false }
        switch finding.kind {
        case .ghostFolderRow:
            return fixGhostFolderRow(finding)
        case .untrackedEmptyDir:
            return fixUntrackedEmptyDir(finding)
        case .staleItemFolderRef:
            return fixStaleItemFolderRef(finding)
        case .staleSessionFolderRef:
            return fixStaleSessionFolderRef(finding)
        case .orphanBreadcrumb:
            return fixOrphanBreadcrumb(finding)
        case .reservedPathInFolders:
            return fixReservedPathInFolders(finding)
        case .untrackedNonEmptyDir, .duplicateFolderPath:
            return false
        }
    }

    private func fixGhostFolderRow(_ finding: Finding) -> Bool {
        guard let db = database, let folderID = finding.payload.folderID else { return false }
        do {
            // Unfile any items + sessions still pointing at this row, then delete.
            let unfileItems = try db.prepare("UPDATE items SET folder_id = NULL WHERE folder_id = ?;")
            unfileItems.bind(DatabaseHelpers.encode(folderID), at: 1)
            try unfileItems.step()
            let unfileSessions = try db.prepare("UPDATE sessions SET folder_id = NULL WHERE folder_id = ?;")
            unfileSessions.bind(DatabaseHelpers.encode(folderID), at: 1)
            try unfileSessions.step()
            let deleteRow = try db.prepare("DELETE FROM folders WHERE id = ?;")
            deleteRow.bind(DatabaseHelpers.encode(folderID), at: 1)
            try deleteRow.step()
            logger.info("Doctor fix: dropped ghost folder row \(folderID.uuidString.prefix(8)) at \(finding.payload.relativePath ?? "<unknown>")")
            return true
        } catch {
            logger.error("fixGhostFolderRow: \(error.localizedDescription)")
            return false
        }
    }

    private func fixUntrackedEmptyDir(_ finding: Finding) -> Bool {
        guard let relPath = finding.payload.relativePath else { return false }
        let url = vaultRoot.appendingPathComponent(relPath)
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Doctor fix: removed untracked empty directory \(relPath)")
            return true
        } catch {
            logger.error("fixUntrackedEmptyDir: \(error.localizedDescription)")
            return false
        }
    }

    private func fixStaleItemFolderRef(_ finding: Finding) -> Bool {
        guard let db = database, let itemID = finding.payload.itemID else { return false }
        do {
            let stmt = try db.prepare("UPDATE items SET folder_id = NULL WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(itemID), at: 1)
            try stmt.step()
            logger.info("Doctor fix: unfiled stale item ref \(itemID.uuidString.prefix(8))")
            return true
        } catch {
            logger.error("fixStaleItemFolderRef: \(error.localizedDescription)")
            return false
        }
    }

    private func fixStaleSessionFolderRef(_ finding: Finding) -> Bool {
        guard let db = database, let sessionID = finding.payload.sessionID else { return false }
        do {
            let stmt = try db.prepare("UPDATE sessions SET folder_id = NULL WHERE id = ?;")
            stmt.bind(DatabaseHelpers.encode(sessionID), at: 1)
            try stmt.step()
            logger.info("Doctor fix: unfiled stale session ref \(sessionID.uuidString.prefix(8))")
            return true
        } catch {
            logger.error("fixStaleSessionFolderRef: \(error.localizedDescription)")
            return false
        }
    }

    private func fixOrphanBreadcrumb(_ finding: Finding) -> Bool {
        guard let path = finding.payload.breadcrumbFile else { return false }
        do {
            try FileManager.default.removeItem(atPath: path)
            logger.info("Doctor fix: deleted orphan breadcrumb \(path)")
            return true
        } catch {
            logger.error("fixOrphanBreadcrumb: \(error.localizedDescription)")
            return false
        }
    }

    private func fixReservedPathInFolders(_ finding: Finding) -> Bool {
        guard let db = database, let folderID = finding.payload.folderID else { return false }
        do {
            // Mirrors the schema-v3 migration logic: re-parent dependents
            // to NULL first so the FK doesn't reject the delete.
            let unfileItems = try db.prepare("UPDATE items SET folder_id = NULL WHERE folder_id = ?;")
            unfileItems.bind(DatabaseHelpers.encode(folderID), at: 1)
            try unfileItems.step()
            let unfileSessions = try db.prepare("UPDATE sessions SET folder_id = NULL WHERE folder_id = ?;")
            unfileSessions.bind(DatabaseHelpers.encode(folderID), at: 1)
            try unfileSessions.step()
            let deleteRow = try db.prepare("DELETE FROM folders WHERE id = ?;")
            deleteRow.bind(DatabaseHelpers.encode(folderID), at: 1)
            try deleteRow.step()
            logger.info("Doctor fix: dropped reserved-path folder row \(folderID.uuidString.prefix(8))")
            return true
        } catch {
            logger.error("fixReservedPathInFolders: \(error.localizedDescription)")
            return false
        }
    }
}
