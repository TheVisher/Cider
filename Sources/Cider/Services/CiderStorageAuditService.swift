import Foundation

struct CiderStorageAuditMismatch: Codable, Equatable {
    var key: String
    var modelCount: Int
    var sqliteCount: Int
    var detail: String
}

struct CiderStorageAuditReport: Equatable {
    var generatedAt: Date
    var modelCounts: [String: Int]
    var sqliteCounts: [String: Int]
    var fileArtifactCounts: [String: Int]
    var doctorFindingGroups: [String: Int]
    var duplicateFindingGroups: [String: Int]
    var totalDoctorFindings: Int
    var fixableDoctorFindings: Int
    var schemaFindings: [CiderStorageAuditSchemaFinding]
    var mismatches: [CiderStorageAuditMismatch]
}

struct CiderStorageAuditSchemaFinding: Codable, Equatable {
    var id: String
    var severity: String
    var affectedTable: String
    var summary: String
    var detail: String
    var nextSafeAction: String
}

@MainActor
final class CiderStorageAuditService {
    private let database: CiderDatabase
    private let vaultRoot: URL
    private let modelCountsProvider: () -> [String: Int]
    private let doctorReportProvider: () -> VaultDoctor.Report
    private let duplicateFindingsProvider: () -> [VaultDuplicateAuditor.Finding]
    private let nowProvider: () -> Date

    init(
        database: CiderDatabase = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        modelCountsProvider: (() -> [String: Int])? = nil,
        doctorReportProvider: @escaping () -> VaultDoctor.Report = { VaultDoctor.shared.scan() },
        duplicateFindingsProvider: @escaping () -> [VaultDuplicateAuditor.Finding] = { VaultDuplicateAuditor.scan() },
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.database = database
        self.vaultRoot = vaultRoot
        self.modelCountsProvider = modelCountsProvider ?? {
            [
                "folder": VaultFolderService.shared.folders.count,
                "note": NotesStorage.shared.notes.count,
                "bookmark": VaultBookmarkService.shared.bookmarks.count,
                "contact": ContactStorage.shared.contacts.count,
                "todo": TodoCardStorage.shared.todoCards.count,
                "dateCard": DateCardStorage.shared.dateCards.count,
                "vaultFile": VaultFileService.shared.files.count,
            ]
        }
        self.doctorReportProvider = doctorReportProvider
        self.duplicateFindingsProvider = duplicateFindingsProvider
        self.nowProvider = nowProvider
    }

    func audit() throws -> CiderStorageAuditReport {
        let modelCounts = modelCountsProvider()
        let sqliteCounts = try sqliteCountsByEntity()
        let fileArtifactCounts = fileArtifactCountsByKind()
        let doctorReport = doctorReportProvider()
        let duplicateFindings = duplicateFindingsProvider()

        return CiderStorageAuditReport(
            generatedAt: nowProvider(),
            modelCounts: modelCounts,
            sqliteCounts: sqliteCounts,
            fileArtifactCounts: fileArtifactCounts,
            doctorFindingGroups: groupedDoctorFindings(doctorReport.findings),
            duplicateFindingGroups: groupedDuplicateFindings(duplicateFindings),
            totalDoctorFindings: doctorReport.findings.count,
            fixableDoctorFindings: doctorReport.fixableCount,
            schemaFindings: try schemaFindings(),
            mismatches: mismatches(modelCounts: modelCounts, sqliteCounts: sqliteCounts)
        )
    }

    private func sqliteCountsByEntity() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        if try tableExists("folders") {
            counts["folder"] = try rowCount(table: "folders")
        }
        guard try tableExists("items") else { return counts }

        let stmt = try database.prepare("""
            SELECT type, COUNT(*)
            FROM items
            GROUP BY type;
            """)
        while try stmt.step() {
            let key = normalizedEntityKey(stmt.string(at: 0))
            counts[key, default: 0] += Int(stmt.int64(at: 1))
        }
        return counts
    }

    private func tableExists(_ tableName: String) throws -> Bool {
        let stmt = try database.prepare("""
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1;
            """)
        stmt.bind(tableName, at: 1)
        return try stmt.step()
    }

    private func rowCount(table: String) throws -> Int {
        let safeTable = table.replacingOccurrences(of: "\"", with: "\"\"")
        let stmt = try database.prepare("SELECT COUNT(*) FROM \"\(safeTable)\";")
        return try stmt.step() ? Int(stmt.int64(at: 0)) : 0
    }

    private func schemaFindings() throws -> [CiderStorageAuditSchemaFinding] {
        var findings: [CiderStorageAuditSchemaFinding] = []
        for table in expectedSecondBrainTables {
            if try !tableExists(table.name) {
                findings.append(
                    CiderStorageAuditSchemaFinding(
                        id: "missing_expected_table:\(table.name)",
                        severity: "error",
                        affectedTable: table.name,
                        summary: "Missing expected second-brain table \(table.name).",
                        detail: table.purpose,
                        nextSafeAction: migrationSafeAction
                    )
                )
                continue
            }

            let columns = try columnNames(for: table.name)
            for column in table.requiredColumns where !columns.contains(column) {
                findings.append(
                    CiderStorageAuditSchemaFinding(
                        id: "missing_expected_column:\(table.name):\(column)",
                        severity: "error",
                        affectedTable: table.name,
                        summary: "Missing expected column \(table.name).\(column).",
                        detail: table.purpose,
                        nextSafeAction: migrationSafeAction
                    )
                )
            }
        }
        return findings
    }

    private func columnNames(for tableName: String) throws -> Set<String> {
        let safeTable = tableName.replacingOccurrences(of: "'", with: "''")
        let stmt = try database.prepare("PRAGMA table_info('\(safeTable)');")
        var columns = Set<String>()
        while try stmt.step() {
            columns.insert(stmt.string(at: 1))
        }
        return columns
    }

    private func fileArtifactCountsByKind() -> [String: Int] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [:] }

        var counts: [String: Int] = [:]
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".cider" {
                enumerator.skipDescendants()
                continue
            }
            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                continue
            }
            if isDirectory == true {
                counts["directory", default: 0] += 1
                continue
            }
            let key: String
            switch url.pathExtension.lowercased() {
            case "md":
                key = "markdown"
            case "webloc":
                key = "webloc"
            case "url":
                key = "url"
            case "vcf":
                key = "vcard"
            case "ics":
                key = "ics"
            default:
                key = "other"
            }
            counts[key, default: 0] += 1
        }
        return counts
    }

    private func groupedDoctorFindings(_ findings: [VaultDoctor.Finding]) -> [String: Int] {
        var groups: [String: Int] = [:]
        for finding in findings {
            groups["\(finding.severity.rawValue):\(finding.kind.rawValue)", default: 0] += 1
        }
        return groups
    }

    private func groupedDuplicateFindings(_ findings: [VaultDuplicateAuditor.Finding]) -> [String: Int] {
        var groups: [String: Int] = [:]
        for finding in findings {
            groups["\(finding.entityType.rawValue):\(finding.kind.rawValue)", default: 0] += 1
        }
        return groups
    }

    private func mismatches(
        modelCounts: [String: Int],
        sqliteCounts: [String: Int]
    ) -> [CiderStorageAuditMismatch] {
        let keys = Set(modelCounts.keys).union(sqliteCounts.keys).sorted()
        return keys.compactMap { key in
            let modelCount = modelCounts[key] ?? 0
            let sqliteCount = sqliteCounts[key] ?? 0
            guard modelCount != sqliteCount else { return nil }
            return CiderStorageAuditMismatch(
                key: key,
                modelCount: modelCount,
                sqliteCount: sqliteCount,
                detail: "Model count for \(key) is \(modelCount) but SQLite has \(sqliteCount)."
            )
        }
    }

    private func normalizedEntityKey(_ raw: String) -> String {
        raw == "event" ? "dateCard" : raw
    }

    private var migrationSafeAction: String {
        "Run the current Cider app or CLI against this vault to apply database migrations, then rerun storage audit."
    }

    private var expectedSecondBrainTables: [(name: String, requiredColumns: [String], purpose: String)] {
        [
            (
                "routing_decisions",
                ["id", "item_id", "item_type", "target_kind", "review_state", "supersedes_decision_id"],
                "The routing_decisions table is required for explainable capture routing and review queues."
            ),
            (
                "second_brain_routing_decisions",
                ["id", "owner_type", "owner_id", "target_type", "status"],
                "The second_brain_routing_decisions table preserves legacy second-brain routing provenance."
            ),
            (
                "item_sections",
                ["id", "owner_type", "owner_id", "section_key", "body"],
                "The item_sections table stores structured context sections for agent-readable item packets."
            ),
            (
                "content_chunks",
                ["id", "owner_type", "owner_id", "body", "chunk_index"],
                "The content_chunks table stores searchable recall/context chunks."
            ),
            (
                "agent_actions",
                ["id", "owner_type", "owner_id", "tool_name", "status"],
                "The agent_actions table stores auditable agent actions against Cider entities."
            ),
        ]
    }
}
