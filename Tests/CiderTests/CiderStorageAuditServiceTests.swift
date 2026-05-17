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
                    nextSafeAction: "Run cider-cli storage repair-schema --json to create the missing table and indexes, then rerun storage audit.",
                    isRepairable: true,
                    repairCommand: "cider-cli storage repair-schema --json"
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
            $0["repairCommand"] as? String == "cider-cli storage repair-schema --json"
        })
        let doctorGroups = try #require(dict["doctorFindingGroups"] as? [String: Int])
        #expect(doctorGroups["warning:duplicateNoteContent"] == 1)
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

    @Test("storage audit repair JSON exposes repaired skipped and remaining findings")
    func storageAuditRepairJSONExposesRepairState() throws {
        let report = CiderStorageAuditSchemaRepairReport(
            generatedAt: Date(timeIntervalSince1970: 12),
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
            finding.repairCommand == "cider-cli storage repair-schema --json"
        }
        #expect(missingRoutingTableFinding)
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

        let repair = try service.repairSchemaFindings()

        #expect(repair.repairedFindingIDs.contains("missing_expected_table:second_brain_routing_decisions"))
        #expect(repair.remainingFindings.isEmpty)
        let afterRepair = try service.audit()
        #expect(afterRepair.schemaFindings.isEmpty)
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

        let repair = try service.repairSchemaFindings()

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
            finding.repairCommand == "cider-cli storage repair-schema --json"
        }
        #expect(missingFTSFinding)

        let repair = try service.repairSchemaFindings()

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
            finding.repairCommand == "cider-cli storage repair-schema --json"
        }
        #expect(missingTriggerFinding)

        let repair = try service.repairSchemaFindings()

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
