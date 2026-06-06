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
            case staleFolderSyncAlias  // sync alias decision points at a nonexistent local folder
            case folderPathOutsideVault // folders.relative_path is not a safe relative vault path
            case artifactLookingFolderRow // folders row path looks like a durable file artifact
            case noncanonicalFolderFamily // bracketed or otherwise noncanonical registered folder family
            case orphanBreadcrumb      // old .cider/folders/.trash/*-breadcrumbs.json > 30 days old
            case reservedPathInFolders // folders row for a reserved top dir (legacy drift)
            case suspiciousFlattenedFolderDuplicate // root folder duplicates an existing nested folder name, often with numeric suffix
            case duplicateNoteContent // notes with same normalized title and exact content
            case duplicateBookmarkURL // bookmarks with same canonical URL
            case duplicateContactEmail // contacts with same normalized email
            case duplicateContactPhone // contacts with same normalized phone
            case untrackedDuplicateMarkdown // markdown file exists on disk but is an exact copy of a tracked note
        }

        /// Fix-action payload. Decoded opaquely — NOT user-facing.
        struct Payload: Codable {
            var folderID: UUID?
            var itemID: UUID?
            var sessionID: UUID?
            var relativePath: String?
            var relatedRelativePaths: [String]?
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
        var findings = scanFolderIntegrityFindings()
        findings.append(contentsOf: scanOrphanBreadcrumbs())
        findings.append(contentsOf: scanDuplicateVaultEntities())
        findings.append(contentsOf: scanUntrackedDuplicateMarkdownArtifacts())

        return Report(
            startedAt: started,
            finishedAt: Date(),
            findings: findings
        )
    }

    /// Runs only folder-critical checks that are cheap and safe enough for startup.
    /// This intentionally excludes duplicate entity scans and trash housekeeping.
    func scanFolderIntegrity() -> Report {
        let started = Date()
        return Report(
            startedAt: started,
            finishedAt: Date(),
            findings: scanFolderIntegrityFindings()
        )
    }

    func logStartupFolderIntegrity(origin: String = "startup") {
        let report = scanFolderIntegrity()
        guard !report.findings.isEmpty else {
            logger.info("Folder integrity \(origin, privacy: .public): no findings")
            return
        }

        let grouped = Dictionary(grouping: report.findings, by: \.kind)
            .map { "\($0.key.rawValue)=\($0.value.count)" }
            .sorted()
            .joined(separator: " ")
        let errorCount = report.counts[.error, default: 0]
        let warningCount = report.counts[.warning, default: 0]
        logger.warning("Folder integrity \(origin, privacy: .public): findings=\(report.findings.count, privacy: .public) errors=\(errorCount, privacy: .public) warnings=\(warningCount, privacy: .public) \(grouped, privacy: .public)")

        for finding in report.findings.prefix(10) {
            logger.warning("Folder integrity finding \(origin, privacy: .public): kind=\(finding.kind.rawValue, privacy: .public) severity=\(finding.severity.rawValue, privacy: .public) summary='\(finding.summary, privacy: .public)' detail='\(finding.detail, privacy: .public)'")
        }
    }

    private func scanFolderIntegrityFindings() -> [Finding] {
        var findings: [Finding] = []
        findings.append(contentsOf: scanGhostFolderRows())
        findings.append(contentsOf: scanUntrackedDirectories())
        findings.append(contentsOf: scanStaleItemFolderRefs())
        findings.append(contentsOf: scanStaleSessionFolderRefs())
        findings.append(contentsOf: scanDuplicateFolderPaths())
        findings.append(contentsOf: scanStaleFolderSyncAliasFindings())
        findings.append(contentsOf: scanFolderPathSafetyFindings())
        findings.append(contentsOf: scanArtifactLookingFolderRows())
        findings.append(contentsOf: scanReservedPathsInFolders())
        findings.append(contentsOf: scanSuspiciousFlattenedFolderDuplicates())
        return findings
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

            // Determine emptiness from all child entries, including dotfiles.
            // Hidden-only directories are not safe to auto-delete: files like
            // `.keep`, `.gitignore`, or sync metadata can be meaningful even
            // when Finder makes the directory look empty.
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
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

    private func scanStaleFolderSyncAliasFindings() -> [Finding] {
        guard let db = database else { return [] }
        return scanStaleFolderSyncAliasFindings(in: db)
    }

    func scanStaleFolderSyncAliasFindings(in db: CiderDatabase) -> [Finding] {
        var out: [Finding] = []
        do {
            let stmt = try db.prepare("""
                SELECT d.remote_folder_id, d.local_folder_id, d.requested_path
                FROM folder_sync_decisions d
                LEFT JOIN folders f ON f.id = d.local_folder_id
                WHERE d.decision = 'alias'
                  AND (d.local_folder_id IS NULL OR f.id IS NULL)
                ORDER BY d.updated_at DESC;
                """)
            while try stmt.step() {
                guard let remoteFolderID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else {
                    continue
                }
                let localFolderID = stmt.optionalString(at: 1).flatMap(DatabaseHelpers.decodeUUID)
                let requestedPath = stmt.optionalString(at: 2) ?? "<unknown path>"
                let remoteShort = remoteFolderID.uuidString.prefix(8)
                let detail: String
                if let localFolderID {
                    detail = "Remote folder \(remoteShort) aliases to local folder \(localFolderID.uuidString.prefix(8)), but that folder row no longer exists. Future sync pulls should quarantine or re-evaluate this remote folder instead of recreating a duplicate."
                } else {
                    detail = "Remote folder \(remoteShort) has an alias decision without a local folder target. Future sync pulls should quarantine or re-evaluate this remote folder instead of recreating a duplicate."
                }
                out.append(Finding(
                    id: "stale-folder-sync-alias-\(remoteFolderID.uuidString)",
                    kind: .staleFolderSyncAlias,
                    severity: .error,
                    summary: "Stale sync folder alias: \(requestedPath)",
                    detail: detail,
                    isFixable: false,
                    fixLabel: nil,
                    payload: Finding.Payload(
                        folderID: localFolderID,
                        relativePath: requestedPath
                    )
                ))
            }
        } catch {
            logger.error("scanStaleFolderSyncAliasFindings: \(error.localizedDescription)")
        }
        return out
    }

    private func scanFolderPathSafetyFindings() -> [Finding] {
        guard let db = database else { return [] }
        return scanFolderPathSafetyFindings(in: db)
    }

    func scanFolderPathSafetyFindings(in db: CiderDatabase) -> [Finding] {
        var out: [Finding] = []
        do {
            let stmt = try db.prepare("""
                SELECT id, relative_path
                FROM folders
                ORDER BY relative_path COLLATE NOCASE;
                """)
            while try stmt.step() {
                let relativePath = stmt.string(at: 1)
                guard let reason = Self.folderPathSafetyReason(relativePath),
                      let folderID = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else {
                    continue
                }
                out.append(Finding(
                    id: "folder-path-outside-vault-\(folderID.uuidString)",
                    kind: .folderPathOutsideVault,
                    severity: .error,
                    summary: "Unsafe folder path: \(relativePath)",
                    detail: "Folder row points outside the vault boundary because its relative_path \(reason). Manual review required before repairing this row.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: Finding.Payload(
                        folderID: folderID,
                        relativePath: relativePath
                    )
                ))
            }
        } catch {
            logger.error("scanFolderPathSafetyFindings: \(error.localizedDescription)")
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

    private func scanArtifactLookingFolderRows() -> [Finding] {
        var out: [Finding] = []
        let folders = VaultFolderService.shared.folders
        for folder in folders where folder.looksLikeArtifactPath {
            let directItemCount = countItemsReferencingFolder(folder.id)
            let childFolderCount = folders.filter { $0.parentRelativePath == folder.relativePath }.count
            let parentDescription = folder.parentRelativePath.map { " Parent folder: \($0)." } ?? ""
            out.append(Finding(
                id: "artifact-looking-folder-\(folder.id.uuidString)",
                kind: .artifactLookingFolderRow,
                severity: .warning,
                summary: "Artifact-looking folder row: \(folder.relativePath)",
                detail: "Folder row path ends with a known file artifact extension, but folders should represent containers, not saved item files.\(parentDescription) Direct items: \(directItemCount). Child folders: \(childFolderCount). Review before routing anything here.",
                isFixable: false,
                fixLabel: nil,
                payload: Finding.Payload(
                    folderID: folder.id,
                    relativePath: folder.relativePath
                )
            ))
        }
        return out
    }

    /// Check 8: root folder looks like a flattened duplicate of a nested folder.
    /// This is intentionally conservative and read-only. It catches sync/adoption
    /// drift where a child folder was created at the vault root after its remote
    /// parent could not be resolved. Cleanup needs human judgement because both
    /// folders may now contain distinct files.
    private func scanSuspiciousFlattenedFolderDuplicates() -> [Finding] {
        let folders = VaultFolderService.shared.folders
        let nestedByNormalizedName = Dictionary(grouping: folders.filter { $0.parentRelativePath != nil }) { folder in
            Self.normalizedFolderDuplicateKey(folder.name)
        }
        let rootFolders = folders.filter { $0.parentRelativePath == nil }
        var out: [Finding] = []

        for folder in rootFolders {
            let key = Self.normalizedFolderDuplicateKey(folder.name)
            guard let nestedMatches = nestedByNormalizedName[key], !nestedMatches.isEmpty else { continue }
            let nestedPaths = nestedMatches.map(\.relativePath).sorted()
            guard !Self.isAllowedRootNestedFolderNameCollision(
                rootRelativePath: folder.relativePath,
                nestedRelativePaths: nestedPaths
            ) else { continue }
            let matchPaths = nestedPaths.joined(separator: ", ")
            out.append(Finding(
                id: "flattened-folder-\(folder.id.uuidString)",
                kind: .suspiciousFlattenedFolderDuplicate,
                severity: .warning,
                summary: "Possible flattened folder duplicate: \(folder.relativePath)",
                detail: "Root folder '\(folder.relativePath)' has the same normalized name as nested folder path(s): \(matchPaths). This can happen when sync receives a child folder before its parent and must be reviewed before merging or deleting files.",
                isFixable: false,
                fixLabel: nil,
                payload: Finding.Payload(
                    folderID: folder.id,
                    relativePath: folder.relativePath,
                    relatedRelativePaths: nestedPaths
                )
            ))
        }

        let siblingGroups = Dictionary(grouping: folders) { folder in
            "\(folder.parentRelativePath ?? "")|\(Self.normalizedFolderDuplicateKey(folder.name))"
        }
        for (_, siblings) in siblingGroups where Self.shouldFlagNumericSuffixFolderGroup(siblings.map(\.name)) {
            let canonicalPaths = siblings
                .filter { !Self.hasNumericSuffix($0.name) }
                .map(\.relativePath)
                .sorted()
            let numericSuffixPaths = siblings
                .filter { Self.hasNumericSuffix($0.name) }
                .map(\.relativePath)
                .sorted()
            let peerDescription: String
            if canonicalPaths.isEmpty {
                peerDescription = "multiple same-parent numeric-suffix siblings exist: \(numericSuffixPaths.joined(separator: ", "))"
            } else {
                peerDescription = "a same-parent canonical folder exists: \(canonicalPaths.joined(separator: ", "))"
            }
            for folder in siblings where Self.hasNumericSuffix(folder.name) {
                let relatedPaths = (canonicalPaths + numericSuffixPaths)
                    .filter { $0 != folder.relativePath }
                    .sorted()
                out.append(Finding(
                    id: "numeric-suffix-folder-\(folder.id.uuidString)",
                    kind: .suspiciousFlattenedFolderDuplicate,
                    severity: .warning,
                    summary: "Possible numeric-suffix folder duplicate: \(folder.relativePath)",
                    detail: "Folder '\(folder.relativePath)' has a numeric-suffix name and \(peerDescription). Review before merging or deleting files.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: Finding.Payload(
                        folderID: folder.id,
                        relativePath: folder.relativePath,
                        relatedRelativePaths: relatedPaths
                    )
                ))
            }
        }

        return out
    }

    /// Check 9: cross-entity duplicate candidates (notes/bookmarks/contacts).
    /// Read-only by design; merge/trash is entity-specific and must be reviewed.
    private func scanDuplicateVaultEntities() -> [Finding] {
        VaultDuplicateAuditor.scan().map { duplicate in
            Finding(
                id: duplicate.id,
                kind: doctorKind(for: duplicate),
                severity: duplicate.confidence == .exact ? .warning : .info,
                summary: duplicate.summary,
                detail: duplicate.detail,
                isFixable: false,
                fixLabel: nil,
                payload: Finding.Payload(relativePath: duplicate.items.compactMap(\.path).first)
            )
        }
    }

    private func doctorKind(for duplicate: VaultDuplicateAuditor.Finding) -> Finding.Kind {
        switch (duplicate.entityType, duplicate.kind) {
        case (.note, .exactContent):
            return .duplicateNoteContent
        case (.bookmark, .canonicalURL):
            return .duplicateBookmarkURL
        case (.contact, .email):
            return .duplicateContactEmail
        case (.contact, .phone):
            return .duplicateContactPhone
        default:
            return .duplicateNoteContent
        }
    }

    private func scanUntrackedDuplicateMarkdownArtifacts() -> [Finding] {
        guard let db = database else { return [] }
        return scanUntrackedDuplicateMarkdownArtifacts(vaultRoot: vaultRoot, database: db)
    }

    func scanUntrackedDuplicateMarkdownArtifacts(
        vaultRoot: URL,
        database db: CiderDatabase
    ) -> [Finding] {
        let fm = FileManager.default
        var trackedPaths = Set<String>()
        var trackedPathsByContent: [String: [String]] = [:]

        do {
            let stmt = try db.prepare("""
                SELECT i.relative_path
                FROM items i
                WHERE i.type = 'note'
                  AND i.relative_path IS NOT NULL
                ORDER BY i.relative_path COLLATE NOCASE;
                """)
            while try stmt.step() {
                guard let relativePath = stmt.optionalString(at: 0) else { continue }
                trackedPaths.insert(relativePath)
                let trackedURL = vaultRoot.appendingPathComponent(relativePath)
                guard let content = try? String(contentsOf: trackedURL, encoding: .utf8) else {
                    continue
                }
                guard !content.isEmpty else { continue }
                trackedPathsByContent[content, default: []].append(relativePath)
            }
        } catch {
            logger.error("scanUntrackedDuplicateMarkdownArtifacts: \(error.localizedDescription)")
            return []
        }

        guard !trackedPathsByContent.isEmpty,
              let enumerator = fm.enumerator(
                at: vaultRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        var out: [Finding] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md",
                  let isRegular = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular else { continue }
            let relativePath = Self.relativePath(for: url, under: vaultRoot)
            guard !trackedPaths.contains(relativePath),
                  let content = try? String(contentsOf: url, encoding: .utf8),
                  let canonicalPaths = trackedPathsByContent[content],
                  !canonicalPaths.isEmpty else { continue }

            out.append(Finding(
                id: "untracked-duplicate-markdown-\(Self.findingIDPathComponent(relativePath))",
                kind: .untrackedDuplicateMarkdown,
                severity: .warning,
                summary: "Untracked duplicate Markdown file: \(relativePath)",
                detail: "Markdown file exists on disk without a note row and exactly matches tracked note path(s): \(canonicalPaths.joined(separator: ", ")). The fix removes only this untracked duplicate artifact.",
                isFixable: true,
                fixLabel: "Remove untracked duplicate Markdown file",
                payload: Finding.Payload(
                    relativePath: relativePath,
                    relatedRelativePaths: canonicalPaths.sorted()
                )
            ))
        }

        return out.sorted {
            ($0.payload.relativePath ?? "") < ($1.payload.relativePath ?? "")
        }
    }

    // MARK: - Helpers

    nonisolated static func isAllowedRootNestedFolderNameCollision(
        rootRelativePath: String,
        nestedRelativePaths: [String]
    ) -> Bool {
        // `Media` is a canonical Cider top-level library container. Users can also
        // have a domain/topic folder named `Media` nested elsewhere (for example
        // `Spaces/Media`), so this name collision is not evidence that sync
        // flattened a child folder to the vault root.
        rootRelativePath == "Media" && nestedRelativePaths.contains { $0 != "Media" }
    }

    nonisolated static func hasNumericSuffix(_ name: String) -> Bool {
        name.range(of: #"\s+\d+$"#, options: .regularExpression) != nil
    }

    nonisolated static func shouldFlagNumericSuffixFolderGroup(_ names: [String]) -> Bool {
        let numericSuffixCount = names.filter { hasNumericSuffix($0) }.count
        guard numericSuffixCount > 0, names.count > 1 else { return false }
        let hasCanonicalSibling = names.contains { !hasNumericSuffix($0) }
        return hasCanonicalSibling || numericSuffixCount > 1
    }

    private static func normalizedFolderDuplicateKey(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedNumericSuffix = trimmed.replacingOccurrences(
            of: #"(?:\s+\d+)+$"#,
            with: "",
            options: .regularExpression
        )
        return strippedNumericSuffix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func relativePath(for url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func findingIDPathComponent(_ relativePath: String) -> String {
        relativePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func folderPathSafetyReason(_ relativePath: String) -> String? {
        if relativePath.isEmpty {
            return "is empty"
        }
        if relativePath.hasPrefix("/") {
            return "is absolute"
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.contains("..") {
            return "contains '..'"
        }
        if components.contains(".") {
            return "contains '.'"
        }
        if components.contains(where: \.isEmpty) {
            return "contains an empty path component"
        }
        return nil
    }

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
        case .untrackedDuplicateMarkdown:
            return fixUntrackedDuplicateMarkdown(finding)
        case .untrackedNonEmptyDir,
             .duplicateFolderPath,
             .staleFolderSyncAlias,
             .folderPathOutsideVault,
             .artifactLookingFolderRow,
             .noncanonicalFolderFamily,
             .suspiciousFlattenedFolderDuplicate,
             .duplicateNoteContent,
             .duplicateBookmarkURL,
             .duplicateContactEmail,
             .duplicateContactPhone:
            return false
        }
    }

    private func fixUntrackedDuplicateMarkdown(_ finding: Finding) -> Bool {
        guard let relPath = finding.payload.relativePath,
              relPath.hasSuffix(".md") else { return false }
        let url = vaultRoot.appendingPathComponent(relPath)
        let standardizedVault = vaultRoot.standardizedFileURL.path
        let standardizedFile = url.standardizedFileURL.path
        guard standardizedFile.hasPrefix(standardizedVault + "/") else {
            return false
        }
        do {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            try FileManager.default.removeItem(at: url)
            logger.info("Doctor fix: removed untracked duplicate Markdown file \(relPath)")
            return true
        } catch {
            logger.error("fixUntrackedDuplicateMarkdown: \(error.localizedDescription)")
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
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
            guard contents.isEmpty else {
                logger.warning("Doctor fix refused stale untracked-empty-dir finding for non-empty directory \(relPath)")
                return false
            }
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
