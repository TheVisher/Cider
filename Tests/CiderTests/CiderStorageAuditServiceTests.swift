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
                    nextSafeAction: "Run the current Cider app or CLI against this vault to apply database migrations, then rerun storage audit."
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
            $0["nextSafeAction"] as? String != nil
        })
        let doctorGroups = try #require(dict["doctorFindingGroups"] as? [String: Int])
        #expect(doctorGroups["warning:duplicateNoteContent"] == 1)
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

        #expect(report.schemaFindings.contains {
            $0.id == "missing_expected_table:routing_decisions" &&
            $0.severity == "error" &&
            $0.affectedTable == "routing_decisions" &&
            $0.nextSafeAction.contains("migrations")
        })
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

        #expect(report.schemaFindings.contains {
            $0.id == "missing_expected_column:routing_decisions:item_type" &&
            $0.severity == "error" &&
            $0.affectedTable == "routing_decisions"
        })
    }
}
