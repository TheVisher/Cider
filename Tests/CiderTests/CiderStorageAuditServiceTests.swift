import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Storage Audit Service Tests")
@MainActor
struct CiderStorageAuditServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-storage-audit-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-storage-doctor-apply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDirectories(_ relativePaths: [String], under root: URL) throws {
        for path in relativePaths {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func insertFolder(_ db: CiderDatabase, id: UUID, relativePath: String) throws {
        let now = DatabaseHelpers.encode(Date(timeIntervalSince1970: 10))
        let stmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(relativePath, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
        try stmt.step()
    }

    private func insertItem(
        _ db: CiderDatabase,
        id: UUID,
        type: String,
        title: String,
        relativePath: String?
    ) throws {
        let now = DatabaseHelpers.encode(Date(timeIntervalSince1970: 10))
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    private func insertItem(
        _ db: CiderDatabase,
        id: UUID,
        type: String,
        title: String,
        relativePath: String?,
        folderID: UUID
    ) throws {
        let now = DatabaseHelpers.encode(Date(timeIntervalSince1970: 10))
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind(DatabaseHelpers.encode(folderID), at: 6)
            .bind(relativePath, at: 7)
        try stmt.step()
    }

    private func insertFolderSyncDecision(
        _ db: CiderDatabase,
        remoteFolderID: UUID,
        localFolderID: UUID?,
        decision: String,
        requestedPath: String
    ) throws {
        let now = DatabaseHelpers.encode(Date(timeIntervalSince1970: 10))
        let stmt = try db.prepare("""
            INSERT INTO folder_sync_decisions (
                remote_folder_id, local_folder_id, decision, reason, requested_path,
                source, metadata, created_at, updated_at
            )
            VALUES (?, ?, ?, 'test', ?, 'sync', '{}', ?, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(remoteFolderID), at: 1)
        stmt.bind(localFolderID.map(DatabaseHelpers.encode), at: 2)
        stmt.bind(decision, at: 3)
            .bind(requestedPath, at: 4)
            .bind(now, at: 5)
            .bind(now, at: 6)
        try stmt.step()
    }

    private func folderExists(_ db: CiderDatabase, relativePath: String) throws -> Bool {
        let stmt = try db.prepare("SELECT 1 FROM folders WHERE relative_path = ? LIMIT 1;")
        stmt.bind(relativePath, at: 1)
        return try stmt.step()
    }

    private func itemCountsProvider(for db: CiderDatabase) -> () -> [String: Int] {
        {
            var counts: [String: Int] = [:]
            if let folders = try? self.rowCount(db, table: "folders") {
                counts["folder"] = folders
            }
            guard let stmt = try? db.prepare("SELECT type, COUNT(*) FROM items GROUP BY type;") else {
                return counts
            }
            while (try? stmt.step()) == true {
                counts[stmt.string(at: 0)] = stmt.int(at: 1)
            }
            return counts
        }
    }

    private func rowCount(_ db: CiderDatabase, table: String) throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM \(table);")
        return try stmt.step() ? stmt.int(at: 0) : 0
    }

    @Test("VaultDoctor reports stale folder sync aliases")
    func vaultDoctorReportsStaleFolderSyncAliases() throws {
        let (db, url) = try makeTestDB()
        defer { cleanup(url) }
        let remoteFolderID = UUID()
        let missingLocalFolderID = UUID()
        try db.runSQL("PRAGMA foreign_keys=OFF;")
        try insertFolderSyncDecision(
            db,
            remoteFolderID: remoteFolderID,
            localFolderID: missingLocalFolderID,
            decision: "alias",
            requestedPath: "Applications 2"
        )
        try db.runSQL("PRAGMA foreign_keys=ON;")

        let findings = VaultDoctor.shared.scanStaleFolderSyncAliasFindings(in: db)

        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.kind == .staleFolderSyncAlias)
        #expect(finding.severity == .error)
        #expect(!finding.isFixable)
        #expect(finding.payload.folderID == missingLocalFolderID)
        #expect(finding.payload.relativePath == "Applications 2")
        #expect(finding.summary.contains("Applications 2"))
        #expect(finding.detail.contains(remoteFolderID.uuidString.prefix(8)))
    }

    @Test("VaultDoctor reports folder rows that point outside the vault")
    func vaultDoctorReportsFolderRowsOutsideVault() throws {
        let (db, url) = try makeTestDB()
        defer { cleanup(url) }
        let folderID = UUID()
        try insertFolder(db, id: folderID, relativePath: "../Secrets")

        let findings = VaultDoctor.shared.scanFolderPathSafetyFindings(in: db)

        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.kind == .folderPathOutsideVault)
        #expect(finding.severity == .error)
        #expect(!finding.isFixable)
        #expect(finding.payload.folderID == folderID)
        #expect(finding.payload.relativePath == "../Secrets")
        #expect(finding.summary.contains("../Secrets"))
    }

    @Test("VaultDoctor treats hidden-only directories as non-empty and refuses stale empty-dir fixes")
    func vaultDoctorHiddenOnlyDirectoriesAreNotAutoDeleted() throws {
        let fm = FileManager.default
        let vault = try makeTempVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let hiddenOnly = vault.appendingPathComponent("Projects/HiddenOnly", isDirectory: true)
        try fm.createDirectory(at: hiddenOnly, withIntermediateDirectories: true)
        let hiddenFile = hiddenOnly.appendingPathComponent(".keep")
        try "keep me".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let hiddenFinding = try #require(VaultDoctor.shared.scanFolderIntegrity().findings.first {
            $0.payload.relativePath?.hasSuffix("Projects/HiddenOnly") == true
        })
        #expect(hiddenFinding.kind == .untrackedNonEmptyDir)
        #expect(!hiddenFinding.isFixable)
        #expect(fm.fileExists(atPath: hiddenFile.path))

        let initiallyEmpty = vault.appendingPathComponent("Projects/InitiallyEmpty", isDirectory: true)
        try fm.createDirectory(at: initiallyEmpty, withIntermediateDirectories: true)
        let staleFinding = try #require(VaultDoctor.shared.scanFolderIntegrity().findings.first {
            $0.payload.relativePath?.hasSuffix("Projects/InitiallyEmpty") == true
        })
        #expect(staleFinding.kind == .untrackedEmptyDir)
        #expect(staleFinding.isFixable)

        let lateHiddenFile = initiallyEmpty.appendingPathComponent(".late")
        try "arrived after scan".write(to: lateHiddenFile, atomically: true, encoding: .utf8)

        #expect(!VaultDoctor.shared.fix(staleFinding))
        #expect(fm.fileExists(atPath: lateHiddenFile.path))
        #expect(fm.fileExists(atPath: initiallyEmpty.path))
    }

    private func flattenedFolderDoctorReport(folderID: UUID) -> VaultDoctor.Report {
        VaultDoctor.Report(
            startedAt: Date(timeIntervalSince1970: 11),
            finishedAt: Date(timeIntervalSince1970: 12),
            findings: [
                VaultDoctor.Finding(
                    id: "flattened-folder-root-games",
                    kind: .suspiciousFlattenedFolderDuplicate,
                    severity: .warning,
                    summary: "Possible flattened folder duplicate: Games",
                    detail: "Root folder 'Games' has the same normalized name as nested folder path(s): Media/Games.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: VaultDoctor.Finding.Payload(
                        folderID: folderID,
                        relativePath: "Games",
                        relatedRelativePaths: ["Media/Games"]
                    )
                )
            ]
        )
    }

    private func sqliteObjectExists(_ name: String, type: String, in db: CiderDatabase) throws -> Bool {
        let stmt = try db.prepare("""
            SELECT count(*)
            FROM sqlite_master
            WHERE type = ? AND name = ?;
            """)
        stmt.bind(type, at: 1)
        stmt.bind(name, at: 2)
        try stmt.step()
        return stmt.int(at: 0) == 1
    }

    private func makeStorageAuditService(db: CiderDatabase) -> CiderStorageAuditService {
        CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { [:] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )
    }

    @Test("storage audit reports bracketed Media folder drift with attached item samples")
    func storageAuditReportsBracketedMediaFolderDriftWithAttachedItemSamples() throws {
        let (db, url) = try makeTestDB()
        defer { cleanup(url) }

        let mediaID = UUID()
        let gamesID = UUID()
        let bracketedMediaID = UUID()
        let bracketedGamesID = UUID()
        let artifactChildID = UUID()
        try insertFolder(db, id: mediaID, relativePath: "Media")
        try insertFolder(db, id: gamesID, relativePath: "Media/Games")
        try insertFolder(db, id: bracketedMediaID, relativePath: "[Media]")
        try insertFolder(db, id: bracketedGamesID, relativePath: "[Media]/[Games]")
        try insertFolder(db, id: artifactChildID, relativePath: "[Media]/[Games]/Paralives.webloc")
        try insertFolder(db, id: UUID(), relativePath: "Projects/Cider/QA")
        try insertFolder(db, id: UUID(), relativePath: "Spaces/Media")

        try insertItem(db, id: UUID(), type: "bookmark", title: "Steam", relativePath: "Media/Games/Steam.webloc", folderID: gamesID)
        try insertItem(db, id: UUID(), type: "bookmark", title: "Paralives", relativePath: "[Media]/[Games]/Paralives.webloc", folderID: bracketedGamesID)
        try insertItem(db, id: UUID(), type: "bookmark", title: "Skate Story", relativePath: "[Media]/[Games]/Skate Story.webloc", folderID: bracketedGamesID)

        let service = makeStorageAuditService(db: db)

        let report = try service.audit()

        #expect(report.doctorFindingGroups["warning:noncanonicalFolderFamily"] == 2)
        let mediaFinding = try #require(report.doctorFindingSamples.first {
            $0.kind == "noncanonicalFolderFamily" && $0.relativePath == "[Media]/[Games]"
        })
        #expect(mediaFinding.isFixable == false)
        #expect(mediaFinding.relatedRelativePaths.contains("Media/Games"))
        #expect(mediaFinding.relatedRelativePaths.contains("[Media]/[Games]/Paralives.webloc"))
        #expect(mediaFinding.detail.contains("bracketed legacy/sync drift"))
        #expect(mediaFinding.detail.contains("[Media]/[Games] has 2 direct item(s)"))
        #expect(mediaFinding.detail.contains("Paralives"))
        #expect(mediaFinding.detail.contains("Skate Story"))
        #expect(mediaFinding.nextSafeAction.contains("read-only"))

        let dict = storageAuditReportToDict(report)
        let samples = try #require(dict["doctorFindingSamples"] as? [[String: Any]])
        let jsonSample = try #require(samples.first {
            $0["kind"] as? String == "noncanonicalFolderFamily"
                && $0["relativePath"] as? String == "[Media]/[Games]"
        })
        #expect(jsonSample["directItemCount"] as? Int == 2)
        let representativeItems = try #require(jsonSample["representativeItems"] as? [[String: Any]])
        #expect(representativeItems.map { $0["title"] as? String }.contains("Paralives"))
    }

    @Test("active duplicate invariant check reports duplicate candidates and count drift read-only")
    func activeDuplicateInvariantCheckReportsDuplicateCandidatesAndCountDriftReadOnly() throws {
        let (db, url) = try makeTestDB()
        defer { cleanup(url) }
        let firstID = UUID()
        let secondID = UUID()
        try db.runSQL("DROP INDEX IF EXISTS idx_items_path;")
        try insertItem(db, id: firstID, type: "note", title: "CodexNote", relativePath: "Inbox/Notes/CodexNote.md")
        try insertItem(db, id: secondID, type: "note", title: "CodexNote 2", relativePath: "Inbox/Notes/CodexNote.md")
        let duplicateFinding = VaultDuplicateAuditor.Finding(
            id: "duplicate-note-content-test",
            entityType: .note,
            kind: .exactContent,
            confidence: .exact,
            summary: "Exact duplicate note content: CodexNote, CodexNote 2",
            detail: "2 note records share exactContent.",
            items: [
                VaultDuplicateAuditor.Item(id: firstID.uuidString, title: "CodexNote", path: "Inbox/Notes/CodexNote.md", value: nil),
                VaultDuplicateAuditor.Item(id: secondID.uuidString, title: "CodexNote 2", path: "Inbox/Notes/CodexNote.md", value: nil),
            ]
        )
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { ["note": 1] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [duplicateFinding] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.activeDuplicateInvariantCheck(limit: 10)

        #expect(report.command == "storage.active-duplicate-invariants")
        #expect(report.isMutating == false)
        #expect(report.status == "issues_found")
        #expect(report.summary["duplicateFindings"] == 1)
        #expect(report.summary["duplicateRelativePaths"] == 1)
        #expect(report.summary["sqliteMismatches"] == 1)
        #expect(report.duplicateFindings.first?.id == "duplicate-note-content-test")
        #expect(report.duplicateRelativePaths.first?.relativePath == "Inbox/Notes/CodexNote.md")
        #expect(report.duplicateRelativePaths.first?.items.map(\.id).contains(firstID.uuidString) == true)
        #expect(report.sqliteMismatches.first?.key == "note")
    }

    @Test("active duplicate invariant check reports vault SQLite path mismatches read-only")
    func activeDuplicateInvariantCheckReportsVaultSQLitePathMismatchesReadOnly() throws {
        let (db, url) = try makeTestDB()
        let vault = try makeTempVault()
        defer {
            cleanup(url)
            try? FileManager.default.removeItem(at: vault)
        }

        let trackedID = UUID()
        let missingID = UUID()
        try makeDirectories(["Notes", "Bookmarks"], under: vault)
        try insertFolder(db, id: UUID(), relativePath: "Bookmarks")
        try "tracked".write(
            to: vault.appendingPathComponent("Notes/Tracked.md"),
            atomically: true,
            encoding: .utf8
        )
        try "loose".write(
            to: vault.appendingPathComponent("Bookmarks/Loose.webloc"),
            atomically: true,
            encoding: .utf8
        )
        try insertItem(db, id: trackedID, type: "note", title: "Tracked", relativePath: "Notes/Tracked.md")
        try insertItem(db, id: missingID, type: "note", title: "Missing", relativePath: "Notes/Missing.md")

        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            modelCountsProvider: { ["folder": 1, "note": 2] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.activeDuplicateInvariantCheck(limit: 10)

        #expect(report.isMutating == false)
        #expect(report.status == "issues_found")
        #expect(report.summary["vaultSQLiteMismatches"] == 2)
        #expect(report.summary["totalIssues"] == 2)
        #expect(report.vaultSQLiteMismatches.contains {
            $0.kind == "sqlite_row_missing_vault_file"
                && $0.itemID == missingID.uuidString
                && $0.relativePath == "Notes/Missing.md"
        })
        #expect(report.vaultSQLiteMismatches.contains {
            $0.kind == "vault_file_missing_sqlite_row"
                && $0.relativePath == "Bookmarks/Loose.webloc"
        })
    }

    @Test("active duplicate invariant JSON exposes non-mutating status and duplicate paths")
    func activeDuplicateInvariantJSONExposesNonMutatingStatusAndDuplicatePaths() throws {
        let report = CiderActiveDuplicateInvariantReport(
            generatedAt: Date(timeIntervalSince1970: 12),
            status: "issues_found",
            summary: [
                "duplicateFindings": 0,
                "duplicateRelativePaths": 1,
                "sqliteMismatches": 0,
                "vaultSQLiteMismatches": 1,
                "totalIssues": 2,
            ],
            duplicateFindingLimit: 20,
            duplicateFindings: [],
            duplicateRelativePaths: [
                CiderDuplicateRelativePathFinding(
                    relativePath: "Inbox/Notes/CodexNote.md",
                    items: [CiderDuplicateRelativePathItem(id: "note-1", type: "note", title: "CodexNote")]
                )
            ],
            sqliteMismatches: [],
            vaultSQLiteMismatches: [
                CiderVaultSQLitePathMismatch(
                    kind: "sqlite_row_missing_vault_file",
                    itemID: "note-2",
                    itemType: "note",
                    title: "Missing",
                    relativePath: "Inbox/Notes/Missing.md",
                    detail: "SQLite item row points to a missing vault file."
                )
            ]
        )

        let dict = activeDuplicateInvariantReportToDict(report)
        let duplicatePaths = try #require(dict["duplicateRelativePaths"] as? [[String: Any]])
        let firstPath = try #require(duplicatePaths.first)
        let vaultSQLiteMismatches = try #require(dict["vaultSQLiteMismatches"] as? [[String: Any]])
        let firstMismatch = try #require(vaultSQLiteMismatches.first)

        #expect(dict["command"] as? String == "storage.active-duplicate-invariants")
        #expect(dict["isMutating"] as? Bool == false)
        #expect(dict["status"] as? String == "issues_found")
        #expect(firstPath["relativePath"] as? String == "Inbox/Notes/CodexNote.md")
        #expect(firstMismatch["kind"] as? String == "sqlite_row_missing_vault_file")
        #expect(firstMismatch["relativePath"] as? String == "Inbox/Notes/Missing.md")
    }

    @Test("restart duplicate regression loop snapshots and passes stable clean state")
    func restartDuplicateRegressionLoopSnapshotsAndPassesStableCleanState() throws {
        let (db, url) = try makeTestDB()
        let vault = try makeTempVault()
        defer {
            cleanup(url)
            try? FileManager.default.removeItem(at: vault)
        }

        try makeDirectories(["Notes"], under: vault)
        try "stable".write(
            to: vault.appendingPathComponent("Notes/Stable.md"),
            atomically: true,
            encoding: .utf8
        )
        try insertFolder(db, id: UUID(), relativePath: "Notes")
        try insertItem(db, id: UUID(), type: "note", title: "Stable", relativePath: "Notes/Stable.md")

        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            modelCountsProvider: itemCountsProvider(for: db),
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.restartRebuildDuplicateRegressionLoop(limit: 10, rebuildReconcile: {})

        #expect(report.command == "storage.restart-duplicate-regression")
        #expect(report.isMutating == true)
        #expect(report.status == "clean")
        #expect(report.passed == true)
        #expect(report.before.status == "clean")
        #expect(report.after.status == "clean")
        #expect(report.snapshotBefore.sqliteTableCounts["items"] == 1)
        #expect(report.snapshotAfter.sqliteTableCounts["items"] == 1)
        #expect(report.snapshotBefore.vaultArtifactCountsByExtension["md"] == 1)
        #expect(report.snapshotAfter.vaultArtifactCountsByExtension["md"] == 1)
        #expect(report.regression.newIssueFingerprints.isEmpty)
        #expect(report.regression.sqliteTableCountChanges.isEmpty)
    }

    @Test("restart duplicate regression loop fails when reconcile introduces duplicate rows")
    func restartDuplicateRegressionLoopFailsWhenReconcileIntroducesDuplicateRows() throws {
        let (db, url) = try makeTestDB()
        let vault = try makeTempVault()
        defer {
            cleanup(url)
            try? FileManager.default.removeItem(at: vault)
        }

        try makeDirectories(["Notes"], under: vault)
        try "duplicate".write(
            to: vault.appendingPathComponent("Notes/Duplicate.md"),
            atomically: true,
            encoding: .utf8
        )
        try insertFolder(db, id: UUID(), relativePath: "Notes")
        try insertItem(db, id: UUID(), type: "note", title: "Duplicate", relativePath: "Notes/Duplicate.md")

        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            modelCountsProvider: itemCountsProvider(for: db),
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.restartRebuildDuplicateRegressionLoop(limit: 10) {
            try db.runSQL("DROP INDEX IF EXISTS idx_items_path;")
            try insertItem(db, id: UUID(), type: "note", title: "Duplicate 2", relativePath: "Notes/Duplicate.md")
        }

        #expect(report.status == "regression_detected")
        #expect(report.passed == false)
        #expect(report.before.status == "clean")
        #expect(report.after.status == "issues_found")
        #expect(report.regression.beforeIssueCount == 0)
        #expect(report.regression.afterIssueCount == 1)
        #expect(report.regression.newIssueFingerprints.contains {
            $0.hasPrefix("duplicateRelativePath:Notes/Duplicate.md:")
        })
        #expect(report.snapshotBefore.duplicateRelativePathRowCount == 0)
        #expect(report.snapshotAfter.duplicateRelativePathRowCount == 1)
        #expect(report.regression.sqliteTableCountChanges["items"] == 1)
        #expect(report.regression.itemCountChangesByType["note"] == 1)

        let dict = restartDuplicateRegressionReportToDict(report)
        #expect(dict["command"] as? String == "storage.restart-duplicate-regression")
        #expect(dict["status"] as? String == "regression_detected")
        #expect(dict["passed"] as? Bool == false)
        let regression = try #require(dict["regression"] as? [String: Any])
        #expect(regression["afterIssueCount"] as? Int == 1)
        #expect((regression["newIssueFingerprints"] as? [String])?.isEmpty == false)
    }

    @Test("restart duplicate regression loop accepts project artifact rescan adoption")
    func restartDuplicateRegressionLoopAcceptsProjectArtifactRescanAdoption() throws {
        let (db, url) = try makeTestDB()
        let vault = try makeTempVault()
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let noteService = NotesStorage(database: db)
        let existing = Note(
            title: "Existing Note",
            content: "Already canonical.",
            relativePath: "Inbox/Notes/Existing Note.md"
        )
        let existingFileURL = vault.appendingPathComponent(existing.relativePath)
        try FileManager.default.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.content.write(to: existingFileURL, atomically: true, encoding: .utf8)
        noteService.persistNoteToDatabase(db, note: existing)
        noteService.loadNotesFromDatabase(db)

        let relativePath = "Projects/Cider/QA/External QA Audit.md"
        let fileURL = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# External QA Audit\n\nNew artifact from disk.\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            modelCountsProvider: { ["note": noteService.notes.count] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.restartRebuildDuplicateRegressionLoop(limit: 10) {
            noteService.rescan()
        }

        #expect(report.status == "clean")
        #expect(report.passed == true)
        #expect(report.regression.newIssueFingerprints.isEmpty)
        #expect(report.after.sqliteMismatches.isEmpty)
        #expect(report.snapshotAfter.itemCountsByType["note"] == 2)
    }

    private func insertContentChunk(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        title: String = "Recall Seed",
        body: String = "The searchable token is moonstone."
    ) throws {
        let now = DatabaseHelpers.encode(Date())
        let stmt = try db.prepare("""
            INSERT INTO content_chunks (
                id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, created_at, updated_at
            )
            VALUES (?, 'kanban_card', ?, 'test', ?, ?, 0, 'hash', ?, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(DatabaseHelpers.encode(UUID()), at: 2)
            .bind(title, at: 3)
            .bind(body, at: 4)
            .bind(now, at: 5)
            .bind(now, at: 6)
        try stmt.step()
    }

    private func insertSearchIndexDriftItem(
        _ db: CiderDatabase,
        id: UUID,
        type: String = "note",
        title: String = "Drifted note",
        updatedAt: Date = Date(timeIntervalSince1970: 200),
        chunkUpdatedAt: Date? = nil
    ) throws {
        let encodedUpdatedAt = DatabaseHelpers.encode(updatedAt)
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, NULL);
            """)
        itemStmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(encodedUpdatedAt, at: 4)
            .bind(encodedUpdatedAt, at: 5)
        try itemStmt.step()

        guard let chunkUpdatedAt else { return }
        let chunkStmt = try db.prepare("""
            INSERT INTO content_chunks (
                id, item_id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, metadata, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, 'item_index.test', ?, 'stale projection body',
                    0, 'stale-projection-hash', '{}', ?, ?);
            """)
        chunkStmt.bind(DatabaseHelpers.encode(UUID()), at: 1)
            .bind(DatabaseHelpers.encode(id), at: 2)
            .bind(type, at: 3)
            .bind(DatabaseHelpers.encode(id), at: 4)
            .bind(title, at: 5)
            .bind(DatabaseHelpers.encode(chunkUpdatedAt), at: 6)
            .bind(DatabaseHelpers.encode(chunkUpdatedAt), at: 7)
        try chunkStmt.step()
    }

    private func insertBookmarkDriftFixture(
        _ db: CiderDatabase,
        id: UUID,
        title: String = "GitHub - AndrewPrifer/liquid-dom",
        url: String = "https://github.com/AndrewPrifer/liquid-dom",
        relativePath: String = "Inbox/Bookmarks/Github.Com (2).webloc",
        chunkTitle: String = "Github.Com",
        chunkBody: String = "Title: Github.Com\nURL: https://github.com/AndrewPrifer/liquid-dom\nPath: Inbox/Bookmarks/Github.Com (2).webloc",
        notes: String = "",
        ocrText: String? = nil
    ) throws {
        let now = DatabaseHelpers.encode(Date(timeIntervalSince1970: 10))
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'bookmark', ?, ?, ?, NULL, ?);
            """)
        itemStmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(title, at: 2)
            .bind(now, at: 3)
            .bind(now, at: 4)
            .bind(relativePath, at: 5)
        try itemStmt.step()

        let bookmarkStmt = try db.prepare("""
            INSERT INTO bookmarks (item_id, url, notes, notes_manually_set, title_manually_set, ocr_text)
            VALUES (?, ?, ?, 0, 0, ?);
            """)
        bookmarkStmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(url, at: 2)
            .bind(notes, at: 3)
            .bind(ocrText, at: 4)
        try bookmarkStmt.step()

        let chunkStmt = try db.prepare("""
            INSERT INTO content_chunks (
                id, item_id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, metadata, created_at, updated_at
            )
            VALUES (?, ?, 'bookmark', ?, 'bookmark:item', ?, ?,
                    0, 'stale-hash', '{}', ?, ?);
            """)
        chunkStmt.bind(DatabaseHelpers.encode(UUID()), at: 1)
            .bind(DatabaseHelpers.encode(id), at: 2)
            .bind(DatabaseHelpers.encode(id), at: 3)
            .bind(chunkTitle, at: 4)
            .bind(chunkBody, at: 5)
            .bind(now, at: 6)
            .bind(now, at: 7)
        try chunkStmt.step()
    }

    private func firstBookmarkChunk(_ db: CiderDatabase, ownerID: UUID) throws -> (title: String, body: String) {
        let stmt = try db.prepare("""
            SELECT title, body
            FROM content_chunks
            WHERE owner_type = 'bookmark' AND owner_id = ?
            ORDER BY chunk_index ASC
            LIMIT 1;
            """)
        stmt.bind(DatabaseHelpers.encode(ownerID), at: 1)
        try #require(try stmt.step())
        return (stmt.string(at: 0), stmt.string(at: 1))
    }

    private func contentChunkFTSMatchCount(_ query: String, in db: CiderDatabase) throws -> Int {
        let stmt = try db.prepare("""
            SELECT COUNT(*)
            FROM content_chunks_fts
            WHERE content_chunks_fts MATCH ?;
            """)
        stmt.bind(query, at: 1)
        try stmt.step()
        return Int(stmt.int64(at: 0))
    }

    @Test("VaultDoctor reports and fixes untracked duplicate Markdown artifacts")
    func vaultDoctorReportsAndFixesUntrackedDuplicateMarkdownArtifacts() throws {
        let (db, url) = try makeTestDB()
        let fm = FileManager.default
        let vault = try makeTempVault()
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        try fm.createDirectory(at: vault.appendingPathComponent("Inbox/Notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: vault.appendingPathComponent("Projects/Cider"), withIntermediateDirectories: true)
        let canonical = vault.appendingPathComponent("Inbox/Notes/Canonical.md")
        let inboxCopy = vault.appendingPathComponent("Inbox/Notes/Canonical 2.md")
        let folderCopy = vault.appendingPathComponent("Projects/Cider/Canonical 3.md")
        try "same content".write(to: canonical, atomically: true, encoding: .utf8)
        try "same content".write(to: inboxCopy, atomically: true, encoding: .utf8)
        try "same content".write(to: folderCopy, atomically: true, encoding: .utf8)
        try "different content".write(
            to: vault.appendingPathComponent("Inbox/Notes/Untracked Unique.md"),
            atomically: true,
            encoding: .utf8
        )

        let note = Note(
            title: "Canonical",
            content: "same content",
            relativePath: "Inbox/Notes/Canonical.md"
        )
        NotesStorage(database: db).persistNoteToDatabase(db, note: note)

        let findings = VaultDoctor.shared.scanUntrackedDuplicateMarkdownArtifacts(
            vaultRoot: vault,
            database: db
        )

        #expect(findings.compactMap(\.payload.relativePath).sorted() == [
            "Inbox/Notes/Canonical 2.md",
            "Projects/Cider/Canonical 3.md",
        ])
        #expect(findings.allSatisfy { $0.kind == .untrackedDuplicateMarkdown })
        #expect(findings.allSatisfy { $0.isFixable })
        #expect(findings.allSatisfy { $0.fixLabel == "Remove untracked duplicate Markdown file" })
        #expect(findings.allSatisfy { $0.payload.relatedRelativePaths == ["Inbox/Notes/Canonical.md"] })

        let fixed = VaultDoctor.shared.fix(try #require(findings.first {
            $0.payload.relativePath == "Projects/Cider/Canonical 3.md"
        }))

        #expect(fixed)
        #expect(fm.fileExists(atPath: canonical.path))
        #expect(fm.fileExists(atPath: inboxCopy.path))
        #expect(!fm.fileExists(atPath: folderCopy.path))
    }

    @Test("storage audit compares model counts SQLite rows filesystem artifacts and finding groups")
    func storageAuditComparesCountsAndFindings() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-storage-audit-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vaultURL.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        try "alpha".write(to: vaultURL.appendingPathComponent("Notes/Alpha.md"), atomically: true, encoding: .utf8)
        try "url".write(to: vaultURL.appendingPathComponent("Example.webloc"), atomically: true, encoding: .utf8)
        try "ignore".write(to: vaultURL.appendingPathComponent(".cider/internal.md"), atomically: true, encoding: .utf8)

        let folderID = UUID()
        let folderStmt = try db.prepare("""
            INSERT INTO folders (id, relative_path, created_at, updated_at)
            VALUES (?, 'Notes', ?, ?);
            """)
        let now = DatabaseHelpers.encode(Date())
        folderStmt.bind(DatabaseHelpers.encode(folderID), at: 1)
            .bind(now, at: 2)
            .bind(now, at: 3)
        try folderStmt.step()

        let noteID = UUID()
        let itemStmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', 'Alpha', ?, ?, ?, 'Notes/Alpha.md');
            """)
        itemStmt.bind(DatabaseHelpers.encode(noteID), at: 1)
            .bind(now, at: 2)
            .bind(now, at: 3)
            .bind(DatabaseHelpers.encode(folderID), at: 4)
        try itemStmt.step()

        let doctorReport = VaultDoctor.Report(
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11),
            findings: [
                VaultDoctor.Finding(
                    id: "dup-folder",
                    kind: .suspiciousFlattenedFolderDuplicate,
                    severity: .warning,
                    summary: "Possible duplicate folder",
                    detail: "Folder A matches Folder B.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: VaultDoctor.Finding.Payload(relativePath: "A")
                )
            ]
        )
        let duplicate = VaultDuplicateAuditor.Finding(
            id: "dup-note",
            entityType: .note,
            kind: .exactContent,
            confidence: .exact,
            summary: "Exact duplicate note content",
            detail: "Two notes match.",
            items: []
        )

        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vaultURL,
            modelCountsProvider: {
                ["folder": 1, "note": 2, "bookmark": 0, "contact": 0, "todo": 0, "dateCard": 0, "vaultFile": 0]
            },
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [duplicate] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.audit()

        #expect(report.modelCounts["note"] == 2)
        #expect(report.sqliteCounts["note"] == 1)
        #expect(report.fileArtifactCounts["markdown"] == 1)
        #expect(report.fileArtifactCounts["webloc"] == 1)
        #expect(report.fileArtifactCounts["ciderInternal"] == nil)
        #expect(report.doctorFindingGroups["warning:suspiciousFlattenedFolderDuplicate"] == 1)
        #expect(report.duplicateFindingGroups["note:exactContent"] == 1)
        #expect(report.mismatches.contains {
            $0.key == "note" && $0.modelCount == 2 && $0.sqliteCount == 1
        })
    }

    @Test("storage audit reports missing and stale item search projections")
    func storageAuditReportsMissingAndStaleItemSearchProjections() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        let missingID = UUID()
        let staleID = UUID()
        try insertSearchIndexDriftItem(db, id: missingID, title: "Missing chunks")
        try insertSearchIndexDriftItem(
            db,
            id: staleID,
            title: "Stale chunks",
            updatedAt: Date(timeIntervalSince1970: 300),
            chunkUpdatedAt: Date(timeIntervalSince1970: 100)
        )

        let service = CiderStorageAuditService(
            database: db,
            modelCountsProvider: { [:] },
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] }
        )
        let report = try service.audit()

        #expect(report.searchIndexDriftFindings.map(\.itemID).contains(missingID.uuidString))
        #expect(report.searchIndexDriftFindings.map(\.itemID).contains(staleID.uuidString))
        let missing = try #require(report.searchIndexDriftFindings.first { $0.itemID == missingID.uuidString })
        let stale = try #require(report.searchIndexDriftFindings.first { $0.itemID == staleID.uuidString })
        #expect(missing.kind == "missing_content_chunks")
        #expect(missing.chunkUpdatedAt == nil)
        #expect(missing.safeRepairCommand == "cider-cli item rebuild-chunks note \(missingID.uuidString) --json")
        #expect(stale.kind == "stale_content_chunks")
        #expect(stale.chunkUpdatedAt != nil)
    }

    @Test("storage audit JSON exposes compact groups and mismatches")
    func storageAuditJSONExposesCompactGroupsAndMismatches() throws {
        let report = CiderStorageAuditReport(
            generatedAt: Date(timeIntervalSince1970: 12),
            modelCounts: ["note": 2],
            sqliteCounts: ["note": 1],
            fileArtifactCounts: ["markdown": 1],
            doctorFindingGroups: ["warning:duplicateNoteContent": 1],
            duplicateFindingGroups: ["note:exactContent": 1],
            totalDoctorFindings: 1,
            fixableDoctorFindings: 0,
            schemaFindings: [
                CiderStorageAuditSchemaFinding(
                    id: "missing_expected_table:routing_decisions",
                    severity: "error",
                    affectedTable: "routing_decisions",
                    summary: "Missing expected second-brain table routing_decisions.",
                    detail: "The routing_decisions table is required for explainable capture routing and review queues.",
                    nextSafeAction: "Run cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json to create the missing table and indexes, then rerun storage audit.",
                    isRepairable: true,
                    repairCommand: "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
                )
            ],
            mismatches: [
                CiderStorageAuditMismatch(
                    key: "note",
                    modelCount: 2,
                    sqliteCount: 1,
                    detail: "Model count for note is 2 but SQLite items has 1."
                )
            ]
        )

        let dict = storageAuditReportToDict(report)

        #expect(dict["totalDoctorFindings"] as? Int == 1)
        let mismatches = try #require(dict["mismatches"] as? [[String: Any]])
        #expect(mismatches.contains {
            $0["key"] as? String == "note" &&
            $0["modelCount"] as? Int == 2 &&
            $0["sqliteCount"] as? Int == 1
        })
        let schemaFindings = try #require(dict["schemaFindings"] as? [[String: Any]])
        #expect(schemaFindings.contains {
            $0["id"] as? String == "missing_expected_table:routing_decisions" &&
            $0["severity"] as? String == "error" &&
            $0["affectedTable"] as? String == "routing_decisions" &&
            $0["nextSafeAction"] as? String != nil &&
            $0["isRepairable"] as? Bool == true &&
            $0["repairCommand"] as? String == "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
        })
        let doctorGroups = try #require(dict["doctorFindingGroups"] as? [String: Int])
        #expect(doctorGroups["warning:duplicateNoteContent"] == 1)
    }

    @Test("storage audit JSON exposes search index drift repair commands")
    func storageAuditJSONExposesSearchIndexDriftRepairCommands() throws {
        let itemID = UUID()
        let report = CiderStorageAuditReport(
            generatedAt: Date(timeIntervalSince1970: 12),
            modelCounts: [:],
            sqliteCounts: [:],
            fileArtifactCounts: [:],
            doctorFindingGroups: [:],
            duplicateFindingGroups: [:],
            totalDoctorFindings: 0,
            fixableDoctorFindings: 0,
            schemaFindings: [],
            searchIndexDriftFindings: [
                CiderSearchIndexDriftFinding(
                    id: "search-index-drift:note:\(itemID.uuidString)",
                    kind: "missing_content_chunks",
                    severity: "warning",
                    itemType: "note",
                    itemID: itemID.uuidString,
                    title: "Missing chunks",
                    updatedAt: Date(timeIntervalSince1970: 200),
                    chunkUpdatedAt: nil,
                    chunkCount: 0,
                    safeRepairCommand: "cider-cli item rebuild-chunks note \(itemID.uuidString) --json"
                )
            ],
            mismatches: []
        )
        let dict = storageAuditReportToDict(report)
        let findings = try #require(dict["searchIndexDriftFindings"] as? [[String: Any]])
        let first = try #require(findings.first)

        #expect(first["kind"] as? String == "missing_content_chunks")
        #expect(first["safeRepairCommand"] as? String == "cider-cli item rebuild-chunks note \(itemID.uuidString) --json")
    }

    @Test("storage audit JSON exposes actionable doctor finding samples")
    func storageAuditJSONExposesActionableDoctorFindingSamples() throws {
        let doctorReport = VaultDoctor.Report(
            startedAt: Date(timeIntervalSince1970: 11),
            finishedAt: Date(timeIntervalSince1970: 12),
            findings: [
                VaultDoctor.Finding(
                    id: "flattened-folder-root-games",
                    kind: .suspiciousFlattenedFolderDuplicate,
                    severity: .warning,
                    summary: "Possible flattened folder duplicate: Games",
                    detail: "Root folder 'Games' has the same normalized name as nested folder path(s): Media/Games. This can happen when sync receives a child folder before its parent and must be reviewed before merging or deleting files.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: VaultDoctor.Finding.Payload(
                        relativePath: "Games",
                        relatedRelativePaths: ["Media/Games"]
                    )
                )
            ]
        )
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let service = CiderStorageAuditService(
            database: db,
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let dict = try storageAuditReportToDict(service.audit())

        #expect(dict["doctorFindingSampleLimit"] as? Int == 20)
        let samples = try #require(dict["doctorFindingSamples"] as? [[String: Any]])
        let sample = try #require(samples.first)
        #expect(sample["id"] as? String == "flattened-folder-root-games")
        #expect(sample["kind"] as? String == "suspiciousFlattenedFolderDuplicate")
        #expect(sample["severity"] as? String == "warning")
        #expect(sample["relativePath"] as? String == "Games")
        #expect(sample["relatedRelativePaths"] as? [String] == ["Media/Games"])
        #expect(sample["isFixable"] as? Bool == false)
        #expect((sample["detail"] as? String)?.contains("Media/Games") == true)
        #expect((sample["nextSafeAction"] as? String)?.contains("manual") == true)
    }

    @Test("storage doctor dry-run plan exposes non-mutating flattened duplicate remediation")
    func storageDoctorDryRunPlanExposesNonMutatingFlattenedDuplicateRemediation() throws {
        let doctorReport = VaultDoctor.Report(
            startedAt: Date(timeIntervalSince1970: 11),
            finishedAt: Date(timeIntervalSince1970: 12),
            findings: [
                VaultDoctor.Finding(
                    id: "flattened-folder-root-games",
                    kind: .suspiciousFlattenedFolderDuplicate,
                    severity: .warning,
                    summary: "Possible flattened folder duplicate: Games",
                    detail: "Root folder 'Games' has the same normalized name as nested folder path(s): Media/Games.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: VaultDoctor.Finding.Payload(
                        relativePath: "Games",
                        relatedRelativePaths: ["Media 2/Games", "Media/Games"]
                    )
                ),
                VaultDoctor.Finding(
                    id: "duplicate-bookmark-url",
                    kind: .duplicateBookmarkURL,
                    severity: .warning,
                    summary: "Duplicate bookmark URL",
                    detail: "Duplicate bookmark URL.",
                    isFixable: false,
                    fixLabel: nil,
                    payload: VaultDoctor.Finding.Payload(relativePath: "Bookmarks/Dupe")
                )
            ]
        )
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let service = CiderStorageAuditService(
            database: db,
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let dict = storageDoctorRemediationPlanReportToDict(service.doctorRemediationPlan(limit: 10))

        #expect(dict["command"] as? String == "storage.doctor.plan")
        #expect(dict["isMutating"] as? Bool == false)
        #expect(dict["approvalRequired"] as? Bool == true)
        #expect(dict["planLimit"] as? Int == 10)
        let plans = try #require(dict["plans"] as? [[String: Any]])
        #expect(plans.count == 1)
        let plan = try #require(plans.first)
        #expect(plan["findingID"] as? String == "flattened-folder-root-games")
        #expect(plan["kind"] as? String == "suspiciousFlattenedFolderDuplicate")
        #expect(plan["proposedAction"] as? String == "manual_merge_review")
        #expect(plan["candidateCanonicalRelativePath"] as? String == "Media/Games")
        #expect(plan["duplicateRelativePaths"] as? [String] == ["Games", "Media 2/Games"])
        #expect(plan["affectedRelativePaths"] as? [String] == ["Games", "Media 2/Games", "Media/Games"])
        #expect(plan["isMutating"] as? Bool == false)
        #expect(plan["approvalRequired"] as? Bool == true)
        #expect(plan["approvalCommand"] as? String == nil)
        let blockers = try #require(plan["blockers"] as? [String])
        #expect(blockers.contains { $0.contains("manual approval") })
    }

    @Test("storage doctor approved remediation refuses without exact approval")
    func storageDoctorApprovedRemediationRefusesWithoutExactApproval() throws {
        let folderID = UUID()
        let doctorReport = flattenedFolderDoctorReport(folderID: folderID)
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Games", "Media/Games"], under: vault)
        try insertFolder(db, id: folderID, relativePath: "Games")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let result = service.applyDoctorRemediation(
            findingID: "flattened-folder-root-games",
            canonicalRelativePath: "Media/Games",
            duplicateRelativePath: "Games",
            approvalToken: nil,
            execute: true
        )

        #expect(result.status == "refused")
        #expect(result.isMutating == false)
        #expect(result.requiredApprovalToken == "flattened-folder-root-games:Games=>Media/Games")
        #expect(result.blockers.contains { $0.contains("exact approval") })
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Games").path))
        #expect(try folderExists(db, relativePath: "Games"))
    }

    @Test("storage doctor approved remediation moves empty duplicate to trash and records audit")
    func storageDoctorApprovedRemediationMovesEmptyDuplicateToTrashAndRecordsAudit() throws {
        let folderID = UUID()
        let doctorReport = flattenedFolderDoctorReport(folderID: folderID)
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Games", "Media/Games"], under: vault)
        try insertFolder(db, id: folderID, relativePath: "Games")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let result = service.applyDoctorRemediation(
            findingID: "flattened-folder-root-games",
            canonicalRelativePath: "Media/Games",
            duplicateRelativePath: "Games",
            approvalToken: "flattened-folder-root-games:Games=>Media/Games",
            execute: true
        )

        #expect(result.status == "applied")
        #expect(result.isMutating == true)
        #expect(result.appliedActions == ["move_duplicate_to_storage_doctor_trash", "delete_duplicate_folder_row", "record_mutation_audit"])
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Games").path) == false)
        let trashPath = try #require(result.trashRelativePath)
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(trashPath).path))
        #expect(try folderExists(db, relativePath: "Games") == false)
        let audit = MutationAuditService(database: db).loadEntries().first
        #expect(audit?.action == "storage.doctor.apply")
        #expect(audit?.source == .cleanup)
        #expect(audit?.metadata["findingID"] == "flattened-folder-root-games")
    }

    @Test("storage doctor apply JSON exposes approval mutation and audit state")
    func storageDoctorApplyJSONExposesApprovalMutationAndAuditState() {
        let report = CiderStorageDoctorRemediationApplyReport(
            generatedAt: Date(timeIntervalSince1970: 12),
            findingID: "flattened-folder-root-games",
            status: "planned",
            isMutating: false,
            requiredApprovalToken: "flattened-folder-root-games:Games=>Media/Games",
            canonicalRelativePath: "Media/Games",
            duplicateRelativePath: "Games",
            plannedActions: ["move_duplicate_to_storage_doctor_trash"],
            appliedActions: [],
            blockers: ["dry-run only"],
            trashRelativePath: ".cider/storage-doctor-trash/flattened-folder-root-games-12/Games",
            auditRecorded: false
        )

        let dict = storageDoctorRemediationApplyReportToDict(report)

        #expect(dict["command"] as? String == "storage.doctor.apply")
        #expect(dict["findingID"] as? String == "flattened-folder-root-games")
        #expect(dict["status"] as? String == "planned")
        #expect(dict["isMutating"] as? Bool == false)
        #expect(dict["approvalRequired"] as? Bool == true)
        #expect(dict["requiredApprovalToken"] as? String == "flattened-folder-root-games:Games=>Media/Games")
        #expect(dict["canonicalRelativePath"] as? String == "Media/Games")
        #expect(dict["duplicateRelativePath"] as? String == "Games")
        #expect(dict["plannedActions"] as? [String] == ["move_duplicate_to_storage_doctor_trash"])
        #expect(dict["blockers"] as? [String] == ["dry-run only"])
        #expect(dict["trashRelativePath"] as? String == ".cider/storage-doctor-trash/flattened-folder-root-games-12/Games")
        #expect(dict["auditRecorded"] as? Bool == false)
    }

    @Test("storage doctor approved remediation refuses non-empty duplicate folders")
    func storageDoctorApprovedRemediationRefusesNonEmptyDuplicateFolders() throws {
        let folderID = UUID()
        let doctorReport = flattenedFolderDoctorReport(folderID: folderID)
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Games", "Media/Games"], under: vault)
        try "important".write(to: vault.appendingPathComponent("Games/save.txt"), atomically: true, encoding: .utf8)
        try insertFolder(db, id: folderID, relativePath: "Games")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { doctorReport },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let result = service.applyDoctorRemediation(
            findingID: "flattened-folder-root-games",
            canonicalRelativePath: "Media/Games",
            duplicateRelativePath: "Games",
            approvalToken: "flattened-folder-root-games:Games=>Media/Games",
            execute: true
        )

        #expect(result.status == "refused")
        #expect(result.blockers.contains { $0.contains("non-empty") })
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Games/save.txt").path))
        #expect(try folderExists(db, relativePath: "Games"))
    }

    @Test("bookmark drift audit detects rich title with stale webloc path and chunks")
    func bookmarkDriftAuditDetectsRichTitleWithStaleWeblocPathAndChunks() throws {
        let bookmarkID = UUID(uuidString: "DE38FB8B-4910-489D-8DCD-C07C6DAACA6A")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        _ = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Github.Com",
                urlString: "https://github.com/example/existing"
            ),
            toDirectory: vault.appendingPathComponent("Inbox/Bookmarks"),
            dirRelativePath: "Inbox/Bookmarks"
        )
        try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                id: bookmarkID,
                title: "Github.Com",
                urlString: "https://github.com/AndrewPrifer/liquid-dom"
            ),
            toDirectory: vault.appendingPathComponent("Inbox/Bookmarks"),
            dirRelativePath: "Inbox/Bookmarks"
        )
        try insertBookmarkDriftFixture(db, id: bookmarkID)
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.bookmarkDriftAudit(limit: 10)

        #expect(report.command == "storage.bookmark-drift.audit")
        #expect(report.isMutating == false)
        #expect(report.findings.count == 1)
        let finding = try #require(report.findings.first)
        #expect(finding.itemID == bookmarkID.uuidString)
        #expect(finding.kind == "bookmark_title_path_drift")
        #expect(finding.currentTitle == "GitHub - AndrewPrifer/liquid-dom")
        #expect(finding.currentRelativePath == "Inbox/Bookmarks/Github.Com (2).webloc")
        #expect(finding.proposedRelativePath == "Inbox/Bookmarks/GitHub - AndrewPrifer-liquid-dom.webloc")
        #expect(finding.pathDrift == true)
        #expect(finding.chunkDrift == true)
        #expect(finding.repairCommand.contains("--execute"))
        #expect(finding.repairCommand.contains(bookmarkID.uuidString))
    }

    @Test("bookmark drift audit ignores host-only titles that would only add duplicate suffixes")
    func bookmarkDriftAuditIgnoresHostOnlyTitles() throws {
        let bookmarkID = UUID(uuidString: "EDE7C93D-4B82-4820-BB2B-C01D67DCCEB4")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        try "url".write(
            to: vault.appendingPathComponent("Inbox/Bookmarks/X.Com (3).webloc"),
            atomically: true,
            encoding: .utf8
        )
        try insertBookmarkDriftFixture(
            db,
            id: bookmarkID,
            title: "X.Com (3)",
            url: "https://x.com/example/status/123",
            relativePath: "Inbox/Bookmarks/X.Com (3).webloc",
            chunkTitle: "X.Com (3)",
            chunkBody: "Title: X.Com (3)"
        )
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.bookmarkDriftAudit(limit: 10)

        #expect(report.findings.isEmpty)
    }

    @Test("bookmark drift audit proposes stored TikTok semantic title when current title is provider generic")
    func bookmarkDriftAuditProposesStoredTikTokSemanticTitleWhenCurrentTitleIsProviderGeneric() throws {
        let bookmarkID = UUID(uuidString: "57AAC094-0804-4FEC-B009-5CA9C32B99EC")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        try "url".write(
            to: vault.appendingPathComponent("Inbox/Bookmarks/Tiktok.Com (2).webloc"),
            atomically: true,
            encoding: .utf8
        )
        try insertBookmarkDriftFixture(
            db,
            id: bookmarkID,
            title: "TikTok - Make Your Day",
            url: "https://www.tiktok.com/t/ZP8pWRSvc/",
            relativePath: "Inbox/Bookmarks/Tiktok.Com (2).webloc",
            chunkTitle: "Tiktok.Com",
            chunkBody: "Title: Tiktok.Com\nURL: https://www.tiktok.com/t/ZP8pWRSvc/\nPath: Inbox/Bookmarks/Tiktok.Com (2).webloc",
            notes: """
            And it's FREE! Welcome to Seattle SummerMaxing Part 1 - Details Below! #seattle #seattleWashington
            So you want to river tube? Here's all you need to know!
            By George M
            Via TikTok
            """,
            ocrText: "Seattle Summermaxing Part 1 did you know that you can do this in Seattle?"
        )
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.bookmarkDriftAudit(limit: 10)

        let finding = try #require(report.findings.first)
        #expect(finding.itemID == bookmarkID.uuidString)
        #expect(finding.currentTitle == "TikTok - Make Your Day")
        #expect(finding.proposedTitle == "Seattle Summermaxing Part 1")
        #expect(finding.proposedRelativePath == "Inbox/Bookmarks/Seattle Summermaxing Part 1.webloc")
        #expect(finding.pathDrift == true)
        #expect(finding.chunkDrift == true)
        #expect(finding.reasons.contains("stored TikTok metadata has a richer semantic title than the provider-generic title"))

        let repair = try service.repairBookmarkDrift(
            itemID: bookmarkID.uuidString,
            approvalToken: finding.approvalToken,
            execute: true
        )

        #expect(repair.status == "applied")
        #expect(repair.proposedTitle == "Seattle Summermaxing Part 1")
        #expect(repair.proposedRelativePath == "Inbox/Bookmarks/Seattle Summermaxing Part 1.webloc")
        #expect(repair.appliedActions.contains("update_bookmark_title"))
        #expect(repair.appliedActions.contains("update_bookmark_relative_path"))
        #expect(repair.appliedActions.contains("rebuild_bookmark_content_chunks"))

        let itemStmt = try db.prepare("SELECT title, relative_path FROM items WHERE id = ?;")
        itemStmt.bind(DatabaseHelpers.encode(bookmarkID), at: 1)
        try #require(try itemStmt.step())
        #expect(itemStmt.string(at: 0) == "Seattle Summermaxing Part 1")
        #expect(itemStmt.string(at: 1) == "Inbox/Bookmarks/Seattle Summermaxing Part 1.webloc")

        let chunk = try firstBookmarkChunk(db, ownerID: bookmarkID)
        #expect(chunk.title == "Seattle Summermaxing Part 1")
        #expect(chunk.body.contains("Path: Inbox/Bookmarks/Seattle Summermaxing Part 1.webloc"))
        #expect(!chunk.body.contains("Tiktok.Com"))
    }

    @Test("bookmark drift audit treats canonically equivalent accented filenames as current")
    func bookmarkDriftAuditTreatsEquivalentAccentedFilenamesAsCurrent() throws {
        let bookmarkID = UUID(uuidString: "1FBFD0AE-3A73-42FF-AC69-0681E6B4F522")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        let title = "Erick: Claude ya no se rinde ante Cloudflare… ahora lo destroza sin pagar NI UNA API. Antes le decías scrapeame esto"
        let decomposedRelativePath = "Inbox/Bookmarks/Erick- Claude ya no se rinde ante Cloudflare… ahora lo destroza sin pagar NI UNA API. Antes le deci\u{0301}as scrapeame esto.webloc"
        try "url".write(
            to: vault.appendingPathComponent(decomposedRelativePath),
            atomically: true,
            encoding: .utf8
        )
        try insertBookmarkDriftFixture(
            db,
            id: bookmarkID,
            title: title,
            url: "https://x.com/example/status/456",
            relativePath: decomposedRelativePath,
            chunkTitle: title,
            chunkBody: "Title: \(title)"
        )
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.bookmarkDriftAudit(limit: 10)

        #expect(report.findings.isEmpty)
    }

    @Test("bookmark drift repair aligns multiline X titles to single-line paths and chunks")
    func bookmarkDriftRepairAlignsMultilineXTitlesToSingleLinePathsAndChunks() throws {
        let bookmarkID = UUID(uuidString: "A78E6726-4D04-4AE9-80D3-E1F4D4AB4DC7")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        let staleRelativePath = "Inbox/Bookmarks/X.Com (8).webloc"
        try "url".write(
            to: vault.appendingPathComponent(staleRelativePath),
            atomically: true,
            encoding: .utf8
        )
        let promotedTitle = """
        IGN: Get your first look at Hands Over,
        a multiplayer horror party game where you'll be playing your favorite childhood game
        """
        try insertBookmarkDriftFixture(
            db,
            id: bookmarkID,
            title: promotedTitle,
            url: "https://x.com/ign/status/2059500091849994699?s=12",
            relativePath: staleRelativePath,
            chunkTitle: promotedTitle,
            chunkBody: "Title: \(promotedTitle)\nURL: https://x.com/ign/status/2059500091849994699?s=12\nPath: \(staleRelativePath)"
        )
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let audit = try service.bookmarkDriftAudit(limit: 10)
        let finding = try #require(audit.findings.first)
        #expect(finding.currentRelativePath == staleRelativePath)
        #expect(finding.proposedTitle == promotedTitle)
        #expect(finding.proposedRelativePath == "Inbox/Bookmarks/IGN- Get your first look at Hands Over, a multiplayer horror party game where you'll be playing your favorite childhood game.webloc")
        #expect(!finding.proposedRelativePath.contains("\n"))
        #expect(finding.pathDrift == true)
        #expect(finding.chunkDrift == true)

        let repair = try service.repairBookmarkDrift(
            itemID: bookmarkID.uuidString,
            approvalToken: finding.approvalToken,
            execute: true
        )

        #expect(repair.status == "applied")
        #expect(repair.proposedRelativePath == "Inbox/Bookmarks/IGN- Get your first look at Hands Over, a multiplayer horror party game where you'll be playing your favorite childhood game.webloc")
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(repair.proposedRelativePath).path))
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent(staleRelativePath).path))

        let chunk = try firstBookmarkChunk(db, ownerID: bookmarkID)
        #expect(chunk.title == promotedTitle)
        #expect(chunk.body.contains("Path: \(repair.proposedRelativePath)"))
        #expect(!chunk.body.contains(staleRelativePath))
    }

    @Test("bookmark drift repair refuses without approval and repairs path and chunks with approval")
    func bookmarkDriftRepairRefusesWithoutApprovalAndRepairsPathAndChunksWithApproval() throws {
        let bookmarkID = UUID(uuidString: "DE38FB8B-4910-489D-8DCD-C07C6DAACA6A")!
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try makeDirectories(["Inbox/Bookmarks"], under: vault)
        _ = try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                title: "Github.Com",
                urlString: "https://github.com/example/existing"
            ),
            toDirectory: vault.appendingPathComponent("Inbox/Bookmarks"),
            dirRelativePath: "Inbox/Bookmarks"
        )
        try BookmarkFileService.shared.write(
            bookmark: Bookmark(
                id: bookmarkID,
                title: "Github.Com",
                urlString: "https://github.com/AndrewPrifer/liquid-dom"
            ),
            toDirectory: vault.appendingPathComponent("Inbox/Bookmarks"),
            dirRelativePath: "Inbox/Bookmarks"
        )
        try insertBookmarkDriftFixture(db, id: bookmarkID)
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: vault,
            doctorReportProvider: { VaultDoctor.Report(startedAt: Date(), finishedAt: Date(), findings: []) },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let refused = try service.repairBookmarkDrift(
            itemID: bookmarkID.uuidString,
            approvalToken: nil,
            execute: true
        )
        #expect(refused.status == "refused")
        #expect(refused.isMutating == false)
        #expect(refused.blockers.contains { $0.contains("exact approval") })

        let audit = try service.bookmarkDriftAudit(limit: 10)
        let token = try #require(audit.findings.first?.approvalToken)
        let repair = try service.repairBookmarkDrift(
            itemID: bookmarkID.uuidString,
            approvalToken: token,
            execute: true
        )

        #expect(repair.status == "applied")
        #expect(repair.isMutating == true)
        #expect(repair.appliedActions.contains("rename_webloc_artifact"))
        #expect(repair.appliedActions.contains("update_bookmark_relative_path"))
        #expect(repair.appliedActions.contains("rebuild_bookmark_content_chunks"))
        #expect(repair.auditRecorded == true)
        #expect(repair.proposedRelativePath == "Inbox/Bookmarks/GitHub - AndrewPrifer-liquid-dom.webloc")
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent(repair.proposedRelativePath).path))
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("Inbox/Bookmarks/Github.Com (2).webloc").path))

        let pathStmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        pathStmt.bind(DatabaseHelpers.encode(bookmarkID), at: 1)
        try #require(try pathStmt.step())
        #expect(pathStmt.string(at: 0) == "Inbox/Bookmarks/GitHub - AndrewPrifer-liquid-dom.webloc")

        let chunk = try firstBookmarkChunk(db, ownerID: bookmarkID)
        #expect(chunk.title == "GitHub - AndrewPrifer/liquid-dom")
        #expect(chunk.body.contains("Path: Inbox/Bookmarks/GitHub - AndrewPrifer-liquid-dom.webloc"))
        #expect(!chunk.body.contains("Path: Inbox/Bookmarks/Github.Com (2).webloc"))
    }

    @Test("storage audit repair JSON exposes approval gated mutation metadata")
    func storageAuditRepairJSONExposesRepairState() throws {
        let report = CiderStorageAuditSchemaRepairReport(
            generatedAt: Date(timeIntervalSince1970: 12),
            status: "applied",
            isMutating: true,
            requiredApprovalToken: "REPAIR_SCHEMA",
            plannedActions: ["repair_schema:missing_expected_table:second_brain_routing_decisions"],
            appliedActions: ["repair_schema:missing_expected_table:second_brain_routing_decisions"],
            blockers: [],
            repairedFindingIDs: ["missing_expected_table:second_brain_routing_decisions"],
            skippedFindingIDs: ["missing_expected_column:routing_decisions:item_type"],
            remainingFindings: [
                CiderStorageAuditSchemaFinding(
                    id: "missing_expected_column:routing_decisions:item_type",
                    severity: "error",
                    affectedTable: "routing_decisions",
                    summary: "Missing expected column routing_decisions.item_type.",
                    detail: "The routing_decisions table is required for explainable capture routing and review queues.",
                    nextSafeAction: "Create a targeted migration or schema repair for this table; do not rely on startup migrations if schema_version is already current."
                )
            ]
        )

        let dict = storageAuditSchemaRepairReportToDict(report)

        #expect(dict["command"] as? String == "storage.repair-schema")
        #expect(dict["status"] as? String == "applied")
        #expect(dict["isMutating"] as? Bool == true)
        #expect(dict["approvalRequired"] as? Bool == true)
        #expect(dict["requiredApprovalToken"] as? String == "REPAIR_SCHEMA")
        #expect(dict["plannedActions"] as? [String] == ["repair_schema:missing_expected_table:second_brain_routing_decisions"])
        #expect(dict["appliedActions"] as? [String] == ["repair_schema:missing_expected_table:second_brain_routing_decisions"])
        #expect(dict["blockers"] as? [String] == [])
        #expect(dict["repairedFindingIDs"] as? [String] == ["missing_expected_table:second_brain_routing_decisions"])
        #expect(dict["skippedFindingIDs"] as? [String] == ["missing_expected_column:routing_decisions:item_type"])
        let remainingFindings = try #require(dict["remainingFindings"] as? [[String: Any]])
        #expect(remainingFindings.contains {
            $0["id"] as? String == "missing_expected_column:routing_decisions:item_type" &&
            $0["isRepairable"] as? Bool == false &&
            $0["repairCommand"] == nil
        })
    }

    @Test("storage audit flags missing second brain routing table")
    func storageAuditFlagsMissingSecondBrainRoutingTable() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE routing_decisions;")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { [:] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.audit()

        let missingRoutingTableFinding = report.schemaFindings.contains { finding in
            finding.id == "missing_expected_table:routing_decisions" &&
            finding.severity == "error" &&
            finding.affectedTable == "routing_decisions" &&
            finding.isRepairable &&
            finding.repairCommand == "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
        }
        #expect(missingRoutingTableFinding)
    }

    @Test("storage audit schema repair plans by default and refuses execution without approval")
    func storageAuditSchemaRepairPlansByDefaultAndRequiresApproval() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE second_brain_routing_decisions;")
        let service = makeStorageAuditService(db: db)

        let plan = try service.repairSchemaFindings()

        #expect(plan.status == "planned")
        #expect(plan.isMutating == false)
        #expect(plan.requiredApprovalToken == "REPAIR_SCHEMA")
        #expect(plan.plannedActions == ["repair_schema:missing_expected_table:second_brain_routing_decisions"])
        #expect(plan.appliedActions.isEmpty)
        #expect(plan.repairedFindingIDs.isEmpty)
        #expect(plan.remainingFindings.contains { $0.id == "missing_expected_table:second_brain_routing_decisions" })
        #expect(!(try sqliteObjectExists("second_brain_routing_decisions", type: "table", in: db)))

        let refused = try service.repairSchemaFindings(approvalToken: nil, execute: true)

        #expect(refused.status == "refused")
        #expect(refused.isMutating == false)
        #expect(refused.blockers.contains { $0.contains("exact approval") })
        #expect(!(try sqliteObjectExists("second_brain_routing_decisions", type: "table", in: db)))
    }

    @Test("storage audit schema repair executes only with exact approval and execute")
    func storageAuditSchemaRepairExecutesOnlyWithExactApproval() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE second_brain_routing_decisions;")
        let service = makeStorageAuditService(db: db)

        let repair = try service.repairSchemaFindings(
            approvalToken: "REPAIR_SCHEMA",
            execute: true
        )

        #expect(repair.status == "applied")
        #expect(repair.isMutating == true)
        #expect(repair.repairedFindingIDs == ["missing_expected_table:second_brain_routing_decisions"])
        #expect(repair.appliedActions == ["repair_schema:missing_expected_table:second_brain_routing_decisions"])
        #expect(repair.blockers.isEmpty)
        #expect(repair.remainingFindings.isEmpty)
        #expect(try sqliteObjectExists("second_brain_routing_decisions", type: "table", in: db))
    }

    @Test("storage audit repairs missing expected second brain table")
    func storageAuditRepairsMissingExpectedSecondBrainTable() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE second_brain_routing_decisions;")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { [:] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let beforeRepair = try service.audit()
        let missingSecondBrainRoutingTableFinding = beforeRepair.schemaFindings.contains { finding in
            finding.id == "missing_expected_table:second_brain_routing_decisions" &&
            finding.isRepairable
        }
        #expect(missingSecondBrainRoutingTableFinding)

        let repair = try service.repairSchemaFindings(approvalToken: "REPAIR_SCHEMA", execute: true)

        #expect(repair.repairedFindingIDs.contains("missing_expected_table:second_brain_routing_decisions"))
        #expect(repair.remainingFindings.isEmpty)
        let afterRepair = try service.audit()
        #expect(afterRepair.schemaFindings.isEmpty)
    }

    @Test("storage audit repairs missing capture attachments table")
    func storageAuditRepairsMissingCaptureAttachmentsTable() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE capture_attachments;")
        let service = makeStorageAuditService(db: db)

        let beforeRepair = try service.audit()
        #expect(beforeRepair.schemaFindings.contains { finding in
            finding.id == "missing_expected_table:capture_attachments"
                && finding.isRepairable
                && finding.repairCommand == "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
        })

        let repair = try service.repairSchemaFindings(approvalToken: "REPAIR_SCHEMA", execute: true)

        #expect(repair.repairedFindingIDs.contains("missing_expected_table:capture_attachments"))
        #expect(repair.remainingFindings.isEmpty)
        #expect(try sqliteObjectExists("capture_attachments", type: "table", in: db))
        #expect(try sqliteObjectExists("idx_capture_attachments_event", type: "index", in: db))
    }

    @Test("storage audit repair restores content chunk FTS artifacts")
    func storageAuditRepairRestoresContentChunkFTSArtifacts() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ai;")
        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ad;")
        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_au;")
        try db.runSQL("DROP TABLE IF EXISTS content_chunks_fts;")
        try db.runSQL("DROP TABLE content_chunks;")
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { [:] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let beforeRepair = try service.audit()
        let missingContentChunksFinding = beforeRepair.schemaFindings.contains { finding in
            finding.id == "missing_expected_table:content_chunks" &&
            finding.isRepairable
        }
        #expect(missingContentChunksFinding)

        let repair = try service.repairSchemaFindings(approvalToken: "REPAIR_SCHEMA", execute: true)

        #expect(repair.repairedFindingIDs.contains("missing_expected_table:content_chunks"))
        #expect(try sqliteObjectExists("content_chunks", type: "table", in: db))
        #expect(try sqliteObjectExists("content_chunks_fts", type: "table", in: db))
        #expect(try sqliteObjectExists("content_chunks_ai", type: "trigger", in: db))
        #expect(try sqliteObjectExists("content_chunks_ad", type: "trigger", in: db))
        #expect(try sqliteObjectExists("content_chunks_au", type: "trigger", in: db))
    }

    @Test("storage audit repairs standalone missing content chunk FTS table")
    func storageAuditRepairsStandaloneMissingContentChunkFTSTable() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try insertContentChunk(db)
        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ai;")
        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ad;")
        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_au;")
        try db.runSQL("DROP TABLE IF EXISTS content_chunks_fts;")
        let service = makeStorageAuditService(db: db)

        let beforeRepair = try service.audit()
        let missingFTSFinding = beforeRepair.schemaFindings.contains { finding in
            finding.id == "missing_expected_table:content_chunks_fts" &&
            finding.affectedTable == "content_chunks_fts" &&
            finding.isRepairable &&
            finding.repairCommand == "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
        }
        #expect(missingFTSFinding)

        let repair = try service.repairSchemaFindings(approvalToken: "REPAIR_SCHEMA", execute: true)

        #expect(repair.repairedFindingIDs.contains("missing_expected_table:content_chunks_fts"))
        #expect(try sqliteObjectExists("content_chunks_fts", type: "table", in: db))
        #expect(try sqliteObjectExists("content_chunks_ai", type: "trigger", in: db))
        #expect(try sqliteObjectExists("content_chunks_ad", type: "trigger", in: db))
        #expect(try sqliteObjectExists("content_chunks_au", type: "trigger", in: db))
        #expect(try contentChunkFTSMatchCount("moonstone", in: db) == 1)
        #expect(try service.audit().schemaFindings.isEmpty)
    }

    @Test("storage audit repairs standalone missing content chunk FTS trigger")
    func storageAuditRepairsStandaloneMissingContentChunkFTSTrigger() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_au;")
        let service = makeStorageAuditService(db: db)

        let beforeRepair = try service.audit()
        let missingTriggerFinding = beforeRepair.schemaFindings.contains { finding in
            finding.id == "missing_expected_trigger:content_chunks_au" &&
            finding.affectedTable == "content_chunks_au" &&
            finding.isRepairable &&
            finding.repairCommand == "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
        }
        #expect(missingTriggerFinding)

        let repair = try service.repairSchemaFindings(approvalToken: "REPAIR_SCHEMA", execute: true)

        #expect(repair.repairedFindingIDs.contains("missing_expected_trigger:content_chunks_au"))
        #expect(try sqliteObjectExists("content_chunks_au", type: "trigger", in: db))
        #expect(try service.audit().schemaFindings.isEmpty)
    }

    @Test("storage audit flags legacy routing table columns")
    func storageAuditFlagsLegacyRoutingTableColumns() throws {
        let (db, dbURL) = try makeTestDB()
        defer { db.close(); cleanup(dbURL) }

        try db.runSQL("DROP TABLE routing_decisions;")
        try db.runSQL("""
            CREATE TABLE routing_decisions (
                id TEXT PRIMARY KEY,
                owner_type TEXT NOT NULL,
                owner_id TEXT NOT NULL,
                target_type TEXT NOT NULL,
                target_id TEXT,
                target_path TEXT,
                status TEXT NOT NULL,
                reviewed_at REAL
            );
            """)
        let service = CiderStorageAuditService(
            database: db,
            vaultRoot: FileManager.default.temporaryDirectory,
            modelCountsProvider: { [:] },
            doctorReportProvider: {
                VaultDoctor.Report(
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 11),
                    findings: []
                )
            },
            duplicateFindingsProvider: { [] },
            nowProvider: { Date(timeIntervalSince1970: 12) }
        )

        let report = try service.audit()

        let missingColumnFinding = report.schemaFindings.contains { finding in
            finding.id == "missing_expected_column:routing_decisions:item_type" &&
            finding.severity == "error" &&
            finding.affectedTable == "routing_decisions" &&
            !finding.isRepairable &&
            finding.repairCommand == nil &&
            finding.nextSafeAction.contains("targeted migration")
        }
        #expect(missingColumnFinding)
    }
}
