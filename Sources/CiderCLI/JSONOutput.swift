@testable import Cider
import Foundation

/// Checks if --json flag is present in command line args
let jsonOutput = CommandLine.arguments.contains("--json")

/// Outputs JSON-encoded data to stdout, or prints human-readable fallback
func outputJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
       let string = String(data: data, encoding: .utf8) {
        print(string)
    }
}

// MARK: - Item Serializers (all @MainActor since they access shared singletons)

@MainActor func bookmarkToDict(_ bm: Bookmark) -> [String: Any] {
    var d: [String: Any] = [
        "id": bm.id.uuidString,
        "title": bm.title,
        "url": bm.urlString,
        "host": bm.hostDisplay,
        "notes": bm.notes,
        "tags": bm.tags,
        "labelIDs": bm.labelIDs.map(\.uuidString),
        "folder": bm.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "folderID": bm.folderID?.uuidString as Any,
        "created": ISO8601DateFormatter().string(from: bm.createdAt),
        "updated": ISO8601DateFormatter().string(from: bm.updatedAt),
        "titleManuallySet": bm.titleManuallySet,
        "notesManuallySet": bm.notesManuallySet,
    ]
    if let path = bm.relativePath { d["relativePath"] = path }
    if let ocr = bm.ocrText { d["ocrText"] = ocr }
    if let colors = bm.dominantColors { d["dominantColors"] = colors }
    if let summary = bm.aiSummary { d["aiSummary"] = summary }
    if let status = bm.enrichmentStatus { d["enrichmentStatus"] = status }
    if let enrichedAt = bm.lastEnrichedAt { d["lastEnrichedAt"] = ISO8601DateFormatter().string(from: enrichedAt) }
    if let thumb = bm.thumbnailRelativePath { d["thumbnailPath"] = thumb }
    if let remoteThumb = bm.thumbnailRemoteURLString { d["thumbnailRemoteURL"] = remoteThumb }
    if let metadataUpdatedAt = bm.metadataUpdatedAt { d["metadataUpdatedAt"] = ISO8601DateFormatter().string(from: metadataUpdatedAt) }
    d["isEnriching"] = bm.isEnriching
    if let media = bm.mediaType { d["mediaType"] = media.rawValue }
    return d
}

@MainActor func noteToDict(_ note: Note) -> [String: Any] {
    var d: [String: Any] = [
        "id": note.id.uuidString,
        "title": note.title,
        "folder": note.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "folderID": note.folderID?.uuidString as Any,
        "labelIDs": note.labelIDs.map(\.uuidString),
        "tags": note.tags,
        "pinned": note.isPinned,
        "created": ISO8601DateFormatter().string(from: note.createdAt),
        "modified": ISO8601DateFormatter().string(from: note.modifiedAt),
        "relativePath": note.relativePath,
        "isProjectArtifact": note.isProjectArtifact,
    ]
    if let projectID = note.projectID { d["projectID"] = projectID }
    if let artifactType = note.artifactType { d["artifactType"] = artifactType }
    if let plan = note.projectPlanMetadata { d["planClassification"] = projectPlanMetadataToDict(plan) }
    return d
}

@MainActor func projectPlanMetadataToDict(_ plan: ProjectPlanMetadata) -> [String: Any] {
    var d: [String: Any] = [
        "type": plan.type,
        "status": plan.status,
        "isParked": plan.isParked,
        "isTemplate": plan.isTemplate,
        "isActive": plan.isActive,
    ]
    if let category = plan.category { d["category"] = category }
    if let source = plan.source { d["source"] = source }
    if let dogfoodStatus = plan.dogfoodStatus { d["dogfoodStatus"] = dogfoodStatus }
    if let parkedBecause = plan.parkedBecause { d["parkedBecause"] = parkedBecause }
    if let revisitTrigger = plan.revisitTrigger { d["revisitTrigger"] = revisitTrigger }
    return d
}

@MainActor func todoToDict(_ todo: TodoCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": todo.id.uuidString,
        "title": todo.title,
        "details": todo.details,
        "completed": todo.isCompleted,
        "created": ISO8601DateFormatter().string(from: todo.createdAt),
        "updated": ISO8601DateFormatter().string(from: todo.updatedAt),
        "labelIDs": todo.labelIDs.map(\.uuidString),
        "folder": todo.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if let due = todo.dueDate { d["dueDate"] = ISO8601DateFormatter().string(from: due) }
    if let priority = todo.priority { d["priority"] = priority.rawValue }
    if let actionURLString = todo.actionURLString { d["actionURL"] = actionURLString }
    if let snoozedUntil = todo.snoozedUntil { d["snoozedUntil"] = ISO8601DateFormatter().string(from: snoozedUntil) }
    if let completedAt = todo.completedAt { d["completedAt"] = ISO8601DateFormatter().string(from: completedAt) }
    d["checklist"] = todo.checklist.map { item -> [String: Any] in
        var cd: [String: Any] = [
            "id": item.id.uuidString,
            "title": item.title,
            "completed": item.isCompleted,
        ]
        if !item.subtasks.isEmpty {
            cd["subtasks"] = item.subtasks.map { [
                "id": $0.id.uuidString,
                "title": $0.title,
                "completed": $0.isCompleted,
            ] as [String: Any] }
        }
        return cd
    }
    return d
}

@MainActor func eventToDict(_ card: DateCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": card.id.uuidString,
        "title": card.title,
        "details": card.details,
        "startAt": ISO8601DateFormatter().string(from: card.startAt),
        "completed": card.isCompleted,
        "created": ISO8601DateFormatter().string(from: card.createdAt),
        "labelIDs": card.labelIDs.map(\.uuidString),
        "folder": card.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if let endAt = card.endAt { d["endAt"] = ISO8601DateFormatter().string(from: endAt) }
    if !card.location.isEmpty { d["location"] = card.location }
    if let amount = card.amount { d["amount"] = amount }
    if let actionURLString = card.actionURLString { d["actionURL"] = actionURLString }
    if let snoozedUntil = card.snoozedUntil { d["snoozedUntil"] = ISO8601DateFormatter().string(from: snoozedUntil) }
    return d
}

func agendaBriefingToDict(_ brief: AgendaBriefing) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    return [
        "generatedAt": formatter.string(from: brief.generatedAt),
        "items": brief.items.map { agendaBriefingItemToDict($0, formatter: formatter) }
    ]
}

func agendaBriefingItemToDict(_ item: AgendaBriefingItem, formatter: ISO8601DateFormatter) -> [String: Any] {
    var dict: [String: Any] = [
        "id": item.id.uuidString,
        "type": item.itemType.rawValue,
        "title": item.title,
        "status": item.status.rawValue,
        "bucket": item.bucket.rawValue,
        "surfaceToday": item.surfaceToday,
        "reason": item.reason
    ]
    if let dueAt = item.dueAt { dict["dueAt"] = formatter.string(from: dueAt) }
    if let nextSurfaceDate = item.nextSurfaceDate { dict["nextSurfaceDate"] = formatter.string(from: nextSurfaceDate) }
    if let priority = item.priority { dict["priority"] = priority }
    if let actionURLString = item.actionURLString { dict["actionURL"] = actionURLString }
    dict["reminderPolicy"] = item.reminderPolicy
    if let suggestedAction = item.suggestedAction { dict["suggestedAction"] = suggestedAction }
    dict["surfacing"] = surfacingExplanationToDict(item.surfacingExplanation)
    return dict
}

func surfacingExplanationToDict(_ explanation: CiderSurfacingExplanation) -> [String: Any] {
    var dict: [String: Any] = [
        "reason": explanation.reason,
        "urgency": explanation.urgency,
        "sourceSignal": explanation.sourceSignal,
        "reviewState": explanation.reviewState,
        "suggestedAction": explanation.suggestedAction,
    ]
    if let actionURLString = explanation.actionURLString {
        dict["actionURLString"] = actionURLString
    }
    return dict
}

func reminderActionResultToDict(_ result: CiderReminderActionResult) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    var dict: [String: Any] = [
        "itemType": result.itemType.rawValue,
        "id": result.id.uuidString,
        "title": result.title,
        "action": result.action.rawValue,
        "completed": result.completed,
    ]
    if let snoozedUntil = result.snoozedUntil {
        dict["snoozedUntil"] = formatter.string(from: snoozedUntil)
    }
    if let surfacing = result.surfacing {
        var surfacingDict: [String: Any] = [
            "id": surfacing.id.uuidString,
            "itemType": surfacing.itemType.rawValue,
            "title": surfacing.title,
            "surfaceToday": surfacing.surfaceToday,
            "explanation": surfacingExplanationToDict(surfacing.surfacing),
        ]
        if let dueAt = surfacing.dueAt {
            surfacingDict["dueAt"] = formatter.string(from: dueAt)
        }
        dict["surfacing"] = surfacingDict
    }
    return dict
}

func recallScorecardToDict(_ scorecard: CiderRecallScorecard) -> [String: Any] {
    [
        "generatedAt": ISO8601DateFormatter().string(from: scorecard.generatedAt),
        "totalProbeCount": scorecard.totalProbeCount,
        "passedProbeCount": scorecard.passedProbeCount,
        "failedProbeCount": scorecard.failedProbeCount,
        "passRate": scorecard.passRate,
        "capabilityScores": CiderRecallCapability.allCases.map { capability in
            recallCapabilityScoreToDict(
                scorecard.capabilityScores[capability]
                    ?? CiderRecallCapabilityScore(capability: capability, passed: 0, failed: 0)
            )
        },
        "results": scorecard.results.map(recallProbeResultToDict),
    ]
}

func recallProbeToDict(_ probe: CiderRecallProbe) -> [String: Any] {
    var dict: [String: Any] = [
        "id": probe.id,
        "title": probe.title,
        "query": probe.query,
        "expectedRef": recallLibraryEntityRefToDict(probe.expectedRef),
        "expectedRelatedRefs": probe.expectedRelatedRefs.map(recallLibraryEntityRefToDict),
    ]
    if let expectsSurfaceToday = probe.expectsSurfaceToday {
        dict["expectsSurfaceToday"] = expectsSurfaceToday
    }
    return dict
}

func recallCapabilityScoreToDict(_ score: CiderRecallCapabilityScore) -> [String: Any] {
    [
        "capability": score.capability.rawValue,
        "passed": score.passed,
        "failed": score.failed,
        "total": score.total,
    ]
}

func recallProbeResultToDict(_ result: CiderRecallProbeResult) -> [String: Any] {
    [
        "id": result.id,
        "probe": recallProbeToDict(result.probe),
        "passed": result.passed,
        "checks": result.checks.map(recallProbeCheckToDict),
        "topResults": result.topResults.map(recallTopResultToDict),
    ]
}

func recallProbeCheckToDict(_ check: CiderRecallProbeCheck) -> [String: Any] {
    [
        "capability": check.capability.rawValue,
        "passed": check.passed,
        "detail": check.detail,
    ]
}

func recallTopResultToDict(_ result: CiderRecallTopResult) -> [String: Any] {
    var dict: [String: Any] = [
        "rank": result.rank,
        "score": result.score,
        "kind": result.kind.rawValue,
        "owner": recallOwnerToDict(result.owner),
        "title": result.title,
        "snippet": result.snippet,
        "matchedExpected": result.matchedExpected,
    ]
    if let stage = result.stage {
        dict["stage"] = stage
    }
    if let matchedQuery = result.matchedQuery {
        dict["matchedQuery"] = matchedQuery
    }
    if !result.rankFactors.isEmpty {
        dict["rankFactors"] = result.rankFactors
    }
    return dict
}

private func recallLibraryEntityRefToDict(_ ref: LibraryEntityRef) -> [String: Any] {
    [
        "id": ref.id,
        "type": ref.type.rawValue,
        "entityID": ref.entityID.uuidString,
    ]
}

private func recallOwnerToDict(_ owner: SecondBrainOwnerRef) -> [String: Any] {
    [
        "ownerType": owner.ownerType,
        "ownerID": owner.ownerID,
    ]
}

func storageAuditReportToDict(_ report: CiderStorageAuditReport) -> [String: Any] {
    [
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "modelCounts": report.modelCounts,
        "sqliteCounts": report.sqliteCounts,
        "fileArtifactCounts": report.fileArtifactCounts,
        "doctorFindingGroups": report.doctorFindingGroups,
        "duplicateFindingGroups": report.duplicateFindingGroups,
        "totalDoctorFindings": report.totalDoctorFindings,
        "fixableDoctorFindings": report.fixableDoctorFindings,
        "doctorFindingSampleLimit": report.doctorFindingSampleLimit,
        "doctorFindingSamples": report.doctorFindingSamples.map(storageAuditDoctorFindingSampleToDict),
        "schemaFindings": report.schemaFindings.map(storageAuditSchemaFindingToDict),
        "searchIndexDriftFindings": report.searchIndexDriftFindings.map(searchIndexDriftFindingToDict),
        "mismatches": report.mismatches.map(storageAuditMismatchToDict),
    ]
}

func searchIndexDriftFindingToDict(_ finding: CiderSearchIndexDriftFinding) -> [String: Any] {
    var dict: [String: Any] = [
        "id": finding.id,
        "kind": finding.kind,
        "severity": finding.severity,
        "itemType": finding.itemType,
        "itemID": finding.itemID,
        "title": finding.title,
        "updatedAt": ISO8601DateFormatter().string(from: finding.updatedAt),
        "chunkCount": finding.chunkCount,
        "safeRepairCommand": finding.safeRepairCommand,
    ]
    if let chunkUpdatedAt = finding.chunkUpdatedAt {
        dict["chunkUpdatedAt"] = ISO8601DateFormatter().string(from: chunkUpdatedAt)
    }
    return dict
}

func storageAuditDoctorFindingSampleToDict(_ sample: CiderStorageAuditDoctorFindingSample) -> [String: Any] {
    var dict: [String: Any] = [
        "id": sample.id,
        "severity": sample.severity,
        "kind": sample.kind,
        "summary": sample.summary,
        "detail": sample.detail,
        "isFixable": sample.isFixable,
        "relatedRelativePaths": sample.relatedRelativePaths,
        "directItemCount": sample.directItemCount,
        "representativeItems": sample.representativeItems.map(storageAuditRepresentativeItemToDict),
        "nextSafeAction": sample.nextSafeAction,
    ]
    if let fixLabel = sample.fixLabel {
        dict["fixLabel"] = fixLabel
    }
    if let relativePath = sample.relativePath {
        dict["relativePath"] = relativePath
    }
    return dict
}

func storageAuditRepresentativeItemToDict(_ item: CiderStorageAuditRepresentativeItem) -> [String: Any] {
    [
        "id": item.id,
        "type": item.type,
        "title": item.title,
    ]
}

func storageAuditSchemaFindingToDict(_ finding: CiderStorageAuditSchemaFinding) -> [String: Any] {
    var dict: [String: Any] = [
        "id": finding.id,
        "severity": finding.severity,
        "affectedTable": finding.affectedTable,
        "summary": finding.summary,
        "detail": finding.detail,
        "nextSafeAction": finding.nextSafeAction,
        "isRepairable": finding.isRepairable,
    ]
    if let repairCommand = finding.repairCommand {
        dict["repairCommand"] = repairCommand
    }
    return dict
}

func storageDoctorRemediationPlanReportToDict(_ report: CiderStorageDoctorRemediationPlanReport) -> [String: Any] {
    [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "planLimit": report.planLimit,
        "plans": report.plans.map(storageDoctorRemediationPlanToDict),
    ]
}

func storageDoctorRemediationPlanToDict(_ plan: CiderStorageDoctorRemediationPlan) -> [String: Any] {
    var dict: [String: Any] = [
        "findingID": plan.findingID,
        "kind": plan.kind,
        "severity": plan.severity,
        "summary": plan.summary,
        "proposedAction": plan.proposedAction,
        "confidence": plan.confidence,
        "duplicateRelativePaths": plan.duplicateRelativePaths,
        "affectedRelativePaths": plan.affectedRelativePaths,
        "blockers": plan.blockers,
        "isMutating": plan.isMutating,
        "approvalRequired": plan.approvalRequired,
    ]
    if let canonicalPath = plan.candidateCanonicalRelativePath {
        dict["candidateCanonicalRelativePath"] = canonicalPath
    }
    if let approvalCommand = plan.approvalCommand {
        dict["approvalCommand"] = approvalCommand
    }
    return dict
}

func storageDoctorRemediationApplyReportToDict(_ report: CiderStorageDoctorRemediationApplyReport) -> [String: Any] {
    var dict: [String: Any] = [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "findingID": report.findingID,
        "status": report.status,
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "requiredApprovalToken": report.requiredApprovalToken,
        "canonicalRelativePath": report.canonicalRelativePath,
        "duplicateRelativePath": report.duplicateRelativePath,
        "plannedActions": report.plannedActions,
        "appliedActions": report.appliedActions,
        "blockers": report.blockers,
        "auditRecorded": report.auditRecorded,
    ]
    if let trashRelativePath = report.trashRelativePath {
        dict["trashRelativePath"] = trashRelativePath
    }
    return dict
}

func duplicateMarkdownCleanupReportToDict(_ report: CiderDuplicateMarkdownCleanupReport) -> [String: Any] {
    var dict: [String: Any] = [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "status": report.status,
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "duplicatePrefix": report.duplicatePrefix,
        "canonicalPrefix": report.canonicalPrefix,
        "candidates": report.candidates.map(duplicateMarkdownCleanupCandidateToDict),
        "blockedCandidates": report.blockedCandidates.map(duplicateMarkdownCleanupCandidateToDict),
        "applied": report.applied.map(duplicateMarkdownCleanupCandidateToDict),
        "blockers": report.blockers,
        "summary": report.summary,
        "plannedCount": report.summary["planned"] ?? 0,
        "appliedCount": report.summary["applied"] ?? 0,
        "skippedCount": report.summary["skipped"] ?? 0,
        "blockerCount": report.summary["blockers"] ?? 0,
        "safeNextCommands": report.safeNextCommands,
    ]
    if let approvalToken = report.approvalToken {
        dict["approvalToken"] = approvalToken
    }
    return dict
}

func duplicateMarkdownCleanupCandidateToDict(_ candidate: CiderDuplicateMarkdownCleanupCandidate) -> [String: Any] {
    var dict: [String: Any] = [
        "id": candidate.id,
        "duplicateRelativePath": candidate.duplicateRelativePath,
        "canonicalRelativePath": candidate.canonicalRelativePath,
        "sha256": candidate.sha256,
        "byteCount": candidate.byteCount,
        "duplicateIndexed": candidate.duplicateIndexed,
        "duplicateSQLiteOwners": candidate.duplicateSQLiteOwners.map(duplicateMarkdownSQLiteOwnerToDict),
        "reasons": candidate.reasons,
        "blockers": candidate.blockers,
        "auditRecorded": candidate.auditRecorded,
    ]
    if let canonicalItemID = candidate.canonicalItemID {
        dict["canonicalItemID"] = canonicalItemID
    }
    if let canonicalProjectID = candidate.canonicalProjectID {
        dict["canonicalProjectID"] = canonicalProjectID
    }
    if let approvalToken = candidate.approvalToken {
        dict["approvalToken"] = approvalToken
    }
    if let safeNextCommand = candidate.safeNextCommand {
        dict["safeNextCommand"] = safeNextCommand
    }
    if let trashRelativePath = candidate.trashRelativePath {
        dict["trashRelativePath"] = trashRelativePath
    }
    return dict
}

func duplicateMarkdownSQLiteOwnerToDict(_ owner: CiderDuplicateMarkdownSQLiteOwner) -> [String: Any] {
    [
        "id": owner.id,
        "type": owner.type,
        "title": owner.title,
    ]
}

func bookmarkDriftAuditReportToDict(_ report: CiderBookmarkDriftAuditReport) -> [String: Any] {
    [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "findingLimit": report.findingLimit,
        "findings": report.findings.map(bookmarkDriftFindingToDict),
    ]
}

func bookmarkDriftFindingToDict(_ finding: CiderBookmarkDriftFinding) -> [String: Any] {
    [
        "id": finding.id,
        "kind": finding.kind,
        "severity": finding.severity,
        "itemID": finding.itemID,
        "currentTitle": finding.currentTitle,
        "proposedTitle": finding.proposedTitle,
        "url": finding.url,
        "currentRelativePath": finding.currentRelativePath,
        "proposedRelativePath": finding.proposedRelativePath,
        "pathDrift": finding.pathDrift,
        "chunkDrift": finding.chunkDrift,
        "reasons": finding.reasons,
        "approvalToken": finding.approvalToken,
        "repairCommand": finding.repairCommand,
    ]
}

func activeDuplicateInvariantReportToDict(_ report: CiderActiveDuplicateInvariantReport) -> [String: Any] {
    [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "isMutating": report.isMutating,
        "status": report.status,
        "summary": report.summary,
        "duplicateFindingLimit": report.duplicateFindingLimit,
        "duplicateFindings": report.duplicateFindings.map(duplicateFindingToDict),
        "duplicateRelativePaths": report.duplicateRelativePaths.map(duplicateRelativePathFindingToDict),
        "sqliteMismatches": report.sqliteMismatches.map(storageAuditMismatchToDict),
        "vaultSQLiteMismatches": report.vaultSQLiteMismatches.map(vaultSQLitePathMismatchToDict),
    ]
}

func restartDuplicateRegressionReportToDict(_ report: CiderRestartDuplicateRegressionReport) -> [String: Any] {
    [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "isMutating": report.isMutating,
        "status": report.status,
        "passed": report.passed,
        "before": activeDuplicateInvariantReportToDict(report.before),
        "after": activeDuplicateInvariantReportToDict(report.after),
        "snapshotBefore": restartDuplicateSnapshotToDict(report.snapshotBefore),
        "snapshotAfter": restartDuplicateSnapshotToDict(report.snapshotAfter),
        "regression": restartDuplicateRegressionDeltaToDict(report.regression),
        "rebuildReconcileActions": report.rebuildReconcileActions,
    ]
}

func restartDuplicateSnapshotToDict(_ snapshot: CiderRestartDuplicateSnapshot) -> [String: Any] {
    [
        "generatedAt": ISO8601DateFormatter().string(from: snapshot.generatedAt),
        "sqliteTableCounts": snapshot.sqliteTableCounts,
        "itemCountsByType": snapshot.itemCountsByType,
        "duplicateRelativePathRowCount": snapshot.duplicateRelativePathRowCount,
        "vaultArtifactCountsByExtension": snapshot.vaultArtifactCountsByExtension,
        "vaultArtifactFingerprint": snapshot.vaultArtifactFingerprint,
    ]
}

func restartDuplicateRegressionDeltaToDict(_ delta: CiderRestartDuplicateRegressionDelta) -> [String: Any] {
    [
        "beforeIssueCount": delta.beforeIssueCount,
        "afterIssueCount": delta.afterIssueCount,
        "newIssueFingerprints": delta.newIssueFingerprints,
        "resolvedIssueFingerprints": delta.resolvedIssueFingerprints,
        "sqliteTableCountChanges": delta.sqliteTableCountChanges,
        "itemCountChangesByType": delta.itemCountChangesByType,
        "vaultArtifactCountChangesByExtension": delta.vaultArtifactCountChangesByExtension,
        "vaultArtifactFingerprintChanged": delta.vaultArtifactFingerprintChanged,
    ]
}

func duplicateFindingToDict(_ finding: VaultDuplicateAuditor.Finding) -> [String: Any] {
    [
        "id": finding.id,
        "entityType": finding.entityType.rawValue,
        "kind": finding.kind.rawValue,
        "confidence": finding.confidence.rawValue,
        "summary": finding.summary,
        "detail": finding.detail,
        "items": finding.items.map(duplicateFindingItemToDict),
    ]
}

func duplicateFindingItemToDict(_ item: VaultDuplicateAuditor.Item) -> [String: Any] {
    var dict: [String: Any] = [
        "id": item.id,
        "title": item.title,
    ]
    if let path = item.path {
        dict["path"] = path
    }
    if let value = item.value {
        dict["value"] = value
    }
    return dict
}

func duplicateRelativePathFindingToDict(_ finding: CiderDuplicateRelativePathFinding) -> [String: Any] {
    [
        "relativePath": finding.relativePath,
        "items": finding.items.map(duplicateRelativePathItemToDict),
    ]
}

func duplicateRelativePathItemToDict(_ item: CiderDuplicateRelativePathItem) -> [String: Any] {
    [
        "id": item.id,
        "type": item.type,
        "title": item.title,
    ]
}

func vaultSQLitePathMismatchToDict(_ mismatch: CiderVaultSQLitePathMismatch) -> [String: Any] {
    var dict: [String: Any] = [
        "kind": mismatch.kind,
        "relativePath": mismatch.relativePath,
        "detail": mismatch.detail,
    ]
    if let itemID = mismatch.itemID {
        dict["itemID"] = itemID
    }
    if let itemType = mismatch.itemType {
        dict["itemType"] = itemType
    }
    if let title = mismatch.title {
        dict["title"] = title
    }
    return dict
}

func bookmarkDriftRepairReportToDict(_ report: CiderBookmarkDriftRepairReport) -> [String: Any] {
    var dict: [String: Any] = [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "itemID": report.itemID,
        "status": report.status,
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "proposedRelativePath": report.proposedRelativePath,
        "plannedActions": report.plannedActions,
        "appliedActions": report.appliedActions,
        "blockers": report.blockers,
        "auditRecorded": report.auditRecorded,
    ]
    if let requiredApprovalToken = report.requiredApprovalToken {
        dict["requiredApprovalToken"] = requiredApprovalToken
    }
    if let currentTitle = report.currentTitle {
        dict["currentTitle"] = currentTitle
    }
    if let proposedTitle = report.proposedTitle {
        dict["proposedTitle"] = proposedTitle
    }
    if let currentRelativePath = report.currentRelativePath {
        dict["currentRelativePath"] = currentRelativePath
    }
    return dict
}

func storageAuditSchemaRepairReportToDict(_ report: CiderStorageAuditSchemaRepairReport) -> [String: Any] {
    [
        "command": report.command,
        "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
        "status": report.status,
        "isMutating": report.isMutating,
        "approvalRequired": report.approvalRequired,
        "requiredApprovalToken": report.requiredApprovalToken,
        "plannedActions": report.plannedActions,
        "appliedActions": report.appliedActions,
        "blockers": report.blockers,
        "repairedFindingIDs": report.repairedFindingIDs,
        "skippedFindingIDs": report.skippedFindingIDs,
        "remainingFindings": report.remainingFindings.map(storageAuditSchemaFindingToDict),
    ]
}

func storageAuditMismatchToDict(_ mismatch: CiderStorageAuditMismatch) -> [String: Any] {
    [
        "key": mismatch.key,
        "modelCount": mismatch.modelCount,
        "sqliteCount": mismatch.sqliteCount,
        "detail": mismatch.detail,
    ]
}

func bookmarkDateSuggestionResultToDict(_ result: CiderBookmarkDateSuggestionResult) -> [String: Any] {
    [
        "command": result.command,
        "bookmarkID": result.bookmarkID.uuidString,
        "bookmarkTitle": result.bookmarkTitle,
        "sourceURL": result.sourceURL,
        "count": result.suggestions.count,
        "suggestions": result.suggestions.map(bookmarkDateSuggestionToDict),
    ]
}

func bookmarkDateSuggestionToDict(_ suggestion: CiderBookmarkDateSuggestion) -> [String: Any] {
    [
        "bookmarkID": suggestion.bookmarkID.uuidString,
        "bookmarkTitle": suggestion.bookmarkTitle,
        "sourceURL": suggestion.sourceURL,
        "suggestionKey": suggestion.suggestionKey,
        "kind": suggestion.kind,
        "confidence": suggestion.confidence,
        "date": ISO8601DateFormatter().string(from: suggestion.date),
        "sourceField": suggestion.sourceField,
        "sourceSnippet": suggestion.sourceSnippet,
        "nextSafeAction": suggestion.nextSafeAction,
    ]
}

@MainActor func bookmarkDateSuggestionApprovalResultToDict(_ result: CiderBookmarkDateSuggestionApprovalResult) -> [String: Any] {
    let links: [LibraryEntityRef]
    let createdItem: [String: Any]
    if let todo = result.todo {
        var todoDict = todoToDict(todo)
        todoDict["linkedEntities"] = todo.linkedEntities.map(libraryEntityRefToDict)
        links = todo.linkedEntities
        createdItem = todoDict
    } else if let dateCard = result.dateCard {
        var dateCardDict = eventToDict(dateCard)
        dateCardDict["linkedEntities"] = dateCard.linkedEntities.map(libraryEntityRefToDict)
        links = dateCard.linkedEntities
        createdItem = dateCardDict
    } else {
        links = []
        createdItem = [:]
    }

    var dictionary: [String: Any] = [
        "command": result.command,
        "bookmarkID": result.bookmarkID.uuidString,
        "bookmarkTitle": result.bookmarkTitle,
        "sourceURL": result.sourceURL,
        "suggestion": bookmarkDateSuggestionToDict(result.suggestion),
        "action": result.action.rawValue,
        "created": result.created,
        "reused": result.reused,
        "createdItemType": result.createdItemType.rawValue,
        "createdItem": createdItem,
        "links": links.map(libraryEntityRefToDict),
    ]
    if let todo = result.todo {
        dictionary["todo"] = createdItem
        dictionary["todoID"] = todo.id.uuidString
    }
    if let dateCard = result.dateCard {
        dictionary["dateCard"] = createdItem
        dictionary["dateCardID"] = dateCard.id.uuidString
    }
    return dictionary
}

private func libraryEntityRefToDict(_ ref: LibraryEntityRef) -> [String: Any] {
    [
        "id": ref.id,
        "type": ref.type.rawValue,
        "entityID": ref.entityID.uuidString,
    ]
}

@MainActor func contactToDict(_ contact: ContactCard) -> [String: Any] {
    var d: [String: Any] = [
        "id": contact.id.uuidString,
        "displayName": contact.displayName,
        "created": ISO8601DateFormatter().string(from: contact.createdAt),
        "labelIDs": contact.labelIDs.map(\.uuidString),
        "folder": contact.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
    ]
    if !contact.email.isEmpty { d["email"] = contact.email }
    if !contact.phone.isEmpty { d["phone"] = contact.phone }
    if !contact.address.isEmpty { d["address"] = contact.address }
    if !contact.notes.isEmpty { d["notes"] = contact.notes }
    if !contact.relationshipLabel.isEmpty { d["relationship"] = contact.relationshipLabel }
    if let birthday = contact.birthday { d["birthday"] = ISO8601DateFormatter().string(from: birthday) }
    if !contact.linkedEntities.isEmpty {
        d["linkedEntities"] = contact.linkedEntities.map { ref in
            [
                "type": ref.type.rawValue,
                "id": ref.entityID.uuidString
            ]
        }
    }
    if !contact.customFields.isEmpty {
        d["fields"] = contact.customFields.map { field in
            [
                "id": field.id.uuidString,
                "section": field.section,
                "label": field.label,
                "value": field.value,
                "kind": field.kind.rawValue,
                "pinned": field.isPinned
            ] as [String: Any]
        }
    }
    return d
}

@MainActor func vaultFileToDict(_ file: VaultFile) -> [String: Any] {
    var d: [String: Any] = [
        "id": file.id.uuidString,
        "filename": file.filename,
        "displayTitle": file.displayTitle,
        "fileType": file.fileType.rawValue,
        "fileSize": file.fileSize,
        "relativePath": file.relativePath,
        "folder": file.folderID.flatMap { VaultFolderService.shared.folder(for: $0)?.name } ?? "Inbox",
        "labelIDs": file.labelIDs.map(\.uuidString),
        "tags": file.tags,
        "notes": file.notes,
        "created": ISO8601DateFormatter().string(from: file.createdAt),
        "modified": ISO8601DateFormatter().string(from: file.modifiedAt),
    ]
    if let title = file.title { d["title"] = title }
    if let ocr = file.ocrText { d["ocrText"] = ocr }
    if let colors = file.dominantColors { d["dominantColors"] = colors }
    return d
}

@MainActor func folderToDict(_ folder: VaultFolder) -> [String: Any] {
    [
        "id": folder.id.uuidString,
        "name": folder.name,
        "relativePath": folder.relativePath,
        "created": ISO8601DateFormatter().string(from: folder.createdAt),
    ]
}

@MainActor func labelToDict(_ label: CardLabel) -> [String: Any] {
    [
        "id": label.id.uuidString,
        "name": label.name,
        "colorHex": label.colorHex,
        "created": ISO8601DateFormatter().string(from: label.createdAt),
    ]
}

@MainActor func boardToDict(_ board: KanbanBoard) -> [String: Any] {
    [
        "id": board.id,
        "name": board.name,
        "created": ISO8601DateFormatter().string(from: board.created),
        "columns": board.columns.map { col in
            [
                "id": col.id,
                "name": col.name,
                "isDoneColumn": col.isDoneColumn,
                "isDoneLikeColumn": col.isDoneLikeColumn,
                "cards": col.cards.map { card in
                    var d: [String: Any] = [
                        "id": card.id,
                        "title": card.title,
                        "created": ISO8601DateFormatter().string(from: card.created),
                    ]
                    appendKanbanCardHandoffFields(card, to: &d)
                    if let notes = card.notes { d["notes"] = notes }
                    if let color = card.color { d["color"] = color.rawValue }
                    if let priority = card.priority { d["priority"] = priority.rawValue }
                    if let agent = card.agent { d["agent"] = agent }
                    if !card.tags.isEmpty { d["tags"] = card.tags }
                    if let parentCardID = card.parentCardID { d["parentCardID"] = parentCardID }
                    if let completed = card.completed { d["completed"] = ISO8601DateFormatter().string(from: completed) }
                    return d
                },
            ] as [String: Any]
        },
    ]
}

@MainActor private func appendKanbanCardHandoffFields(_ card: KanbanCard, to dict: inout [String: Any]) {
    if let aiSummary = card.aiSummary, !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        dict["aiSummary"] = aiSummary
    }
    if !card.relatedCardIDs.isEmpty {
        dict["relatedCardIDs"] = card.relatedCardIDs
    }
    if !card.linkedEntities.isEmpty {
        dict["linkedEntities"] = card.linkedEntities.map { ref in
            [
                "id": ref.id,
                "type": ref.type.rawValue,
                "entityID": ref.entityID.uuidString,
            ]
        }
    }
    if !card.historyEntries.isEmpty {
        dict["historyEntries"] = card.historyEntries.map { entry in
            var entryDict: [String: Any] = [
                "id": entry.id,
                "type": entry.type.rawValue,
                "body": entry.body,
                "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
            ]
            if let author = entry.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entryDict["author"] = author
            }
            return entryDict
        }
    }
    if !card.comments.isEmpty {
        dict["comments"] = card.comments.map { comment in
            var commentDict: [String: Any] = [
                "id": comment.id,
                "permalinkID": comment.permalinkID,
                "kind": comment.kind.rawValue,
                "body": comment.body,
                "createdAt": ISO8601DateFormatter().string(from: comment.createdAt),
                "isResolved": comment.isResolved,
            ]
            if let author = comment.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["author"] = author
            }
            if let source = comment.source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["source"] = source
            }
            if let parentCommentID = comment.parentCommentID, !parentCommentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["parentCommentID"] = parentCommentID
            }
            if let resolvedAt = comment.resolvedAt {
                commentDict["resolvedAt"] = ISO8601DateFormatter().string(from: resolvedAt)
            }
            if let resolvedBy = comment.resolvedBy, !resolvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commentDict["resolvedBy"] = resolvedBy
            }
            return commentDict
        }
        dict["commentCount"] = card.comments.count
    }
}

@MainActor func kanbanAgentWorkflowSummaryToDict(_ summary: KanbanAgentWorkflowSummary) -> [String: Any] {
    [
        "boardID": summary.boardID,
        "boardName": summary.boardName,
        "agents": summary.agentNames,
        "lanes": summary.laneSummaries.map { lane in
            [
                "role": lane.role.rawValue,
                "columnID": lane.columnID,
                "columnName": lane.columnName,
                "cardCount": lane.count,
                "cards": lane.cards.map { card in
                    var d: [String: Any] = [
                        "id": card.id,
                        "title": card.title,
                        "created": ISO8601DateFormatter().string(from: card.created),
                    ]
                    appendKanbanCardHandoffFields(card, to: &d)
                    if let priority = card.priority { d["priority"] = priority.rawValue }
                    if let agent = card.agent { d["agent"] = agent }
                    if !card.tags.isEmpty { d["tags"] = card.tags }
                    if let parentCardID = card.parentCardID { d["parentCardID"] = parentCardID }
                    if let completed = card.completed { d["completed"] = ISO8601DateFormatter().string(from: completed) }
                    return d
                },
            ] as [String: Any]
        },
        "nextImplementationCards": summary.nextImplementationCards.map(\.id),
        "backlogCards": summary.backlogCards.map(\.id),
        "activeAgentCards": summary.activeAgentCards.map(\.id),
        "testingCards": summary.testingCards.map(\.id),
        "needsFixCards": summary.needsFixCards.map(\.id),
        "completedCards": summary.completedCards.map(\.id),
        "automationActions": summary.automationActions.map(kanbanAgentWorkflowActionToDict),
    ]
}

@MainActor private func kanbanAgentWorkflowActionToDict(_ action: KanbanAgentWorkflowAction) -> [String: Any] {
    var dict: [String: Any] = [
        "id": action.id,
        "cardID": action.cardID,
        "cardTitle": action.cardTitle,
        "sourceColumnID": action.sourceColumnID,
        "sourceColumnName": action.sourceColumnName,
        "action": action.action.rawValue,
        "label": action.label,
        "reason": action.reason,
        "requiresApproval": action.requiresApproval,
        "safeCommands": action.safeCommands,
    ]
    if let destinationColumnID = action.destinationColumnID {
        dict["destinationColumnID"] = destinationColumnID
    }
    if let destinationColumnName = action.destinationColumnName {
        dict["destinationColumnName"] = destinationColumnName
    }
    return dict
}

@MainActor func kanbanTestingTriageSummaryToDict(_ summary: KanbanTestingTriageSummary) -> [String: Any] {
    [
        "boardID": summary.boardID,
        "boardName": summary.boardName,
        "counts": [
            "total": summary.items.count,
            "needsErik": summary.needsErik.count,
            "agentCanVerify": summary.agentCanVerify.count,
            "mixed": summary.mixed.count,
        ],
        "needsErik": summary.needsErik.map(kanbanTestingTriageItemToDict),
        "agentCanVerify": summary.agentCanVerify.map(kanbanTestingTriageItemToDict),
        "mixed": summary.mixed.map(kanbanTestingTriageItemToDict),
        "items": summary.items.map { item in
            kanbanTestingTriageItemToDict(item)
        },
    ]
}

@MainActor private func kanbanTestingTriageItemToDict(_ item: KanbanTestingTriageSummary.Item) -> [String: Any] {
    var dict: [String: Any] = [
        "id": item.card.id,
        "title": item.card.title,
        "columnID": item.columnID,
        "columnName": item.columnName,
        "owner": item.owner.rawValue,
        "ownerLabel": item.owner.displayName,
        "reason": item.reason,
        "whatChanged": item.whatChanged,
        "testEvidence": item.testEvidence,
        "agentVerificationSteps": item.agentVerificationSteps,
        "manualQASteps": item.manualQASteps,
        "failedQASteps": item.failedQASteps,
    ]
    if let priority = item.card.priority { dict["priority"] = priority.rawValue }
    if let parentCardID = item.card.parentCardID { dict["parentCardID"] = parentCardID }
    if let parentTitle = item.parentTitle { dict["parentTitle"] = parentTitle }
    if !item.card.tags.isEmpty { dict["tags"] = item.card.tags }
    return dict
}

@MainActor func dashboardTopicToDict(_ topic: DashboardTopic) -> [String: Any] {
    let contract = topic.secondBrainContract
    var dict: [String: Any] = [
        "id": topic.ciderSyncId,
        "title": topic.title,
        "position": topic.position,
        "createdAt": topic.createdAt,
        "updatedAt": topic.updatedAt,
        "authority": contract.authority.rawValue,
        "secondBrainTruth": contract.isSecondBrainTruth,
        "homePrimaryReadModel": contract.homePrimaryReadModel,
        "safeGraphCommands": contract.safeGraphCommands,
    ]
    if let icon = topic.icon { dict["icon"] = icon }
    if let colorToken = topic.colorToken { dict["colorToken"] = colorToken }
    if let isPinned = topic.isPinned { dict["isPinned"] = isPinned }
    if let isArchived = topic.isArchived { dict["isArchived"] = isArchived }
    if let deleted = topic.deleted { dict["deleted"] = deleted }
    if let deletedAt = topic.deletedAt { dict["deletedAt"] = deletedAt }
    return dict
}

@MainActor func dashboardCardToDict(_ card: DashboardCard) -> [String: Any] {
    let contract = card.secondBrainContract
    var dict: [String: Any] = [
        "id": card.ciderSyncId,
        "topicSyncIds": card.topicSyncIds,
        "title": card.title,
        "summary": card.summary,
        "sourceKind": card.sourceKind.rawValue,
        "status": card.status.rawValue,
        "priority": card.priority.rawValue,
        "createdAt": card.createdAt,
        "updatedAt": card.updatedAt,
        "authority": contract.authority.rawValue,
        "secondBrainTruth": contract.isSecondBrainTruth,
        "homePrimaryReadModel": contract.homePrimaryReadModel,
        "safeGraphCommands": contract.safeGraphCommands,
    ]
    if let subtitle = card.subtitle { dict["subtitle"] = subtitle }
    if let whyItMatters = card.whyItMatters { dict["whyItMatters"] = whyItMatters }
    if let sourceURL = card.sourceURL { dict["sourceURL"] = sourceURL }
    if let sourceTitle = card.sourceTitle { dict["sourceTitle"] = sourceTitle }
    if let relatedItemSyncId = card.relatedItemSyncId { dict["relatedItemSyncId"] = relatedItemSyncId }
    if let relatedItemType = card.relatedItemType { dict["relatedItemType"] = relatedItemType }
    if let score = card.score { dict["score"] = score }
    if let feedback = card.feedback {
        var feedbackDict: [String: Any] = ["updatedAt": feedback.updatedAt]
        if let rating = feedback.rating { feedbackDict["rating"] = rating }
        if let moreLikeThis = feedback.moreLikeThis { feedbackDict["moreLikeThis"] = moreLikeThis }
        if let lessLikeThis = feedback.lessLikeThis { feedbackDict["lessLikeThis"] = lessLikeThis }
        if let notInterested = feedback.notInterested { feedbackDict["notInterested"] = notInterested }
        if let note = feedback.note { feedbackDict["note"] = note }
        dict["feedback"] = feedbackDict
    }
    if let lastSeenAt = card.lastSeenAt { dict["lastSeenAt"] = lastSeenAt }
    if let dismissedAt = card.dismissedAt { dict["dismissedAt"] = dismissedAt }
    if let deleted = card.deleted { dict["deleted"] = deleted }
    if let deletedAt = card.deletedAt { dict["deletedAt"] = deletedAt }
    return dict
}

@MainActor func clipboardItemToDict(_ item: ClipboardItem) -> [String: Any] {
    var d: [String: Any] = [
        "id": item.id.uuidString,
        "type": item.type.rawValue,
        "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
        "isSaved": item.isSaved,
    ]
    if let text = item.textContent { d["textContent"] = text }
    if let app = item.sourceAppName { d["sourceApp"] = app }
    if let savedID = item.savedItemID { d["savedItemID"] = savedID.uuidString }
    return d
}

@MainActor func trashItemToDict(_ item: TrashItem) -> [String: Any] {
    [
        "id": item.id.uuidString,
        "itemID": item.itemID.uuidString,
        "type": item.itemType.rawValue,
        "title": item.title,
        "deletedAt": ISO8601DateFormatter().string(from: item.deletedAt),
        "folderID": item.originalFolderID?.uuidString as Any,
    ]
}

@MainActor func searchResultToDict(_ result: SearchResult) -> [String: Any] {
    var d: [String: Any] = [
        "id": result.id.uuidString,
        "type": "\(result.type)",
        "title": result.title,
        "date": ISO8601DateFormatter().string(from: result.date),
    ]
    if let subtitle = result.subtitle { d["subtitle"] = subtitle }
    return d
}

@MainActor func doctorReportToDict(_ report: VaultDoctor.Report) -> [String: Any] {
    let iso = ISO8601DateFormatter()
    let countsByKey: [String: Int] = Dictionary(uniqueKeysWithValues: report.counts.map { ($0.key.rawValue, $0.value) })
    return [
        "startedAt": iso.string(from: report.startedAt),
        "finishedAt": iso.string(from: report.finishedAt),
        "counts": countsByKey,
        "fixableCount": report.fixableCount,
        "findings": report.findings.map(doctorFindingToDict),
    ]
}

@MainActor func doctorFindingToDict(_ f: VaultDoctor.Finding) -> [String: Any] {
    var d: [String: Any] = [
        "id": f.id,
        "kind": f.kind.rawValue,
        "severity": f.severity.rawValue,
        "summary": f.summary,
        "detail": f.detail,
        "isFixable": f.isFixable,
    ]
    if let label = f.fixLabel { d["fixLabel"] = label }
    if let fid = f.payload.folderID { d["folderID"] = fid.uuidString }
    if let iid = f.payload.itemID { d["itemID"] = iid.uuidString }
    if let sid = f.payload.sessionID { d["sessionID"] = sid.uuidString }
    if let rp = f.payload.relativePath { d["relativePath"] = rp }
    if let bc = f.payload.breadcrumbFile { d["breadcrumbFile"] = bc }
    return d
}

@MainActor func statusToDict() -> [String: Any] {
    [
        "bookmarks": VaultBookmarkService.shared.bookmarks.count,
        "notes": NotesStorage.shared.notes.count,
        "todos": TodoCardStorage.shared.todoCards.count,
        "todosActive": TodoCardStorage.shared.todoCards.filter { !$0.isCompleted }.count,
        "events": DateCardStorage.shared.dateCards.count,
        "contacts": ContactStorage.shared.contacts.count,
        "vaultFiles": VaultFileService.shared.files.count,
        "vaultFilesImages": VaultFileService.shared.files.filter { $0.fileType == .image }.count,
        "folders": VaultFolderService.shared.folders.count,
        "labels": CardLabelStorage.shared.labels.count,
        "boards": KanbanStorage.shared.boards.count,
        "boardCards": KanbanStorage.shared.boards.flatMap(\.columns).flatMap(\.cards).count,
        "trash": TrashStorage.shared.allTrashItems().count,
        "vaultRoot": StoragePaths.cachedVaultDirectoryURL.path,
    ]
}

func dueToSurfaceFeedToDict(_ feed: CiderDueToSurfaceFeed) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    return [
        "ok": true,
        "command": feed.command,
        "generatedAt": formatter.string(from: feed.generatedAt),
        "readOnly": feed.readOnly,
        "changed": feed.changed,
        "count": feed.candidates.count,
        "countsByFamily": feed.countsByFamily,
        "truthBoundary": "reviewable_candidate_not_truth",
        "candidates": feed.candidates.map { dueToSurfaceCandidateToDict($0, formatter: formatter) },
        "safeNextCommands": feed.safeNextCommands,
    ]
}

func dueToSurfaceCandidateToDict(_ candidate: CiderDueToSurfaceCandidate, formatter: ISO8601DateFormatter) -> [String: Any] {
    var dict: [String: Any] = [
        "id": candidate.id,
        "family": candidate.family.rawValue,
        "owner": [
            "ownerType": candidate.owner.ownerType,
            "ownerID": candidate.owner.ownerID,
            "ref": candidate.owner.canonicalRef,
        ],
        "title": candidate.title,
        "itemType": candidate.itemType,
        "whyNow": candidate.whyNow,
        "reasonCodes": candidate.reasonCodes,
        "urgency": candidate.urgency,
        "confidence": candidate.confidence,
        "reviewState": candidate.reviewState,
        "truthBoundary": candidate.truthBoundary,
        "score": candidate.score,
        "sourceRefs": candidate.sourceRefs,
        "citedEvidence": candidate.citedEvidence.map(dueToSurfaceEvidenceToDict),
        "safeNextCommands": candidate.safeNextCommands,
        "window": dueToSurfaceWindowToDict(candidate.window, formatter: formatter),
    ]
    if candidate.truthBoundary == "reviewable_candidate_not_truth" {
        dict["needsReview"] = true
        dict["acceptedTruth"] = false
    }
    return dict
}

func dueToSurfaceWindowToDict(_ window: CiderDueToSurfaceWindow, formatter: ISO8601DateFormatter) -> [String: Any] {
    var dict: [String: Any] = ["label": window.label]
    if let startsAt = window.startsAt { dict["startsAt"] = formatter.string(from: startsAt) }
    if let endsAt = window.endsAt { dict["endsAt"] = formatter.string(from: endsAt) }
    return dict
}

func dueToSurfaceEvidenceToDict(_ evidence: CiderDueToSurfaceEvidence) -> [String: Any] {
    var dict: [String: Any] = [
        "ref": evidence.ref,
        "kind": evidence.kind,
        "summary": evidence.summary,
        "metadata": evidence.metadata,
    ]
    if let sourceOwnerRef = evidence.sourceOwnerRef { dict["sourceOwnerRef"] = sourceOwnerRef }
    if let candidateRef = evidence.candidateRef { dict["candidateRef"] = candidateRef }
    return dict
}
