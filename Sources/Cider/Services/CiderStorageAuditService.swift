import Foundation

struct CiderStorageAuditMismatch: Codable, Equatable {
    var key: String
    var modelCount: Int
    var sqliteCount: Int
    var detail: String
}

struct CiderStorageAuditDoctorFindingSample: Codable, Equatable {
    var id: String
    var severity: String
    var kind: String
    var summary: String
    var detail: String
    var isFixable: Bool
    var fixLabel: String?
    var relativePath: String?
    var relatedRelativePaths: [String]
    var nextSafeAction: String
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
    var doctorFindingSampleLimit: Int = 20
    var doctorFindingSamples: [CiderStorageAuditDoctorFindingSample] = []
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
    var isRepairable: Bool = false
    var repairCommand: String? = nil
}

struct CiderStorageAuditSchemaRepairReport: Equatable {
    var generatedAt: Date
    var repairedFindingIDs: [String]
    var skippedFindingIDs: [String]
    var remainingFindings: [CiderStorageAuditSchemaFinding]
}

struct CiderStorageDoctorRemediationPlanReport: Equatable {
    var command: String = "storage.doctor.plan"
    var generatedAt: Date
    var isMutating: Bool = false
    var approvalRequired: Bool = true
    var planLimit: Int
    var plans: [CiderStorageDoctorRemediationPlan]
}

struct CiderStorageDoctorRemediationPlan: Equatable {
    var findingID: String
    var kind: String
    var severity: String
    var summary: String
    var proposedAction: String
    var confidence: String
    var candidateCanonicalRelativePath: String?
    var duplicateRelativePaths: [String]
    var affectedRelativePaths: [String]
    var blockers: [String]
    var isMutating: Bool = false
    var approvalRequired: Bool = true
    var approvalCommand: String? = nil
}

@MainActor
final class CiderStorageAuditService {
    private static let defaultDoctorFindingSampleLimit = 20

    private let database: CiderDatabase
    private let vaultRoot: URL
    private let modelCountsProvider: () -> [String: Int]
    private let doctorReportProvider: () -> VaultDoctor.Report
    private let duplicateFindingsProvider: () -> [VaultDuplicateAuditor.Finding]
    private let nowProvider: () -> Date
    private let doctorFindingSampleLimit: Int

    init(
        database: CiderDatabase = .shared,
        vaultRoot: URL = StoragePaths.cachedVaultDirectoryURL,
        modelCountsProvider: (() -> [String: Int])? = nil,
        doctorReportProvider: @escaping () -> VaultDoctor.Report = { VaultDoctor.shared.scan() },
        duplicateFindingsProvider: @escaping () -> [VaultDuplicateAuditor.Finding] = { VaultDuplicateAuditor.scan() },
        doctorFindingSampleLimit: Int = CiderStorageAuditService.defaultDoctorFindingSampleLimit,
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
        self.doctorFindingSampleLimit = doctorFindingSampleLimit
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
            doctorFindingSampleLimit: doctorFindingSampleLimit,
            doctorFindingSamples: doctorFindingSamples(
                doctorReport.findings,
                limit: doctorFindingSampleLimit
            ),
            schemaFindings: try schemaFindings(),
            mismatches: mismatches(modelCounts: modelCounts, sqliteCounts: sqliteCounts)
        )
    }

    func repairSchemaFindings() throws -> CiderStorageAuditSchemaRepairReport {
        let findings = try schemaFindings()
        var repairedFindingIDs: [String] = []
        var skippedFindingIDs: [String] = []

        for finding in findings {
            guard finding.isRepairable else {
                skippedFindingIDs.append(finding.id)
                continue
            }
            guard let repairSQL = repairSQL(for: finding) else {
                skippedFindingIDs.append(finding.id)
                continue
            }
            try database.withTransaction {
                for sql in repairSQL {
                    try database.runSQL(sql)
                }
            }
            repairedFindingIDs.append(finding.id)
        }

        return CiderStorageAuditSchemaRepairReport(
            generatedAt: nowProvider(),
            repairedFindingIDs: repairedFindingIDs.sorted(),
            skippedFindingIDs: skippedFindingIDs.sorted(),
            remainingFindings: try schemaFindings()
        )
    }

    func doctorRemediationPlan(limit: Int = defaultDoctorFindingSampleLimit) -> CiderStorageDoctorRemediationPlanReport {
        let normalizedLimit = max(0, limit)
        let doctorReport = doctorReportProvider()
        let plans = doctorReport.findings
            .compactMap(storageDoctorRemediationPlan)
            .prefix(normalizedLimit)

        return CiderStorageDoctorRemediationPlanReport(
            generatedAt: nowProvider(),
            planLimit: normalizedLimit,
            plans: Array(plans)
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

    private func triggerExists(_ triggerName: String) throws -> Bool {
        let stmt = try database.prepare("""
            SELECT 1
            FROM sqlite_master
            WHERE type = 'trigger' AND name = ?
            LIMIT 1;
            """)
        stmt.bind(triggerName, at: 1)
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
                        nextSafeAction: nextSafeActionForMissingTable(named: table.name),
                        isRepairable: missingTableRepairs[table.name] != nil,
                        repairCommand: missingTableRepairs[table.name] == nil ? nil : repairSchemaCommand
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
                        nextSafeAction: columnDriftSafeAction
                    )
                )
            }
        }
        findings.append(contentsOf: try contentChunkFTSArtifactFindings())
        return findings
    }

    private func contentChunkFTSArtifactFindings() throws -> [CiderStorageAuditSchemaFinding] {
        guard try tableExists("content_chunks") else { return [] }

        var findings: [CiderStorageAuditSchemaFinding] = []
        if try !tableExists("content_chunks_fts") {
            findings.append(
                CiderStorageAuditSchemaFinding(
                    id: "missing_expected_table:content_chunks_fts",
                    severity: "error",
                    affectedTable: "content_chunks_fts",
                    summary: "Missing expected content chunk FTS table content_chunks_fts.",
                    detail: contentChunkFTSPurpose,
                    nextSafeAction: "Run \(repairSchemaCommand) to create the missing FTS table, rebuild its index from content_chunks, and recreate sync triggers.",
                    isRepairable: true,
                    repairCommand: repairSchemaCommand
                )
            )
        }

        for triggerName in expectedContentChunkFTSTriggers {
            if try !triggerExists(triggerName) {
                findings.append(
                    CiderStorageAuditSchemaFinding(
                        id: "missing_expected_trigger:\(triggerName)",
                        severity: "error",
                        affectedTable: triggerName,
                        summary: "Missing expected content chunk FTS trigger \(triggerName).",
                        detail: contentChunkFTSPurpose,
                        nextSafeAction: "Run \(repairSchemaCommand) to recreate the missing content chunk FTS trigger, then rerun storage audit.",
                        isRepairable: true,
                        repairCommand: repairSchemaCommand
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

    private func doctorFindingSamples(
        _ findings: [VaultDoctor.Finding],
        limit: Int
    ) -> [CiderStorageAuditDoctorFindingSample] {
        findings.prefix(max(0, limit)).map { finding in
            CiderStorageAuditDoctorFindingSample(
                id: finding.id,
                severity: finding.severity.rawValue,
                kind: finding.kind.rawValue,
                summary: finding.summary,
                detail: finding.detail,
                isFixable: finding.isFixable,
                fixLabel: finding.fixLabel,
                relativePath: finding.payload.relativePath,
                relatedRelativePaths: finding.payload.relatedRelativePaths ?? [],
                nextSafeAction: nextSafeAction(for: finding)
            )
        }
    }

    private func nextSafeAction(for finding: VaultDoctor.Finding) -> String {
        if finding.isFixable {
            return "Review the finding details, then run the matching explicit doctor fix action only after confirming the target."
        }

        switch finding.kind {
        case .suspiciousFlattenedFolderDuplicate:
            return "Inspect the listed folder paths and choose a manual merge, move, or delete plan; do not run automatic repair."
        case .duplicateNoteContent, .duplicateBookmarkURL, .duplicateContactEmail, .duplicateContactPhone:
            return "Review the listed duplicate candidates manually before merging, deleting, or changing any vault item."
        default:
            return "Review this finding manually; no automatic repair is advertised for this issue."
        }
    }

    private func storageDoctorRemediationPlan(
        for finding: VaultDoctor.Finding
    ) -> CiderStorageDoctorRemediationPlan? {
        guard finding.kind == .suspiciousFlattenedFolderDuplicate else { return nil }
        guard let relativePath = finding.payload.relativePath else { return nil }

        let relatedPaths = finding.payload.relatedRelativePaths ?? []
        let affectedPaths = ([relativePath] + relatedPaths).deduplicatedSorted()
        let canonicalPath = candidateCanonicalRelativePath(
            relativePath: relativePath,
            relatedPaths: relatedPaths
        )
        let duplicatePaths = affectedPaths
            .filter { $0 != canonicalPath }
            .deduplicatedSorted()

        return CiderStorageDoctorRemediationPlan(
            findingID: finding.id,
            kind: finding.kind.rawValue,
            severity: finding.severity.rawValue,
            summary: finding.summary,
            proposedAction: "manual_merge_review",
            confidence: "review_required",
            candidateCanonicalRelativePath: canonicalPath,
            duplicateRelativePaths: duplicatePaths,
            affectedRelativePaths: affectedPaths,
            blockers: [
                "manual approval required before any file or folder mutation",
                "inspect files in every affected path before choosing merge, move, or delete",
                "no automatic remediation command is available for this finding"
            ]
        )
    }

    private func candidateCanonicalRelativePath(
        relativePath: String,
        relatedPaths: [String]
    ) -> String? {
        let affectedPaths = ([relativePath] + relatedPaths).deduplicatedSorted()
        if let nestedPath = affectedPaths.first(where: { $0.contains("/") && !hasNumericSuffixPathComponent($0) }) {
            return nestedPath
        }
        if let nonNumericPath = affectedPaths.first(where: { !hasNumericSuffixPathComponent($0) }) {
            return nonNumericPath
        }
        return affectedPaths.first
    }

    private func hasNumericSuffixPathComponent(_ path: String) -> Bool {
        path.split(separator: "/").contains { component in
            component.range(of: #" \d+$"#, options: .regularExpression) != nil
        }
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

    private var repairSchemaCommand: String {
        "cider-cli storage repair-schema --json"
    }

    private func nextSafeActionForMissingTable(named tableName: String) -> String {
        if missingTableRepairs[tableName] != nil {
            return "Run \(repairSchemaCommand) to create the missing table and related schema artifacts, then rerun storage audit."
        }
        return columnDriftSafeAction
    }

    private var columnDriftSafeAction: String {
        "Create a targeted migration or schema repair for this table; do not rely on startup migrations if schema_version is already current."
    }

    private struct MissingTableRepair {
        var createTableSQL: String
        var additionalSQL: [String]
    }

    private func repairSQL(for finding: CiderStorageAuditSchemaFinding) -> [String]? {
        if let repair = missingTableRepairs[finding.affectedTable] {
            return [repair.createTableSQL] + repair.additionalSQL
        }

        switch finding.id {
        case "missing_expected_table:content_chunks_fts":
            return contentChunkFTSRepairSQL(rebuild: true)
        case "missing_expected_trigger:content_chunks_ai":
            return [CiderSchema.createContentChunksFTSInsertTrigger]
        case "missing_expected_trigger:content_chunks_ad":
            return [CiderSchema.createContentChunksFTSDeleteTrigger]
        case "missing_expected_trigger:content_chunks_au":
            return [CiderSchema.createContentChunksFTSUpdateTrigger]
        default:
            return nil
        }
    }

    private func contentChunkFTSRepairSQL(rebuild: Bool) -> [String] {
        var sql = [
            CiderSchema.createContentChunksFTS,
            CiderSchema.createContentChunksFTSInsertTrigger,
            CiderSchema.createContentChunksFTSDeleteTrigger,
            CiderSchema.createContentChunksFTSUpdateTrigger,
        ]
        if rebuild {
            sql.append("INSERT INTO content_chunks_fts(content_chunks_fts) VALUES('rebuild');")
        }
        return sql
    }

    private var missingTableRepairs: [String: MissingTableRepair] {
        [
            "routing_decisions": MissingTableRepair(
                createTableSQL: CiderSchema.createRoutingDecisions,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_routing_decisions_item ON routing_decisions(item_id, created_at);",
                    "CREATE INDEX IF NOT EXISTS idx_routing_decisions_review ON routing_decisions(review_state);",
                ]
            ),
            "second_brain_routing_decisions": MissingTableRepair(
                createTableSQL: CiderSchema.createSecondBrainRoutingDecisions,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_owner ON second_brain_routing_decisions(owner_type, owner_id, created_at);",
                    "CREATE INDEX IF NOT EXISTS idx_second_brain_routing_status ON second_brain_routing_decisions(status, created_at);",
                ]
            ),
            "item_sections": MissingTableRepair(
                createTableSQL: CiderSchema.createItemSections,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_item_sections_owner ON item_sections(owner_type, owner_id, sort_order);",
                    "CREATE INDEX IF NOT EXISTS idx_item_sections_item ON item_sections(item_id) WHERE item_id IS NOT NULL;",
                ]
            ),
            "content_chunks": MissingTableRepair(
                createTableSQL: CiderSchema.createContentChunks,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_content_chunks_owner ON content_chunks(owner_type, owner_id, chunk_index);",
                    "CREATE INDEX IF NOT EXISTS idx_content_chunks_section ON content_chunks(section_id) WHERE section_id IS NOT NULL;",
                ] + contentChunkFTSRepairSQL(rebuild: false)
            ),
            "agent_actions": MissingTableRepair(
                createTableSQL: CiderSchema.createAgentActions,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_agent_actions_owner ON agent_actions(owner_type, owner_id, created_at);",
                    "CREATE INDEX IF NOT EXISTS idx_agent_actions_tool ON agent_actions(tool_name, created_at);",
                ]
            ),
        ]
    }

    private var contentChunkFTSPurpose: String {
        "The content_chunks_fts table and sync triggers keep content chunk recall searchable."
    }

    private var expectedContentChunkFTSTriggers: [String] {
        ["content_chunks_ai", "content_chunks_ad", "content_chunks_au"]
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

private extension Array where Element == String {
    func deduplicatedSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
