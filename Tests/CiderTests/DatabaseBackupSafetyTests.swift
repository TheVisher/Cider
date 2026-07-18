import CryptoKit
import Darwin
import Foundation
import SQLite3
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("CID-850 database backup safety", .serialized)
@MainActor
struct DatabaseBackupSafetyTests {
    @Test("backup creation never installs a persistent append-only guard")
    func appendOnlyRestorationFailureCannotPersistAcrossRestart() throws {
        let result = try runCID850BoundaryHarness("append-restore")

        #expect(!result.didAttack)
        #expect(!result.policyAppendOnly)
        #expect(result.created)
        #expect(result.verified)
        #expect(result.usable)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
    }

    @Test("recursive policy creation cannot follow an intermediate backups symlink")
    func intermediatePolicySymlinkCannotRedirectBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let redirectedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-policy-redirect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: redirectedRoot) }
        try FileManager.default.createDirectory(at: redirectedRoot, withIntermediateDirectories: false)
        try Data("redirect target marker".utf8).write(to: redirectedRoot.appendingPathComponent("marker.bin"))
        let redirectedBefore = try fingerprintTree(redirectedRoot)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let manager = IntermediatePolicySymlinkFileManager(
            sourceRoot: fixture.root,
            redirectedRoot: redirectedRoot
        )
        let service = DatabaseSafetyService(fileManager: manager)
        try manager.installSymlink()

        let receipt = service.createManualBackup(database: fixture.database)

        #expect(manager.didInstallSymlink)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(receipt.failureKind == .staging)
        #expect(try fingerprintTree(redirectedRoot) == redirectedBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print(
            "CID850_EVIDENCE policy_symlink redirect=\(fingerprintDescription(redirectedBefore)) "
                + "source=\(fingerprintDescription(sourceBefore))"
        )
    }

    @Test("staging creation cannot select a replacement installed after mkdirat returns")
    func stagingMkdiratToOpenatReplacementFailsClosed() throws {
        let result = try runCID850BoundaryHarness("staging")

        #expect(!result.didAttack)
        #expect(result.created)
        #expect(result.verified)
        #expect(result.usable)
        #expect(result.failureKind == nil)
        #expect(!result.heldExists)
        #expect(result.policyArtifactCount == 2)
        #expect(result.retainedVerified)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
        print(
            "CID850_EVIDENCE staging_mkdir_open replacement_blocked=true "
                + "source=\(fingerprintDescription(result.sourceFingerprint)) "
                + "prior=\(fingerprintDescription(result.priorFingerprint))"
        )
    }

    @Test("publication cannot bless a byte-identical replacement installed after atomic rename returns")
    func publicationCloneToOpenReplacementFailsClosed() throws {
        let result = try runCID850BoundaryHarness("publication")

        #expect(result.didAttack)
        #expect(!result.created)
        #expect(!result.verified)
        #expect(!result.usable)
        #expect(result.failureKind == "publication")
        #expect(result.heldExists)
        #expect(!result.receiptNamesHeldArtifact)
        #expect(result.replacementMatchesHeld)
        #expect(result.retainedVerified)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
        print(
            "CID850_EVIDENCE publication_clone_open replacement_blocked=true "
                + "source=\(fingerprintDescription(result.sourceFingerprint)) "
                + "prior=\(fingerprintDescription(result.priorFingerprint))"
        )
    }

    @Test("descriptor-bound publication selects the pinned inode after a source path replacement")
    func pathnamePublicationSelectsReplacementAtFinalBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-red-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let held = root.appendingPathComponent("held", isDirectory: true)
        let replacement = root.appendingPathComponent("replacement", isDirectory: true)
        let published = root.appendingPathComponent("published", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
        try Data("pinned source".utf8).write(to: source.appendingPathComponent("identity.bin"))
        try Data("unpinned replacement".utf8).write(to: replacement.appendingPathComponent("identity.bin"))
        let pinnedFingerprint = try fingerprintTree(source)
        let replacementFingerprint = try fingerprintTree(replacement)

        let parentDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(parentDescriptor >= 0)
        defer { if parentDescriptor >= 0 { Darwin.close(parentDescriptor) } }
        let sourceDescriptor = Darwin.openat(
            parentDescriptor,
            "source",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        #expect(sourceDescriptor >= 0)
        defer { if sourceDescriptor >= 0 { Darwin.close(sourceDescriptor) } }

        try FileManager.default.moveItem(at: source, to: held)
        try FileManager.default.moveItem(at: replacement, to: source)
        #expect(DatabaseSafetyService.clonePinnedDirectoryAtomically(
            sourceDescriptor: sourceDescriptor,
            destinationDirectoryDescriptor: parentDescriptor,
            destinationName: "published"
        ) == 0)

        print(
            "CID850_EVIDENCE descriptor_publication pinned=\(fingerprintDescription(pinnedFingerprint)) "
                + "replacement=\(fingerprintDescription(replacementFingerprint)) "
                + "published=\(try fingerprintDescription(fingerprintTree(published)))"
        )
        #expect(try fingerprintTree(held) == pinnedFingerprint)
        #expect(try fingerprintTree(published) == pinnedFingerprint)
        #expect(try fingerprintTree(published) != replacementFingerprint)
    }

    @Test("production publication never moves a replacement selected at the final source-name boundary")
    func productionPublicationDoesNotSelectReplacementSourceName() throws {
        let result = try runCID850BoundaryHarness("publication-source")

        #expect(!result.didAttack)
        #expect(!result.replacementStayedAtSource)
        #expect(result.created)
        #expect(result.usable)
        #expect(!result.heldExists)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
    }

    @Test("descriptor-bound publication is collision-safe and preserves both source and destination")
    func descriptorBoundPublicationDoesNotReplaceDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-collision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("pinned source".utf8).write(to: source.appendingPathComponent("identity.bin"))
        try Data("occupied destination".utf8).write(to: destination.appendingPathComponent("identity.bin"))
        let sourceBefore = try fingerprintTree(source)
        let destinationBefore = try fingerprintTree(destination)
        let parentDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(parentDescriptor >= 0)
        defer { if parentDescriptor >= 0 { Darwin.close(parentDescriptor) } }
        let sourceDescriptor = Darwin.openat(
            parentDescriptor,
            "source",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        #expect(sourceDescriptor >= 0)
        defer { if sourceDescriptor >= 0 { Darwin.close(sourceDescriptor) } }

        #expect(DatabaseSafetyService.clonePinnedDirectoryAtomically(
            sourceDescriptor: sourceDescriptor,
            destinationDirectoryDescriptor: parentDescriptor,
            destinationName: "destination"
        ) == -1)
        print(
            "CID850_EVIDENCE descriptor_collision source=\(fingerprintDescription(sourceBefore)) "
                + "destination=\(fingerprintDescription(destinationBefore))"
        )
        #expect(errno == EEXIST)
        #expect(try fingerprintTree(source) == sourceBefore)
        #expect(try fingerprintTree(destination) == destinationBefore)
    }

    @Test("same-second same-reason backups publish distinct retained artifacts")
    func sameSecondRequestsRemainDistinct() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let first = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "same-second",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let firstFingerprint = try fingerprintTree(first)
        let second = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "same-second",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )

        #expect(first.standardizedFileURL != second.standardizedFileURL)
        #expect(try fingerprintTree(first) == firstFingerprint)
        #expect(FileManager.default.fileExists(atPath: second.path))
        let backups = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
        #expect(backups.count == 2)
        #expect(backups.allSatisfy { $0.verification.isVerified })
    }

    @Test("retention preserves every verified excess package without pathname mutation")
    func retentionPreservesExcessPackagesExactly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var priorFingerprints: [URL: [String: String]] = [:]
        for index in 0..<7 {
            let url = try observedURL(
                for: fixture.service.createRollingBackup(
                    reason: "retention-prior-\(index)",
                    database: fixture.database
                ),
                service: fixture.service,
                databaseURL: fixture.databaseURL
            )
            priorFingerprints[url] = try fingerprintTree(url)
        }
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        let receipt = try fixture.service.createRollingBackupReceipt(
            reason: "retention-excess",
            database: fixture.database
        )

        #expect(receipt.usable)
        #expect(receipt.warnings.isEmpty)
        #expect(try hiddenEntries(
            in: fixture.service.rollingBackupsDirectory(for: fixture.databaseURL),
            suffix: ".pruning"
        ).isEmpty)
        for (url, fingerprint) in priorFingerprints {
            #expect(try fingerprintTree(url) == fingerprint)
            #expect(fixture.service.verifyBackup(at: url).isVerified)
        }
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).count == 8)
        print(
            "CID850_EVIDENCE retention_preserved count=8 source=\(fingerprintDescription(sourceBefore))"
        )
    }

    @Test("a full policy rotates its oldest verified slot without deleting or exhausting")
    func retentionCapacityRotatesVerifiedSlot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<8 {
            _ = try fixture.service.createRollingBackup(
                reason: "capacity-\(index)",
                database: fixture.database
            )
        }
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let listedBefore = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
        let preserved = try packageFingerprints(Array(listedBefore.prefix(7).map(\.url)))
        let rotatedURL = try #require(listedBefore.last?.url)
        let rotatedBefore = try fingerprintTree(rotatedURL)

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.created)
        #expect(receipt.verified)
        #expect(receipt.usable)
        #expect(receipt.failureKind == nil)
        #expect(receipt.backupURL == nil)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(try packageFingerprints(Array(listedBefore.prefix(7).map(\.url))) == preserved)
        #expect(try fingerprintTree(rotatedURL) != rotatedBefore)
        #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).count == 8)
    }

    @Test("aggregate capacity refuses before creating staging")
    func aggregateCapacityRefusesBeforeStagingCreation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "aggregate-cap-prior",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let before = try policyInventory(policy)
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let required = try aggregateProjectedCapacity(
            policyURL: policy,
            databaseURL: fixture.databaseURL
        )
        let bounded = DatabaseSafetyService(
            maximumPolicyBytes: required - 1
        )

        for _ in 0..<5 {
            let receipt = bounded.createManualBackup(database: fixture.database)
            #expect(receipt.failureKind == .retentionCapacity)
            #expect(!receipt.created && !receipt.verified && !receipt.usable)
            #expect(receipt.backupURL == nil)
            #expect(receipt.message.localizedCaseInsensitiveContains("no staging artifact"))
            #expect(try policyInventory(policy) == before)
            #expect(try fingerprintTree(prior) == priorBefore)
            #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        }
    }

    @Test("an aggregate admission exactly at the configured cap succeeds")
    func aggregateCapacityExactAtCapSucceeds() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let exactCap = try aggregateProjectedCapacity(
            policyURL: policy,
            databaseURL: fixture.databaseURL
        )
        let bounded = DatabaseSafetyService(maximumPolicyBytes: exactCap)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        let receipt = bounded.createManualBackup(database: fixture.database)

        #expect(receipt.created && receipt.verified && receipt.usable)
        #expect(receipt.failureKind == nil)
        #expect(try accountedPolicyBytes(policy) <= exactCap)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
    }

    @Test("source growth after admission is refused before the reserved descriptor is written")
    func sourceGrowthAfterAdmissionLeavesNoDurableExcess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admittedBytes = try sqliteSetByteUpperBound(fixture.databaseURL)
        try fixture.database.runSQL(
            "CREATE TABLE aggregate_growth(payload BLOB NOT NULL); "
                + "INSERT INTO aggregate_growth(payload) VALUES (zeroblob(\(admittedBytes + 1_048_576)));"
        )
        let destination = fixture.root.appendingPathComponent("growth-reservation.sqlite")
        let descriptor = Darwin.open(
            destination.path,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }

        do {
            try fixture.database.captureOnlineBackup(
                into: descriptor,
                maximumBytes: admittedBytes
            )
            Issue.record("Expected source growth to exceed the admitted capture bytes")
        } catch let error as CiderDatabaseBackupCapacityError {
            guard case .captureExceedsReservation(let actual, let reserved) = error else {
                Issue.record("Expected typed capture reservation refusal")
                return
            }
            #expect(actual > reserved)
            #expect(reserved == admittedBytes)
        }
        var value = stat()
        #expect(fstat(descriptor, &value) == 0)
        #expect(value.st_size == 0)
        #expect(try Data(contentsOf: destination).isEmpty)
    }

    @Test("production aggregate admission converts late source growth into a bounded typed receipt")
    func productionLateSourceGrowthRemainsDurablyBounded() throws {
        let result = try runCID850AggregateGrowthHarness()

        #expect(result.didAttack)
        #expect(result.writerSucceeded)
        #expect(result.failureKind == DatabaseSafetyService.BackupFailureKind.retentionCapacity.rawValue)
        #expect(!result.created && !result.verified && !result.usable)
        #expect(result.retainedDatabaseBytes == 0)
        #expect(result.retainedManifestBytes == 0)
        #expect(result.accountedPolicyBytes <= result.policyCap)
        #expect(result.repeatedFailureKind == DatabaseSafetyService.BackupFailureKind.retentionCapacity.rawValue)
        #expect(result.repeatedRefusalCreatedNoArtifact)
    }

    @Test("clone seam growth and replacement roll back without exceeding the exact cap", arguments: [
        "aggregate-stage-grow",
        "aggregate-stage-replace",
        "aggregate-published-grow",
        "aggregate-published-replace",
    ])
    func aggregateCloneSeamRacesRemainDurablyBounded(_ boundary: String) throws {
        let result = try runCID850AggregateCloneRaceHarness(boundary)

        #expect(result.attacksCompleted == 3)
        #expect(result.failureKinds.allSatisfy {
            $0 == DatabaseSafetyService.BackupFailureKind.retentionCapacity.rawValue
        })
        #expect(result.everyAttemptFailed)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
        #expect(result.exactInventoryUnchanged)
        #expect(result.exactLedgerUnchanged)
        #expect(result.accountedPolicyBytes <= result.policyCap)
        #expect(result.noDuplicateStageOrPublication)
    }

    @Test("visible hidden quarantine and ledger accounting each refuse before new staging")
    func everyAggregateRetentionClassCountsBeforeStaging() throws {
        let hiddenFixture = try Fixture()
        defer { hiddenFixture.remove() }
        let hiddenPolicy = hiddenFixture.service.rollingBackupsDirectory(for: hiddenFixture.databaseURL)
        try hiddenFixture.database.runSQL("BEGIN IMMEDIATE;")
        let hiddenFailure = hiddenFixture.service.createManualBackup(database: hiddenFixture.database)
        #expect(hiddenFailure.failureKind == .capture)
        try hiddenFixture.database.runSQL("ROLLBACK;")
        let hiddenURL = try #require(hiddenFailure.backupURL)
        let hiddenBefore = try policyInventory(hiddenPolicy)
        let hiddenRequired = try aggregateProjectedCapacity(
            policyURL: hiddenPolicy,
            databaseURL: hiddenFixture.databaseURL,
            reusing: hiddenURL
        )
        let hiddenBounded = DatabaseSafetyService(maximumPolicyBytes: hiddenRequired - 1)
        let hiddenReceipt = hiddenBounded.createManualBackup(database: hiddenFixture.database)
        #expect(hiddenReceipt.failureKind == .retentionCapacity)
        #expect(hiddenReceipt.backupURL == nil)
        #expect(try policyInventory(hiddenPolicy) == hiddenBefore)

        let quarantineFixture = try Fixture()
        defer { quarantineFixture.remove() }
        let quarantinePolicy = quarantineFixture.service.rollingBackupsDirectory(
            for: quarantineFixture.databaseURL
        )
        let corrupting = DatabaseSafetyService(
            fileManager: RepeatingPostPublicationCorruptionFileManager(policyURL: quarantinePolicy)
        )
        let quarantineFailure = corrupting.createManualBackup(database: quarantineFixture.database)
        #expect(quarantineFailure.failureKind == .verification)
        let quarantineURL = try #require(quarantineFailure.backupURL)
        #expect(quarantineURL.lastPathComponent == ".cid850-failed-publication.staging")
        let quarantineBefore = try policyInventory(quarantinePolicy)
        let quarantineRequired = try aggregateProjectedCapacity(
            policyURL: quarantinePolicy,
            databaseURL: quarantineFixture.databaseURL,
            reusing: quarantineURL
        )
        let quarantineBounded = DatabaseSafetyService(maximumPolicyBytes: quarantineRequired - 1)
        let quarantineReceipt = quarantineBounded.createManualBackup(database: quarantineFixture.database)
        #expect(quarantineReceipt.failureKind == .retentionCapacity)
        #expect(quarantineReceipt.backupURL == nil)
        #expect(try policyInventory(quarantinePolicy) == quarantineBefore)

        let ledgerFixture = try Fixture()
        defer { ledgerFixture.remove() }
        let ledgerPolicy = ledgerFixture.service.rollingBackupsDirectory(for: ledgerFixture.databaseURL)
        try FileManager.default.createDirectory(at: ledgerPolicy, withIntermediateDirectories: true)
        let ledgerBefore = try policyInventory(ledgerPolicy)
        let incoming = try incomingPackageByteUpperBound(ledgerFixture.databaseURL)
        let withoutLedgerReservation = try checkedTestSum(incoming, incoming)
        let ledgerBounded = DatabaseSafetyService(maximumPolicyBytes: withoutLedgerReservation)
        let ledgerReceipt = ledgerBounded.createManualBackup(database: ledgerFixture.database)
        #expect(ledgerReceipt.failureKind == .retentionCapacity)
        #expect(ledgerReceipt.backupURL == nil)
        #expect(try policyInventory(ledgerPolicy) == ledgerBefore)
    }

    @Test("aggregate accounting overflow is a typed capacity refusal")
    func aggregateAccountingOverflowRefusesTyped() throws {
        do {
            _ = try DatabaseSafetyService.checkedRetentionCapacitySum(Int64.max, 1)
            Issue.record("Expected checked aggregate accounting overflow")
        } catch let error as DatabaseSafetyService.BackupError {
            #expect(error.kind == .retentionCapacity)
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("overflow"))
        }
    }

    @Test("small-cap rotation and retained workspace reuse remain sustainable")
    func aggregateSmallCapRotationAndReuseRemainBounded() throws {
        let rotationFixture = try Fixture()
        defer { rotationFixture.remove() }
        let rotationPolicy = rotationFixture.service.rollingBackupsDirectory(
            for: rotationFixture.databaseURL
        )
        let incoming = try incomingPackageByteUpperBound(rotationFixture.databaseURL)
        var rotationCap = retentionLedgerAccountingBytes
        for _ in 0..<10 { rotationCap = try checkedTestSum(rotationCap, incoming) }
        let rotating = DatabaseSafetyService(maximumPolicyBytes: rotationCap)
        for index in 0..<16 {
            let receipt = try rotating.createRollingBackupReceipt(
                reason: "small-cap-rotation-\(index)",
                database: rotationFixture.database,
                updateState: false
            )
            #expect(receipt.created && receipt.verified && receipt.usable)
            #expect(try accountedPolicyBytes(rotationPolicy) <= rotationCap)
        }
        #expect(rotating.listRollingBackups(databaseURL: rotationFixture.databaseURL).count == 8)

        let reuseFixture = try Fixture()
        defer { reuseFixture.remove() }
        let reusePolicy = reuseFixture.service.rollingBackupsDirectory(for: reuseFixture.databaseURL)
        let reuseIncoming = try incomingPackageByteUpperBound(reuseFixture.databaseURL)
        let reuseCap = try checkedTestSum(
            retentionLedgerAccountingBytes,
            try checkedTestSum(reuseIncoming, reuseIncoming)
        )
        let reusing = DatabaseSafetyService(maximumPolicyBytes: reuseCap)
        try reuseFixture.database.runSQL("BEGIN IMMEDIATE;")
        for _ in 0..<5 {
            let failure = reusing.createManualBackup(database: reuseFixture.database)
            #expect(failure.failureKind == .capture)
            #expect(try policyInventory(reusePolicy).hiddenPackageCount == 1)
            #expect(try accountedPolicyBytes(reusePolicy) <= reuseCap)
        }
        try reuseFixture.database.runSQL("ROLLBACK;")
        let recovered = reusing.createManualBackup(database: reuseFixture.database)
        #expect(recovered.created && recovered.verified && recovered.usable)
        #expect(recovered.failureKind == nil)
        #expect(try accountedPolicyBytes(reusePolicy) <= reuseCap)
    }

    @Test("failed capture at full rotation preserves every visible verified package")
    func fullRotationFailurePreservesAllVisiblePackages() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<8 {
            _ = try fixture.service.createRollingBackup(
                reason: "full-failure-\(index)",
                database: fixture.database
            )
        }
        let visible = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).map(\.url)
        let before = try packageFingerprints(visible)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        try fixture.database.runSQL("BEGIN IMMEDIATE;")
        defer { try? fixture.database.runSQL("ROLLBACK;") }

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.failureKind == .capture)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(try packageFingerprints(visible) == before)
        #expect(visible.allSatisfy { fixture.service.verifyBackup(at: $0).isVerified })
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
    }

    @Test("foreign generated-looking slots and malformed lock residue are preserved without denial")
    func foreignAndMalformedResidueDoNotBlockOwnedRotation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<8 {
            _ = try fixture.service.createRollingBackup(
                reason: "foreign-prior-\(index)",
                database: fixture.database
            )
        }
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let lock = policy.appendingPathComponent(".cid850-retention.lock")
        let heldLock = policy.appendingPathComponent(".cid850-original-lock")
        if FileManager.default.fileExists(atPath: lock.path) {
            try FileManager.default.moveItem(at: lock, to: heldLock)
        }
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        try Data("malformed lock residue".utf8).write(to: lock.appendingPathComponent("marker"))
        let foreign = policy.appendingPathComponent(
            "20260717T170000Z-foreign-12345678-123.ciderbackup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: false)
        try Data("same uid but never established by Cider".utf8)
            .write(to: foreign.appendingPathComponent("database.sqlite"))
        let foreignBefore = try fingerprintTree(foreign)
        let malformedBefore = try fingerprintTree(lock)

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.created)
        #expect(receipt.verified)
        #expect(receipt.usable)
        #expect(receipt.failureKind == nil)
        #expect(try fingerprintTree(foreign) == foreignBefore)
        #expect(try fingerprintTree(lock) == malformedBefore)
        #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
            .filter { $0.verification.isVerified }.count == 8)
    }

    @Test("a copied public owner marker never authorizes slot reuse")
    func copiedOwnerMarkerCannotAuthorizeForeignSlotReuse() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legitimate = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "marker-source",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let copiedNonceValue = try extendedAttribute(
            at: legitimate,
            name: "com.cider.cid850.package-creation-nonce-v1"
        )
        let copiedNonce = try #require(copiedNonceValue)
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        try FileManager.default.createDirectory(at: policy, withIntermediateDirectories: true)
        let forged = policy.appendingPathComponent(
            ".cid850-forged-owner.staging",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: forged, withIntermediateDirectories: false)
        let foreignDatabase = forged.appendingPathComponent("database.sqlite")
        try Data("foreign same-uid bytes that must never be truncated".utf8).write(to: foreignDatabase)
        try setExtendedAttribute(
            at: forged,
            name: "com.cider.cid850.package-owner-v1",
            value: Data("cider-owned-package-v1".utf8)
        )
        try setExtendedAttribute(
            at: forged,
            name: "com.cider.cid850.package-creation-nonce-v1",
            value: copiedNonce
        )
        let forgedBefore = try fingerprintTree(forged)

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.created && receipt.verified && receipt.usable)
        #expect(try fingerprintTree(forged) == forgedBefore)
    }

    @Test("replaced or corrupt parent ownership ledgers preserve old slots and block admission")
    func ownershipLedgerReplacementAndCorruptionFailClosedAndRecover() throws {
        let first = try Fixture()
        defer { first.remove() }
        let second = try Fixture()
        defer { second.remove() }
        let firstArtifact = try observedURL(
            for: first.service.createRollingBackup(reason: "ledger-first", database: first.database),
            service: first.service,
            databaseURL: first.databaseURL
        )
        let secondArtifact = try observedURL(
            for: second.service.createRollingBackup(reason: "ledger-second", database: second.database),
            service: second.service,
            databaseURL: second.databaseURL
        )
        let firstLedgerValue = try extendedAttribute(
            at: first.root,
            name: "com.cider.cid850.parent-ownership-ledger-v1"
        )
        let firstLedger = try #require(firstLedgerValue)
        let secondBefore = try fingerprintTree(secondArtifact)

        try setExtendedAttribute(
            at: second.root,
            name: "com.cider.cid850.parent-ownership-ledger-v1",
            value: firstLedger
        )
        let afterReplacement = second.service.createManualBackup(database: second.database)
        #expect(afterReplacement.failureKind == .retentionCapacity)
        #expect(!afterReplacement.created && !afterReplacement.verified && !afterReplacement.usable)
        #expect(afterReplacement.backupURL?.standardizedFileURL == secondArtifact.standardizedFileURL)
        let replacementVerification = second.service.verifyBackup(at: secondArtifact)
        #expect(replacementVerification.state == .unusable)
        #expect(!replacementVerification.isVerified)
        #expect(replacementVerification.retainedBytesUnchanged)
        #expect(replacementVerification.messages.contains {
            $0.localizedCaseInsensitiveContains("ownership ledger")
        })
        #expect(try fingerprintTree(secondArtifact) == secondBefore)

        try setExtendedAttribute(
            at: second.root,
            name: "com.cider.cid850.parent-ownership-ledger-v1",
            value: Data("not a ledger".utf8)
        )
        let afterCorruption = second.service.createManualBackup(database: second.database)
        #expect(afterCorruption.failureKind == .retentionCapacity)
        #expect(!afterCorruption.created && !afterCorruption.verified && !afterCorruption.usable)
        #expect(afterCorruption.backupURL?.standardizedFileURL == secondArtifact.standardizedFileURL)
        let corruptVerification = second.service.verifyBackup(at: secondArtifact)
        #expect(corruptVerification.state == .unusable)
        #expect(!corruptVerification.isVerified)
        #expect(corruptVerification.retainedBytesUnchanged)
        #expect(corruptVerification.messages.contains {
            $0.localizedCaseInsensitiveContains("ownership ledger")
        })
        #expect(try fingerprintTree(secondArtifact) == secondBefore)
        #expect(try fingerprintTree(firstArtifact).isEmpty == false)
    }

    @Test("retention mutation stays bound to the pinned slot when its pathname is replaced")
    func retentionMutationDoesNotTouchReplacementOccupant() throws {
        let result = try runCID850BoundaryHarness("retention")

        #expect(result.didAttack)
        #expect(result.created)
        #expect(result.verified)
        #expect(result.usable)
        #expect(result.failureKind == nil)
        #expect(result.heldExists)
        #expect(!result.receiptNamesHeldArtifact)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
    }

    @Test("retained failed slots remain bounded and reusable after repeated capture failures")
    func repeatedCaptureFailuresCannotPermanentlyExhaustRetention() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.database.runSQL("BEGIN IMMEDIATE;")
        let sourceDuringFailure = try sqliteSetFingerprint(fixture.databaseURL)

        for _ in 0..<12 {
            let receipt = fixture.service.createManualBackup(database: fixture.database)
            #expect(receipt.failureKind == .capture)
            #expect(receipt.backupURL != nil)
            #expect(!receipt.created)
            #expect(!receipt.verified)
            #expect(!receipt.usable)
            #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceDuringFailure)
            #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).count <= 8)
        }

        try fixture.database.runSQL("ROLLBACK;")
        let sourceBeforeRecovery = try sqliteSetFingerprint(fixture.databaseURL)
        let recovered = fixture.service.createManualBackup(database: fixture.database)

        #expect(recovered.failureKind == nil)
        #expect(recovered.created)
        #expect(recovered.verified)
        #expect(recovered.usable)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBeforeRecovery)
        #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).count == 1)
    }

    @Test("repeated post-publication failures use one bounded quarantine workspace")
    func repeatedPostPublicationFailuresRemainHardBounded() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<3 {
            _ = try fixture.service.createRollingBackup(
                reason: "post-publication-prior-\(index)",
                database: fixture.database
            )
        }
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let priorURLs = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).map(\.url)
        let priorBefore = try packageFingerprints(priorURLs)
        let manager = RepeatingPostPublicationCorruptionFileManager(policyURL: policy)
        let service = DatabaseSafetyService(fileManager: manager)
        var boundedInventory: PolicyInventory?

        for attempt in 0..<24 {
            let receipt = service.createManualBackup(database: fixture.database)
            #expect(receipt.failureKind == .verification)
            #expect(!receipt.created && !receipt.verified && !receipt.usable)
            #expect(try packageFingerprints(priorURLs) == priorBefore)
            let inventory = try policyInventory(policy)
            if attempt == 0 {
                boundedInventory = inventory
            } else {
                #expect(inventory.visiblePackageCount == boundedInventory?.visiblePackageCount)
                #expect(inventory.hiddenPackageCount == boundedInventory?.hiddenPackageCount)
                #expect(inventory.totalEntryCount == boundedInventory?.totalEntryCount)
                #expect(inventory.retainedBytes <= (boundedInventory?.retainedBytes ?? 0) + 4_096)
            }
            #expect(inventory.visiblePackageCount == 3)
            #expect(inventory.hiddenPackageCount == 1)
        }
        #expect(manager.corruptionCount == 24)
    }

    @Test("an uncertain failed-publication marker blocks admission without mutation")
    func uncertainFailedPublicationBlocksBeforeAnotherVisiblePackage() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        try FileManager.default.createDirectory(at: policy, withIntermediateDirectories: true)
        let uncertain = policy.appendingPathComponent(
            "20260717T190000Z-manual-deadbeef-123.ciderbackup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: uncertain, withIntermediateDirectories: false)
        try Data("uncertain occupant".utf8)
            .write(to: uncertain.appendingPathComponent("database.sqlite"))
        try setExtendedAttribute(
            at: uncertain,
            name: "com.cider.cid850.package-owner-v1",
            value: Data("cider-owned-package-v1".utf8)
        )
        let before = try fingerprintTree(uncertain)
        let inventoryBefore = try policyInventory(policy)

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.failureKind == .retentionCapacity)
        #expect(!receipt.created && !receipt.verified && !receipt.usable)
        #expect(try fingerprintTree(uncertain) == before)
        #expect(try policyInventory(policy) == inventoryBefore)
    }

    @Test("concurrent processes rotate within capacity instead of over-admitting or exhausting permanently")
    func concurrentProcessAdmissionRotatesWithinBound() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<7 {
            _ = try fixture.service.createRollingBackup(
                reason: "concurrent-prior-\(index)",
                database: fixture.database
            )
        }
        fixture.database.close()
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        let results = try runConcurrentSharedCreators(databaseURL: fixture.databaseURL, count: 4)

        #expect(results.count == 4)
        #expect(results.allSatisfy { $0.created && $0.verified && $0.usable && $0.failureKind == nil })
        let packages = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
        #expect(packages.count <= 8)
        #expect(packages.filter { $0.verification.isVerified }.count >= 7)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
    }

    @Test("database-parent authority serializes startup against backup after obsolete lock replacement")
    func databaseParentAuthoritySurvivesObsoleteLockReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.database.close()
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let coordination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-flock-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: coordination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: coordination) }
        let ready = coordination.appendingPathComponent("ready.fifo")
        let release = coordination.appendingPathComponent("release.fifo")
        let result = coordination.appendingPathComponent("result.fifo")
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

        let processA = try startSharedCreatorLockProbe(
            databaseURL: fixture.databaseURL,
            role: 1,
            ready: ready,
            release: release,
            result: result
        )
        #expect(try readProbeByte(readyDescriptor) == Character("A"))

        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let obsoleteLock = policy.appendingPathComponent(".cid850-retention.lock")
        let heldObsoleteLock = policy.appendingPathComponent(".cid850-obsolete-lock-held")
        let obsoleteBytes = Data("obsolete pathname authority".utf8)
        try obsoleteBytes.write(to: obsoleteLock)
        try FileManager.default.moveItem(at: obsoleteLock, to: heldObsoleteLock)
        try FileManager.default.createDirectory(at: obsoleteLock, withIntermediateDirectories: false)
        try Data("replacement occupant".utf8).write(to: obsoleteLock.appendingPathComponent("marker"))

        let processB = try startSharedCreatorLockProbe(
            databaseURL: fixture.databaseURL,
            role: 2,
            ready: ready,
            release: release,
            result: result
        )
        #expect(try readProbeByte(resultDescriptor) == Character("0"))
        let first = try finishSharedCreator(processA)
        let second = try finishSharedCreator(processB)

        #expect(first.created && first.verified && first.usable && first.failureKind == nil)
        #expect(second.created && second.verified && second.usable && second.failureKind == nil)
        #expect(try Data(contentsOf: heldObsoleteLock) == obsoleteBytes)
        #expect(try Data(contentsOf: obsoleteLock.appendingPathComponent("marker"))
            == Data("replacement occupant".utf8))
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).count == 2)
    }

    @Test("a crash before visible retirement preserves prior bytes and subsequent rotations stay bounded")
    func crashBeforeRetirementRecoversIntoLongRunBound() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0..<8 {
            _ = try fixture.service.createRollingBackup(
                reason: "crash-prior-\(index)",
                database: fixture.database
            )
        }
        let prior = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL).map(\.url)
        let priorBefore = try packageFingerprints(prior)
        fixture.database.close()
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        try runSharedCreatorCrashingBeforeRetirement(databaseURL: fixture.databaseURL)

        #expect(try packageFingerprints(prior) == priorBefore)
        let afterCrash = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
        #expect(afterCrash.count == 9)
        #expect(afterCrash.allSatisfy { $0.verification.isVerified })
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)

        try fixture.database.open(at: fixture.databaseURL)
        for _ in 0..<24 {
            let receipt = fixture.service.createManualBackup(database: fixture.database)
            #expect(receipt.created && receipt.verified && receipt.usable && receipt.failureKind == nil)
            let retained = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
            #expect(retained.count == 8)
            #expect(retained.allSatisfy { $0.verification.isVerified })
            #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        }
    }

    @Test("a crash after visible publication leaves one diagnosed orphan and blocks every later admission")
    func crashAfterVisiblePublicationBeforeLedgerRegistrationIsHardBounded() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorArtifact = try fixture.service.createRollingBackup(
            reason: "pre-ledger-prior",
            database: fixture.database
        )
        let prior = try observedURL(
            for: priorArtifact,
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        fixture.database.close()
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let policy = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)

        let first = try runSharedCreatorAtPostPublicationCrashBoundary(
            databaseURL: fixture.databaseURL
        )
        #expect(first.status == 88)
        #expect(first.receipt == nil)
        let afterCrash = try policyInventory(policy)
        #expect(afterCrash.visiblePackageCount == 2)
        #expect(afterCrash.hiddenPackageCount == 1)
        #expect(afterCrash.quarantinePackageCount == 0)
        #expect(afterCrash.ledgerEntryCount == 2)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(try fingerprintTree(prior) == priorBefore)

        let listedAfterCrash = fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
        let orphan = try #require(listedAfterCrash.first {
            $0.url.standardizedFileURL != prior.standardizedFileURL
        })
        #expect(orphan.verification.state == .unusable)
        #expect(orphan.verification.retainedBytesUnchanged)
        #expect(orphan.verification.messages.contains {
            $0.localizedCaseInsensitiveContains("ownership ledger")
        })

        let orphanBefore = try fingerprintTree(orphan.url)
        let directVerification = fixture.service.verifyBackup(at: orphan.url)
        #expect(directVerification.state == .unusable)
        #expect(!directVerification.isVerified)
        #expect(directVerification.retainedBytesUnchanged)
        #expect(directVerification.messages.contains {
            $0.localizedCaseInsensitiveContains("ownership ledger")
        })
        let orphanCLI = CiderCLI.databaseBackupVerificationDict(directVerification)
        #expect(orphanCLI["verified"] as? Bool == false)
        #expect(orphanCLI["recoveryEligible"] as? Bool == false)
        #expect(try fingerprintTree(orphan.url) == orphanBefore)

        let absentMaterialization = fixture.root.appendingPathComponent("orphan-materialized.sqlite")
        do {
            _ = try fixture.service.materializeVerifiedBackupDatabase(
                from: orphan.url,
                at: absentMaterialization
            )
            Issue.record("Expected orphan materialization to be rejected")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("ownership ledger"))
        }
        #expect(!FileManager.default.fileExists(atPath: absentMaterialization.path))

        let occupiedMaterialization = fixture.root.appendingPathComponent("occupied-materialized.sqlite")
        let occupiedBytes = Data("materialization sentinel".utf8)
        try occupiedBytes.write(to: occupiedMaterialization)
        do {
            _ = try fixture.service.materializeVerifiedBackupDatabase(
                from: orphan.url,
                at: occupiedMaterialization
            )
            Issue.record("Expected orphan materialization to reject before destination inspection")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("ownership ledger"))
        }
        #expect(try Data(contentsOf: occupiedMaterialization) == occupiedBytes)

        let destinationBeforeRestore = try sqliteSetFingerprint(fixture.databaseURL)
        let sentinelBeforeRestore = try scalarInt(
            databaseURL: fixture.databaseURL,
            sql: "SELECT count(*) FROM schema_version;"
        )
        do {
            _ = try fixture.service.restoreRollingBackup(
                from: orphan.url,
                into: fixture.databaseURL
            )
            Issue.record("Expected orphan restore to be rejected before snapshot or live mutation")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("ownership ledger"))
        }
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == destinationBeforeRestore)
        #expect(try scalarInt(
            databaseURL: fixture.databaseURL,
            sql: "SELECT count(*) FROM schema_version;"
        ) == sentinelBeforeRestore)
        #expect(try fingerprintTree(orphan.url) == orphanBefore)
        #expect(try policyInventory(policy) == afterCrash)

        for _ in 0..<3 {
            let repeated = try runSharedCreatorAtPostPublicationCrashBoundary(
                databaseURL: fixture.databaseURL
            )
            #expect(repeated.status == 0)
            #expect(repeated.receipt?.failureKind == DatabaseSafetyService.BackupFailureKind.retentionCapacity.rawValue)
            #expect(repeated.receipt?.created == false)
            #expect(repeated.receipt?.verified == false)
            #expect(repeated.receipt?.usable == false)
            #expect(try policyInventory(policy) == afterCrash)
            #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
            #expect(try fingerprintTree(prior) == priorBefore)
        }

        try fixture.database.open(at: fixture.databaseURL)
        fixture.service.performStartupSafetyPass(database: fixture.database)
        #expect(try policyInventory(policy) == afterCrash)
        let manual = fixture.service.createManualBackup(database: fixture.database)
        #expect(manual.failureKind == .retentionCapacity)
        #expect(!manual.created && !manual.verified && !manual.usable)
        #expect(manual.backupURL?.standardizedFileURL == orphan.url.standardizedFileURL)
        #expect(try policyInventory(policy) == afterCrash)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(try fingerprintTree(prior) == priorBefore)
        print(
            "CID850_EVIDENCE preledger_orphan_bound visible=\(afterCrash.visiblePackageCount) "
            + "hidden=\(afterCrash.hiddenPackageCount) quarantine=\(afterCrash.quarantinePackageCount) "
            + "ledger=\(afterCrash.ledgerEntryCount) bytes=\(afterCrash.retainedBytes) "
            + "source=\(fingerprintDescription(sourceBefore)) "
            + "prior=\(fingerprintDescription(priorBefore))"
        )
    }

    @Test("an open SQLite handle cannot publish under a replacement policy lineage")
    func liveHandlePolicyLineageDriftFailsTyped() throws {
        let fixture = try Fixture()
        let heldRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-lineage-held-\(UUID().uuidString)", isDirectory: true)
        var restored = false
        defer {
            fixture.database.close()
            if !restored {
                try? FileManager.default.removeItem(at: fixture.root)
                try? FileManager.default.moveItem(at: heldRoot, to: fixture.root)
            }
            fixture.remove()
        }
        try fixture.database.checkpointWal()
        try FileManager.default.moveItem(at: fixture.root, to: heldRoot)
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: false)
        try FileManager.default.copyItem(
            at: heldRoot.appendingPathComponent("cider.db"),
            to: fixture.databaseURL
        )
        let heldSourceBefore = try sqliteSetFingerprint(heldRoot.appendingPathComponent("cider.db"))

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(receipt.failureKind == .sourceUnavailable)
        #expect(receipt.backupURL == nil)
        #expect(try sqliteSetFingerprint(heldRoot.appendingPathComponent("cider.db")) == heldSourceBefore)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.service.rollingBackupsDirectory(for: fixture.databaseURL).path
        ))

        fixture.database.close()
        try FileManager.default.removeItem(at: fixture.root)
        try FileManager.default.moveItem(at: heldRoot, to: fixture.root)
        restored = true
    }

    @Test("a displaced or replaced final package is unusable when the receipt is consumed")
    func receiptIdentityRejectsFinalBoundaryReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let receipt = try fixture.service.createRollingBackupReceipt(
            reason: "receipt-original",
            database: fixture.database
        )
        let originalURL = try observedURL(
            for: try #require(receipt.artifact),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let replacementURL = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "receipt-replacement",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let heldURL = originalURL.deletingLastPathComponent().appendingPathComponent(
            ".receipt-held-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: originalURL, to: heldURL)
        try FileManager.default.copyItem(at: replacementURL, to: originalURL)

        #expect(receipt.backupURL == nil)
        #expect(!receipt.usable)
        #expect(receipt.verified)
        #expect(try fingerprintTree(originalURL) == fingerprintTree(replacementURL))
    }

    @Test("qualified receipt requires exact package membership on every read")
    func receiptRejectsUnexpectedPackageChild() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let receipt = try fixture.service.createRollingBackupReceipt(
            reason: "receipt-membership",
            database: fixture.database
        )
        let package = try observedURL(
            for: try #require(receipt.artifact),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        try Data("unexpected member".utf8)
            .write(to: package.appendingPathComponent("unexpected.bin"))

        #expect(receipt.backupURL == nil)
        #expect(receipt.verified)
        #expect(!receipt.usable)
    }

    @Test("current lineage is enforced while safe raw and v1 artifacts remain recovery-only")
    func currentLineageAndLegacyRecoveryClassification() throws {
        let first = try Fixture()
        defer { first.remove() }
        let second = try Fixture()
        defer { second.remove() }
        let current = try observedURL(
            for: first.service.createRollingBackup(reason: "lineage-source", database: first.database),
            service: first.service,
            databaseURL: first.databaseURL
        )
        let foreign = second.service.rollingBackupsDirectory(for: second.databaseURL)
            .appendingPathComponent("foreign.ciderbackup", isDirectory: true)
        try FileManager.default.createDirectory(
            at: foreign.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: current, to: foreign)
        let foreignBefore = try fingerprintTree(foreign)

        let v1 = current.deletingLastPathComponent()
            .appendingPathComponent("legacy-v1.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: current, to: v1)
        try rewriteManifestAsV1(at: v1)
        let v1Before = try fingerprintTree(v1)
        let raw = current.deletingLastPathComponent().appendingPathComponent("legacy-raw.db")
        try FileManager.default.copyItem(
            at: current.appendingPathComponent("database.sqlite"),
            to: raw
        )
        let rawBefore = sha256(try Data(contentsOf: raw))

        let foreignVerification = second.service.verifyBackup(at: foreign)
        let v1Verification = first.service.verifyBackup(at: v1)
        let rawVerification = first.service.verifyBackup(at: raw)

        #expect(!foreignVerification.isVerified)
        #expect(foreignVerification.state.rawValue == "unusable")
        #expect(v1Verification.state.rawValue == "legacyRecovery")
        #expect(!v1Verification.isVerified)
        #expect(rawVerification.state.rawValue == "legacyRecovery")
        #expect(!rawVerification.isVerified)
        #expect(CiderCLI.databaseBackupVerificationDict(v1Verification)["recoveryEligible"] as? Bool == true)
        #expect(CiderCLI.databaseBackupVerificationDict(rawVerification)["recoveryEligible"] as? Bool == true)
        let v1Materialized = first.root.appendingPathComponent("legacy-v1-materialized.sqlite")
        let rawMaterialized = first.root.appendingPathComponent("legacy-raw-materialized.sqlite")
        _ = try first.service.materializeVerifiedBackupDatabase(from: v1, at: v1Materialized)
        _ = try first.service.materializeVerifiedBackupDatabase(from: raw, at: rawMaterialized)
        #expect(try scalarInt(databaseURL: v1Materialized, sql: "SELECT count(*) FROM schema_version;") == 1)
        #expect(try scalarInt(databaseURL: rawMaterialized, sql: "SELECT count(*) FROM schema_version;") == 1)
        #expect(try fingerprintTree(foreign) == foreignBefore)
        #expect(try fingerprintTree(v1) == v1Before)
        #expect(sha256(try Data(contentsOf: raw)) == rawBefore)
    }

    @Test("restore compares v2 lineage and conservatively associates v1 and raw recovery with destination")
    func restoreRequiresDestinationLineageForCurrentAndLegacyArtifacts() throws {
        let source = try Fixture()
        defer { source.remove() }
        let destination = try Fixture()
        defer { destination.remove() }
        try source.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('source-only', 'Source', '#112233', 'custom', 1, 1);
            """)
        try destination.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('destination-only', 'Destination', '#445566', 'custom', 1, 1);
            """)
        let current = try observedURL(
            for: source.service.createRollingBackup(reason: "cross-v2", database: source.database),
            service: source.service,
            databaseURL: source.databaseURL
        )
        let v1 = current.deletingLastPathComponent()
            .appendingPathComponent("cross-v1.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: current, to: v1)
        try rewriteManifestAsV1(at: v1)
        let raw = current.deletingLastPathComponent().appendingPathComponent("cross-raw.db")
        try FileManager.default.copyItem(
            at: current.appendingPathComponent("database.sqlite"),
            to: raw
        )
        destination.database.close()
        let destinationBefore = try sqliteSetFingerprint(destination.databaseURL)

        for artifact in [current, v1, raw] {
            do {
                _ = try destination.service.restoreRollingBackup(
                    from: artifact,
                    into: destination.databaseURL
                )
                Issue.record("Expected cross-database restore rejection for \(artifact.lastPathComponent)")
            } catch {
                #expect(try sqliteSetFingerprint(destination.databaseURL) == destinationBefore)
            }
        }

        let associatedV1 = source.service.rollingBackupsDirectory(for: source.databaseURL)
            .appendingPathComponent("associated-v1.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: current, to: associatedV1)
        try rewriteManifestAsV1(at: associatedV1)
        let associatedRaw = source.service.rollingBackupsDirectory(for: source.databaseURL)
            .appendingPathComponent("associated-raw.db")
        try FileManager.default.copyItem(
            at: current.appendingPathComponent("database.sqlite"),
            to: associatedRaw
        )
        source.database.close()
        _ = try source.service.restoreRollingBackup(from: current, into: source.databaseURL)
        _ = try source.service.restoreRollingBackup(from: associatedV1, into: source.databaseURL)
        _ = try source.service.restoreRollingBackup(from: associatedRaw, into: source.databaseURL)
        #expect(try scalarInt(
            databaseURL: source.databaseURL,
            sql: "SELECT count(*) FROM labels WHERE id = 'source-only';"
        ) == 1)
    }

    @Test("absent-destination restore is bound to package policy and source filename")
    func absentDestinationRestoreRequiresPolicyAssociationForV2V1AndRaw() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('absent-policy-source', 'Source', '#224466', 'custom', 1, 1);
            """)
        let current = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "absent-policy-v2",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let v1 = current.deletingLastPathComponent()
            .appendingPathComponent("absent-policy-v1.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: current, to: v1)
        try rewriteManifestAsV1(at: v1)
        let raw = current.deletingLastPathComponent()
            .appendingPathComponent("cider.db.legacy.db")
        try FileManager.default.copyItem(
            at: current.appendingPathComponent("database.sqlite"),
            to: raw
        )

        let unrelated = fixture.root.appendingPathComponent("unrelated.db")
        let parentBefore = try fingerprintTree(fixture.root)
        for artifact in [current, v1, raw] {
            do {
                _ = try fixture.service.restoreRollingBackup(from: artifact, into: unrelated)
                Issue.record("Expected absent cross-policy restore rejection for \(artifact.lastPathComponent)")
            } catch {
                #expect(!FileManager.default.fileExists(atPath: unrelated.path))
                #expect(!FileManager.default.fileExists(atPath: unrelated.path + "-wal"))
                #expect(!FileManager.default.fileExists(atPath: unrelated.path + "-shm"))
                #expect(try fingerprintTree(fixture.root) == parentBefore)
            }
        }

        fixture.database.close()
        try removeDisposableSQLiteSet(at: fixture.databaseURL)
        for artifact in [current, v1, raw] {
            let result = try fixture.service.restoreRollingBackup(
                from: artifact,
                into: fixture.databaseURL
            )
            #expect(result.sourceBackupURL?.standardizedFileURL == artifact.standardizedFileURL)
            #expect(try scalarInt(
                databaseURL: fixture.databaseURL,
                sql: "SELECT count(*) FROM labels WHERE id = 'absent-policy-source';"
            ) == 1)
            try removeDisposableSQLiteSet(at: fixture.databaseURL)
        }
    }

    @Test("failure receipt drops a pathname after its retained occupant is replaced")
    func failureReceiptDoesNotAdvertiseReplacementOccupant() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-failure-receipt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        let held = root.appendingPathComponent("held", isDirectory: true)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        try Data("owned".utf8).write(to: retained.appendingPathComponent("value"))
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: .capture,
                state: .failed,
                detail: "retained",
                url: retained
            )
        )
        try FileManager.default.moveItem(at: retained, to: held)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: retained.appendingPathComponent("value"))

        #expect(receipt.backupURL == nil)
        #expect(!receipt.usable)
    }

    @Test("failure receipt drops a pathname after retained child bytes change in place")
    func failureReceiptDoesNotAdvertiseMutatedRetainedBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-failure-child-receipt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let retained = root.appendingPathComponent("retained", isDirectory: true)
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        let child = retained.appendingPathComponent("value")
        try Data("owned".utf8).write(to: child)
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: .capture,
                state: .failed,
                detail: "retained",
                url: retained
            )
        )

        try Data("replacement".utf8).write(to: child)

        #expect(receipt.backupURL == nil)
        #expect(!receipt.usable)
    }

    @Test("receipt snapshot rejects a FIFO before any blocking open")
    func receiptSnapshotRejectsUnwrittenFIFOWithoutBlocking() throws {
        let result = try runCID850ReceiptSpecialHarness("receipt-fifo")

        #expect(result.completedWithoutWriter)
        #expect(result.rejected)
    }

    @Test("receipt snapshot rejects socket, device, symlink, hard-link, and cycle fixtures")
    func receiptSnapshotRejectsSpecialAndCyclicEntries() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent(
            "c8-\(UUID().uuidString.prefix(12))",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)

        let socketURL = root.appendingPathComponent("entry.socket")
        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(socketDescriptor) }
        try bindUnixSocket(socketDescriptor, at: socketURL)

        let symlinkURL = root.appendingPathComponent("entry.symlink")
        #expect(symlink("target", symlinkURL.path) == 0)
        let hardRoot = root.appendingPathComponent("hard", isDirectory: true)
        try FileManager.default.createDirectory(at: hardRoot, withIntermediateDirectories: false)
        let hardOriginal = hardRoot.appendingPathComponent("original")
        let hardCopy = hardRoot.appendingPathComponent("copy")
        try Data("linked".utf8).write(to: hardOriginal)
        #expect(link(hardOriginal.path, hardCopy.path) == 0)
        let cycleRoot = root.appendingPathComponent("cycle", isDirectory: true)
        try FileManager.default.createDirectory(at: cycleRoot, withIntermediateDirectories: false)
        #expect(symlink(".", cycleRoot.appendingPathComponent("again").path) == 0)

        for artifact in [socketURL, URL(fileURLWithPath: "/dev/null"), symlinkURL, hardRoot, cycleRoot] {
            let receipt = DatabaseSafetyService.failedCreationReceipt(
                for: .retainedArtifact(
                    kind: .verification,
                    state: .unusable,
                    detail: "special fixture",
                    url: artifact
                )
            )
            #expect(receipt.backupURL == nil)
            #expect(!receipt.usable)
        }
    }

    @Test("receipt snapshot enforces entry, depth, and byte bounds")
    func receiptSnapshotRejectsOversizedTrees() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cid850-receipt-bounds-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let oversized = root.appendingPathComponent("oversized")
        let descriptor = Darwin.open(
            oversized.path,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        #expect(ftruncate(descriptor, 128 * 1_024 * 1_024 + 1) == 0)
        Darwin.close(descriptor)
        let deep = root.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: false)
        var cursor = deep
        for index in 0..<33 {
            cursor = cursor.appendingPathComponent("d\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: false)
        }
        let wide = root.appendingPathComponent("wide", isDirectory: true)
        try FileManager.default.createDirectory(at: wide, withIntermediateDirectories: false)
        let wideDescriptor = Darwin.open(wide.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard wideDescriptor >= 0 else { throw POSIXError(.EIO) }
        for index in 0..<4_097 {
            let child = Darwin.openat(
                wideDescriptor,
                "e\(index)",
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
            guard child >= 0 else {
                Darwin.close(wideDescriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            Darwin.close(child)
        }
        Darwin.close(wideDescriptor)

        for artifact in [oversized, deep, wide] {
            let receipt = DatabaseSafetyService.failedCreationReceipt(
                for: .retainedArtifact(
                    kind: .verification,
                    state: .unusable,
                    detail: "bounded fixture",
                    url: artifact
                )
            )
            #expect(receipt.backupURL == nil)
        }
    }

    @Test("restore copy pins the verified database occupant through the final source read")
    func restoreCopyRejectsReplacementAtFinalUseBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try observedURL(
            for: fixture.service.createRollingBackup(reason: "restore-source", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        try fixture.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('replacement-only', 'Replacement', '#aabbcc', 'custom', 1, 1);
            """)
        let replacement = try observedURL(
            for: fixture.service.createRollingBackup(reason: "restore-replacement", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let manager = RestoreSourceReplacementFileManager(
            packageURL: original,
            replacementURL: replacement
        )
        let service = DatabaseSafetyService(fileManager: manager)
        let destination = fixture.databaseURL

        let result = try service.restoreRollingBackup(
            from: original,
            into: destination,
            database: fixture.database
        )
        #expect(!manager.didReplaceAtCopy)
        #expect(result.sourceBackupURL?.standardizedFileURL == original.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try scalarInt(
            databaseURL: destination,
            sql: "SELECT count(*) FROM labels WHERE id = 'replacement-only';"
        ) == 0)

        let held = original.deletingLastPathComponent().appendingPathComponent(
            ".restore-receipt-held-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: original, to: held)
        try FileManager.default.copyItem(at: replacement, to: original)
        #expect(result.sourceBackupURL == nil)
    }

    @Test("restore retains the verified package capability through the pre-restore snapshot")
    func restoreRejectsPackageReplacementDuringSnapshot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try observedURL(
            for: fixture.service.createRollingBackup(reason: "snapshot-source", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        try fixture.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('snapshot-replacement', 'Replacement', '#abcdef', 'custom', 1, 1);
            """)
        let replacement = try observedURL(
            for: fixture.service.createRollingBackup(reason: "snapshot-replacement", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let destinationBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let manager = RestoreSnapshotSourceReplacementFileManager(
            sourcePackageURL: original,
            replacementPackageURL: replacement
        )
        let service = DatabaseSafetyService(fileManager: manager)

        do {
            _ = try service.restoreRollingBackup(
                from: original,
                into: fixture.databaseURL,
                database: fixture.database
            )
            Issue.record("Expected replacement during pre-restore snapshot to abort restore")
        } catch {
            #expect(manager.didReplace)
            #expect(try sqliteSetFingerprint(fixture.databaseURL) == destinationBefore)
        }
    }

    @Test("restore cannot delete a replacement installed at the final live mutation boundary")
    func restorePreservesLivePathReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try observedURL(
            for: fixture.service.createRollingBackup(reason: "live-replacement", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let manager = RestoreLivePathReplacementFileManager(databaseURL: fixture.databaseURL)
        let service = DatabaseSafetyService(fileManager: manager)

        do {
            _ = try service.restoreRollingBackup(
                from: backup,
                into: fixture.databaseURL,
                database: fixture.database
            )
            Issue.record("Expected final live-path replacement to abort restore")
        } catch {
            #expect(manager.didReplace)
            #expect(try Data(contentsOf: fixture.databaseURL) == manager.replacementData)
        }
    }

    @Test("a WAL appearing immediately before the database swap is preserved and aborts restore")
    func walAppearanceAtActualSwapSeamRollsBackWithoutDeletion() throws {
        let result = try runCID850RestoreSidecarHarness("restore-sidecar-before-wal")

        #expect(result.didAttack)
        #expect(result.restoreFailed)
        #expect(result.databaseRolledBack)
        #expect(result.unexpectedOccupantPreserved)
        #expect(result.quarantinedOriginalPreserved)
        #expect(!result.reopened)
    }

    @Test("an SHM appearing immediately after the database swap is preserved and rolls back restore")
    func shmAppearanceAtActualSwapSeamRollsBackWithoutDeletion() throws {
        let result = try runCID850RestoreSidecarHarness("restore-sidecar-after-shm")

        #expect(result.didAttack)
        #expect(result.restoreFailed)
        #expect(result.databaseRolledBack)
        #expect(result.unexpectedOccupantPreserved)
        #expect(result.quarantinedOriginalPreserved)
        #expect(!result.reopened)
    }

    @Test("post-swap parent fsync failure rolls back the complete original SQLite set")
    func postSwapParentFsyncFailureRollsBackCoherently() throws {
        let result = try runCID850RestoreFsyncHarness("restore-post-swap-fsync")

        #expect(result.didAttack)
        #expect(result.restoreFailed)
        #expect(result.originalSQLiteSetRestored)
        #expect(result.replacementRetained)
        #expect(result.unexpectedOccupantsPreserved)
        #expect(!result.reopened)
        #expect(result.originalFingerprint == result.finalFingerprint)
        #expect(result.failureMessage.localizedCaseInsensitiveContains(
            "prior coherent database was restored"
        ))
        #expect(result.failureMessage.localizedCaseInsensitiveContains(
            "replacement remains retained"
        ))
        print(
            "CID850_EVIDENCE restore_post_swap_fsync original="
            + fingerprintDescription(result.originalFingerprint)
            + " final=" + fingerprintDescription(result.finalFingerprint)
            + " replacement_retained=\(result.replacementRetained)"
        )
    }

    @Test("rollback parent fsync failure reports restored namespace with uncertain crash durability")
    func rollbackParentFsyncFailureIsTruthful() throws {
        let result = try runCID850RestoreFsyncHarness(
            "restore-post-swap-and-rollback-fsync"
        )

        #expect(result.didAttack)
        #expect(result.restoreFailed)
        #expect(result.originalSQLiteSetRestored)
        #expect(result.replacementRetained)
        #expect(!result.reopened)
        #expect(result.originalFingerprint == result.finalFingerprint)
        #expect(result.failureMessage.localizedCaseInsensitiveContains(
            "rollback parent-directory flush failed"
        ))
        #expect(result.failureMessage.localizedCaseInsensitiveContains(
            "crash durability is uncertain"
        ))
        print(
            "CID850_EVIDENCE restore_rollback_fsync original="
            + fingerprintDescription(result.originalFingerprint)
            + " final=" + fingerprintDescription(result.finalFingerprint)
            + " replacement_retained=\(result.replacementRetained)"
        )
    }

    @Test("qualified materialization rejects package replacement at its final descriptor read")
    func qualifiedUseRejectsReplacementAtFinalRead() throws {
        let result = try runCID850BoundaryHarness("use")

        #expect(result.didAttack)
        #expect(!result.useSucceeded)
        #expect(!result.destinationExists)
        #expect(result.heldExists)
        #expect(result.sourceUnchanged)
        #expect(result.priorUnchanged)
    }

    @Test("verification is byte-exact non-mutating and physically reopenable")
    func verificationDoesNotMutateRetainedPackage() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.database.runSQL("""
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('immutable-proof', 'Immutable', '#123456', 'custom', 1, 1);
            """)

        let receipt = try fixture.service.createRollingBackupReceipt(
            reason: "immutable",
            database: fixture.database
        )
        let artifact = try #require(receipt.artifact)
        let packageURL = try observedURL(
            for: artifact,
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let before = try fingerprintTree(packageURL)
        let first = fixture.service.verifyBackup(at: packageURL)
        let second = fixture.service.verifyBackup(at: packageURL)
        let after = try fingerprintTree(packageURL)

        print("CID850_EVIDENCE physical_reopen \(fingerprintDescription(before))")

        #expect(first.isVerified)
        #expect(receipt.state == .verified)
        #expect(receipt.created)
        #expect(receipt.verified)
        #expect(receipt.usable)
        #expect(second == first)
        #expect(before == after)
        #expect(first.schemaVersion == DatabaseMigrations.latestVersion)
        #expect(first.databaseSHA256?.count == 64)
        #expect(first.manifestSHA256?.count == 64)
        #expect(first.artifactNames == ["database.sqlite", "manifest.json"])
        #expect(!FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("database.sqlite-wal").path))
        #expect(!FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("database.sqlite-shm").path))
        #expect(try scalarInt(
            backupURL: packageURL,
            service: fixture.service,
            sql: "SELECT count(*) FROM labels WHERE id = 'immutable-proof';"
        ) == 1)
        let pathMaterialized = fixture.root.appendingPathComponent("current-path-materialized.sqlite")
        let qualifiedMaterialized = fixture.root.appendingPathComponent("current-qualified-materialized.sqlite")
        _ = try fixture.service.materializeVerifiedBackupDatabase(
            from: packageURL,
            at: pathMaterialized
        )
        _ = try fixture.service.materializeVerifiedBackupDatabase(
            from: artifact,
            at: qualifiedMaterialized
        )
        #expect(try scalarInt(
            databaseURL: pathMaterialized,
            sql: "SELECT count(*) FROM labels WHERE id = 'immutable-proof';"
        ) == 1)
        #expect(try scalarInt(
            databaseURL: qualifiedMaterialized,
            sql: "SELECT count(*) FROM labels WHERE id = 'immutable-proof';"
        ) == 1)
        #expect(try fingerprintTree(packageURL) == before)
        let json = CiderCLI.databaseBackupCreationReceiptToDict(receipt)
        #expect(json["state"] as? String == "verified")
        #expect(json["created"] as? Bool == true)
        #expect(json["verified"] as? Bool == true)
        #expect(json["usable"] as? Bool == true)
    }

    @Test("online capture includes committed WAL and excludes an in-flight writer transaction")
    func coherentWALSnapshotWithConcurrentWriter() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var writer: OpaquePointer?
        #expect(sqlite3_open_v2(
            fixture.databaseURL.path,
            &writer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK)
        let writerHandle = try #require(writer)
        defer { sqlite3_close_v2(writerHandle) }
        try execute(writerHandle, "PRAGMA journal_mode=WAL;")
        try execute(writerHandle, """
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('committed-wal', 'Committed', '#abcdef', 'custom', 1, 1);
            """)
        try execute(writerHandle, "BEGIN IMMEDIATE;")
        try execute(writerHandle, """
            INSERT INTO labels (id, name, color_hex, kind, created_at, updated_at)
            VALUES ('concurrent-writer', 'Pending', '#654321', 'custom', 2, 2);
            """)

        let walURL = URL(fileURLWithPath: fixture.databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: fixture.databaseURL.path + "-shm")
        #expect((try Data(contentsOf: walURL)).count > 0)
        #expect(FileManager.default.fileExists(atPath: shmURL.path))
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        print("CID850_EVIDENCE wal_source \(fingerprintDescription(sourceBefore))")

        let beforeCommitArtifact = try fixture.service.createRollingBackup(
            reason: "writer-in-flight",
            database: fixture.database
        )
        let beforeCommit = try observedURL(
            for: beforeCommitArtifact,
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let sourceAfter = try sqliteSetFingerprint(fixture.databaseURL)
        #expect(sourceAfter == sourceBefore)
        #expect(try scalarInt(
            backupURL: beforeCommit,
            service: fixture.service,
            sql: "SELECT count(*) FROM labels WHERE id = 'concurrent-writer';"
        ) == 0)
        #expect(try scalarInt(
            backupURL: beforeCommit,
            service: fixture.service,
            sql: "SELECT count(*) FROM labels WHERE id = 'committed-wal';"
        ) == 1)

        try execute(writerHandle, "COMMIT;")
        let afterCommitArtifact = try fixture.service.createRollingBackup(
            reason: "writer-committed",
            database: fixture.database
        )
        let afterCommit = try observedURL(
            for: afterCommitArtifact,
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        #expect(try scalarInt(
            backupURL: afterCommit,
            service: fixture.service,
            sql: "SELECT count(*) FROM labels WHERE id = 'concurrent-writer';"
        ) == 1)
        #expect(fixture.service.verifyBackup(at: afterCommit).isVerified)
    }

    @Test("pre-open capture preserves an older healthy source byte-for-byte")
    func olderSchemaPreOpenCaptureIsNonMutating() throws {
        let fixture = try Fixture()
        fixture.database.close()
        try updateSchemaVersion(at: fixture.databaseURL, to: DatabaseMigrations.latestVersion - 1)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        fixture.service.capturePreOpenSnapshotIfNeeded(databaseURL: fixture.databaseURL)

        let sourceAfter = try sqliteSetFingerprint(fixture.databaseURL)
        let snapshot = try #require(
            fixture.service.listPreOpenSnapshots(databaseURL: fixture.databaseURL).first
        )
        #expect(sourceAfter == sourceBefore)
        #expect(snapshot.verification.isVerified)
        #expect(snapshot.verification.schemaVersion == DatabaseMigrations.latestVersion - 1)
        #expect(try scalarInt(
            backupURL: snapshot.url,
            service: fixture.service,
            sql: "SELECT MAX(version) FROM schema_version;"
        ) == DatabaseMigrations.latestVersion - 1)
    }

    @Test("malformed retained package is reported unusable without mutation")
    func malformedPackageIsNotAUsableBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let valid = try observedURL(
            for: fixture.service.createRollingBackup(reason: "valid", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let malformed = valid.deletingLastPathComponent()
            .appendingPathComponent("malformed.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: valid, to: malformed)
        try Data("not sqlite".utf8).write(to: malformed.appendingPathComponent("database.sqlite"))
        let before = try fingerprintTree(malformed)

        let verification = fixture.service.verifyBackup(at: malformed)
        let listed = try #require(
            fixture.service.listRollingBackups(databaseURL: fixture.databaseURL)
                .first { $0.url.standardizedFileURL == malformed.standardizedFileURL }
        )

        #expect(verification.state == .unusable)
        #expect(!verification.isVerified)
        #expect(verification.retainedBytesUnchanged)
        #expect(listed.verification.state == .unusable)
        #expect(try fingerprintTree(malformed) == before)
        #expect(try fingerprintTree(valid) != [:])
    }

    @Test("unhealthy pre-open source is refused without changing its physical set")
    func unhealthyPreOpenSourceIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.database.close()
        try Data("malformed sqlite source".utf8).write(to: fixture.databaseURL)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        fixture.service.capturePreOpenSnapshotIfNeeded(databaseURL: fixture.databaseURL)

        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(fixture.service.listPreOpenSnapshots(databaseURL: fixture.databaseURL).isEmpty)
    }

    @Test("swap and restore during verification never returns verified")
    func swapAndRestoreDuringVerificationFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let packageURL = try observedURL(
            for: fixture.service.createRollingBackup(reason: "swap-original", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let originalFingerprint = try fingerprintTree(packageURL)
        let replacementURL = fixture.root.appendingPathComponent("verification-replacement", isDirectory: true)
        try FileManager.default.copyItem(at: packageURL, to: replacementURL)
        try Data("malformed replacement".utf8).write(
            to: replacementURL.appendingPathComponent("database.sqlite")
        )

        let manager = SwapAndRestoreVerificationFileManager(
            packageURL: packageURL,
            replacementURL: replacementURL
        )
        let service = DatabaseSafetyService(fileManager: manager)
        let verification = service.verifyBackup(at: packageURL)

        #expect(manager.didSwap)
        #expect(manager.didRestore)
        #expect(!verification.isVerified)
        #expect(verification.state == .unusable)
        #expect(try fingerprintTree(packageURL) == originalFingerprint)
    }

    @Test("manual backup reports a real SQLite capture failure after creating its staging artifacts")
    func manualBackupCaptureFailureAfterFirstSideEffectIsTruthful() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorURLs = try createPriorBackups(count: 3, fixture: fixture, prefix: "composed-capture-prior")
        let priorBefore = try packageFingerprints(priorURLs)
        try fixture.database.runSQL("BEGIN IMMEDIATE;")
        defer { try? fixture.database.runSQL("ROLLBACK;") }
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        let receipt = fixture.service.createManualBackup(database: fixture.database)
        let retainedURL = try #require(receipt.backupURL)
        let retainedBeforeReopen = try fingerprintTree(retainedURL)

        #expect(receipt.failureKind == .capture)
        #expect(receipt.state == .failed)
        #expect(retainedURL.lastPathComponent.hasPrefix(".cid850-stage-"))
        #expect(retainedURL.lastPathComponent.hasSuffix(".staging"))
        #expect(receipt.message.contains(retainedURL.path))
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(try directoryEntryNames(at: retainedURL) == ["database.sqlite", "manifest.json"])
        #expect(try packageFingerprints(priorURLs) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(try fingerprintTree(retainedURL) == retainedBeforeReopen)
        for priorURL in priorURLs {
            #expect(fixture.service.verifyBackup(at: priorURL).isVerified)
            #expect(try fingerprintTree(priorURL) == priorBefore[priorURL.standardizedFileURL.path])
        }
        print(
            "CID850_EVIDENCE composed_capture retained=\(retainedURL.path) "
                + "retained_fingerprint=\(fingerprintDescription(retainedBeforeReopen)) "
                + "priors=\(packageFingerprintsDescription(priorBefore)) "
                + "source=\(fingerprintDescription(sourceBefore))"
        )
    }

    @Test("capture failure after staging creation is typed and retains the exact path")
    func captureFailureAfterFirstFilesystemSideEffectIsTruthful() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "capture-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let policyURL = fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        let stagingURL = policyURL.appendingPathComponent(".capture-after-side-effect.staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let stagingDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(stagingDescriptor >= 0)
        defer { if stagingDescriptor >= 0 { Darwin.close(stagingDescriptor) } }
        #expect(Darwin.chmod(stagingURL.path, S_IRUSR | S_IXUSR) == 0)
        defer { _ = Darwin.chmod(stagingURL.path, S_IRWXU) }

        let primitiveError: DatabaseSafetyService.BackupError
        do {
            let descriptor = try DatabaseSafetyService.createExclusivePinnedRegularFile(
                directoryDescriptor: stagingDescriptor,
                name: "database.sqlite"
            )
            Darwin.close(descriptor)
            Issue.record("Expected the real permission boundary to reject staged database creation")
            return
        } catch let error as DatabaseSafetyService.BackupError {
            primitiveError = error
        }
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: .capture,
                state: .failed,
                detail: primitiveError.localizedDescription,
                url: stagingURL
            )
        )

        #expect(primitiveError.kind == .staging)
        #expect(receipt.failureKind == .capture)
        #expect(receipt.backupURL?.standardizedFileURL == stagingURL.standardizedFileURL)
        #expect(receipt.state == .failed)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(receipt.message.contains(stagingURL.path))
        #expect(try directoryEntryNames(at: stagingURL).isEmpty)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print(
            "CID850_EVIDENCE capture_after_side_effect retained=\(stagingURL.path) "
                + "prior=\(fingerprintDescription(priorBefore)) source=\(fingerprintDescription(sourceBefore))"
        )
    }

    @Test("exclusive staged database reservation rejects a symlink without touching its target")
    func stagedSymlinkIsRejectedByProductionPrimitive() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "symlink-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let stagingURL = fixture.root.appendingPathComponent("symlink.staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: stagingURL.appendingPathComponent("database.sqlite"),
            withDestinationURL: prior.appendingPathComponent("database.sqlite")
        )
        let stagingDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(stagingDescriptor >= 0)
        defer { if stagingDescriptor >= 0 { Darwin.close(stagingDescriptor) } }

        do {
            let descriptor = try DatabaseSafetyService.createExclusivePinnedRegularFile(
                directoryDescriptor: stagingDescriptor,
                name: "database.sqlite"
            )
            Darwin.close(descriptor)
            Issue.record("Expected O_EXCL | O_NOFOLLOW staged symlink rejection")
        } catch let error as DatabaseSafetyService.BackupError {
            #expect(error.kind == .staging)
        }

        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: stagingURL.appendingPathComponent("database.sqlite").path) == prior.appendingPathComponent("database.sqlite").path)
        print("CID850_EVIDENCE staged_symlink prior=\(fingerprintDescription(priorBefore))")
    }

    @Test("exclusive staged database reservation rejects a hard link without overwriting it")
    func stagedHardLinkIsRejectedByProductionPrimitive() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "hardlink-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let stagingURL = fixture.root.appendingPathComponent("hardlink.staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let targetURL = prior.appendingPathComponent("database.sqlite")
        let linkedURL = stagingURL.appendingPathComponent("database.sqlite")
        try FileManager.default.linkItem(at: targetURL, to: linkedURL)
        let linkedBefore = sha256(try Data(contentsOf: linkedURL))
        let stagingDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(stagingDescriptor >= 0)
        defer { if stagingDescriptor >= 0 { Darwin.close(stagingDescriptor) } }

        do {
            let descriptor = try DatabaseSafetyService.createExclusivePinnedRegularFile(
                directoryDescriptor: stagingDescriptor,
                name: "database.sqlite"
            )
            Darwin.close(descriptor)
            Issue.record("Expected O_EXCL staged hard-link rejection")
        } catch let error as DatabaseSafetyService.BackupError {
            #expect(error.kind == .staging)
        }

        #expect(sha256(try Data(contentsOf: linkedURL)) == linkedBefore)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print("CID850_EVIDENCE staged_hardlink prior=\(fingerprintDescription(priorBefore))")
    }

    @Test("supplemental descriptor publication collision primitive preserves both artifacts")
    func productionPublicationCollisionReceiptIsTyped() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorURLs = try createPriorBackups(count: 3, fixture: fixture, prefix: "collision-prior")
        let priorBefore = try packageFingerprints(priorURLs)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let publicationRoot = fixture.root.appendingPathComponent("collision-publication", isDirectory: true)
        try FileManager.default.createDirectory(at: publicationRoot, withIntermediateDirectories: false)
        let stagingURL = publicationRoot.appendingPathComponent("source.staging", isDirectory: true)
        let occupiedURL = publicationRoot.appendingPathComponent("occupied.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: priorURLs[0], to: stagingURL)
        try FileManager.default.copyItem(at: priorURLs[1], to: occupiedURL)
        let stagingBefore = try fingerprintTree(stagingURL)
        let occupiedBefore = try fingerprintTree(occupiedURL)
        let sourceDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        let destinationDescriptor = Darwin.open(publicationRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(sourceDescriptor >= 0)
        #expect(destinationDescriptor >= 0)
        defer {
            if sourceDescriptor >= 0 { Darwin.close(sourceDescriptor) }
            if destinationDescriptor >= 0 { Darwin.close(destinationDescriptor) }
        }

        let publicationError: DatabaseSafetyService.BackupError
        do {
            try DatabaseSafetyService.publishPinnedDirectoryAtomically(
                sourceDescriptor: sourceDescriptor,
                destinationDirectoryDescriptor: destinationDescriptor,
                destinationName: occupiedURL.lastPathComponent
            )
            Issue.record("Expected a real existing-destination publication collision")
            return
        } catch let error as DatabaseSafetyService.BackupError {
            publicationError = error
        }
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: publicationError.kind,
                state: publicationError.failureState,
                detail: publicationError.localizedDescription,
                url: stagingURL
            )
        )

        #expect(publicationError.kind == .collision)
        #expect(receipt.failureKind == .collision)
        #expect(receipt.backupURL?.standardizedFileURL == stagingURL.standardizedFileURL)
        #expect(receipt.state == .failed)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(try fingerprintTree(stagingURL) == stagingBefore)
        #expect(try fingerprintTree(occupiedURL) == occupiedBefore)
        #expect(try packageFingerprints(priorURLs) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print(
            "CID850_EVIDENCE publication_collision staging=\(fingerprintDescription(stagingBefore)) "
                + "occupied=\(fingerprintDescription(occupiedBefore))"
        )
    }

    @Test("supplemental descriptor publication permission primitive preserves every prior artifact")
    func productionPublicationPermissionFailurePreservesPriorBackups() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorURLs = try createPriorBackups(count: 3, fixture: fixture, prefix: "publication-prior")
        let priorBefore = try packageFingerprints(priorURLs)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let publicationRoot = fixture.root.appendingPathComponent("denied-publication", isDirectory: true)
        let stagingURL = fixture.root.appendingPathComponent("permission-source.staging", isDirectory: true)
        try FileManager.default.createDirectory(at: publicationRoot, withIntermediateDirectories: false)
        try FileManager.default.copyItem(at: priorURLs[0], to: stagingURL)
        let stagingBefore = try fingerprintTree(stagingURL)
        let sourceDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        let destinationDescriptor = Darwin.open(publicationRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(sourceDescriptor >= 0)
        #expect(destinationDescriptor >= 0)
        defer {
            _ = Darwin.chmod(publicationRoot.path, S_IRWXU)
            if sourceDescriptor >= 0 { Darwin.close(sourceDescriptor) }
            if destinationDescriptor >= 0 { Darwin.close(destinationDescriptor) }
        }
        #expect(Darwin.chmod(publicationRoot.path, S_IRUSR | S_IXUSR) == 0)

        let publicationError: DatabaseSafetyService.BackupError
        do {
            try DatabaseSafetyService.publishPinnedDirectoryAtomically(
                sourceDescriptor: sourceDescriptor,
                destinationDirectoryDescriptor: destinationDescriptor,
                destinationName: "permission-denied.ciderbackup"
            )
            Issue.record("Expected the real directory permission boundary to fail publication")
            return
        } catch let error as DatabaseSafetyService.BackupError {
            publicationError = error
        }
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: publicationError.kind,
                state: publicationError.failureState,
                detail: publicationError.localizedDescription,
                url: stagingURL
            )
        )

        #expect(publicationError.kind == .publication)
        #expect(receipt.failureKind == .publication)
        #expect(receipt.backupURL?.standardizedFileURL == stagingURL.standardizedFileURL)
        #expect(receipt.state == .failed)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(try fingerprintTree(stagingURL) == stagingBefore)
        #expect(try packageFingerprints(priorURLs) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print(
            "CID850_EVIDENCE publication_permission source=\(fingerprintDescription(stagingBefore)) "
                + "prior_count=\(priorBefore.count)"
        )
    }

    @Test("standalone retained verification reports post-publication corruption without mutation")
    func postPublicationCorruptionCannotEmitFalseSuccess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorURLs = try createPriorBackups(count: 3, fixture: fixture, prefix: "verification-prior")
        let priorBefore = try packageFingerprints(priorURLs)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let publishedURL = try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "published-corruption",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        try Data("corrupt after real publication".utf8)
            .write(to: publishedURL.appendingPathComponent("database.sqlite"))
        let corruptBefore = try fingerprintTree(publishedURL)

        let verification = fixture.service.verifyBackup(at: publishedURL)
        let receipt = DatabaseSafetyService.failedCreationReceipt(
            for: .retainedArtifact(
                kind: .verification,
                state: .unusable,
                detail: verification.messages.joined(separator: " | "),
                url: publishedURL
            )
        )

        #expect(verification.state == .unusable)
        #expect(!verification.isVerified)
        #expect(verification.retainedBytesUnchanged)
        #expect(receipt.failureKind == .verification)
        #expect(receipt.backupURL?.standardizedFileURL == publishedURL.standardizedFileURL)
        #expect(receipt.state == .unusable)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(receipt.message.contains(publishedURL.path))
        #expect(try fingerprintTree(publishedURL) == corruptBefore)
        #expect(try packageFingerprints(priorURLs) == priorBefore)
        for priorURL in priorURLs {
            #expect(fixture.service.verifyBackup(at: priorURL).isVerified)
            #expect(try fingerprintTree(priorURL) == priorBefore[priorURL.standardizedFileURL.path])
        }
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print("CID850_EVIDENCE post_publication_corruption \(fingerprintDescription(corruptBefore))")
    }

    @Test("manual backup fails closed when the descriptor-published package is corrupted before retained verification")
    func manualBackupRejectsPostPublicationCorruption() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorURLs = try createPriorBackups(count: 3, fixture: fixture, prefix: "composed-verification-prior")
        let priorBefore = try packageFingerprints(priorURLs)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let manager = PostPublicationCorruptionFileManager(
            policyURL: fixture.service.rollingBackupsDirectory(for: fixture.databaseURL)
        )
        let service = DatabaseSafetyService(fileManager: manager)

        let receipt = service.createManualBackup(database: fixture.database)
        let publishedURL = try #require(manager.publishedURL)
        let retainedURL = try #require(receipt.backupURL)
        let retainedAfter = try fingerprintTree(retainedURL)

        #expect(manager.didCorrupt)
        #expect(receipt.failureKind == .verification)
        #expect(receipt.state == .unusable)
        #expect(retainedURL.lastPathComponent == ".cid850-failed-publication.staging")
        #expect(!FileManager.default.fileExists(atPath: publishedURL.path))
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(receipt.message.contains(retainedURL.path))
        #expect(try packageFingerprints(priorURLs) == priorBefore)
        for priorURL in priorURLs {
            #expect(fixture.service.verifyBackup(at: priorURL).isVerified)
            #expect(try fingerprintTree(priorURL) == priorBefore[priorURL.standardizedFileURL.path])
        }
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        #expect(retainedAfter == manager.corruptFingerprint)
        print(
            "CID850_EVIDENCE composed_verification_failure retained=\(fingerprintDescription(retainedAfter)) "
                + "priors=\(packageFingerprintsDescription(priorBefore)) "
                + "source=\(fingerprintDescription(sourceBefore)) reopen=unusable"
        )
    }

    @Test("incomplete published package is unusable and byte-exact under verification")
    func incompletePublishedPackageFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "incomplete-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let incompleteURL = prior.deletingLastPathComponent()
            .appendingPathComponent("incomplete.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: prior, to: incompleteURL)
        try FileManager.default.removeItem(at: incompleteURL.appendingPathComponent("manifest.json"))
        let incompleteBefore = try fingerprintTree(incompleteURL)

        let verification = fixture.service.verifyBackup(at: incompleteURL)

        #expect(verification.state == .unusable)
        #expect(!verification.isVerified)
        #expect(verification.artifactNames == ["database.sqlite"])
        #expect(try fingerprintTree(incompleteURL) == incompleteBefore)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print("CID850_EVIDENCE incomplete_package \(fingerprintDescription(incompleteBefore))")
    }

    @Test("unreadable published database is unusable and unchanged after permission recovery")
    func unreadablePublishedPackageFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "unreadable-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let unreadableURL = prior.deletingLastPathComponent()
            .appendingPathComponent("unreadable.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: prior, to: unreadableURL)
        let databaseURL = unreadableURL.appendingPathComponent("database.sqlite")
        let unreadableBefore = try fingerprintTree(unreadableURL)
        #expect(Darwin.chmod(databaseURL.path, 0) == 0)
        let verification = fixture.service.verifyBackup(at: unreadableURL)
        #expect(Darwin.chmod(databaseURL.path, S_IRUSR | S_IWUSR) == 0)

        #expect(verification.state == .unusable)
        #expect(!verification.isVerified)
        #expect(try fingerprintTree(unreadableURL) == unreadableBefore)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print("CID850_EVIDENCE unreadable_package \(fingerprintDescription(unreadableBefore))")
    }

    @Test("malformed manifest verification is unusable without changing package or source")
    func malformedManifestFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "manifest-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)
        let malformedURL = prior.deletingLastPathComponent()
            .appendingPathComponent("malformed-manifest.ciderbackup", isDirectory: true)
        try FileManager.default.copyItem(at: prior, to: malformedURL)
        try Data("{not-json".utf8).write(to: malformedURL.appendingPathComponent("manifest.json"))
        let malformedBefore = try fingerprintTree(malformedURL)

        let verification = fixture.service.verifyBackup(at: malformedURL)

        #expect(verification.state == .unusable)
        #expect(!verification.isVerified)
        #expect(verification.retainedBytesUnchanged)
        #expect(try fingerprintTree(malformedURL) == malformedBefore)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
        print("CID850_EVIDENCE malformed_manifest \(fingerprintDescription(malformedBefore))")
    }

    @Test("manual backup reports a closed source as typed failure without mutating its files")
    func closedSourceReceiptIsTruthful() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prior = try observedURL(
            for: fixture.service.createRollingBackup(reason: "closed-source-prior", database: fixture.database),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
        let priorBefore = try fingerprintTree(prior)
        fixture.database.close()
        let sourceBefore = try sqliteSetFingerprint(fixture.databaseURL)

        let receipt = fixture.service.createManualBackup(database: fixture.database)

        #expect(receipt.failureKind == .sourceUnavailable)
        #expect(receipt.state == .failed)
        #expect(receipt.backupURL == nil)
        #expect(!receipt.created)
        #expect(!receipt.verified)
        #expect(!receipt.usable)
        #expect(try fingerprintTree(prior) == priorBefore)
        #expect(try sqliteSetFingerprint(fixture.databaseURL) == sourceBefore)
    }

    @Test("all typed production failure receipts are incapable of success")
    func failureReceiptCompositionNeverClaimsSuccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid850-receipts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let cases: [(DatabaseSafetyService.BackupFailureKind, DatabaseSafetyService.BackupVerificationState)] = [
            (.sourceUnavailable, .failed),
            (.staging, .failed),
            (.capture, .failed),
            (.verification, .unusable),
            (.collision, .failed),
            (.publication, .failed),
        ]

        for (kind, state) in cases {
            let retainedURL = root.appendingPathComponent("\(kind.rawValue).retained", isDirectory: true)
            try FileManager.default.createDirectory(at: retainedURL, withIntermediateDirectories: false)
            try Data(kind.rawValue.utf8).write(to: retainedURL.appendingPathComponent("evidence.bin"))
            let retainedBefore = try fingerprintTree(retainedURL)
            let receipt = DatabaseSafetyService.failedCreationReceipt(
                for: .retainedArtifact(
                    kind: kind,
                    state: state,
                    detail: "deterministic \(kind.rawValue) failure",
                    url: retainedURL
                )
            )

            #expect(receipt.failureKind == kind)
            #expect(receipt.state == state)
            #expect(receipt.backupURL?.standardizedFileURL == retainedURL.standardizedFileURL)
            #expect(!receipt.created)
            #expect(!receipt.verified)
            #expect(!receipt.usable)
            #expect(receipt.message.contains(retainedURL.path))
            #expect(try fingerprintTree(retainedURL) == retainedBefore)
        }
    }

}

private final class DescriptorRelativeStagingSwapFileManager: FileManager, @unchecked Sendable {
    private let expectedPolicyURL: URL
    private(set) var policyURL: URL?
    private(set) var heldPolicyURL: URL?
    private(set) var stagingName: String?
    private(set) var replacementBeforeCreation: [String: String]?
    private(set) var didSwap = false
    private(set) var usedRawStagingCreation = false

    init(policyURL: URL) {
        expectedPolicyURL = policyURL
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        guard url.lastPathComponent.hasSuffix(".staging"), !didSwap else {
            try super.createDirectory(
                at: url,
                withIntermediateDirectories: createIntermediates,
                attributes: attributes
            )
            return
        }
        usedRawStagingCreation = true
        try installPolicyReplacement(forStagingURL: url)
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if url.lastPathComponent.hasSuffix(".staging"), !didSwap {
            try installPolicyReplacement(forStagingURL: url)
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }

    private func installPolicyReplacement(forStagingURL stagingURL: URL) throws {
        let policy = stagingURL.deletingLastPathComponent()
        let held = policy.deletingLastPathComponent().appendingPathComponent(
            ".\(UUID().uuidString).descriptor-policy-held",
            isDirectory: true
        )
        try super.moveItem(at: policy, to: held)
        try super.createDirectory(at: policy, withIntermediateDirectories: false)
        try Data("unowned replacement policy marker".utf8)
            .write(to: policy.appendingPathComponent("replacement-policy.bin"))
        policyURL = policy
        heldPolicyURL = held
        stagingName = stagingURL.lastPathComponent
        replacementBeforeCreation = try fingerprintTree(policy)
        didSwap = true
    }
}

private final class StagingIdentityDriftFileManager: FileManager, @unchecked Sendable {
    private let policyURL: URL
    private(set) var heldStagingURL: URL?
    private(set) var originalBeforeMove: [String: String]?
    private(set) var didMove = false

    init(policyURL: URL) {
        self.policyURL = policyURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didMove,
           url.deletingLastPathComponent().standardizedFileURL == policyURL.standardizedFileURL,
           url.lastPathComponent.hasSuffix(".staging") {
            let held = policyURL.appendingPathComponent(
                ".\(UUID().uuidString).staging-identity-retained",
                isDirectory: true
            )
            originalBeforeMove = try fingerprintTree(url)
            try super.moveItem(at: url, to: held)
            heldStagingURL = held
            didMove = true
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class ComposedPublicationCollisionFileManager: FileManager, @unchecked Sendable {
    private let policyURL: URL
    private(set) var stagingURL: URL?
    private(set) var occupiedURL: URL?
    private(set) var stagingBeforeCollision: [String: String]?
    private(set) var occupiedBeforeCollision: [String: String]?
    private(set) var didOccupyDestination = false

    init(policyURL: URL) {
        self.policyURL = policyURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didOccupyDestination,
           url.deletingLastPathComponent().standardizedFileURL == policyURL.standardizedFileURL,
           url.lastPathComponent.hasSuffix(".staging") {
            let occupied = finalURL(forStagingURL: url)
            try super.createDirectory(at: occupied, withIntermediateDirectories: false)
            try Data("occupied descriptor-publication destination".utf8)
                .write(to: occupied.appendingPathComponent("occupied.bin"))
            stagingURL = url
            occupiedURL = occupied
            stagingBeforeCollision = try fingerprintTree(url)
            occupiedBeforeCollision = try fingerprintTree(occupied)
            didOccupyDestination = true
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class ComposedPublicationPermissionFileManager: FileManager, @unchecked Sendable {
    private let policyURL: URL
    private(set) var stagingURL: URL?
    private(set) var stagingBeforePermissionChange: [String: String]?
    private(set) var didRemoveWritePermission = false

    init(policyURL: URL) {
        self.policyURL = policyURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didRemoveWritePermission,
           url.deletingLastPathComponent().standardizedFileURL == policyURL.standardizedFileURL,
           url.lastPathComponent.hasSuffix(".staging") {
            stagingURL = url
            stagingBeforePermissionChange = try fingerprintTree(url)
            guard Darwin.chmod(policyURL.path, S_IRUSR | S_IXUSR) == 0 else {
                throw CocoaError(.fileWriteNoPermission)
            }
            didRemoveWritePermission = true
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class SwapAndRestoreVerificationFileManager: FileManager, @unchecked Sendable {
    private let packageURL: URL
    private let replacementURL: URL
    private let heldURL: URL
    private var packageReads = 0
    private(set) var didSwap = false
    private(set) var didRestore = false

    init(packageURL: URL, replacementURL: URL) {
        self.packageURL = packageURL
        self.replacementURL = replacementURL
        heldURL = packageURL.deletingLastPathComponent().appendingPathComponent(".verification-held")
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if url.standardizedFileURL == packageURL.standardizedFileURL {
            packageReads += 1
            if packageReads == 1 {
                try super.moveItem(at: packageURL, to: heldURL)
                try super.moveItem(at: replacementURL, to: packageURL)
                didSwap = true
            } else if packageReads == 2, didSwap, !didRestore {
                try super.moveItem(at: packageURL, to: replacementURL)
                try super.moveItem(at: heldURL, to: packageURL)
                didRestore = true
            }
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private func finalURL(forStagingURL stagingURL: URL) -> URL {
    var finalName = stagingURL.lastPathComponent
    if finalName.hasPrefix(".") { finalName.removeFirst() }
    if finalName.hasSuffix(".staging") { finalName.removeLast(".staging".count) }
    return stagingURL.deletingLastPathComponent().appendingPathComponent(finalName, isDirectory: true)
}

private final class PostPublicationCorruptionFileManager: FileManager, @unchecked Sendable {
    private let policyURL: URL
    private(set) var publishedURL: URL?
    private(set) var corruptFingerprint: [String: String]?
    private(set) var didCorrupt = false

    init(policyURL: URL) {
        self.policyURL = policyURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didCorrupt,
           url.deletingLastPathComponent().standardizedFileURL == policyURL.standardizedFileURL,
           url.pathExtension == "ciderbackup",
           url.lastPathComponent.contains("-manual-"),
           !url.lastPathComponent.hasPrefix(".") {
            try Data("corrupt after descriptor publication".utf8)
                .write(to: url.appendingPathComponent("database.sqlite"))
            publishedURL = url
            corruptFingerprint = try fingerprintTree(url)
            didCorrupt = true
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class RepeatingPostPublicationCorruptionFileManager: FileManager, @unchecked Sendable {
    private let policyURL: URL
    private var corruptedNames: Set<String> = []
    private(set) var corruptionCount = 0

    init(policyURL: URL) {
        self.policyURL = policyURL
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if url.deletingLastPathComponent().standardizedFileURL == policyURL.standardizedFileURL,
           url.pathExtension == "ciderbackup",
           url.lastPathComponent.contains("-manual-"),
           !url.lastPathComponent.hasPrefix("."),
           corruptedNames.insert(url.lastPathComponent).inserted {
            try Data("repeatable post-publication corruption".utf8)
                .write(to: url.appendingPathComponent("database.sqlite"))
            corruptionCount += 1
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class RestoreSourceReplacementFileManager: FileManager, @unchecked Sendable {
    private let packageURL: URL
    private let replacementURL: URL
    private let heldURL: URL
    private(set) var didReplaceAtCopy = false

    init(packageURL: URL, replacementURL: URL) {
        self.packageURL = packageURL
        self.replacementURL = replacementURL
        heldURL = packageURL.deletingLastPathComponent().appendingPathComponent(
            ".restore-source-held-\(UUID().uuidString)",
            isDirectory: true
        )
        super.init()
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if !didReplaceAtCopy,
           srcURL.standardizedFileURL == packageURL.appendingPathComponent("database.sqlite").standardizedFileURL {
            try super.moveItem(at: packageURL, to: heldURL)
            try super.copyItem(at: replacementURL, to: packageURL)
            didReplaceAtCopy = true
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

private final class RestoreSnapshotSourceReplacementFileManager: FileManager, @unchecked Sendable {
    private let sourcePackageURL: URL
    private let replacementPackageURL: URL
    private let heldPackageURL: URL
    private(set) var didReplace = false

    init(sourcePackageURL: URL, replacementPackageURL: URL) {
        self.sourcePackageURL = sourcePackageURL
        self.replacementPackageURL = replacementPackageURL
        heldPackageURL = sourcePackageURL.deletingLastPathComponent().appendingPathComponent(
            ".snapshot-source-held-\(UUID().uuidString)",
            isDirectory: true
        )
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if !didReplace,
           url.path.contains("/backups/sqlite/preflight/"),
           url.lastPathComponent.hasPrefix(".cid850-stage-") {
            try super.moveItem(at: sourcePackageURL, to: heldPackageURL)
            try super.copyItem(at: replacementPackageURL, to: sourcePackageURL)
            didReplace = true
        }
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class RestoreLivePathReplacementFileManager: FileManager, @unchecked Sendable {
    private let databaseURL: URL
    private let heldURL: URL
    let replacementData = Data("unowned live replacement".utf8)
    private(set) var didReplace = false

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        heldURL = databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".live-database-held-\(UUID().uuidString)"
        )
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if !didReplace,
           createIntermediates,
           url.standardizedFileURL == databaseURL.deletingLastPathComponent().standardizedFileURL {
            try super.moveItem(at: databaseURL, to: heldURL)
            try replacementData.write(to: databaseURL)
            didReplace = true
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let databaseURL: URL
    let database = CiderDatabase()
    let service = DatabaseSafetyService()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-backup-safety-\(UUID().uuidString)", isDirectory: true)
        databaseURL = root.appendingPathComponent("cider.db")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try database.open(at: databaseURL)
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }
}

private struct CID850BoundaryHarnessResult: Decodable {
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

private struct CID850SharedCreationResult: Decodable {
    let created: Bool
    let verified: Bool
    let usable: Bool
    let failureKind: String?
}

private struct CID850AggregateGrowthResult: Decodable {
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

private struct CID850AggregateCloneRaceResult: Decodable {
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

private struct CID850RestoreSidecarResult: Decodable {
    let didAttack: Bool
    let restoreFailed: Bool
    let databaseRolledBack: Bool
    let unexpectedOccupantPreserved: Bool
    let quarantinedOriginalPreserved: Bool
    let reopened: Bool
}

private struct CID850RestoreFsyncResult: Decodable {
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

private struct CID850CrashPublicationAttempt {
    let status: Int32
    let receipt: CID850SharedCreationResult?
}

private struct CID850ReceiptSpecialResult: Decodable {
    let completedWithoutWriter: Bool
    let rejected: Bool
}

private struct CID850SharedCreatorExecution {
    let process: Process
    let output: Pipe
    let error: Pipe
}

private func runCID850BoundaryHarness(_ boundary: String) throws -> CID850BoundaryHarnessResult {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = [boundary]
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errors = standardError.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "CID850BoundaryHarness",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: String(decoding: errors + output, as: UTF8.self),
            ]
        )
    }
    return try JSONDecoder().decode(CID850BoundaryHarnessResult.self, from: output)
}

private func runCID850AggregateGrowthHarness() throws -> CID850AggregateGrowthResult {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["aggregate-growth"]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw NSError(
            domain: "CID850AggregateGrowthHarness",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: String(decoding: errorData + outputData, as: UTF8.self)]
        )
    }
    return try JSONDecoder().decode(CID850AggregateGrowthResult.self, from: outputData)
}

private func runCID850AggregateCloneRaceHarness(
    _ boundary: String
) throws -> CID850AggregateCloneRaceResult {
    try runCID850Harness(boundary, as: CID850AggregateCloneRaceResult.self)
}

private func runCID850RestoreSidecarHarness(_ boundary: String) throws -> CID850RestoreSidecarResult {
    try runCID850Harness(boundary, as: CID850RestoreSidecarResult.self)
}

private func runCID850RestoreFsyncHarness(_ boundary: String) throws -> CID850RestoreFsyncResult {
    try runCID850Harness(boundary, as: CID850RestoreFsyncResult.self)
}

private func runCID850ReceiptSpecialHarness(_ boundary: String) throws -> CID850ReceiptSpecialResult {
    try runCID850Harness(boundary, as: CID850ReceiptSpecialResult.self)
}

private func runCID850Harness<Result: Decodable>(
    _ boundary: String,
    as type: Result.Type
) throws -> Result {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = [boundary]
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    let errors = standardError.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "CID850BoundaryHarness",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: String(decoding: errors + output, as: UTF8.self)]
        )
    }
    return try JSONDecoder().decode(type, from: output)
}

private func runConcurrentSharedCreators(
    databaseURL: URL,
    count: Int
) throws -> [CID850SharedCreationResult] {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    var executions: [(process: Process, output: Pipe, error: Pipe)] = []
    for _ in 0..<count {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["shared-create", databaseURL.path]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        executions.append((process, output, error))
    }
    return try executions.map { execution in
        execution.process.waitUntilExit()
        let output = execution.output.fileHandleForReading.readDataToEndOfFile()
        let errors = execution.error.fileHandleForReading.readDataToEndOfFile()
        guard execution.process.terminationStatus == 0 else {
            throw NSError(
                domain: "CID850SharedCreation",
                code: Int(execution.process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: errors + output, as: UTF8.self)]
            )
        }
        return try JSONDecoder().decode(CID850SharedCreationResult.self, from: output)
    }
}

private func runSharedCreatorAtPostPublicationCrashBoundary(
    databaseURL: URL
) throws -> CID850CrashPublicationAttempt {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["shared-create-crash-after-publish", databaseURL.path]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus == 88 {
        return CID850CrashPublicationAttempt(status: 88, receipt: nil)
    }
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "CID850PostPublicationCrash",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: String(decoding: errorData + outputData, as: UTF8.self),
            ]
        )
    }
    return CID850CrashPublicationAttempt(
        status: 0,
        receipt: try JSONDecoder().decode(CID850SharedCreationResult.self, from: outputData)
    )
}

private func startSharedCreatorLockProbe(
    databaseURL: URL,
    role: Int,
    ready: URL,
    release: URL,
    result: URL
) throws -> CID850SharedCreatorExecution {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = [
        "shared-create-lock-probe",
        databaseURL.path,
        String(role),
        ready.path,
        release.path,
        result.path,
    ]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    return CID850SharedCreatorExecution(process: process, output: output, error: error)
}

private func finishSharedCreator(
    _ execution: CID850SharedCreatorExecution
) throws -> CID850SharedCreationResult {
    execution.process.waitUntilExit()
    let output = execution.output.fileHandleForReading.readDataToEndOfFile()
    let errors = execution.error.fileHandleForReading.readDataToEndOfFile()
    guard execution.process.terminationStatus == 0 else {
        throw NSError(
            domain: "CID850SharedCreation",
            code: Int(execution.process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: String(decoding: errors + output, as: UTF8.self)]
        )
    }
    return try JSONDecoder().decode(CID850SharedCreationResult.self, from: output)
}

private func readProbeByte(_ descriptor: Int32) throws -> Character {
    var byte: UInt8 = 0
    guard Darwin.read(descriptor, &byte, 1) == 1 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return Character(UnicodeScalar(byte))
}

private func runSharedCreatorCrashingBeforeRetirement(databaseURL: URL) throws {
    let executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/CID850BoundaryHarness")
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["shared-create-crash-before-retire", databaseURL.path]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let errors = error.fileHandleForReading.readDataToEndOfFile()
        + output.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationReason == .exit, process.terminationStatus == 86 else {
        throw NSError(
            domain: "CID850CrashBoundary",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: String(decoding: errors, as: UTF8.self)]
        )
    }
}

private func execute(_ handle: OpaquePointer, _ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    defer { sqlite3_free(message) }
    let result = sqlite3_exec(handle, sql, nil, nil, &message)
    guard result == SQLITE_OK else {
        throw NSError(
            domain: "DatabaseBackupSafetyTests.SQLite",
            code: Int(result),
            userInfo: [NSLocalizedDescriptionKey: message.map { String(cString: $0) } ?? "unknown error"]
        )
    }
}

private func scalarInt(databaseURL: URL, sql: String) throws -> Int {
    var components = URLComponents(url: databaseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    components.scheme = "file"
    components.queryItems = [
        URLQueryItem(name: "mode", value: "ro"),
        URLQueryItem(name: "immutable", value: "1"),
    ]
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(
        components.string ?? databaseURL.path,
        &handle,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
        nil
    )
    guard result == SQLITE_OK, let handle else {
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
private func scalarInt(
    backupURL: URL,
    service: DatabaseSafetyService,
    sql: String
) throws -> Int {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "cid850-materialized-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let databaseURL = directory.appendingPathComponent("database.sqlite")
    try service.materializeVerifiedBackupDatabase(from: backupURL, at: databaseURL)
    return try scalarInt(databaseURL: databaseURL, sql: sql)
}

private func updateSchemaVersion(at databaseURL: URL, to version: Int) throws {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(
        databaseURL.path,
        &handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil
    ) == SQLITE_OK, let handle else {
        sqlite3_close_v2(handle)
        throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_close_v2(handle) }
    try execute(handle, "UPDATE schema_version SET version = \(version);")
}

private func rewriteManifestAsV1(at packageURL: URL) throws {
    let manifestURL = packageURL.appendingPathComponent("manifest.json")
    let data = try Data(contentsOf: manifestURL)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    object["formatVersion"] = 1
    object.removeValue(forKey: "sourceLineageIdentifier")
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        .write(to: manifestURL)
}

private func fingerprintTree(_ root: URL) throws -> [String: String] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
    var result: [String: String] = [:]
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: keys,
        options: []
    ) else { return result }
    let resolvedRootPath = root.resolvingSymlinksInPath().path
    let rootPrefix = resolvedRootPath.hasSuffix("/") ? resolvedRootPath : resolvedRootPath + "/"
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: Set(keys))
        let resolvedPath = url.resolvingSymlinksInPath().path
        let relative = String(resolvedPath.dropFirst(rootPrefix.count))
        if values.isDirectory == true {
            result[relative + "/"] = "directory"
        } else if values.isRegularFile == true {
            result[relative] = sha256(try Data(contentsOf: url, options: [.mappedIfSafe]))
        }
    }
    return result
}

private func sqliteSetFingerprint(_ databaseURL: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for suffix in ["", "-wal", "-shm"] {
        let url = URL(fileURLWithPath: databaseURL.path + suffix)
        if FileManager.default.fileExists(atPath: url.path) {
            result[suffix.isEmpty ? "db" : String(suffix.dropFirst())] = sha256(
                try Data(contentsOf: url, options: [.mappedIfSafe])
            )
        } else {
            result[suffix.isEmpty ? "db" : String(suffix.dropFirst())] = "absent"
        }
    }
    return result
}

private func sqliteSetByteUpperBound(_ databaseURL: URL) throws -> Int64 {
    var total: Int64 = 0
    for suffix in ["", "-wal", "-shm"] {
        let url = URL(fileURLWithPath: databaseURL.path + suffix)
        var value = stat()
        if lstat(url.path, &value) != 0 {
            if suffix != "", errno == ENOENT { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let (sum, overflow) = total.addingReportingOverflow(Int64(value.st_size))
        guard !overflow else { throw CocoaError(.fileReadTooLarge) }
        total = sum
    }
    return total
}

private let retentionLedgerAccountingBytes =
    DatabaseSafetyService.retentionLedgerPayloadBytes
        + DatabaseSafetyService.retentionLedgerOverheadBytes

private func checkedTestSum(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw CocoaError(.fileReadTooLarge) }
    return sum
}

private func incomingPackageByteUpperBound(_ databaseURL: URL) throws -> Int64 {
    var total = try sqliteSetByteUpperBound(databaseURL)
    total = try checkedTestSum(total, DatabaseSafetyService.retentionMaximumManifestBytes)
    for _ in 0..<3 {
        total = try checkedTestSum(
            total,
            DatabaseSafetyService.retentionAccountingNodeOverheadBytes
        )
    }
    return total
}

private func accountedTreeBytes(_ url: URL) throws -> Int64 {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let type = value.st_mode & S_IFMT
    if type == S_IFREG {
        return try checkedTestSum(
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
        total = try checkedTestSum(total, try accountedTreeBytes(child))
    }
    return total
}

private func accountedPolicyBytes(_ policyURL: URL) throws -> Int64 {
    var total = retentionLedgerAccountingBytes
    guard FileManager.default.fileExists(atPath: policyURL.path) else { return total }
    for child in try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: nil,
        options: []
    ) {
        total = try checkedTestSum(total, try accountedTreeBytes(child))
    }
    return total
}

private func aggregateProjectedCapacity(
    policyURL: URL,
    databaseURL: URL,
    reusing workspace: URL? = nil
) throws -> Int64 {
    let retained = try accountedPolicyBytes(policyURL)
    let incoming = try incomingPackageByteUpperBound(databaseURL)
    let reused = try workspace.map(accountedTreeBytes) ?? 0
    let workspaceGrowth = max(0, incoming - reused)
    return try checkedTestSum(
        retained,
        try checkedTestSum(workspaceGrowth, incoming)
    )
}

private struct PolicyInventory: Equatable {
    let visiblePackageCount: Int
    let hiddenPackageCount: Int
    let quarantinePackageCount: Int
    let totalEntryCount: Int
    let retainedBytes: Int64
    let ledgerEntryCount: Int
}

private func policyInventory(_ policyURL: URL) throws -> PolicyInventory {
    let entries = try FileManager.default.contentsOfDirectory(
        at: policyURL,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
        options: []
    )
    var bytes: Int64 = 0
    for entry in entries {
        if let enumerator = FileManager.default.enumerator(
            at: entry,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) {
            for case let child as URL in enumerator {
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
        } else {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
    }
    let authority = policyURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let ledgerData = try extendedAttribute(
        at: authority,
        name: "com.cider.cid850.parent-ownership-ledger-v1"
    )
    let ledgerEntryCount: Int
    if let ledgerData,
       let object = try JSONSerialization.jsonObject(with: ledgerData) as? [String: Any],
       let ledgerEntries = object["entries"] as? [[String: Any]] {
        ledgerEntryCount = ledgerEntries.count
    } else {
        ledgerEntryCount = 0
    }
    return PolicyInventory(
        visiblePackageCount: entries.filter {
            !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "ciderbackup"
        }.count,
        hiddenPackageCount: entries.filter { $0.lastPathComponent.hasPrefix(".cid850-") }.count,
        quarantinePackageCount: entries.filter {
            $0.lastPathComponent == ".cid850-failed-publication.staging"
        }.count,
        totalEntryCount: entries.count,
        retainedBytes: bytes,
        ledgerEntryCount: ledgerEntryCount
    )
}

private func setExtendedAttribute(at url: URL, name: String, value: Data) throws {
    let result = value.withUnsafeBytes { bytes in
        setxattr(url.path, name, bytes.baseAddress, bytes.count, 0, 0)
    }
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func extendedAttribute(at url: URL, name: String) throws -> Data? {
    let size = getxattr(url.path, name, nil, 0, 0, 0)
    if size < 0 {
        if errno == ENOATTR { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var result = Data(count: size)
    let read = result.withUnsafeMutableBytes { bytes in
        getxattr(url.path, name, bytes.baseAddress, bytes.count, 0, 0)
    }
    guard read == size else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return result
}

private func removeDisposableSQLiteSet(at databaseURL: URL) throws {
    for suffix in ["", "-wal", "-shm"] {
        let url = URL(fileURLWithPath: databaseURL.path + suffix)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private func bindUnixSocket(_ descriptor: Int32, at url: URL) throws {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(url.path.utf8CString)
    let pathCapacity = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size
    guard pathBytes.count <= pathCapacity else {
        throw CocoaError(.fileWriteInvalidFileName)
    }
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
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func hiddenEntries(in directoryURL: URL, suffix: String) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: []
    ).filter { $0.lastPathComponent.hasSuffix(suffix) }
}

private func directoryEntryNames(at directoryURL: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: []
    ).map(\.lastPathComponent).sorted()
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func fingerprintDescription(_ fingerprint: [String: String]) -> String {
    fingerprint.keys.sorted().map { "\($0)=\(fingerprint[$0] ?? "missing")" }.joined(separator: ",")
}

@MainActor
private func createPriorBackups(
    count: Int,
    fixture: Fixture,
    prefix: String
) throws -> [URL] {
    try (0..<count).map { index in
        try observedURL(
            for: fixture.service.createRollingBackup(
                reason: "\(prefix)-\(index)",
                database: fixture.database
            ),
            service: fixture.service,
            databaseURL: fixture.databaseURL
        )
    }
}

private func packageFingerprints(_ urls: [URL]) throws -> [String: [String: String]] {
    try Dictionary(uniqueKeysWithValues: urls.map { url in
        (url.standardizedFileURL.path, try fingerprintTree(url))
    })
}

private func packageFingerprintsDescription(_ fingerprints: [String: [String: String]]) -> String {
    fingerprints.keys.sorted().map { path in
        "\(URL(fileURLWithPath: path).lastPathComponent){\(fingerprintDescription(fingerprints[path] ?? [:]))}"
    }.joined(separator: ";")
}

@MainActor
private func observedURL(
    for artifact: DatabaseSafetyService.QualifiedBackupArtifact,
    service: DatabaseSafetyService,
    databaseURL: URL,
    kind: DatabaseSafetyService.SQLiteBackupInfo.Kind = .rolling
) throws -> URL {
    let backups = kind == .rolling
        ? service.listRollingBackups(databaseURL: databaseURL)
        : service.listPreOpenSnapshots(databaseURL: databaseURL)
    return try #require(backups.first { $0.url.lastPathComponent == artifact.packageName }?.url)
}
