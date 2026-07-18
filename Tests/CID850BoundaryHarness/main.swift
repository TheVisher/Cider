import CID850Interpose
import CryptoKit
import Darwin
import Foundation
import SQLite3
@testable import Cider

private struct BoundaryResult: Encodable {
    let didMutation: Bool
    let created: Bool
    let verified: Bool
    let usable: Bool
    let failureKind: String?
    let heldExists: Bool
    let retainedVerified: Bool
    let sourceUnchanged: Bool
    let priorUnchanged: Bool
    let sourceFingerprint: [String: String]
    let priorFingerprint: [String: String]
    let policyAppendOnly: Bool
    let policyArtifactCount: Int
    let receiptNamesHeldArtifact: Bool
    let replacementMatchesHeld: Bool
    let replacementStayedAtSource: Bool
    let useSucceeded: Bool
    let destinationExists: Bool
}

@MainActor
private func runBoundary(_ boundary: String) throws -> BoundaryResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-boundary-harness-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let priorArtifact = try service.createRollingBackup(reason: "boundary-prior", database: database)
    let prior = service.rollingBackupsDirectory(for: databaseURL).appendingPathComponent(
        priorArtifact.packageName,
        isDirectory: true
    )
    if boundary == "retention" {
        for index in 0..<7 {
            _ = try service.createRollingBackup(
                reason: "boundary-retention-\(index)",
                database: database
            )
        }
    }
    let priorBefore = try fingerprintTree(prior)
    let sourceBefore = try sqliteSetFingerprint(databaseURL)
    let heldName: String
    cid850_interpose_reset()
    switch boundary {
    case "staging":
        heldName = ".cid850-held-package-template"
        cid850_interpose_replace_after_mkdirat(".cid850-package-template", heldName)
    case "publication":
        heldName = ".cid850-held-created-publication.ciderbackup"
        cid850_interpose_replace_after_fclonefileat(".ciderbackup", heldName)
    case "publication-source":
        heldName = ".cid850-held-publication-source.staging"
        cid850_interpose_replace_before_renameatx_np(".staging", heldName)
    case "append-restore":
        heldName = ".cid850-unused"
        cid850_interpose_fail_append_guard_restoration()
    case "use":
        heldName = ".cid850-held-use.ciderbackup"
        cid850_interpose_replace_before_lseek("/database.sqlite", heldName, 4)
    case "retention":
        heldName = ".cid850-held-retention.ciderbackup"
        cid850_interpose_replace_before_renameatx_np(".ciderbackup", heldName)
    default:
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    var receipt = DatabaseSafetyService.failedCreationReceipt(
        for: .verification("No creation receipt for a qualified-use boundary.")
    )
    var useSucceeded = false
    let useDestination = root.appendingPathComponent("materialized-use.db")
    if boundary == "use" {
        do {
            try service.materializeVerifiedBackupDatabase(
                from: priorArtifact,
                at: useDestination
            )
            useSucceeded = true
        } catch {
            receipt = DatabaseSafetyService.failedCreationReceipt(
                for: .verification(error.localizedDescription)
            )
        }
    } else {
        receipt = service.createManualBackup(database: database)
    }
    let policyURL = service.rollingBackupsDirectory(for: databaseURL)
    let didMutation = cid850_interpose_did_mutation()
    var policyStat = stat()
    let inspectedPolicy = lstat(policyURL.path, &policyStat) == 0
    let policyAppendOnly = inspectedPolicy && policyStat.st_flags & UInt32(UF_APPEND) != 0
    cid850_interpose_reset()
    if policyAppendOnly {
        _ = chflags(policyURL.path, policyStat.st_flags & ~UInt32(UF_APPEND))
    }
    let heldURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(heldName, isDirectory: true)
    let policyArtifacts = try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: nil,
        options: []
    )
    let observedReceiptURL = receipt.backupURL ?? receipt.artifactName.map {
        policyURL.appendingPathComponent($0, isDirectory: true)
    }
    let receiptNamesHeldArtifact = observedReceiptURL?.standardizedFileURL == heldURL.standardizedFileURL
    let replacementCandidates = policyArtifacts.filter {
        $0.pathExtension == "ciderbackup"
            && $0.lastPathComponent != prior.lastPathComponent
            && $0.lastPathComponent != heldName
    }
    let replacementMatchesHeld: Bool
    if boundary == "publication", replacementCandidates.count == 1 {
        replacementMatchesHeld = try fingerprintTree(heldURL) == fingerprintTree(replacementCandidates[0])
    } else {
        replacementMatchesHeld = false
    }
    let replacementStayedAtSource = policyArtifacts.contains {
        $0.lastPathComponent.hasSuffix(".staging") && $0.lastPathComponent != heldName
    }
    let sourceAfter = try sqliteSetFingerprint(databaseURL)
    let priorAfter = try fingerprintTree(prior)
    return BoundaryResult(
        didMutation: didMutation,
        created: receipt.created,
        verified: receipt.verified,
        usable: receipt.usable,
        failureKind: receipt.failureKind?.rawValue,
        heldExists: FileManager.default.fileExists(atPath: heldURL.path),
        retainedVerified: observedReceiptURL.map { service.verifyBackup(at: $0).isVerified } ?? false,
        sourceUnchanged: sourceAfter == sourceBefore,
        priorUnchanged: priorAfter == priorBefore,
        sourceFingerprint: sourceAfter,
        priorFingerprint: priorAfter,
        policyAppendOnly: policyAppendOnly,
        policyArtifactCount: policyArtifacts.count,
        receiptNamesHeldArtifact: receiptNamesHeldArtifact,
        replacementMatchesHeld: replacementMatchesHeld,
        replacementStayedAtSource: replacementStayedAtSource,
        useSucceeded: useSucceeded,
        destinationExists: FileManager.default.fileExists(atPath: useDestination.path)
    )
}

private struct SharedCreationResult: Encodable {
    let created: Bool
    let verified: Bool
    let usable: Bool
    let failureKind: String?
}

private struct AggregateGrowthResult: Encodable {
    let didMutation: Bool
    let writerSucceeded: Bool
    let failureKind: String?
    let created: Bool
    let verified: Bool
    let usable: Bool
    let retainedDatabaseBytes: Int64
    let retainedManifestBytes: Int64
    let accountedPolicyBytes: Int64
    let policyCap: Int64
    let repeatedFailureKind: String?
    let repeatedRefusalCreatedNoArtifact: Bool
}

private struct AggregateCloneRaceResult: Encodable {
    let mutationsCompleted: Int
    let failureKinds: [String?]
    let everyAttemptFailed: Bool
    let sourceUnchanged: Bool
    let priorUnchanged: Bool
    let exactInventoryUnchanged: Bool
    let exactLedgerUnchanged: Bool
    let accountedPolicyBytes: Int64
    let policyCap: Int64
    let noDuplicateStageOrPublication: Bool
}

private struct RestoreSidecarResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let databaseRolledBack: Bool
    let unexpectedOccupantPreserved: Bool
    let quarantinedOriginalPreserved: Bool
    let reopened: Bool
    let sqliteOpenCallbackCount: Int32
}

private struct RestoreV2InterruptionResult: Encodable {
    let restoreStatus: Int32
    let reconciliationStatus: Int32
    let firstReconciliation: String
    let secondReconciliation: String
    let sourceUnchanged: Bool
    let parentIdentityUnchanged: Bool
    let canonicalRecordAbsent: Bool
    let hiddenMemberCount: Int
    let repeatedFingerprintExact: Bool
    let destinationExists: Bool
    let liveNamespaceCoherent: Bool
    let integrityHealthy: Bool
    let retainedUnlinkAttempts: Int32
}

private struct RestorePlannedUnknownResult: Encodable {
    let childStatus: Int32
    let firstRecoveryRequired: Bool
    let secondRecoveryRequired: Bool
    let replacementIdentityExact: Bool
    let replacementBytesExact: Bool
    let completeFingerprintExact: Bool
    let transactionRemainsPlanned: Bool
    let transactionClaimsNoStagedIdentity: Bool
    let sourceUnchanged: Bool
}

private struct RestorePlannedFIFOResult: Encodable {
    let childStatus: Int32
    let firstReturnedPromptly: Bool
    let secondReturnedPromptly: Bool
    let firstRecoveryRequired: Bool
    let secondRecoveryRequired: Bool
    let fifoIdentityAndTypeExact: Bool
    let canonicalStateExact: Bool
    let repeatedFingerprintExact: Bool
    let sourceUnchanged: Bool
}

private struct PackageSpecialMemberResult: Encodable {
    let kind: String
    let member: String
    let listRejected: Bool
    let directVerificationRejected: Bool
    let urlMaterializationRejected: Bool
    let qualifiedMaterializationRejected: Bool
    let liveRestoreRejected: Bool
    let specialIdentityAndTypeExact: Bool
    let otherMemberExact: Bool
    let liveDatabaseExact: Bool
}

private struct RawSpecialMemberResult: Encodable {
    let kind: String
    let listRejected: Bool
    let directVerificationRejected: Bool
    let urlMaterializationRejected: Bool
    let liveRestoreRejected: Bool
    let specialIdentityAndTypeExact: Bool
    let liveDatabaseExact: Bool
}

private struct TerminalEvidenceResult: Encodable {
    let evidenceCount: Int
    let unlinkAttempts: Int32
    let evidenceNonselectable: Bool
    let evidenceNonmaterializable: Bool
    let evidenceNonrestorable: Bool
    let firstReconciliation: String
    let secondReconciliation: String
    let repeatedFingerprintExact: Bool
    let capacityRefusedBeforeMutation: Bool
    let hardByteCapacityRefusedBeforeMutation: Bool
}

private struct HeldDescriptorEvidenceResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let unlinkAttempts: Int32
    let retainedNameReachesDescriptorBytes: Bool
    let repeatedRecoveryRequired: Bool
    let repeatedFingerprintExact: Bool
}

private struct RetentionCollisionResult: Encodable {
    let attack: String
    let didMutation: Bool
    let restoreFailed: Bool
    let unlinkAttempts: Int32
    let retainedEvidencePresent: Bool
    let sourceReoccupationPresent: Bool
}

private struct RecordRemovalReoccupationResult: Encodable {
    let didMutation: Bool
    let reconciliationRecoveryRequired: Bool
    let recordBytesPreserved: Bool
    let occupantBytesExact: Bool
    let inventoryReoccupied: Bool
    let repeatedRecoveryRequired: Bool
    let fixedGraphNamesExact: Bool
    let sourceUnchanged: Bool
    let liveDatabaseExact: Bool
}

private struct RestoreMalformedGraphResult: Encodable {
    let variantCount: Int
    let rejectedCount: Int
    let completeFingerprintsExact: Bool
    let canonicalStateBytesExact: Bool
}

private struct RestoreMemberSeamResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let firstRecoveryRequired: Bool
    let secondRecoveryRequired: Bool
    let changedMemberPreserved: Bool
    let sourceReplacementPreserved: Bool
    let distinctPreservedIdentities: Bool
    let cleanupSourcePreserved: Bool
    let destinationOccupantPreserved: Bool
    let repeatedFingerprintExact: Bool
    let sourceUnchanged: Bool
    let retainedUnlinkAttempts: Int32
}

private struct RestoreFsyncResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let originalSQLiteSetRestored: Bool
    let replacementRetained: Bool
    let recoveryRequired: Bool
    let recoveryArtifactVerified: Bool
    let recoverySelector: String?
    let unexpectedOccupantsPreserved: Bool
    let reopened: Bool
    let failureMessage: String
    let originalFingerprint: [String: String]
    let finalFingerprint: [String: String]
}

private struct RestoreCrashFixture: Codable {
    let originalFingerprint: [String: String]
    let sourcePackageName: String
    let sourceFingerprint: [String: String]
}

private struct RestoreCrashResult: Encodable {
    let childStatus: Int32
    let reconciliationState: String
    let repeatedState: String
    let exactOriginalRestored: Bool
    let sourceUnchanged: Bool
    let physicallyReopened: Bool
    let integrityHealthy: Bool
    let hiddenRestoreArtifactCount: Int
    let repeatedFingerprintExact: Bool
    let originalFingerprint: [String: String]
    let finalFingerprint: [String: String]
}

private struct RestoreSameFileChangeResult: Encodable {
    let childStatus: Int32
    let firstRecoveryRequired: Bool
    let repeatedRecoveryRequired: Bool
    let sameInodeChangedContentPreserved: Bool
    let journalPreserved: Bool
    let sourceUnchanged: Bool
    let hiddenFingerprintAfterFirst: [String: String]
    let hiddenFingerprintAfterSecond: [String: String]
}

private struct RestoreRecordRemovalSyncResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let recoveryRequired: Bool
    let journalAbsentAfterFailure: Bool
    let registrationPresentAfterFailure: Bool
    let reconciliationState: String
    let repeatedState: String
    let registrationClearedAfterReconciliation: Bool
    let sourceUnchanged: Bool
    let physicallyReopened: Bool
    let integrityHealthy: Bool
    let hiddenRestoreArtifactCount: Int
}

private struct RestoreValidationFailureResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let recoveryRequired: Bool
    let exactOriginalRestored: Bool
    let exactOriginalRetained: Bool
    let sourceUnchanged: Bool
    let recoveryArtifactNamedByError: Bool
    let rollbackArtifactVerified: Bool
    let rollbackSelector: String?
    let physicallyReopened: Bool
    let integrityHealthy: Bool
    let failureMessage: String
    let originalFingerprint: [String: String]
    let finalFingerprint: [String: String]
}

private struct RestoreAuthorityResult: Encodable {
    let restored: Bool
    let integrityHealthy: Bool
    let exclusiveAcquisitions: Int32
    let releases: Int32
}

private struct RestoreArchitectureResult: Encodable {
    let restored: Bool
    let integrityHealthy: Bool
    let legacyMetadataWrites: Int32
    let canonicalMetadataWrites: Int32
    let parentReopensAfterLock: Int32
}

private struct RestoreFinalCapabilityResult: Encodable {
    let didMutation: Bool
    let restoreFailed: Bool
    let recoveryRequired: Bool
    let sourceMoved: Bool
    let parentReplaced: Bool
    let hiddenRecoveryRetained: Bool
    let firstReconciliation: String
    let secondReconciliation: String
    let physicallyReopened: Bool
    let integrityHealthy: Bool
}

private struct ReceiptSpecialResult: Encodable {
    let completedWithoutWriter: Bool
    let rejected: Bool
}

private struct QualifiedReceiptRaceResult: Encodable {
    let action: String
    let didMutation: Bool
    let receiptUnusable: Bool
    let returnedPromptly: Bool
    let liveDatabaseExact: Bool
    let manifestExact: Bool
    let originalMemberPreserved: Bool
    let visibleMemberDifferentInode: Bool
}

@MainActor
private func runRestoreSidecarBoundary(_ boundary: String) throws -> RestoreSidecarResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-restore-sidecar-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        cid851_reset_sqlite_open_sidecar()
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let backup = try service.createRollingBackup(reason: "sidecar-source", database: database)
    let backupURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(backup.packageName, isDirectory: true)
    let absentDestination = boundary == "restore-sidecar-at-open-absent-wal"
    var writer: OpaquePointer?
    defer { sqlite3_close_v2(writer) }
    if absentDestination {
        database.close()
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    } else {
        try database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('live-after-backup', 'Live', '#775533', 'custom', 1, 1);
            """)

        guard sqlite3_open_v2(
            databaseURL.path,
            &writer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let writer else {
            sqlite3_close_v2(writer)
            throw CocoaError(.fileReadCorruptFile)
        }
        try execute(writer, "PRAGMA journal_mode=WAL;")
        try execute(writer, "BEGIN IMMEDIATE;")
        try execute(writer, "COMMIT;")
    }
    let before = try sqliteSetFingerprint(databaseURL)
    let boundarySuffix: String
    cid850_interpose_reset()
    switch boundary {
    case "restore-sidecar-before-wal":
        boundarySuffix = "-wal"
        cid850_interpose_create_sidecar_before_swap("cider.db", boundarySuffix)
    case "restore-sidecar-after-shm":
        boundarySuffix = "-shm"
        cid850_interpose_create_sidecar_after_swap("cider.db", boundarySuffix)
    case "restore-sidecar-at-open-wal", "restore-sidecar-at-open-absent-wal":
        boundarySuffix = "-wal"
        cid851_install_sidecar_at_sqlite_open(
            databaseURL.path,
            backupURL.appendingPathComponent("database.sqlite").path,
            boundarySuffix
        )
    default:
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    var restoreFailed = false
    do {
        _ = try service.restoreRollingBackup(
            from: backupURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
    }
    let didMutation = cid850_interpose_did_mutation()
    let sqliteOpenCallbackCount = cid851_sqlite_open_callback_count()
    cid850_interpose_reset()
    let unexpectedURL = URL(fileURLWithPath: databaseURL.path + boundarySuffix)
    let expectedMarker = Data("cid850-unexpected-sidecar".utf8)
    let hiddenCandidates = (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ))?.filter {
        ($0.lastPathComponent.hasPrefix(".cid850-restore-")
            || $0.lastPathComponent.hasPrefix(".cid851-restore-"))
            && $0.lastPathComponent.hasSuffix(boundarySuffix)
    } ?? []
    let originalHash = before[String(boundarySuffix.dropFirst())]
    let markerOccupantPreserved = (try? Data(contentsOf: unexpectedURL)) == expectedMarker
    let validSQLiteURLs = hiddenCandidates + [unexpectedURL]
    let validSQLiteOccupantPreserved = validSQLiteURLs.contains { candidate in
        guard let bytes = try? Data(contentsOf: candidate), bytes.count >= 32 else { return false }
        let magic = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return magic == 0x377f0682 || magic == 0x377f0683
    }
    let unexpectedOccupantPreserved = boundary.hasPrefix("restore-sidecar-at-open")
        ? validSQLiteOccupantPreserved
        : markerOccupantPreserved
    let hiddenOriginalPreserved = hiddenCandidates.contains { candidate in
        guard let data = try? Data(contentsOf: candidate) else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == originalHash
    }
    let liveOriginalPreserved = (try? Data(contentsOf: unexpectedURL)).map {
        SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
    } == originalHash
    let quarantinedOriginalPreserved = boundary.hasPrefix("restore-sidecar-at-open")
        ? liveOriginalPreserved
        : hiddenOriginalPreserved
    let databaseRolledBack = absentDestination
        ? !FileManager.default.fileExists(atPath: databaseURL.path)
        : (try? Data(contentsOf: databaseURL)).map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        } == before["db"]
    return RestoreSidecarResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        databaseRolledBack: databaseRolledBack,
        unexpectedOccupantPreserved: unexpectedOccupantPreserved,
        quarantinedOriginalPreserved: quarantinedOriginalPreserved,
        reopened: database.isOpen,
        sqliteOpenCallbackCount: sqliteOpenCallbackCount
    )
}

@MainActor
private func runInterruptionChild(_ arguments: [String]) throws -> Never {
    guard arguments.count == 5,
          let boundary = Int(arguments[3]),
          let ordinal = Int(arguments[4]) else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    let action = arguments[0]
    let databaseURL = URL(fileURLWithPath: arguments[1])
    let sourceURL = URL(fileURLWithPath: arguments[2])
    cid850_interpose_reset()
    cid851_interpose_crash_restore_boundary(Int32(boundary), Int32(ordinal))
    if boundary == 9 {
        cid851_interpose_crash_sqlite_open_for_path(databaseURL.path)
    }
    let service = DatabaseSafetyService()
    if action == "restore" {
        let database = CiderDatabase()
        defer { database.close() }
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } else if action == "reconcile" {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    exit(0)
}

private func runInterruptionProcess(
    action: String,
    databaseURL: URL,
    sourceURL: URL,
    boundary: Int,
    ordinal: Int
) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = [
        "restore-v2-interruption-child",
        action,
        databaseURL.path,
        sourceURL.path,
        String(boundary),
        String(ordinal),
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

@MainActor
private func runRestoreV2InterruptionBoundary(
    mode: String,
    restoreBoundary: Int,
    restoreOrdinal: Int,
    reconciliationBoundary: Int,
    reconciliationOrdinal: Int
) throws -> RestoreV2InterruptionResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-v2-interruption-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    var parentBefore = stat()
    guard lstat(root.path, &parentBefore) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let artifact = try service.createRollingBackup(
        reason: "v2-interruption-source",
        database: database
    )
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(artifact.packageName, isDirectory: true)
    if mode == "existing" {
        try database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('v2-interruption-live', 'Live', '#557799', 'custom', 1, 1);
            """)
    } else if mode != "absent" {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    database.close()
    if mode == "absent" {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    let sourceBefore = try completeTreeFingerprint(sourceURL)

    let restoreStatus = try runInterruptionProcess(
        action: "restore",
        databaseURL: databaseURL,
        sourceURL: sourceURL,
        boundary: restoreBoundary,
        ordinal: restoreOrdinal
    )
    let reconciliationStatus = try runInterruptionProcess(
        action: "reconcile",
        databaseURL: databaseURL,
        sourceURL: sourceURL,
        boundary: reconciliationBoundary,
        ordinal: reconciliationOrdinal
    )

    cid851_interpose_count_retained_restore_unlinks()
    let first = try service.reconcileInterruptedRestore(at: databaseURL)
    let fingerprintAfterFirst = try completeTreeFingerprint(root)
    let second = try service.reconcileInterruptedRestore(at: databaseURL)
    let repeatedFingerprintExact = try completeTreeFingerprint(root) == fingerprintAfterFirst
    let sourceUnchanged = try completeTreeFingerprint(sourceURL) == sourceBefore
    var parentAfter = stat()
    let parentIdentityUnchanged = lstat(root.path, &parentAfter) == 0
        && parentBefore.st_dev == parentAfter.st_dev
        && parentBefore.st_ino == parentAfter.st_ino
        && parentBefore.st_gen == parentAfter.st_gen
    let recordSize = getxattr(
        root.path,
        "com.cider.cid851.restore-transaction-v2",
        nil,
        0,
        0,
        0
    )
    let canonicalRecordAbsent = recordSize < 0 && errno == ENOATTR
    let hiddenMemberCount = try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasPrefix(".cid851-restore-") }
        .count

    let destinationExists = FileManager.default.fileExists(atPath: databaseURL.path)
    var liveNamespaceCoherent = true
    var integrityHealthy = true
    if destinationExists {
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                var member = stat()
                liveNamespaceCoherent = liveNamespaceCoherent
                    && lstat(path, &member) == 0
                    && member.st_mode & S_IFMT == S_IFREG
                    && member.st_nlink == 1
            }
        }
        let reopened = CiderDatabase()
        do {
            try reopened.open(at: databaseURL)
            integrityHealthy = try reopened.integrityCheck().isHealthy
            reopened.close()
        } catch {
            reopened.close()
            integrityHealthy = false
        }
    } else {
        liveNamespaceCoherent = !FileManager.default.fileExists(atPath: databaseURL.path + "-wal")
            && !FileManager.default.fileExists(atPath: databaseURL.path + "-shm")
    }
    return RestoreV2InterruptionResult(
        restoreStatus: restoreStatus,
        reconciliationStatus: reconciliationStatus,
        firstReconciliation: first.state.rawValue,
        secondReconciliation: second.state.rawValue,
        sourceUnchanged: sourceUnchanged,
        parentIdentityUnchanged: parentIdentityUnchanged,
        canonicalRecordAbsent: canonicalRecordAbsent,
        hiddenMemberCount: hiddenMemberCount,
        repeatedFingerprintExact: repeatedFingerprintExact,
        destinationExists: destinationExists,
        liveNamespaceCoherent: liveNamespaceCoherent,
        integrityHealthy: integrityHealthy,
        retainedUnlinkAttempts: Int32(cid851_interpose_retained_restore_unlink_attempts())
    )
}

@MainActor
private func runRestorePlannedUnknownBoundary() throws -> RestorePlannedUnknownResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-planned-unknown-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }

    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let artifact = try service.createRollingBackup(reason: "planned-unknown", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(artifact.packageName, isDirectory: true)
    database.close()
    let sourceBefore = try completeTreeFingerprint(sourceURL)

    let childStatus = try runInterruptionProcess(
        action: "restore",
        databaseURL: databaseURL,
        sourceURL: sourceURL,
        boundary: 2,
        ordinal: 1
    )
    let stagingURL = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).first {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            && $0.lastPathComponent.hasSuffix("-staging.sqlite")
    }.map { $0 } ?? { throw CocoaError(.fileNoSuchFile) }()
    let interruptedURL = root.appendingPathComponent("planned-interrupted-held.sqlite")
    try FileManager.default.moveItem(at: stagingURL, to: interruptedURL)
    let replacementBytes = Data("unknown planned occupant must remain exact".utf8)
    let replacementDescriptor = Darwin.open(
        stagingURL.path,
        O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
    )
    guard replacementDescriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    _ = replacementBytes.withUnsafeBytes {
        Darwin.write(replacementDescriptor, $0.baseAddress, $0.count)
    }
    guard fsync(replacementDescriptor) == 0 else {
        Darwin.close(replacementDescriptor)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    Darwin.close(replacementDescriptor)
    var before = stat()
    guard lstat(stagingURL.path, &before) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let fingerprintBefore = try completeTreeFingerprint(root)

    var firstRecoveryRequired = false
    var secondRecoveryRequired = false
    do {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } catch let error as DatabaseSafetyService.RestoreError {
        firstRecoveryRequired = error.requiresRecovery
    }
    do {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } catch let error as DatabaseSafetyService.RestoreError {
        secondRecoveryRequired = error.requiresRecovery
    }

    var after = stat()
    let replacementStillPresent = lstat(stagingURL.path, &after) == 0
    let stateAttribute = "com.cider.cid851.restore-transaction-v2"
    let stateSize = getxattr(root.path, stateAttribute, nil, 0, 0, 0)
    var stateObject: [String: Any] = [:]
    if stateSize > 0 {
        var stateBytes = Data(count: stateSize)
        let read = stateBytes.withUnsafeMutableBytes {
            getxattr(root.path, stateAttribute, $0.baseAddress, $0.count, 0, 0)
        }
        if read == stateSize {
            stateObject = (try? JSONSerialization.jsonObject(with: stateBytes)) as? [String: Any] ?? [:]
        }
    }
    return RestorePlannedUnknownResult(
        childStatus: childStatus,
        firstRecoveryRequired: firstRecoveryRequired,
        secondRecoveryRequired: secondRecoveryRequired,
        replacementIdentityExact: replacementStillPresent
            && before.st_dev == after.st_dev
            && before.st_ino == after.st_ino
            && before.st_gen == after.st_gen,
        replacementBytesExact: (try? Data(contentsOf: stagingURL)) == replacementBytes,
        completeFingerprintExact: try completeTreeFingerprint(root) == fingerprintBefore,
        transactionRemainsPlanned: stateObject["phase"] as? String == "planned",
        transactionClaimsNoStagedIdentity: stateObject["stagedDatabase"] == nil
            || stateObject["stagedDatabase"] is NSNull,
        sourceUnchanged: try completeTreeFingerprint(sourceURL) == sourceBefore
    )
}

@MainActor
private func runPlannedFIFOReconciliationChild(databaseURL: URL) {
    do {
        _ = try DatabaseSafetyService().reconcileInterruptedRestore(at: databaseURL)
        FileHandle.standardOutput.write(Data("not-rejected".utf8))
        exit(2)
    } catch let error as DatabaseSafetyService.RestoreError where error.requiresRecovery {
        FileHandle.standardOutput.write(Data("recovery-required".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(error.localizedDescription.utf8))
        exit(3)
    }
}

private func runPromptChild(arguments: [String]) throws -> (returned: Bool, recovery: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = arguments
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + .seconds(2)) == .success else {
        process.terminate()
        process.waitUntilExit()
        return (false, false)
    }
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    _ = errors.fileHandleForReading.readDataToEndOfFile()
    return (
        process.terminationStatus == 0,
        String(decoding: bytes, as: UTF8.self) == "recovery-required"
    )
}

@MainActor
private func runRestorePlannedFIFOBoundary() throws -> RestorePlannedFIFOResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-planned-fifo-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let artifact = try service.createRollingBackup(reason: "planned-fifo", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(artifact.packageName, isDirectory: true)
    database.close()
    let sourceBefore = try completeTreeFingerprint(sourceURL)
    let childStatus = try runInterruptionProcess(
        action: "restore",
        databaseURL: databaseURL,
        sourceURL: sourceURL,
        boundary: 2,
        ordinal: 1
    )
    let stagingURL = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).first {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            && $0.lastPathComponent.hasSuffix("-staging.sqlite")
    }.map { $0 } ?? { throw CocoaError(.fileNoSuchFile) }()
    try FileManager.default.removeItem(at: stagingURL)
    guard mkfifo(stagingURL.path, S_IRUSR | S_IWUSR) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var fifoBefore = stat()
    guard lstat(stagingURL.path, &fifoBefore) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let stateAttribute = "com.cider.cid851.restore-transaction-v2"
    let stateSize = getxattr(root.path, stateAttribute, nil, 0, 0, 0)
    guard stateSize > 0 else { throw CocoaError(.fileNoSuchFile) }
    var stateBefore = Data(count: stateSize)
    guard stateBefore.withUnsafeMutableBytes({
        getxattr(root.path, stateAttribute, $0.baseAddress, $0.count, 0, 0)
    }) == stateSize else { throw CocoaError(.fileReadCorruptFile) }
    let before = try completeTreeFingerprint(root)
    let first = try runPromptChild(arguments: [
        "restore-v2-planned-fifo-reconcile-child",
        databaseURL.path,
    ])
    let afterFirst = try completeTreeFingerprint(root)
    let second = try runPromptChild(arguments: [
        "restore-v2-planned-fifo-reconcile-child",
        databaseURL.path,
    ])
    let afterSecond = try completeTreeFingerprint(root)
    var fifoAfter = stat()
    let fifoPresent = lstat(stagingURL.path, &fifoAfter) == 0
    let stateSizeAfter = getxattr(root.path, stateAttribute, nil, 0, 0, 0)
    var stateAfter = Data(count: max(0, stateSizeAfter))
    let stateRead = stateSizeAfter > 0 ? stateAfter.withUnsafeMutableBytes {
        getxattr(root.path, stateAttribute, $0.baseAddress, $0.count, 0, 0)
    } : -1
    return RestorePlannedFIFOResult(
        childStatus: childStatus,
        firstReturnedPromptly: first.returned,
        secondReturnedPromptly: second.returned,
        firstRecoveryRequired: first.recovery,
        secondRecoveryRequired: second.recovery,
        fifoIdentityAndTypeExact: fifoPresent
            && fifoBefore.st_dev == fifoAfter.st_dev
            && fifoBefore.st_ino == fifoAfter.st_ino
            && fifoBefore.st_gen == fifoAfter.st_gen
            && fifoAfter.st_mode & S_IFMT == S_IFIFO,
        canonicalStateExact: stateRead == stateSizeAfter && stateAfter == stateBefore,
        repeatedFingerprintExact: afterFirst == before && afterSecond == afterFirst,
        sourceUnchanged: try completeTreeFingerprint(sourceURL) == sourceBefore
    )
}

private func bindHarnessUnixSocket(_ descriptor: Int32, at url: URL) throws {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(url.path.utf8CString)
    let capacity = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size
    guard pathBytes.count <= capacity else { throw CocoaError(.fileWriteInvalidFileName) }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.initializeMemory(as: UInt8.self, repeating: 0)
        for (index, byte) in pathBytes.enumerated() {
            destination[index] = UInt8(bitPattern: byte)
        }
    }
    let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, length)
        }
    }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

private func installSpecialMember(_ kind: String, at url: URL, socketRoot: URL) throws -> Int32 {
    switch kind {
    case "fifo":
        guard mkfifo(url.path, S_IRUSR | S_IWUSR) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return -1
    case "socket":
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        do {
            let socketPath = socketRoot.appendingPathComponent("s-\(UUID().uuidString)")
            try bindHarnessUnixSocket(descriptor, at: socketPath)
            try FileManager.default.moveItem(at: socketPath, to: url)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    case "directory":
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return -1
    case "symlink":
        try FileManager.default.createSymbolicLink(
            at: url,
            withDestinationURL: URL(fileURLWithPath: "/dev/null")
        )
        return -1
    default:
        throw CocoaError(.validationMissingMandatoryProperty)
    }
}

@MainActor
private func runPackageSpecialMemberBoundary(
    _ kind: String,
    member: String
) throws -> PackageSpecialMemberResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("c8-\(UUID().uuidString.prefix(8))", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let qualified = try service.createRollingBackup(reason: "package-special", database: database)
    let packageURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(qualified.packageName, isDirectory: true)
    let memberURL = packageURL.appendingPathComponent(member)
    let otherMember = member == "manifest.json" ? "database.sqlite" : "manifest.json"
    let otherMemberURL = packageURL.appendingPathComponent(otherMember)
    let otherMemberBefore = try Data(contentsOf: otherMemberURL)
    database.close()
    let liveBefore = try Data(contentsOf: databaseURL)
    try FileManager.default.removeItem(at: memberURL)
    let socketDescriptor = try installSpecialMember(kind, at: memberURL, socketRoot: root)
    defer { if socketDescriptor >= 0 { Darwin.close(socketDescriptor) } }
    var specialBefore = stat()
    guard lstat(memberURL.path, &specialBefore) == 0 else { throw CocoaError(.fileNoSuchFile) }

    let listed = service.listRestoreCandidates(databaseURL: databaseURL)
        .first { $0.url.lastPathComponent == qualified.packageName }
    let direct = service.verifyBackup(at: packageURL)
    var urlMaterializationRejected = false
    do {
        _ = try service.materializeVerifiedBackupDatabase(
            from: packageURL,
            at: root.appendingPathComponent("url-materialized.sqlite")
        )
    } catch { urlMaterializationRejected = true }
    var qualifiedMaterializationRejected = false
    do {
        _ = try service.materializeVerifiedBackupDatabase(
            from: qualified,
            at: root.appendingPathComponent("qualified-materialized.sqlite")
        )
    } catch { qualifiedMaterializationRejected = true }
    var liveRestoreRejected = false
    do {
        _ = try service.restoreRollingBackup(
            from: packageURL,
            into: databaseURL,
            database: database,
            reopenDatabase: false
        )
    } catch { liveRestoreRejected = true }
    var specialAfter = stat()
    let specialPresent = lstat(memberURL.path, &specialAfter) == 0
    return PackageSpecialMemberResult(
        kind: kind,
        member: member,
        listRejected: listed?.verification.isRecoveryEligible != true,
        directVerificationRejected: !direct.isRecoveryEligible,
        urlMaterializationRejected: urlMaterializationRejected,
        qualifiedMaterializationRejected: qualifiedMaterializationRejected,
        liveRestoreRejected: liveRestoreRejected,
        specialIdentityAndTypeExact: specialPresent
            && specialBefore.st_dev == specialAfter.st_dev
            && specialBefore.st_ino == specialAfter.st_ino
            && specialBefore.st_gen == specialAfter.st_gen
            && specialBefore.st_mode & S_IFMT == specialAfter.st_mode & S_IFMT,
        otherMemberExact: try Data(contentsOf: otherMemberURL) == otherMemberBefore,
        liveDatabaseExact: try Data(contentsOf: databaseURL) == liveBefore
    )
}

@MainActor
private func runRawSpecialMemberBoundary(_ kind: String) throws -> RawSpecialMemberResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("c8-raw-\(UUID().uuidString.prefix(8))", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    _ = try service.createRollingBackup(reason: "raw-special-policy", database: database)
    let rawURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent("cider.db.legacy.db")
    try Data("legacy-regular-placeholder".utf8).write(to: rawURL)
    database.close()
    let liveBefore = try Data(contentsOf: databaseURL)
    try FileManager.default.removeItem(at: rawURL)
    let socketDescriptor = try installSpecialMember(kind, at: rawURL, socketRoot: root)
    defer { if socketDescriptor >= 0 { Darwin.close(socketDescriptor) } }
    var specialBefore = stat()
    guard lstat(rawURL.path, &specialBefore) == 0 else { throw CocoaError(.fileNoSuchFile) }

    let listed = service.listRestoreCandidates(databaseURL: databaseURL)
        .first { $0.url.lastPathComponent == rawURL.lastPathComponent }
    let direct = service.verifyBackup(at: rawURL)
    var urlMaterializationRejected = false
    do {
        _ = try service.materializeVerifiedBackupDatabase(
            from: rawURL,
            at: root.appendingPathComponent("raw-materialized.sqlite")
        )
    } catch { urlMaterializationRejected = true }
    var liveRestoreRejected = false
    do {
        _ = try service.restoreRollingBackup(
            from: rawURL,
            into: databaseURL,
            database: database,
            reopenDatabase: false
        )
    } catch { liveRestoreRejected = true }
    var specialAfter = stat()
    let specialPresent = lstat(rawURL.path, &specialAfter) == 0
    return RawSpecialMemberResult(
        kind: kind,
        listRejected: listed?.verification.isRecoveryEligible != true,
        directVerificationRejected: !direct.isRecoveryEligible,
        urlMaterializationRejected: urlMaterializationRejected,
        liveRestoreRejected: liveRestoreRejected,
        specialIdentityAndTypeExact: specialPresent
            && specialBefore.st_dev == specialAfter.st_dev
            && specialBefore.st_ino == specialAfter.st_ino
            && specialBefore.st_gen == specialAfter.st_gen
            && specialBefore.st_mode & S_IFMT == specialAfter.st_mode & S_IFMT,
        liveDatabaseExact: try Data(contentsOf: databaseURL) == liveBefore
    )
}

private func harnessTerminalEvidenceURLs(in root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).filter {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            && $0.lastPathComponent.contains("-cleanup-retained-")
    }
}

private func harnessDescriptorBytes(_ descriptor: Int32) throws -> Data {
    var value = stat()
    guard fstat(descriptor, &value) == 0, value.st_size >= 0 else {
        throw POSIXError(.EIO)
    }
    var result = Data(count: Int(value.st_size))
    var offset = 0
    while offset < result.count {
        let count = result.withUnsafeMutableBytes { bytes in
            pread(
                descriptor,
                bytes.baseAddress?.advanced(by: offset),
                bytes.count - offset,
                off_t(offset)
            )
        }
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw POSIXError(.EIO) }
        offset += count
    }
    return result
}

@MainActor
private func runTerminalEvidenceBoundary() throws -> TerminalEvidenceResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-terminal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    defer { database.close() }
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "terminal-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('terminal-live', 'Terminal Live', '#223344', 'custom', 1, 1);
        """)
    cid850_interpose_reset()
    cid851_interpose_count_retained_restore_unlinks()
    _ = try service.restoreRollingBackup(
        from: sourceURL,
        into: databaseURL,
        database: database,
        reopenDatabase: true
    )
    let evidence = try harnessTerminalEvidenceURLs(in: root)
    let selectors = Set(service.listRestoreCandidates(databaseURL: databaseURL)
        .map { $0.url.lastPathComponent })
    let nonselectable = evidence.allSatisfy {
        !selectors.contains($0.lastPathComponent)
            && !service.verifyBackup(at: $0).isRecoveryEligible
    }
    var nonmaterializable = true
    for url in evidence {
        do {
            _ = try service.materializeVerifiedBackupDatabase(
                from: url,
                at: root.appendingPathComponent("forbidden-\(UUID().uuidString).sqlite")
            )
            nonmaterializable = false
        } catch {}
    }
    let beforeEvidenceRestore = try completeTreeFingerprint(root)
    var nonrestorable = true
    for url in evidence {
        do {
            _ = try service.restoreRollingBackup(
                from: url,
                into: databaseURL,
                database: database,
                reopenDatabase: false
            )
            nonrestorable = false
        } catch {}
    }
    let evidenceRestoreTreeExact = try completeTreeFingerprint(root) == beforeEvidenceRestore
    nonrestorable = nonrestorable && evidenceRestoreTreeExact
    database.close()
    let first = try service.reconcileInterruptedRestore(at: databaseURL)
    let afterFirst = try completeTreeFingerprint(root)
    let second = try service.reconcileInterruptedRestore(at: databaseURL)
    let repeated = try completeTreeFingerprint(root) == afterFirst
    let beforeRefusal = try completeTreeFingerprint(root)
    var capacityRefused = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: false
        )
    } catch let error as DatabaseSafetyService.RestoreError {
        let unchanged = try completeTreeFingerprint(root) == beforeRefusal
        capacityRefused = error.requiresRecovery
            && error.localizedDescription.contains("terminal-evidence capacity")
            && unchanged
    }

    let boundedRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-terminal-capacity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: boundedRoot) }
    try FileManager.default.createDirectory(at: boundedRoot, withIntermediateDirectories: false)
    let boundedDatabaseURL = boundedRoot.appendingPathComponent("cider.db")
    let boundedDatabase = CiderDatabase()
    try boundedDatabase.open(at: boundedDatabaseURL)
    let boundedSource = try service.createRollingBackup(
        reason: "terminal-capacity-source",
        database: boundedDatabase
    )
    boundedDatabase.close()
    let boundedSourceURL = service.rollingBackupsDirectory(for: boundedDatabaseURL)
        .appendingPathComponent(boundedSource.packageName, isDirectory: true)
    let beforeHardCapacityRefusal = try completeTreeFingerprint(boundedRoot)
    var hardCapacityRefused = false
    do {
        _ = try DatabaseSafetyService(maximumPolicyBytes: 1).restoreRollingBackup(
            from: boundedSourceURL,
            into: boundedDatabaseURL,
            database: nil,
            reopenDatabase: false
        )
    } catch let error as DatabaseSafetyService.RestoreError {
        let hardCapacityTreeExact = try completeTreeFingerprint(boundedRoot)
            == beforeHardCapacityRefusal
        hardCapacityRefused = error.requiresRecovery
            && error.localizedDescription.contains("terminal-evidence retention capacity")
            && hardCapacityTreeExact
    }
    return TerminalEvidenceResult(
        evidenceCount: evidence.count,
        unlinkAttempts: Int32(cid851_interpose_retained_restore_unlink_attempts()),
        evidenceNonselectable: nonselectable,
        evidenceNonmaterializable: nonmaterializable,
        evidenceNonrestorable: nonrestorable,
        firstReconciliation: first.state.rawValue,
        secondReconciliation: second.state.rawValue,
        repeatedFingerprintExact: repeated,
        capacityRefusedBeforeMutation: capacityRefused,
        hardByteCapacityRefusedBeforeMutation: hardCapacityRefused
    )
}

@MainActor
private func runRecordRemovalReoccupationBoundary() throws -> RecordRemovalReoccupationResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-record-reoccupation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "record-reoccupation", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    let sourceBefore = try completeTreeFingerprint(sourceURL)
    _ = try service.restoreRollingBackup(
        from: sourceURL,
        into: databaseURL,
        database: database,
        reopenDatabase: true
    )
    database.close()
    let liveBefore = try sqliteSetFingerprint(databaseURL)
    let inventory = try service.terminalRestoreEvidenceInventory(at: databaseURL)
    for member in inventory.members where member.safeToRemoveOutOfBand {
        try FileManager.default.removeItem(at: root.appendingPathComponent(member.basename))
    }
    let attribute = "com.cider.cid851.restore-transaction-v2"
    let recordBefore = try extendedAttribute(at: root, name: attribute)
    cid850_interpose_reset()
    cid851_interpose_reoccupy_before_completed_record_removal()
    var recoveryRequired = false
    do {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } catch let error as DatabaseSafetyService.RestoreError {
        recoveryRequired = error.requiresRecovery
    }
    let fixedName = ".cid851-restore-fixed-staging.sqlite"
    let occupantURL = root.appendingPathComponent(fixedName)
    let marker = Data("record-removal-reoccupation".utf8)
    let after = try service.terminalRestoreEvidenceInventory(at: databaseURL)
    let namesAfter = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).map(\.lastPathComponent).filter {
        $0.hasPrefix(".cid851-restore-")
    }.sorted()
    var repeated = true
    for _ in 0..<2 {
        do {
            _ = try service.reconcileInterruptedRestore(at: databaseURL)
            repeated = false
        } catch let error as DatabaseSafetyService.RestoreError {
            repeated = repeated && error.requiresRecovery
        }
    }
    return RecordRemovalReoccupationResult(
        didMutation: cid850_interpose_did_mutation(),
        reconciliationRecoveryRequired: recoveryRequired,
        recordBytesPreserved: try extendedAttribute(at: root, name: attribute) == recordBefore,
        occupantBytesExact: (try? Data(contentsOf: occupantURL)) == marker,
        inventoryReoccupied: after.members.first { $0.basename == fixedName }?.status
            == .reoccupied,
        repeatedRecoveryRequired: repeated,
        fixedGraphNamesExact: namesAfter == [fixedName],
        sourceUnchanged: try completeTreeFingerprint(sourceURL) == sourceBefore,
        liveDatabaseExact: try sqliteSetFingerprint(databaseURL) == liveBefore
    )
}

@MainActor
private func runHeldDescriptorEvidenceBoundary() throws -> HeldDescriptorEvidenceResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-held-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    defer { database.close() }
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "held-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('held-live', 'Held Live', '#445566', 'custom', 1, 1);
        """)
    let held = Darwin.open(databaseURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    guard held >= 0 else { throw POSIXError(.EIO) }
    defer { Darwin.close(held) }
    cid850_interpose_reset()
    cid851_interpose_mutate_held_descriptor_after_retention(held)
    cid851_interpose_count_retained_restore_unlinks()
    var restoreFailed = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch { restoreFailed = true }
    var heldStat = stat()
    guard fstat(held, &heldStat) == 0 else { throw POSIXError(.EIO) }
    let retainedURL = try harnessTerminalEvidenceURLs(in: root).first { url in
        var value = stat()
        return lstat(url.path, &value) == 0
            && value.st_dev == heldStat.st_dev
            && value.st_ino == heldStat.st_ino
            && value.st_gen == heldStat.st_gen
    }
    let descriptorBytes = try harnessDescriptorBytes(held)
    let exact = try retainedURL.map { try Data(contentsOf: $0) == descriptorBytes } ?? false
    let afterReturn = try completeTreeFingerprint(root)
    var repeatedRecovery = true
    for _ in 0..<2 {
        do {
            _ = try service.reconcileInterruptedRestore(at: databaseURL)
            repeatedRecovery = false
        } catch let error as DatabaseSafetyService.RestoreError {
            repeatedRecovery = repeatedRecovery && error.requiresRecovery
        }
    }
    return HeldDescriptorEvidenceResult(
        didMutation: cid850_interpose_did_mutation(),
        restoreFailed: restoreFailed,
        unlinkAttempts: Int32(cid851_interpose_retained_restore_unlink_attempts()),
        retainedNameReachesDescriptorBytes: exact,
        repeatedRecoveryRequired: repeatedRecovery,
        repeatedFingerprintExact: try completeTreeFingerprint(root) == afterReturn
    )
}

@MainActor
private func runQualifiedReceiptRaceBoundary(_ action: String) throws -> QualifiedReceiptRaceResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-qualified-receipt-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    defer { database.close() }
    let service = DatabaseSafetyService()
    let receipt = try service.createRollingBackupReceipt(
        reason: "qualified-receipt-race",
        database: database
    )
    guard let artifact = receipt.artifact else { throw CocoaError(.fileNoSuchFile) }
    let packageURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(artifact.packageName, isDirectory: true)
    let memberURL = packageURL.appendingPathComponent("database.sqlite")
    let manifestURL = packageURL.appendingPathComponent("manifest.json")
    let memberBefore = try Data(contentsOf: memberURL)
    let manifestBefore = try Data(contentsOf: manifestURL)
    let liveBefore = try sqliteSetFingerprint(databaseURL)
    var originalStat = stat()
    guard lstat(memberURL.path, &originalStat) == 0 else { throw POSIXError(.EIO) }
    cid850_interpose_reset()
    cid851_interpose_qualified_receipt_member_race(
        packageURL.path,
        "database.sqlite",
        action
    )
    let started = Date()
    let usable = receipt.usable
    let elapsed = Date().timeIntervalSince(started)
    let heldURL = packageURL.appendingPathComponent(".cid851-receipt-held-database.sqlite")
    let heldBytes = try? Data(contentsOf: heldURL)
    var visibleStat = stat()
    let visiblePresent = lstat(memberURL.path, &visibleStat) == 0
    let originalPreserved: Bool
    if action == "post-read-mutate" {
        originalPreserved = if visiblePresent {
            try Data(contentsOf: memberURL).count == memberBefore.count
        } else {
            false
        }
    } else {
        originalPreserved = heldBytes == memberBefore
    }
    return QualifiedReceiptRaceResult(
        action: action,
        didMutation: cid850_interpose_did_mutation(),
        receiptUnusable: !usable,
        returnedPromptly: elapsed < 2,
        liveDatabaseExact: try sqliteSetFingerprint(databaseURL) == liveBefore,
        manifestExact: try Data(contentsOf: manifestURL) == manifestBefore,
        originalMemberPreserved: originalPreserved,
        visibleMemberDifferentInode: visiblePresent
            && (visibleStat.st_dev != originalStat.st_dev
                || visibleStat.st_ino != originalStat.st_ino
                || visibleStat.st_gen != originalStat.st_gen)
    )
}

@MainActor
private func runRetentionCollisionBoundary(_ attack: String) throws -> RetentionCollisionResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-collision-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    defer { database.close() }
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "collision-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('collision-live', 'Collision Live', '#667788', 'custom', 1, 1);
        """)
    cid850_interpose_reset()
    if attack == "destination" {
        cid851_interpose_occupy_cleanup_retention_destination()
    } else if attack == "source" {
        cid851_interpose_reoccupy_cleanup_source_after_retention()
    } else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    cid851_interpose_count_retained_restore_unlinks()
    var restoreFailed = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch { restoreFailed = true }
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    return RetentionCollisionResult(
        attack: attack,
        didMutation: cid850_interpose_did_mutation(),
        restoreFailed: restoreFailed,
        unlinkAttempts: Int32(cid851_interpose_retained_restore_unlink_attempts()),
        retainedEvidencePresent: names.contains { $0.contains("-cleanup-retained-") },
        sourceReoccupationPresent: attack != "source"
            || names.contains { $0.hasSuffix("-staging.sqlite") }
    )
}

@MainActor
private func runRestoreMalformedGraphBoundary() throws -> RestoreMalformedGraphResult {
    let phases = [
        "planned", "staged", "originalsRetained", "published", "reopened",
        "cleaning", "rollingBack", "rolledBack", "completed",
    ]
    let variants = [
        "arbitrary-generated-retained",
        "arbitrary-artifact-retained",
        "duplicate-name",
        "duplicate-identity",
        "database-as-sidecar",
        "source-member-overlap",
    ] + phases.map { "phase-arbitrary-retained:\($0)" }
    var rejectedCount = 0
    var fingerprintsExact = true
    var stateBytesExact = true
    for variant in variants {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid851-malformed-graph-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let databaseURL = root.appendingPathComponent("cider.db")
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        let service = DatabaseSafetyService()
        let artifact = try service.createRollingBackup(reason: "malformed-graph", database: database)
        let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
            .appendingPathComponent(artifact.packageName, isDirectory: true)
        database.close()
        let status = try runInterruptionProcess(
            action: "restore",
            databaseURL: databaseURL,
            sourceURL: sourceURL,
            boundary: 3,
            ordinal: 2
        )
        guard status == 93 else { throw CocoaError(.fileReadCorruptFile) }
        let attribute = "com.cider.cid851.restore-transaction-v2"
        let size = getxattr(root.path, attribute, nil, 0, 0, 0)
        guard size > 0 else { throw CocoaError(.fileNoSuchFile) }
        var bytes = Data(count: size)
        guard bytes.withUnsafeMutableBytes({
            getxattr(root.path, attribute, $0.baseAddress, $0.count, 0, 0)
        }) == size,
        var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var initial = object["initialNamespace"] as? [String: Any] ?? [:]
        var databaseArtifact = initial["database"] as? [String: Any] ?? [:]
        let staged = object["stagedDatabase"] as? [String: Any] ?? [:]
        let source = object["source"] as? [String: Any] ?? [:]
        let sourceMembers = source["members"] as? [[String: Any]] ?? []
        switch variant {
        case "arbitrary-generated-retained":
            object["originalDatabaseRetainedName"] = ".arbitrary-retained.sqlite"
        case "arbitrary-artifact-retained":
            databaseArtifact["retainedName"] = ".arbitrary-retained.sqlite"
            initial["database"] = databaseArtifact
            object["initialNamespace"] = initial
        case "duplicate-name":
            object["replacementWALRetainedName"] = object["originalWALRetainedName"]
        case "duplicate-identity":
            databaseArtifact["identity"] = staged["identity"]
            initial["database"] = databaseArtifact
            object["initialNamespace"] = initial
        case "database-as-sidecar":
            var sidecar = databaseArtifact
            sidecar["originalName"] = databaseURL.lastPathComponent + "-wal"
            sidecar["retainedName"] = object["originalWALRetainedName"]
            initial["wal"] = sidecar
            object["initialNamespace"] = initial
        case "source-member-overlap":
            databaseArtifact["identity"] = sourceMembers.first?["identity"]
            initial["database"] = databaseArtifact
            object["initialNamespace"] = initial
        default:
            if let phase = variant.split(separator: ":", maxSplits: 1).last,
               variant.hasPrefix("phase-arbitrary-retained:") {
                object["phase"] = String(phase)
                object["originalDatabaseRetainedName"] = ".arbitrary-retained.sqlite"
            }
        }
        let malformed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard malformed.withUnsafeBytes({
            setxattr(root.path, attribute, $0.baseAddress, $0.count, 0, 0)
        }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let before = try completeTreeFingerprint(root)
        do {
            _ = try service.reconcileInterruptedRestore(at: databaseURL)
        } catch let error as DatabaseSafetyService.RestoreError where error.requiresRecovery {
            rejectedCount += 1
        }
        let afterFingerprint = try completeTreeFingerprint(root)
        fingerprintsExact = fingerprintsExact && afterFingerprint == before
        let afterSize = getxattr(root.path, attribute, nil, 0, 0, 0)
        var after = Data(count: max(0, afterSize))
        let afterRead = afterSize > 0 ? after.withUnsafeMutableBytes {
            getxattr(root.path, attribute, $0.baseAddress, $0.count, 0, 0)
        } : -1
        stateBytesExact = stateBytesExact && afterRead == afterSize && after == malformed
    }
    return RestoreMalformedGraphResult(
        variantCount: variants.count,
        rejectedCount: rejectedCount,
        completeFingerprintsExact: fingerprintsExact,
        canonicalStateBytesExact: stateBytesExact
    )
}

@MainActor
private func runRestoreMemberSeamBoundary(_ operation: String) throws -> RestoreMemberSeamResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-member-seam-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let artifact = try service.createRollingBackup(reason: "member-seam", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(artifact.packageName, isDirectory: true)
    let sourceBefore = try completeTreeFingerprint(sourceURL)
    try database.runSQL("CREATE TABLE IF NOT EXISTS member_seam_live(value INTEGER NOT NULL);")
    try database.runSQL("INSERT INTO member_seam_live(value) VALUES (1);")
    database.close()
    if operation == "clone" {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    let expectedByteSets = [
        try? Data(contentsOf: sourceURL.appendingPathComponent("database.sqlite")),
        try? Data(contentsOf: databaseURL),
    ].compactMap { $0 }
    let expectedHashes = Set(expectedByteSets.map(sha256))
    let seamMutatedHashes = Set(expectedByteSets.compactMap { bytes -> String? in
        guard bytes.count >= 2 else { return nil }
        var changed = bytes
        let offset = bytes.count > 100 ? 100 : bytes.count - 1
        changed[offset] ^= 0x5a
        return sha256(changed)
    })
    cid850_interpose_reset()
    switch operation {
    case "rename": cid851_interpose_mutate_restore_member_before_rename()
    case "unlink": cid851_interpose_mutate_restore_member_before_unlink()
    case "clone": cid851_interpose_mutate_restore_member_before_clone()
    case "destination-exists": cid851_interpose_occupy_cleanup_retention_destination()
    default: throw CocoaError(.validationMissingMandatoryProperty)
    }
    cid851_interpose_count_retained_restore_unlinks()
    var restoreFailed = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
    }
    let didMutation = cid850_interpose_did_mutation()
    let retainedUnlinkAttempts = Int32(cid851_interpose_retained_restore_unlink_attempts())
    cid850_interpose_reset()
    let candidates = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ).filter {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            || $0.lastPathComponent == databaseURL.lastPathComponent
    }
    let sourceReplacementBytes = Data("cid851-cleanup-source-replacement".utf8)
    let destinationOccupantBytes = Data("cid851-cleanup-destination-occupant".utf8)
    let replacementCandidates = candidates.filter {
        (try? Data(contentsOf: $0)) == sourceReplacementBytes
    }
    let changedCandidates = candidates.filter { candidate in
        guard let bytes = try? Data(contentsOf: candidate), !bytes.isEmpty else { return false }
        return seamMutatedHashes.contains(sha256(bytes))
    }
    let cleanupSourcePreserved = candidates.contains { candidate in
        candidate.lastPathComponent.hasSuffix("-staging.sqlite")
            && (try? Data(contentsOf: candidate)).map { expectedHashes.contains(sha256($0)) } == true
    }
    let preservedIdentities = (replacementCandidates + changedCandidates).compactMap { url -> String? in
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return "\(value.st_dev):\(value.st_ino):\(value.st_gen)"
    }
    var firstRecoveryRequired = false
    var secondRecoveryRequired = false
    do { _ = try service.reconcileInterruptedRestore(at: databaseURL) }
    catch let error as DatabaseSafetyService.RestoreError {
        firstRecoveryRequired = error.requiresRecovery
    }
    let firstFingerprint = try completeTreeFingerprint(root)
    do { _ = try service.reconcileInterruptedRestore(at: databaseURL) }
    catch let error as DatabaseSafetyService.RestoreError {
        secondRecoveryRequired = error.requiresRecovery
    }
    return RestoreMemberSeamResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        firstRecoveryRequired: firstRecoveryRequired,
        secondRecoveryRequired: secondRecoveryRequired,
        changedMemberPreserved: !changedCandidates.isEmpty,
        sourceReplacementPreserved: !replacementCandidates.isEmpty,
        distinctPreservedIdentities: Set(preservedIdentities).count >= 2,
        cleanupSourcePreserved: cleanupSourcePreserved,
        destinationOccupantPreserved: candidates.contains {
            (try? Data(contentsOf: $0)) == destinationOccupantBytes
        },
        repeatedFingerprintExact: try completeTreeFingerprint(root) == firstFingerprint,
        sourceUnchanged: try completeTreeFingerprint(sourceURL) == sourceBefore,
        retainedUnlinkAttempts: retainedUnlinkAttempts
    )
}

@MainActor
private func runRestoreFsyncBoundary(failureCount: Int) throws -> RestoreFsyncResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-restore-fsync-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let backup = try service.createRollingBackup(reason: "fsync-source", database: database)
    let backupURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(backup.packageName, isDirectory: true)
    let replacementData = try Data(contentsOf: backupURL.appendingPathComponent("database.sqlite"))
    let replacementHash = SHA256.hash(data: replacementData)
        .map { String(format: "%02x", $0) }
        .joined()

    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('live-after-fsync-backup', 'Live', '#664422', 'custom', 1, 1);
        """)
    try database.checkpointWal()
    var writer: OpaquePointer?
    guard sqlite3_open_v2(
        databaseURL.path,
        &writer,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK, let writer else {
        sqlite3_close_v2(writer)
        throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_close_v2(writer) }
    try execute(writer, "PRAGMA journal_mode=WAL;")
    try execute(writer, "BEGIN IMMEDIATE;")
    try execute(writer, """
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('live-wal-after-fsync-backup', 'Live WAL', '#446622', 'custom', 2, 2);
        """)
    try execute(writer, "COMMIT;")
    let original = try sqliteSetFingerprint(databaseURL)

    cid850_interpose_reset()
    cid850_interpose_fail_post_swap_parent_fsync("cider.db", Int32(failureCount))
    var failureMessage = ""
    var restoreFailed = false
    var restoreError: DatabaseSafetyService.RestoreError?
    do {
        _ = try service.restoreRollingBackup(
            from: backupURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
        failureMessage = error.localizedDescription
        restoreError = error as? DatabaseSafetyService.RestoreError
    }
    let didMutation = cid850_interpose_did_mutation()
    cid850_interpose_reset()
    _ = try service.reconcileInterruptedRestore(at: databaseURL)
    _ = try service.reconcileInterruptedRestore(at: databaseURL)
    let final = try sqliteSetFingerprint(databaseURL)
    let entries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    )
    let replacementRetained = entries.contains { entry in
        guard (entry.lastPathComponent.hasPrefix(".cid850-restore-")
                || entry.lastPathComponent.hasPrefix(".cid851-restore-")),
              entry.pathExtension == "sqlite",
              let data = try? Data(contentsOf: entry) else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            == replacementHash
    }
    let unexpectedOccupantsPreserved = entries
        .filter { $0.lastPathComponent.hasPrefix(".cid850-unexpected-") }
        .allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    let recoveryArtifact = restoreError?.retainedRecoveryArtifactURL
        ?? service.listRestoreCandidates(databaseURL: databaseURL)
            .first { $0.kind == .preflight }?.url
    let recoveryArtifactVerified = recoveryArtifact.map {
        service.verifyBackup(at: $0).isVerified
    } ?? false
    let recoverySelector = recoveryArtifact.flatMap { artifact in
        service.listRestoreCandidates(databaseURL: databaseURL)
            .first { $0.url.standardizedFileURL == artifact.standardizedFileURL }?
            .url.lastPathComponent
    }
    return RestoreFsyncResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        originalSQLiteSetRestored: final == original,
        replacementRetained: replacementRetained,
        recoveryRequired: restoreError?.requiresRecovery ?? false,
        recoveryArtifactVerified: recoveryArtifactVerified,
        recoverySelector: recoverySelector,
        unexpectedOccupantsPreserved: unexpectedOccupantsPreserved,
        reopened: database.isOpen,
        failureMessage: failureMessage,
        originalFingerprint: original,
        finalFingerprint: final
    )
}

@MainActor
private func runRestoreCrashChild(
    rootPath: String,
    crashBeforeCompletion: Bool = false
) throws {
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "crash-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('crash-original', 'Crash Original', '#335577', 'custom', 1, 1);
        """)
    var writer: OpaquePointer?
    guard sqlite3_open_v2(
        databaseURL.path,
        &writer,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK, let writer else {
        sqlite3_close_v2(writer)
        throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_close_v2(writer) }
    try execute(writer, "PRAGMA journal_mode=WAL;")
    try execute(writer, "BEGIN IMMEDIATE;")
    try execute(writer, "COMMIT;")
    let fixture = RestoreCrashFixture(
        originalFingerprint: try sqliteSetFingerprint(databaseURL),
        sourcePackageName: source.packageName,
        sourceFingerprint: try fingerprintTree(sourceURL)
    )
    try JSONEncoder().encode(fixture).write(
        to: root.appendingPathComponent("crash-fixture.json"),
        options: .atomic
    )
    cid850_interpose_reset()
    if crashBeforeCompletion {
        cid851_interpose_crash_restore_boundary(3, 5)
    } else {
        cid850_interpose_crash_after_restore_swap("cider.db")
    }
    _ = try service.restoreRollingBackup(
        from: sourceURL,
        into: databaseURL,
        database: database,
        reopenDatabase: true
    )
    exit(99)
}

@MainActor
private func runRestoreCrashBoundary(crashBeforeCompletion: Bool = false) throws -> RestoreCrashResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-crash-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = [
        crashBeforeCompletion
            ? "restore-crash-before-completion-child"
            : "restore-crash-after-swap-child",
        root.path,
    ]
    child.standardOutput = Pipe()
    child.standardError = Pipe()
    try child.run()
    child.waitUntilExit()
    let fixture = try JSONDecoder().decode(
        RestoreCrashFixture.self,
        from: Data(contentsOf: root.appendingPathComponent("crash-fixture.json"))
    )
    let databaseURL = root.appendingPathComponent("cider.db")
    let service = DatabaseSafetyService()
    let reconciliation = try service.reconcileInterruptedRestore(at: databaseURL)
    let finalFingerprint = try sqliteSetFingerprint(databaseURL)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(fixture.sourcePackageName, isDirectory: true)
    let sourceUnchanged = try fingerprintTree(sourceURL) == fixture.sourceFingerprint
    let database = CiderDatabase()
    var physicallyReopened = false
    var integrityHealthy = false
    do {
        try database.open(at: databaseURL)
        physicallyReopened = database.isOpen
        integrityHealthy = try database.integrityCheck().isHealthy
        database.close()
    }
    let fingerprintBeforeRepeatedReconciliation = try completeTreeFingerprint(root)
    let repeated = try service.reconcileInterruptedRestore(at: databaseURL)
    let repeatedFingerprintExact = try completeTreeFingerprint(root)
        == fingerprintBeforeRepeatedReconciliation
    let hiddenCount = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).filter {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            || $0.lastPathComponent.hasPrefix(".cid850-restore-")
    }.count
    return RestoreCrashResult(
        childStatus: child.terminationStatus,
        reconciliationState: reconciliation.state.rawValue,
        repeatedState: repeated.state.rawValue,
        exactOriginalRestored: finalFingerprint == fixture.originalFingerprint,
        sourceUnchanged: sourceUnchanged,
        physicallyReopened: physicallyReopened,
        integrityHealthy: integrityHealthy,
        hiddenRestoreArtifactCount: hiddenCount,
        repeatedFingerprintExact: repeatedFingerprintExact,
        originalFingerprint: fixture.originalFingerprint,
        finalFingerprint: finalFingerprint
    )
}

@MainActor
private func runRestoreSameFileChangeBoundary() throws -> RestoreSameFileChangeResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-same-file-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["restore-crash-after-swap-child", root.path]
    child.standardOutput = Pipe()
    child.standardError = Pipe()
    try child.run()
    child.waitUntilExit()
    let fixture = try JSONDecoder().decode(
        RestoreCrashFixture.self,
        from: Data(contentsOf: root.appendingPathComponent("crash-fixture.json"))
    )
    let hiddenURL = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).first {
        ($0.lastPathComponent.hasPrefix(".cid850-restore-")
            || $0.lastPathComponent.hasPrefix(".cid851-restore-"))
            && $0.lastPathComponent.hasSuffix(".sqlite")
    }!
    var before = stat()
    guard lstat(hiddenURL.path, &before) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let descriptor = Darwin.open(hiddenURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var byte: UInt8 = 0
    guard pread(descriptor, &byte, 1, 100) == 1 else {
        Darwin.close(descriptor)
        throw POSIXError(.EIO)
    }
    byte ^= 0xff
    guard pwrite(descriptor, &byte, 1, 100) == 1, fsync(descriptor) == 0 else {
        Darwin.close(descriptor)
        throw POSIXError(.EIO)
    }
    Darwin.close(descriptor)
    var after = stat()
    guard lstat(hiddenURL.path, &after) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let changedHash = sha256(try Data(contentsOf: hiddenURL))
    let service = DatabaseSafetyService()
    let databaseURL = root.appendingPathComponent("cider.db")
    var firstRecoveryRequired = false
    var repeatedRecoveryRequired = false
    do {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } catch let error as DatabaseSafetyService.RestoreError {
        firstRecoveryRequired = error.requiresRecovery
    }
    let firstFingerprint = try fingerprintTree(root)
    do {
        _ = try service.reconcileInterruptedRestore(at: databaseURL)
    } catch let error as DatabaseSafetyService.RestoreError {
        repeatedRecoveryRequired = error.requiresRecovery
    }
    let secondFingerprint = try fingerprintTree(root)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(fixture.sourcePackageName, isDirectory: true)
    return RestoreSameFileChangeResult(
        childStatus: child.terminationStatus,
        firstRecoveryRequired: firstRecoveryRequired,
        repeatedRecoveryRequired: repeatedRecoveryRequired,
        sameInodeChangedContentPreserved: before.st_dev == after.st_dev
            && before.st_ino == after.st_ino
            && (try? sha256(Data(contentsOf: hiddenURL))) == changedHash,
        journalPreserved: getxattr(
            root.path,
            "com.cider.cid851.restore-transaction-v2",
            nil,
            0,
            0,
            0
        ) > 0,
        sourceUnchanged: try fingerprintTree(sourceURL) == fixture.sourceFingerprint,
        hiddenFingerprintAfterFirst: firstFingerprint,
        hiddenFingerprintAfterSecond: secondFingerprint
    )
}

@MainActor
private func runRestoreRecordRemovalSyncBoundary() throws -> RestoreRecordRemovalSyncResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-record-removal-sync-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "record-removal-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    let sourceBefore = try fingerprintTree(sourceURL)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('record-removal-live', 'Live', '#447799', 'custom', 1, 1);
        """)
    try database.checkpointWal()

    cid850_interpose_reset()
    cid850_interpose_fail_restore_record_removal_fsync()
    var restoreFailed = false
    var recoveryRequired = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
        recoveryRequired = (error as? DatabaseSafetyService.RestoreError)?.requiresRecovery
            ?? true
    }
    let didMutation = cid850_interpose_did_mutation()
    cid850_interpose_reset()

    let journalURL = root.appendingPathComponent(
        cid851RestoreJournalName(databaseName: databaseURL.lastPathComponent)
    )
    let journalAbsentAfterFailure = !FileManager.default.fileExists(atPath: journalURL.path)
    let registrationName = "com.cider.cid851.restore-journal-registration-v1"
    let registrationPresentAfterFailure = getxattr(
        root.path,
        registrationName,
        nil,
        0,
        0,
        0
    ) >= 0

    database.close()
    let reconciliation = try service.reconcileInterruptedRestore(at: databaseURL)
    let repeated = try service.reconcileInterruptedRestore(at: databaseURL)
    let registrationClearedAfterReconciliation: Bool
    if getxattr(root.path, registrationName, nil, 0, 0, 0) < 0 {
        registrationClearedAfterReconciliation = errno == ENOATTR
    } else {
        registrationClearedAfterReconciliation = false
    }
    let reopened = CiderDatabase()
    try reopened.open(at: databaseURL)
    let physicallyReopened = reopened.isOpen
    let integrityHealthy = try reopened.integrityCheck().isHealthy
    reopened.close()
    let hiddenRestoreArtifactCount = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).filter {
        $0.lastPathComponent.hasPrefix(".cid851-restore-")
            || $0.lastPathComponent.hasPrefix(".cid850-restore-")
    }.count
    return RestoreRecordRemovalSyncResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        recoveryRequired: recoveryRequired,
        journalAbsentAfterFailure: journalAbsentAfterFailure,
        registrationPresentAfterFailure: registrationPresentAfterFailure,
        reconciliationState: reconciliation.state.rawValue,
        repeatedState: repeated.state.rawValue,
        registrationClearedAfterReconciliation: registrationClearedAfterReconciliation,
        sourceUnchanged: try fingerprintTree(sourceURL) == sourceBefore,
        physicallyReopened: physicallyReopened,
        integrityHealthy: integrityHealthy,
        hiddenRestoreArtifactCount: hiddenRestoreArtifactCount
    )
}

@MainActor
private func runRestoreValidationFailureBoundary(_ boundary: String) throws -> RestoreValidationFailureResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-validation-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "validation-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    let sourceBefore = try fingerprintTree(sourceURL)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('validation-original', 'Validation Original', '#224466', 'custom', 1, 1);
        """)
    try database.checkpointWal()
    let original = try sqliteSetFingerprint(databaseURL)
    cid850_interpose_reset()
    if boundary == "restore-reopen-failure" {
        cid850_interpose_fail_restore_reopen_after_swap("cider.db")
    } else if boundary == "restore-integrity-failure" {
        cid850_interpose_fail_restore_integrity_after_swap("cider.db")
    } else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    var failureMessage = ""
    var restoreFailed = false
    var restoreError: DatabaseSafetyService.RestoreError?
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
        failureMessage = error.localizedDescription
        restoreError = error as? DatabaseSafetyService.RestoreError
    }
    let didMutation = cid850_interpose_did_mutation()
    cid850_interpose_reset()
    let final = (try? sqliteSetFingerprint(databaseURL)) ?? [
        "db": "unreadable",
        "wal": FileManager.default.fileExists(atPath: databaseURL.path + "-wal") ? "present" : "absent",
        "shm": FileManager.default.fileExists(atPath: databaseURL.path + "-shm") ? "present" : "absent"
    ]
    let exactOriginalRestored = final == original
    let exactOriginalRetained = (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ).contains { entry in
        guard (entry.lastPathComponent.hasPrefix(".cid850-restore-")
                || entry.lastPathComponent.hasPrefix(".cid851-restore-")),
              entry.pathExtension == "sqlite",
              let bytes = try? Data(contentsOf: entry) else { return false }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return hash == original["db"]
    }) ?? false
    let namedRecoveryURL = restoreError?.retainedRecoveryArtifactURL
    let candidates = service.listRestoreCandidates(databaseURL: databaseURL)
    let rollbackArtifact = namedRecoveryURL.flatMap { named in
        candidates.first { $0.url.standardizedFileURL == named.standardizedFileURL }
    } ?? candidates.first { $0.kind == .preflight }
    let rollbackArtifactVerified = rollbackArtifact.map {
        service.verifyBackup(at: $0.url).isVerified
    } ?? false
    let sourceUnchanged = try fingerprintTree(sourceURL) == sourceBefore
    let reopened = CiderDatabase()
    var physicallyReopened = false
    var integrityHealthy = false
    if exactOriginalRestored {
        try reopened.open(at: databaseURL)
        physicallyReopened = reopened.isOpen
        integrityHealthy = try reopened.integrityCheck().isHealthy
        reopened.close()
    }
    return RestoreValidationFailureResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        recoveryRequired: restoreError?.requiresRecovery ?? false,
        exactOriginalRestored: exactOriginalRestored,
        exactOriginalRetained: exactOriginalRetained,
        sourceUnchanged: sourceUnchanged,
        recoveryArtifactNamedByError: namedRecoveryURL != nil
            && rollbackArtifact?.url.standardizedFileURL == namedRecoveryURL?.standardizedFileURL,
        rollbackArtifactVerified: rollbackArtifactVerified,
        rollbackSelector: rollbackArtifact?.url.lastPathComponent,
        physicallyReopened: physicallyReopened,
        integrityHealthy: integrityHealthy,
        failureMessage: failureMessage,
        originalFingerprint: original,
        finalFingerprint: final
    )
}

@MainActor
private func runRestoreAuthorityBoundary() throws -> RestoreAuthorityResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-authority-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let database = CiderDatabase()
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "authority-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('authority-live', 'Authority Live', '#557799', 'custom', 1, 1);
        """)

    cid850_interpose_reset()
    cid851_interpose_count_restore_authority()
    _ = try service.restoreRollingBackup(
        from: sourceURL,
        into: databaseURL,
        database: database,
        reopenDatabase: true
    )
    let acquisitions = cid851_interpose_restore_authority_acquisitions()
    let releases = cid851_interpose_restore_authority_releases()
    return RestoreAuthorityResult(
        restored: database.isOpen,
        integrityHealthy: try database.integrityCheck().isHealthy,
        exclusiveAcquisitions: acquisitions,
        releases: releases
    )
}

@MainActor
private func runRestoreArchitectureBoundary() throws -> RestoreArchitectureResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-architecture-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let database = CiderDatabase()
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let source = try service.createRollingBackup(reason: "architecture-source", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(source.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('architecture-live', 'Architecture Live', '#557799', 'custom', 1, 1);
        """)

    cid850_interpose_reset()
    cid851_interpose_count_restore_metadata()
    cid851_interpose_count_parent_reopens(root.path)
    _ = try service.restoreRollingBackup(
        from: sourceURL,
        into: databaseURL,
        database: database,
        reopenDatabase: true
    )
    return RestoreArchitectureResult(
        restored: database.isOpen,
        integrityHealthy: try database.integrityCheck().isHealthy,
        legacyMetadataWrites: cid851_interpose_legacy_restore_metadata_writes(),
        canonicalMetadataWrites: cid851_interpose_canonical_restore_metadata_writes(),
        parentReopensAfterLock: cid851_interpose_parent_reopens_after_lock()
    )
}

@MainActor
private func runRestoreFinalCapabilityBoundary(_ boundary: String) throws -> RestoreFinalCapabilityResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid851-restore-final-capability-\(UUID().uuidString)", isDirectory: true)
    let heldRoot = root.deletingLastPathComponent()
        .appendingPathComponent(".cid851-held-parent-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    let database = CiderDatabase()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        cid850_interpose_reset()
        database.close()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: heldRoot)
    }
    try database.open(at: databaseURL)
    let service = DatabaseSafetyService()
    let receipt = try service.createRollingBackup(reason: "final-capability", database: database)
    let sourceURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(receipt.packageName, isDirectory: true)
    let heldSource = sourceURL.deletingLastPathComponent()
        .appendingPathComponent(".cid851-held-source-\(UUID().uuidString)", isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('final-capability-live', 'Live', '#557799', 'custom', 1, 1);
        """)

    cid850_interpose_reset()
    if boundary == "restore-source-before-cleanup" {
        cid851_interpose_move_source_before_restore_cleanup(sourceURL.path, heldSource.path)
    } else if boundary == "restore-parent-before-cleanup" {
        cid851_interpose_replace_parent_before_restore_cleanup(root.path, heldRoot.path)
    } else {
        throw CocoaError(.validationMissingMandatoryProperty)
    }
    var restoreFailed = false
    var recoveryRequired = false
    do {
        _ = try service.restoreRollingBackup(
            from: sourceURL,
            into: databaseURL,
            database: database,
            reopenDatabase: true
        )
    } catch {
        restoreFailed = true
        recoveryRequired = (error as? DatabaseSafetyService.RestoreError)?.requiresRecovery
            ?? true
    }
    let didMutation = cid850_interpose_did_mutation()
    cid850_interpose_reset()

    let displacedRoot = boundary == "restore-parent-before-cleanup" ? heldRoot : root
    let names = (try? FileManager.default.contentsOfDirectory(atPath: displacedRoot.path)) ?? []
    let hiddenRecoveryRetained = names.contains {
        $0.hasPrefix(".cid850-restore-") || $0.hasPrefix(".cid851-restore-")
    }
    let sourceMoved = FileManager.default.fileExists(atPath: heldSource.path)
    let parentReplaced = boundary == "restore-parent-before-cleanup"
        && FileManager.default.fileExists(atPath: root.path)
        && FileManager.default.fileExists(atPath: heldRoot.path)
    if sourceMoved {
        try FileManager.default.moveItem(at: heldSource, to: sourceURL)
    }
    if parentReplaced {
        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: heldRoot, to: root)
    }
    let recoveryDatabaseURL = root.appendingPathComponent("cider.db")
    let first = try service.reconcileInterruptedRestore(at: recoveryDatabaseURL)
    let second = try service.reconcileInterruptedRestore(at: recoveryDatabaseURL)
    let reopened = CiderDatabase()
    try reopened.open(at: recoveryDatabaseURL)
    let physicallyReopened = reopened.isOpen
    let integrityHealthy = try reopened.integrityCheck().isHealthy
    reopened.close()
    return RestoreFinalCapabilityResult(
        didMutation: didMutation,
        restoreFailed: restoreFailed,
        recoveryRequired: recoveryRequired,
        sourceMoved: sourceMoved,
        parentReplaced: parentReplaced,
        hiddenRecoveryRetained: hiddenRecoveryRetained,
        firstReconciliation: first.state.rawValue,
        secondReconciliation: second.state.rawValue,
        physicallyReopened: physicallyReopened,
        integrityHealthy: integrityHealthy
    )
}

@MainActor
private func runReceiptFIFO() throws -> ReceiptSpecialResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-receipt-fifo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let fifo = root.appendingPathComponent("unwritten.fifo")
    guard mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["receipt-fifo-child", fifo.path]
    child.standardOutput = Pipe()
    child.standardError = Pipe()
    try child.run()
    var completedWithoutWriter = false
    var writerWasNeeded = false
    for _ in 0..<1_000_000 {
        if !child.isRunning {
            completedWithoutWriter = true
            break
        }
        let writerDescriptor = Darwin.open(fifo.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        if writerDescriptor >= 0 {
            writerWasNeeded = true
            Darwin.close(writerDescriptor)
            child.waitUntilExit()
            break
        }
    }
    if !completedWithoutWriter && !writerWasNeeded {
        child.terminate()
        child.waitUntilExit()
    }
    return ReceiptSpecialResult(
        completedWithoutWriter: completedWithoutWriter,
        rejected: child.terminationReason == .exit && child.terminationStatus == 0
    )
}

@MainActor
private func runReceiptFIFOChild(path: String) -> Never {
    let fifo = URL(fileURLWithPath: path)
    let receipt = DatabaseSafetyService.failedCreationReceipt(
        for: .retainedArtifact(
            kind: .verification,
            state: .unusable,
            detail: "fifo fixture",
            url: fifo
        )
    )
    exit(receipt.backupURL == nil ? 0 : 2)
}

private func execute(_ handle: OpaquePointer, _ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
    if result != SQLITE_OK {
        let message = errorMessage.map { String(cString: $0) } ?? "SQLite error \(result)"
        sqlite3_free(errorMessage)
        throw NSError(domain: "SQLite", code: Int(result), userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

private func scalarInt(databaseURL: URL, sql: String) throws -> Int {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(
        databaseURL.path,
        &handle,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK, let handle else {
        sqlite3_close_v2(handle)
        throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_close_v2(handle) }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_ROW else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return Int(sqlite3_column_int64(statement, 0))
}

@MainActor
private func runSharedCreation(databasePath: String) throws -> SharedCreationResult {
    let database = CiderDatabase()
    defer { database.close() }
    try database.open(at: URL(fileURLWithPath: databasePath))
    let receipt = DatabaseSafetyService().createManualBackup(database: database)
    return SharedCreationResult(
        created: receipt.created,
        verified: receipt.verified,
        usable: receipt.usable,
        failureKind: receipt.failureKind?.rawValue
    )
}

@MainActor
private func runSharedCreationWithLockProbe(
    databasePath: String,
    role: Int,
    readyPath: String,
    releasePath: String,
    resultPath: String
) throws -> SharedCreationResult {
    cid850_interpose_configure_flock_probe(
        Int32(role),
        readyPath,
        releasePath,
        resultPath
    )
    return try runSharedCreation(databasePath: databasePath)
}

@MainActor
private func runSharedCreationCrashingBeforeRetirement(databasePath: String) throws -> Never {
    cid850_interpose_crash_before_renameatx_np(".ciderbackup")
    _ = try runSharedCreation(databasePath: databasePath)
    exit(87)
}

@MainActor
private func runSharedCreationCrashingAfterPublication(databasePath: String) throws -> SharedCreationResult {
    cid850_interpose_crash_after_fclonefileat(".ciderbackup")
    return try runSharedCreation(databasePath: databasePath)
}

private func sqliteSetByteUpperBound(_ databaseURL: URL) throws -> Int64 {
    var total: Int64 = 0
    for suffix in ["", "-wal", "-shm"] {
        var value = stat()
        let path = databaseURL.path + suffix
        if lstat(path, &value) != 0 {
            if suffix != "", errno == ENOENT { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let (sum, overflow) = total.addingReportingOverflow(Int64(value.st_size))
        guard !overflow else { throw CocoaError(.fileReadTooLarge) }
        total = sum
    }
    return total
}

private func regularByteCount(_ url: URL) throws -> Int64 {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    if value.st_mode & S_IFMT == S_IFREG { return Int64(value.st_size) }
    guard value.st_mode & S_IFMT == S_IFDIR else { return 0 }
    return try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: []
    ).reduce(Int64(0)) { try $0 + regularByteCount($1) }
}

private func checkedAggregateSum(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow, lhs >= 0, rhs >= 0 else { throw CocoaError(.fileReadTooLarge) }
    return sum
}

private func accountedTreeBytes(_ url: URL) throws -> Int64 {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let type = value.st_mode & S_IFMT
    if type == S_IFREG {
        return try checkedAggregateSum(
            Int64(value.st_size),
            DatabaseSafetyService.retentionAccountingNodeOverheadBytes
        )
    }
    guard type == S_IFDIR else { throw CocoaError(.fileReadUnknown) }
    var total = DatabaseSafetyService.retentionAccountingNodeOverheadBytes
    for child in try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: []
    ) {
        total = try checkedAggregateSum(total, try accountedTreeBytes(child))
    }
    return total
}

private func accountedPolicyBytes(_ policyURL: URL) throws -> Int64 {
    var total = try checkedAggregateSum(
        DatabaseSafetyService.retentionLedgerPayloadBytes,
        DatabaseSafetyService.retentionLedgerOverheadBytes
    )
    for child in try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: nil,
        options: []
    ) {
        total = try checkedAggregateSum(total, try accountedTreeBytes(child))
    }
    return total
}

private func ownershipLedgerData(_ policyURL: URL) throws -> Data? {
    let authorityURL = policyURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let attribute = "com.cider.cid850.parent-ownership-ledger-v1"
    let size = getxattr(authorityURL.path, attribute, nil, 0, 0, 0)
    if size < 0 {
        if errno == ENOATTR { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var data = Data(count: size)
    let read = data.withUnsafeMutableBytes { bytes in
        getxattr(authorityURL.path, attribute, bytes.baseAddress, bytes.count, 0, 0)
    }
    guard read == size else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return data
}

private func extendedAttribute(at url: URL, name: String) throws -> Data? {
    let size = getxattr(url.path, name, nil, 0, 0, 0)
    if size < 0 {
        if errno == ENOATTR { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var data = Data(count: size)
    let read = data.withUnsafeMutableBytes { bytes in
        getxattr(url.path, name, bytes.baseAddress, bytes.count, 0, 0)
    }
    guard read == size else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return data
}

@MainActor
private func runAggregateGrowthBoundary() throws -> AggregateGrowthResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-growth-harness-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = CiderDatabase()
    defer { database.close() }
    try database.open(at: databaseURL)

    let admittedDatabaseBytes = try sqliteSetByteUpperBound(databaseURL)
    let incomingPackageBytes = admittedDatabaseBytes
        + DatabaseSafetyService.retentionMaximumManifestBytes
        + 3 * DatabaseSafetyService.retentionAccountingNodeOverheadBytes
    let policyCap = DatabaseSafetyService.retentionLedgerPayloadBytes
        + DatabaseSafetyService.retentionLedgerOverheadBytes
        + 2 * incomingPackageBytes
    let ready = root.appendingPathComponent("growth-ready.fifo")
    let release = root.appendingPathComponent("growth-release.fifo")
    let result = root.appendingPathComponent("growth-result.fifo")
    for fifo in [ready, release, result] {
        guard mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    let readyDescriptor = Darwin.open(ready.path, O_RDWR | O_CLOEXEC)
    let releaseDescriptor = Darwin.open(release.path, O_RDWR | O_CLOEXEC)
    let resultDescriptor = Darwin.open(result.path, O_RDWR | O_CLOEXEC)
    guard readyDescriptor >= 0, releaseDescriptor >= 0, resultDescriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer {
        Darwin.close(readyDescriptor)
        Darwin.close(releaseDescriptor)
        Darwin.close(resultDescriptor)
    }

    cid850_interpose_reset()
    cid850_interpose_pause_after_stage_ownership(ready.path, release.path)
    Thread.detachNewThread {
        var readyByte: UInt8 = 0
        _ = Darwin.read(readyDescriptor, &readyByte, 1)
        var writer: OpaquePointer?
        var succeeded = sqlite3_open_v2(
            databaseURL.path,
            &writer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK
        if let writer, succeeded {
            sqlite3_busy_timeout(writer, 5_000)
            let growthBytes = admittedDatabaseBytes + 1_048_576
            succeeded = (try? execute(
                writer,
                "CREATE TABLE aggregate_growth(payload BLOB NOT NULL); "
                    + "INSERT INTO aggregate_growth(payload) VALUES (zeroblob(\(growthBytes)));"
            )) != nil
        }
        sqlite3_close_v2(writer)
        var resultByte: UInt8 = succeeded ? 49 : 48
        _ = Darwin.write(resultDescriptor, &resultByte, 1)
        var releaseByte: UInt8 = 82
        _ = Darwin.write(releaseDescriptor, &releaseByte, 1)
    }

    let service = DatabaseSafetyService(maximumPolicyBytes: policyCap)
    let receipt = service.createManualBackup(database: database)
    var writerResult: UInt8 = 0
    _ = Darwin.read(resultDescriptor, &writerResult, 1)
    let didMutation = cid850_interpose_did_mutation()
    cid850_interpose_reset()

    guard let retainedURL = receipt.backupURL else { throw CocoaError(.fileNoSuchFile) }
    let databaseBytes = try regularByteCount(retainedURL.appendingPathComponent("database.sqlite"))
    let manifestBytes = try regularByteCount(retainedURL.appendingPathComponent("manifest.json"))
    let policyURL = service.rollingBackupsDirectory(for: databaseURL)
    let entriesBeforeRepeatedRefusal = try fingerprintTree(policyURL)
    let repeated = service.createManualBackup(database: database)
    let entriesAfterRepeatedRefusal = try fingerprintTree(policyURL)
    let accountedPolicyBytes = DatabaseSafetyService.retentionLedgerPayloadBytes
        + DatabaseSafetyService.retentionLedgerOverheadBytes
        + 3 * DatabaseSafetyService.retentionAccountingNodeOverheadBytes
        + databaseBytes
        + manifestBytes
    return AggregateGrowthResult(
        didMutation: didMutation,
        writerSucceeded: writerResult == 49,
        failureKind: receipt.failureKind?.rawValue,
        created: receipt.created,
        verified: receipt.verified,
        usable: receipt.usable,
        retainedDatabaseBytes: databaseBytes,
        retainedManifestBytes: manifestBytes,
        accountedPolicyBytes: accountedPolicyBytes,
        policyCap: policyCap,
        repeatedFailureKind: repeated.failureKind?.rawValue,
        repeatedRefusalCreatedNoArtifact: repeated.backupURL == nil
            && entriesAfterRepeatedRefusal == entriesBeforeRepeatedRefusal
    )
}

@MainActor
private func runAggregateCloneRaceBoundary(_ boundary: String) throws -> AggregateCloneRaceResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-clone-race-harness-\(UUID().uuidString)", isDirectory: true)
    let databaseURL = root.appendingPathComponent("cider.db")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = CiderDatabase()
    defer { database.close() }
    try database.open(at: databaseURL)

    let seedService = DatabaseSafetyService()
    let priorArtifact = try seedService.createRollingBackup(
        reason: "clone-race-prior",
        database: database
    )
    let policyURL = seedService.rollingBackupsDirectory(for: databaseURL)
    let priorURL = policyURL.appendingPathComponent(priorArtifact.packageName, isDirectory: true)
    let sourceBefore = try sqliteSetFingerprint(databaseURL)
    let priorBefore = try fingerprintTree(priorURL)
    let inventoryBefore = try fingerprintTree(policyURL)
    let namesBefore = try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: nil,
        options: []
    ).map(\.lastPathComponent).sorted()
    let ledgerBefore = try ownershipLedgerData(policyURL)
    let admittedDatabaseBytes = try sqliteSetByteUpperBound(databaseURL)
    var incomingPackageBytes = try checkedAggregateSum(
        admittedDatabaseBytes,
        DatabaseSafetyService.retentionMaximumManifestBytes
    )
    for _ in 0..<3 {
        incomingPackageBytes = try checkedAggregateSum(
            incomingPackageBytes,
            DatabaseSafetyService.retentionAccountingNodeOverheadBytes
        )
    }
    let policyCap = try checkedAggregateSum(
        try accountedPolicyBytes(policyURL),
        try checkedAggregateSum(incomingPackageBytes, incomingPackageBytes)
    )
    let service = DatabaseSafetyService(maximumPolicyBytes: policyCap)
    var mutationsCompleted = 0
    var failureKinds: [String?] = []
    var everyAttemptFailed = true

    for _ in 0..<3 {
        cid850_interpose_reset()
        switch boundary {
        case "aggregate-stage-grow":
            cid850_interpose_grow_staged_child_before_clone()
        case "aggregate-stage-replace":
            cid850_interpose_replace_staged_child_before_clone()
        case "aggregate-published-grow":
            cid850_interpose_grow_published_child_after_clone()
        case "aggregate-published-replace":
            cid850_interpose_replace_published_child_after_clone()
        default:
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let receipt = service.createManualBackup(database: database)
        if cid850_interpose_did_mutation() { mutationsCompleted += 1 }
        failureKinds.append(receipt.failureKind?.rawValue)
        everyAttemptFailed = everyAttemptFailed
            && !receipt.created && !receipt.verified && !receipt.usable
    }
    cid850_interpose_reset()

    let namesAfter = try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: nil,
        options: []
    ).map(\.lastPathComponent).sorted()
    return AggregateCloneRaceResult(
        mutationsCompleted: mutationsCompleted,
        failureKinds: failureKinds,
        everyAttemptFailed: everyAttemptFailed,
        sourceUnchanged: try sqliteSetFingerprint(databaseURL) == sourceBefore,
        priorUnchanged: try fingerprintTree(priorURL) == priorBefore,
        exactInventoryUnchanged: try fingerprintTree(policyURL) == inventoryBefore,
        exactLedgerUnchanged: try ownershipLedgerData(policyURL) == ledgerBefore,
        accountedPolicyBytes: try accountedPolicyBytes(policyURL),
        policyCap: policyCap,
        noDuplicateStageOrPublication: namesAfter == namesBefore
    )
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func cid851RestoreJournalName(databaseName: String) -> String {
    ".cid851-restore-\(sha256(Data(databaseName.utf8)).prefix(16)).json"
}

private func fingerprintTree(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ) else { return result }
    let rootPrefix = root.resolvingSymlinksInPath().path + "/"
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let relative = String(url.resolvingSymlinksInPath().path.dropFirst(rootPrefix.count))
        result[relative] = SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }
    return result
}

/// A restart-stability fingerprint for every reachable and hidden member.
/// It includes directory/file identity, mode/link/size metadata, exact xattr
/// names and bytes (including transaction and ownership-ledger state), and
/// regular-file contents. The relative path inventory captures the generated
/// transaction graph, packages, and the complete live DB/WAL/SHM namespace.
private func completeTreeFingerprint(_ root: URL) throws -> [String: String] {
    var urls = [root]
    if let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ) {
        urls.append(contentsOf: enumerator.compactMap { $0 as? URL })
    }
    var result: [String: String] = [:]
    for url in urls.sorted(by: { $0.path < $1.path }) {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let relative = url.path == root.path
            ? "."
            : String(url.path.dropFirst(root.path.count + 1))
        var fields = [
            "dev=\(metadata.st_dev)",
            "ino=\(metadata.st_ino)",
            "gen=\(metadata.st_gen)",
            "mode=\(metadata.st_mode)",
            "nlink=\(metadata.st_nlink)",
            "size=\(metadata.st_size)",
        ]
        let attributeBytes = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard attributeBytes >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if attributeBytes > 0 {
            var names = [CChar](repeating: 0, count: attributeBytes)
            guard listxattr(url.path, &names, names.count, XATTR_NOFOLLOW) == attributeBytes else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var start = 0
            var attributes: [String] = []
            for index in 0..<names.count where names[index] == 0 {
                let name = names[start..<index].map { UInt8(bitPattern: $0) }
                start = index + 1
                guard let attribute = String(bytes: name, encoding: .utf8) else { continue }
                let size = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
                guard size >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                var data = Data(count: size)
                let read = data.withUnsafeMutableBytes {
                    getxattr(
                        url.path,
                        attribute,
                        $0.baseAddress,
                        $0.count,
                        0,
                        XATTR_NOFOLLOW
                    )
                }
                guard read == size else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                attributes.append("\(attribute)=\(data.base64EncodedString())")
            }
            fields.append("xattrs=\(attributes.sorted().joined(separator: ","))")
        } else {
            fields.append("xattrs=")
        }
        if metadata.st_mode & S_IFMT == S_IFREG {
            fields.append("sha256=\(sha256(try Data(contentsOf: url)))")
        }
        result[relative] = fields.joined(separator: "|")
    }
    return result
}

private func sqliteSetFingerprint(_ databaseURL: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for suffix in ["", "-wal", "-shm"] {
        let url = URL(fileURLWithPath: databaseURL.path + suffix)
        let name = suffix.isEmpty ? "db" : String(suffix.dropFirst())
        if FileManager.default.fileExists(atPath: url.path) {
            result[name] = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }
                .joined()
        } else {
            result[name] = "absent"
        }
    }
    return result
}

do {
    let boundary = CommandLine.arguments.dropFirst().first ?? ""
    if boundary == "shared-create" {
        let databasePath = CommandLine.arguments.dropFirst(2).first ?? ""
        FileHandle.standardOutput.write(try JSONEncoder().encode(runSharedCreation(databasePath: databasePath)))
    } else if boundary == "shared-create-lock-probe" {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        let result = try runSharedCreationWithLockProbe(
            databasePath: arguments[0],
            role: Int(arguments[1]) ?? 0,
            readyPath: arguments[2],
            releasePath: arguments[3],
            resultPath: arguments[4]
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    } else if boundary == "shared-create-crash-before-retire" {
        let databasePath = CommandLine.arguments.dropFirst(2).first ?? ""
        try runSharedCreationCrashingBeforeRetirement(databasePath: databasePath)
    } else if boundary == "shared-create-crash-after-publish" {
        let databasePath = CommandLine.arguments.dropFirst(2).first ?? ""
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(
                runSharedCreationCrashingAfterPublication(databasePath: databasePath)
            )
        )
    } else if boundary == "aggregate-growth" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runAggregateGrowthBoundary())
        )
    } else if boundary.hasPrefix("aggregate-stage-")
        || boundary.hasPrefix("aggregate-published-") {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runAggregateCloneRaceBoundary(boundary))
        )
    } else if boundary.hasPrefix("restore-sidecar-") {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreSidecarBoundary(boundary))
        )
    } else if boundary == "restore-post-swap-fsync" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreFsyncBoundary(failureCount: 1))
        )
    } else if boundary == "restore-post-swap-and-rollback-fsync" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreFsyncBoundary(failureCount: 2))
        )
    } else if boundary == "restore-crash-after-swap" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreCrashBoundary())
        )
    } else if boundary == "restore-crash-before-completion" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreCrashBoundary(crashBeforeCompletion: true))
        )
    } else if boundary == "restore-crash-same-file-change" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreSameFileChangeBoundary())
        )
    } else if boundary == "restore-record-removal-fsync" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreRecordRemovalSyncBoundary())
        )
    } else if boundary == "restore-crash-after-swap-child" {
        let rootPath = CommandLine.arguments.dropFirst(2).first ?? ""
        try runRestoreCrashChild(rootPath: rootPath)
    } else if boundary == "restore-crash-before-completion-child" {
        let rootPath = CommandLine.arguments.dropFirst(2).first ?? ""
        try runRestoreCrashChild(rootPath: rootPath, crashBeforeCompletion: true)
    } else if boundary == "restore-reopen-failure"
        || boundary == "restore-integrity-failure" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreValidationFailureBoundary(boundary))
        )
    } else if boundary == "restore-authority" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreAuthorityBoundary())
        )
    } else if boundary == "restore-architecture" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreArchitectureBoundary())
        )
    } else if boundary == "restore-v2-interruption-child" {
        try runInterruptionChild(Array(CommandLine.arguments.dropFirst(2)))
    } else if boundary.hasPrefix("restore-v2-interruption:") {
        let parts = boundary.split(separator: ":").map(String.init)
        guard parts.count == 6,
              let restoreBoundary = Int(parts[2]),
              let restoreOrdinal = Int(parts[3]),
              let reconciliationBoundary = Int(parts[4]),
              let reconciliationOrdinal = Int(parts[5]) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(
            runRestoreV2InterruptionBoundary(
                mode: parts[1],
                restoreBoundary: restoreBoundary,
                restoreOrdinal: restoreOrdinal,
                reconciliationBoundary: reconciliationBoundary,
                reconciliationOrdinal: reconciliationOrdinal
            )
        ))
    } else if boundary == "restore-v2-planned-unknown" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestorePlannedUnknownBoundary())
        )
    } else if boundary == "restore-v2-planned-fifo" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestorePlannedFIFOBoundary())
        )
    } else if boundary == "restore-v2-planned-fifo-reconcile-child" {
        let path = CommandLine.arguments.dropFirst(2).first ?? ""
        runPlannedFIFOReconciliationChild(databaseURL: URL(fileURLWithPath: path))
    } else if boundary.hasPrefix("restore-v2-package-special:") {
        let parts = boundary.split(separator: ":").map(String.init)
        guard parts.count == 3 else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(
                runPackageSpecialMemberBoundary(parts[2], member: parts[1])
            )
        )
    } else if boundary.hasPrefix("restore-v2-raw-special:") {
        let kind = String(boundary.split(separator: ":").last ?? "")
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRawSpecialMemberBoundary(kind))
        )
    } else if boundary == "restore-v2-terminal-evidence" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runTerminalEvidenceBoundary())
        )
    } else if boundary == "restore-v2-record-removal-reoccupation" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRecordRemovalReoccupationBoundary())
        )
    } else if boundary == "restore-v2-held-descriptor-evidence" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runHeldDescriptorEvidenceBoundary())
        )
    } else if boundary.hasPrefix("qualified-receipt-race:") {
        let action = String(boundary.split(separator: ":").last ?? "")
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runQualifiedReceiptRaceBoundary(action))
        )
    } else if boundary.hasPrefix("restore-v2-retention-collision:") {
        let attack = String(boundary.split(separator: ":").last ?? "")
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRetentionCollisionBoundary(attack))
        )
    } else if boundary == "restore-v2-malformed-graph" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreMalformedGraphBoundary())
        )
    } else if boundary.hasPrefix("restore-v2-member-seam:") {
        let operation = String(boundary.split(separator: ":").last ?? "")
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreMemberSeamBoundary(operation))
        )
    } else if boundary == "restore-source-before-cleanup"
        || boundary == "restore-parent-before-cleanup" {
        FileHandle.standardOutput.write(
            try JSONEncoder().encode(runRestoreFinalCapabilityBoundary(boundary))
        )
    } else if boundary == "receipt-fifo" {
        FileHandle.standardOutput.write(try JSONEncoder().encode(runReceiptFIFO()))
    } else if boundary == "receipt-fifo-child" {
        let path = CommandLine.arguments.dropFirst(2).first ?? ""
        runReceiptFIFOChild(path: path)
    } else {
        let result = try runBoundary(boundary)
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    }
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
