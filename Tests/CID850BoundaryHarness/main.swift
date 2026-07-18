import CID850Interpose
import CryptoKit
import Darwin
import Foundation
import SQLite3
@testable import Cider

private struct BoundaryResult: Encodable {
    let didAttack: Bool
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
        cid850_interpose_replace_before_lseek("/database.sqlite", heldName, 7)
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
    let didAttack = cid850_interpose_did_attack()
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
        didAttack: didAttack,
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
    let didAttack: Bool
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
    let attacksCompleted: Int
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
    let didAttack: Bool
    let restoreFailed: Bool
    let databaseRolledBack: Bool
    let unexpectedOccupantPreserved: Bool
    let quarantinedOriginalPreserved: Bool
    let reopened: Bool
}

private struct RestoreFsyncResult: Encodable {
    let didAttack: Bool
    let restoreFailed: Bool
    let originalSQLiteSetRestored: Bool
    let replacementRetained: Bool
    let unexpectedOccupantsPreserved: Bool
    let reopened: Bool
    let failureMessage: String
    let originalFingerprint: [String: String]
    let finalFingerprint: [String: String]
}

private struct ReceiptSpecialResult: Encodable {
    let completedWithoutWriter: Bool
    let rejected: Bool
}

@MainActor
private func runRestoreSidecarBoundary(_ boundary: String) throws -> RestoreSidecarResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cid850-restore-sidecar-\(UUID().uuidString)", isDirectory: true)
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
    let backup = try service.createRollingBackup(reason: "sidecar-source", database: database)
    let backupURL = service.rollingBackupsDirectory(for: databaseURL)
        .appendingPathComponent(backup.packageName, isDirectory: true)
    try database.runSQL("""
        INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
        VALUES ('live-after-backup', 'Live', '#775533', 'custom', 1, 1);
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
    let before = try sqliteSetFingerprint(databaseURL)
    let attackedSuffix: String
    cid850_interpose_reset()
    switch boundary {
    case "restore-sidecar-before-wal":
        attackedSuffix = "-wal"
        cid850_interpose_create_sidecar_before_swap("cider.db", attackedSuffix)
    case "restore-sidecar-after-shm":
        attackedSuffix = "-shm"
        cid850_interpose_create_sidecar_after_swap("cider.db", attackedSuffix)
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
    let didAttack = cid850_interpose_did_attack()
    cid850_interpose_reset()
    let unexpectedURL = URL(fileURLWithPath: databaseURL.path + attackedSuffix)
    let unexpectedOccupantPreserved = (try? Data(contentsOf: unexpectedURL))
        == Data("cid850-unexpected-sidecar".utf8)
    let hiddenCandidates = (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    ))?.filter {
        $0.lastPathComponent.hasPrefix(".cid850-restore-")
            && $0.lastPathComponent.hasSuffix(attackedSuffix)
    } ?? []
    let originalHash = before[String(attackedSuffix.dropFirst())]
    let quarantinedOriginalPreserved = hiddenCandidates.contains { candidate in
        guard let data = try? Data(contentsOf: candidate) else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == originalHash
    }
    let databaseRolledBack = (try? Data(contentsOf: databaseURL)).map {
        SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
    } == before["db"]
    return RestoreSidecarResult(
        didAttack: didAttack,
        restoreFailed: restoreFailed,
        databaseRolledBack: databaseRolledBack,
        unexpectedOccupantPreserved: unexpectedOccupantPreserved,
        quarantinedOriginalPreserved: quarantinedOriginalPreserved,
        reopened: database.isOpen
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
    }
    let didAttack = cid850_interpose_did_attack()
    cid850_interpose_reset()
    let final = try sqliteSetFingerprint(databaseURL)
    let entries = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil,
        options: []
    )
    let replacementRetained = entries.contains { entry in
        guard entry.lastPathComponent.hasPrefix(".cid850-restore-"),
              entry.pathExtension == "sqlite",
              let data = try? Data(contentsOf: entry) else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            == replacementHash
    }
    let unexpectedOccupantsPreserved = entries
        .filter { $0.lastPathComponent.hasPrefix(".cid850-unexpected-") }
        .allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    return RestoreFsyncResult(
        didAttack: didAttack,
        restoreFailed: restoreFailed,
        originalSQLiteSetRestored: final == original,
        replacementRetained: replacementRetained,
        unexpectedOccupantsPreserved: unexpectedOccupantsPreserved,
        reopened: database.isOpen,
        failureMessage: failureMessage,
        originalFingerprint: original,
        finalFingerprint: final
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
    let didAttack = cid850_interpose_did_attack()
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
        didAttack: didAttack,
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
    var attacksCompleted = 0
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
        if cid850_interpose_did_attack() { attacksCompleted += 1 }
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
        attacksCompleted: attacksCompleted,
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
