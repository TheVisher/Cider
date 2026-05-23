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
    var command: String = "storage.repair-schema"
    var generatedAt: Date
    var status: String
    var isMutating: Bool
    var approvalRequired: Bool = true
    var requiredApprovalToken: String
    var plannedActions: [String]
    var appliedActions: [String]
    var blockers: [String]
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

struct CiderStorageDoctorRemediationApplyReport: Equatable {
    var command: String = "storage.doctor.apply"
    var generatedAt: Date
    var findingID: String
    var status: String
    var isMutating: Bool
    var approvalRequired: Bool = true
    var requiredApprovalToken: String
    var canonicalRelativePath: String
    var duplicateRelativePath: String
    var plannedActions: [String]
    var appliedActions: [String]
    var blockers: [String]
    var trashRelativePath: String?
    var auditRecorded: Bool = false
}

struct CiderBookmarkDriftAuditReport: Equatable {
    var command: String = "storage.bookmark-drift.audit"
    var generatedAt: Date
    var isMutating: Bool = false
    var approvalRequired: Bool = true
    var findingLimit: Int
    var findings: [CiderBookmarkDriftFinding]
}

struct CiderBookmarkDriftFinding: Equatable {
    var id: String
    var kind: String
    var severity: String
    var itemID: String
    var currentTitle: String
    var url: String
    var currentRelativePath: String
    var proposedRelativePath: String
    var pathDrift: Bool
    var chunkDrift: Bool
    var reasons: [String]
    var approvalToken: String
    var repairCommand: String
}

struct CiderBookmarkDriftRepairReport: Equatable {
    var command: String = "storage.bookmark-drift.repair"
    var generatedAt: Date
    var itemID: String
    var status: String
    var isMutating: Bool
    var approvalRequired: Bool = true
    var requiredApprovalToken: String?
    var currentRelativePath: String?
    var proposedRelativePath: String
    var plannedActions: [String]
    var appliedActions: [String]
    var blockers: [String]
    var auditRecorded: Bool = false
}

struct CiderActiveDuplicateInvariantReport: Equatable {
    var command: String = "storage.active-duplicate-invariants"
    var generatedAt: Date
    var isMutating: Bool = false
    var status: String
    var summary: [String: Int]
    var duplicateFindingLimit: Int
    var duplicateFindings: [VaultDuplicateAuditor.Finding]
    var duplicateRelativePaths: [CiderDuplicateRelativePathFinding]
    var sqliteMismatches: [CiderStorageAuditMismatch]
}

struct CiderDuplicateRelativePathFinding: Equatable {
    var relativePath: String
    var items: [CiderDuplicateRelativePathItem]
}

struct CiderDuplicateRelativePathItem: Equatable {
    var id: String
    var type: String
    var title: String
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

    func activeDuplicateInvariantCheck(limit: Int = defaultDoctorFindingSampleLimit) throws -> CiderActiveDuplicateInvariantReport {
        let normalizedLimit = max(0, limit)
        let duplicateFindings = Array(duplicateFindingsProvider().prefix(normalizedLimit))
        let duplicateRelativePaths = try duplicateRelativePathFindings(limit: normalizedLimit)
        let mismatches = try mismatches(modelCounts: modelCountsProvider(), sqliteCounts: sqliteCountsByEntity())
        let issueCount = duplicateFindings.count + duplicateRelativePaths.count + mismatches.count

        return CiderActiveDuplicateInvariantReport(
            generatedAt: nowProvider(),
            status: issueCount == 0 ? "clean" : "issues_found",
            summary: [
                "duplicateFindings": duplicateFindings.count,
                "duplicateRelativePaths": duplicateRelativePaths.count,
                "sqliteMismatches": mismatches.count,
                "totalIssues": issueCount,
            ],
            duplicateFindingLimit: normalizedLimit,
            duplicateFindings: duplicateFindings,
            duplicateRelativePaths: duplicateRelativePaths,
            sqliteMismatches: mismatches
        )
    }

    func repairSchemaFindings(
        approvalToken: String? = nil,
        execute: Bool = false
    ) throws -> CiderStorageAuditSchemaRepairReport {
        let findings = try schemaFindings()
        let requiredApprovalToken = "REPAIR_SCHEMA"
        let repairableFindings = findings.filter { $0.isRepairable && repairSQL(for: $0) != nil }
        let plannedActions = repairableFindings.map { "repair_schema:\($0.id)" }.sorted()
        var blockers: [String] = []

        guard execute else {
            return CiderStorageAuditSchemaRepairReport(
                generatedAt: nowProvider(),
                status: plannedActions.isEmpty ? "clean" : "planned",
                isMutating: false,
                requiredApprovalToken: requiredApprovalToken,
                plannedActions: plannedActions,
                appliedActions: [],
                blockers: [],
                repairedFindingIDs: [],
                skippedFindingIDs: findings.filter { !$0.isRepairable || repairSQL(for: $0) == nil }.map(\.id).sorted(),
                remainingFindings: findings
            )
        }

        guard approvalToken == requiredApprovalToken else {
            blockers.append("Refusing schema repair without exact approval token \(requiredApprovalToken).")
            return CiderStorageAuditSchemaRepairReport(
                generatedAt: nowProvider(),
                status: "refused",
                isMutating: false,
                requiredApprovalToken: requiredApprovalToken,
                plannedActions: plannedActions,
                appliedActions: [],
                blockers: blockers,
                repairedFindingIDs: [],
                skippedFindingIDs: findings.filter { !$0.isRepairable || repairSQL(for: $0) == nil }.map(\.id).sorted(),
                remainingFindings: findings
            )
        }

        var repairedFindingIDs: [String] = []
        var skippedFindingIDs: [String] = []
        var appliedActions: [String] = []

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
            appliedActions.append("repair_schema:\(finding.id)")
        }

        return CiderStorageAuditSchemaRepairReport(
            generatedAt: nowProvider(),
            status: repairedFindingIDs.isEmpty && skippedFindingIDs.isEmpty ? "clean" : "applied",
            isMutating: !repairedFindingIDs.isEmpty,
            requiredApprovalToken: requiredApprovalToken,
            plannedActions: plannedActions,
            appliedActions: appliedActions.sorted(),
            blockers: [],
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

    func bookmarkDriftAudit(limit: Int = defaultDoctorFindingSampleLimit) throws -> CiderBookmarkDriftAuditReport {
        let normalizedLimit = max(0, limit)
        let findings = try bookmarkDriftFindings()
            .prefix(normalizedLimit)

        return CiderBookmarkDriftAuditReport(
            generatedAt: nowProvider(),
            findingLimit: normalizedLimit,
            findings: Array(findings)
        )
    }

    func repairBookmarkDrift(
        itemID: String,
        approvalToken: String?,
        execute: Bool = false
    ) throws -> CiderBookmarkDriftRepairReport {
        let matchingFinding = try bookmarkDriftFindings().first { $0.itemID == itemID }
        let requiredApprovalToken = matchingFinding?.approvalToken
        let plannedActions = ["rename_webloc_artifact", "update_bookmark_relative_path", "rebuild_bookmark_content_chunks", "record_mutation_audit"]
        var report = CiderBookmarkDriftRepairReport(
            generatedAt: nowProvider(),
            itemID: itemID,
            status: execute ? "refused" : "planned",
            isMutating: false,
            requiredApprovalToken: requiredApprovalToken,
            currentRelativePath: matchingFinding?.currentRelativePath,
            proposedRelativePath: matchingFinding?.proposedRelativePath ?? "",
            plannedActions: plannedActions,
            appliedActions: [],
            blockers: []
        )

        guard let finding = matchingFinding else {
            report.blockers.append("bookmark drift finding is not present in the current audit")
            return report
        }
        report.currentRelativePath = finding.currentRelativePath
        report.proposedRelativePath = finding.proposedRelativePath

        guard approvalToken == finding.approvalToken else {
            report.blockers.append("exact approval token required: \(finding.approvalToken)")
            return report
        }
        guard execute else {
            report.status = "planned"
            report.blockers.append("dry-run only; pass --execute with the exact approval token to mutate")
            return report
        }
        guard isSafeRelativePath(finding.currentRelativePath),
              isSafeRelativePath(finding.proposedRelativePath) else {
            report.blockers.append("paths must be vault-relative and cannot contain traversal")
            return report
        }

        let currentURL = vaultRoot.appendingPathComponent(finding.currentRelativePath)
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            report.blockers.append("current bookmark artifact does not exist on disk")
            return report
        }

        let dirRelativePath = (finding.currentRelativePath as NSString).deletingLastPathComponent
        let filename = (finding.currentRelativePath as NSString).lastPathComponent
        let dirURL = vaultRoot.appendingPathComponent(dirRelativePath, isDirectory: true)
        let bookmarkID = UUID(uuidString: itemID)
        let bookmark = Bookmark(
            id: bookmarkID ?? UUID(),
            title: finding.currentTitle,
            urlString: finding.url,
            updatedAt: nowProvider(),
            relativePath: finding.currentRelativePath
        )

        do {
            let newRelativePath = try BookmarkFileService.shared.renameInPlace(
                bookmark: bookmark,
                filename: filename,
                in: dirURL,
                dirRelativePath: dirRelativePath
            )
            report.proposedRelativePath = newRelativePath
            if newRelativePath != finding.currentRelativePath {
                report.appliedActions.append("rename_webloc_artifact")
            }

            let updateStmt = try database.prepare("""
                UPDATE items
                SET relative_path = ?, updated_at = ?
                WHERE id = ? AND type = 'bookmark';
                """)
            updateStmt.bind(newRelativePath, at: 1)
                .bind(DatabaseHelpers.encode(nowProvider()), at: 2)
                .bind(itemID, at: 3)
            try updateStmt.step()
            report.appliedActions.append("update_bookmark_relative_path")

            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: itemID)
            _ = try SecondBrainItemContentIndexingService(database: database).rebuild(owner: owner)
            report.appliedActions.append("rebuild_bookmark_content_chunks")

            if let bookmarkID {
                MutationAuditService(database: database).record(
                    action: "storage.bookmark-drift.repair",
                    itemType: "bookmark",
                    itemID: bookmarkID,
                    before: [
                        "relativePath": finding.currentRelativePath,
                    ],
                    after: [
                        "relativePath": newRelativePath,
                    ],
                    metadata: [
                        "findingID": finding.id,
                        "pathDrift": String(finding.pathDrift),
                        "chunkDrift": String(finding.chunkDrift),
                    ],
                    source: .cleanup
                )
                report.auditRecorded = true
                report.appliedActions.append("record_mutation_audit")
            }

            report.status = "applied"
            report.isMutating = true
            return report
        } catch {
            report.status = "failed"
            report.blockers.append(error.localizedDescription)
            return report
        }
    }

    func applyDoctorRemediation(
        findingID: String,
        canonicalRelativePath: String,
        duplicateRelativePath: String,
        approvalToken: String?,
        execute: Bool = false
    ) -> CiderStorageDoctorRemediationApplyReport {
        let requiredApprovalToken = Self.doctorRemediationApprovalToken(
            findingID: findingID,
            duplicateRelativePath: duplicateRelativePath,
            canonicalRelativePath: canonicalRelativePath
        )
        let plannedActions = ["move_duplicate_to_storage_doctor_trash", "delete_duplicate_folder_row", "record_mutation_audit"]
        var result = CiderStorageDoctorRemediationApplyReport(
            generatedAt: nowProvider(),
            findingID: findingID,
            status: execute ? "refused" : "planned",
            isMutating: false,
            requiredApprovalToken: requiredApprovalToken,
            canonicalRelativePath: canonicalRelativePath,
            duplicateRelativePath: duplicateRelativePath,
            plannedActions: plannedActions,
            appliedActions: [],
            blockers: [],
            trashRelativePath: nil
        )

        guard let plan = doctorRemediationPlan(limit: Int.max).plans.first(where: { $0.findingID == findingID }) else {
            result.status = "refused"
            result.blockers.append("finding not present in current storage doctor plan")
            return result
        }
        guard plan.proposedAction == "empty_duplicate_folder_removal" else {
            result.status = "refused"
            result.blockers.append("only empty_duplicate_folder_removal plans can be applied")
            return result
        }
        guard plan.candidateCanonicalRelativePath == canonicalRelativePath,
              plan.duplicateRelativePaths.contains(duplicateRelativePath) else {
            result.status = "refused"
            result.blockers.append("requested canonical and duplicate paths do not exactly match the current plan")
            return result
        }
        guard isSafeRelativePath(canonicalRelativePath),
              isSafeRelativePath(duplicateRelativePath) else {
            result.status = "refused"
            result.blockers.append("paths must be vault-relative and cannot contain traversal")
            return result
        }
        guard approvalToken == requiredApprovalToken else {
            result.status = "refused"
            result.blockers.append("exact approval token required: \(requiredApprovalToken)")
            return result
        }

        let canonicalURL = vaultRoot.appendingPathComponent(canonicalRelativePath, isDirectory: true)
        let duplicateURL = vaultRoot.appendingPathComponent(duplicateRelativePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: canonicalURL.path) else {
            result.status = "refused"
            result.blockers.append("canonical path does not exist on disk")
            return result
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: duplicateURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.status = "refused"
            result.blockers.append("duplicate path does not exist as a directory on disk")
            return result
        }
        guard directoryIsEmpty(duplicateURL) else {
            result.status = "refused"
            result.blockers.append("duplicate folder is non-empty; manual merge review is required")
            return result
        }
        guard execute else {
            result.status = "planned"
            result.blockers.append("dry-run only; pass --execute with the exact approval token to mutate")
            return result
        }

        let trashRelativePath = ".cider/storage-doctor-trash/\(safeTrashComponent(findingID))-\(Int(nowProvider().timeIntervalSince1970))/\(duplicateRelativePath)"
        let trashURL = vaultRoot.appendingPathComponent(trashRelativePath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: trashURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: duplicateURL, to: trashURL)
            result.appliedActions.append("move_duplicate_to_storage_doctor_trash")
            result.trashRelativePath = trashRelativePath

            if deleteFolderRow(relativePath: duplicateRelativePath) {
                result.appliedActions.append("delete_duplicate_folder_row")
            }

            if let folderID = planFolderID(for: plan) {
                MutationAuditService(database: database).record(
                    action: "storage.doctor.apply",
                    itemType: "vaultFolder",
                    itemID: folderID,
                    before: [
                        "relativePath": duplicateRelativePath,
                    ],
                    after: [
                        "trashRelativePath": trashRelativePath,
                        "canonicalRelativePath": canonicalRelativePath,
                    ],
                    metadata: [
                        "findingID": findingID,
                        "requiredApprovalToken": requiredApprovalToken,
                        "proposedAction": plan.proposedAction,
                    ],
                    source: .cleanup
                )
                result.auditRecorded = true
                result.appliedActions.append("record_mutation_audit")
            }
            result.status = "applied"
            result.isMutating = true
            return result
        } catch {
            result.status = "failed"
            result.blockers.append(error.localizedDescription)
            return result
        }
    }

    static func doctorRemediationApprovalToken(
        findingID: String,
        duplicateRelativePath: String,
        canonicalRelativePath: String
    ) -> String {
        "\(findingID):\(duplicateRelativePath)=>\(canonicalRelativePath)"
    }

    static func bookmarkDriftApprovalToken(
        itemID: String,
        currentRelativePath: String,
        proposedRelativePath: String
    ) -> String {
        "bookmark-drift:\(itemID):\(currentRelativePath)=>\(proposedRelativePath)"
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

    private func duplicateRelativePathFindings(limit: Int) throws -> [CiderDuplicateRelativePathFinding] {
        guard limit > 0, try tableExists("items") else { return [] }
        let stmt = try database.prepare("""
            SELECT relative_path, id, type, title
            FROM items
            WHERE relative_path IS NOT NULL AND relative_path != ''
            ORDER BY relative_path COLLATE NOCASE ASC, updated_at DESC, title COLLATE NOCASE ASC;
            """)
        var grouped: [String: [CiderDuplicateRelativePathItem]] = [:]
        while try stmt.step() {
            let relativePath = stmt.string(at: 0)
            grouped[relativePath, default: []].append(
                CiderDuplicateRelativePathItem(
                    id: stmt.string(at: 1),
                    type: stmt.string(at: 2),
                    title: stmt.string(at: 3)
                )
            )
        }
        return grouped
            .filter { $0.value.count > 1 }
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .prefix(limit)
            .map { CiderDuplicateRelativePathFinding(relativePath: $0.key, items: $0.value) }
    }

    private struct BookmarkDriftCandidate {
        var itemID: String
        var title: String
        var url: String
        var relativePath: String
    }

    private func bookmarkDriftFindings() throws -> [CiderBookmarkDriftFinding] {
        guard try tableExists("items"), try tableExists("bookmarks") else { return [] }
        let candidates = try bookmarkDriftCandidates()
        return try candidates.compactMap(bookmarkDriftFinding)
    }

    private func bookmarkDriftCandidates() throws -> [BookmarkDriftCandidate] {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, b.url, COALESCE(i.relative_path, '')
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.type = 'bookmark'
              AND i.relative_path IS NOT NULL
              AND i.relative_path != ''
            ORDER BY i.updated_at DESC, i.title COLLATE NOCASE ASC;
            """)
        var candidates: [BookmarkDriftCandidate] = []
        while try stmt.step() {
            candidates.append(
                BookmarkDriftCandidate(
                    itemID: stmt.string(at: 0),
                    title: stmt.string(at: 1),
                    url: stmt.string(at: 2),
                    relativePath: stmt.string(at: 3)
                )
            )
        }
        return candidates
    }

    private func bookmarkDriftFinding(for candidate: BookmarkDriftCandidate) throws -> CiderBookmarkDriftFinding? {
        guard candidate.relativePath.lowercased().hasSuffix(".webloc"),
              isSafeRelativePath(candidate.relativePath),
              meaningfulBookmarkTitle(candidate.title, urlString: candidate.url) else {
            return nil
        }

        let currentFilename = (candidate.relativePath as NSString).lastPathComponent
        let currentBase = stripDuplicateSuffix((currentFilename as NSString).deletingPathExtension)
        let expectedBase = BookmarkFileService.shared.sanitizedFilename(candidate.title)
        let proposedRelativePath = proposedBookmarkRelativePath(
            title: candidate.title,
            currentRelativePath: candidate.relativePath
        )
        let fileExists = FileManager.default.fileExists(atPath: vaultRoot.appendingPathComponent(candidate.relativePath).path)
        let pathDrift = fileExists
            && proposedRelativePath != candidate.relativePath
            && normalizedFilenameBase(currentBase) != normalizedFilenameBase(expectedBase)
            && likelyStaleBookmarkFilename(currentBase, title: candidate.title, urlString: candidate.url)

        let chunkDrift = try bookmarkChunkDrift(candidate: candidate)
        guard pathDrift || chunkDrift else { return nil }

        let approvalToken = Self.bookmarkDriftApprovalToken(
            itemID: candidate.itemID,
            currentRelativePath: candidate.relativePath,
            proposedRelativePath: proposedRelativePath
        )
        var reasons: [String] = []
        if pathDrift {
            reasons.append("bookmark title is rich but the .webloc filename still looks host-derived or stale")
        }
        if chunkDrift {
            reasons.append("bookmark content chunks still contain stale title/path text")
        }

        return CiderBookmarkDriftFinding(
            id: "bookmark-title-path-drift:\(candidate.itemID)",
            kind: "bookmark_title_path_drift",
            severity: "warning",
            itemID: candidate.itemID,
            currentTitle: candidate.title,
            url: candidate.url,
            currentRelativePath: candidate.relativePath,
            proposedRelativePath: proposedRelativePath,
            pathDrift: pathDrift,
            chunkDrift: chunkDrift,
            reasons: reasons,
            approvalToken: approvalToken,
            repairCommand: "cider-cli storage bookmark-drift-repair --item \(Self.shellQuoted(candidate.itemID)) --approve \(Self.shellQuoted(approvalToken)) --execute --json"
        )
    }

    private func proposedBookmarkRelativePath(title: String, currentRelativePath: String) -> String {
        let dirRelativePath = (currentRelativePath as NSString).deletingLastPathComponent
        let currentFilename = (currentRelativePath as NSString).lastPathComponent
        let currentBase = stripDuplicateSuffix((currentFilename as NSString).deletingPathExtension)
        let sanitizedTitle = BookmarkFileService.shared.sanitizedFilename(title)
        if normalizedFilenameBase(currentBase) == normalizedFilenameBase(sanitizedTitle) {
            return currentRelativePath
        }
        let dirURL = vaultRoot.appendingPathComponent(dirRelativePath, isDirectory: true)
        let filename = BookmarkFileService.shared.uniqueFilename(
            for: sanitizedTitle,
            extension: "webloc",
            in: dirURL
        )
        return dirRelativePath.isEmpty ? filename : "\(dirRelativePath)/\(filename)"
    }

    private func bookmarkChunkDrift(candidate: BookmarkDriftCandidate) throws -> Bool {
        guard try tableExists("content_chunks") else { return false }
        let stmt = try database.prepare("""
            SELECT title, body
            FROM content_chunks
            WHERE owner_type = 'bookmark' AND owner_id = ?
            ORDER BY chunk_index ASC;
            """)
        stmt.bind(candidate.itemID, at: 1)

        var sawChunk = false
        while try stmt.step() {
            sawChunk = true
            let chunkTitle = stmt.string(at: 0)
            let chunkBody = stmt.string(at: 1)
            if chunkTitle != candidate.title {
                return true
            }
            if chunkBody.contains(candidate.relativePath) {
                let proposedPath = proposedBookmarkRelativePath(
                    title: candidate.title,
                    currentRelativePath: candidate.relativePath
                )
                if proposedPath != candidate.relativePath {
                    return true
                }
            }
        }
        return sawChunk == false ? false : false
    }

    private func meaningfulBookmarkTitle(_ title: String, urlString: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let lower = trimmed.lowercased()
        guard !["untitled", "bookmark"].contains(lower) else { return false }

        let titleBase = normalizedFilenameBase(stripDuplicateSuffix(trimmed))
        guard !titleBase.isEmpty else { return false }
        return !hostDerivedTitleCandidates(urlString: urlString).contains(titleBase)
    }

    private func likelyStaleBookmarkFilename(_ filenameBase: String, title: String, urlString: String) -> Bool {
        let normalizedFilename = normalizedFilenameBase(filenameBase)
        guard normalizedFilename != normalizedFilenameBase(title) else { return false }
        if hostDerivedTitleCandidates(urlString: urlString).contains(normalizedFilename) {
            return true
        }
        return !normalizedFilename.isEmpty && !normalizedFilenameBase(title).contains(normalizedFilename)
    }

    private func hostDerivedTitleCandidates(urlString: String) -> Set<String> {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return []
        }
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let parts = trimmedHost.split(separator: ".").map(String.init)
        var candidates = Set<String>()
        candidates.insert(normalizedFilenameBase(trimmedHost))
        if let first = parts.first {
            candidates.insert(normalizedFilenameBase(first))
        }
        candidates.insert(normalizedFilenameBase(trimmedHost.capitalized))
        return candidates
    }

    private func normalizedFilenameBase(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    private func stripDuplicateSuffix(_ value: String) -> String {
        value.replacingOccurrences(
            of: #" \(\d+\)$"#,
            with: "",
            options: .regularExpression
        )
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

        let proposedAction = duplicatePaths.count == 1 ? "empty_duplicate_folder_removal" : "manual_merge_review"
        let approvalCommand: String? = {
            guard proposedAction == "empty_duplicate_folder_removal",
                  let canonicalPath,
                  let duplicatePath = duplicatePaths.first else { return nil }
            let token = Self.doctorRemediationApprovalToken(
                findingID: finding.id,
                duplicateRelativePath: duplicatePath,
                canonicalRelativePath: canonicalPath
            )
            return "cider-cli storage doctor-apply --finding \(Self.shellQuoted(finding.id)) --canonical \(Self.shellQuoted(canonicalPath)) --duplicate \(Self.shellQuoted(duplicatePath)) --approve \(Self.shellQuoted(token)) --execute --json"
        }()

        return CiderStorageDoctorRemediationPlan(
            findingID: finding.id,
            kind: finding.kind.rawValue,
            severity: finding.severity.rawValue,
            summary: finding.summary,
            proposedAction: proposedAction,
            confidence: "review_required",
            candidateCanonicalRelativePath: canonicalPath,
            duplicateRelativePaths: duplicatePaths,
            affectedRelativePaths: affectedPaths,
            blockers: [
                "manual approval required before any file or folder mutation",
                "inspect files in every affected path before choosing merge, move, or delete",
                proposedAction == "empty_duplicate_folder_removal"
                    ? "approved command refuses unless the duplicate folder is empty"
                    : "no automatic remediation command is available for this finding"
            ],
            approvalCommand: approvalCommand
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

    private func deleteFolderRow(relativePath: String) -> Bool {
        do {
            let stmt = try database.prepare("DELETE FROM folders WHERE relative_path = ?;")
            stmt.bind(relativePath, at: 1)
            try stmt.step()
            return true
        } catch {
            return false
        }
    }

    private func planFolderID(for plan: CiderStorageDoctorRemediationPlan) -> UUID? {
        doctorReportProvider().findings
            .first { $0.id == plan.findingID }?
            .payload
            .folderID
    }

    private func directoryIsEmpty(_ url: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        return contents.isEmpty
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && path.split(separator: "/").allSatisfy { component in
                component != "." && component != ".."
            }
    }

    private func safeTrashComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return filtered.isEmpty ? UUID().uuidString : filtered
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
        "cider-cli storage repair-schema --approve REPAIR_SCHEMA --execute --json"
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
            "owner_relations": MissingTableRepair(
                createTableSQL: CiderSchema.createOwnerRelations,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_owner_relations_source ON owner_relations(source_owner_type, source_owner_id, relation_type, updated_at);",
                    "CREATE INDEX IF NOT EXISTS idx_owner_relations_target ON owner_relations(target_owner_type, target_owner_id, relation_type, updated_at);",
                    "CREATE INDEX IF NOT EXISTS idx_owner_relations_type ON owner_relations(relation_type, updated_at);",
                ]
            ),
            "projects": MissingTableRepair(
                createTableSQL: CiderSchema.createProjects,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status, updated_at);",
                ]
            ),
            "capture_events": MissingTableRepair(
                createTableSQL: CiderSchema.createCaptureEvents,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_capture_events_source ON capture_events(source_kind, created_at);",
                    "CREATE INDEX IF NOT EXISTS idx_capture_events_channel ON capture_events(channel, channel_id, message_id);",
                ]
            ),
            "capture_attachments": MissingTableRepair(
                createTableSQL: CiderSchema.createCaptureAttachments,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_capture_attachments_event ON capture_attachments(capture_event_id, attachment_index);",
                    "CREATE INDEX IF NOT EXISTS idx_capture_attachments_source ON capture_attachments(source_attachment_id) WHERE source_attachment_id IS NOT NULL;",
                ]
            ),
            "enrichment_outputs": MissingTableRepair(
                createTableSQL: CiderSchema.createEnrichmentOutputs,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_enrichment_outputs_owner ON enrichment_outputs(owner_type, owner_id, kind, review_state);",
                    "CREATE INDEX IF NOT EXISTS idx_enrichment_outputs_kind ON enrichment_outputs(kind, normalized_value);",
                ]
            ),
            "similarity_candidates": MissingTableRepair(
                createTableSQL: CiderSchema.createSimilarityCandidates,
                additionalSQL: [
                    "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_source ON similarity_candidates(source_owner_type, source_owner_id, review_state, score);",
                    "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_target ON similarity_candidates(target_owner_type, target_owner_id, review_state, score);",
                    "CREATE INDEX IF NOT EXISTS idx_similarity_candidates_review ON similarity_candidates(review_state, updated_at);",
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
            (
                "owner_relations",
                ["id", "source_owner_type", "source_owner_id", "target_owner_type", "target_owner_id", "relation_type"],
                "The owner_relations table stores typed graph edges between second-brain owners."
            ),
            (
                "projects",
                ["id", "title", "status", "metadata"],
                "The projects table gives project workspaces stable backend identity and project context."
            ),
            (
                "capture_events",
                ["id", "source_kind", "source_url", "source_file", "source_text", "metadata"],
                "The capture_events table preserves structured source provenance for captured items."
            ),
            (
                "capture_attachments",
                ["id", "capture_event_id", "attachment_index", "filename", "mime_type", "byte_size"],
                "The capture_attachments table stores durable per-attachment provenance for capture events."
            ),
            (
                "enrichment_outputs",
                ["id", "owner_type", "owner_id", "kind", "value", "normalized_value", "review_state"],
                "The enrichment_outputs table stores reviewable extracted entities, topics, dates, and links."
            ),
            (
                "similarity_candidates",
                ["id", "source_owner_type", "source_owner_id", "target_owner_type", "target_owner_id", "candidate_type", "signal", "score", "review_state"],
                "The similarity_candidates table stores reviewable duplicate, similar, and grouping candidates before they become graph relations."
            ),
        ]
    }
}

private extension Array where Element == String {
    func deduplicatedSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
